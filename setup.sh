#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backups go to a directory of their own: iTerm2 loads every file in
# DynamicProfiles, so a backup left beside the profile is parsed as a second
# profile with a duplicate Guid.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"

# Set by backup_file to the copy it has just taken, so a caller can point a
# message at it. Empty when there was nothing to back up.
LAST_BACKUP=""

# Copy an existing dst into BACKUP_DIR. Does nothing when dst is not there yet.
backup_file() {
  local dst="$1" bak
  LAST_BACKUP=""
  if [ -e "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    bak="$BACKUP_DIR/$(basename "$dst").$(date +%Y%m%d%H%M%S).bak"
    cp "$dst" "$bak"
    LAST_BACKUP="$bak"
    echo "Backed up existing config to $bak"
  fi
}

# Copy src to dst, backing up an existing dst first. For the files only
# dotfiles ever writes: the whole file is ours, so it is replaced wholesale.
backup_then_copy() {
  local src="$1" dst="$2"
  backup_file "$dst"
  cp "$src" "$dst"
  echo "Installed $dst"
}

# Merge src into dst item by item, backing up an existing dst first. For the
# files the application itself also writes: the keys dotfiles has are set to
# the dotfiles value, the keys only dst has are left alone. Both take
# (src, dst) exactly like backup_then_copy, so switching a call site over is
# a matter of changing the function name.
#
# dst is replaced atomically, and a dst that is missing or unusable is
# recreated from src instead of aborting the setup. A src that does not parse
# is a bug in dotfiles: it aborts the setup, leaving dst untouched. So does a
# merge whose result would not parse again -- see the merger's own notes.
merge_json() {
  merge_config json "$1" "$2"
}

merge_toml() {
  merge_config toml "$1" "$2"
}

# Shared body of merge_json / merge_toml: back up dst, then hand both files to
# the merger below. Backing up here keeps the one backup rule in one place --
# the merger only ever writes dst.
merge_config() {
  local format="$1" src="$2" dst="$3" status=0
  # `command -v python3` is not a test of whether python3 runs: macOS ships a
  # /usr/bin/python3 shim that exists on a machine with no Command Line Tools
  # and only fails when something invokes it. Running it is the test.
  #
  # Without python3 the file is left exactly as it is. It is deliberately not
  # copied over instead: these are the files the application also writes, so
  # replacing one wholesale throws away the settings that live only there --
  # the very thing merging exists to avoid. Warn and carry on, the way the
  # rest of setup.sh treats a missing tool.
  if ! python3 -c 'pass' &>/dev/null; then
    echo
    echo "WARNING: python3 does not run, so $dst was left as it is."
    echo "  Merging config files needs it (macOS: xcode-select --install)."
    echo "  The dotfiles copy was NOT written over it on purpose: this file is"
    echo "  one the application writes too, and overwriting it would discard"
    echo "  the settings that exist only on this machine."
    echo
    return 0
  fi
  backup_file "$dst"
  MERGE_BACKUP="$LAST_BACKUP" python3 - "$format" "$src" "$dst" <<'PYTHON_MERGE' || status=$?
"""Merge the dotfiles copy of a config file into the installed one.

usage: python3 - {json|toml} SRC DST

Only the keys SRC has are touched; everything else in DST survives, including
-- for TOML -- its comments, blank lines and key order. Nothing here needs a
module newer than Python 3.9 (macOS ships 3.9, which has no TOML parser) and
nothing shells out, so no jq either.

The exit code says which of three things happened. 0: SRC was merged into
DST. 3: DST was not usable and SRC replaced it wholesale, after a warning on
stderr naming the backup. Anything else: nothing was written and DST is
exactly as it was, with a one line reason on stderr.

Nothing reaches DST that has not been parsed again first, so "the result is a
file the application can read" is something the merge establishes rather than
hopes for.
"""

import json
import os
import stat
import sys
import tempfile


class Unsupported(Exception):
    """A document that parses but uses a construct the merge cannot handle."""


def warn(message):
    sys.stderr.write("merge: %s\n" % message)


def report_replaced(dst, label, reason):
    """The loud form of warn, for the one outcome that loses settings.

    A single lower case line on stderr is missed in the middle of a setup
    run, and this is the case where the machine's own configuration has just
    been thrown away, so it gets the same shape as setup.sh's other warnings
    and it names the backup it can be recovered from.
    """
    backup = os.environ.get("MERGE_BACKUP", "")
    lines = ["",
             "WARNING: %s is not usable %s (%s)." % (dst, label, reason),
             "  It has been replaced by the dotfiles copy, so any setting that",
             "  existed only on this machine is gone from it."]
    if backup:
        lines.append("  The file as it was is kept at %s" % backup)
        lines.append("  Copy anything still wanted out of there by hand.")
    lines.append("")
    sys.stderr.write("\n".join(lines) + "\n")


def read_text(path):
    # newline="" so a CRLF file arrives exactly as it sits on disk: the TOML
    # merge writes those endings back, while the JSON merge re-serialises the
    # whole document and so always writes LF. utf-8-sig so a byte order mark
    # from a Windows editor is skipped rather than read as content and
    # mistaken for a corrupt file.
    with open(path, encoding="utf-8-sig", newline="") as handle:
        return handle.read()


def ensure_newline(text):
    if text and not text.endswith("\n"):
        return text + "\n"
    return text


# --- JSON ------------------------------------------------------------------

# Arrays whose elements carry a stable id and so are matched element by
# element instead of being replaced wholesale, keyed by the path of the array.
# Windows Terminal keeps one profiles.list entry per profile and writes an
# extra one for every WSL distro installed on that machine.
MERGE_BY_ID = {("profiles", "list"): "guid"}


def json_path(path):
    return ".".join(str(part) for part in path) or "the document"


def json_skip_string(text, index):
    """Index just past the string literal that starts at index."""
    index += 1
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == '"':
            return index + 1
        index += 1
    return index


def json_relax(text):
    """JSONC reduced to plain JSON: comments and trailing commas dropped.

    Windows Terminal's settings.json is JSONC by design -- the file it ships
    is full of // comments and people add their own -- so a file with them is
    a working file, not a broken one. Losing the comments from the output is
    a far smaller price than discarding every setting the file held.
    """
    plain = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == '"':
            end = json_skip_string(text, index)
            plain.append(text[index:end])
            index = end
            continue
        if text.startswith("//", index):
            end = text.find("\n", index)
            index = len(text) if end < 0 else end
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            index = len(text) if end < 0 else end + 2
            continue
        plain.append(char)
        index += 1
    text = "".join(plain)
    out = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == '"':
            end = json_skip_string(text, index)
            out.append(text[index:end])
            index = end
            continue
        if char == ",":
            after = index + 1
            while after < len(text) and text[after] in " \t\r\n":
                after += 1
            if after < len(text) and text[after] in "}]":
                index += 1
                continue
        out.append(char)
        index += 1
    return "".join(out)


def json_parse(text):
    try:
        value = json.loads(text)
    except ValueError:
        value = json.loads(json_relax(text))
    if not isinstance(value, dict):
        raise ValueError("the top level is not a JSON object")
    return value


def element_id(item, id_key):
    """Identity of an array element, or None when it has no usable id."""
    if not isinstance(item, dict):
        return None
    value = item.get(id_key)
    if not isinstance(value, str):
        return None
    # Windows Terminal writes GUIDs as "{0caa0dad-...}" and hex digits are
    # case insensitive, so elements are matched on the case-folded id. The
    # dotfiles spelling then wins, the same as every other value it owns.
    return value.lower()


def merge_by_id(old, new, id_key, path):
    merged = list(old)
    at = {}
    for position, item in enumerate(merged):
        key = element_id(item, id_key)
        if key is not None:
            at.setdefault(key, position)
    for item in new:
        key = element_id(item, id_key)
        if key is None:
            # Nothing to match it against, so appending it would append it
            # again on the next run and the one after that. setup.sh is meant
            # to be safe to re-run, so it is skipped instead.
            warn("an entry of %s has no usable %s; skipping it"
                 % (json_path(path), id_key))
        elif key in at:
            # The same rule as the document itself: the keys dotfiles has win,
            # the keys only this machine's entry has are left alone.
            merged[at[key]] = merge_objects(merged[at[key]], item,
                                            path + ("[]",))
        else:
            at[key] = len(merged)
            merged.append(item)
    return merged


def merge_objects(old, new, path=()):
    """Recursive dict merge, new winning. Arrays are leaves unless the path
    to them is listed in MERGE_BY_ID."""
    merged = dict(old)
    for key, value in new.items():
        here = path + (key,)
        current = merged.get(key)
        if isinstance(value, dict) and isinstance(current, dict):
            merged[key] = merge_objects(current, value, here)
        elif (isinstance(value, list) and isinstance(current, list)
                and here in MERGE_BY_ID):
            merged[key] = merge_by_id(current, value, MERGE_BY_ID[here], here)
        else:
            merged[key] = value
    return merged


def json_indent(text):
    """Indent width of a JSON document, so the merge keeps its layout."""
    for line in text.splitlines():
        width = len(line) - len(line.lstrip(" "))
        if width:
            return min(width, 8)
    return 2


def json_combine(old, new, dst_text):
    return json.dumps(merge_objects(old, new), indent=json_indent(dst_text),
                      ensure_ascii=False) + "\n"


# --- TOML ------------------------------------------------------------------
#
# Line based on purpose: rewriting the file through a parser would drop the
# comments and the ordering the application (or the user) put there, and
# Python 3.9 has no TOML parser to rewrite it with anyway. What is parsed is
# only as much as the merge has to understand -- where each logical line
# starts and ends, and which key it sets.

BARE_KEY = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                     "abcdefghijklmnopqrstuvwxyz0123456789_-")

ESCAPES = {"b": "\b", "t": "\t", "n": "\n", "f": "\f", "r": "\r",
           '"': '"', "\\": "\\"}


def toml_skip_string(text, index):
    """Index just past the single line string starting at index."""
    quote = text[index]
    index += 1
    while index < len(text):
        char = text[index]
        if char == "\\" and quote == '"':
            index += 2
            continue
        if char == "\n":
            break
        if char == quote:
            return index + 1
        index += 1
    raise ValueError("unterminated %s string" % quote)


def toml_skip_multiline(text, index):
    """Index just past the \"\"\" or ''' string starting at index.

    Getting this right is what stops the merge from treating the lines inside
    a multi-line string as key lines and rewriting them: input and output
    both parse, so nothing would ever notice the value had been mangled.
    """
    quote = text[index:index + 3]
    index += 3
    while index < len(text):
        if text[index] == "\\" and quote == '"""':
            index += 2
            continue
        if text.startswith(quote, index):
            run = 0
            while index + run < len(text) and text[index + run] == quote[0]:
                run += 1
            # A closing delimiter may be preceded by one or two more quotes,
            # which belong to the string; beyond that it is a new one.
            return index + (run if run <= 5 else 3)
        index += 1
    raise ValueError("unterminated multi-line string")


def toml_lex(text):
    """Split a TOML document into logical lines.

    A logical line is one key/value pair, one section header, or one comment
    or blank line, together with every physical line it spans: a multi-line
    array, inline table or triple-quoted string stays with the line that
    opened it. Returns [(text, eq)], eq being the offset within text of the
    '=' that separates key from value, or None when there is none.
    """
    records = []
    start = 0
    eq = None
    depth = 0
    index = 0
    while index < len(text):
        char = text[index]
        if char == "#":
            end = text.find("\n", index)
            index = len(text) if end < 0 else end
            continue
        if text.startswith('"""', index) or text.startswith("'''", index):
            index = toml_skip_multiline(text, index)
            continue
        if char == '"' or char == "'":
            index = toml_skip_string(text, index)
            continue
        if char in "[{":
            depth += 1
        elif char in "]}":
            depth -= 1
            if depth < 0:
                raise ValueError("unbalanced bracket")
        elif char == "=" and depth == 0 and eq is None:
            eq = index - start
        elif char == "\n" and depth == 0:
            records.append((text[start:index + 1], eq))
            start = index + 1
            eq = None
        index += 1
    if depth != 0:
        raise ValueError("unterminated array or inline table")
    if start < len(text):
        records.append((text[start:], eq))
    return records


def toml_unescape(body):
    if "\\" not in body:
        return body
    out = []
    index = 0
    while index < len(body):
        char = body[index]
        if char != "\\":
            out.append(char)
            index += 1
            continue
        index += 1
        code = body[index:index + 1]
        if code in ESCAPES:
            out.append(ESCAPES[code])
            index += 1
        elif code in ("u", "U"):
            width = 4 if code == "u" else 8
            out.append(chr(int(body[index + 1:index + 1 + width], 16)))
            index += 1 + width
        else:
            raise ValueError("bad escape in %r" % body)
    return "".join(out)


def toml_key_path(raw):
    """A key or header name as the tuple of parts TOML gives it.

    bare, "quoted", 'literal', dotted, and any spacing around the dots are
    four spellings of the same key. Comparing the spellings instead of the
    parts is how a merge ends up declaring the same table twice.
    """
    text = raw.strip()
    parts = []
    index = 0
    while True:
        while index < len(text) and text[index] in " \t":
            index += 1
        if index >= len(text):
            raise ValueError("empty key in %r" % raw.strip())
        char = text[index]
        if char == '"' or char == "'":
            end = toml_skip_string(text, index)
            body = text[index + 1:end - 1]
            parts.append(toml_unescape(body) if char == '"' else body)
            index = end
        else:
            end = index
            while end < len(text) and text[end] in BARE_KEY:
                end += 1
            if end == index:
                raise ValueError("cannot parse key %r" % raw.strip())
            parts.append(text[index:end])
            index = end
        while index < len(text) and text[index] in " \t":
            index += 1
        if index >= len(text):
            return tuple(parts)
        if text[index] != ".":
            raise ValueError("cannot parse key %r" % raw.strip())
        index += 1


def toml_header_path(raw):
    """(path, is_array_of_tables) for a section header line."""
    body = raw.strip()
    array = body.startswith("[[")
    index = 2 if array else 1
    while index < len(body):
        char = body[index]
        if char == '"' or char == "'":
            index = toml_skip_string(body, index)
            continue
        if char == "]":
            break
        index += 1
    else:
        raise ValueError("unterminated section header %r" % body)
    inner = body[2 if array else 1:index]
    rest = body[index + (2 if array else 1):]
    if array and not body[index:index + 2] == "]]":
        raise ValueError("unterminated section header %r" % body)
    if rest.strip() and not rest.strip().startswith("#"):
        raise ValueError("trailing text after section header %r" % body)
    return toml_key_path(inner), array


def toml_quote(part):
    if part and all(char in BARE_KEY for char in part):
        return part
    return '"%s"' % part.replace("\\", "\\\\").replace('"', '\\"')


def toml_join(path):
    return ".".join(toml_quote(part) for part in path)


def toml_parse(text):
    """Split a TOML document into sections of items.

    Every line of the document lands in exactly one item, so re-joining them
    reproduces the input byte for byte. An item's path is None for comments,
    blank lines and section headers, and the full key path otherwise. Raises
    ValueError on anything that cannot be classified or that TOML itself
    would reject -- that is how a truncated or otherwise broken file, and a
    merge that went wrong, are both recognised.
    """
    sections = [{"path": (), "header": None, "items": []}]
    # A missing final newline would otherwise glue an added key or section
    # onto the last line of the file.
    for raw, eq in toml_lex(ensure_newline(text)):
        stripped = raw.strip()
        if eq is None and stripped.startswith("["):
            path, array = toml_header_path(raw)
            if array:
                raise Unsupported(
                    "arrays of tables ([[...]]) are not something this merge "
                    "can match entry by entry")
            sections.append({"path": path, "header": raw, "items": []})
            sections[-1]["items"].append({"path": None, "text": raw, "eq": None})
            continue
        if eq is not None:
            path = sections[-1]["path"] + toml_key_path(raw[:eq])
            sections[-1]["items"].append({"path": path, "text": raw, "eq": eq})
            continue
        if stripped and not stripped.startswith("#"):
            raise ValueError("cannot parse %r" % stripped[:60])
        sections[-1]["items"].append({"path": None, "text": raw, "eq": None})
    toml_check(sections)
    return sections


def toml_check(sections):
    """Reject a document TOML itself would reject.

    A key set twice or a table declared twice is exactly what a merge that
    compared key spellings rather than key paths produces, and it stops the
    application from starting. Running this over the merged text before it
    goes anywhere near dst is what makes a readable result a property of the
    merge instead of a hope; running it over dst is what tells a genuinely
    broken file apart from one this parser merely found surprising.
    """
    keys = set()
    tables = set()
    implied = set()
    for section in sections:
        if section["header"] is not None:
            if section["path"] in tables or section["path"] in implied:
                raise ValueError("table [%s] is declared twice"
                                 % toml_join(section["path"]))
            tables.add(section["path"])
        for item in section["items"]:
            path = item["path"]
            if path is None:
                continue
            if path in keys:
                raise ValueError("key %s is set twice" % toml_join(path))
            keys.add(path)
            # A dotted key quietly creates the tables above it, and a later
            # header for one of those is not allowed to add to it.
            for cut in range(len(section["path"]) + 1, len(path)):
                implied.add(path[:cut])
    clash = keys & (tables | implied)
    if clash:
        raise ValueError("%s is both a key and a table"
                         % toml_join(sorted(clash)[0]))


def toml_render(sections):
    out = []
    for section in sections:
        for item in section["items"]:
            out.append(item["text"])
    return ensure_newline("".join(out))


def toml_last_line(sections):
    """Last physical line written so far, "" when nothing has been."""
    for section in reversed(sections):
        for item in reversed(section["items"]):
            lines = item["text"].splitlines()
            if lines:
                return lines[-1]
    return ""


def toml_ending(sections):
    """How dst ends its lines, so added lines are not the odd ones out."""
    for section in sections:
        for item in section["items"]:
            for line in item["text"].splitlines(True):
                if line.endswith("\r\n"):
                    return "\r\n"
                if line.endswith("\n"):
                    return "\n"
    return "\n"


def toml_reline(text, ending):
    out = []
    for line in text.splitlines(True):
        bare = line.rstrip("\r\n")
        out.append(bare + ending if bare != line else line)
    return "".join(out)


def toml_index(sections):
    """Where dst keeps things, by path: the item for a key, and the section
    an added key belongs in."""
    index = {"keys": {}, "sections": {}, "parents": {}, "implied": {}}
    index["sections"][()] = sections[0]
    for section in sections:
        if section["header"] is not None:
            index["sections"].setdefault(section["path"], section)
        for item in section["items"]:
            path = item["path"]
            if path is None:
                continue
            index["keys"].setdefault(path, []).append(item)
            index["parents"].setdefault(path[:-1], section)
            for cut in range(len(section["path"]) + 1, len(path)):
                index["implied"].setdefault(path[:cut], section)
    return index


def toml_set_value(target, item, ending):
    """dst keeps its spelling of the key and its spacing; src supplies the
    value. Rewriting the whole line would put src's spelling of the key into
    a file whose table layout may express it differently."""
    head = target["text"][:target["eq"] + 1]
    target["text"] = toml_reline(head + item["text"][item["eq"] + 1:], ending)


def toml_can_append(index, section, keys):
    """True when a whole src section is new to dst and can go in as it is,
    comments and all."""
    if not keys or section["header"] is None:
        return False
    if section["path"] in index["sections"] or section["path"] in index["implied"]:
        return False
    for item in keys:
        if item["path"] in index["keys"] or item["path"][:-1] in index["parents"]:
            return False
    return True


def toml_add_key(merged, index, src_section, item, ending):
    """Add a key dst does not have, where dst would have kept it."""
    path = item["path"]
    section = (index["parents"].get(path[:-1])
               or index["sections"].get(src_section["path"])
               or index["sections"].get(path[:-1])
               or index["implied"].get(path[:-1]))
    if section is None:
        if toml_last_line(merged).strip():
            merged.append({"path": (), "header": None,
                           "items": [{"path": None, "text": ending,
                                      "eq": None}]})
        section = {"path": src_section["path"],
                   "header": toml_reline(src_section["header"], ending),
                   "items": []}
        section["items"].append({"path": None, "text": section["header"],
                                 "eq": None})
        merged.append(section)
        index["sections"].setdefault(section["path"], section)
    relative = path[len(section["path"]):]
    if relative == path[len(src_section["path"]):]:
        head = item["text"][:item["eq"] + 1]
    else:
        # The key sits at a different depth here than it does in src, so it
        # has to be respelled to mean the same thing.
        head = toml_join(relative) + " ="
    added = {"path": path, "eq": len(head) - 1,
             "text": toml_reline(head + item["text"][item["eq"] + 1:], ending)}
    # At the end of the section, but above its trailing blank lines.
    items = section["items"]
    at = len(items)
    while at > 0 and not items[at - 1]["text"].strip():
        at -= 1
    items.insert(at, added)
    index["keys"].setdefault(path, []).append(added)
    index["parents"].setdefault(path[:-1], section)


def toml_merge(dst_sections, src_sections):
    """dst with every key src has set to src's value, everything else as it
    was: its comments, its blank lines, its key order, its line endings."""
    ending = toml_ending(dst_sections)
    merged = list(dst_sections)
    for src_section in src_sections:
        index = toml_index(merged)
        keys = [item for item in src_section["items"]
                if item["path"] is not None]
        if toml_can_append(index, src_section, keys):
            # A table dst has never heard of: append it whole, comments and
            # all, keeping one blank line between it and what came before.
            if toml_last_line(merged).strip():
                merged.append({"path": (), "header": None,
                               "items": [{"path": None, "text": ending,
                                          "eq": None}]})
            merged.append({
                "path": src_section["path"],
                "header": toml_reline(src_section["header"], ending),
                "items": [{"path": item["path"], "eq": item["eq"],
                           "text": toml_reline(item["text"], ending)}
                          for item in src_section["items"]]})
            continue
        for item in keys:
            found = index["keys"].get(item["path"])
            if found:
                for target in found:
                    toml_set_value(target, item, ending)
            else:
                toml_add_key(merged, index, src_section, item, ending)
    return merged


def toml_combine(old, new, dst_text):
    return toml_render(toml_merge(old, new))


# --- merging ---------------------------------------------------------------

HANDLERS = {"json": (json_parse, json_combine, "JSON"),
            "toml": (toml_parse, toml_combine, "TOML")}


def merge_text(fmt, src_text, dst_text, src, dst):
    """The shape both formats share.

    A src that does not parse is a bug in dotfiles: abort and leave dst
    alone. A dst that does not parse has already lost whatever it held, so
    recover it from src and say so loudly. A document that parses but uses
    something the merge cannot handle safely also aborts, because guessing
    would be a silent corruption. And the merged text is parsed once more
    before it is allowed near dst: if the result could only be expressed as
    an invalid document, writing nothing is the safe answer.
    """
    parse, combine, label = HANDLERS[fmt]
    try:
        new = parse(src_text)
    except Unsupported as err:
        sys.exit("merge: %s: %s" % (src, err))
    except ValueError as err:
        sys.exit("merge: %s: %s" % (src, err))
    if dst_text is None:
        return ensure_newline(src_text), False
    try:
        old = parse(dst_text)
    except Unsupported as err:
        sys.exit("merge: %s: %s" % (dst, err))
    except ValueError as err:
        report_replaced(dst, label, err)
        return ensure_newline(src_text), True
    text = combine(old, new, dst_text)
    try:
        parse(text)
    except (Unsupported, ValueError) as err:
        sys.exit("merge: not writing %s: the merged %s would be invalid (%s)"
                 % (dst, label, err))
    return text, False


# --- writing ---------------------------------------------------------------


def write_atomically(path, text):
    """Replace path with text through a temp file in the same directory.

    Same directory means same filesystem, so the rename is atomic: an
    interrupted run leaves either the old file or the new one, never half of
    either. The temp file is hidden because iTerm2 reads every file in
    DynamicProfiles, and one left behind by a SIGKILL would be read as a
    second profile with a duplicate Guid.

    A symlinked path is followed to the file it points at. dotfiles are
    often symlinked into place, and replacing the link with a regular file
    would leave the real file behind holding the old contents.
    """
    path = os.path.realpath(path)
    directory = os.path.dirname(path) or "."
    mode = 0o644
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except OSError:
        pass
    handle, temporary = tempfile.mkstemp(
        dir=directory, prefix="." + os.path.basename(path) + ".",
        suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="") as out:
            out.write(text)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: merge {json|toml} SRC DST")
    fmt, src, dst = argv
    if fmt not in HANDLERS:
        sys.exit("merge: unknown format %r" % fmt)
    src_text = read_text(src)
    dst_text = None
    damaged = None
    if os.path.exists(dst):
        try:
            dst_text = read_text(dst)
        except UnicodeDecodeError as err:
            # Not text at all: broken content, not a broken environment.
            damaged = err
        else:
            if not dst_text.strip():
                # An empty file has nothing to keep: same as not being there.
                dst_text = None
    if damaged is not None:
        report_replaced(dst, HANDLERS[fmt][2], damaged)
        text, replaced = ensure_newline(src_text), True
    else:
        text, replaced = merge_text(fmt, src_text, dst_text, src, dst)
    write_atomically(dst, text)
    if replaced:
        sys.exit(3)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except OSError as err:
        # A missing src, a missing parent directory, a file that cannot be
        # written: one line like every other message here, not a traceback in
        # the middle of setup's output.
        sys.exit("merge: %s" % err)
PYTHON_MERGE
  case "$status" in
    0) echo "Merged $(basename "$src") into $dst" ;;
    3) echo "Replaced $dst with $(basename "$src") -- see the warning above" ;;
    *) return "$status" ;;
  esac
}

