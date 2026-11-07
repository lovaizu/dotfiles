# Sourced from ~/.zshrc or ~/.bashrc by the line that chezmoi adds there,
# before prompt.sh, and by setup.sh. It puts the tools that mise installs on
# PATH, through their shims, ahead of any other copy. The shims work in a
# script as well, unlike `mise activate`, which needs a prompt.
_mise_shims="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
case ":$PATH:" in
*":$_mise_shims:"*) ;;
*) PATH="$_mise_shims:$PATH" ;;
esac
unset _mise_shims
