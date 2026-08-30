#!/bin/bash
# Round trip on real files -- always on copies. The originals are never
# opened for writing; their md5 and mtime are printed before and after, and
# compared at the end.
#
# Every line below is worth exactly as much as the merge it describes, and
# from #13 until this was fixed there was no merge at all: helpers.sh works
# DOTFILES_DIR out from "$0", which under `source` is this script, so the
# merger resolved to tests/lib/merge.py, every pass failed with rc=2 and
# wrote nothing -- and the script still ended by calling itself idempotent
# and the config ok. A green result that cannot go red is worse than no test,
# so every step here records a failure instead of printing and moving on, and
# the script exits non-zero when there is one.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
W="$HERE/real"
rm -rf "$W"; mkdir -p "$W"
sed -n '1,/^# herdr (common)$/p' "$REPO/setup.sh" | sed '$d' > "$W/helpers.sh"

FAILURES=0
fail() { FAILURES=$((FAILURES + 1)); echo "  FAIL: $*"; }

# setup.sh's helpers, with the one thing `source` gets wrong put right.
# DOTFILES_DIR has to name the repository, and "$0" only says so when
# setup.sh is the script being run.
load_helpers() {
  source "$W/helpers.sh"
  DOTFILES_DIR="$REPO"
}

# want_rc <expected> <actual> <what>: an exit code other than the expected
# one means the step did not do what everything after it goes on to assume.
want_rc() {
  if [ "$2" = "$1" ]; then
    echo "  rc=$2"
  else
    fail "$3: rc=$2, expected $1"
  fi
}

# want_in <file> <text>...: each text is still somewhere in the file.
want_in() {
  local file="$1" text
  shift
  for text in "$@"; do
    if grep -qF -- "$text" "$file"; then
      echo "  kept: $text"
    else
      fail "$file no longer has: $text"
    fi
  done
}

ORIGINALS=("$HOME/.config/herdr/config.toml" "$HOME/.claude/settings.json")
fingerprint() {
  echo "  $1: md5=$(md5 -q "$1") mtime=$(stat -f '%m' "$1") size=$(stat -f '%z' "$1")"
}
snapshot() {
  local file
  for file in "${ORIGINALS[@]}"; do fingerprint "$file"; done
}
echo "=== originals BEFORE"
snapshot | tee "$W/before.txt"

# --- herdr: a copy of the real config, judged by herdr config check --------
# First a copy herdr fully understands, so "config: ok" means what it says.
mkdir -p "$W/clean/herdr"
cp "$HOME/.config/herdr/config.toml" "$W/clean/herdr/config.toml"
echo "=== clean copy: herdr config check BEFORE"
XDG_CONFIG_HOME="$W/clean" herdr config check
want_rc 0 $? "herdr config check on the clean copy, before"
( set -euo pipefail
  XDG_STATE_HOME="$W/state"
  load_helpers
  merge_toml "$REPO/herdr/config.toml" "$W/clean/herdr/config.toml" )
want_rc 0 $? "clean copy merge"
echo "=== clean copy: herdr config check AFTER"
XDG_CONFIG_HOME="$W/clean" herdr config check
want_rc 0 $? "herdr config check on the clean copy, after"

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
grep -q 'dark_name = "nord" # hand set, keep' "$W/xdg/herdr/config.toml" \
  || fail "the dst was not set up with a hand-edited dark_name"

echo "=== herdr config check BEFORE the merge"
XDG_CONFIG_HOME="$W/xdg" herdr config check; echo "  rc=$?"

run_merge() {
  ( set -euo pipefail
    XDG_STATE_HOME="$W/state"
    load_helpers
    merge_toml "$REPO/herdr/config.toml" "$W/xdg/herdr/config.toml" )
}
echo "=== merge pass 1"; run_merge; want_rc 0 $? "herdr merge pass 1"
cp "$W/xdg/herdr/config.toml" "$W/pass1.toml"
echo "=== merge pass 2"; run_merge; want_rc 0 $? "herdr merge pass 2"
if cmp -s "$W/pass1.toml" "$W/xdg/herdr/config.toml"; then
  echo "IDEMPOTENT: yes"
