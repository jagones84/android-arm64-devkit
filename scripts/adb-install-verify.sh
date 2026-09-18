#!/usr/bin/env bash
# Install an APK and actually verify it runs: version, launch, focus, pid, logcat, screenshot.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/../config.sh" ] && . "$HERE/../config.sh"

APK="${1:-}"
[ -n "$APK" ] && [ -f "$APK" ] || { echo "usage: $0 path/to/app.apk" >&2; exit 2; }

ADB_REMOTE_HOST="${ADB_REMOTE_HOST:-}"
ADB_REMOTE_BIN="${ADB_REMOTE_BIN:-adb}"
OUT_DIR="${OUT_DIR:-$HERE/../out}"
mkdir -p "$OUT_DIR"

adb_call() {
  if [ -n "$ADB_REMOTE_HOST" ]; then
    ssh -o BatchMode=yes "$ADB_REMOTE_HOST" "'${ADB_REMOTE_BIN:-adb}' $*"
  else
    adb "$@"
  fi
}
# capture runs on the host that owns the device
capture_binary() { # capture_binary <local-dest> <remote-dest> <adb args...>
  local dest="$1" rdest="$2"; shift 2
  if [ -n "$ADB_REMOTE_HOST" ]; then
    ssh -o BatchMode=yes "$ADB_REMOTE_HOST" "cmd /c \"'${ADB_REMOTE_BIN:-adb}' $* > $rdest\"" >/dev/null
    scp -q -o BatchMode=yes "$ADB_REMOTE_HOST:$rdest" "$dest"
  else
    adb "$@" > "$dest"
  fi
}

DEV="$(cat "$HERE/../.adb-device" 2>/dev/null || true)"
[ -n "$DEV" ] || { echo "no device; run adb-connect.sh first" >&2; exit 1; }
D=(-s "$DEV")

# If the device lives on a remote host, stage the APK there.
STAGE="$APK"
if [ -n "$ADB_REMOTE_HOST" ]; then
  STAGE="/tmp/$(basename "$APK")"
  scp -q -o BatchMode=yes "$APK" "$ADB_REMOTE_HOST:$STAGE"
  echo "staged APK on $ADB_REMOTE_HOST:$STAGE"
fi

PKG="${PACKAGE_ID:-}"
ACT="${LAUNCH_ACTIVITY:-}"

echo "== install =="
adb_call "${D[*]}" install -r "$STAGE" | sed 's/^/  /'

if [ -z "$PKG" ]; then
  if command -v aapt2 >/dev/null && [ "${APK##*.}" = "apk" ]; then
    PKG="$(aapt2 dump badging "$APK" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
    [ -z "$ACT" ] && ACT="$(aapt2 dump badging "$APK" 2>/dev/null | sed -n "s/.*launchable-activity: name='\([^']*\)'.*/\1/p" | head -1)"
  fi
fi
[ -n "$PKG" ] || { echo "set PACKAGE_ID in config.sh (could not read it from the APK)" >&2; exit 1; }
echo "  package: $PKG"

echo "== installed metadata =="
adb_call "${D[*]}" shell dumpsys package "$PKG" | grep -E 'versionName|versionCode|targetSdk|firstInstallTime|lastUpdateTime' | head -6 | sed 's/^/  /'

if [ -n "$ACT" ]; then
  echo "== launch =="
  adb_call "${D[*]}" shell input keyevent 224 >/dev/null 2>&1 || true   # wake display
  adb_call "${D[*]}" shell svc power stayon true >/dev/null 2>&1 || true
  adb_call "${D[*]}" shell input keyevent 3 >/dev/null 2>&1 || true      # HOME
  sleep 2
  case "$ACT" in .*) COMPONENT="$PKG/$ACT" ;; *) COMPONENT="$PKG/$ACT" ;; esac
  adb_call "${D[*]}" shell am start -n "$COMPONENT" | sed 's/^/  /'
  sleep 5

  echo "== focus (must be our package) =="
  FOCUS="$(adb_call "${D[*]}" shell dumpsys window | grep -i mCurrentFocus | head -2)"
  echo "$FOCUS" | sed 's/^/  /'
  echo "$FOCUS" | grep -q "$PKG" || echo "  WARNING: $PKG does not hold focus (lockscreen? crash?)"

  echo "== process =="
  PID="$(adb_call "${D[*]}" shell pidof "$PKG" | tr -d '\r')"
  echo "  pid: ${PID:-<none>}"
fi

echo "== crashes in logcat =="
adb_call "${D[*]}" logcat -d -t 400 | grep -iE "AndroidRuntime|FATAL EXCEPTION|$PKG" | tail -10 | sed 's/^/  /' || echo "  (clean)"

echo "== screenshot =="
SHOT="$OUT_DIR/screen.png"
capture_binary "$SHOT" "/tmp/adb-verify-screen.png" "${D[*]}" exec-out screencap -p
if [ -f "$SHOT" ]; then
  SZ=$(wc -c < "$SHOT")
  echo "  saved $SHOT ($SZ bytes)"
  if [ "$SZ" -lt 30000 ]; then
    echo "  WARNING: suspiciously small — some OEM lockscreens return a cached black"
    echo "           framebuffer. Wake the device, dismiss the lockscreen, retry."
  fi
fi
echo "DONE"
