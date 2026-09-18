#!/usr/bin/env bash
# Connect to an Android device over USB or wireless, without ever assuming a port.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/../config.sh" ] && . "$HERE/../config.sh"

ADB_REMOTE_HOST="${ADB_REMOTE_HOST:-}"
ADB_REMOTE_BIN="${ADB_REMOTE_BIN:-adb}"
ADB_HOST="${ADB_HOST:-}"
ADB_TCP_PORT="${ADB_TCP_PORT:-}"
DEVICE_SERIAL="${DEVICE_SERIAL:-}"

# adb_call runs adb here, or on a remote host over ssh when configured.
adb_call() {
  if [ -n "$ADB_REMOTE_HOST" ]; then
    if [ -n "${ADB_REMOTE_BIN:-}" ]; then
      ssh -o BatchMode=yes "$ADB_REMOTE_HOST" "'$ADB_REMOTE_BIN' $*"
    else
      ssh -o BatchMode=yes "$ADB_REMOTE_HOST" "adb $*"
    fi
  else
    adb "$@"
  fi
}

echo "== transports currently visible =="
LIST="$(adb_call devices -l)"
echo "$LIST" | sed 's/^/  /'

USB_SERIAL="$(echo "$LIST" | awk '/ device / && $1 !~ /:/ {print $1; exit}')"
WIRELESS="$(echo "$LIST" | awk '/ device / && $1 ~ /:/ {print $1; exit}')"

if [ -n "$ADB_HOST" ]; then
  PORT="$ADB_TCP_PORT"
  if [ -z "$PORT" ] && [ -n "$WIRELESS" ]; then
    PORT="${WIRELESS##*:}"
    echo "  discovered port from an existing wireless transport: $PORT"
  fi
  if [ -z "$PORT" ] && [ -n "$USB_SERIAL" ]; then
    PORT="$(adb_call -s "$USB_SERIAL" shell getprop service.adb.tcp.port | tr -d '\r')"
    [ -n "$PORT" ] && echo "  port read over USB from service.adb.tcp.port: $PORT"
  fi
  if [ -z "$PORT" ]; then
    cat >&2 <<'MSG'
No wireless port found.
Wireless debugging is not exposed right now. Either:
  - enable it in Developer options and re-run, or
  - expose it once over USB:  adb -s <SERIAL> shell setprop service.adb.tcp.port 5555
    (this resets when wireless debugging restarts; never hardcode 5555 elsewhere)
MSG
    exit 1
  fi
  echo "== connecting to $ADB_HOST:$PORT =="
  adb_call connect "$ADB_HOST:$PORT"
  OK="$ADB_HOST:$PORT"
else
  [ -n "$DEVICE_SERIAL" ] || DEVICE_SERIAL="$USB_SERIAL"
  [ -n "$DEVICE_SERIAL" ] || DEVICE_SERIAL="$WIRELESS"
  [ -n "$DEVICE_SERIAL" ] || { echo "no device found; set DEVICE_SERIAL or ADB_HOST in config.sh" >&2; exit 1; }
  OK="$DEVICE_SERIAL"
fi

echo "== verifying =="
adb_call devices -l | sed 's/^/  /'
STATE="$(adb_call devices | awk -v d="$OK" '$1==d {print $2}')"
case "$STATE" in
  device) echo "OK: $OK is ready"; echo "$OK" > "$HERE/../.adb-device" ;;
  unauthorized) echo "UNAUTHORIZED: accept the USB-debugging prompt on the device, or sync ~/.android/adbkey from the host that is already authorized" >&2; exit 1 ;;
  *) echo "device state is '$STATE' (offline?) — try: adb kill-server && adb start-server, then re-run" >&2; exit 1 ;;
esac
