#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# tmux
if ! command -v tmux &>/dev/null; then
  echo "Installing tmux..."
  sudo apt install -y tmux
fi
ln -sfv "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# alacritty (Windows side)
if ! winget.exe list --id Alacritty.Alacritty &>/dev/null; then
  echo "Installing Alacritty..."
  winget.exe install --id Alacritty.Alacritty
fi
ALACRITTY_DIR="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')/alacritty"
ALACRITTY_WIN_DIR="$(wslpath "$ALACRITTY_DIR")"
mkdir -p "$ALACRITTY_WIN_DIR"
cp -v "$DOTFILES_DIR/alacritty/alacritty.toml" "$ALACRITTY_WIN_DIR/alacritty.toml"

# Windows Terminal (Windows side)
WT_DIR="$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
if [ -d "$WT_DIR" ]; then
  cp -v "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json"
else
  echo "Windows Terminal not found. Skipping."
fi

echo "Done."
