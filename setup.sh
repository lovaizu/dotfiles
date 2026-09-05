#!/bin/bash
set -euo pipefail

# Every destination below is built from HOME, so a HOME that is not set is not a
# machine this script can deploy to. The check comes before the traps because
# after them a `set -u` fatal is handed back as exit 0 (see the traps), and this
# is exactly how that used to bite: with XDG_CONFIG_HOME and XDG_STATE_HOME both
# set, the two expansions of $HOME above the OS branch were never reached, so
# the run deployed herdr's config, died on the first bare $HOME with "unbound
# variable", deployed no iTerm2 profile, listed no failure, printed no "Done."
# and exited 0 (measured). A trimmed environment reaches here that way in
# ordinary use -- a systemd unit, a cron, a docker run. An empty HOME is as
# useless as an unset one, since every destination would then be an absolute
# path with nothing in front of it, and :? refuses both.
: "${HOME:?HOME is not set. Every path this script deploys to is built from it.}"

# Names at this level: capitals for what outlives the block that sets it -- the
# settings here, and the state the traps read -- and lower case for a value one
# block works out and spends on the spot, iterm_dir and wt_dir among them.
# Inside the functions everything is a local and lower case.
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# The XDG base directories, read through one test rather than straight, because
# unset is not the only value that has to fall back on the default: a relative
# one is worse than none. The specification says a value that is not an absolute
# path is invalid and must be ignored, and using it literally instead makes
# every destination relative to whatever directory the run was started in
# (measured: with XDG_CONFIG_HOME=relcfg, the same run from two directories
# deployed to work/relcfg/herdr/config.toml and to elsewhere/relcfg/herdr/
# config.toml, and said "Done." both times). Both of this script's promises
# break there -- the file is not where the program reads it, and a second run
# from another directory writes somewhere else again instead of saying Up to
# date -- so anything not beginning with / is ignored here, for both variables
# and by the same "is it absolute" question the WSL branch asks of
# %LOCALAPPDATA%.
#
# Ignoring it is not done in silence. herdr does not follow the specification on
# such a machine: it resolves a relative value against its own working directory
# (measured: with XDG_CONFIG_HOME=relcfg and a broken config.toml under ./relcfg,
# `herdr config check` reported that file's parse error; run from a directory
# with no relcfg beside it, the same command said "config: ok" and read the one
# under ~/.config). So no single path this script could write is sure to be the
# one herdr reads, and a run that quietly took the default would be claiming
# more than it knows. The warning is spoken further down, where warn exists.
#
# The answer comes back in xdg_base rather than on stdout because the caller is
# not the only thing this has to tell: a command substitution runs in a subshell,
# and the note of what was ignored would not survive it. xdg_base is read on the
# line after the call and never again, so it is lower case like the other values
# a block works out and spends; XDG_IGNORED outlives this block and is not.
XDG_IGNORED=""
xdg_base=""
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

# Where the deployed files go. The XDG variables are read wherever the program
# that owns the file reads them: herdr looks under $XDG_CONFIG_HOME when it is
# set and does not fall back to ~/.config (measured: with XDG_CONFIG_HOME
# pointing at a directory holding a broken config.toml and a good one under
# ~/.config, `herdr config check` reported the broken one's parse error), so
# deploying to ~/.config on such a machine would write a file herdr never reads
# and still call the run a success (measured: the run said "Installed
# .../.config/herdr/config.toml" and left the XDG directory empty).
set_xdg_base XDG_CONFIG_HOME "${XDG_CONFIG_HOME:-}" "$HOME/.config"
HERDR_CONFIG="$xdg_base/herdr/config.toml"

