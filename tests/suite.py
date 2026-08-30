"""Round-3 regression suite for the setup.sh merger.

Run under python 3.12 (it needs tomllib as the oracle); the merger itself is
invoked with MERGE_PY, which defaults to /usr/bin/python3 (3.9).
"""
import json
import os
import sys
import tomllib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h import run, clean, HERE  # noqa: E402

PASS = FAIL = 0
FAILED = []


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
    else:
        FAIL += 1
        FAILED.append("%s  %s" % (name, detail))
        print("FAIL %-46s %s" % (name, detail))


def toml_ok(text):
    try:
        tomllib.loads(text)
        return True
    except Exception:
        return False


def toml_why(text):
    try:
        tomllib.loads(text)
        return "valid"
    except Exception as err:
        return str(err)


def json_ok(text):
    try:
        json.loads(text)
        return True
    except Exception:
        return False


def never_lies(name, fmt, src, dst):
    """The one invariant every case shares: the merge never makes a file
    worse. A valid dst that comes back rc=0 is still valid; an already
    invalid dst is not the merge's doing, and rc=0 there only promises the
    merge did not add to the damage. Any other rc means it said so out loud.

    This used to read "rc=0 means valid", full stop, which the merge could
    only keep by vetting every value it copied -- and every gap in that
    vetting turned into a refusal to touch a file the application reads
    fine. The property below is the one the merge can actually hold.
    """
    rc, out, err, got, _ = run(fmt, src, dst)
    good = toml_ok if fmt == "toml" else json_ok
    if rc == 0 and dst is not None and good(dst):
        check(name + " [rc0 -> still valid]", got is not None and good(got),
              "rc=0 but %r" % (got,))
    return rc, out, err, got


# --- (1) str.strip() eating CR / FF / VT / NBSP ---------------------------
STRIP_CASES = [
    ("1-cr-key", "a = 1\n", "a\r = 2\n"),
    ("1-cr-header", "[t]\na = 1\n", "[t\r]\na = 2\n"),
    ("1-cr-dotted", "[t]\na = 1\n", "x.y\r = 2\n[t]\na = 3\n"),
    ("1-ff-key", "a = 1\n", "a\x0c = 2\n"),
    ("1-vt-key", "a = 1\n", "a\x0b = 2\n"),
    ("1-nbsp-key", "a = 1\n", "a\xa0 = 2\n"),
    ("1-ff-after-value", "a = 1\n", "a = 1 \x0c\n"),
    ("1-ff-line", "a = 1\n", "a = 2\n\x0c\n"),
    ("1-nbsp-line", "a = 1\n", "a = 2\n\xa0\n"),
    ("1-cr-after-value", "a = 1\n", "a = 2 \r\rb = 3\n"),
]
for name, src, dst in STRIP_CASES:
    assert not toml_ok(dst), name  # the dst really is broken
    rc, out, err, got = never_lies(name, "toml", src, dst)
    check(name + " [not silently ok]", rc != 0, "rc=%s out=%r" % (rc, got))

# A file that stops halfway through a CRLF is truncated, not a CRLF file.
for name, dst in [("1-cr-eof", 'a = 2\r'), ("1-cr-eof-crlf", 'a = 2\r\nb = 3\r')]:
    assert not toml_ok(dst), name
    rc, out, err, got = never_lies(name, "toml", "a = 1\n", dst)
    check(name + " [not silently ok]", rc != 0, "rc=%s out=%r" % (rc, got))
# A file with no final newline at all is not broken, only unfinished.
rc, out, err, got = never_lies("1-no-final-newline", "toml", "a = 1\n", "a = 2")
check("1-no-final-newline [merged]", rc == 0 and got == "a = 1\n", repr(got))

# CRLF and a trailing CR-only file must keep working.
rc, out, err, got = never_lies("1-crlf-ok", "toml", "a = 1\r\n", "a = 2\r\n")
check("1-crlf-ok [merged]", rc == 0 and got == "a = 1\r\n", repr(got))
rc, out, err, got = never_lies("1-crlf-blank", "toml", "a = 1\n",
                               "a = 2\r\n\r\n[t]\r\nz = 3\r\n")
