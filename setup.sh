#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backups go to a directory of their own: iTerm2 loads every file in
# DynamicProfiles, so a backup left beside the profile is parsed as a second
# profile with a duplicate Guid.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"

# Set by backup_file to the copy it has just taken, so a caller can point a
# message at it. Empty when there was nothing to back up.
LAST_BACKUP=""

# Copy an existing dst into BACKUP_DIR. Does nothing when dst is not there yet.
# One run backs up several files with the same basename and a timestamp counts
# whole seconds, so the name is made unique by counting up: the message
# backup_then_copy prints promises the user a file at that path.
backup_file() {
  local dst="$1" stem bak count=1
  LAST_BACKUP=""
  if [ -e "$dst" ]; then
    # No directory, no backup, and a backup is what the caller is about to
    # promise the user -- so this is a failure like any other here.
    mkdir -p "$BACKUP_DIR" || return 1
    stem="$BACKUP_DIR/$(basename "$dst").$(date +%Y%m%d%H%M%S)"
    bak="$stem.bak"
    while [ -e "$bak" ]; do
      bak="$stem-$count.bak"
      count=$((count + 1))
    done
    # Non-zero when there is a dst but it cannot be copied -- a directory in
    # its place, a file that cannot be read, a disk that fills up. cp says why
    # on stderr and the caller decides what that means: backup_then_copy hands
    # the non-zero on to whoever called it, where set -e stops the setup for
    # most of them and install_statusline turns it into a warning.
    #
    # A cp that dies partway leaves a half-written file under a name that says
    # it is a whole backup, and nothing else would ever remove it: LAST_BACKUP
    # stays empty, so no message ever names it. Better no backup than a
    # plausible-looking wrong one.
    if ! cp "$dst" "$bak"; then
      rm -f "$bak"
      return 1
    fi
    LAST_BACKUP="$bak"
  fi
}

# One wording for "dst now holds the dotfiles copy", from both paths there.
installed() { echo "Installed $1"; }

# Copy src over dst, backing up an existing dst first. This is the only way
# anything here is deployed, and every managed file goes through it: dotfiles
# is the source of truth, so the whole file is replaced and no file gets a
# method of its own. A setting made on the machine that dotfiles does not
# carry does not survive the next run -- to keep one, put it in dotfiles.
#
# A dst that already holds the dotfiles copy is left untouched. There is
# nothing to write, and the backup is for the one run that moves this machine
# onto dotfiles: a copy of a file that is byte-for-byte the one in the
# repository would be litter that every later run adds to.
#
# Returns non-zero when there is a dst that cannot be backed up or replaced,
# rather than leaving that to set -e inside the function: the caller decides
# what a failure means, and most of them let set -e stop the setup.
backup_then_copy() {
  local src="$1" dst="$2"
  if cmp -s "$src" "$dst"; then
    installed "$dst"
    return 0
  fi
  backup_file "$dst" || return 1
  # Said before the copy rather than after it: a cp that dies partway has
  # already changed dst, and that is exactly when the user needs to be told
  # where the old contents went.
  if [ -n "$LAST_BACKUP" ]; then
    echo "Backed up existing config to $LAST_BACKUP"
  fi
  cp "$src" "$dst" || return 1
  installed "$dst"
}

# herdr (common)
# herdr writes this file itself -- it saves the theme name and the onboarding
# flag back into it -- and the overwrite is what corrects that: dotfiles holds
# the values this machine is meant to have, so a theme picked in herdr's UI
# goes back to the dotfiles one on the next run.
if ! command -v herdr &>/dev/null; then
  echo "herdr not found. Installing its config anyway."
fi
mkdir -p "$HOME/.config/herdr"
backup_then_copy "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml"

# Claude Code (common)
# statusline.sh reads its input with jq and exits 0 without it, so the status
# line looks configured and is nearly empty. Say so rather than let it fail
# quietly.
if ! command -v jq &>/dev/null; then
  echo
  echo "WARNING: jq not found, so the Claude Code status line will be nearly empty."
  echo "  Only the directory and branch survive; the script still exits 0, so the"
  echo "  other sign is jq's \"command not found\" on stderr, once per value read."
  echo "  Fix: brew install jq (mac) / sudo apt install jq (Ubuntu, WSL)"
  echo
fi
# herdr's integration installer writes the hook script, so dotfiles carries
# the hook entry but not the script it points at.
if [ ! -f "$HOME/.claude/hooks/herdr-agent-state.sh" ]; then
  echo
  echo "WARNING: ~/.claude/hooks/herdr-agent-state.sh is missing."
  echo "  The SessionStart hook dotfiles carries points at it, so once the"
  echo "  settings.json below is in place Claude Code runs a script that is"
  echo "  not there, every session."
  echo "  Fix: install the herdr integration (herdr integration ...)."
  echo
fi

