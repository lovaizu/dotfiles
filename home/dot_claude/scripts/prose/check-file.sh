#!/bin/bash
# Checks the whole of each file that Claude Code has just written: the file
# of a Write or an Edit, and each file that a Bash command wrote by a
# redirect or by `tee`, as command-texts.jq finds them. The findings go
# back to Claude Code, so that it fixes them before it goes on.
set -uo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
. "$here/checks.sh"

input="$(cat)"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -d "$cwd" ] || cwd="$PWD"
if [ "$(jq -r '.tool_name' <<<"$input")" = Bash ]; then
  command="$(jq -r '.tool_input.command // empty' <<<"$input")"
  grep -qE '>|(^|[^[:alnum:]_-])tee([[:space:]]|$)' <<<"$command" || exit 0
  command -v shfmt &>/dev/null || exit 0
  files="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -r -f "$here/command-texts.jq" | jq -r '.[] | .name // empty')" || exit 0
else
  files="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
fi

checked=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in /*) ;; *) file="$cwd/$file" ;; esac
  [ -f "$file" ] || continue
  path="$(in_repo "$file")" || continue
  prose_file "$file" "$path"
  checked+=("$file")
done <<<"$files"

answer PostToolUse "${checked[*]}" "Fix each one in the file before you go on."
exit 0
