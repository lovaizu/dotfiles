#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# tmux
ln -sfv "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# alacritty (Windows side)
ALACRITTY_DIR="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')/alacritty"
ALACRITTY_WIN_DIR="$(wslpath "$ALACRITTY_DIR")"
mkdir -p "$ALACRITTY_WIN_DIR"
cp -v "$DOTFILES_DIR/alacritty/alacritty.toml" "$ALACRITTY_WIN_DIR/alacritty.toml"

echo "Done."