check("1-crlf-blank [merged]", rc == 0 and "z = 3" in (got or ""), repr(got))

# --- (2) implied vs declared tables ---------------------------------------
rc, out, err, got = never_lies(
    "2-broken-dst", "toml", 'prefix = "new"\n',
    '[a.b]\nd = 2\n\n[a]\nb.c = 1\nprefix = "old"\n')
check("2-broken-dst [recovered]", rc == 3, "rc=%s" % rc)

CASES2 = [
    ("2-empty-table", "[a]\nb.c = 1\n", "[a.b]\n\n[a]\nz = 3\n", "z = 3"),
    ("2-deep", "[a]\nb.c.d = 1\n", "[a.b.c]\n\n[a]\nz = 3\n", "z = 3"),
    ("2-no-a", "[a]\nb.c = 1\n", "[a.b]\n", None),
    ("2-toast", "[ui]\ntoast.enable = true\n",
     "[ui]\nx = 1\n\n[ui.toast]\n", "x = 1"),
]
for name, src, dst, keep in CASES2:
    assert toml_ok(dst), name  # the dst is valid to start with
    rc, out, err, got = never_lies(name, "toml", src, dst)
    check(name + " [wrote or skipped]", rc in (0, 4), "rc=%s" % rc)
    if rc == 0:
        check(name + " [src applied]", got is not None and "1" in got, repr(got))
        if keep:
            check(name + " [dst key kept]", keep in got, repr(got))

# False positives: valid documents that must merge cleanly.
CASES2FP = [
    ("2fp-order", "[ui]\nx = 2\n",
     "[ui.toast]\nenable = false\n\n[ui]\nx = 1\n", ["x = 2", "enable = false"]),
    ("2fp-dotted-table", "[a]\nb.c = 2\n",
     "[a]\nb.c = 1\n\n[a.d]\nx = 1\n", ["b.c = 2", "x = 1"]),
    ("2fp-same-name", "[a]\nx = 9\n", "[a]\nx = 1\n\n[b]\nx = 2\n",
     ["x = 9", "x = 2"]),
    ("2fp-quoted-dot", 'a."b.c".d = 2\n', 'a."b.c".d = 1\n', ['d = 2']),
    ("2fp-dotted-then-table", "a.b = 2\n", "a.b = 1\n\n[a.c]\nx = 1\n",
     ["a.b = 2", "x = 1"]),
    ("2fp-header-then-parent", "[a]\nz = 4\n", "[a.b]\nq = 1\n\n[a]\nz = 3\n",
     ["z = 4", "q = 1"]),
]
for name, src, dst, wants in CASES2FP:
    assert toml_ok(dst), name
    rc, out, err, got = never_lies(name, "toml", src, dst)
    check(name + " [merged]", rc == 0, "rc=%s %s" % (rc, out.strip()))
    for want in wants:
        check(name + " [%s]" % want, want in (got or ""), repr(got))

# --- (3) a structure the parser cannot follow must not cost dst -----------
CASES3 = [
    ("3-array-of-tables", '[[x]]\ny = 1\n'),
]
for name, dst in CASES3:
    rc, out, err, got = never_lies(name, "toml", 'prefix = "new"\n', dst)
    check(name + " [dst untouched]", rc == 4 and got == dst,
          "rc=%s got=%r" % (rc, got))
    check(name + " [says so]", "left as it is" in out, out.strip()[:90])

# --- (3V) a value spelled in a way this merge does not read is not its call.
# These used to be refused, which left dst holding the old dotfiles values
# for good. The merge no longer reads values: the key it owns is set and
# the odd value beside it is carried through untouched.
CASES3V = [
    ("3v-leap-second", 'stamp = 1979-05-27T23:59:60Z\n', "stamp"),
    ("3v-escape-e", 'a = "\\e[0m"\n', "a"),
    ("3v-time-no-seconds", 'stamp = 07:32\n', "stamp"),
    ("3v-bare-word", 'a = hello\n', "a"),
    ("3v-impossible-date", 'a = 2020-13-45\n', "a"),
    ("3v-leading-zero", 'a = 0123\n', "a"),
]
for name, keep, _key in CASES3V:
    dst = keep + 'prefix = "old"\n'
    rc, out, err, got = never_lies(name, "toml", 'prefix = "new"\n', dst)
    check(name + " [merged]", rc == 0, "rc=%s %s" % (rc, out.strip()[:80]))
    check(name + " [dotfiles key applied]", 'prefix = "new"' in (got or ""),
          repr(got))
    check(name + " [odd value kept]", keep in (got or ""), repr(got))

