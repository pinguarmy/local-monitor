# Sourced (not executed) by build-direct.sh, test-direct.sh and build-app.sh; expects ROOT.
# Sets ARCH and OUT for the raw swiftc build:
#   LOCAL_MONITOR_ARCH unset or empty -> host architecture (uname -m), output .build/direct
#   LOCAL_MONITOR_ARCH=arm64|x86_64   -> that architecture,         output .build/direct-<arch>
if [ -n "${LOCAL_MONITOR_ARCH:-}" ]; then
  ARCH="$LOCAL_MONITOR_ARCH"
  OUT_NAME="direct-$ARCH"
else
  ARCH="$(uname -m)"
  OUT_NAME="direct"
fi
# Validate before the value becomes part of a path.
case "$ARCH" in
  arm64|x86_64) ;;
  *) printf 'Unsupported architecture: %s (LOCAL_MONITOR_ARCH may be arm64 or x86_64)\n' "$ARCH" >&2; exit 1 ;;
esac
OUT="$ROOT/.build/$OUT_NAME"
unset OUT_NAME
