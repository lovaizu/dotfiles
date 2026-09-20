#!/bin/bash
set -euo pipefail

# Before the traps: after them, a set -u fatal here would read as exit 0
# (see lib/deploy.sh's cleanup) -- measured against bash 3.2.
: "${HOME:?HOME is not set. Every path this script deploys to is built from it.}"

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$DOTFILES_DIR/lib/deploy.sh"
source "$DOTFILES_DIR/lib/iterm2.sh"
source "$DOTFILES_DIR/lib/hackgen_font.sh"
source "$DOTFILES_DIR/lib/windows_terminal.sh"
source "$DOTFILES_DIR/lib/herdr_integration.sh"
source "$DOTFILES_DIR/lib/ccpm_plugin.sh"

# herdr reads $XDG_CONFIG_HOME when set and never falls back to ~/.config,
# so a hard $HOME/.config here would deploy a file herdr never reads and
# still call the run a success (measured).
set_xdg_base XDG_CONFIG_HOME "${XDG_CONFIG_HOME:-}" "$HOME/.config"
HERDR_CONFIG="$xdg_base/herdr/config.toml"

# Backups get their own tree: iTerm2 reads every file in DynamicProfiles
# except names starting with a dot or ending in a tilde (measured in the
# binary's strings), so a .bak left beside a profile reads as a second
# profile with a duplicate Guid.
set_xdg_base XDG_STATE_HOME "${XDG_STATE_HOME:-}" "$HOME/.local/state"
BACKUP_DIR="$xdg_base/dotfiles-backups"

if [ -n "${XDG_IGNORED:-}" ]; then
  warn "an XDG base directory must be an absolute path, so this run ignored: $XDG_IGNORED" \
    "The specification says a value that does not begin with / is invalid and" \
    "is to be ignored, so the default was used instead. Taking the value" \
    "literally would put the deployed files under whichever directory the run" \
    "was started in, somewhere new each time." \
    "If XDG_CONFIG_HOME is among them, herdr does not ignore it: it resolves" \
    "the relative value against its own working directory, so it may read a" \
    "different config.toml from the one deployed here." \
    "Fix: set it to an absolute path, or unset it, and re-run ./setup.sh."
fi

if ! command -v herdr &>/dev/null; then
  echo "herdr not found. Its config is managed here all the same:"
fi
deploy "$DOTFILES_DIR/herdr/config.toml" "$HERDR_CONFIG"

deploy "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
deploy "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
deploy "$DOTFILES_DIR/claude/scripts/statusline.sh" "$HOME/.claude/scripts/statusline.sh"

case "$(uname -s)" in
  Darwin)
    deploy_iterm2_profile
    install_hackgen_font
    ;;
  *) deploy_windows_terminal ;;
esac

realize_herdr_integration
realize_ccpm_plugin

# Not tidiness: under set -u, bash 3.2 reads "${arr[@]}" on an empty array
# as an unbound variable and kills the script on the spot, and with an EXIT
# trap set the run then ends 0 -- it used to die quietly (measured, bash
# 3.2.57).
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo >&2
  echo "Finished with ${#FAILURES[@]} failure(s):" >&2
  for failed in "${FAILURES[@]}"; do
    echo "  - $failed" >&2
  done
  echo "Each one is explained above. Everything else was deployed or skipped as noted." >&2
  # Set here, not at the top of the block, so a run that dies mid-list is
  # still one that did not reach an end.
  REACHED_END=1
  exit 1
fi

echo "Done."
# An exit 0 the EXIT trap sees without this set is a run that stopped
# somewhere it never meant to (see lib/deploy.sh's traps).
REACHED_END=1
