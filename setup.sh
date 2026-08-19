#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Copy src to dst, backing up an existing dst first.
backup_then_copy() {
  local src="$1" dst="$2" bak
  if [ -e "$dst" ]; then
    bak="$dst.$(date +%Y%m%d%H%M%S).bak"
    cp "$dst" "$bak"
    echo "Backed up existing config to $bak"
  fi
  cp "$src" "$dst"
  echo "Installed $dst"
}

# herdr
if ! command -v herdr &>/dev/null; then
  echo "herdr not found. Copying config anyway."
fi
mkdir -p "$HOME/.config/herdr"
backup_then_copy "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml"

# Windows Terminal (Windows side)
WT_DIR="$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
if [ -d "$WT_DIR" ]; then
  backup_then_copy "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json"
else
  echo "Windows Terminal not found. Skipping."
fi

echo "Done."
