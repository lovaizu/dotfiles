#!/bin/sh
input=$(cat)

# The JSON is re-emitted with printf, never echo: both of the shells this runs
# under — macOS /bin/sh and WSL's dash — expand backslash escapes in echo, which
# mangles the JSON before jq ever parses it.

# Context usage in tokens: used_k/size_k (e.g. C:110k/1000k).
# The built-in indicator and .context_window.used_percentage both count input
# tokens only (input + cache_creation + cache_read), so they read low. The real
# context-limit check counts output too. Compute from current_usage's raw token
# breakdown — input + output + cache_creation + cache_read — to match it exactly.
# Fall back to used_percentage (+ output share) on older clients without
# current_usage.
seg1=$(printf '%s\n' "$input" | jq -r '
  .context_window as $cw
  | ($cw.context_window_size // 0) as $w
  | ($cw.current_usage) as $u
  | (if ($u != null) then
      (($u.input_tokens // 0)
       + ($u.output_tokens // 0)
       + ($u.cache_creation_input_tokens // 0)
       + ($u.cache_read_input_tokens // 0))
    elif ($cw.used_percentage != null and $w > 0) then
      (($cw.used_percentage / 100 * $w) + ($cw.total_output_tokens // 0))
    else
      0
    end) as $used
  | if ($w > 0) then
      "C:\([$used, $w] | min / 1000 | round)k/\($w / 1000 | round)k"
    else
      "C:\($used / 1000 | round)k"
    end
')

# Model name: family + version, e.g. Opus5 / Sonnet5 / Fable5 / Haiku4.5.
# No family is named in these rules on purpose — the old per-family list let
# Fable through untouched, and the next new family would slip through too.
# The parenthesised note ("(1M context)") is dropped to keep the segment to the
# name; the C: segment above is where context size belongs.
# display_name can arrive empty as well as absent, so pick the first non-empty
# of display_name / id rather than relying on jq's // (empty string is truthy).
# The normalisation lives in jq, not sed, because jq is already a hard
# dependency and its regex engine (Oniguruma) is the same build on both hosts,
# whereas sed is BSD on macOS and GNU on WSL — and the two really do disagree
# about whether [[:space:]] covers a non-breaking space (GNU/glibc does not).
# Doing it here also makes the result locale-independent.
# The notes go first so the anchor below sees the real start of the name.
# "Claude " is then stripped at the front only, so a name that merely contains
# it ("Foo Claude 5") is not cut in half; the leading-whitespace tolerance is
# there because a note removed from the front ("(beta) Claude Opus 5") leaves a
# space the anchor would otherwise miss.
# [\p{Z}\s] is the whitespace class throughout. Measured against jq 1.6, 1.7
# and 1.7.1-apple: \p{Z} takes the Unicode separators (U+00A0, U+3000) but not
# the tab or the newline, which are control characters rather than separators;
# \s takes those two, and in these builds the separators as well. The union is
# what keeps the class from depending on how Unicode-aware a given Oniguruma
# build's \s happens to be. \s reaching the newline also means a name with one
# embedded can no longer split the status line in two.
model_name=$(printf '%s\n' "$input" | jq -r '
  [.model.display_name, .model.id, "unknown"]
  | map(select(. != null and . != ""))
  | first
  | gsub("\\([^)]*\\)"; "")
  | sub("^[\\p{Z}\\s]*Claude[\\p{Z}\\s]"; "")
  | gsub("[\\p{Z}\\s]"; "")
')
# A name that is nothing but a note or blanks ("(1M context)", "   ") is emptied
# by the rules above; jq printing nothing at all (no jq on PATH, unparsable
# input) lands here too. Without this the segment would degrade to a bare "/h".
[ -n "$model_name" ] || model_name=unknown

# Effort level first letter
effort=$(printf '%s\n' "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  e=$(printf '%.1s' "$effort")
  seg2="${model_name}/${e}"
else
  seg2="${model_name}"
fi

# Directory basename @ git branch
dir=$(printf '%s\n' "$input" | jq -r '.workspace.current_dir // empty')
dirname=$(basename "${dir:-$(pwd)}")
branch=$(cd "${dir:-.}" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  seg3="${dirname}@${branch}"
else
  seg3="${dirname}"
fi

# Max plan rate limits — append to seg1
five_h_pct=$(printf '%s\n' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d_pct=$(printf '%s\n' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$five_h_pct" ]; then
  five_h_int=$(printf '%.0f' "$five_h_pct")
  seg1="${seg1} 5h:${five_h_int}%"
fi
if [ -n "$seven_d_pct" ]; then
  seven_d_int=$(printf '%.0f' "$seven_d_pct")
  seg1="${seg1} 7d:${seven_d_int}%"
fi

printf '%s | %s | %s' "$seg1" "$seg2" "$seg3"
