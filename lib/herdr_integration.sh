# Called after the OS-specific deploy so a failure here can't pull
# iTerm2/Windows Terminal into it.
realize_herdr_integration() {
  # hooks.SessionStart and the script it calls are not settings.json data --
  # `herdr integration install claude` writes hooks.SessionStart into the
  # live settings.json and deploys the script it names (measured against an
  # isolated $HOME). Keeping that key in the repo's settings.json would be a
  # second, driftable copy of what herdr already manages -- same reasoning
  # as realize_ccpm_plugin.
  #
  # No precheck: deploy() always redeploys settings.json from the repo
  # copy, which never carries hooks.SessionStart, so this always starts
  # from "not registered" and always needs to run. A `herdr integration
  # status | grep -q ...` precheck was tried and measured broken: grep
  # exits as soon as it matches, killing the still-writing `status` with
  # SIGPIPE, which this script's pipefail turns into a failure regardless
  # of what grep matched -- the "already current" branch could never be
  # taken (measured: three isolated runs, always the install branch).
  # `herdr integration install claude` is measured idempotent (three real
  # runs, same end state, no duplicate entry), so calling it
  # unconditionally is safe.
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
}
