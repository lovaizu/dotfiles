"""Random valid TOML pairs: the output must stay valid, keep every dst key
the src did not touch, and be the same the second time round."""
import os
import random
import sys

import tomllib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h import run, clean  # noqa: E402

random.seed(int(os.environ.get("SEED", "9")))
N = int(os.environ.get("N", "600"))

NAMES = ["a", "b", "c", "ui", "theme", "keys", "toast", "name", "x_1", "b.c",
         "d-e", "Q"]
VALUES = ['"s"', "1", "0.5", "true", "false", "[1, 2]", "{ k = 1 }",
          "1979-05-27", "1979-05-27T07:32:00Z", "'lit'", '"""\nml\n"""',
          "[\n  1,\n  2,\n]", "0x1f", "inf", "-3"]


def key(depth):
    return ".".join(quote(random.choice(NAMES)) for _ in range(depth))


def quote(name):
    return name if name.replace("_", "").replace("-", "").isalnum() else '"%s"' % name


def document():
    """A document built so it is valid by construction: distinct table names,
    distinct key names inside each, no dotted key crossing a table."""
    lines = []
    tables = random.sample(["", "t1", "t2", "t3.sub", "t4"],
                           random.randint(1, 4))
    for table in tables:
        if table:
            if random.random() < 0.3:
                lines.append("# a note about [%s]" % table)
            lines.append("[%s]" % table)
        used = set()
        for _ in range(random.randint(0, 4)):
            name = random.choice(NAMES)
            if name in used:
                continue
            used.add(name)
            gap = " " * random.randint(1, 3)
            lines.append("%s%s=%s%s" % (quote(name), gap, gap,
                                        random.choice(VALUES)))
        if random.random() < 0.4:
            lines.append("")
        if random.random() < 0.2:
            lines.append("# trailing note")
    return "\n".join(lines) + "\n"


def valid(text):
    try:
        return tomllib.loads(text)
    except Exception:
        return None


bad = invalid_out = nonidem = lost = 0
tried = 0
for round_no in range(N):
    src, dst = document(), document()
    if valid(src) is None or valid(dst) is None:
        continue
    tried += 1
    rc, out, err, got, _ = run("toml", src, dst)
    if rc not in (0, 3, 4, 5):
        bad += 1
        print("unexpected rc=%s\nsrc=%r\ndst=%r\n%s" % (rc, src, dst, out))
        continue
    if rc != 0:
        continue
    parsed = valid(got)
    if parsed is None:
        invalid_out += 1
        print("INVALID OUT\nsrc=%r\ndst=%r\ngot=%r" % (src, dst, got))
        continue
    rc2, _, _, got2, _ = run("toml", src, got)
    if got2 != got:
        nonidem += 1
        print("NON IDEMPOTENT\nsrc=%r\ndst=%r\n1=%r\n2=%r" % (src, dst, got, got2))
    # every dst leaf the src did not set must still be there
    src_doc, dst_doc = valid(src), valid(dst)

    def leaves(doc, prefix=()):
        for name, value in doc.items():
            if isinstance(value, dict):
                for item in leaves(value, prefix + (name,)):
                    yield item
            else:
                yield prefix + (name,), value

    src_keys = dict(leaves(src_doc))
    for path, value in leaves(dst_doc):
        # src setting c = 1 over dst's c = { k = 1 } takes c.k with it: that
        # is the documented "written as one value" case, and it warns.
        if any(path[:cut] in src_keys for cut in range(1, len(path) + 1)):
            continue
        node = parsed
        for part in path[:-1]:
            node = node.get(part, {}) if isinstance(node, dict) else {}
        if not isinstance(node, dict) or path[-1] not in node:
            lost += 1
            print("LOST %s\nsrc=%r\ndst=%r\ngot=%r" % (path, src, dst, got))
    if round_no % 100 == 0:
        clean()

print("pairs: %d  unexpected rc: %d  invalid_out: %d  nonidem: %d  lost: %d"
      % (tried, bad, invalid_out, nonidem, lost))
clean()