CASES3B = [
    ("3-unterminated", 'a = "oops\n'),
    ("3-junk-line", "!!!\n"),
    ("3-no-value", "a =\n"),
    ("3-dup-key", "a = 1\na = 1\n"),
    ("3-dup-table", "[t]\n[t]\n"),
    ("3-key-and-table", "a = 1\n[a]\n"),
    ("3-unbalanced", "a = [1, 2\n"),
    ("3-control-char", 'a = "x\x01y"\n'),
]
for name, dst in CASES3B:
    assert not toml_ok(dst), name
    rc, out, err, got = never_lies(name, "toml", 'prefix = "new"\n', dst)
    check(name + " [recovered]", rc == 3 and got == 'prefix = "new"\n',
          "rc=%s got=%r" % (rc, got))

# --- (7) a new key goes above the section's trailing comment block --------
DST7 = ('[ui]\nshow_agent_labels = false\nmy_own_key = 42\n\n'
        '# theme section comment\n[theme]\nname = "nord"\n')
SRC7 = '[ui]\nshow_agent_labels = true\nagent_panel_sort = "priority"\n'
rc, out, err, got = never_lies("7-comment-block", "toml", SRC7, DST7)
check("7-comment-block [merged]", rc == 0, "rc=%s" % rc)
check("7-comment-block [above the comment]",
      got is not None and got.index("agent_panel_sort") < got.index("# theme"),
      repr(got))
check("7-comment-block [comment still above theme]",
      got is not None and got.index("# theme") < got.index("[theme]"), repr(got))
check("7-comment-block [dst key kept]", "my_own_key = 42" in (got or ""),
      repr(got))
# ... and a section that is nothing but comments still gets the key.
rc, out, err, got = never_lies("7-only-comments", "toml", "a = 1\n",
                               "# lone comment\n")
check("7-only-comments [merged]", rc == 0 and "a = 1" in (got or ""), repr(got))
check("7-only-comments [comment kept]", "# lone comment" in (got or ""),
      repr(got))

# --- (8) the comments and docstrings say what the code does ---------------
# The wording checks below span both halves of the merge: the shell that
# calls it and the python that does it. They used to be one file.
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [os.environ.get("SETUP_SH", os.path.join(REPO, "setup.sh")),
           os.environ.get("MERGE_FILE", os.path.join(REPO, "lib", "merge.py"))]
SETUP = ""
for source in SOURCES:
    with open(source, encoding="utf-8") as handle:
        SETUP += handle.read()
check("8-outcome-count-consistent",
      "Three outcomes" not in SETUP and "three outcomes" not in SETUP
      and "four things happened" not in SETUP,
      "still says three")
check("8-outcome-count-stated", "which of five things happened" in SETUP
      and "One line per exit code" in SETUP, "")
check("8-no-date-overclaim", "or a date that exists" not in SETUP, "")
check("8-stderr-noted", "stderr" in SETUP, "")
check("8-trailing-commas", "trailing comma" in SETUP, "")
check("8-backup-cp-loud", 'cp "$dst" "$bak" 2>/dev/null' not in SETUP, "")
check("8-bom-noted", "byte order mark" in SETUP and "BOM" in SETUP, "")

# --- regressions from the earlier rounds ----------------------------------
rc, out, err, got = never_lies(
    "R-json-nested", "json",
    '{"model": "opus", "hooks": {"SessionStart": [{"x": 1}]}}\n',
    '{"model": "sonnet", "localOnly": true,'
    ' "hooks": {"Stop": [{"y": 2}]}}\n')
doc = json.loads(got)
check("R-json-nested [src wins]", doc["model"] == "opus", got)
check("R-json-nested [dst kept]", doc["localOnly"] is True, got)
check("R-json-nested [nested kept]", "Stop" in doc["hooks"], got)
check("R-json-nested [nested added]", "SessionStart" in doc["hooks"], got)

