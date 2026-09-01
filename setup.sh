#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backups go to a directory of their own: iTerm2 loads every file in
# DynamicProfiles, so a backup left beside the profile is parsed as a second
# profile with a duplicate Guid.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"

# What this run could not deploy, one entry per file. A deployment that fails
# is a warning and the setup carries on -- nothing deployed here is needed by
# anything else in this script, and a home directory that will not take one
# file is no reason to skip the ones that would have worked. This list is what
# keeps that from passing for success: the run names every entry at the end and
# exits non-zero.
FAILURES=()

# The temp file deploy is writing, so an interrupt does not leave it behind.
# Empty whenever there is none.
DEPLOY_TMP=""
remove_deploy_tmp() {
  if [ -n "$DEPLOY_TMP" ]; then
    # A dst whose directory has gone makes even rm complain; nothing here is
    # worth a message.
    rm -f "$DEPLOY_TMP" 2>/dev/null || true
    DEPLOY_TMP=""
  fi
}
# INT and TERM exit rather than only cleaning up: a trap that returns leaves
# bash carrying on to the next deployment, so Ctrl-C would stop nothing.
trap remove_deploy_tmp EXIT
trap 'remove_deploy_tmp; exit 130' INT
trap 'remove_deploy_tmp; exit 143' TERM

# Set by backup_file to the copy it has just taken, so a caller can point a
# message at it. Empty when there was nothing to back up.
LAST_BACKUP=""

# Say that something was not deployed and remember it for the summary. The
# detail lines are the caller's, because what to do about it differs; what is
# the same everywhere is that the run goes on and ends non-zero.
record_failure() {
  local what="$1" line
  shift
  FAILURES+=("$what")
  echo
  echo "WARNING: $what"
  for line in "$@"; do
    echo "  $line"
  done
  echo
}

# Copy an existing dst into BACKUP_DIR. Does nothing when dst is not there yet.
# One run backs up several files with the same basename and a timestamp counts
# whole seconds, so the name is made unique by counting up: the message deploy
# prints promises the user a file at that path.
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
    # Non-zero when there is a dst that cannot be copied: a directory in its
    # place, a file that cannot be read, a disk that fills up. cp says why on
    # stderr and deploy turns it into a warning.
    #
    # A cp that dies partway leaves a half-written file under a name that says
    # it is a whole backup, and nothing else would ever remove it. Better no
    # backup than a plausible-looking wrong one.
    if ! cp "$dst" "$bak"; then
      rm -f "$bak"
      return 1
    fi
    LAST_BACKUP="$bak"
  fi
}

