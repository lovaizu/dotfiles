#!/bin/bash
# Checks the prose that a Bash command would keep, before the command runs:
# the message of a `git commit`, the title, body or comment of a `gh issue`
# or `gh pr` command, and the prose that `cat` or `tee` writes into a file.
# When the check finds a problem, the command does not run, and the findings
# go back to Claude Code so that it fixes the text first. command-texts.jq says which texts these are.
set -uo pipefail
hooks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$hooks_dir/checks.sh"

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"$input")"
# A command that runs none of these programs is not parsed.
grep -qE '(^|[^[:alnum:]_-])(git|gh|cat|tee)([[:space:]]|$)' <<<"$command" || exit 0
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -d "$cwd" ] || cwd="$PWD"

load_checks || exit 0
if ! command -v shfmt &>/dev/null; then
  jq -n '{systemMessage: "prose-check: shfmt is not installed, so commit messages and gh bodies were not checked. Fix: run ./setup.sh of lovaizu/dotfiles."}'
  exit 0
fi
# shfmt parses the command as Bash does, here-documents and quotes as well,
# without running any of it.
if ! texts="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -c -f "$hooks_dir/command-texts.jq")"; then
  exit 0
fi
[ "$texts" = "[]" ] && exit 0

config="$(vale_config "$cwd")"
i=0
while IFS= read -r item; do
  i=$((i + 1))
  what="$(jq -r .what <<<"$item")"
  file="$(jq -r '.file // empty' <<<"$item")"
  name="$(jq -r '.name // empty' <<<"$item")"
  ext=md
  if [ -n "$name" ]; then
    ext="$(vale_ext "$name")"
    [ -n "$ext" ] || continue
  fi
  text="$work/text-$i.$ext"
  if [ -n "$file" ]; then
    case "$file" in /*) ;; *) file="$cwd/$file" ;; esac
    if [ ! -f "$file" ]; then
      notes+=("$what is in $file, which isn't there before the command runs, so the check skipped it.")
      continue
    fi
    cp "$file" "$text"
  elif jq -e '.text == null' <<<"$item" >/dev/null; then
    notes+=("The command makes $what when it runs, for example from a variable, so the check skipped it.")
    continue
  else
    jq -j .text <<<"$item" >"$text"
  fi
  # The trailers of a commit message, such as Co-Authored-By, are fields in
  # a fixed form, not prose. So the last paragraph is left out when each of
  # its lines is a trailer. --trailer is not read for the same reason.
  if [ "$what" = "the commit message" ]; then
    awk -v RS= -v ORS='\n\n' '{ p[NR] = $0 } END {
      t = 1; n = split(p[NR], l, "\n"); for (i = 1; i <= n; i++) if (l[i] !~ /^[A-Za-z0-9-]+: /) t = 0
      for (i = 1; i < NR + (NR > 1 && t ? 0 : 1); i++) print p[i] }' "$text" >"$text.body" && mv "$text.body" "$text"
  fi
  check_english "$text" "$ext" "$config" null "$what"
  if is_markdown "$ext" || [ "$ext" = txt ]; then
    check_japanese "$text" null "$what"
  else
    check_japanese "$(japanese_text "$text" "$ext")" null "$what"
  fi
done < <(jq -c '.[]' <<<"$texts")

message=""
if [ "${#notes[@]}" -gt 0 ]; then
  message="prose-check: $(printf '%s ' "${notes[@]}")"
fi
if [ -n "$report" ]; then
  reason="The prose check found these problems in the text that this command would keep, so the command didn't run. Fix the text, then run the command again. The line numbers count from the first line of each text."$'\n\n'"$report"
  jq -n --arg reason "$reason" --arg message "$message" '
    {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}
    + (if $message != "" then {systemMessage: $message} else {} end)'
elif [ -n "$message" ]; then
  jq -n --arg message "$message" '{systemMessage: $message}'
fi
exit 0
