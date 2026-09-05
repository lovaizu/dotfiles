#!/bin/bash
set -euo pipefail

# Before the traps rather than after: past them a `set -u` fatal comes back as
# exit 0 (see cleanup), and that is exactly how this used to bite -- an unset
# HOME deployed herdr's config, died on the first bare $HOME, deployed no iTerm2
# profile, listed no failure and exited 0 (measured). An empty HOME is as useless
# as an unset one, and :? refuses both.
: "${HOME:?HOME is not set. Every path this script deploys to is built from it.}"

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# An XDG base directory that is not an absolute path is invalid and must be
# ignored: taking such a value literally makes every destination relative to
# whichever directory the run was started in, somewhere new each time (measured).
# The warning that says the value was ignored is spoken further down, where warn
# exists.
#
# The answer comes back in xdg_base rather than on stdout because a command
# substitution runs in a subshell, and the note left in XDG_IGNORED would not
# survive it.
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

# herdr reads $XDG_CONFIG_HOME when it is set and does not fall back to
# ~/.config, so a hard $HOME/.config here would deploy a file herdr never reads
# and still call the run a success (measured).
set_xdg_base XDG_CONFIG_HOME "${XDG_CONFIG_HOME:-}" "$HOME/.config"
HERDR_CONFIG="$xdg_base/herdr/config.toml"

# Backups go to a directory of their own rather than beside the file: iTerm2
# reads every file in DynamicProfiles except the ones whose name begins with a
# dot or ends with a tilde (measured in the binary's strings), and
# herdr.json.<timestamp>.bak is neither, so one left beside the profile should be
# read as a second profile with a duplicate Guid. Should -- that reading is an
# inference, and keeping backups elsewhere costs nothing either way.
set_xdg_base XDG_STATE_HOME "${XDG_STATE_HOME:-}" "$HOME/.local/state"
BACKUP_DIR="$xdg_base/dotfiles-backups"

# What this run could not deploy, one entry per file. The run names every entry
# at the end and exits non-zero; this list is what keeps a partial run from
# passing for success (design.md 4.6).
FAILURES=()

# The name of the half-written file for a destination. The leading dot is what
# makes it safe in DynamicProfiles: a name beginning with a dot is one of the two
# kinds iTerm2 skips (see BACKUP_DIR), so a file half-way through being deployed
# is never read as a profile.
#
# Built here and nowhere else -- sweep_tmp_files has to find the same files
# again, and a second hand-written copy of the format would let a change to one
# stop the other matching without saying so.
tmp_prefix_for() {
  printf '%s/.%s.dotfiles-tmp.' "$(dirname "$1")" "$(basename "$1")"
}

# The pid gives each run a name of its own, so two runs at once write into two
# files. That is all it buys: it is not what would make two runs at once safe,
# since the sweep below removes every temp file beside the destination, other
# runs' included (measured).
tmp_for() {
  printf '%s%s' "$(tmp_prefix_for "$1")" "$$"
}

# Where the backup of dst lives, before the timestamp is added. The name is the
# basename and nothing else, so BACKUP_DIR is one flat namespace and the managed
# files must have basenames that differ -- left as a rule rather than a runtime
# check, for the reason design.md 4.6 gives.
backup_path_for() {
  printf '%s/%s' "$BACKUP_DIR" "$(basename "$1")"
}

# Remove the temp files earlier runs left beside a destination -- every one of
# them, whichever run wrote it, since the glob is on the shared prefix and not on
# this run's pid (measured). A run killed outright leaves one, and without this
# sweep nothing would ever remove it (measured): the leading dot that keeps
# iTerm2 from reading such a file also keeps a plain ls from showing it.
sweep_tmp_files() {
  rm -f "$(tmp_prefix_for "$1")"* 2>/dev/null || true
}

