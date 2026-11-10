# Sourced from ~/.zshrc or ~/.bashrc by a line that chezmoi adds there, and
# from the startup command of sbx/spec.yaml, so both use this one path. The
# startup command writes the notice when it can't update the dotfiles, and
# deletes it when an update succeeds. Until then, each new shell prints it.
dotfiles_update_notice="$HOME/.local/state/dotfiles/update-failed"
case $- in
*i*)
  if [ -f "$dotfiles_update_notice" ]; then
    cat "$dotfiles_update_notice" >&2
  fi
  ;;
esac
