#!/bin/bash
set -euo pipefail

# Before the traps: past them a `set -u` fatal comes back as exit 0 (see cleanup).
# An unset HOME used to deploy herdr's config, die on the first bare $HOME, deploy
# no iTerm2 profile, list no failure and exit 0 (measured).
: "${HOME:?HOME is not set. Every path this script deploys to is built from it.}"

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# An XDG base that is not an absolute path is invalid and must be ignored: taken
# literally it puts every destination under whichever directory the run started
# in, somewhere new each time (measured). The answer comes back in xdg_base and
# not on stdout so the note left in XDG_IGNORED survives the call.
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

# Backups go to a directory of their own: iTerm2 reads every file in
# DynamicProfiles except names beginning with a dot or ending with a tilde
# (measured in the binary's strings), so a .bak left beside the profile should be
# read as a second profile with a duplicate Guid.
set_xdg_base XDG_STATE_HOME "${XDG_STATE_HOME:-}" "$HOME/.local/state"
BACKUP_DIR="$xdg_base/dotfiles-backups"

FAILURES=()

# The leading dot is what makes a half-written file safe in DynamicProfiles: a
# name beginning with a dot is one of the two kinds iTerm2 skips (see
# BACKUP_DIR). Built here and nowhere else, so sweep_tmp_files matches the same
# files.
tmp_prefix_for() {
  printf '%s/.%s.dotfiles-tmp.' "$(dirname "$1")" "$(basename "$1")"
}

tmp_for() {
  printf '%s%s' "$(tmp_prefix_for "$1")" "$$"
}

# BACKUP_DIR is a tree that mirrors the repository: the key is the managed
# file's path relative to DOTFILES_DIR, not the deploy destination's
# basename. Two destinations can share a basename (claude/settings.json and
# windows-terminal/settings.json both land in a settings.json); their repo
# paths never collide, so this guarantees uniqueness without a convention to
# maintain by hand (.rn/20260906-issue-9/design.md §4.3).
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
# INT and TERM exit rather than only cleaning up: a trap that returns leaves bash
# carrying on to the next deployment.
#
# REACHED_END: with an EXIT trap set, bash 3.2 hands a `set -u` fatal back as exit
# 0 and $? in the trap does not recover it (measured, /bin/bash 3.2.57). So only
# the two places that end this script on purpose set the flag, and an exit 0 that
# did not come from one of them is turned into 1. The test on $st leaves the other
# ways out alone -- a run killed by SIGTERM exits 143 through its own trap.
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

# Returns 0 so that record_failure does too: its caller in the WSL branch runs
# under errexit, and a value taken from whatever the last echo returned would make
# that call a coin toss.
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

# The timestamp counts whole seconds, so the count-up below is what keeps a second
# backup taken within the same second from writing over the first, which deploy
# has already promised the user by path (measured).
#
# The path goes back to the caller on stdout and not through a global: a global
# outlives the call, and a later deploy's cleanup then deleted a backup the run
# had already promised (measured).
backup_file() {
  local dst="$1" tmp="$2" src_rel="$3" stem bak count=1
  # -e reads through a symlink, so a dangling one takes no backup at all: deploy
  # replaces the link with a regular file and there is nothing to restore.
  [ -e "$dst" ] || return 0
  stem="$(backup_path_for "$src_rel").$(date +%Y%m%d%H%M%S)"
  bak="$stem.bak"
  while [ -e "$bak" ]; do
    bak="$stem-$count.bak"
    count=$((count + 1))
  done
  mkdir -p "$(dirname "$bak")" || return 1
  # Written through a temp file and renamed: a Ctrl-C during the copy leaves the
  # script through the INT trap before cp's exit status could be tested, and a
  # part-written .bak stayed behind under that name (measured).
  if ! cp "$dst" "$tmp" || ! mv -f "$tmp" "$bak"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$bak"
}

