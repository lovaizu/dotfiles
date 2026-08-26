"""One-byte mutations of the real herdr config, merged into as dst.

The oracle is 3.12's tomllib. The only thing that must never happen is
"rc=0 and the file on disk is not TOML"; the outcome breakdown is printed so
the split between "dst replaced" and "dst left alone" can be compared across
rounds.
"""
import collections
import os
import sys

import tomllib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h import run, clean  # noqa: E402

REAL = os.path.expanduser("~/.config/herdr/config.toml")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "herdr", "config.toml")

with open(REAL, "rb") as handle:
    BASE = handle.read()
with open(SRC, encoding="utf-8") as handle:
    SRC_TEXT = handle.read()

BYTES = [b"\r", b"\x0b", b"\x0c", b"\xc2\xa0", b'"', b"'", b"[", b"]", b"{",
         b"}", b"=", b".", b"#", b"\\", b"\n", b" ", b",", b"\x00", b"z",
         b"\xff", b"0", b":"]


def cases():
    for position in range(len(BASE)):
        for repl in BYTES:
            yield BASE[:position] + repl + BASE[position + 1:]
        yield BASE[:position] + BASE[position + 1:]


def valid(text):
    try:
        tomllib.loads(text)
        return True
    except Exception:
        return False


counts = collections.Counter()
bad = []
accepted = []
total = 0
for raw in cases():
    try:
        dst = raw.decode("utf-8")
    except UnicodeDecodeError:
        dst = None
    total += 1
    if dst is None:
        continue
    rc, out, err, got, _ = run("toml", SRC_TEXT, dst)
    counts[rc] += 1
    counts["dst-valid" if valid(dst) else "dst-broken"] += 1
    # The merge does not vet values any more, so rc=0 on an already broken
    # dst is expected (counted as `accepted` below). What must never happen
    # is a valid dst coming back invalid.
    if rc == 0 and valid(dst) and (got is None or not valid(got)):
        bad.append((dst, got))
    if rc == 0 and not valid(dst):
        accepted.append(dst)
    if total % 500 == 0:
        clean()

print("mutations tried: %d (decodable: %d)" % (total, sum(
    counts[k] for k in counts if isinstance(k, int))))
print("exit codes: %s" % dict(
    (k, counts[k]) for k in sorted(k for k in counts if isinstance(k, int))))
print("dst valid/broken: %d / %d" % (counts["dst-valid"], counts["dst-broken"]))
print("rc=0 turning a VALID dst invalid: %d" % len(bad))
for dst, got in bad[:3]:
    print("  dst=%r\n  got=%r" % (dst, got))
print("rc=0 on a dst tomllib rejects: %d" % len(accepted))
for dst in accepted[:3]:
    print("  dst=%r" % (dst,))
clean()

# Of the already broken dsts the merge now accepts, how many does it leave
# broken? The merge owns the keys src names, so rewriting one often repairs
# the very line the mutation damaged; what is left is damage elsewhere.
repaired = still_broken = 0
for dst in accepted:
    rc, out, err, got, _ = run("toml", SRC_TEXT, dst)
    if got is not None and valid(got):
        repaired += 1
    else:
        still_broken += 1
clean()
print("of those, output valid after merge: %d; still broken: %d"
      % (repaired, still_broken))
