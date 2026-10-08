# Runs before anything that needs these commands, so one ./setup.sh on a
# fresh machine gets as far as it can: the herdr integration needs herdr,
# and the statusline and the ccpm plugin step need jq. Neither is a managed
# file, so a failed install only warns; the steps that need the command warn
# again with their own cost.
install_tools() {
  install_herdr
  install_jq
}

install_herdr() {
  if command -v herdr &>/dev/null; then
    echo "herdr already installed. Skipping."
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      # Same channel the Mac already uses, so brew keeps it updated.
      if ! command -v brew &>/dev/null; then
        warn "Homebrew is not installed, so herdr was not installed either." \
          "Fix: install Homebrew, or herdr by hand (https://herdr.dev/docs/install/)," \
          "and re-run ./setup.sh."
      elif ! brew install herdr; then
        warn "brew install herdr failed." \
          "brew said why just above." \
          "Fix: once the reason is gone, re-run ./setup.sh."
      fi
      ;;
    *)
      # The official installer: no root, checks the binary's SHA-256, puts
      # it in ~/.local/bin (read, 2026-10-08).
      if ! curl -fsSL https://herdr.dev/install.sh | sh; then
        warn "herdr's installer failed." \
          "It said why just above." \
          "Fix: once the reason is gone, re-run ./setup.sh."
      fi
      ;;
  esac
  # The installer exits 0 even when its directory is not on PATH.
  if ! command -v herdr &>/dev/null; then
    warn "herdr is still not found on PATH." \
      "If it was installed above, its directory is not on PATH." \
      "Fix: add it to PATH (the installer printed the line), then re-run ./setup.sh."
  fi
}

install_jq() {
  if command -v jq &>/dev/null; then
    echo "jq already installed. Skipping."
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      if ! command -v brew &>/dev/null; then
        warn "Homebrew is not installed, so jq was not installed either." \
          "Fix: install Homebrew, or jq by hand, and re-run ./setup.sh."
      elif ! brew install jq; then
        warn "brew install jq failed." \
          "brew said why just above." \
          "Fix: once the reason is gone, re-run ./setup.sh."
      fi
      ;;
    *)
      # apt over a downloaded binary so apt upgrade keeps it current; the
      # cost is a sudo password prompt during the run.
      if ! command -v apt-get &>/dev/null; then
        warn "apt-get is not available, so jq was not installed." \
          "Fix: install jq with this system's package manager, then re-run ./setup.sh."
      elif ! sudo apt-get install -y jq; then
        warn "sudo apt-get install -y jq failed." \
          "It said why just above (sudo needs a terminal to ask for the password)." \
          "Fix: once the reason is gone, re-run ./setup.sh."
      fi
      ;;
  esac
}
