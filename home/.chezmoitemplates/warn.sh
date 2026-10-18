# Every run_ script includes this, so a reason reads the same whichever
# script it comes from.
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
