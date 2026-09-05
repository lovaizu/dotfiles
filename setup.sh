#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backups go to a directory of their own because of what iTerm2 does with
# DynamicProfiles: it reads every file in that directory except the ones whose
# name begins with a dot or ends with a tilde (measured: the iTerm2 binary
# carries "Skipping it because of leading dot" and "Skipping it because of
# trailing tilde (GNU-style backup file)" beside reallyReloadDynamicProfiles).
# A backup is named herdr.json.<timestamp>.bak, which is neither, so one left
# beside the profile would be read as a second profile with a duplicate Guid.
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
#
# The report is spoken on stderr, with the warnings it summarises, so a caller
# that trims this script's stdout does not lose the diagnostics with it:
# ./setup.sh | head -2, or a run whose stdout goes to a file, still shows every
# warning the run had printed. What a truncated pipe does still cost is the run
# itself: the next write to stdout ends it with a broken pipe, so the
# deployments after that point never happen and this list -- printed after all
# of them -- is never reached (measured: PIPESTATUS "141 0", the warning on the
# terminal, no "Finished with" line). It is left that way. Surviving a
# truncated pipe would mean every echo in this file carrying its own failure
# handling, and the run that dies does end non-zero and converges on the next
# one like any other interrupted run.
FAILURES=()

# Every half-written file this script makes is a dot file named after where it
# is going, in the directory it is going to, and is renamed into place once it
# is whole. The leading dot is what makes that safe in iTerm2's
# DynamicProfiles: a name that begins with a dot is one of the two kinds iTerm2
# skips (see BACKUP_DIR above), so a file half-way through being deployed is
# never read as a profile.
#
# The name is built here and nowhere else. sweep_tmp_files has to find the same
# files again, and a second hand-written copy of the format would let a change
# to one stop the other matching without saying so.
tmp_prefix_for() {
  printf '%s/.%s.dotfiles-tmp.' "$(dirname "$1")" "$(basename "$1")"
}

# The pid on the end is what keeps two runs at once from writing into one temp
# file and renaming the mixture into place. Two setup.sh at once is not a case
# this script serves, and the pid does not make it one: what the two runs do to
# each other beyond this file is not defined here (measured: two runs started
# together both announced the same backup path, and only one .bak was left).
# What the pid buys is that neither one renames a file the other was half-way
# through writing.
tmp_for() {
  printf '%s%s' "$(tmp_prefix_for "$1")" "$$"
}

# Where the backup of dst lives, before the timestamp is added. deploy needs it
# to sweep and to name the temp file the trap must know about, and backup_file
# needs it to build the .bak name, so it is worked out here for both.
#
# The name is the basename and nothing else, so BACKUP_DIR is one flat
# namespace: the managed files must have basenames that differ. The three here
# do (config.toml, herdr.json, settings.json). A fourth that repeats one of
# them would put both files' backups under one name, with nothing in the name
# to tell them apart, and deploy's sweep would glob the same pattern for both.
backup_path_for() {
  printf '%s/%s' "$BACKUP_DIR" "$(basename "$1")"
}

# Remove the temp files earlier runs left beside a destination. A run killed
# outright (SIGKILL) leaves one, as does a machine that loses power, and since
# the name carries that run's pid no later run ever writes over it -- without
# this sweep nothing would ever remove it (measured). The leading dot that keeps
# iTerm2 from reading such a file also keeps a plain ls from showing it, so
# nobody finds it by looking either; it is litter that would otherwise sit in
# the directory for good.
sweep_tmp_files() {
  rm -f "$(tmp_prefix_for "$1")"* 2>/dev/null || true
}

# The temp files this run is part-way through writing, so an interrupt does not
# leave them behind. Empty whenever there is none, and rm is content with that
# (measured: rm -f "" exits 0 and says nothing).
DEPLOY_TMP=""
BACKUP_TMP=""
remove_pending_tmp() {
  # A dst whose directory has gone makes even rm complain; nothing here is
  # worth a message.
  rm -f "$DEPLOY_TMP" "$BACKUP_TMP" 2>/dev/null || true
  DEPLOY_TMP=""
  BACKUP_TMP=""
}
# INT and TERM exit rather than only cleaning up: a trap that returns leaves
# bash carrying on to the next deployment, so Ctrl-C would stop nothing. That
# is about a signal this shell actually gets. Ctrl-C is one -- the terminal
# sends it to the whole process group (measured: SIGINT to the group during a
# copy left through this trap with 130 and no temp file behind) -- but a signal
# aimed at this script's pid alone is not: bash is waiting on cp or mv, the
# child never sees it, and the run carries on to the end (measured: kill -INT
# on the pid alone finished the deployment and exited 0).
trap remove_pending_tmp EXIT
trap 'remove_pending_tmp; exit 130' INT
trap 'remove_pending_tmp; exit 143' TERM

