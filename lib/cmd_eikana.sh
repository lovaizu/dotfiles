CMD_EIKANA_CASK="dominion525/tap/cmd-eikana"
CMD_EIKANA_BUNDLE_ID="io.github.dominion525.cmd-eikana"

# Prints the PID of every process holding a Quartz event tap, one per line.
# CGEventTapInformation is 48 bytes with tappingProcess at byte 24, so the
# 7th of each 12 uint32s (measured on arm64, macOS 26).
event_tap_owners() {
  osascript -l JavaScript \
    -e 'ObjC.import("CoreGraphics"); ObjC.import("Foundation");' \
    -e 'ObjC.bindFunction("CGGetEventTapList", ["int", ["unsigned int", "void *", "unsigned int *"]]);' \
    -e 'var n = Ref("unsigned int"); $.CGGetEventTapList(0, null, n);' \
    -e 'var d = $.NSMutableData.dataWithLength(48 * n[0]); $.CGGetEventTapList(n[0], d.mutableBytes, n);' \
    -e 'd.base64EncodedStringWithOptions(0).js' |
    base64 -d | od -v -A n -t u4 | tr -s ' ' '\n' | sed '/^$/d' |
    awk 'NR % 12 == 7'
}

# The app is what selects the input source, so the guarantee is "it holds a
# key tap", not "it is installed". It creates the tap only once both
# Input Monitoring and Accessibility are granted, and neither can be granted
# from a script, nor read back from one: the TCC database is closed to the
# terminal without Full Disk Access (measured).
realize_cmd_eikana() {
  local cost=(
    "Until this is fixed, left and right ⌘ alone do nothing, and the only"
    "way to switch input is the fn (globe) key."
  )
  if ! command -v brew &>/dev/null; then
    record_failure "Homebrew is not installed, so ⌘英かな was not installed either." \
      "${cost[@]}" \
      "Fix: install Homebrew and re-run ./setup.sh."
    return 0
  fi
  if brew list --cask "$CMD_EIKANA_CASK" &>/dev/null; then
    echo "⌘英かな already installed. Skipping."
  # Current Homebrew refuses a cask from a tap that was never tapped
  # (measured), so the tap comes first.
  elif ! brew tap dominion525/tap || ! brew install --cask "$CMD_EIKANA_CASK"; then
    record_failure "brew install --cask $CMD_EIKANA_CASK failed." \
      "brew said why just above." \
      "${cost[@]}" \
      "Fix: once the reason is gone, re-run ./setup.sh."
    return 0
  fi

  # First launch is what registers it as a login item and asks for the
  # permissions; later launches come from that login item.
  if ! pgrep -f "/⌘英かな.app/Contents/MacOS/" >/dev/null; then
    open -b "$CMD_EIKANA_BUNDLE_ID"
    sleep 2
  fi
  local pid
  pid="$(pgrep -f "/⌘英かな.app/Contents/MacOS/" | head -n 1)"
  if [ -z "$pid" ]; then
    record_failure "⌘英かな did not start." \
      "${cost[@]}" \
      "Fix: open ⌘英かな from Applications to see why, then re-run ./setup.sh."
    return 0
  fi
  if ! event_tap_owners | grep -qx "$pid"; then
    record_failure "⌘英かな is running but cannot see the keyboard yet." \
      "Only you can grant this. In System Settings > Privacy & Security, turn" \
      "⌘英かな on under both Input Monitoring and Accessibility." \
      "${cost[@]}" \
      "Fix: grant both, then re-run ./setup.sh."
    return 0
  fi
  echo "⌘英かな is running with keyboard access."
}
