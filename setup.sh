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
    mkdir -p "$BACKUP_DIR"
    stem="$BACKUP_DIR/$(basename "$dst").$(date +%Y%m%d%H%M%S)"
    bak="$stem.bak"
    while [ -e "$bak" ]; do
      bak="$stem-$count.bak"
      count=$((count + 1))
    done
    # Non-zero when there is a dst but it cannot be copied -- a directory in
    # its place, a file that cannot be read. cp says why on stderr and the
    # caller decides what that means: merge_config warns and carries on,
    # backup_then_copy does not, so set -e stops the setup there.
    cp "$dst" "$bak" || return 1
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

# Copy src to dst, backing up an existing dst first. For the files only
# dotfiles ever writes: the whole file is ours, so it is replaced wholesale.
backup_then_copy() {
  local src="$1" dst="$2"
  backup_file "$dst"
  announce_backup
  cp "$src" "$dst"
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
  # A backup nobody can use is litter: re-running setup.sh with nothing to
  # change would otherwise leave one identical .bak per run. The copy is
  # still taken up front -- once the merger has written, the old file is
  # gone -- so the useless ones are dropped here instead.
  if [ -n "$LAST_BACKUP" ] && cmp -s "$LAST_BACKUP" "$dst"; then
    rm -f "$LAST_BACKUP"
    LAST_BACKUP=""
  fi
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