# The shape a warning has, wherever it comes from: a blank line, the headline,
# the caller's detail lines indented under it, a blank line. Kept apart from
# record_failure below because not everything worth warning about is a managed
# file that was not deployed -- of the callers that use this directly, two are
# about something outside the managed files (iTerm2's default profile, the
# font) and one is about a managed file that is being deployed correctly at a
# cost the backup cannot undo (the symlink in deploy). None of them should make
# the run end non-zero.
#
# All of it on stderr. What a warning explains is a command that has just said
# why on stderr itself, and the two belong together: on stdout the explanation
# lands in a different stream from the complaint it explains, so a caller
# reading either one alone gets half the story (measured: with the warning on
# stdout, 2>/dev/null showed the WARNING without cp's "is a directory" and
# 1>/dev/null showed cp's line with nothing saying which managed file it was
# about). Progress -- Up to date, Installed, Backed up, Done. -- stays on
# stdout.
warn() {
  local what="$1" line
  shift
  echo >&2
  echo "WARNING: $what" >&2
  for line in "$@"; do
    echo "  $line" >&2
  done
  echo >&2
}

# Say that a managed file was not deployed and remember it for the summary. The
# detail lines are the caller's, because what to do about it differs; what is
# the same everywhere is that the run goes on and ends non-zero.
record_failure() {
  FAILURES+=("$1")
  warn "$@"
}

