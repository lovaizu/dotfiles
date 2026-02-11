#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# tmux
ln -sfv "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

echo "Done."
