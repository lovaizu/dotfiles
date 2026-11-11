#!/bin/bash
# Checks the text that a Bash command would keep, before the command runs:
# the message of a `git commit`, and the title, body or comment of a
# `gh issue` or `gh pr` command. command-texts.jq finds these texts. When
# the check finds a problem, the command doesn't run, and the findings go
# back to Claude Code, so that it fixes the text first. check-file.sh checks
# the files that the command writes, once it has run.
set -uo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
. "$here/checks.sh"

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"$input")"
# A command that runs neither program isn't parsed.
grep -qE '(^|[^[:alnum:]_-])(git|gh)([[:space:]]|$)' <<<"$command" || exit 0
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -d "$cwd" ] || cwd="$PWD"
if ! command -v shfmt &>/dev/null; then
  jq -n '{systemMessage: "prose check: shfmt isn'\''t installed, so commit messages and gh bodies weren'\''t checked. Fix: run ./setup.sh of lovaizu/dotfiles."}'
  exit 0
fi
# shfmt parses the command as Bash does, here-documents and quotes as well,
# without running any of it.
texts="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -c -f "$here/command-texts.jq")" || exit 0

i=0
while IFS= read -r item; do
  [ -n "$item" ] || continue
  i=$((i + 1))
  what="$(jq -r .what <<<"$item")"
  file="$(jq -r '.file // empty' <<<"$item")"
  # The check reads a copy, so that it checks the text wherever the command
  # keeps it.
  text="$work/text-$i.md"
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
    jq -r .text <<<"$item" >"$text"
  fi
  prose_text "$cwd" "$text" "$what"
done < <(jq -c '.[] | select(has("name") | not)' <<<"$texts")

answer PreToolUse "the text that this command would keep, so the command didn't run" \
  "Fix the text, then run the command again. The line numbers count from the first line of each text."
exit 0
