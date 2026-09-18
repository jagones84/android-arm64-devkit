#!/usr/bin/env bash
# Tear down the adb session cleanly.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/../config.sh" ] && . "$HERE/../config.sh"

ADB_REMOTE_HOST="${ADB_REMOTE_HOST:-}"
ADB_REMOTE_BIN="${ADB_REMOTE_BIN:-adb}"
adb_call() {
  if [ -n "$ADB_REMOTE_HOST" ]; then
    ssh -o BatchMode=yes "$ADB_REMOTE_HOST" "'${ADB_REMOTE_BIN:-adb}' $*"
  else
    adb "$@"
  fi
}

DEV="$(cat "$HERE/../.adb-device" 2>/dev/null || true)"
if [ -n "${ADB_HOST:-}" ] && [ -n "$DEV" ]; then
  echo "disconnecting $DEV"
  adb_call disconnect "$DEV" | sed 's/^/  /'
fi

# A wedged server is the usual cause of "device offline".
if [ "${1:-}" = "--restart-server" ]; then
  echo "restarting adb server"
  adb_call kill-server || true
  adb_call start-server || true
fi

rm -f "$HERE/../.adb-device"
echo "done"
