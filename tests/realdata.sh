#!/bin/bash
# Round trip on real files -- always on copies. The originals are never
# opened for writing; their md5 and mtime are printed before and after.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
W="$HERE/real"
rm -rf "$W"; mkdir -p "$W"
sed -n '1,/^# herdr (common)$/p' "$REPO/setup.sh" | sed '$d' > "$W/helpers.sh"

fingerprint() {
  echo "  $1: md5=$(md5 -q "$1") mtime=$(stat -f '%m' "$1") size=$(stat -f '%z' "$1")"
}
echo "=== originals BEFORE"
fingerprint "$HOME/.config/herdr/config.toml"
fingerprint "$HOME/.claude/settings.json"

# --- herdr: a copy of the real config, judged by herdr config check --------
# First a copy herdr fully understands, so "config: ok" means what it says.
mkdir -p "$W/clean/herdr"
cp "$HOME/.config/herdr/config.toml" "$W/clean/herdr/config.toml"
echo "=== clean copy: herdr config check BEFORE"
XDG_CONFIG_HOME="$W/clean" herdr config check; echo "  rc=$?"
( set -euo pipefail
  XDG_STATE_HOME="$W/state"
  source "$W/helpers.sh"
  merge_toml "$REPO/herdr/config.toml" "$W/clean/herdr/config.toml" )
echo "=== clean copy: herdr config check AFTER"
XDG_CONFIG_HOME="$W/clean" herdr config check; echo "  rc=$?"

mkdir -p "$W/xdg/herdr"
cp "$HOME/.config/herdr/config.toml" "$W/xdg/herdr/config.toml"
# A machine-only section and a hand-edited comment, to see them survive.
cat >> "$W/xdg/herdr/config.toml" <<'EOF'

# only on this machine
[machine]
label = "kiyo-mac"
EOF
python3 - "$W/xdg/herdr/config.toml" <<'EOF'
import sys
p = sys.argv[1]
t = open(p).read().replace('dark_name = "gruvbox"',
                           'dark_name = "nord" # hand set, keep')
open(p, "w").write(t)
EOF

echo "=== herdr config check BEFORE the merge"
XDG_CONFIG_HOME="$W/xdg" herdr config check; echo "  rc=$?"

run_merge() {
  ( set -euo pipefail
    XDG_STATE_HOME="$W/state"
    source "$W/helpers.sh"
    merge_toml "$REPO/herdr/config.toml" "$W/xdg/herdr/config.toml" )
}
echo "=== merge pass 1"; run_merge; echo "  rc=$?"
cp "$W/xdg/herdr/config.toml" "$W/pass1.toml"
echo "=== merge pass 2"; run_merge; echo "  rc=$?"
if cmp -s "$W/pass1.toml" "$W/xdg/herdr/config.toml"; then
  echo "IDEMPOTENT: yes"
else
  echo "IDEMPOTENT: no"; diff "$W/pass1.toml" "$W/xdg/herdr/config.toml"
fi
echo "=== herdr config check AFTER the merge"
XDG_CONFIG_HOME="$W/xdg" herdr config check; echo "  rc=$?"
echo "--- dotfiles values applied / machine-only kept:"
grep -n 'prefix\|dark_name\|label\|only on this machine\|toast' "$W/xdg/herdr/config.toml"

echo "=== negative control (a broken config in the same place)"
cp "$W/xdg/herdr/config.toml" "$W/good.toml"
printf 'name = "unterminated\n' >> "$W/xdg/herdr/config.toml"
XDG_CONFIG_HOME="$W/xdg" herdr config check; echo "  rc=$?"
cp "$W/good.toml" "$W/xdg/herdr/config.toml"

# --- Windows Terminal settings.json against another machine's copy --------
mkdir -p "$W/wt"
cat > "$W/wt/settings.json" <<'EOF'
{
    // this machine's own notes
    "$help": "https://aka.ms/terminal-documentation",
    "launchMode": "maximized",
    "profiles":
    {
        "defaults":
        {
            "opacity": 90
        },
        "list":
        [
            {
                "guid": "{2c4de342-38b7-51cf-b940-2309a097f518}",
                "name": "Ubuntu-22.04",
                "startingDirectory": "//wsl$/Ubuntu-22.04/home/kiyo",
            }
        ]
    }
}
EOF
run_wt() {
  ( set -euo pipefail
    XDG_STATE_HOME="$W/state"
    source "$W/helpers.sh"
    merge_json "$REPO/windows-terminal/settings.json" "$W/wt/settings.json" )
}
echo "=== WT merge pass 1"; run_wt; echo "  rc=$?"
cp "$W/wt/settings.json" "$W/wt1.json"
echo "=== WT merge pass 2"; run_wt; echo "  rc=$?"
if cmp -s "$W/wt1.json" "$W/wt/settings.json"; then
  echo "WT IDEMPOTENT: yes"
else
  echo "WT IDEMPOTENT: no"; diff "$W/wt1.json" "$W/wt/settings.json"
fi
python3 - "$W/wt/settings.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
print("valid JSON: yes")
print("dst-only launchMode kept:", d.get("launchMode"))
print("dst-only defaults.opacity kept:", d["profiles"]["defaults"].get("opacity"))
print("dotfiles defaults applied:", d["profiles"]["defaults"].get("font"))
lst = d["profiles"]["list"]
print("profiles:", len(lst))
wsl = [p for p in lst if p.get("name") == "Ubuntu-22.04"]
print("dst-only WSL profile kept:", bool(wsl))
if wsl:
    print("  its startingDirectory:", wsl[0].get("startingDirectory"))
EOF

echo "=== originals AFTER"
fingerprint "$HOME/.config/herdr/config.toml"
fingerprint "$HOME/.claude/settings.json"