# herdr (common)
if ! command -v herdr &>/dev/null; then
  echo "herdr not found. Copying config anyway."
fi
mkdir -p "$HOME/.config/herdr"
backup_then_copy "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml"

# OS-specific setup
case "$(uname -s)" in
  Darwin)
    # iTerm2 (Dynamic Profile)
    ITERM_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    mkdir -p "$ITERM_DIR"
    backup_then_copy "$DOTFILES_DIR/iterm2/herdr.json" "$ITERM_DIR/herdr.json"

    # The key mappings live in the herdr profile, so they only apply to windows
    # opened with it. Warn when it is not the default profile.
    ITERM_PROFILE_GUID="8f7b6c1e-3d2a-4e9b-9c5d-71a2b4e6f038"
    default_guid="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)"
    if [ "$default_guid" != "$ITERM_PROFILE_GUID" ]; then
      echo
      echo "WARNING: the 'herdr' profile is not iTerm2's default profile."
      echo "  The ctrl+cmd key mappings apply only to windows using that profile,"
      echo "  so herdr workspace switching will not work in other windows."
      echo "  Fix: iTerm2 > Settings > Profiles > herdr > Other Actions... > Set as Default,"
      echo "  then open a NEW window (existing windows keep their old profile)."
      echo
    fi

    # HackGen Nerd font (via Homebrew)
    if command -v brew &>/dev/null; then
      if brew list --cask font-hackgen-nerd &>/dev/null; then
        echo "font-hackgen-nerd already installed. Skipping."
      else
        brew install --cask font-hackgen-nerd
      fi
    else
      echo "Homebrew not found. Install the HackGen Nerd font manually (see README)."
    fi
    ;;
  *)
    # Windows Terminal (Windows side)
    WT_DIR="$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
    if [ -d "$WT_DIR" ]; then
      backup_then_copy "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json"
    else
      echo "Windows Terminal not found. Skipping."
    fi
    ;;
esac

echo "Done."
