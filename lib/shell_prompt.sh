# The user's rc file is theirs, so it is not deployed: it gets one line that
# sources the deployed shell/prompt.sh, added once.
realize_shell_prompt() {
  local prompt_file="$1" rc
  case "$(basename "${SHELL:-}")" in
    zsh) rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)
      warn "The login shell is ${SHELL:-unset}, neither zsh nor bash, so the Starship prompt was not set up." \
        "Fix: source $prompt_file from that shell's startup file by hand."
      return 0
      ;;
  esac
  deploy "$DOTFILES_DIR/shell/prompt.sh" "$prompt_file"
  local line=". \"$prompt_file\""
  if grep -qxF "$line" "$rc" 2>/dev/null; then
    echo "Up to date: $rc"
  elif printf '\n%s\n' "$line" >>"$rc"; then
    echo "Added to $rc: $line"
  else
    record_failure "$rc was not changed." \
      "The shell said why just above." \
      "Until this is fixed, new shells keep their old prompt and tab title." \
      "Fix: once the reason is gone, re-run ./setup.sh."
  fi
}
