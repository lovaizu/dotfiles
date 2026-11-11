#!/bin/bash
# Stops a Bash command that Claude Code would hold for the user's approval
# with its check for rm, even in the permission mode bypassPermissions.
# Subagents and the agents in herdr panes run without the user, so they
# wait on that prompt. This hook runs before the prompt, so the command
# stops without one, and the reason that the hook returns says how to write
# the command instead. The hook stops these commands:
#
# - A command that starts a shell with -c, such as `bash -l -c "…"`, and
#   also runs rm. The rm can be in the script string or out of it. The
#   prompt says that Claude Code can't check the script.
# - A command with a ${…} expansion that has a { with no } to match it,
#   such as ${y:-{\}}, even without rm. The prompt says that Bash might
#   read the command in a different way from Claude Code.
#
# command.jq finds these parts. The hook also reads the script strings
# inside another script string.
set -uo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
# A Claude Code started from a desktop app doesn't always have the tools of
# mise on PATH, so the hook adds them as the shells do.
PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.config/shell/mise.sh" ] && . "$HOME/.config/shell/mise.sh"

has_rm() { grep -qE '(^|[^[:alnum:]_.-])rm([^[:alnum:]_.-]|$)' <<<"$1"; }
deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"$input")"
# A command without rm or ${ isn't parsed.
has_rm "$command" || [[ "$command" == *'${'* ]] || exit 0
if ! command -v shfmt &>/dev/null; then
  jq -n '{systemMessage: "rm check: shfmt isn'\''t installed, so the hook didn'\''t look for the commands that Claude Code holds for approval. Fix: run ./setup.sh of lovaizu/dotfiles."}'
  exit 0
fi

# shfmt parses the command and each script string as Bash does, without
# running any of it.
result="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -c -f "$here/command.jq")" || exit 0

# shfmt gives byte offsets, so the C locale makes ${command:…} count bytes.
while IFS=$'\t' read -r end need; do
  [ -n "$end" ] || continue
  closing="$(LC_ALL=C; printf '%s' "${command:end:need}")"
  [ "$closing" = "$(printf '}%.0s' $(seq "$need"))" ] && continue
  deny "This command has a \${…} expansion with a { that has no } to match it, such as \${y:-{\\}}. Claude Code reads such an expansion in a different way from Bash, so it would ask the user for approval, and an agent without the user would wait on it. Put the { in quotes, such as \${y:-\"{}\"}, or give the value in a variable of its own."
done < <(jq -r '.braces[] | "\(.end)\t\(.need)"' <<<"$result")

rm="$(jq -r .rm <<<"$result")"
scripts=()
mapfile -t scripts < <(jq -r '.scripts[] | @json' <<<"$result")
# Without a script string, Claude Code checks rm itself.
[ "${#scripts[@]}" -gt 0 ] || exit 0
while [ "$rm" != true ] && [ "${#scripts[@]}" -gt 0 ]; do
  script="$(jq -r . <<<"${scripts[0]}")"
  scripts=("${scripts[@]:1}")
  if ! result="$(shfmt --to-json <<<"$script" 2>/dev/null | jq -c -f "$here/command.jq")"; then
    # A script string that doesn't parse counts when it has the word rm.
    has_rm "$script" && rm=true
    continue
  fi
  rm="$(jq -r .rm <<<"$result")"
  mapfile -t -O "${#scripts[@]}" scripts < <(jq -r '.scripts[] | @json' <<<"$result")
done
[ "$rm" = true ] || exit 0

deny "This command starts a shell with -c, such as bash -c \"…\", and runs rm. Claude Code can't check what rm deletes in such a command, so it would ask the user for approval, and an agent without the user would wait on it. Run rm as a Bash command of its own, with the exact path, and run the rest without rm. To change a variable for one tool, write VAR=value tool instead of bash -c."
