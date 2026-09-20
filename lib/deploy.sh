# The deploy engine: turns "put this repo file at this path" into an
# idempotent, backed-up, interrupt-safe copy. Nothing here knows what is
# being deployed -- callers only ever call deploy().

FAILURES=()

XDG_IGNORED=""
xdg_base=""
# A relative XDG base is invalid per spec and must be ignored -- taken
# literally it deploys under wherever the run started (measured). Returned
# via xdg_base, not stdout, so XDG_IGNORED can still be set in the same call.
set_xdg_base() {
  local name="$1" value="${2:-}" fallback="$3"
  case "$value" in
    /*)
      xdg_base="$value"
      return 0
      ;;
  esac
  if [ -n "$value" ]; then
    XDG_IGNORED="${XDG_IGNORED}${XDG_IGNORED:+, }$name"
  fi
  xdg_base="$fallback"
}

# The leading dot is what makes a half-written file safe in DynamicProfiles
# (iTerm2 skips dotfiles and files ending in ~, measured in the binary's
# strings). Built here and nowhere else, so sweep_tmp_files matches the
# same files.
tmp_prefix_for() {
  printf '%s/.%s.dotfiles-tmp.' "$(dirname "$1")" "$(basename "$1")"
}

tmp_for() {
  printf '%s%s' "$(tmp_prefix_for "$1")" "$$"
}

# Keyed on the managed file's repo-relative path, not the destination's
# basename -- two destinations can share a basename (claude/settings.json
# and windows-terminal/settings.json both land in settings.json); repo
# paths never collide, so this needs no hand-kept convention.
backup_path_for() {
  printf '%s/%s' "$BACKUP_DIR" "$1"
}

sweep_tmp_files() {
  rm -f "$(tmp_prefix_for "$1")"* 2>/dev/null || true
}

DEPLOY_TMP=""
BACKUP_TMP=""
remove_pending_tmp() {
  rm -f "$DEPLOY_TMP" "$BACKUP_TMP" 2>/dev/null || true
  DEPLOY_TMP=""
  BACKUP_TMP=""
}

# INT/TERM exit rather than clean up and return: returning would leave bash
# to carry on to the next deployment.
#
# REACHED_END: with an EXIT trap set, bash 3.2 turns a set -u fatal into
# exit 0, and $? inside the trap can't recover it (measured, bash 3.2.57).
# Only the two intentional exits in setup.sh set this flag, so an exit 0
# that didn't come from one of them is turned into 1. Other ways out are
# left alone -- SIGTERM still exits 143 through its own trap.
REACHED_END=""
cleanup() {
  local st=$?
  remove_pending_tmp
  if [ -z "${REACHED_END:-}" ] && [ "$st" -eq 0 ]; then
    exit 1
  fi
  exit "$st"
}
trap cleanup EXIT
trap 'remove_pending_tmp; exit 130' INT
trap 'remove_pending_tmp; exit 143' TERM

# Returns 0 so record_failure does too: its caller in the WSL branch runs
# under errexit, and a status taken from the last echo would be a coin toss.
warn() {
  local what="$1" line
  shift
  echo >&2
  echo "WARNING: $what" >&2
  for line in "$@"; do
    echo "  $line" >&2
  done
  echo >&2
  return 0
}

record_failure() {
  FAILURES+=("$1")
  warn "$@"
}

# The whole-second timestamp is why the count-up exists: it stops a second
# backup taken in the same second from overwriting the first, after deploy
# has already promised the caller that path (measured).
#
# The path returns on stdout, not through a global: a global outlives the
# call, and a later deploy's cleanup then deleted a backup already promised
# to the user (measured).
backup_file() {
  local dst="$1" tmp="$2" src_rel="$3" stem bak count=1
  # -e follows a symlink, so a dangling one takes no backup: deploy replaces
  # the link with a regular file and there is nothing to restore.
  [ -e "$dst" ] || return 0
  stem="$(backup_path_for "$src_rel").$(date +%Y%m%d%H%M%S)"
  bak="$stem.bak"
  while [ -e "$bak" ]; do
    bak="$stem-$count.bak"
    count=$((count + 1))
  done
  mkdir -p "$(dirname "$bak")" || return 1
  # Via a temp file and rename: a Ctrl-C mid-copy exits through the INT trap
  # before cp's status could be tested, leaving a part-written .bak behind
  # (measured).
  if ! cp "$dst" "$tmp" || ! mv -f "$tmp" "$bak"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$bak"
}

# Always returns 0; callers rely on it. A real status once cost more than it
# was worth: every call needed `|| true`, which turns off errexit for the
# whole call, and a bare line added here then failed silently, ending the
# run 0 having deployed nothing (measured).
deploy() {
  local src="$1" dst="$2" src_rel dir backup="" was_link=""
  # Callers always pass src as "$DOTFILES_DIR/...", so stripping that
  # prefix gives the repo-relative path backup_path_for keys backups on.
  src_rel="${src#"$DOTFILES_DIR"/}"
  sweep_tmp_files "$dst"
  sweep_tmp_files "$(backup_path_for "$src_rel")"
  if cmp -s "$src" "$dst" 2>/dev/null; then
    echo "Up to date: $dst"
    return 0
  fi
  if [ -L "$dst" ]; then
    was_link=1
  fi
  dir="$(dirname "$dst")"
  DEPLOY_TMP="$(tmp_for "$dst")"
  BACKUP_TMP="$(tmp_for "$(backup_path_for "$src_rel")")"
  if mkdir -p "$dir" && cp "$src" "$DEPLOY_TMP" && backup="$(backup_file "$dst" "$BACKUP_TMP" "$src_rel")"; then
    BACKUP_TMP=""
    # -f: a read-only dst makes mv ask, but only when stdin is a tty -- which
    # is exactly a person running this. The prompt defaults to "no" and mv
    # exits 0 having replaced nothing, announcing a file it never wrote
    # (measured under a pty).
    if mv -f "$DEPLOY_TMP" "$dst"; then
      DEPLOY_TMP=""
      if [ -n "$backup" ]; then
        echo "Backed up the previous $dst to $backup"
      fi
      echo "Installed $dst"
      if [ -n "$was_link" ]; then
        warn "$dst was a symlink and is not one any more." \
          "The link has been replaced by a regular file holding the dotfiles" \
          "copy; what it pointed at was left as it was. A backup taken here" \
          "holds the target's contents rather than the link, so putting the" \
          "backup back restores the contents and not the link -- and a link" \
          "pointing at nothing left no backup at all." \
          "Fix: if the link was wanted, make it again now."
      fi
      return 0
    fi
  fi
  remove_pending_tmp
  if [ -n "$backup" ]; then
    rm -f "$backup" || true
  fi
  record_failure "$dst was not deployed." \
    "The command that failed said why just above. Nothing was replaced: the" \
    "copy is renamed into place only once it is whole, and a rename that" \
    "fails replaces nothing, so the file is as it was and no backup was" \
    "kept. The directory holding the file may be left behind empty, since it" \
    "is made before anything is copied into it. The backup directory is made" \
    "later, only once the new file has been copied, so it is there only if it" \
    "was taking the backup that failed." \
    "The rest of the setup runs below and this run ends non-zero." \
    "Fix: a \"No such file or directory\" naming a path under" \
    "  $DOTFILES_DIR" \
    "is a file missing from the repository itself -- re-check the clone." \
    "Anything else is this machine: make the file, the directory holding" \
    "it, or the backup directory" \
    "  $BACKUP_DIR" \
    "writable, or move aside something standing where the file belongs." \
    "Then re-run ./setup.sh."
  return 0
}
