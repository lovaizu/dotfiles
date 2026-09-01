#!/bin/sh
input=$(cat)

# Context usage in tokens: used_k/size_k (e.g. C:110k/1000k).
# The built-in indicator and .context_window.used_percentage both count input
# tokens only (input + cache_creation + cache_read), so they read low. The real
# context-limit check counts output too. Compute from current_usage's raw token
# breakdown — input + output + cache_creation + cache_read — to match it exactly.
# Fall back to used_percentage (+ output share) on older clients without
# current_usage.
seg1=$(echo "$input" | jq -r '
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
# The parenthesised note ("(1M context)") is dropped because the C: segment
# above already states the context size.
display=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
abbrev=$(echo "$display" | sed -E \
  -e 's/ *[(][^)]*[)]//g' \
  -e 's/^Claude //' \
  -e 's/ //g')

# Effort level first letter
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  e=$(printf '%.1s' "$effort")
  seg2="${abbrev}/${e}"
else
  seg2="${abbrev}"
fi

# Directory basename @ git branch
dir=$(echo "$input" | jq -r '.workspace.current_dir // empty')
dirname=$(basename "${dir:-$(pwd)}")
branch=$(cd "${dir:-.}" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  seg3="${dirname}@${branch}"
else
  seg3="${dirname}"
fi

# Max plan rate limits — append to seg1
five_h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$five_h_pct" ]; then
  five_h_int=$(printf '%.0f' "$five_h_pct")
  seg1="${seg1} 5h:${five_h_int}%"
fi
if [ -n "$seven_d_pct" ]; then
  seven_d_int=$(printf '%.0f' "$seven_d_pct")
  seg1="${seg1} 7d:${seven_d_int}%"
fi

printf '%s | %s | %s' "$seg1" "$seg2" "$seg3"
