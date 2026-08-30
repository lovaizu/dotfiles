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
# whole seconds, so the name is made unique by counting up: the messages
# promise the user a file at that path.
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
    # on stderr and the caller decides what that means: merge_config warns and
    # carries on, backup_then_copy hands the non-zero on to whoever called it,
    # where set -e stops the setup for most of them and install_statusline
    # turns it into a warning.
    #
    # A cp that dies partway leaves a half-written file under a name that says
    # it is a whole backup, and nothing else would ever remove it: LAST_BACKUP
    # stays empty, so drop_identical_backup never sees it and no message ever
    # names it. Better no backup than a plausible-looking wrong one.
    if ! cp "$dst" "$bak"; then
      rm -f "$bak"
      return 1
    fi
    LAST_BACKUP="$bak"
  fi
}

# Say where the backup went. Separate from backup_file because merge_config
# only knows whether the copy was worth keeping once the merge has run.
announce_backup() {
  [ -n "$LAST_BACKUP" ] && echo "Backed up existing config to $LAST_BACKUP"
  return 0
}

# One wording for "dst now holds the dotfiles copy", from every path there.
installed() { echo "Installed $1"; }

# Throw away a backup that turned out to hold exactly what now sits at dst.
# A backup nobody can use is litter: re-running setup.sh with nothing to
# change would otherwise leave one more identical .bak behind every time. The
# copy is still taken up front by backup_file -- once the new content has
# been written the old file is gone, so there is no deciding this afterwards.
drop_identical_backup() {
  if [ -n "$LAST_BACKUP" ] && cmp -s "$LAST_BACKUP" "$1"; then
    rm -f "$LAST_BACKUP"
    LAST_BACKUP=""
  fi
  return 0
}

# Copy src to dst, backing up an existing dst first. For the files only
# dotfiles ever writes: the whole file is ours, so it is replaced wholesale.
#
# Returns non-zero when there is a dst that cannot be copied or replaced,
# rather than leaving that to set -e inside the function: the caller decides
# what a failure means, and most of them let set -e stop the setup.
backup_then_copy() {
  local src="$1" dst="$2" status=0
  backup_file "$dst" || return 1
  cp "$src" "$dst" || status=$?
  # Dropped on the failure path as well: cp that could not start leaves dst
  # exactly as it was, so the copy of it is as useless as one taken before a
  # write that changed nothing. A cp that got partway through does change
  # dst, and that backup survives here and is announced below.
  drop_identical_backup "$dst"
  announce_backup
  [ "$status" -eq 0 ] || return "$status"
  installed "$dst"
}

# Merge src into dst item by item, backing up an existing dst first. For the
# files the application itself also writes: the keys dotfiles has are set to
# the dotfiles value, the keys only dst has are left alone. Both take
# (src, dst) exactly like backup_then_copy.
#
# Only a broken src stops the setup; a broken dst is replaced and a merge that
# cannot be done leaves dst untouched, both with a warning. dst is replaced
# atomically. The merger's docstring has the outcomes in full.
#
# Read-modify-write, so it assumes herdr and Claude Code are not writing the
# same file at the same moment. Run setup.sh with them closed, or expect to
# re-apply a change made in their UI while it ran.
merge_json() {
  merge_config json "$1" "$2"
}

merge_toml() {
  merge_config toml "$1" "$2"
}

# Shared body of merge_json / merge_toml: back up dst, then hand both files to
# lib/merge.py. Backing up here keeps the one backup rule in one place -- the
# merger only ever writes dst.
merge_config() {
  local format="$1" src="$2" dst="$3" status=0
  # `command -v python3` is not the test: macOS ships a /usr/bin/python3 shim
  # that exists until something invokes it. Running it is.
  if ! python3 -c 'pass' &>/dev/null; then
    # Nothing here to discard, so copy: refusing would leave a fresh mac with
    # no configuration at all. An existing file is left alone instead -- the
    # application writes it too, and overwriting it discards what only it has.
    if [ ! -e "$dst" ]; then
      if cp "$src" "$dst"; then
        installed "$dst"
      else
        echo
        echo "WARNING: $dst could not be written."
        echo "  The dotfiles settings for it were not applied."
        echo
      fi
      return 0
    fi
    echo
    echo "WARNING: python3 does not run, so $dst was left as it is."
    echo "  Merging config files needs it (macOS: xcode-select --install)."
    echo "  The dotfiles copy was NOT written over it on purpose: this file is"
    echo "  one the application writes too, and overwriting it would discard"
    echo "  the settings that exist only on this machine."
    echo
    return 0
  fi
  # No backup, no merge: the merger promises the user a copy of whatever it
  # replaces, and it cannot make that promise without this one.
  if ! backup_file "$dst"; then
    echo
    echo "WARNING: $dst could not be copied, so it was left as it is."
    echo "  The dotfiles settings for it were not applied."
    echo
    return 0
  fi
  MERGE_BACKUP="$LAST_BACKUP" python3 "$DOTFILES_DIR/lib/merge.py" \
    "$format" "$src" "$dst" || status=$?
  drop_identical_backup "$dst"
  announce_backup
  # One line per exit code the merger has. Anything else is a broken src,
  # which stops the setup.
  case "$status" in
    0) echo "Merged $(basename "$src") into $dst" ;;
    3) echo "Replaced $dst with $(basename "$src") -- see the warning above" ;;
    4) echo "Left $dst as it is -- see the warning above" ;;
    5) installed "$dst" ;;
    6) echo "Could not install $dst -- see the warning above" ;;
    *) return "$status" ;;
  esac
}

# herdr (common)
if ! command -v herdr &>/dev/null; then
  echo "herdr not found. Copying config anyway."
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
# the hook entry but not the script it points at. Said before the merge, so
# the wording is about the entry dotfiles carries rather than about a
# settings.json that may not have it yet or may be left as it is.
if [ ! -f "$HOME/.claude/hooks/herdr-agent-state.sh" ]; then
  echo
  echo "WARNING: ~/.claude/hooks/herdr-agent-state.sh is missing."
  echo "  The SessionStart hook dotfiles carries points at it, so once the"
  echo "  settings.json below is in place Claude Code runs a script that is"
  echo "  not there, every session -- unless the merge leaves the file as it"
  echo "  is, which it says when it does."
  echo "  Fix: install the herdr integration (herdr integration ...)."
  echo
fi

# The status line, as a step of its own so that a home directory this machine
# will not let us write is a warning rather than an abort. Not the file's
# habit -- the herdr and iTerm2 blocks around it do stop the setup, and the
# merge is the one neighbour that warns and carries on. It is the position
# that earns it: this block sits between the settings.json merge and the
# terminal profile, so dying here would cost two deployments that have
# nothing to do with the status line. set -e does not apply inside a function
# whose result the caller tests, so each command carries its own || return.
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
# picker), so a whole-file copy would discard whatever this machine set that
# dotfiles does not carry.
#
# ~/.claude is made next to the write that needs it rather than left to
# install_statusline above, and quietly, because merge_json names the file it
# could not write anyway.
mkdir -p "$HOME/.claude" 2>/dev/null || true
merge_json "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"

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
    # Windows Terminal (Windows side)
    WT_DIR="$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
    if [ -d "$WT_DIR" ]; then
      backup_then_copy "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json"
    else
      echo "Windows Terminal not found. Skipping."
    fi
    ;;
esac

echo "Done."