# Every managed file is deployed by this one call, and by nothing else.
# dotfiles is the source of truth, so the whole file is replaced: a setting
# made on the machine that dotfiles does not carry does not survive the next
# run -- to keep one, put it in dotfiles. The status line script asks for a
# chmod afterwards, but that is about the mode of a file already deployed, not
# a second way of deploying one.
#
# A dst that already holds the dotfiles copy is left alone. There is nothing to
# write, and a backup of a file that is byte-for-byte the one in the repository
# would be litter that every later run adds to.
#
# The new contents go to a temp file beside dst and are renamed over it. rename
# within a directory is atomic, so a run stopped partway leaves dst holding the
# old file or the new one and never a mix of the two -- worth having for
# settings.json, which Claude Code reads as JSON and a half-written one is not.
# It also settles what to do with the backup: everything that can fail here
# fails before the rename, with dst untouched, so a backup taken a moment
# earlier is a second copy of a file that is still in place and goes again.
# Without that, a dst that cannot be written would leave one more identical
# .bak behind on every run.
#
# What renaming costs: it needs the directory writable rather than the file, so
# a dst whose directory is read-only is a failure here even where writing
# through the existing file would have worked, and a dst that is replaced comes
# out with the repository's mode rather than its own. A dst that is a symlink
# is replaced by the file itself and the link's target is left alone (measured)
# -- the opposite of writing through it, and the safer way round, since the
# target is somewhere this script does not manage. The mode a rewritten dst
# ends up with is the repository's less the umask (measured: under umask 077,
# a 755 statusline.sh lands as 700).
#
# Returns non-zero, having already warned and recorded it, when the file was
# not deployed. Callers add `|| true` so that set -e does not turn the warning
# back into an abort.
deploy() {
  local src="$1" dst="$2" dir
  # cmp -s keeps quiet about a difference but not about a dst it cannot open,
  # and a lone "Is a directory" naming neither the managed file nor what to do
  # about it is worse than no message. One of the commands below runs into the
  # same thing and its complaint arrives with the warning that explains it.
  if cmp -s "$src" "$dst" 2>/dev/null; then
    echo "Up to date: $dst"
    return 0
  fi
  dir="$(dirname "$dst")"
  DEPLOY_TMP="$dir/.$(basename "$dst").dotfiles-tmp.$$"
  if mkdir -p "$dir" && cp "$src" "$DEPLOY_TMP" && backup_file "$dst"; then
    if mv "$DEPLOY_TMP" "$dst"; then
      # The rename took the temp file away, so there is nothing left to clean.
      DEPLOY_TMP=""
      # Announced after the rename, so the run only ever promises a backup of
      # contents that have actually been replaced.
      if [ -n "$LAST_BACKUP" ]; then
        echo "Backed up existing config to $LAST_BACKUP"
      fi
      echo "Installed $dst"
      return 0
    fi
  fi
  remove_deploy_tmp
  # Nothing above reached the rename, so dst is as it was and this backup is a
  # copy of a file that is still there. Keeping it would add one more identical
  # .bak per run for as long as the cause lasts.
  if [ -n "$LAST_BACKUP" ]; then
    rm -f "$LAST_BACKUP"
    LAST_BACKUP=""
  fi
  record_failure "$dst was not deployed." \
    "The command that failed said why just above. The file still holds what" \
    "it held before, and no backup was kept: the copy is renamed into place" \
    "only once it is whole, so a failure here leaves nothing to undo." \
    "The rest of the setup runs below and this run ends non-zero." \
    "Fix: clear whatever that message names -- make the file, the directory" \
    "holding it, or $BACKUP_DIR writable, or move aside" \
    "something standing where the file belongs -- then re-run ./setup.sh."
  return 1
}

# herdr (common)
# herdr writes this file itself -- it saves the theme name and the onboarding
# flag back into it -- and the overwrite is what corrects that: dotfiles holds
# the values this machine is meant to have, so a theme picked in herdr's UI
# goes back to the dotfiles one on the next run.
if ! command -v herdr &>/dev/null; then
  echo "herdr not found. Installing its config anyway."
fi
deploy "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml" || true

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

# Claude Code writes settings.json itself (/config, /output-style, the theme
# picker), and it is replaced whole all the same: what was set here and is not
# in dotfiles goes back to the dotfiles value. Everything else Claude Code
# writes -- sessions/, projects/, history.jsonl, plugins/ -- is a different
# file and is not touched.
deploy "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json" || true

# The status line script. The chmod is the one thing here that outlives the
# copy, and it runs whether or not deploy wrote anything: a file deploy wrote
# comes from cp and is executable already, but a dst that already matched byte
# for byte was not rewritten and keeps whatever mode it had.
STATUSLINE_DST="$HOME/.claude/scripts/statusline.sh"
if deploy "$DOTFILES_DIR/claude/scripts/statusline.sh" "$STATUSLINE_DST"; then
  if ! chmod +x "$STATUSLINE_DST"; then
    echo
    echo "WARNING: chmod +x on the Claude Code status line script failed."
    echo "  chmod said why just above. This is not a failed deployment and is"
    echo "  not counted as one: the dotfiles script is in place and byte-exact,"
    echo "  and the status line works without the bit -- settings.json runs it"
    echo "  as \`sh \"\$HOME/...\"\`, which does not need the file executable."
    echo "  Fix: nothing, unless you run it by its own path -- then chmod +x it."
    echo
  fi
fi