else
  echo "IDEMPOTENT: no"; diff "$W/pass1.toml" "$W/xdg/herdr/config.toml"
  fail "the herdr merge is not idempotent"
fi
echo "=== herdr config check AFTER the merge"
XDG_CONFIG_HOME="$W/xdg" herdr config check 2>&1 | tee "$W/check-after.txt"
echo "  rc=${PIPESTATUS[0]}"
# A non-zero rc is expected here and is not a failure: this copy carries a
# [machine] section herdr does not know, which is the whole point of it. What
# must not appear is a parse error -- that would mean the merge broke a file
# herdr could read before.
grep -q "parse error" "$W/check-after.txt" \
  && fail "herdr can no longer parse the merged config"
echo "--- dotfiles values applied / machine-only kept:"
want_in "$W/xdg/herdr/config.toml" \
  'prefix = "ctrl+t"' \
  'dark_name = "gruvbox" # hand set, keep' \
  '# only on this machine' \
  'label = "kiyo-mac"'

echo "=== negative control (a broken config in the same place)"
cp "$W/xdg/herdr/config.toml" "$W/good.toml"
printf 'name = "unterminated\n' >> "$W/xdg/herdr/config.toml"
XDG_CONFIG_HOME="$W/xdg" herdr config check; rc=$?
echo "  rc=$rc"
# The control is only a control if herdr does object. rc=0 here would mean
# the "config: ok" above says nothing about anything.
[ "$rc" -ne 0 ] || fail "herdr accepted a config it should have rejected"
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
    load_helpers
    merge_json "$REPO/windows-terminal/settings.json" "$W/wt/settings.json" )
}
echo "=== WT merge pass 1"; run_wt; want_rc 0 $? "WT merge pass 1"
cp "$W/wt/settings.json" "$W/wt1.json"
echo "=== WT merge pass 2"; run_wt; want_rc 0 $? "WT merge pass 2"
if cmp -s "$W/wt1.json" "$W/wt/settings.json"; then
  echo "WT IDEMPOTENT: yes"
else
  echo "WT IDEMPOTENT: no"; diff "$W/wt1.json" "$W/wt/settings.json"
  fail "the WT merge is not idempotent"
fi
# The assertions live in python because the answers are inside the document,
# not in its text. It says which expectation went wrong and leaves with a
# non-zero code, so a merge that never ran cannot read as a pass.
if ! python3 - "$W/wt/settings.json" <<'EOF'
import json, sys

try:
    with open(sys.argv[1]) as handle:
        doc = json.load(handle)
except Exception as err:
    print("  not valid JSON: %s" % err)
    sys.exit(1)
bad = []
def want(label, got, expected):
    print("  %s: %r" % (label, got))
    if got != expected:
        bad.append("%s is %r, expected %r" % (label, got, expected))

profiles = doc.get("profiles", {})
want("dst-only launchMode kept", doc.get("launchMode"), "maximized")
want("dst-only defaults.opacity kept",
     profiles.get("defaults", {}).get("opacity"), 90)
want("dotfiles defaults.font applied",
     profiles.get("defaults", {}).get("font", {}).get("face"),
     "HackGen Console NF")
entries = profiles.get("list", [])
want("profiles", len(entries), 7)
wsl = [p for p in entries if p.get("name") == "Ubuntu-22.04"]
want("dst-only WSL profile kept", len(wsl), 1)
if wsl:
    want("  its startingDirectory", wsl[0].get("startingDirectory"),
         "//wsl$/Ubuntu-22.04/home/kiyo")
for line in bad:
    print("  FAILED: %s" % line)
sys.exit(1 if bad else 0)
EOF
then
  fail "the merged WT settings.json is not what it should be"
fi

echo "=== originals AFTER"
snapshot | tee "$W/after.txt"
cmp -s "$W/before.txt" "$W/after.txt" \
  || fail "an original file changed; this script only ever reads them"

if [ "$FAILURES" -eq 0 ]; then
  echo "REALDATA: PASS"
else
  echo "REALDATA: FAIL ($FAILURES)"
  exit 1
fi
