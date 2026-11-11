# The hooks check prose with the jobs english and japanese of
# lovaizu/checks, by the lefthook config of the repository that the text
# belongs to. Each repository names lovaizu/checks, its version and its
# languages in its own lefthook config, so the repository decides whether
# the hooks check its prose, in which languages, and by which version. The
# hooks don't check a repository without those jobs. They don't run
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

# Finds the repository that holds directory $1, and the jobs of lovaizu/checks
# that its lefthook config gives the hook pre-commit. Sets $root, $config
# and $jobs. Fails, with a note where it helps, when the hooks can't check
# the text that $2 names.
repo() {
  local dir="$1" what="$2"
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  if ! command -v lefthook &>/dev/null; then
    notes+=("lefthook isn't installed, so $what wasn't checked. Fix: run ./setup.sh of lovaizu/dotfiles.")
    return 1
  fi
  # Without the fetched copy, lefthook has neither job and passes.
  config="$(cd "$root" && lefthook dump --format json 2>/dev/null)" || config='{}'
  jobs="$(jq -r '[.["pre-commit"].jobs[]? | select(.name == "english" or .name == "japanese") | .name] | unique | .[]' <<<"$config")"
  [ -n "$jobs" ] && return 0
  if jq -e 'any(.remotes[]?; .git_url | test("lovaizu/checks"))' <<<"$config" >/dev/null; then
    notes+=("$root names lovaizu/checks in its lefthook config, but it hasn't fetched that version, so $what wasn't checked. Fix: run lefthook install in $root.")
  fi
  return 1
}

# Adds the findings in $out on the text that $1 names to $report, or what
# the check printed to $work/err when it found none.
found() {
  [ -n "$out" ] || out="$(cat "$work/err")"
  # lefthook adds a line of its own with the exit status.
  report+="$1:"$'\n'"$(grep -vE '^exit status [0-9]+$' <<<"$out")"$'\n\n'
}

# Checks file $1, at path $2 from the root of its repository, with each job
# of lovaizu/checks that the repository gives it, by the glob and exclude of
# the job: the language of a file is the case of its repository.
prose_file() {
  local file="$1" path="$2" root config jobs out args=()
  repo "$(dirname "$file")" "$file" || return 0
  while IFS= read -r job; do args+=(--job "$job"); done <<<"$jobs"
  if out="$(cd "$root" && LEFTHOOK_OUTPUT=execution_out lefthook run pre-commit "${args[@]}" --file "$path" --no-auto-install --no-tty --colors off 2>"$work/err")"; then
    return 0
  fi
  # The repository gives this file to none of the jobs.
  grep -q '^Error: failed to run the hook: no job matching' "$work/err" && return 0
  found "$file"
}

# Checks text $2 that Claude Code would keep in the repository that holds
# directory $1, such as a commit message, as the text that $3 names. The
# text has no path in the repository, so no glob gives it a language: a text
# with kana is Japanese, and any other is English. The hooks run prose.sh of
# the version that the repository has fetched, as lefthook would check only
# the paths that the glob of the job takes.
prose_text() {
  local dir="$1" text="$2" what="$3" root config jobs language remote up out
  repo "$dir" "$what" || return 0
  # Hiragana and katakana in UTF-8, U+3040 to U+30FF.
  if LC_ALL=C grep -q $'\xe3[\x81-\x83]' "$text"; then language=japanese; else language=english; fi
  # The repository doesn't check this language.
  grep -qxF "$language" <<<"$jobs" || return 0
  # lefthook keeps each remote in a directory of the name of its repository
  # and its ref.
  remote="$(jq -r '.remotes[]? | select(.git_url | test("lovaizu/checks")) | "\(.git_url | sub("\\.git$"; "") | split("/") | last)-\(.ref)"' <<<"$config" | head -n 1)"
  remote="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)/info/lefthook-remotes/$remote/prose.sh"
  if [ ! -f "$remote" ]; then
    notes+=("$root names lovaizu/checks in its lefthook config, but the hooks didn't find its prose.sh at $remote, so $what wasn't checked. Fix: run lefthook install in $root.")
    return 0
  fi
  # prose.sh reads a path from the root of the repository, and takes the
  # settings of the repository from the directories that the path goes
  # through. A path that goes up to / and down to the text gets those of
  # the root.
  up="${root//[^\/]/}"
  up="${up//\//../}"
  if out="$(cd "$root" && NO_COLOR=1 bash "$remote" "$language" "$up${text#/}" 2>"$work/err")"; then
    return 0
  fi
  found "$what"
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