# Always returns 0, and callers rely on that. Returning a status instead cost more
# than it was worth: every call needed `|| true`, which bash applies to the whole
# call, so errexit was switched off for everything inside this function too -- a
# bare line added here failed in silence and let the run end 0 having deployed
# nothing (measured).
deploy() {
  local src="$1" dst="$2" src_rel dir backup="" was_link=""
  # Every caller passes src as "$DOTFILES_DIR/...", so stripping that prefix
  # gives the file's path within the repository -- the key backup_path_for
  # keys backups on (.rn/20260906-issue-9/design.md §4.3).
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
    # -f because a read-only dst makes mv ask, but only when stdin is a tty, which is
    # exactly how a person runs this. The prompt defaults to "no" and mv then exits 0
    # having replaced nothing, so the run announced a file it had not written
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

if ! command -v herdr &>/dev/null; then
  echo "herdr not found. Its config is managed here all the same:"
fi
deploy "$DOTFILES_DIR/herdr/config.toml" "$HERDR_CONFIG"

deploy "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
deploy "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
deploy "$DOTFILES_DIR/claude/scripts/statusline.sh" "$HOME/.claude/scripts/statusline.sh"

case "$(uname -s)" in
  Darwin)
    # Deployed whether or not iTerm2 is on this machine, and deploy's mkdir -p makes
    # the directory: a Mac without iTerm2 still has to end the run with the
    # profile in place. The WSL arm does the opposite with LocalState
    # (.rn/20260822-herdr4mac/design.md §4.5).
    iterm_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    deploy "$DOTFILES_DIR/iterm2/herdr.json" "$iterm_dir/herdr.json"

    # The same value as "Guid" in iterm2/herdr.json, which cannot say so itself --
    # JSON takes no comments. Change one without the other and this compares
    # against a profile no file defines: the warning below then fires on every
    # run, including where herdr is already the default, and stops meaning
    # anything.
    iterm_profile_guid="8f7b6c1e-3d2a-4e9b-9c5d-71a2b4e6f038"
    iterm_default_menu="iTerm2 > Settings > Profiles > herdr > Other Actions... > Set as Default"
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
    # The kernel answers whether this is WSL: Microsoft's release string carries
    # "microsoft" and nothing else here does. The tools were the test before and
    # were the wrong one -- [interop] appendWindowsPath=false keeps cmd.exe off
    # PATH, so a real WSL was told "Not WSL", counted as having nowhere to deploy
    # to, and left at exit 0 (measured).
    if [ ! -r /proc/sys/kernel/osrelease ] || ! grep -qi microsoft /proc/sys/kernel/osrelease; then
      echo "Not WSL. Skipping Windows Terminal." >&2
    elif ! command -v wslpath &>/dev/null || ! command -v cmd.exe &>/dev/null; then
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
      appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' | tr -d '\r' || true)"
      if [ -n "$appdata" ]; then
        if resolved="$(wslpath "$appdata")"; then
          appdata="$resolved"
        fi
      fi
      # Absolute, or this went wrong. cmd.exe echoes an undefined variable back as
      # the literal %LOCALAPPDATA% (measured), which a test for emptiness alone
      # would carry into wt_dir, where the [ -d ] below finds no such directory
      # and the run ends 0 saying Windows Terminal is not installed -- a managed
      # file missed and counted as a skip. What wslpath answers for a Windows path
      # begins with /, so that is the test. What it rests on:
      # .rn/20260822-herdr4mac/design.md §4.5.
      case "$appdata" in
        /*)
          wt_dir="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
          if [ -d "$wt_dir" ]; then
            deploy "$DOTFILES_DIR/windows-terminal/settings.json" "$wt_dir/settings.json"
          else
            # A skip and not a failure: the Windows side was found and there is
            # nothing to deploy to. LocalState is an installed package's
            # footprint and not a drop box, so unlike DynamicProfiles it is
            # not made here.
            echo "Windows Terminal not installed ($wt_dir does not exist). Skipping." >&2
          fi
          ;;
        *)
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

# herdr integration realization (.rn/20260906-issue-9/design.md §4.1/§4.2): hooks.SessionStart and
# the $HOME/.claude/hooks/herdr-agent-state.sh script it calls are not
# settings.json data -- `herdr integration install claude` writes
# hooks.SessionStart into the live settings.json itself and deploys the
# script it names (measured against an isolated $HOME), so keeping that key
# in the repo's settings.json would be a second, driftable copy of what
# herdr already manages, same reasoning as the plugin realization below.
# Placed after the OS branch for the same reason as that step: a failure
# here cannot pull iTerm2/Windows Terminal into it.
#
# No precheck: the wholesale deploy() above always redeploys settings.json
# from the repo copy, which does not carry hooks.SessionStart, so this step
# always starts from "not registered" and always needs to run, by this
# repo's own design (same reasoning as the plugin step below). A
# `herdr integration status | grep -q ...` precheck was tried and measured
# broken besides: `grep -q` exits as soon as it matches, closing the pipe
# while `herdr integration status` is still writing, which kills it with
# SIGPIPE -- under this script's `set -o pipefail` that non-zero exit fails
# the whole pipeline regardless of what grep matched, so the "already
# current" branch could never be taken (measured: three consecutive runs
# against an isolated $HOME all took the install branch, never the skip
# one). `herdr integration install claude` is measured idempotent (three
# consecutive real runs, same end state, no duplicate SessionStart entry),
# so calling it unconditionally is safe.
if ! command -v herdr &>/dev/null; then
  warn "herdr is missing, so its Claude Code SessionStart hook was not realized." \
    "Turning it into an installed hook needs the herdr command itself." \
    "settings.json itself was still deployed above and is unaffected." \
    "Fix: install herdr, then re-run ./setup.sh."
elif herdr integration install claude; then
  echo "Installed/updated herdr's claude integration."
else
  record_failure "herdr's claude integration was not installed." \
    "\`herdr integration install claude\` said why just above." \
    "Fix: once the reason above is gone, re-run ./setup.sh."
fi

# Plugin realization (.rn/20260906-issue-9/design.md §4.2): the marketplace and plugin this repo
# uses are not settings.json data -- Claude Code writes enabledPlugins/
# extraKnownMarketplaces back into the live file itself once a plugin is
# installed, so keeping them in the repo's settings.json would be a second,
# driftable copy of runtime state, not configuration (design.md §5.1, same
# file). This step names them directly instead. Placed after the OS branch so
# a failure here cannot pull iTerm2/Windows Terminal into it, and
# record_failure here cannot make #4's placement result look any different
# (design.md §3.3, §4.2, same file).
CCPM_MARKETPLACE_NAME="ccpm"
CCPM_MARKETPLACE_REPO="lovaizu/ccpm"
CCPM_PLUGIN_ID="rn@ccpm"

if ! command -v claude &>/dev/null; then
  warn "claude is missing, so the $CCPM_MARKETPLACE_NAME marketplace and the $CCPM_PLUGIN_ID plugin were not realized." \
    "Turning them into an actual marketplace and an installed, enabled" \
    "plugin needs the claude command to check current state and act on it." \
    "settings.json itself was still deployed above and is unaffected." \
    "Fix: install claude, then re-run ./setup.sh."
elif ! command -v jq &>/dev/null; then
  warn "jq is missing, so the $CCPM_MARKETPLACE_NAME marketplace and the $CCPM_PLUGIN_ID plugin were not realized." \
    "Reading \`claude plugin marketplace list --json\` to check whether the" \
    "marketplace is already present, before deciding whether to add it," \
    "needs jq." \
    "settings.json itself was still deployed above and is unaffected." \
    "Fix: install jq, then re-run ./setup.sh."
else
  marketplaces_now="$(claude plugin marketplace list --json 2>/dev/null || echo '[]')"

  # Checked before calling `add`, rather than trusting `add` to be safe to
  # repeat: precheck-then-invoke makes the three outcomes in
  # .rn/20260906-issue-9/design.md §4.2 hold whether or not the command
  # itself turns out to be idempotent (§2.1, same file).
  # Marketplace registration is not settings.json data (it survives the
  # wholesale deploy() above), so "already present" is a real, reachable
  # state here -- worth skipping, since `add` re-clones the marketplace repo.
  if echo "$marketplaces_now" | jq -e --arg n "$CCPM_MARKETPLACE_NAME" '.[] | select(.name == $n)' >/dev/null; then
    echo "Marketplace $CCPM_MARKETPLACE_NAME already configured. Skipping."
  elif claude plugin marketplace add "$CCPM_MARKETPLACE_REPO"; then
    echo "Added marketplace $CCPM_MARKETPLACE_NAME ($CCPM_MARKETPLACE_REPO)."
  else
    record_failure "Marketplace $CCPM_MARKETPLACE_NAME ($CCPM_MARKETPLACE_REPO) was not added." \
      "\`claude plugin marketplace add\` said why just above." \
      "The $CCPM_PLUGIN_ID plugin from this marketplace could not be" \
      "installed either, as a result." \
      "Fix: once the reason above is gone, re-run ./setup.sh."
  fi

  # No precheck here, unlike the marketplace above: "already installed and
  # enabled" cannot be a state this step finds itself in. The wholesale
  # deploy() above always redeploys settings.json from the repo copy, which
  # does not carry enabledPlugins (4.2) -- so every run starts with the
  # plugin off, by this repo's own design, and always needs re-enabling.
  # A precheck for it would never take its skip branch. `claude plugin
  # install` is measured idempotent (2.1: two consecutive real runs, same
  # end state, no error), so calling it unconditionally is safe.
  # -y answers the marketplace-declared-command prompt a plugin's install can
  # raise, so this does not sit waiting for input that a non-interactive run
  # never sends.
  if claude plugin install "$CCPM_PLUGIN_ID" -y; then
    echo "Installed plugin $CCPM_PLUGIN_ID."
  else
    record_failure "Plugin $CCPM_PLUGIN_ID was not installed." \
      "\`claude plugin install\` said why just above -- the" \
      "$CCPM_MARKETPLACE_NAME marketplace not having been added is the usual" \
      "reason." \
      "Fix: once the reason above is gone, re-run ./setup.sh."
  fi
fi

# Not tidiness: under set -u, bash 3.2 reads "${arr[@]}" on an empty array as an
# unbound variable and kills the script on the spot, and with an EXIT trap set the
# run then ends 0 -- it used to die quietly (measured, /bin/bash 3.2.57).
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo >&2
  echo "Finished with ${#FAILURES[@]} failure(s):" >&2
  for failed in "${FAILURES[@]}"; do
    echo "  - $failed" >&2
  done
  echo "Each one is explained above. Everything else was deployed or skipped as noted." >&2
  # Set here rather than at the top of the block, so that a run which dies
  # part-way through printing the list is still a run that did not reach an end.
  REACHED_END=1
  exit 1
fi

echo "Done."
# The other end. An exit 0 that the EXIT trap sees without this having been set is
# a run that stopped somewhere it never meant to (see the traps).
REACHED_END=1