# OS-specific setup
case "$(uname -s)" in
  Darwin)
    # iTerm2 (Dynamic Profile)
    ITERM_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    deploy "$DOTFILES_DIR/iterm2/herdr.json" "$ITERM_DIR/herdr.json" || true

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

    # HackGen Nerd font (via Homebrew). The font is the one optional thing
    # here: it is not a managed file, the README carries a manual install for
    # it, and a machine without brew is already told to use that. So an install
    # that fails is a warning and not a recorded failure -- treating it as one
    # would make a dropped network connection the same kind of event as a home
    # directory that refuses the settings, which it is not.
    if command -v brew &>/dev/null; then
      if brew list --cask font-hackgen-nerd &>/dev/null; then
        echo "font-hackgen-nerd already installed. Skipping."
      elif ! brew install --cask font-hackgen-nerd; then
        echo
        echo "WARNING: brew install --cask font-hackgen-nerd failed."
        echo "  brew said why just above. Nothing else here depends on it; the"
        echo "  iTerm2 profile names HackGen and macOS falls back to another"
        echo "  monospace font until it is installed."
        echo "  Fix: re-run brew install --cask font-hackgen-nerd once the"
        echo "  reason is gone, or install the font by hand (see README)."
        echo
      fi
    else
      echo "Homebrew not found. Install the HackGen Nerd font manually (see README)."
    fi
    ;;
  *)
    # Windows Terminal (Windows side). The Windows-side path is found through
    # wslpath and cmd.exe, and both exist only under WSL -- on a Linux box that
    # is not one there is no Windows to deploy to, and asking for wslpath
    # anyway would end the run non-zero over a file this machine has no place
    # for.
    if ! command -v wslpath &>/dev/null || ! command -v cmd.exe &>/dev/null; then
      echo "Not WSL (no wslpath / cmd.exe). Skipping Windows Terminal."
    else
      # cmd.exe ends the value with a CR. Its stderr is kept rather than
      # dropped: when this comes back empty, that message is the only account
      # of why.
      appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' | tr -d '\r' || true)"
      # The guard is what keeps wslpath from being handed the empty string that
      # a cmd.exe answering with nothing leaves here. wslpath keeps its stderr
      # for the same reason cmd.exe does.
      if [ -n "$appdata" ]; then
        appdata="$(wslpath "$appdata" || true)"
      fi
      if [ -z "$appdata" ]; then
        # Not the same thing as Windows Terminal being absent, and told apart
        # from it: both tools answered to command -v, so this is WSL and there
        # is a Windows side -- what could not be found is where it keeps the
        # user's AppData. Windows Terminal may well be installed, so a managed
        # file was missed and this counts like any other miss.
        record_failure "Windows Terminal's settings.json was not deployed." \
          "%LOCALAPPDATA% would not resolve, so where Windows Terminal keeps" \
          "its settings is unknown. Whatever cmd.exe or wslpath said about it" \
          "is just above. This says nothing about whether Windows Terminal is" \
          "installed -- only that the Windows side of this machine could not" \
          "be located from here, and that nothing was written anywhere." \
          "Fix: check that \`cmd.exe /c 'echo %LOCALAPPDATA%'\` answers from" \
          "this shell (a cwd on a UNC path is the usual reason it does not)."
      else
        WT_DIR="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
        if [ -d "$WT_DIR" ]; then
          # Windows Terminal writes this file itself, and the overwrite costs
          # it nothing it cannot rebuild: the profiles it generates per WSL
          # distro are this machine's inventory and it generates them again.
          deploy "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json" || true
        else
          # The Windows side was found and Windows Terminal is not on it. There
          # is nothing to deploy to, so this is a skip and not a failure.
          echo "Windows Terminal not installed ($WT_DIR does not exist). Skipping."
        fi
      fi
    fi
    ;;
esac

if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo
  echo "Finished with ${#FAILURES[@]} failure(s):"
  for failed in "${FAILURES[@]}"; do
    echo "  - $failed"
  done
  echo "Each one is explained above. Everything else here was deployed."
  exit 1
fi

echo "Done."