# The inner hooks array of a matched matcher is merged item-wise too, keyed
# on the command: Claude Code's /config writes into that array, so a matcher
# dotfiles also carries is not dotfiles' alone.
HSRC = ('{"hooks": {"SessionStart": [{"matcher": "*", "hooks": ['
        '{"type": "command", "command": "bash dotfiles.sh", "timeout": 10}]}]}}\n')
HDST = ('{"hooks": {"SessionStart": [{"matcher": "*", "hooks": ['
        '{"type": "command", "command": "echo my-own-machine-hook"}]}]}}\n')
rc, out, err, got = never_lies("R-json-hook-same-matcher", "json", HSRC, HDST)
ev = json.loads(got)["hooks"]["SessionStart"]
check("R-json-hook-same-matcher [one matcher]", len(ev) == 1, got)
cmds = [h.get("command") for h in ev[0]["hooks"]]
check("R-json-hook-same-matcher [machine hook kept]",
      "echo my-own-machine-hook" in cmds, got)
check("R-json-hook-same-matcher [dotfiles hook applied]",
      "bash dotfiles.sh" in cmds, got)
check("R-json-hook-same-matcher [no replaced-whole warning]",
      "replaced whole" not in out, out.strip())
rc2, out2, err2, got2, _ = run("json", HSRC, got)
check("R-json-hook-same-matcher [idempotent]", got2 == got, repr(got2))

# A matcher only this machine has is a separate element and stays whole.
NDST = ('{"hooks": {"SessionStart": [{"matcher": "mine", "hooks": ['
        '{"type": "command", "command": "echo mine"}]}]}}\n')
rc, out, err, got = never_lies("R-json-hook-other-matcher", "json", HSRC, NDST)
ev = json.loads(got)["hooks"]["SessionStart"]
check("R-json-hook-other-matcher [both matchers]", len(ev) == 2, got)
by = dict((entry["matcher"], entry) for entry in ev)
check("R-json-hook-other-matcher [machine matcher kept]",
      [h["command"] for h in by["mine"]["hooks"]] == ["echo mine"], got)
check("R-json-hook-other-matcher [dotfiles matcher added]",
      [h["command"] for h in by["*"]["hooks"]] == ["bash dotfiles.sh"], got)
rc2, out2, err2, got2, _ = run("json", HSRC, got)
check("R-json-hook-other-matcher [idempotent]", got2 == got, repr(got2))

# A matcher and a command are compared literally, unlike a WT guid: two that
# differ only in case are two entries, and neither is written over the other.
CSRC = ('{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": ['
        '{"type": "command", "command": "echo Hello"}]}]}}\n')
CDST = ('{"hooks": {"PreToolUse": [{"matcher": "bash", "hooks": ['
        '{"type": "command", "command": "echo hello"}]}]}}\n')
rc, out, err, got = never_lies("R-json-hook-case", "json", CSRC, CDST)
ev = json.loads(got)["hooks"]["PreToolUse"]
check("R-json-hook-case [matcher case kept apart]", len(ev) == 2,
      json.dumps(ev))
mine = [entry for entry in ev if entry["matcher"] == "bash"]
check("R-json-hook-case [machine matcher untouched]",
      len(mine) == 1 and [h["command"] for h in mine[0]["hooks"]]
      == ["echo hello"], json.dumps(ev))
rc, out, err, got = never_lies("R-json-hook-cmd-case", "json", CSRC, CSRC)
ev = json.loads(got)["hooks"]["PreToolUse"]
check("R-json-hook-cmd-case [same matcher merged]", len(ev) == 1,
      json.dumps(ev))
rc, out, err, got = never_lies(
    "R-json-hook-cmd-case2", "json", CSRC,
    ('{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": ['
     '{"type": "command", "command": "echo hello"}]}]}}\n'))
cmds = [h["command"] for h in json.loads(got)["hooks"]["PreToolUse"][0]["hooks"]]
check("R-json-hook-cmd-case2 [command case kept apart]",
      sorted(cmds) == ["echo Hello", "echo hello"], got)