# The status line, as a step of its own so that a home directory this machine
# will not let us write is a warning rather than an abort. Not the file's
# habit -- every other deployment here stops the setup. It is the position
# that earns it: this block sits between the herdr config above and the
# settings.json and terminal profile below, so dying here would cost two
# deployments that have nothing to do with the status line. set -e does not
# apply inside a function whose result the caller tests, so each command
# carries its own || return.
#
# 1 means nothing was deployed; 2, the copy is there but chmod on it failed.
# cp gives a dst it creates the source's mode, so a fresh statusline.sh is
# executable already and 2 needs a dst that existed without the bit and a
# chmod that then fails on it -- reachable in testing only with a stub.
install_statusline() {
  local dst="$HOME/.claude/scripts/statusline.sh"
  # Made here rather than earlier because this is the copy that needs it.
  mkdir -p "$HOME/.claude/scripts" || return 1
  backup_then_copy "$DOTFILES_DIR/claude/scripts/statusline.sh" "$dst" \
    || return 1
  chmod +x "$dst" || return 2
}
statusline_status=0
install_statusline || statusline_status=$?
case "$statusline_status" in
  0) ;;
  1)
    echo
    echo "WARNING: the Claude Code status line script was not deployed."
    echo "  The command that failed said why just above. statusline.sh is now"
    echo "  missing, this machine's own copy, or -- if the copy died partway --"
    echo "  a truncated mix of the two that settings.json still feeds to sh."
    echo "  Nothing else here needs it, and the rest of the setup runs below."
    echo "  Fix: make writable whatever that message names (the file, the"
    echo "  directory holding it, or $BACKUP_DIR), then re-run ./setup.sh."
    echo
    ;;
  *)
    echo
    echo "WARNING: chmod on ~/.claude/scripts/statusline.sh failed."
    echo "  The command that failed said why just above. The dotfiles script is"
    echo "  in place; only its mode is in doubt -- a dst cp had to create has the"
    echo "  source's mode already, one that was there keeps its own. Either way"
    echo "  the status line works: settings.json runs it as \`sh \"\$HOME/...\"\`."
    echo "  Fix: nothing, unless you run it by its own path -- then chmod +x it."
    echo
    ;;
esac

# Claude Code writes this file itself (/config, /output-style, the theme
# picker), and it is replaced whole all the same: what was set here and is not
# in dotfiles goes back to the dotfiles value. Everything else Claude Code
# writes -- sessions/, projects/, history.jsonl, plugins/ -- is a different
# file and is not touched.
mkdir -p "$HOME/.claude"
backup_then_copy "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"

# OS-specific setup
case "$(uname -s)" in
  Darwin)
    # iTerm2 (Dynamic Profile)
    ITERM_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    mkdir -p "$ITERM_DIR"
    backup_then_copy "$DOTFILES_DIR/iterm2/herdr.json" "$ITERM_DIR/herdr.json"

    # The key mappings live in the herdr profile, so they only apply to windows
    # opened with it. Warn when it is not the default profile.
    ITERM_PROFILE_GUID="8f7b6c1e-3d2a-4e9b-9c5d-71a2b4e6f038"
    default_guid="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)"
    if [ "$default_guid" != "$ITERM_PROFILE_GUID" ]; then
      echo
      echo "WARNING: the 'herdr' profile is not iTerm2's default profile."
      echo "  The ctrl+cmd key mappings apply only to windows using that profile,"
      echo "  so herdr workspace switching will not work in other windows."
      echo "  Fix: iTerm2 > Settings > Profiles > herdr > Other Actions... > Set as Default,"
      echo "  then open a NEW window (existing windows keep their old profile)."
      echo
    fi

    # HackGen Nerd font (via Homebrew)
    if command -v brew &>/dev/null; then
      if brew list --cask font-hackgen-nerd &>/dev/null; then
        echo "font-hackgen-nerd already installed. Skipping."
      else
        brew install --cask font-hackgen-nerd
      fi
    else
      echo "Homebrew not found. Install the HackGen Nerd font manually (see README)."
    fi
    ;;
  *)
    # Windows Terminal (Windows side). The Windows-side path is found through
    # wslpath and cmd.exe, and both exist only under WSL -- on a Linux box that
    # is not one there is no Windows to deploy to, and asking for wslpath
    # anyway would abort the whole setup here over a file this machine has no
    # place for.
    if ! command -v wslpath &>/dev/null || ! command -v cmd.exe &>/dev/null; then
      echo "Not WSL (no wslpath / cmd.exe). Skipping Windows Terminal."
    else
      # cmd.exe ends the value with a CR. One that fails, or answers with
      # nothing, leaves this empty -- a skip, rather than a wslpath called
      # with no argument.
      appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' || true)"
      if [ -n "$appdata" ]; then
        appdata="$(wslpath "$appdata" 2>/dev/null || true)"
      fi
      WT_DIR="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
      if [ -n "$appdata" ] && [ -d "$WT_DIR" ]; then
        # Windows Terminal writes this file itself, and the overwrite costs it
        # nothing it cannot rebuild: the profiles it generates per WSL distro
        # are this machine's inventory and it generates them again.
        backup_then_copy "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json"
      else
        echo "Windows Terminal not found. Skipping."
      fi
    fi
    ;;
esac

echo "Done."