# The temp files this run is part-way through writing. Empty whenever there is
# none, and rm is content with that (measured: rm -f "" exits 0 and says nothing).
DEPLOY_TMP=""
BACKUP_TMP=""
remove_pending_tmp() {
  # A dst whose directory has gone makes even rm complain; nothing here is
  # worth a message.
  rm -f "$DEPLOY_TMP" "$BACKUP_TMP" 2>/dev/null || true
  DEPLOY_TMP=""
  BACKUP_TMP=""
}
# INT and TERM exit rather than only cleaning up: a trap that returns leaves bash
# carrying on to the next deployment, so Ctrl-C would stop nothing.
#
# REACHED_END is there because with an EXIT trap set, bash 3.2 hands a `set -u`
# fatal back as exit 0, and reading $? in the trap does not recover it -- the trap
# is handed 0 for that failure while it is handed 1 for an ordinary errexit
# failure (measured with /bin/bash 3.2.57). So only the two places that end this
# script on purpose set the flag, and an exit 0 that did not come from one of them
# is turned into 1. The test on $st keeps that from flattening the other ways out:
# a run killed by SIGTERM leaves through its own trap with 143 (measured).
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
# the caller's detail lines indented under it, a blank line. All of it on stderr,
# beside the command's own complaint that it explains -- on stdout the two land
# in different streams and a caller reading either alone gets half the story
# (measured). Which of the three notification shapes to use is design.md 4.6.
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
# detail lines are the caller's, because what to do about it differs.
record_failure() {
  FAILURES+=("$1")
  warn "$@"
}

# Copy an existing dst into BACKUP_DIR and print where it went. Prints nothing
# when dst is not there yet.
#
# The timestamp counts whole seconds, so the count-up below is what keeps a
# second backup taken within the same second from writing over the first, which
# deploy has already promised the user by path (measured: with herdr's theme
# rewritten between two runs, the pair left config.toml.<ts>.bak and
# config.toml.<ts>-1.bak).
#
# The path goes back to the caller on stdout rather than through a global. A
# global outlives the call, and a later deploy's cleanup then deleted a backup
# the run had already promised the user (measured).
#
# The temp file to write through is handed in rather than worked out here, for
# the reason deploy gives where it works it out.
backup_file() {
  local dst="$1" tmp="$2" stem bak count=1
  # -e reads through a symlink, so a dangling one takes no backup at all: deploy
  # replaces the link with a regular file and there is nothing to restore. The
  # warning deploy prints after the rename is what covers that (design.md 4.6).
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
  # Written to a temp file and renamed, the way a deployment is: checking cp's
  # exit status cannot do this alone, since a Ctrl-C during the copy leaves the
  # script through the INT trap before any test of it could run, and a
  # part-written .bak stayed behind under that name (measured).
  if ! cp "$dst" "$tmp" || ! mv -f "$tmp" "$bak"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$bak"
}

