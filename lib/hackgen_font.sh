install_hackgen_font() {
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
