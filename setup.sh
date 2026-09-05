#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backups go to a directory of their own: iTerm2 loads every file in
# DynamicProfiles, so a backup left beside the profile is parsed as a second
# profile with a duplicate Guid.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups"

# What this run could not deploy, one entry per file. A deployment that fails
# is a warning and the setup carries on -- nothing deployed here is read by
# anything later in this script, so one refusal cannot derail the deployments
# after it, and a home directory that will not take one file is no reason to
# skip the ones that would have worked. That is about this script's order of
# work, not about the files fitting each other once they are in place: an
# iTerm2 profile that lands while herdr's config.toml is refused sends the key
# sequences dotfiles chose to a herdr still configured the way this machine had
# it. What makes that safe to leave is the retry -- the next run makes the same
# judgement again and either quietly agrees or names the same file. This list
# is what keeps a partial run from passing for success: the run names every
# entry at the end and exits non-zero.
FAILURES=()

# Every half-written file this script makes is a dot file named after where it
# is going, in the directory it is going to, and is renamed into place once it
# is whole. $$ keeps two runs from writing the same name.
tmp_for() {
  printf '%s/.%s.dotfiles-tmp.%s' "$(dirname "$1")" "$(basename "$1")" "$$"
}

# Remove the temp files earlier runs left beside a destination. A run killed
# outright (SIGKILL, a power cut) leaves one, and since the name carries that
# run's pid no later run ever writes over it -- without this sweep nothing would
# ever remove it (measured). Leftovers matter most in iTerm2's DynamicProfiles,
# where every file in the directory is read: that is the same reason backups are
# kept in a directory of their own, and the temp file must not undo it. A
# concurrent run's temp file would be swept too; two setup.sh at once is not a
# case this script serves.
sweep_tmp_files() {
  rm -f "$(dirname "$1")/.$(basename "$1").dotfiles-tmp."* 2>/dev/null || true
}

# The temp file deploy is writing, so an interrupt does not leave it behind.
# Empty whenever there is none.
DEPLOY_TMP=""
remove_deploy_tmp() {
  if [ -n "$DEPLOY_TMP" ]; then
    # A dst whose directory has gone makes even rm complain; nothing here is
    # worth a message.
    rm -f "$DEPLOY_TMP" 2>/dev/null || true
    DEPLOY_TMP=""
  fi
}
# INT and TERM exit rather than only cleaning up: a trap that returns leaves
# bash carrying on to the next deployment, so Ctrl-C would stop nothing.
trap remove_deploy_tmp EXIT
trap 'remove_deploy_tmp; exit 130' INT
trap 'remove_deploy_tmp; exit 143' TERM

# Say that something was not deployed and remember it for the summary. The
# detail lines are the caller's, because what to do about it differs; what is
# the same everywhere is that the run goes on and ends non-zero.
record_failure() {
  local what="$1" line
  shift
  FAILURES+=("$what")
  echo
  echo "WARNING: $what"
  for line in "$@"; do
    echo "  $line"
  done
  echo
}

# Copy an existing dst into BACKUP_DIR and print where it went. Prints nothing
# when dst is not there yet. The timestamp counts whole seconds, so two runs
# that back up the same file inside one second arrive at the same name, and the
# second is made unique by counting up rather than writing over the first: the
# message deploy prints promises the user a file at that path. Two runs on
# their own never get that far -- the second finds dst already matching, says
# Up to date and backs up nothing -- so it takes a dst that changes between
# them, which is what herdr does to this config.toml every time it saves a
# theme (measured: with the theme name rewritten in dst before each of two
# runs, the pair left config.toml.<ts>.bak and config.toml.<ts>-1.bak).
#
# The path goes back to the caller on stdout rather than through a global. A
# global outlives the call: it would still hold one file's backup when a later
# deploy fails, and that deploy's cleanup would delete a backup the run had
# already promised the user (measured: a second run where config.toml differs
# and the iTerm2 profile deployed after it cannot be written -- with a global,
# the config.toml backup the run had just announced was gone by the end of it;
# taken on stdout into a local, it is still there).
backup_file() {
  local dst="$1" base stem bak count=1 tmp
  [ -e "$dst" ] || return 0
  # No directory, no backup, and a backup is what the caller is about to
  # promise the user -- so this is a failure like any other here.
  mkdir -p "$BACKUP_DIR" || return 1
  base="$(basename "$dst")"
  stem="$BACKUP_DIR/$base.$(date +%Y%m%d%H%M%S)"
  bak="$stem.bak"
  while [ -e "$bak" ]; do
    bak="$stem-$count.bak"
    count=$((count + 1))
  done
  # Written to a temp file and renamed, the way a deployment is. A copy that
  # dies partway must not be left under a name that says it is a whole backup,
  # and checking cp's exit status cannot do that alone: a Ctrl-C during the copy
  # leaves the script through the INT trap before any test of it could run, and
  # a part-written .bak stayed behind under that name (measured). Under a temp
  # name a half-written copy claims nothing and the next run sweeps it.
  #
  # Non-zero when there is a dst that cannot be copied: a directory in its
  # place, a file that cannot be read, a disk that fills up. cp says why on
  # stderr and deploy turns it into a warning.
  tmp="$(tmp_for "$BACKUP_DIR/$base")"
  sweep_tmp_files "$BACKUP_DIR/$base"
  if ! cp "$dst" "$tmp" || ! mv -f "$tmp" "$bak"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$bak"
}

