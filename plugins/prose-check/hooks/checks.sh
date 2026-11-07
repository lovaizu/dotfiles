# The checks of lovaizu/checks that the hooks run, at a commit pinned here.
# home/run_after_prose-check-checks.sh.tmpl fetches that commit into
# $checks_dir and installs its tools. The hooks then source its lib/lib.sh.
checks_url=https://github.com/lovaizu/checks.git
checks_sha=ba9e6bcd5448fbee5fc68dc55fb56c47c87549d5
checks_dir="${XDG_DATA_HOME:-$HOME/.local/share}/lovaizu-checks/$checks_sha"

# The hooks run jq, and lib.sh runs mise, which is in ~/.local/bin. A Claude
# Code started from a desktop app doesn't always have that directory or the
# tools of mise on PATH, so the hooks add them as the shells do.
PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.config/shell/mise.sh" ] && . "$HOME/.config/shell/mise.sh"

# Sources lib/lib.sh of the checks, or else prints the reason as a message
# to Claude Code and returns 1.
load_checks() {
  if [ ! -f "$checks_dir/lib/lib.sh" ] || ! command -v mise &>/dev/null; then
    echo "{\"systemMessage\": \"prose-check: lovaizu/checks or mise isn't installed, so the prose wasn't checked. Fix: run ./setup.sh of lovaizu/dotfiles.\"}"
    return 1
  fi
  . "$checks_dir/lib/lib.sh"
}
