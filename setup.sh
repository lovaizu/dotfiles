#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backups go to a directory of their own: iTerm2 loads every file in
# DynamicProfiles, so a backup left beside the profile is parsed as a second
# profile with a duplicate Guid.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"

# Copy an existing dst into BACKUP_DIR. Does nothing when dst is not there yet.
backup_file() {
  local dst="$1" bak
  if [ -e "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    bak="$BACKUP_DIR/$(basename "$dst").$(date +%Y%m%d%H%M%S).bak"
    cp "$dst" "$bak"
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
# is a bug in dotfiles: it aborts the setup, leaving dst untouched.
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
  local format="$1" src="$2" dst="$3"
  if ! command -v python3 &>/dev/null; then
    echo "python3 not found: cannot merge $src into $dst" >&2
    return 1
  fi
  backup_file "$dst"
  python3 - "$format" "$src" "$dst" <<'PYTHON_MERGE'
"""Merge the dotfiles copy of a config file into the installed one.

usage: python3 - {json|toml} SRC DST

Only the keys SRC has are touched; everything else in DST survives, including
-- for TOML -- its comments, blank lines and key order. Nothing here needs a
module newer than Python 3.9 (macOS ships 3.9, which has no tomllib) and
nothing shells out, so no jq either.
"""

import json
import os
import stat
import sys
import tempfile


def warn(message):
    sys.stderr.write("merge: %s\n" % message)


def read_text(path):
    # newline="" so CRLF survives being read and written back unchanged.
    with open(path, encoding="utf-8", newline="") as handle:
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


def merge_by_id(old, new, id_key):
    merged = list(old)
    at = {}
    for position, item in enumerate(merged):
        key = element_id(item, id_key)
        if key is not None:
            at.setdefault(key, position)
    for item in new:
        key = element_id(item, id_key)
        if key is not None and key in at:
            merged[at[key]] = item
        else:
            # Unknown to dst, or an element with no id to match on: append.
            if key is not None:
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
            merged[key] = merge_by_id(current, value, MERGE_BY_ID[here])
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


def json_object(text, what):
    value = json.loads(text)
    if not isinstance(value, dict):
        raise ValueError("%s is not a JSON object" % what)
    return value


def merge_json_text(src_text, dst_text, src, dst):
    try:
        new = json_object(src_text, src)
    except ValueError as err:
        sys.exit("merge: %s: %s" % (src, err))
    if dst_text is None:
        return ensure_newline(src_text)
    try:
        old = json_object(dst_text, dst)
    except ValueError as err:
        warn("%s is not usable JSON (%s); writing the dotfiles copy" % (dst, err))
        return ensure_newline(src_text)
    return json.dumps(merge_objects(old, new), indent=json_indent(dst_text),
                      ensure_ascii=False) + "\n"


# --- TOML ------------------------------------------------------------------
#
# Line based on purpose: rewriting the file through a parser would drop the
# comments and the ordering the application (or the user) put there, and
# Python 3.9 has no TOML parser to rewrite it with anyway. Multi-line basic
# and literal strings are the one construct not understood -- no config we
# manage uses them.


def toml_scan(line, depth):
    """Return (line without its trailing comment, bracket depth after it).

    Quotes are honoured, so a '#' or a bracket inside a string does not count.
    depth is what is still open from a multi-line array or inline table.
    """
    code = []
    quote = None
    index = 0
    while index < len(line):
        char = line[index]
        if quote is not None:
            code.append(char)
            if quote == '"' and char == "\\" and index + 1 < len(line):
                code.append(line[index + 1])
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if char in "\"'":
            quote = char
        elif char == "#":
            break
        elif char in "[{":
            depth += 1
        elif char in "]}":
            depth -= 1
        code.append(char)
        index += 1
    return "".join(code), depth


def toml_section_name(code):
    """Normalised name of a section header, [[array]] kept distinct."""
    inner = code.strip()
    if inner.startswith("[[") and inner.endswith("]]"):
        return "[[%s]]" % inner[2:-2].strip()
    return inner[1:-1].strip()


def toml_parse(text):
    """Split a TOML document into sections of (key, lines) items.

    Every line of the document lands in exactly one item, so re-joining them
    reproduces the input byte for byte. key is None for comments, blank lines
    and section headers; the implicit section before the first header is "".
    Raises ValueError on a line that cannot be classified -- that is how a
    truncated or otherwise broken file is recognised.
    """
    sections = [{"name": "", "items": []}]
    # A missing final newline would otherwise glue an added key or section
    # onto the last line of the file.
    lines = ensure_newline(text).splitlines(True)
    depth = 0
    index = 0
    while index < len(lines):
        line = lines[index]
        code, next_depth = toml_scan(line, depth)
        if depth != 0:
            # Continuation of a multi-line value: kept with its opening line.
            sections[-1]["items"][-1][1].append(line)
            depth = next_depth
            index += 1
            continue
        stripped = code.strip()
        if stripped.startswith("["):
            if not stripped.endswith("]") or next_depth != 0:
                raise ValueError("unterminated section header on line %d" % (index + 1))
            sections.append({"name": toml_section_name(stripped), "items": []})
            sections[-1]["items"].append((None, [line]))
            index += 1
            continue
        if "=" in stripped:
            sections[-1]["items"].append((stripped.split("=", 1)[0].strip(), [line]))
            depth = next_depth
            index += 1
            continue
        if stripped:
            raise ValueError("cannot parse line %d: %r" % (index + 1, line))
        sections[-1]["items"].append((None, [line]))
        index += 1
    if depth != 0:
        raise ValueError("unterminated value at end of file")
    return sections


def toml_keys(section):
    """(key order, key -> lines) for a section; the first spelling wins."""
    order = []
    keys = {}
    for key, lines in section["items"]:
        if key is not None and key not in keys:
            keys[key] = lines
            order.append(key)
    return order, keys


def toml_render(sections):
    out = []
    for section in sections:
        for _, lines in section["items"]:
            out.extend(lines)
    return ensure_newline("".join(out))


def toml_last_line(sections):
    """Last physical line written so far, "" when nothing has been."""
    for section in reversed(sections):
        for _, lines in reversed(section["items"]):
            if lines:
                return lines[-1]
    return ""


def toml_ending(sections):
    """How dst ends its lines, so added lines are not the odd ones out."""
    for section in sections:
        for _, lines in section["items"]:
            for line in lines:
                if line.endswith("\r\n"):
                    return "\r\n"
                if line.endswith("\n"):
                    return "\n"
    return "\n"


def toml_reline(lines, ending):
    relined = []
    for line in lines:
        bare = line.rstrip("\r\n")
        relined.append(bare + ending if bare != line else line)
    return relined


def toml_merge(dst_sections, src_sections):
    """dst with every key src has set to src's line, everything else as it was.

    A section name repeated in dst is not valid TOML for tables and we manage
    no arrays of tables, so keys are replaced in every section of that name
    and keys src alone has are added to the first one.
    """
    ending = toml_ending(dst_sections)
    first = {}
    for section in dst_sections:
        first.setdefault(section["name"], section)
    merged = list(dst_sections)
    for src_section in src_sections:
        order, replacement = toml_keys(src_section)
        replacement = dict((key, toml_reline(lines, ending))
                           for key, lines in replacement.items())
        target = first.get(src_section["name"])
        if target is None:
            # A section dst never had: append it whole, comments and all,
            # keeping one blank line between it and what came before.
            if toml_last_line(merged).strip():
                merged.append({"name": None, "items": [(None, [ending])]})
            merged.append({"name": src_section["name"],
                           "items": [(key, toml_reline(lines, ending))
                                     for key, lines in src_section["items"]]})
            continue
        replaced = set()
        for section in dst_sections:
            if section["name"] != src_section["name"]:
                continue
            items = section["items"]
            for position, (key, _) in enumerate(items):
                if key in replacement:
                    items[position] = (key, replacement[key])
                    replaced.add(key)
        missing = [key for key in order if key not in replaced]
        if missing:
            # At the end of the section, but above its trailing blank lines.
            items = target["items"]
            at = len(items)
            while at > 0 and not "".join(items[at - 1][1]).strip():
                at -= 1
            items[at:at] = [(key, replacement[key]) for key in missing]
    return merged


def merge_toml_text(src_text, dst_text, src, dst):
    try:
        src_sections = toml_parse(src_text)
    except ValueError as err:
        sys.exit("merge: %s: %s" % (src, err))
    if dst_text is None:
        return ensure_newline(src_text)
    try:
        dst_sections = toml_parse(dst_text)
    except ValueError as err:
        warn("%s is not usable TOML (%s); writing the dotfiles copy" % (dst, err))
        return ensure_newline(src_text)
    return toml_render(toml_merge(dst_sections, src_sections))


# --- writing ---------------------------------------------------------------


def write_atomically(path, text):
    """Replace path with text through a temp file in the same directory.

    Same directory means same filesystem, so the rename is atomic: an
    interrupted run leaves either the old file or the new one, never half of
    either.
    """
    directory = os.path.dirname(os.path.abspath(path))
    mode = 0o644
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except OSError:
        pass
    handle, temporary = tempfile.mkstemp(
        dir=directory, prefix=os.path.basename(path) + ".", suffix=".tmp")
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
    src_text = read_text(src)
    dst_text = None
    if os.path.exists(dst):
        try:
            dst_text = read_text(dst)
        except (OSError, UnicodeDecodeError) as err:
            warn("%s cannot be read (%s); writing the dotfiles copy" % (dst, err))
        else:
            if not dst_text.strip():
                # An empty file has nothing to keep: same as not being there.
                dst_text = None
    if fmt == "json":
        text = merge_json_text(src_text, dst_text, src, dst)
    elif fmt == "toml":
        text = merge_toml_text(src_text, dst_text, src, dst)
    else:
        sys.exit("merge: unknown format %r" % fmt)
    write_atomically(dst, text)


main(sys.argv[1:])
PYTHON_MERGE
  echo "Merged $(basename "$src") into $dst"
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