SRCJ = ('{"profiles": {"list": [{"guid": "{AAAA}", "font": {"face": "HackGen"}},'
        ' {"guid": "{cccc}"}]}}\n')
DSTJ = ('{"profiles": {"list": [{"guid": "{aaaa}", "font": {"size": 12},'
        ' "startingDirectory": "/x"}, {"guid": "{bbbb}"}]}}\n')
rc, out, err, got = never_lies("R-json-guid", "json", SRCJ, DSTJ)
lst = json.loads(got)["profiles"]["list"]
check("R-json-guid [three entries]", len(lst) == 3, got)
check("R-json-guid [dst-only kept]",
      any(p["guid"] == "{bbbb}" for p in lst), got)
check("R-json-guid [matched recursively]",
      lst[0]["startingDirectory"] == "/x"
      and lst[0]["font"] == {"size": 12, "face": "HackGen"}, got)

rc, out, err, got = never_lies("R-jsonc", "json", '{"a": 1}\n',
                               '{\n  // note\n  "a": 2,\n  "b": 3,\n}\n')
check("R-jsonc [merged]", rc == 0 and json.loads(got) == {"a": 1, "b": 3}, got)
check("R-jsonc [warns about both]",
      "comments and trailing commas" in out, out.strip())

# JSON keeps the keys, not the layout: the document is rebuilt, so a CRLF dst
# comes back LF. tests/README.md says so, and this is what says it is true.
rc, out, err, got = never_lies("R-json-crlf", "json", '{"a": 1}\n',
                               '{\r\n  "a": 2,\r\n  "b": 3\r\n}\r\n')
check("R-json-crlf [merged]", rc == 0 and json.loads(got) == {"a": 1, "b": 3},
      repr(got))
check("R-json-crlf [written LF]", "\r" not in (got or ""), repr(got))

DSTT = ('# top\nprefix = "ctrl+b"\nmine = 7\n\n[ui]\n'
        'dark_name = "nord" # hand set\n')
SRCT = 'prefix = "ctrl+t"\n\n[ui]\ndark_name = "gruvbox"\nnew_key = 1\n'
rc, out, err, got = never_lies("R-toml-basic", "toml", SRCT, DSTT)
for want in ["# top", 'prefix = "ctrl+t"', "mine = 7",
             'dark_name = "gruvbox" # hand set', "new_key = 1"]:
    check("R-toml-basic [%s]" % want, want in (got or ""), repr(got))
rc2, out2, err2, got2, _ = run("toml", SRCT, got)
check("R-toml-basic [idempotent]", got2 == got, repr(got2))

rc, out, err, got = never_lies("R-toml-fresh", "toml", "a = 1\n", None)
check("R-toml-fresh [installed]", rc == 5, "rc=%s" % rc)
check("R-toml-fresh [content]", got == "a = 1\n", repr(got))

rc, out, err, got = never_lies("R-toml-empty-dst", "toml", "a = 1\n", "\n")
check("R-toml-empty-dst [installed quietly]",
      rc == 5 and "WARNING" not in out, "rc=%s %s" % (rc, out.strip()))

rc, out, err, got = never_lies("R-multiline", "toml",
                               'a = """\nx = 1\n"""\nb = 2\n',
                               'a = """\nold\n"""\nb = 1\nc = 3\n')
check("R-multiline [value replaced]", 'x = 1' in (got or ""), repr(got))
check("R-multiline [dst key kept]", "c = 3" in (got or ""), repr(got))

rc, out, err, got = never_lies("R-src-broken", "toml", "a = 1\na = 2\n",
                               "a = 3\n")
check("R-src-broken [aborts]", rc not in (0, 3, 4, 5, 6), "rc=%s" % rc)
check("R-src-broken [dst untouched]", got == "a = 3\n", repr(got))
check("R-src-broken [on stderr]", "merge:" in err, repr(err))

print("\nPASS=%d FAIL=%d" % (PASS, FAIL))
if FAILED:
    print("failed: " + ", ".join(item.split("  ")[0] for item in FAILED))
clean()
sys.exit(1 if FAIL else 0)