# Backups go to a directory of their own because of what iTerm2 does with
# DynamicProfiles: it reads every file in that directory except the ones whose
# name begins with a dot or ends with a tilde (measured: the iTerm2 binary
# carries "Skipping it because of leading dot" and "Skipping it because of
# trailing tilde (GNU-style backup file)" beside reallyReloadDynamicProfiles).
# A backup is named herdr.json.<timestamp>.bak, which is neither of those, so
# one left beside the profile should be read as a second profile with a
# duplicate Guid. Should: the strings are measured, that reading of them is not
# -- iTerm2 has not been run on a DynamicProfiles directory holding a .bak to
# watch it happen. The inference is enough to keep backups elsewhere, which
# costs nothing either way.
#
# XDG_STATE_HOME rather than a path of this script's own so that the two XDG
# variables are treated alike here; nothing but this script reads BACKUP_DIR.
set_xdg_base XDG_STATE_HOME "${XDG_STATE_HOME:-}" "$HOME/.local/state"
BACKUP_DIR="$xdg_base/dotfiles-backups"

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
# terminal, no "Finished with" line). It is left that way, and not for want of a
# way to survive it -- the progress lines could go through one helper and be
# handled there once. It is that surviving buys nothing worth the helper: a
# caller that asked for two lines got its two lines, the run ends non-zero, and
# deployment is idempotent, so the next run makes every judgement again from the
# start. Nobody deploys through `| head`.
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

# The pid on the end gives each run a name of its own, so two runs at once write
# into two files rather than into one, and neither renames a mixture of both
# into place. That is the whole of what it buys, and it is not what would make
# two runs at once safe: the sweep below removes every temp file beside the
# destination, other runs' included (measured: a leftover carrying a foreign pid
# was gone after one run), so a run can have the copy it is half-way through
# writing unlinked underneath it by another run's sweep. Two setup.sh at once is
# not a case this script serves, and what the two do to each other beyond this
# file is not defined here (measured: two runs started together both announced
# the same backup path, and only one .bak was left).
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
#
# Left as a rule rather than a check in deploy, for the reason the Guid in the
# Darwin arm is left to a grep: a check could only compare the basenames one run
# actually deploys, so the pair it would miss -- two managed files on different
# operating systems, which never run together -- is exactly the pair a person
# would get wrong, while `grep -n 'deploy "' setup.sh` shows all of them at once
# and costs the run nothing.
backup_path_for() {
  printf '%s/%s' "$BACKUP_DIR" "$(basename "$1")"
}

# Remove the temp files earlier runs left beside a destination -- every one of
# them, whichever run wrote it, since the glob is on the shared prefix and not
# on this run's pid (measured: a leftover carrying a foreign pid was gone after
# one run). A run killed outright (SIGKILL) leaves one, as does a machine that
# loses power, and the name carries that run's pid, so no later run writes over
# it unless the system hands the same pid out again -- and without this sweep
# nothing would ever remove it (measured). The leading dot that keeps
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
# bash carrying on to the next deployment, so Ctrl-C would stop nothing. Both
# fire whether the signal is aimed at the process group or at this script's pid
# alone (measured, five runs each, SIGINT during a copy: exit 130, nothing
# deployed after it, no temp file behind). What decides whether a trap exists to
# fire is the disposition this shell was started with: a shell that inherited
# SIGINT ignored cannot trap it at all, which is what a non-interactive shell
# hands its `&` jobs (measured: `bash -c 'trap ... INT; kill -INT $$; ...' &`
# from a script printed "trap did not fire" and exited 0, while the same command
# started through a wrapper that put SIGINT back to its default ran the trap and
# exited 130). Nothing here can mend that from the inside, and it is not how a
# person runs a deployment.
#
# The EXIT trap costs the run one thing: with an EXIT trap set, bash 3.2 hands a
# `set -u` fatal back as exit 0. The message is printed and the run still calls
# itself a success (measured with /bin/bash 3.2.57: a script whose statement
# after the trap reads an unset variable printed "unbound variable" and exited 0;
# the same script without the trap exited 1). Reading $? in the trap and exiting
# with it does not recover it -- the trap is handed 0 for this failure, though it
# is handed 1 for an ordinary errexit failure (measured: `trap 'st=$?; ...; exit
# $st' EXIT` still exited 0 on the unset variable, and a trap that printed $? saw
# 0 there and 1 after a plain `false`). So it is not about any one variable: any
# expansion below that could be unset would end its run quietly at 0.
#
# REACHED_END is the mechanism against that whole class, and the `${VAR:-}` and
# `${#ARR[@]}` defaults below are the discipline that keeps it from being needed.
# The discipline alone had already been broken once -- an unset HOME, guarded at
# the top of this file now -- so the run says out loud where it got to: only the
# two places that end this script on purpose set REACHED_END, and an exit 0 that
# did not come from one of them is turned into 1. The test on $st is what keeps
# that from flattening every other way out: a run killed by SIGTERM leaves
# through its own trap with 143, and forcing 1 on it would lose which signal
# stopped it (measured, all four ways out: `set -u` fatal 1, ordinary end 0,
# SIGTERM 143, the failure list's own exit 1; SIGINT 130).
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

