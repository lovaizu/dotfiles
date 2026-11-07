# The hooks check prose with the job prose of lovaizu/checks, through the
# lefthook of the repository that the text belongs to. Each repository names
# lovaizu/checks and its version in its own lefthook config, so the
# repository decides whether the hooks check its prose, and by which
# version. The hooks don't check a repository without that job. They don't run
# `lefthook install` either, as it rewrites the git hooks of the repository.
# When the repository hasn't fetched the version that its config names, the
# hooks say so.

# A Claude Code started from a desktop app doesn't always have ~/.local/bin
# or the tools of mise on PATH, so the hooks add them as the shells do.
PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.config/shell/mise.sh" ] && . "$HOME/.config/shell/mise.sh"

report=""
notes=()
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Runs the job prose of lefthook hook $2 in the repository that holds
# directory $1, on the text that $3 names. The rest are the arguments of
# `lefthook run`. Adds the findings to $report and the reasons for a skipped
# check to $notes.
prose() {
  local dir="$1" hook="$2" what="$3" root config out
  shift 3
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  if ! command -v lefthook &>/dev/null; then
    notes+=("lefthook isn't installed, so $what wasn't checked. Fix: run ./setup.sh of lovaizu/dotfiles.")
    return 0
  fi
  # Without the fetched copy, lefthook has no job prose and passes.
  config="$(cd "$root" && lefthook dump --format json 2>/dev/null)" || config='{}'
  if ! jq -e --arg h "$hook" 'any(.[$h].jobs[]?; .name == "prose")' <<<"$config" >/dev/null; then
    if jq -e 'any(.remotes[]?; .git_url | test("lovaizu/checks"))' <<<"$config" >/dev/null; then
      notes+=("$root names lovaizu/checks in its lefthook config, but it hasn't fetched that version, so $what wasn't checked. Fix: run lefthook install in $root.")
    fi
    return 0
  fi
  if out="$(cd "$root" && LEFTHOOK_OUTPUT=execution_out lefthook run "$hook" --job prose --no-auto-install --no-tty --colors off "$@" 2>"$work/err")"; then
    return 0
  fi
  # The repository leaves this file out of the check.
  grep -q 'no job matching prose' "$work/err" && return 0
  [ -n "$out" ] || out="$(cat "$work/err")"
  # lefthook adds a line of its own with the exit status.
  report+="$what:"$'\n'"$(grep -vE '^exit status [0-9]+$' <<<"$out")"$'\n\n'
}

# Prints the path of file $1 from the root of its repository, as the
# patterns of lefthook, such as exclude, match a file by that path.
in_repo() {
  local dir root
  # git gives the root with no symbolic link in it, so the function reads the
  # file's path the same way.
  dir="$(cd "$(dirname "$1")" && pwd -P)" || return 1
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  echo "${dir#"$root"}/${1##*/}" | sed 's|^/||'
}

# Prints the result to Claude Code as the JSON of a hook. $1 is the event,
# $2 says what the findings are in, and $3 says what Claude Code does next.
answer() {
  local message=""
  [ "${#notes[@]}" -gt 0 ] && message="prose check: ${notes[*]}"
  if [ -n "$report" ]; then
    local reason="The prose check found these problems in $2. $3"$'\n\n'"$report"
    if [ "$1" = PreToolUse ]; then
      jq -n --arg r "$reason" --arg m "$message" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}
        + (if $m != "" then {systemMessage: $m} else {} end)'
    else
      jq -n --arg r "$reason" --arg m "$message" \
        '{decision: "block", reason: $r} + (if $m != "" then {systemMessage: $m} else {} end)'
    fi
  elif [ -n "$message" ]; then
    jq -n --arg m "$message" '{systemMessage: $m}'
  fi
}
