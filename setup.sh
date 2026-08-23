#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backups go to a directory of their own: iTerm2 loads every file in
# DynamicProfiles, so a backup left beside the profile is parsed as a second
# profile with a duplicate Guid.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"

# Copy src to dst, backing up an existing dst first.
backup_then_copy() {
  local src="$1" dst="$2" bak
  if [ -e "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    bak="$BACKUP_DIR/$(basename "$dst").$(date +%Y%m%d%H%M%S).bak"
    cp "$dst" "$bak"
    echo "Backed up existing config to $bak"
  fi
  cp "$src" "$dst"
  echo "Installed $dst"
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