# The shape a warning has, wherever it comes from: a blank line, the headline,
# the caller's detail lines indented under it, a blank line. Kept apart from
# record_failure below because not everything worth warning about is a managed
# file that was not deployed -- of the callers that use this directly, four are
# about something outside the managed files (two about iTerm2's default profile,
# two about the font), one is about a managed file that has been deployed
# correctly at a cost the backup cannot undo (the symlink in deploy), and one is
# about a managed file deployed to the path the specification names while the
# program that reads it may look elsewhere (the ignored XDG value). None of them
# should make the run end non-zero.
#
# All of it on stderr. What a warning explains is a command that has just said
# why on stderr itself, and the two belong together: on stdout the explanation
# lands in a different stream from the complaint it explains, so a caller
# reading either one alone gets half the story (measured: with the warning on
# stdout, 2>/dev/null showed the WARNING without cp's "is a directory" and
# 1>/dev/null showed cp's line with nothing saying which managed file it was
# about).
#
# That is the split for the whole file, and the line it draws is progress
# against diagnosis rather than warnings against everything else. On stdout: Up
# to date, Backed up, Installed, the font that was already there, the note that
# herdr is not installed (which is the opening half of the sentence the Up to
# date or Installed line below it finishes), Done. On stderr: every WARNING, the
# failure list at the end, and every notice that a managed file was not
# deployed -- the Windows Terminal skips. Those last are the reason the line is
# drawn here and not around the word WARNING: a run that deployed one file fewer
# than the reader expects says so where the rest of the diagnosis is, and a
# caller keeping only stdout is not left with a clean-looking log of a run that
# quietly skipped something.
#
# Three shapes speak on stderr, and what tells them apart is what the run wants
# from the reader, not how grave the event sounds (§4.6 of design.md carries the
# same three):
#   record_failure -- a managed file had somewhere to go and did not get there.
#     The run ends non-zero and names it again at the end.
#   warn           -- nothing managed is misplaced, but the run wants something
#     it cannot do itself: install the font, set the default profile, make the
#     symlink again. Every one of these carries a Fix line, which is what the
#     block shape is for.
#   a plain echo   -- a fact about this machine that asks nothing of anyone: a
#     managed file has nowhere to go here and that is not a defect (a Linux that
#     is not WSL, a Windows side without Windows Terminal).
# So the font, which is not even a managed file, gets a block while a skipped
# settings.json gets one line. That is the intended way round: the block is the
# shape of a request, and there is nothing to ask of a machine that is exactly
# as it should be. Turning the skips into blocks would warn every run on every
# ordinary Linux box for no act anyone was meant to take.
#
# Ends by returning 0 so that record_failure does too: its caller in the WSL
# branch runs under errexit, and a warn whose value came from whatever the last
# echo returned would make that call a coin toss.
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
# What half a managed file would cost differs by format, and the quieter half is
# the worse one. Half a JSON file is not a document at all: only the cut that
# drops the trailing newline parses (measured with Python's json, standing in
# for iTerm2 and Windows Terminal, which cannot be run on a broken file from
# here). Half of config.toml is quieter, and the measurement behind that is
# about cuts at a line boundary: every one of the 20 line-boundary cuts of this
# repository's config.toml, the empty file included, is valid TOML with whole
# tables gone, and 15 of the 20 leave no [keys] table at all -- which asks
# nothing of herdr, so the machine gets herdr's fallbacks and the workspace
# switching this repository exists for is not there, and herdr calls every one
# of them "config: ok" (measured with herdr config check). A cut at an arbitrary
# byte is mostly not that quiet: of the 368 byte-boundary cuts, 332 make herdr
# config check exit non-zero and 36 pass. So the case for the rename rests on
# the line-boundary reading, which is the charitable one -- and a cp interrupted
# mid-write stops wherever it stops, not at a line.
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
# Always returns 0. A file that was not deployed has already been warned about
# and put in FAILURES, which is where the run reads it back; no caller has ever
# had a use for the return value. Returning it anyway cost more than it was
# worth: every call needed `|| true` to keep set -e from turning a warning into
# an abort, and bash applies that `|| true` to the whole call, so errexit was
# switched off for everything inside this function too. A bare line added here
# would then have failed in silence and let the run end 0 having deployed
# nothing. With the contract stated instead, the calls are bare, errexit is live
# inside this function, and the only lines that opt out of it are the ones that
# name a failure they mean to allow.
deploy() {
  local src="$1" dst="$2" dir backup="" was_link=""
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
  #
  # Only "identical" is read here; every other answer means "carry on and
  # deploy", and they cannot usefully be told apart anyway -- cmp answers 2 for
  # a dst that does not exist yet (measured), which is the ordinary first
  # install. The one that hides in there is 127, a cmp that is not on PATH,
  # whose "command not found" the redirection above swallows. That machine still
  # gets the right bytes and is never told a false success; what it loses is Up
  # to date, so every run rewrites the file and leaves one more identical .bak.
  # Left unchecked, and named here instead: guarding this one command while cp,
  # mv, mkdir and date -- leaned on just as hard, and absent on the same machine
  # -- go unguarded would be the asymmetry, and a bounded cost of one backup per
  # run does not buy it.
  if cmp -s "$src" "$dst" 2>/dev/null; then
    echo "Up to date: $dst"
    return 0
  fi
  # Noted here, said after the rename. Whether dst is a link can only be asked
  # before the rename -- afterwards it is a regular file -- but a run that
  # warned here and then failed to deploy told the user their link was gone
  # while it was still there, and sent them off to make it again (measured:
  # with dst a symlink inside a read-only directory, the run printed "is about
  # to stop being one" and its Fix line, then cp failed and the link was
  # untouched). Only a run that actually replaced the link has anything to say.
  if [ -L "$dst" ]; then
    was_link=1
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
      # contents that have actually been replaced. The message names the
      # destination because this line is printed for every managed file -- the
      # iTerm2 profile and Windows Terminal's settings.json as much as herdr's
      # config -- and "existing config" named none of them.
      if [ -n "$backup" ]; then
        echo "Backed up the previous $dst to $backup"
      fi
      echo "Installed $dst"
      # After the rename, and only when the rename happened: this is the one
      # thing here the backup cannot undo, so it is the one thing said out loud
      # even though nothing went wrong -- warn and not record_failure, because
      # the managed file does land where it belongs and nothing outside the
      # managed files is written. A link whose target already held the dotfiles
      # copy never reaches this: the cmp above reads through it and returns.
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
  # dst is as it was on either way here: nothing above reached the rename, or
  # the rename itself failed -- and mv within one directory either replaces dst
  # or leaves it alone. So this backup is a copy of a file that is still there.
  # Keeping it would add one more identical .bak per run for as long as the
  # cause lasts.
  if [ -n "$backup" ]; then
    # The one line here that is allowed to fail: the backup is being thrown
    # away, so a machine that will not let go of it changes nothing about what
    # this run is reporting.
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

# Said here rather than where the value was thrown away, because warn does not
# exist that early. Not a failure: every managed file is deployed, and to the
# path the specification names. What the reader is being asked for is the thing
# this script cannot settle -- which of the two paths herdr will read (see
# set_xdg_base).
if [ -n "${XDG_IGNORED:-}" ]; then
  warn "an XDG base directory must be an absolute path, so this run ignored: $XDG_IGNORED" \
    "The specification says a value that does not begin with / is invalid and" \
    "is to be ignored, so the default was used instead. Taking the value" \
    "literally would put the deployed files under whichever directory the run" \
    "was started in, somewhere new each time." \
    "If XDG_CONFIG_HOME is among them, herdr does not ignore it: it resolves" \
    "the relative value against its own working directory, so it may read a" \
    "different config.toml from the one deployed here." \
    "Fix: set it to an absolute path, or unset it, and re-run ./setup.sh."
fi

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
deploy "$DOTFILES_DIR/herdr/config.toml" "$HERDR_CONFIG"

# OS-specific setup
case "$(uname -s)" in
  Darwin)
    # iTerm2 (Dynamic Profile). The profile is deployed whether or not iTerm2
    # is on this machine: it is a managed file with somewhere to go, iTerm2
    # reads the directory when it is next started, and a Mac that has not got
    # iTerm2 yet is not a Mac that should be told a managed file was skipped.
    # deploy's mkdir -p makes this directory when it is not there, which is the
    # opposite of what the WSL arm does with Windows Terminal's LocalState, and
    # the test that tells them apart is whose directory it is: DynamicProfiles
    # is a drop box iTerm2 scans on start-up, empty is a state it is meant to be
    # in, and one made early is read whenever iTerm2 arrives. LocalState belongs
    # to an installed package -- Windows makes it when the app is installed --
    # so making one here would leave a settings.json inside a package footprint
    # for an app that is not there and that nothing would read. So Darwin has no
    # third outcome: on a Mac every managed file is either deployed or a failure,
    # never skipped for want of anywhere to go (design.md 4.5).
    iterm_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    deploy "$DOTFILES_DIR/iterm2/herdr.json" "$iterm_dir/herdr.json"

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
    iterm_profile_guid="8f7b6c1e-3d2a-4e9b-9c5d-71a2b4e6f038"
    # The one thing both messages below have in common, held once so that a menu
    # iTerm2 renames cannot be corrected in one of them and left wrong in the
    # other -- the same reason tmp_prefix_for and backup_path_for exist.
    iterm_default_menu="iTerm2 > Settings > Profiles > herdr > Other Actions... > Set as Default"
    # `defaults` failing and `defaults` answering something else are two
    # different machines, and they get two different messages. It fails when the
    # domain is not there at all -- iTerm2 never installed, or installed and
    # never started -- and telling that machine to open iTerm2 > Settings sends
    # it somewhere it cannot go (measured: with a `defaults` that exits 1, the
    # old code took the empty answer for a mismatch and printed the Set as
    # Default instructions). It is still not a failure either way: the profile
    # is deployed, and what is left is a choice for later.
    #
    # This one check does not read HOME: `defaults` answers from the real user's
    # preferences whatever HOME says (measured: an isolated home returned this
    # machine's own Guid), so it is the one thing here that a throwaway home
    # cannot exercise.
    if default_guid="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null)"; then
      if [ "$default_guid" != "$iterm_profile_guid" ]; then
        warn "the 'herdr' profile is not iTerm2's default profile." \
          "The ctrl+cmd key mappings apply only to windows using that profile," \
          "so herdr workspace switching will not work in other windows." \
          "Fix: set it as the default in" \
          "  $iterm_default_menu" \
          "then open a NEW window (existing windows keep their old profile)."
      fi
    else
      warn "iTerm2 has no preferences on this machine, so which profile is its default is unknown." \
        "That is what a Mac looks like where iTerm2 has never been installed or" \
        "never been started. The profile itself is deployed and iTerm2 will" \
        "read it when it first runs, so nothing was missed here." \
        "Fix: after installing and starting iTerm2, set the default profile in" \
        "  $iterm_default_menu" \
        "Re-running ./setup.sh then says whether it took."
    fi

    # HackGen Nerd font (via Homebrew). The font is the one optional thing
    # here: it is not a managed file, the README carries a manual install for
    # it, and a machine without brew is already told to use that. So an install
    # that fails is a warning and not a recorded failure -- treating it as one
    # would make a dropped network connection the same kind of event as a home
    # directory that refuses the settings, which it is not.
    #
    # What a missing font costs is the same sentence in both arms below, so it
    # is written once, for the reason iterm_default_menu is: two copies drift.
    # A literal array with lines in it is never the empty one the traps warn
    # about.
    font_cost=(
      "Nothing else here depends on it; the iTerm2 profile names HackGen and"
      "macOS falls back to another monospace font until it is installed. The"
      "font is not a managed file, so this run is not counted a failure."
    )
    if command -v brew &>/dev/null; then
      if brew list --cask font-hackgen-nerd &>/dev/null; then
        echo "font-hackgen-nerd already installed. Skipping."
      elif ! brew install --cask font-hackgen-nerd; then
        warn "brew install --cask font-hackgen-nerd failed." \
          "brew said why just above." \
          "${font_cost[@]}" \
          "Fix: re-run brew install --cask font-hackgen-nerd once the" \
          "reason is gone, or install the font by hand (see README)."
      fi
    else
      # Through warn, like the failed install just above it: the two are the
      # same news -- the font is not going to be installed by this run -- and
      # printing one on each stream would split it in two.
      warn "Homebrew is not installed, so the HackGen Nerd font was not installed either." \
        "${font_cost[@]}" \
        "Fix: install the font by hand (see README), or install Homebrew and" \
        "re-run ./setup.sh."
    fi
    ;;
  *)
    # Windows Terminal (Windows side). Two questions, in this order, because
    # they have different answers: is this WSL at all, and if it is, can the
    # Windows side be reached from here.
    #
    # The kernel answers the first. Microsoft's kernel carries "microsoft" in
    # its release string, and nothing else here does. The tools were the test
    # before and were the wrong one: /etc/wsl.conf can turn interop off
    # ([interop] appendWindowsPath=false is a common setting), and a real WSL
    # then has no cmd.exe on PATH -- so a machine whose settings.json this run
    # is meant to deploy was told "Not WSL", counted as having nowhere to
    # deploy to, and left at exit 0 (measured with no wslpath and no cmd.exe on
    # PATH: "Not WSL (no wslpath / cmd.exe). Skipping Windows Terminal." then
    # "Done." and 0). A Mac never reaches either test -- the Darwin arm above
    # takes it -- and a Mac has no /proc for the first one to read.
    if [ ! -r /proc/sys/kernel/osrelease ] || ! grep -qi microsoft /proc/sys/kernel/osrelease; then
      # Not WSL: there is no Windows side, so settings.json has nowhere to go.
      # A skip, not a failure -- on stderr all the same, because a managed file
      # not being deployed is the reader's business wherever the reason lies.
      echo "Not WSL. Skipping Windows Terminal." >&2
    elif ! command -v wslpath &>/dev/null || ! command -v cmd.exe &>/dev/null; then
      # WSL, but the Windows side cannot be spoken to. Unlike the arm above
      # there is a Windows Terminal out there to deploy to, so this is a miss
      # and counts like any other.
      record_failure "Windows Terminal's settings.json was not deployed." \
        "This is WSL -- /proc/sys/kernel/osrelease names microsoft -- but" \
        "wslpath or cmd.exe is missing, so where Windows keeps this user's" \
        "AppData cannot be worked out from here. The usual reason is interop:" \
        "[interop] appendWindowsPath=false in /etc/wsl.conf keeps cmd.exe off" \
        "PATH, and [interop] enabled=false stops Windows binaries running at" \
        "all. Nothing was written anywhere." \
        "Fix: run this from a shell that has cmd.exe on PATH, or turn interop" \
        "back on in /etc/wsl.conf (it takes a wsl --shutdown to apply), then" \
        "re-run ./setup.sh."
    else
      # cmd.exe ends the value with a CR. Its stderr is kept rather than
      # dropped: when this comes back empty, that message is the only account
      # of why.
      #
      # The `|| true` is the one place in this file that lets a pipeline fail on
      # purpose: a cmd.exe that cannot run, or a pipefail on either half, would
      # otherwise end the run right here under errexit -- before the case below
      # can say which of the three ways it went wrong. The empty answer that
      # leaves behind is exactly what that case is written to name.
      appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' | tr -d '\r' || true)"
      # The guard is what keeps wslpath from being handed the empty string that
      # a cmd.exe answering with nothing leaves here. wslpath keeps its stderr
      # for the same reason cmd.exe does.
      #
      # Its answer replaces cmd.exe's only when it succeeds. Assigning the
      # output unconditionally lost the diagnosis: a wslpath that fails prints
      # nothing, so the answer the failure message below quotes came out blank,
      # and "cmd.exe returned the literal %LOCALAPPDATA%" read exactly like
      # "cmd.exe answered nothing at all" (measured: three stubs -- a literal, an
      # empty answer, and a wslpath that fails on a good one -- printed the same
      # blank line). Keeping cmd.exe's answer means each of the three says
      # something different.
      if [ -n "$appdata" ]; then
        if resolved="$(wslpath "$appdata")"; then
          appdata="$resolved"
        fi
      fi
      # Absolute, or this went wrong. An empty answer is not the only wrong
      # one: cmd.exe echoes an undefined variable back as the literal
      # %LOCALAPPDATA% (measured), which is not empty, so a test for emptiness
      # alone carries that string into wt_dir, where the [ -d ] below finds no
      # such directory and the run ends 0 saying Windows Terminal is not
      # installed -- a managed file missed, counted as a skip, and blamed on
      # something that may well be there. What wslpath answers for a Windows
      # path begins with /, so that is the test, and it also catches a wslpath
      # that succeeded while writing only part of an answer (one that fails
      # leaves cmd.exe's answer in place, which does not begin with / either).
      #
      # What the test rests on, and what has not been checked: it catches the
      # literal only while wslpath refuses to translate it. A wslpath that took
      # %LOCALAPPDATA% for a relative path and answered with something beginning
      # with / would carry it straight through here, and the run would be back
      # to blaming a Windows Terminal that may well be installed (measured with
      # two stubs: one that fails on the literal reaches record_failure and exit
      # 1, one that answers /mnt/c/%LOCALAPPDATA% prints "Windows Terminal not
      # installed (...)" and exits 0). Which of the two the real wslpath does
      # cannot be found out from a Mac, so it stands unverified beside the other
      # thing only a WSL machine can settle -- whether Windows Terminal rebuilds
      # its per-distro profiles after the overwrite (design.md 4.5, 4.6).
      case "$appdata" in
        /*)
          wt_dir="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
          if [ -d "$wt_dir" ]; then
            # Windows Terminal writes this file itself, and the overwrite costs
            # it nothing it cannot rebuild: the profiles it generates per WSL
            # distro are this machine's inventory and it generates them again.
            deploy "$DOTFILES_DIR/windows-terminal/settings.json" "$wt_dir/settings.json"
          else
            # The Windows side was found and Windows Terminal is not on it.
            # There is nothing to deploy to, so this is a skip and not a
            # failure -- on stderr with the other notices about a managed file
            # that was not deployed. LocalState is not made here, for the reason
            # the Darwin arm gives where it does make DynamicProfiles: this one
            # is part of an installed package's footprint, not a drop box.
            echo "Windows Terminal not installed ($wt_dir does not exist). Skipping." >&2
          fi
          ;;
        *)
          # Not the same thing as Windows Terminal being absent, and told apart
          # from it: both tools answered to command -v, so this is WSL and there
          # is a Windows side -- what could not be found is where it keeps the
          # user's AppData. Windows Terminal may well be installed, so a managed
          # file was missed and this counts like any other miss.
          #
          # The answer quoted is cmd.exe's own unless wslpath replaced it with
          # one of its own, so the three ways here differ on the page: the
          # literal %LOCALAPPDATA%, a wslpath that could not translate a real
          # Windows path (the path is shown, wslpath's complaint is just above),
          # and a cmd.exe that said nothing (which is named as nothing rather
          # than left as an empty line).
          record_failure "Windows Terminal's settings.json was not deployed." \
            "%LOCALAPPDATA% did not resolve to a path. The answer was:" \
            "  ${appdata:-(nothing at all)}" \
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

# The guard is not tidiness, and it is one instance of the rule stated at the
# traps: under set -u, bash 3.2 reads "${arr[@]}" on an empty array as an
# unbound variable and kills the script on the spot, and with an EXIT trap set
# the run then ends 0, so it used to die quietly (measured with /bin/bash
# 3.2.57: with this guard removed, a run that deployed everything printed
# "FAILURES[@]: unbound variable" and still exited 0; with REACHED_END in place
# the same run prints it and exits 1). "${#FAILURES[@]}" is safe on an empty
# array, so it is what decides whether the loop below is reached at all.
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
  # One of the two ends this script has. Set here rather than at the top of the
  # block so that a run which dies part-way through printing the list is still
  # a run that did not reach an end.
  REACHED_END=1
  exit 1
fi

echo "Done."
# The other end. Nothing follows it, so an exit 0 that the EXIT trap sees
# without this having been set is a run that stopped somewhere it never meant
# to (see the traps).
REACHED_END=1
