#!/bin/bash
# Checks the prose of the file that Claude Code has just written or edited,
# and gives the findings back to Claude Code so that it fixes them before it
# goes on. The prose is the whole text of a Markdown or text file, and the
# comments and docstrings of code. vale_ext in lib/lib.sh of lovaizu/checks
# lists the formats.
#
# The hook reports only the paragraphs that the edit changed. The rest of the
# file can be the work of another person, and an edit is no reason to
# rewrite it.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/checks.sh"

input="$(cat)"
file="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
[ -f "$file" ] || exit 0

# The lines that the edit wrote, from the patch that Claude Code reports. A
# new file has no patch, and all of its lines are new.
changed="$(jq -c '
  [ .tool_response.structuredPatch // [] | .[] |
    foreach .lines[] as $l (
      {n: (.newStart - 1)};
      if ($l | startswith("-")) then .out = null
      else .n += 1 | .out = (if ($l | startswith("+")) then .n else null end) end;
      .out
    ) | select(. != null) ]' <<<"$input")"
if [ "$changed" = "[]" ]; then
  if [ "$(jq -r '.tool_response.type // empty' <<<"$input")" != "create" ]; then
    exit 0
  fi
  changed="$(awk 'BEGIN { printf "[" } { printf "%s%d", (NR > 1 ? "," : ""), NR } END { print "]" }' "$file")"
fi

# Every line of each paragraph that holds a changed line. lint.py reports a
# finding on a paragraph at the paragraph's first line.
lines="$(awk -v changed="$changed" '
  BEGIN { gsub(/[][]/, "", changed); n = split(changed, c, ","); for (i = 1; i <= n; i++) want[c[i]] = 1 }
  /^[[:space:]]*$/ { para++; next }
  { of[NR] = para; if (NR in want) hit[para] = 1 }
  END {
    printf "["; sep = ""
    for (l = 1; l <= NR; l++) if ((l in of) && (of[l] in hit)) { printf "%s%d", sep, l; sep = "," }
    print "]"
  }' "$file")"
[ "$lines" = "[]" ] && exit 0
load_checks || exit 0

check_prose "$file" "$lines" "$(vale_config "$(dirname "$file")")"

message=""
if [ "${#notes[@]}" -gt 0 ]; then
  message="prose-check: $(printf '%s ' "${notes[@]}")"
fi
if [ -n "$report" ]; then
  reason="The prose check found these problems in the paragraphs that this edit wrote in $file. Fix each one in the file before you go on."$'\n\n'"$report"
  jq -n --arg reason "$reason" --arg message "$message" \
    '{decision: "block", reason: $reason} + (if $message != "" then {systemMessage: $message} else {} end)'
elif [ -n "$message" ]; then
  jq -n --arg message "$message" '{systemMessage: $message}'
fi
exit 0
