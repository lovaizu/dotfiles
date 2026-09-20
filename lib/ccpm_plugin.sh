# Called after the OS-specific deploy so a failure here can't pull
# iTerm2/Windows Terminal into it, and record_failure here can't change
# their result.
realize_ccpm_plugin() {
  # The marketplace and plugin are not settings.json data -- Claude Code
  # writes enabledPlugins/extraKnownMarketplaces back into the live file
  # once a plugin is installed, so keeping them in the repo's settings.json
  # would be a second, driftable copy of runtime state, not configuration.
  # This step names them directly instead.
  local marketplace_name="ccpm"
  local marketplace_repo="lovaizu/ccpm"
  local plugin_id="rn@ccpm"

  if ! command -v claude &>/dev/null; then
    warn "claude is missing, so the $marketplace_name marketplace and the $plugin_id plugin were not realized." \
      "Turning them into an actual marketplace and an installed, enabled" \
      "plugin needs the claude command to check current state and act on it." \
      "settings.json itself was still deployed above and is unaffected." \
      "Fix: install claude, then re-run ./setup.sh."
    return 0
  fi
  if ! command -v jq &>/dev/null; then
    warn "jq is missing, so the $marketplace_name marketplace and the $plugin_id plugin were not realized." \
      "Reading \`claude plugin marketplace list --json\` to check whether the" \
      "marketplace is already present, before deciding whether to add it," \
      "needs jq." \
      "settings.json itself was still deployed above and is unaffected." \
      "Fix: install jq, then re-run ./setup.sh."
    return 0
  fi

  local marketplaces_now
  marketplaces_now="$(claude plugin marketplace list --json 2>/dev/null || echo '[]')"

  # Checked before calling `add` rather than trusting it to be safe to
  # repeat, so "already present" / "just added" / "add failed" hold either
  # way. Marketplace registration survives the wholesale deploy() above, so
  # "already present" is a real, reachable state -- worth skipping, since
  # `add` re-clones the marketplace repo.
  if echo "$marketplaces_now" | jq -e --arg n "$marketplace_name" '.[] | select(.name == $n)' >/dev/null; then
    echo "Marketplace $marketplace_name already configured. Skipping."
  elif claude plugin marketplace add "$marketplace_repo"; then
    echo "Added marketplace $marketplace_name ($marketplace_repo)."
  else
    record_failure "Marketplace $marketplace_name ($marketplace_repo) was not added." \
      "\`claude plugin marketplace add\` said why just above." \
      "The $plugin_id plugin from this marketplace could not be" \
      "installed either, as a result." \
      "Fix: once the reason above is gone, re-run ./setup.sh."
  fi

  # No precheck here, unlike the marketplace: "already installed and
  # enabled" can't be a state this finds itself in -- deploy() always
  # redeploys settings.json without enabledPlugins, so the plugin starts
  # off on every run and always needs re-enabling. `claude plugin install`
  # is measured idempotent (two real runs, same end state), so calling it
  # unconditionally is safe. -y answers the install's own prompt so a
  # non-interactive run never sits waiting for input.
  if claude plugin install "$plugin_id" -y; then
    echo "Installed plugin $plugin_id."
  else
    record_failure "Plugin $plugin_id was not installed." \
      "\`claude plugin install\` said why just above -- the" \
      "$marketplace_name marketplace not having been added is the usual" \
      "reason." \
      "Fix: once the reason above is gone, re-run ./setup.sh."
  fi
}