# Copy an existing dst into BACKUP_DIR and print where it went. Prints nothing
# when dst is not there yet. The timestamp counts whole seconds, so two runs
# that back up the same file inside one second arrive at the same name, and the
# second is made unique by counting up rather than writing over the first: the
# message deploy prints promises the user a file at that path. One run after
# another never gets that far on its own -- the second finds dst already
# matching, says Up to date and backs up nothing -- so it takes a dst that
# changes between them, which is what herdr does to this config.toml every time
# it saves a theme (measured: with the theme name rewritten in dst before each
# of two runs, the pair left config.toml.<ts>.bak and config.toml.<ts>-1.bak).
#
# Two runs at the same time are a different matter and are not served here: the
# loop below is a test followed by a rename, so both can pass it on the same
# name and one .bak then holds what two runs announced (measured: two runs
# started together printed the same path and left one file). That is the
# concurrency this script does not support, not a promise it breaks.
#
# The path goes back to the caller on stdout rather than through a global. A
# global outlives the call: it would still hold one file's backup when a later
# deploy fails, and that deploy's cleanup would delete a backup the run had
# already promised the user (measured: a second run where config.toml differs
# and the iTerm2 profile deployed after it cannot be written -- with a global,
# the config.toml backup the run had just announced was gone by the end of it;
# taken on stdout into a local, it is still there).
#
# The temp file to write through is handed in rather than worked out here, for
# the reason deploy gives where it works it out.
backup_file() {
  local dst="$1" tmp="$2" stem bak count=1
  [ -e "$dst" ] || return 0
  # No directory, no backup, and a backup is what the caller is about to
  # promise the user -- so this is a failure like any other here.
  mkdir -p "$BACKUP_DIR" || return 1
  stem="$(backup_path_for "$dst").$(date +%Y%m%d%H%M%S)"
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
  # name a half-written copy claims nothing, the trap removes it, and a run
  # killed outright leaves it for deploy's sweep.
  #
  # Non-zero when there is a dst that cannot be copied: a directory in its
  # place, a file that cannot be read, a disk that fills up. cp says why on
  # stderr and deploy turns it into a warning.
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
# old file or the new one and never a mix of the two. "Stopped" means the
# process stopped -- SIGINT, SIGTERM, SIGKILL, all measured. It does not cover
# a machine that loses power or panics: nothing here fsyncs the temp file, so
# the rename can reach the disk before the bytes do and leave dst short. That
# is left alone; what is at stake is config files a clone and one setup.sh
# rebuild.
#
# What half a managed file would cost differs by format, and the quieter half
# is the worse one. Half a
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
# lands as 600). Only a rewritten one: the mode does not converge the way the
# contents do, because a dst that already matches is not rewritten at all
# (measured: a dst left at 600 by a run under umask 077 was still 600 after a
# run under umask 022, which said Up to date). "dotfiles is the source of
# truth" is about the contents.
#
# Returns non-zero, having already warned and recorded it, when the file was
# not deployed. Callers add `|| true` so that set -e does not turn the warning
# back into an abort. That `|| true` also switches errexit off for everything
# inside this function -- bash applies it to the whole call -- so the file's
# set -euo pipefail is no help here: every command below that can fail is
# checked explicitly, and a bare line added to this function would fail in
# silence and let the run end 0 having deployed nothing.
deploy() {
  local src="$1" dst="$2" dir backup=""
  # Before the check below rather than after it: a dst that is already correct
  # still has to come out of a directory with no leftovers standing in it, and
  # a run killed before the rename leaves both an old dst and a temp file. The
  # backup directory is swept on the same terms and for the same reason -- a
  # sweep that only ran when a backup is actually taken would never reach a
  # machine that is up to date, and the leftover would sit there for good
  # (measured: a backup interrupted mid-copy survived three later runs).
  sweep_tmp_files "$dst"
  sweep_tmp_files "$(backup_path_for "$dst")"
  # cmp -s keeps quiet about a difference but not about a dst it cannot open,
  # and a lone "Is a directory" naming neither the managed file nor what to do
  # about it is worse than no message. One of the commands below runs into the
  # same thing and its complaint arrives with the warning that explains it.
  if cmp -s "$src" "$dst" 2>/dev/null; then
    echo "Up to date: $dst"
    return 0
  fi
  # Said before anything is written, and only on the path that actually
  # replaces something: a link whose target already holds the dotfiles copy
  # returned above and stays a link. This is the one thing here the backup
  # cannot undo, so it is the one thing that gets said out loud even though
  # nothing has gone wrong -- warn and not record_failure, because the managed
  # file does land where it belongs and nothing outside the managed files is
  # written.
  if [ -L "$dst" ]; then
    warn "$dst is a symlink and is about to stop being one." \
      "The link itself is replaced by a regular file holding the dotfiles" \
      "copy; what it points at is left as it was. A backup taken here holds" \
      "the target's contents rather than the link, so putting the backup" \
      "back restores the contents and not the link -- and a link pointing at" \
      "nothing leaves no backup at all." \
      "Fix: if the link was wanted, make it again after this run."
  fi
  dir="$(dirname "$dst")"
  DEPLOY_TMP="$(tmp_for "$dst")"
  # backup_file's temp file is named here, where the trap can see it, and handed
  # in. backup_file runs in a command substitution, and the name would be no use
  # to anyone if it were set in there: a subshell does not run these traps
  # (measured: with the name set inside the command substitution, a SIGINT to
  # the process group left the part-written file behind; named here, the same
  # interrupt removes it).
  BACKUP_TMP="$(tmp_for "$(backup_path_for "$dst")")"
  # mkdir -p is also what can leave an empty directory behind when it is the
  # copy that fails -- the destination's here, BACKUP_DIR in backup_file. They
  # are left where they are: mkdir -p does not say whether this run made the
  # directory, so removing one means being ready to remove a directory that was
  # there all along. An empty directory under ~/.config or ~/.local/state asks
  # nothing of anyone and the next run that gets further fills it. The warning
  # below says so rather than claiming nothing was written.
  #
  # backup is local, and empty until backup_file has actually taken one, so the
  # cleanup below can only ever remove this file's own backup.
  if mkdir -p "$dir" && cp "$src" "$DEPLOY_TMP" && backup="$(backup_file "$dst" "$BACKUP_TMP")"; then
    # Either renamed onto the .bak or removed by backup_file; either way there
    # is no longer a backup temp file for the trap to worry about.
    BACKUP_TMP=""
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
  remove_pending_tmp
  # dst is as it was on either way here: nothing above reached the rename, or
  # the rename itself failed -- and mv within one directory either replaces dst
  # or leaves it alone. So this backup is a copy of a file that is still there.
  # Keeping it would add one more identical .bak per run for as long as the
  # cause lasts.
  if [ -n "$backup" ]; then
    rm -f "$backup"
  fi
  record_failure "$dst was not deployed." \
    "The command that failed said why just above. Nothing was replaced: the" \
    "copy is renamed into place only once it is whole, and a rename that" \
    "fails replaces nothing, so the file is as it was and no backup was" \
    "kept. An empty directory may be left behind -- the one holding the" \
    "file, or the backup directory -- since both are made before the copy" \
    "that failed." \
    "The rest of the setup runs below and this run ends non-zero." \
    "Fix: a \"No such file or directory\" naming a path under" \
    "  $DOTFILES_DIR" \
    "is a file missing from the repository itself -- re-check the clone." \
    "Anything else is this machine: make the file, the directory holding" \
    "it, or the backup directory" \
    "  $BACKUP_DIR" \
    "writable, or move aside something standing where the file belongs." \
    "Then re-run ./setup.sh."
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
    # opened with it. Warn when it is not the default profile -- a warning and
    # not a failure, because every managed file is where it belongs; what is
    # missing is a choice only the iTerm2 UI can make.
    # The same value as "Guid" in iterm2/herdr.json, which cannot say so
    # itself -- JSON takes no comments, so the tie is recorded on this side.
    # Change one without the other and this comparison asks about a profile
    # no file defines: the warning below then fires on every run, including on
    # the machine where herdr is already the default, and stops meaning
    # anything.
    ITERM_PROFILE_GUID="8f7b6c1e-3d2a-4e9b-9c5d-71a2b4e6f038"
    default_guid="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)"
    if [ "$default_guid" != "$ITERM_PROFILE_GUID" ]; then
      warn "the 'herdr' profile is not iTerm2's default profile." \
        "The ctrl+cmd key mappings apply only to windows using that profile," \
        "so herdr workspace switching will not work in other windows." \
        "Fix: iTerm2 > Settings > Profiles > herdr > Other Actions... > Set as Default," \
        "then open a NEW window (existing windows keep their old profile)."
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
        warn "brew install --cask font-hackgen-nerd failed." \
          "brew said why just above. Nothing else here depends on it; the" \
          "iTerm2 profile names HackGen and macOS falls back to another" \
          "monospace font until it is installed." \
          "Fix: re-run brew install --cask font-hackgen-nerd once the" \
          "reason is gone, or install the font by hand (see README)."
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
      # Absolute, or this went wrong. An empty answer is not the only wrong
      # one: cmd.exe echoes an undefined variable back as the literal
      # %LOCALAPPDATA% (measured), which is not empty, so a test for emptiness
      # alone carries that string into WT_DIR, where the [ -d ] below finds no
      # such directory and the run ends 0 saying Windows Terminal is not
      # installed -- a managed file missed, counted as a skip, and blamed on
      # something that may well be there. What wslpath answers for a Windows
      # path begins with /, so that is the test, and it also catches a wslpath
      # that failed after writing part of an answer (the `|| true` above keeps
      # a non-empty one).
      case "$appdata" in
        /*)
          WT_DIR="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
          if [ -d "$WT_DIR" ]; then
            # Windows Terminal writes this file itself, and the overwrite costs
            # it nothing it cannot rebuild: the profiles it generates per WSL
            # distro are this machine's inventory and it generates them again.
            deploy "$DOTFILES_DIR/windows-terminal/settings.json" "$WT_DIR/settings.json" || true
          else
            # The Windows side was found and Windows Terminal is not on it.
            # There is nothing to deploy to, so this is a skip and not a
            # failure.
            echo "Windows Terminal not installed ($WT_DIR does not exist). Skipping."
          fi
          ;;
        *)
          # Not the same thing as Windows Terminal being absent, and told apart
          # from it: both tools answered to command -v, so this is WSL and there
          # is a Windows side -- what could not be found is where it keeps the
          # user's AppData. Windows Terminal may well be installed, so a managed
          # file was missed and this counts like any other miss.
          record_failure "Windows Terminal's settings.json was not deployed." \
            "%LOCALAPPDATA% did not resolve to a path. The answer was:" \
            "  $appdata" \
            "so where Windows Terminal keeps its settings is unknown. Whatever" \
            "cmd.exe or wslpath said about it is just above. This says nothing" \
            "about whether Windows Terminal is installed -- only that the" \
            "Windows side of this machine could not be located from here, and" \
            "that nothing was written anywhere." \
            "Fix: check that \`cmd.exe /c 'echo %LOCALAPPDATA%'\` answers from" \
            "this shell (a cwd on a UNC path is the usual reason it does not)."
          ;;
      esac
    fi
    ;;
esac

# The guard is not tidiness. Under set -u, bash 3.2 reads "${arr[@]}" on an
# empty array as an unbound variable and kills the script on the spot, and the
# EXIT trap above then hands back its own status rather than the failure's, so
# a run that dies here dies quietly (measured with /bin/bash 3.2.57: with this
# guard removed, a run that deployed everything printed "FAILURES[@]: unbound
# variable" and still exited 0). "${#FAILURES[@]}" is safe on an empty array,
# so it is what decides whether the loop below is reached at all.
if [ "${#FAILURES[@]}" -gt 0 ]; then
  # On stderr with the warnings it summarises, for the reason warn gives.
  echo >&2
  echo "Finished with ${#FAILURES[@]} failure(s):" >&2
  for failed in "${FAILURES[@]}"; do
    echo "  - $failed" >&2
  done
  # Not "everything else was deployed": a run can also skip a managed file for
  # want of anywhere to put it (Windows Terminal, on a machine that is not WSL
  # or has not got it), and those are named above too.
  echo "Each one is explained above. Everything else was deployed or skipped as noted." >&2
  exit 1
fi

echo "Done."
