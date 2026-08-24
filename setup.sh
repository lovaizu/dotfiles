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
#
# One run backs up several files with the same basename -- ~/.claude/settings.json
# and Windows Terminal's settings.json both land here -- and a timestamp only
# counts whole seconds, so the name is made unique by counting up instead of
# letting the second copy overwrite the first. The messages promise the user a
# file at that path; it has to still be there afterwards.
backup_file() {
  local dst="$1" stem bak count=1
  LAST_BACKUP=""
  if [ -e "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    stem="$BACKUP_DIR/$(basename "$dst").$(date +%Y%m%d%H%M%S)"
    bak="$stem.bak"
    while [ -e "$bak" ]; do
      bak="$stem-$count.bak"
      count=$((count + 1))
    done
    # Returns non-zero when there is a dst but it cannot be copied -- a
    # directory in its place, a file that cannot be read. backup_then_copy is
    # about to fail on the same file anyway; merge_config asks first.
    cp "$dst" "$bak" 2>/dev/null || return 1
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
# Three outcomes, and only the first of them can stop the setup:
#   1. src is broken or uses something the merge does not handle -- a bug in
#      dotfiles, so it aborts and leaves dst untouched.
#   2. dst is broken -- back it up, put the dotfiles copy there, warn, carry on.
#   3. the merge cannot be done (dst is in the way, the environment is, or the
#      result did not pass its own check) -- write nothing at all, warn, carry
#      on. Not writing to dst is a complete answer to "never leave dst
#      invalid", and it keeps one machine's damaged config from stopping every
#      other file in the setup from being installed.
#
# dst is replaced atomically. This is a read-modify-write, so it assumes the
# application is not writing the same file at the same moment: herdr and Claude
# Code both rewrite their config when settings change in their UI, and a change
# made there while setup.sh runs can be read before it and written back after.
# Run setup.sh with them closed, or expect to re-apply that change.
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
  # Without python3 an existing file is left exactly as it is. It is
  # deliberately not copied over instead: these are the files the application
  # also writes, so replacing one wholesale throws away the settings that live
  # only there -- the very thing merging exists to avoid. Warn and carry on,
  # the way the rest of setup.sh treats a missing tool.
  #
  # When dst is not there yet that reasoning does not apply -- there is
  # nothing on this machine to discard -- and refusing to write would leave a
  # fresh mac with no configuration at all, which is the case "clone, run
  # setup.sh" exists for. So copy.
  if ! python3 -c 'pass' &>/dev/null; then
    if [ ! -e "$dst" ]; then
      if cp "$src" "$dst" 2>/dev/null; then
        echo "Installed $dst"
      else
        echo
        echo "WARNING: $dst could not be written."
        echo "  The dotfiles settings for it were not applied."
        echo
      fi
      return 0
    fi
    echo
    echo "WARNING: python3 does not run, so $dst was left as it is."
    echo "  Merging config files needs it (macOS: xcode-select --install)."
    echo "  The dotfiles copy was NOT written over it on purpose: this file is"
    echo "  one the application writes too, and overwriting it would discard"
    echo "  the settings that exist only on this machine."
    echo
    return 0
  fi
  # Outcome 3 again: no backup, no merge. The merger promises the user a copy
  # of what it replaces, and it cannot make that promise without this.
  if ! backup_file "$dst"; then
    echo
    echo "WARNING: $dst could not be copied, so it was left as it is."
    echo "  The dotfiles settings for it were not applied."
    echo
    return 0
  fi
  MERGE_BACKUP="$LAST_BACKUP" python3 - "$format" "$src" "$dst" <<'PYTHON_MERGE' || status=$?
"""Merge the dotfiles copy of a config file into the installed one.

usage: python3 - {json|toml} SRC DST

Only the keys SRC has are touched; everything else in DST survives, including
-- for TOML -- its comments, blank lines and key order. Nothing here needs a
module newer than Python 3.9 (macOS ships 3.9, which has no TOML parser) and
nothing shells out, so no jq either.

The exit code says which of four things happened. 0: SRC was merged into an
existing DST. 5: there was no DST and SRC was installed as it is. 3: DST was
not usable and SRC replaced it wholesale, after a warning naming the backup.
4: the merge could not be done -- DST is in the way, or the environment is,
or the result failed its own check -- so nothing was written and DST is
exactly as it was, again after a warning. Anything else means SRC itself is
broken, which is a bug in dotfiles; DST is untouched and setup.sh stops.

What the merge guarantees about what it writes: the text is re-read by the
parser below before it is allowed near DST, so its key structure is one TOML
or JSON accepts -- no key set twice, no table declared twice, no name used as
both a key and a table, and every value syntactically well formed. It does
not guarantee that the application likes the *meaning* of what it holds: an
unknown key, or a value of the wrong type for the setting it names, is
carried across from SRC or left in DST exactly as it was found.

Messages go to stdout, where the rest of setup.sh's warnings go, so that
`./setup.sh > log` keeps them in the same order as the lines they explain.
"""

import datetime
import json
import os
import re
import stat
import sys
import tempfile


class Unsupported(Exception):
    """A document that parses but uses a construct the merge cannot handle."""


class Unmergeable(Exception):
    """DST cannot be merged into, for a reason that is not SRC's fault."""


# The exit codes setup.sh reads back, one per outcome. A broken SRC is not
# among them: it leaves through sys.exit with a message, like any other bug.
MERGED = 0
REPLACED = 3
SKIPPED = 4
INSTALLED = 5

# The file being merged into. Every message here is about that one file, and
# threading it through the merge itself would put a parameter on functions
# that have no other use for it.
TARGET = "the installed file"


def warn(message):
    sys.stdout.write("merge: %s: %s\n" % (TARGET, message))


def report(headline, *rest):
    """The loud form of warn: setup.sh's own WARNING shape, so that an outcome
    the user has to know about is not one lower case line among many."""
    lines = ["", "WARNING: " + headline]
    lines.extend("  " + line for line in rest)
    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")


def report_replaced(label, reason):
    """DST was not usable and the dotfiles copy has taken its place.

    This is the one outcome that loses settings, so it names the backup they
    can be recovered from.
    """
    lines = ["It has been replaced by the dotfiles copy, so any setting that",
             "existed only on this machine is gone from it."]
    backup = os.environ.get("MERGE_BACKUP", "")
    if backup:
        lines.append("The file as it was is kept at %s" % backup)
        lines.append("Copy anything still wanted out of there by hand.")
    report("%s is not usable %s (%s)." % (TARGET, label, reason), *lines)


def report_unmerged(reason):
    """The merge did not happen and DST was not written to at all."""
    report("%s was left as it is (%s)." % (TARGET, reason),
           "The dotfiles settings for it were not applied. Nothing was",
           "written, so it still holds exactly what it held before.",
           "Deal with the reason above and re-run ./setup.sh to apply them.")
    return SKIPPED


def read_text(path):
    # newline="" so a CRLF file arrives exactly as it sits on disk: the TOML
    # merge writes those endings back, while the JSON merge re-serialises the
    # whole document and so always writes LF. utf-8-sig so a byte order mark
    # from a Windows editor is skipped rather than read as content and
    # mistaken for a corrupt file.
    with open(path, encoding="utf-8-sig", newline="") as handle:
        return handle.read()


def ensure_newline(text, ending="\n"):
    # The ending matters for a CRLF file with no final newline: supplying an
    # LF there would leave one line of the file ending differently from the
    # rest of it.
    if text and not text.endswith("\n"):
        return text + ending
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
            if isinstance(current, (dict, list)) and current != value:
                # An array not listed in MERGE_BY_ID (hooks, actions,
                # keybindings, schemes) is a leaf: dotfiles' whole array wins
                # and any entry only this machine had goes with it. Same when
                # dst holds a different shape than src does for the key.
                warn("%s is replaced whole, so anything inside it that only "
                     "this machine had is gone" % json_path(here))
            merged[key] = value
    return merged


# Wider than this and the "indent" is not a layout any more, so the merge
# stops copying it: one mangled line should not re-indent the whole document.
MAX_INDENT = 8


def json_indent(text):
    """Indent unit of a JSON document, so the merge keeps its layout."""
    for line in text.splitlines():
        body = line.lstrip(" \t")
        if body and body != line:
            lead = line[:len(line) - len(body)]
            return "\t" if "\t" in lead else min(len(lead), MAX_INDENT)
    return 2


def json_combine(old, new, dst_text):
    if dst_text is not None and json_relax(dst_text) != dst_text:
        # JSONC input, plain JSON output: the merge works on the parsed
        # document, and comments are not part of it.
        warn("the // comments in it are not kept by the merge (the settings "
             "they sit next to are)")
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


def toml_unescape(body, multiline=False):
    """The text of a basic string, with a ValueError for an escape TOML has
    no meaning for. Used on quoted keys and to check quoted values."""
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
            digits = body[index + 1:index + 1 + width]
            if len(digits) < width:
                raise ValueError("bad escape in %r" % body)
            out.append(chr(int(digits, 16)))
            index += 1 + width
        elif multiline and code in " \t\r\n":
            # A backslash at the end of a line joins it to the next one and
            # eats the indentation, so nothing of it reaches the value.
            while index < len(body) and body[index] in " \t":
                index += 1
            if index >= len(body) or body[index] not in "\r\n":
                raise ValueError("bad escape in %r" % body)
            while index < len(body) and body[index] in " \t\r\n":
                index += 1
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
    if "\n" in inner:
        # The lexer keeps a bracket open across lines for the sake of
        # multi-line arrays; a header is not allowed to use that.
        raise ValueError("section header %r is split over lines"
                         % body.replace("\n", "\\n")[:40])
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


DEC_INT = r"[+-]?(?:0|[1-9](?:_?[0-9])*)"
FRACTION = r"\.[0-9](?:_?[0-9])*"
EXPONENT = r"[eE][+-]?[0-9](?:_?[0-9])*"
NUMBER_RE = re.compile(r"(?:%s)\Z" % "|".join([
    r"[+-]?(?:inf|nan)",
    DEC_INT + "(?:" + FRACTION + "(?:" + EXPONENT + ")?|" + EXPONENT + ")",
    DEC_INT,
    r"0x[0-9A-Fa-f](?:_?[0-9A-Fa-f])*",
    r"0o[0-7](?:_?[0-7])*",
    r"0b[01](?:_?[01])*"]))
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}\Z")
TIME_RE = re.compile(r"\d{2}:\d{2}:\d{2}(?:\.\d+)?\Z")
DATETIME_RE = re.compile(r"(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}:\d{2}(?:\.\d+)?)"
                         r"(?:[Zz]|([+-])(\d{2}):(\d{2}))?\Z")


def toml_temporal_ok(token):
    """True for a date or time whose numbers are a date or time that exists."""
    match = DATETIME_RE.match(token)
    date_part = time_part = None
    if match:
        date_part, time_part = match.group(1), match.group(2)
    elif DATE_RE.match(token):
        date_part = token
    elif TIME_RE.match(token):
        time_part = token
    else:
        return False
    try:
        if date_part:
            datetime.date(*(int(part) for part in date_part.split("-")))
        if time_part:
            hour, minute, second = time_part.split(":")
            datetime.time(int(hour), int(minute), int(float(second)))
        if match and match.group(3) is not None:
            if int(match.group(4)) > 23 or int(match.group(5)) > 59:
                return False
    except ValueError:
        return False
    return True


def toml_atom_ok(token):
    """True for an unquoted value: a boolean, a number, or a date/time."""
    return (token in ("true", "false") or bool(NUMBER_RE.match(token))
            or toml_temporal_ok(token))


def toml_skip_space(text, index, newlines=False):
    """Past blanks, and -- inside an array, where a line may break -- past
    the comments and newlines between one element and the next."""
    while index < len(text):
        char = text[index]
        if char in " \t" or (newlines and char in "\r\n"):
            index += 1
        elif newlines and char == "#":
            end = text.find("\n", index)
            index = len(text) if end < 0 else end
        else:
            break
    return index


def toml_check_body(body, escapes, multiline):
    """A string's contents: no raw control characters, no escape TOML has no
    meaning for."""
    allowed = "\t\r\n" if multiline else "\t"
    for char in body:
        if (char < " " or char == "\x7f") and char not in allowed:
            raise ValueError("a control character inside a string")
    if escapes:
        toml_unescape(body, multiline)


def toml_value_end(text, index):
    """Index just past the value at index; ValueError when there is not one.

    This is the line the merge draws around "the value is broken", and it is
    drawn there because the merge writes values through untouched: a value it
    accepts from DST is a value it writes back out. What it establishes: the
    value is present, strings are terminated and hold nothing TOML forbids,
    arrays and inline tables are balanced and punctuated, an inline table
    does not set the same key twice, and a bare word is a boolean, a number
    or a date that exists. What it does not: that an integer fits in 64 bits,
    that a \\u escape names a character rather than a surrogate half, or
    anything at all about whether the application wants this value here.
    """
    char = text[index:index + 1]
    if not char or char in "\r\n":
        raise ValueError("no value after the '='")
    if text.startswith('"""', index) or text.startswith("'''", index):
        end = toml_skip_multiline(text, index)
        toml_check_body(text[index + 3:end - 3], char == '"', True)
        return end
    if char in "\"'":
        end = toml_skip_string(text, index)
        toml_check_body(text[index + 1:end - 1], char == '"', False)
        return end
    if char == "[":
        return toml_array_end(text, index)
    if char == "{":
        return toml_table_end(text, index)[0]
    return toml_atom_end(text, index)


def toml_atom_end(text, index):
    end = index
    while end < len(text) and text[end] not in " \t\r\n,]}#":
        end += 1
    token = text[index:end]
    if DATE_RE.match(token) and text[end:end + 1] == " ":
        # A date and a time with a space between them are one value.
        rest = end + 1
        while rest < len(text) and text[rest] not in " \t\r\n,]}#":
            rest += 1
        if toml_atom_ok(token + "T" + text[end + 1:rest]):
            return rest
    if not toml_atom_ok(token):
        raise ValueError("%r is not a value TOML understands" % token[:40])
    return end


def toml_array_end(text, index):
    index += 1
    while True:
        index = toml_skip_space(text, index, True)
        if index >= len(text):
            raise ValueError("unterminated array")
        if text[index] == "]":
            return index + 1
        index = toml_skip_space(text, toml_value_end(text, index), True)
        if index < len(text) and text[index] == ",":
            index += 1
            continue
        if index >= len(text) or text[index] != "]":
            raise ValueError("expected ',' or ']' in an array")
        return index + 1


def toml_table_end(text, index):
    """(index just past the inline table at index, the key paths it sets)."""
    keys = []
    index = toml_skip_space(text, index + 1)
    if text[index:index + 1] == "}":
        return index + 1, keys
    while True:
        start = index
        index = toml_key_end(text, index)
        path = toml_key_path(text[start:index])
        if any(seen[:len(path)] == path or path[:len(seen)] == seen
               for seen in keys):
            raise ValueError("%s is set twice in one inline table"
                             % toml_join(path))
        keys.append(path)
        index = toml_skip_space(text, index)
        if text[index:index + 1] != "=":
            raise ValueError("expected '=' in an inline table")
        index = toml_skip_space(text, index + 1)
        index = toml_skip_space(text, toml_value_end(text, index))
        if text[index:index + 1] == ",":
            index = toml_skip_space(text, index + 1)
            continue
        if text[index:index + 1] != "}":
            raise ValueError("expected ',' or '}' in an inline table")
        return index + 1, keys


def toml_key_end(text, index):
    """Index just past the key at index, dots, quotes and all."""
    while True:
        if text[index:index + 1] in ('"', "'"):
            index = toml_skip_string(text, index)
        else:
            start = index
            while index < len(text) and text[index] in BARE_KEY:
                index += 1
            if index == start:
                raise ValueError("expected a key")
        after = toml_skip_space(text, index)
        if text[after:after + 1] != ".":
            return index
        index = toml_skip_space(text, after + 1)


def toml_split_value(text, eq):
    """(the value written after the '=', whatever follows it on the line).

    What follows may only be blank or a comment: a second value there is one
    of the ways a hand edited line goes wrong.
    """
    start = toml_skip_space(text, eq + 1)
    end = toml_value_end(text, start)
    rest = text[end:].strip()
    if rest and not rest.startswith("#"):
        raise ValueError("%r after the value" % rest[:40])
    return text[eq + 1:end], text[end:]


def toml_inline_keys(text, eq):
    """The keys an inline table value sets, or None for any other value."""
    start = toml_skip_space(text, eq + 1)
    if text[start:start + 1] != "{":
        return None
    return toml_table_end(text, start)[1]


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
    for raw, eq in toml_lex(ensure_newline(text, toml_ending_of(text))):
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

    Two kinds of breakage: a name used twice or used as two different things,
    which is exactly what a merge that compared key spellings rather than key
    paths produces, and a value that is not a value, which is what a file
    truncated or edited by hand tends to hold. Running this over the merged
    text before it goes anywhere near dst is what makes those two properties
    of the merge instead of hopes; running it over dst is what tells a
    genuinely broken file apart from one this parser merely found surprising.

    What it establishes is the structure and the syntax, not the meaning: see
    toml_value_end for where the line around a value is drawn.
    """
    keys = set()
    tables = set()
    implied = set()
    parents = set()
    for section in sections:
        if section["header"] is not None:
            if section["path"] in tables or section["path"] in implied:
                raise ValueError("table [%s] is declared twice"
                                 % toml_join(section["path"]))
            tables.add(section["path"])
            # [a.b] creates a as a table too, but writing [a] afterwards is
            # allowed, so the tables a header implies are kept apart from the
            # ones it declares: only the clash below may look at them.
            for cut in range(1, len(section["path"])):
                parents.add(section["path"][:cut])
        for item in section["items"]:
            path = item["path"]
            if path is None:
                continue
            if path in keys:
                raise ValueError("key %s is set twice" % toml_join(path))
            keys.add(path)
            toml_split_value(item["text"], item["eq"])
            # A dotted key quietly creates the tables above it, and a later
            # header for one of those is not allowed to add to it.
            for cut in range(len(section["path"]) + 1, len(path)):
                implied.add(path[:cut])
    clash = keys & (tables | implied | parents)
    if clash:
        raise ValueError("%s is both a key and a table"
                         % toml_join(sorted(clash)[0]))


def toml_text(sections):
    return "".join(item["text"] for section in sections
                   for item in section["items"])


def toml_render(sections):
    text = toml_text(sections)
    return ensure_newline(text, toml_ending_of(text))


def toml_last_line(sections):
    """Last physical line written so far, "" when nothing has been."""
    for section in reversed(sections):
        for item in reversed(section["items"]):
            lines = item["text"].splitlines()
            if lines:
                return lines[-1]
    return ""


def toml_ending_of(text):
    """How a document ends its lines, so added lines are not the odd ones
    out and a missing final newline is supplied in the file's own style."""
    return "\r\n" if "\r\n" in text else "\n"


def toml_ending(sections):
    return toml_ending_of(toml_text(sections))


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
    """dst keeps its spelling of the key, its spacing and anything it wrote
    after the value; src supplies the value and nothing else.

    Rewriting the whole line would put src's spelling of the key into a file
    whose table layout may express it differently, and would carry src's own
    end of line comment into a file it was not written about -- while losing
    the comment dst had there, which was.
    """
    value = toml_split_value(item["text"], item["eq"])[0]
    trailing = toml_split_value(target["text"], target["eq"])[1]
    old = toml_inline_keys(target["text"], target["eq"])
    if old is not None:
        new = toml_inline_keys(item["text"], item["eq"]) or []
        lost = [key for key in old if key not in new]
        if lost:
            warn("%s is written as one value, so %s in it is gone"
                 % (toml_join(target["path"]),
                    ", ".join(toml_join(key) for key in lost)))
    head = target["text"][:target["eq"] + 1]
    target["text"] = toml_reline(head + value + trailing, ending)


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


def toml_append_section(merged, src_section, items, ending):
    """Put a src section at the end of merged, one blank line clear of
    whatever is already there, with its lines in dst's line endings."""
    if toml_last_line(merged).strip():
        merged.append({"path": (), "header": None,
                       "items": [{"path": None, "text": ending, "eq": None}]})
    section = {"path": src_section["path"],
               "header": toml_reline(src_section["header"], ending),
               "items": [dict(item, text=toml_reline(item["text"], ending))
                         for item in items]}
    merged.append(section)
    return section


def toml_add_key(merged, index, src_section, item, ending):
    """Add a key dst does not have, where dst would have kept it."""
    path = item["path"]
    section = (index["parents"].get(path[:-1])
               or index["sections"].get(src_section["path"])
               or index["sections"].get(path[:-1])
               or index["implied"].get(path[:-1]))
    if section is None:
        section = toml_append_section(
            merged, src_section,
            [{"path": None, "text": src_section["header"], "eq": None}],
            ending)
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


def toml_adopt_comments(sections):
    """Give each section the comment lines written directly above its header.

    A comment above [table] is about that table, but a parse puts it in the
    section before it, where appending the table whole would leave it behind.
    """
    adopted = [dict(section, items=list(section["items"]))
               for section in sections]
    for position in range(1, len(adopted)):
        if adopted[position]["header"] is None:
            continue
        before = adopted[position - 1]["items"]
        at = len(before)
        while at > 0 and (before[at - 1]["path"] is None
                          and before[at - 1]["text"].lstrip().startswith("#")):
            at -= 1
        adopted[position]["items"][:0] = before[at:]
        del before[at:]
    return adopted


def toml_merge(dst_sections, src_sections):
    """dst with every key src has set to src's value, everything else as it
    was: its comments, its blank lines, its key order, its line endings."""
    ending = toml_ending(dst_sections)
    merged = list(dst_sections)
    for src_section in toml_adopt_comments(src_sections):
        index = toml_index(merged)
        keys = [item for item in src_section["items"]
                if item["path"] is not None]
        if toml_can_append(index, src_section, keys):
            # A table dst has never heard of: append it whole, comments and
            # all, keeping one blank line between it and what came before.
            toml_append_section(merged, src_section, src_section["items"],
                                ending)
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
    # dst_text is unused: the signature is json_combine's, so that merge_text
    # can call either without knowing which it has.
    return toml_render(toml_merge(old, new))


# --- merging ---------------------------------------------------------------

HANDLERS = {"json": (json_parse, json_combine, "JSON"),
            "toml": (toml_parse, toml_combine, "TOML")}


def merge_text(fmt, src_text, dst_text, src):
    """The shape both formats share, as (text to write, outcome).

    A src that does not parse, or that uses something the merge cannot
    handle, is a bug in dotfiles: abort and leave dst alone. A dst that does
    not parse has already lost whatever it held, so recover it from src and
    say so loudly. A dst that parses but is beyond the merge is nobody's
    fault and no reason to stop: leave it alone and carry on. And the merged
    text is parsed once more before it is allowed near dst: if the result
    could only be expressed as an invalid document, writing nothing is the
    safe answer.

    That last check is the TOML side's: json.dumps cannot produce JSON that
    json.loads then rejects, so for JSON it only ever confirms what the
    serialiser already guarantees.
    """
    parse, combine, label = HANDLERS[fmt]
    try:
        new = parse(src_text)
    except (Unsupported, ValueError) as err:
        sys.exit("merge: %s: %s" % (src, err))
    if dst_text is None:
        return ensure_newline(src_text), INSTALLED
    try:
        old = parse(dst_text)
    except Unsupported as err:
        raise Unmergeable(err)
    except ValueError as err:
        report_replaced(label, err)
        return ensure_newline(src_text), REPLACED
    text = combine(old, new, dst_text)
    try:
        parse(text)
    except (Unsupported, ValueError) as err:
        raise Unmergeable("the merged %s would be invalid: %s" % (label, err))
    return text, MERGED


# --- writing ---------------------------------------------------------------


def write_atomically(path, text):
    """Replace path with text through a temp file in the same directory.

    Same directory means same filesystem, so the rename is atomic: a run
    interrupted at any point leaves either the old file or the new one, never
    half of either. That is atomicity against the process stopping, which is
    what an interrupted setup.sh does; surviving a power cut as well would
    take an fsync of the directory too, and is not what this is for. The temp
    file is hidden because iTerm2 reads every file in DynamicProfiles, and
    one left behind by a SIGKILL would be read as a second profile with a
    duplicate Guid.

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


def merge_file(fmt, src_text, src, dst):
    dst_text = None
    if os.path.exists(dst):
        try:
            dst_text = read_text(dst)
        except UnicodeDecodeError as err:
            # Not text at all: broken content, not a broken environment.
            report_replaced(HANDLERS[fmt][2], err)
            write_atomically(dst, ensure_newline(src_text))
            return REPLACED
        if not dst_text.strip():
            # An empty file has nothing to keep: same as not being there.
            dst_text = None
    text, outcome = merge_text(fmt, src_text, dst_text, src)
    write_atomically(dst, text)
    return outcome


def main(argv):
    global TARGET
    if len(argv) != 3:
        sys.exit("usage: merge {json|toml} SRC DST")
    fmt, src, dst = argv
    if fmt not in HANDLERS:
        sys.exit("merge: unknown format %r" % fmt)
    TARGET = dst
    try:
        src_text = read_text(src)
    except UnicodeDecodeError as err:
        sys.exit("merge: %s: %s" % (src, err))
    except OSError as err:
        # src comes from the repository: if it cannot be read, the checkout
        # is wrong and every other file is suspect too.
        sys.exit("merge: %s: %s" % (src, err.strerror or err))
    try:
        return merge_file(fmt, src_text, src, dst)
    except Unmergeable as err:
        return report_unmerged(err)
    except OSError as err:
        # A missing parent directory, a read-only file, a dst that is really
        # a directory. err itself names the temp file the write was going
        # through, which means nothing to anyone: name dst and the reason.
        return report_unmerged(err.strerror or err)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PYTHON_MERGE
  # The three outcomes above, in the merger's exit codes. Anything else is
  # outcome 1 -- a broken src -- and stops the setup.
  case "$status" in
    0) echo "Merged $(basename "$src") into $dst" ;;
    3) echo "Replaced $dst with $(basename "$src") -- see the warning above" ;;
    4) echo "Left $dst as it is -- see the warning above" ;;
    5) echo "Installed $dst" ;;
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
