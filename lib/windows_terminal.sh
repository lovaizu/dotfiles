deploy_windows_terminal() {
  # The kernel says whether this is WSL: Microsoft's release string carries
  # "microsoft". A tool-presence check was tried before and was wrong --
  # [interop] appendWindowsPath=false hides cmd.exe from PATH, so a real
  # WSL read as "not WSL" and exited 0 with nothing deployed (measured).
  if [ ! -r /proc/sys/kernel/osrelease ] || ! grep -qi microsoft /proc/sys/kernel/osrelease; then
    echo "Not WSL. Skipping Windows Terminal." >&2
    return 0
  fi
  if ! command -v wslpath &>/dev/null || ! command -v cmd.exe &>/dev/null; then
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
    return 0
  fi

  local appdata resolved wt_dir
  appdata="$(cmd.exe /c 'echo %LOCALAPPDATA%' | tr -d '\r' || true)"
  if [ -n "$appdata" ]; then
    if resolved="$(wslpath "$appdata")"; then
      appdata="$resolved"
    fi
  fi
  # Must come back absolute, or this went wrong: cmd.exe echoes an unset
  # variable back as the literal %LOCALAPPDATA% (measured), and testing
  # only for emptiness would carry that into wt_dir, where [ -d ] finds
  # nothing and the run reports Windows Terminal as merely not installed.
  case "$appdata" in
    /*)
      wt_dir="$appdata/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
      if [ -d "$wt_dir" ]; then
        deploy "$DOTFILES_DIR/windows-terminal/settings.json" "$wt_dir/settings.json"
      else
        # A skip, not a failure: LocalState is an installed package's
        # footprint, not a drop box -- unlike DynamicProfiles it is never
        # created here.
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
}
