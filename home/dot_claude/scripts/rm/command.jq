# Reads the syntax tree that `shfmt --to-json` makes of a Bash command, and
# prints {rm, scripts, braces}.
#
# rm is true when the command runs rm itself. scripts holds the script
# string of each shell that the command starts with -c, such as the "…" of
# `bash -l -c "…"`. A part that only running the command can give, such as
# $dir, stands as `_` in the string, so that the string still parses and
# shows each command in it.
#
# braces holds each ${…} expansion whose operand has more { than }, outside
# quotes, such as ${y:-{\}}. Each is {end, need}: end is the byte offset
# just after the closing }, and need is the count of { left open. Bash
# counts a { in the operand, so the expansion ends only after need more }.
# shfmt ends it at the first }, so the check of those } is up to the hook.

def part:
  if .Type == "Lit" then .Value
  elif .Type == "SglQuoted" then .Value
  elif .Type == "DblQuoted" then
    [.Parts[]? | if .Type == "Lit" then .Value | gsub("\\\\(?<c>[\"\\\\$`])"; .c) else "_" end] | join("")
  else "_" end;
def word: [.Parts[]? | part] | join("");

# The words of a command, without the commands that only run the next
# word, such as `env HOME=x` and `sudo`.
def unwrap:
  if length == 0 then .
  elif (.[0] | split("/") | last) as $p | any(["env", "sudo", "exec", "command", "nohup"][]; . == $p) then
    .[1:] | until(length == 0 or ((.[0] | startswith("-") or test("^[A-Za-z_][A-Za-z0-9_]*=")) | not); .[1:]) | unwrap
  else . end;

# The script string of a shell started with -c, or empty.
def script:
  if length > 0 and ((.[0] | split("/") | last) as $p | any(["bash", "sh", "zsh", "dash", "ksh"][]; . == $p)) then
    reduce .[1:][] as $a ({c: false, skip: false, done: false, script: null};
      if .done then .
      elif .skip then .skip = false
      elif $a == "-o" or $a == "+o" then .skip = true
      elif $a == "--" then .
      elif ($a | test("^[-+][A-Za-z]+$")) then (if ($a | test("^-[A-Za-z]*c")) then .c = true else . end)
      elif ($a | startswith("--")) then .
      else .script = $a | .done = true end)
    | select(.c and .script != null) | .script
  else empty end;

# The count of { minus the count of } in a literal, where a character
# after a backslash counts as neither.
def open_braces:
  gsub("\\\\."; "") | [explode[] | if . == 123 then 1 elif . == 125 then -1 else 0 end] | add // 0;

[.. | objects | select(.Type? == "CallExpr" and (.Args | length) > 0) | [.Args[] | word] | unwrap] as $calls
| {rm: any($calls[]; length > 0 and (.[0] | split("/") | last) == "rm"),
   scripts: [$calls[] | script],
   braces: [.. | objects | select(.Type? == "ParamExp" and .Rbrace != null) |
     {end: .End.Offset,
      need: ([(.Exp.Word?, .Repl.Orig?, .Repl.With?) | select(. != null) |
        .Parts[]? | select(.Type == "Lit") | .Value | open_braces] | add // 0)} |
     select(.need > 0)]}
