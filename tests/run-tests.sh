#!/usr/bin/env bash
# Test suite for android-arm64-devkit.
#
#   ./tests/run-tests.sh
#
# The adb-related tests run against a COPY of scripts/ in a temp dir, so the
# real (gitignored) config.sh is never read and never written.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUB="$REPO/tests/stubs"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
COPY="$TMP/repo"; mkdir -p "$COPY"; cp -r "$REPO/scripts" "$COPY/"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
ko()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
has() { [ "${1#*"$2"}" != "$1" ]; }

echo "== setup-aapt2-arm64.sh =="

out="$(bash "$REPO/scripts/setup-aapt2-arm64.sh" --bogus 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok "unknown option exits 2" || ko "unknown option exits 2" "exit=$rc"

out="$(bash "$REPO/scripts/setup-aapt2-arm64.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "check mode exits 0" || ko "check mode exits 0" "exit=$rc"
has "$out" "ARM aarch64" && ok "reports the native aarch64 toolchain" || ko "reports the native aarch64 toolchain"

proj="$TMP/proj"; mkdir -p "$proj"; printf 'org.gradle.jvmargs=-Xmx1g\n' > "$proj/gradle.properties"
bash "$REPO/scripts/setup-aapt2-arm64.sh" --write-gradle-property "$proj" >/dev/null 2>&1
bash "$REPO/scripts/setup-aapt2-arm64.sh" --write-gradle-property "$proj" >/dev/null 2>&1
n="$(grep -c '^android.aapt2FromMavenOverride=' "$proj/gradle.properties")"
[ "$n" = 1 ] && ok "writes the gradle property exactly once (idempotent)" || ko "writes the gradle property exactly once (idempotent)" "count=$n"
grep -q '^org.gradle.jvmargs=' "$proj/gradle.properties" \
  && ok "preserves existing gradle.properties content" || ko "preserves existing gradle.properties content"

echo "== scripts/lib/adb.sh =="

[ -f "$REPO/scripts/lib/adb.sh" ] && ok "lib exists" || ko "lib exists" "missing scripts/lib/adb.sh"

if [ -f "$REPO/scripts/lib/adb.sh" ]; then
  out="$(PATH="$STUB:$PATH" STUB_ARGV=1 bash -c ". '$REPO/scripts/lib/adb.sh'; ADB_REMOTE_HOST=; adb_call -s dev:1 install -r /tmp/a.apk" 2>&1)"
  if has "$out" "ARG[-s]" && has "$out" "ARG[dev:1]" && has "$out" "ARG[-r]"; then
    ok "local: arguments reach adb as separate argv entries"
  else
    ko "local: arguments reach adb as separate argv entries" "$(printf '%s' "$out" | tr '\n' ' ')"
  fi

  out="$(PATH="$STUB:$PATH" ADB_REMOTE_HOST=testhost ADB_REMOTE_BIN=adb.exe bash -c ". '$REPO/scripts/lib/adb.sh'; adb_call -s dev:1 install -r /tmp/a.apk" 2>&1)"
  if has "$out" "adb.exe" && has "$out" "-s" && has "$out" "dev:1"; then
    ok "remote: command carries the binary and all arguments"
  else
    ko "remote: command carries the binary and all arguments" "$out"
  fi
fi

echo "== adb-connect.sh =="

out="$(cd "$COPY" && PATH="$STUB:$PATH" ADB_HOST=dev bash scripts/adb-connect.sh 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "No wireless port found" \
  && ok "refuses to guess when no wireless port is discoverable" \
  || ko "refuses to guess when no wireless port is discoverable" "exit=$rc out=$(printf '%s' "$out" | tr '\n' ' ')"

out="$(cd "$COPY" && PATH="$STUB:$PATH" ADB_HOST=dev \
      STUB_DEVICES_L="dev:41271   device product:STUB model:STUB transport_id:1" \
      STUB_DEVICES="dev:41271	device" bash scripts/adb-connect.sh 2>&1)"; rc=$?
has "$out" "dev:41271" && ok "discovers the port from an existing wireless transport" \
  || ko "discovers the port from an existing wireless transport" "$(printf '%s' "$out" | tr '\n' ' ')"
[ "$rc" = 0 ] && ok "connects successfully with a good port" || ko "connects successfully with a good port" "exit=$rc"

# A Windows-hosted adb server answers with CRLF; the state parser must survive it.
out="$(cd "$COPY" && PATH="$STUB:$PATH" ADB_HOST=dev STUB_CRLF=1 \
      STUB_DEVICES_L="dev:41271   device product:STUB model:STUB transport_id:1" \
      STUB_DEVICES="dev:41271 device" bash scripts/adb-connect.sh 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "$out" "is ready" \
  && ok "tolerates CRLF line endings from a Windows adb server" \
  || ko "tolerates CRLF line endings from a Windows adb server" "exit=$rc out=$(printf '%s' "$out" | tr -d '\r' | tr '\n' ' ')"

echo "== repository hygiene =="

miss=""
for f in config.sh .adb-device out/screen.png local.properties x.keystore app.apk; do
  git -C "$REPO" check-ignore -q "$f" 2>/dev/null || miss="$miss $f"
done
[ -z "$miss" ] && ok ".gitignore covers every sensitive/derived path" || ko ".gitignore covers every sensitive/derived path" "not ignored:$miss"

# personal-data guard: build the pattern from fragments so this file is not a hit
p1="jag""ones"; p2="one""plus"; p3="10""0.67.181"; p4="gio""va"; p5="Min""ipad"
PAT="$p1|$p2|$p3|$p4|$p5"
# scan only what could actually be committed: tracked + untracked-but-not-ignored
hits=""
while IFS= read -r f; do
  case "$f" in LICENSE|tests/*) continue ;; esac
  [ -f "$REPO/$f" ] || continue
  grep -qEi "$PAT" "$REPO/$f" && hits="$hits $f"
done < <(git -C "$REPO" ls-files --cached --others --exclude-standard)
[ -z "$hits" ] && ok "no personal data in tracked files (LICENSE excluded)" \
  || ko "no personal data in tracked files" "$(printf '%s' "$hits" | tr '\n' ' ')"

n="$(find "$REPO/tests" -type f | wc -l)"
[ "$n" -ge 3 ] && ok "test files are present ($n)" || ko "test files are present" "found $n"

echo
printf 'TOTAL: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
