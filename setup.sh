#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# tmux
ln -sf "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"
echo "Linked .tmux.conf"

echo "Done."