# Every managed file is deployed by this one call, and by nothing else.
# dotfiles is the source of truth, so the whole file is replaced: a setting
# made on the machine that dotfiles does not carry does not survive the next
# run -- to keep one, put it in dotfiles.
#
# A dst that already holds the dotfiles copy is left alone. There is nothing to
# write, and a backup of a file that is byte-for-byte the one in the repository
# would be litter that every later run adds to.
#
# The new contents go to a temp file beside dst and are renamed over it. rename
# within a directory is atomic, so a run stopped partway leaves dst holding the
# old file or the new one and never a mix of the two. What half a managed file
# would cost differs by format, and the quieter half is the worse one. Half a
# JSON file is not a document at all: only the cut that drops the trailing
# newline parses (measured with Python's json, standing in for iTerm2 and
# Windows Terminal, which cannot be run on a broken file from here). Half of
# config.toml usually still is a document: cut at a line boundary it is usually
# valid TOML with whole tables gone, and most cuts leave no [keys] table at
# all -- which asks nothing of herdr, so the machine gets herdr's fallbacks and
# the workspace switching this repository exists for is not there. herdr itself
# calls such a cut "config: ok" (measured with herdr config check): no error
# anywhere, which is the case for the rename rather than against it.
# Renaming also settles what to do with the backup: everything that can fail
# here fails before the rename, with dst untouched, so a backup taken a moment
# earlier is a second copy of a file that is still in place and goes again.
# Without that, a dst that cannot be written would leave one more identical
# .bak behind on every run.
#
# What renaming costs: it needs the directory writable rather than the file, so
# a dst whose directory is read-only is a failure here even where writing
# through the existing file would have worked, and a dst that is replaced comes
# out with the repository's mode rather than its own. A dst that is a symlink
# whose target differs is replaced by the file itself and the link's target is
# left alone (measured) -- the opposite of writing through it, and the safer way
# round, since the target is somewhere this script does not manage. A symlink
# whose target already holds the dotfiles copy never gets that far: the check
# above reads through the link, finds no difference and returns, so that link
# stays a link (measured). The mode a rewritten dst ends up with is the
# repository's less the umask (measured: under umask 077, a 644 config.toml
# lands as 600).
#
# Returns non-zero, having already warned and recorded it, when the file was
# not deployed. Callers add `|| true` so that set -e does not turn the warning
# back into an abort.
deploy() {
  local src="$1" dst="$2" dir backup=""
  # Before the check below rather than after it: a dst that is already correct
  # still has to come out of a directory with no leftovers standing in it, and
  # a run killed before the rename leaves both an old dst and a temp file.
  sweep_tmp_files "$dst"
  # cmp -s keeps quiet about a difference but not about a dst it cannot open,
  # and a lone "Is a directory" naming neither the managed file nor what to do
  # about it is worse than no message. One of the commands below runs into the
  # same thing and its complaint arrives with the warning that explains it.
  if cmp -s "$src" "$dst" 2>/dev/null; then
    echo "Up to date: $dst"
    return 0
  fi
  dir="$(dirname "$dst")"
  DEPLOY_TMP="$(tmp_for "$dst")"
  # backup is local, and empty until backup_file has actually taken one, so the
  # cleanup below can only ever remove this file's own backup.
  if mkdir -p "$dir" && cp "$src" "$DEPLOY_TMP" && backup="$(backup_file "$dst")"; then
    # -f because a read-only dst makes mv ask -- but only when stdin is a tty,
    # which is exactly how a person runs this. The prompt defaults to "no" and
    # mv then exits 0 having replaced nothing, so the run announced a file it
    # had not written and left the temp file behind (measured under a pty). -f
    # is also what mv already did with no tty, so this is the behaviour every
    # earlier measurement of this script saw.
    if mv -f "$DEPLOY_TMP" "$dst"; then
      # The rename took the temp file away, so there is nothing left to clean.
      DEPLOY_TMP=""
      # Announced after the rename, so the run only ever promises a backup of
      # contents that have actually been replaced.
      if [ -n "$backup" ]; then
        echo "Backed up existing config to $backup"
      fi
      echo "Installed $dst"
      return 0
    fi
  fi
  remove_deploy_tmp
  # Nothing above reached the rename, so dst is as it was and this backup is a
  # copy of a file that is still there. Keeping it would add one more identical
  # .bak per run for as long as the cause lasts.
  if [ -n "$backup" ]; then
    rm -f "$backup"
  fi
  record_failure "$dst was not deployed." \
    "The command that failed said why just above. The file still holds what" \
    "it held before, and no backup was kept: the copy is renamed into place" \
    "only once it is whole, so a failure here leaves nothing to undo." \
    "The rest of the setup runs below and this run ends non-zero." \
    "Fix: clear whatever that message names -- make the file, the directory" \
    "holding it, or $BACKUP_DIR writable, or move aside" \
    "something standing where the file belongs -- then re-run ./setup.sh."
  return 1
}

