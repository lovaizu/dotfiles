#!/bin/bash
# Stops a Bash command that starts a shell with -c, such as
# `bash -l -c "…"`, and also runs rm. The rm can be in the script string
# or out of it.
# The reason that the hook returns says to run rm as a command of its own.
# Claude Code can't
# check such a command, so it asks the user for approval even in the
# permission mode bypassPermissions, and an agent that runs without the user,
# such as a subagent or an agent in a herdr pane, waits on that prompt. This
# hook runs before that prompt, so the command stops without one.
# shell-scripts.jq finds the script strings, also those inside another
# script string.
set -uo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
# A Claude Code started from a desktop app doesn't always have the tools of
# mise on PATH, so the hook adds them as the shells do.
PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.config/shell/mise.sh" ] && . "$HOME/.config/shell/mise.sh"

has_rm() { grep -qE '(^|[^[:alnum:]_.-])rm([^[:alnum:]_.-]|$)' <<<"$1"; }

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"$input")"
# A command without the word rm isn't parsed.
has_rm "$command" || exit 0
if ! command -v shfmt &>/dev/null; then
  jq -n '{systemMessage: "rm check: shfmt isn'\''t installed, so the hook didn'\''t look for rm with bash -c. Fix: run ./setup.sh of lovaizu/dotfiles."}'
  exit 0
fi

# shfmt parses the command and each script string as Bash does, without
# running any of it.
result="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -c -f "$here/shell-scripts.jq")" || exit 0
rm="$(jq -r .rm <<<"$result")"
scripts=()
mapfile -t scripts < <(jq -r '.scripts[] | @json' <<<"$result")
# Without a script string, Claude Code checks rm itself.
[ "${#scripts[@]}" -gt 0 ] || exit 0
while [ "$rm" != true ] && [ "${#scripts[@]}" -gt 0 ]; do
  script="$(jq -r . <<<"${scripts[0]}")"
  scripts=("${scripts[@]:1}")
  if ! result="$(shfmt --to-json <<<"$script" 2>/dev/null | jq -c -f "$here/shell-scripts.jq")"; then
    # A script string that doesn't parse counts when it has the word rm.
    has_rm "$script" && rm=true
    continue
  fi
  rm="$(jq -r .rm <<<"$result")"
  mapfile -t -O "${#scripts[@]}" scripts < <(jq -r '.scripts[] | @json' <<<"$result")
done
[ "$rm" = true ] || exit 0

reason="This command starts a shell with -c, such as bash -c \"…\", and runs rm. Claude Code can't check what rm deletes in such a command, so it would ask the user for approval, and an agent without the user would wait on it. Run rm as a Bash command of its own, with the exact path, and run the rest without rm. To change a variable for one tool, write VAR=value tool instead of bash -c."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
