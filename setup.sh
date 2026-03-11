#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# tmux
if ! command -v tmux &>/dev/null; then
  echo "Installing tmux..."
  sudo apt install -y tmux
fi
ln -sfv "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# Windows Terminal (Windows side)
WT_DIR="$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
if [ -d "$WT_DIR" ]; then
  cp -v "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json"
else
  echo "Windows Terminal not found. Skipping."
fi

echo "Done."