# herdr (common)
# herdr writes this file itself -- it saves the theme name and the onboarding
# flag back into it -- and the overwrite is what corrects that: dotfiles holds
# the values this machine is meant to have, so a theme picked in herdr's UI
# goes back to the dotfiles one on the next run.
if ! command -v herdr &>/dev/null; then
  # Says what is true of herdr, not what this run is about to do: the deploy
  # below may well write nothing, and a run that changes nothing should not read
  # as an install.
  echo "herdr not found. Its config is managed here all the same:"
fi
deploy "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml" || true

# OS-specific setup
case "$(uname -s)" in
  Darwin)
    # iTerm2 (Dynamic Profile)
    ITERM_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    deploy "$DOTFILES_DIR/iterm2/herdr.json" "$ITERM_DIR/herdr.json" || true

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

    # HackGen Nerd font (via Homebrew). The font is the one optional thing
    # here: it is not a managed file, the README carries a manual install for
    # it, and a machine without brew is already told to use that. So an install
    # that fails is a warning and not a recorded failure -- treating it as one
    # would make a dropped network connection the same kind of event as a home
    # directory that refuses the settings, which it is not.
    if command -v brew &>/dev/null; then
      if brew list --cask font-hackgen-nerd &>/dev/null; then
        echo "font-hackgen-nerd already installed. Skipping."
      elif ! brew install --cask font-hackgen-nerd; then
        echo
        echo "WARNING: brew install --cask font-hackgen-nerd failed."
        echo "  brew said why just above. Nothing else here depends on it; the"
        echo "  iTerm2 profile names HackGen and macOS falls back to another"
        echo "  monospace font until it is installed."
        echo "  Fix: re-run brew install --cask font-hackgen-nerd once the"
        echo "  reason is gone, or install the font by hand (see README)."
        echo
      fi
    else
      echo "Homebrew not found. Install the HackGen Nerd font manually (see README)."
    fi
    ;;
  *)
    # Windows Terminal (Windows side). The Windows-side path is found through
    # wslpath and cmd.exe, and both exist only under WSL -- on a Linux box that
    # is not one there is no Windows to deploy to, and asking for wslpath
    # anyway would end the run non-zero over a file this machine has no place
    # for.
    if ! command -v wslpath &>/dev/null || ! command -v cmd.exe &>/dev/null; then
      echo "Not WSL (no wslpath / cmd.exe). Skipping Windows Terminal."
    else
      # cmd.exe ends the value with a CR. Its stderr is kept rather than
      # dropped: when this comes back empty, that message is the only account
      # of why.
      appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' | tr -d '\r' || true)"
      # The guard is what keeps wslpath from being handed the empty string that
      # a cmd.exe answering with nothing leaves here. wslpath keeps its stderr
      # for the same reason cmd.exe does.
      if [ -n "$appdata" ]; then
        appdata="$(wslpath "$appdata" || true)"
      fi
      if [ -z "$appdata" ]; then
        # Not the same thing as Windows Terminal being absent, and told apart
        # from it: both tools answered to command -v, so this is WSL and there
        # is a Windows side -- what could not be found is where it keeps the
        # user's AppData. Windows Terminal may well be installed, so a managed
        # file was missed and this counts like any other miss.
        record_failure "Windows Terminal's settings.json was not deployed." \
          "%LOCALAPPDATA% would not resolve, so where Windows Terminal keeps" \
          "its settings is unknown. Whatever cmd.exe or wslpath said about it" \
          "is just above. This says nothing about whether Windows Terminal is" \
          "installed -- only that the Windows side of this machine could not" \
          "be located from here, and that nothing was written anywhere." \
          "Fix: check that \`cmd.exe /c 'echo %LOCALAPPDATA%'\` answers from" \
          "this shell (a cwd on a UNC path is the usual reason it does not)."
      else
        WT_DIR="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
        if [ -d "$WT_DIR" ]; then
          # Windows Terminal writes this file itself, and the overwrite costs
          # it nothing it cannot rebuild: the profiles it generates per WSL
          # distro are this machine's inventory and it generates them again.
          deploy "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json" || true
        else
          # The Windows side was found and Windows Terminal is not on it. There
          # is nothing to deploy to, so this is a skip and not a failure.
          echo "Windows Terminal not installed ($WT_DIR does not exist). Skipping."
        fi
      fi
    fi
    ;;
esac

if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo
  echo "Finished with ${#FAILURES[@]} failure(s):"
  for failed in "${FAILURES[@]}"; do
    echo "  - $failed"
  done
  # Not "everything else was deployed": a run can also skip a managed file for
  # want of anywhere to put it (Windows Terminal, on a machine that is not WSL
  # or has not got it), and those are named above too.
  echo "Each one is explained above. Everything else was deployed or skipped as noted."
  exit 1
fi

echo "Done."
