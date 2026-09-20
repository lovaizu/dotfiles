deploy_darwin() {
  # Deployed regardless of whether iTerm2 is installed (deploy's mkdir -p
  # makes the directory) -- a Mac without iTerm2 still ends the run with
  # the profile in place. deploy_windows_terminal does the opposite: it
  # deploys only when the Windows-side directory already exists.
  local iterm_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  deploy "$DOTFILES_DIR/iterm2/herdr.json" "$iterm_dir/herdr.json"

  # Must match "Guid" in iterm2/herdr.json -- JSON has no comments to say
  # so. Out of sync, this compares against a profile no file defines and
  # the warning below fires on every run, even when herdr already is
  # default.
  local iterm_profile_guid="8f7b6c1e-3d2a-4e9b-9c5d-71a2b4e6f038"
  local iterm_default_menu="iTerm2 > Settings > Profiles > herdr > Other Actions... > Set as Default"
  local default_guid
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

  # Not a managed file, so its absence is never a failure -- nothing else
  # here depends on it, and macOS just falls back to another monospace font
  # until it's installed.
  local font_cost=(
    "The iTerm2 profile names HackGen; macOS falls back to another monospace"
    "font until it is installed. Not a managed file, so this is not a failure."
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
}
