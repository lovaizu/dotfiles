# Every run_ script includes this, so a reason reads the same whichever
# script it comes from. setup.sh gives DOTFILES_WARNINGS, and prints the
# file again once chezmoi ends.
warn() {
  local block="WARNING: $1" line
  shift
  for line in "$@"; do
    block="$block
  $line"
  done
  printf '\n%s\n\n' "$block" >&2
  if [ -n "${DOTFILES_WARNINGS:-}" ]; then
    printf '%s\n\n' "$block" >>"$DOTFILES_WARNINGS" || true
  fi
  return 0
}