# Deploy one managed file: replace dst with the dotfiles copy unless it already
# holds it, keeping a backup of whatever was there (design.md 4.6).
#
# Always returns 0, and callers rely on that. Returning a status instead cost
# more than it was worth: every call needed `|| true`, which bash applies to the
# whole call, so errexit was switched off for everything inside this function
# too -- a bare line added here failed in silence and let the run end 0 having
# deployed nothing (measured).
deploy() {
  local src="$1" dst="$2" dir backup="" was_link=""
  # Before the check below rather than after it: a dst that is already correct
  # still has to come out of a directory with no leftovers standing in it, and a
  # sweep that only ran when a backup is actually taken would never reach a
  # machine that is up to date (measured: a backup interrupted mid-copy survived
  # three later runs).
  sweep_tmp_files "$dst"
  sweep_tmp_files "$(backup_path_for "$dst")"
  # Only "identical" is read here; every other answer means carry on and deploy,
  # and they cannot usefully be told apart anyway -- cmp answers 2 for a dst that
  # does not exist yet (measured), which is the ordinary first install.
  #
  # The redirection is because cmp keeps quiet about a difference but not about a
  # dst it cannot open, and a lone "Is a directory" naming neither the managed
  # file nor what to do about it is worse than no message. One of the commands
  # below runs into the same thing and its complaint arrives with the warning
  # that explains it.
  if cmp -s "$src" "$dst" 2>/dev/null; then
    echo "Up to date: $dst"
    return 0
  fi
  # Noted here, said after the rename. Whether dst is a link can only be asked
  # before the rename -- afterwards it is a regular file -- but a run that warned
  # here and then failed to deploy told the user their link was gone while it was
  # still there, and sent them off to make it again (measured).
  if [ -L "$dst" ]; then
    was_link=1
  fi
  dir="$(dirname "$dst")"
  DEPLOY_TMP="$(tmp_for "$dst")"
  # backup_file's temp file is named here, where the trap can see it, and handed
  # in. backup_file runs in a command substitution, and the name would be no use
  # to anyone if it were set in there: a subshell does not run these traps
  # (measured: named inside the substitution, a SIGINT to the process group left
  # the part-written file behind; named here, the same interrupt removes it).
  BACKUP_TMP="$(tmp_for "$(backup_path_for "$dst")")"
  # backup is local, and empty until backup_file has actually taken one, so the
  # cleanup below can only ever remove this file's own backup.
  if mkdir -p "$dir" && cp "$src" "$DEPLOY_TMP" && backup="$(backup_file "$dst" "$BACKUP_TMP")"; then
    # Either renamed onto the .bak or removed by backup_file; either way there
    # is no longer a backup temp file for the trap to worry about.
    BACKUP_TMP=""
    # -f because a read-only dst makes mv ask -- but only when stdin is a tty,
    # which is exactly how a person runs this. The prompt defaults to "no" and
    # mv then exits 0 having replaced nothing, so the run announced a file it
    # had not written and left the temp file behind (measured under a pty).
    if mv -f "$DEPLOY_TMP" "$dst"; then
      # The rename took the temp file away, so there is nothing left to clean.
      DEPLOY_TMP=""
      # Announced after the rename, so the run only ever promises a backup of
      # contents that have actually been replaced.
      if [ -n "$backup" ]; then
        echo "Backed up the previous $dst to $backup"
      fi
      echo "Installed $dst"
      # Only a run that actually replaced the link says so, and it says so here
      # because this is the one thing the backup cannot undo. warn and not
      # record_failure: the managed file does land where it belongs.
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
  # dst is as it was on either way here: nothing above reached the rename, or the
  # rename itself failed -- and mv within one directory either replaces dst or
  # leaves it alone. So this backup is a copy of a file that is still there, and
  # keeping it would add one more identical .bak per run.
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
# exist that early (see set_xdg_base).
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
    # iTerm2 (Dynamic Profile). The profile is deployed whether or not iTerm2 is
    # on this machine, and deploy's mkdir -p makes this directory when it is not
    # there -- which is the opposite of what the WSL arm does with LocalState,
    # for the reason design.md 4.5 gives.
    iterm_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    deploy "$DOTFILES_DIR/iterm2/herdr.json" "$iterm_dir/herdr.json"

    # The key mappings live in the herdr profile, so they only apply to windows
    # opened with it. Warn when it is not the default -- not a failure, since
    # what is missing is a choice only the iTerm2 UI can make.
    # The same value as "Guid" in iterm2/herdr.json, which cannot say so
    # itself -- JSON takes no comments, so the tie is recorded on this side.
    # Change one without the other and this comparison asks about a profile no
    # file defines: the warning below then fires on every run, including on the
    # machine where herdr is already the default, and stops meaning anything.
    iterm_profile_guid="8f7b6c1e-3d2a-4e9b-9c5d-71a2b4e6f038"
    iterm_default_menu="iTerm2 > Settings > Profiles > herdr > Other Actions... > Set as Default"
    # `defaults` failing and `defaults` answering something else are two
    # different machines, and they get two different messages. It fails when the
    # domain is not there at all -- iTerm2 never installed, or installed and
    # never started -- and telling that machine to open iTerm2 > Settings sends
    # it somewhere it cannot go (measured: with a `defaults` that exits 1, the
    # old code took the empty answer for a mismatch and printed the Set as
    # Default instructions).
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

    # HackGen Nerd font (via Homebrew). The one optional thing here: not a
    # managed file, so neither a failed install nor a missing brew is counted a
    # failure (design.md 4.5).
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
      warn "Homebrew is not installed, so the HackGen Nerd font was not installed either." \
        "${font_cost[@]}" \
        "Fix: install the font by hand (see README), or install Homebrew and" \
        "re-run ./setup.sh."
    fi
    ;;
  *)
    # Windows Terminal (Windows side). The kernel answers whether this is WSL at
    # all: Microsoft's release string carries "microsoft" and nothing else here
    # does. The tools were the test before and were the wrong one --
    # [interop] appendWindowsPath=false keeps cmd.exe off PATH, so a real WSL
    # whose settings.json this run is meant to deploy was told "Not WSL",
    # counted as having nowhere to deploy to, and left at exit 0 (measured).
    if [ ! -r /proc/sys/kernel/osrelease ] || ! grep -qi microsoft /proc/sys/kernel/osrelease; then
      # A skip and not a failure -- on stderr all the same, because a managed
      # file not being deployed is the reader's business wherever the reason lies.
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
      # can say which of the three ways it went wrong.
      appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' | tr -d '\r' || true)"
      # The guard is what keeps wslpath from being handed the empty string that
      # a cmd.exe answering with nothing leaves here. wslpath keeps its stderr
      # for the same reason cmd.exe does.
      #
      # Its answer replaces cmd.exe's only when it succeeds. Assigning the
      # output unconditionally lost the diagnosis: a wslpath that fails prints
      # nothing, so the answer the failure message below quotes came out blank,
      # and "cmd.exe returned the literal %LOCALAPPDATA%" read exactly like
      # "cmd.exe answered nothing at all" (measured, three stubs).
      if [ -n "$appdata" ]; then
        if resolved="$(wslpath "$appdata")"; then
          appdata="$resolved"
        fi
      fi
      # Absolute, or this went wrong. An empty answer is not the only wrong one:
      # cmd.exe echoes an undefined variable back as the literal %LOCALAPPDATA%
      # (measured), which a test for emptiness alone would carry into wt_dir,
      # where the [ -d ] below finds no such directory and the run ends 0 saying
      # Windows Terminal is not installed -- a managed file missed, counted as a
      # skip, and blamed on something that may well be there. What wslpath
      # answers for a Windows path begins with /, so that is the test, and it
      # also catches a wslpath that succeeded while writing only part of an
      # answer. What it rests on and cannot verify from a Mac: design.md 4.5.
      case "$appdata" in
        /*)
          wt_dir="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
          if [ -d "$wt_dir" ]; then
            deploy "$DOTFILES_DIR/windows-terminal/settings.json" "$wt_dir/settings.json"
          else
            # A skip and not a failure: the Windows side was found and there is
            # nothing to deploy to. LocalState is not made here, for the reason
            # the Darwin arm gives where it does make DynamicProfiles -- this
            # one is part of an installed package's footprint, not a drop box.
            echo "Windows Terminal not installed ($wt_dir does not exist). Skipping." >&2
          fi
          ;;
        *)
          # Not the same thing as Windows Terminal being absent, and told apart
          # from it: both tools answered to command -v, so this is WSL and there
          # is a Windows side -- what could not be found is where it keeps the
          # user's AppData. So a managed file was missed and this counts like
          # any other miss.
          #
          # The answer quoted is cmd.exe's own unless wslpath replaced it, which
          # is what keeps the three ways here apart on the page.
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

# The guard is not tidiness: under set -u, bash 3.2 reads "${arr[@]}" on an empty
# array as an unbound variable and kills the script on the spot, and with an EXIT
# trap set the run then ends 0, so it used to die quietly (measured with
# /bin/bash 3.2.57). "${#FAILURES[@]}" is safe on an empty array, so it is what
# decides whether the loop below is reached at all.
if [ "${#FAILURES[@]}" -gt 0 ]; then
  # On stderr with the warnings it summarises, for the reason warn gives.
  echo >&2
  echo "Finished with ${#FAILURES[@]} failure(s):" >&2
  for failed in "${FAILURES[@]}"; do
    echo "  - $failed" >&2
  done
  # Not "everything else was deployed": a run can also skip a managed file for
  # want of anywhere to put it, and those are named above too.
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
