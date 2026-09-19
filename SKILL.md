---
name: android-arm64-devkit
description: Build and deploy Android APKs on ARM64 Linux (DGX Spark, Raspberry Pi, ARM cloud): native aarch64 aapt2 for Gradle, plus adb install-and-verify over USB or VPN. Use for aarch64 APK builds.
metadata:
  emoji: 🤖
  os: [linux]
---

# android-arm64-devkit

Thin wrapper over the scripts in this repo. One skill, two branches: pick your
**host** and your **transport**. Every machine-specific value lives in
`config.sh` (from `config.example.sh`) — never in this file.

## Branch 1 — Host (pick yours)

| Host | What changes |
|---|---|
| **ARM64 Linux** (DGX Spark, Raspberry Pi, ARM server/cloud) | Google's `aapt2` / `aidl` / `zipalign` are **x86-64** only, so Gradle dies with `Exec format error` → **MUST** override with the Debian **aarch64** build (see "Build branch") |
| **x86-64 Linux** | Google's toolchain runs natively → skip the aapt2 override; the adb scripts still apply |
| **Windows / macOS** | These bash scripts do not run there → use the Android Studio workflow instead (see "Cross-references") |

## Branch 2 — Transport (pick yours)

| Situation | Transport |
|---|---|
| Device attached to the machine running the scripts | **USB** — leave `ADB_HOST` empty, set `DEVICE_SERIAL` |
| Device on a VPN (e.g. Tailscale) | **TCP** — set `ADB_HOST` to the MagicDNS name; the port is discovered |
| Device attached to another host you can ssh into | **remote adb** — set `ADB_REMOTE_HOST` + `ADB_REMOTE_BIN` |

## Config — the only place personal values live

```bash
cp {baseDir}/config.example.sh {baseDir}/config.sh
$EDITOR {baseDir}/config.sh
```

`config.sh` is gitignored and is never committed. Host names, IPs, serials,
package ids and personal paths go **here** — not in this skill, not in any tracked
file. Gradle-side values (`sdk.dir`, `android.aapt2FromMavenOverride`) belong to
the project's `local.properties` / `gradle.properties`.

## Build branch (ARM64 host)

```bash
sudo apt-get install -y android-sdk-build-tools android-sdk-platform-tools android-libaapt
{baseDir}/scripts/setup-aapt2-arm64.sh
{baseDir}/scripts/setup-aapt2-arm64.sh --write-gradle-property path/to/project
cd path/to/project && ./gradlew clean assembleDebug
```

## Deploy + verify branch (any host)

```bash
{baseDir}/scripts/adb-connect.sh
{baseDir}/scripts/adb-install-verify.sh app/build/outputs/apk/debug/app-debug.apk
{baseDir}/scripts/adb-disconnect.sh
```

## Operating Rules (for agents)

- **MUST** invoke the repo scripts by their `{baseDir}` path; never rewrite their
  logic inline.
- **MUST** run `./gradlew clean assembleDebug` and require
  `N actionable tasks: M executed` with **M > 0**. A build with every task
  `UP-TO-DATE` means `aapt2` never ran — it proves nothing.
- **MUST** create `config.sh` from `config.example.sh` before the adb scripts, and
  **MUST NOT** commit it or hardcode its values.
- **MUST NOT** hardcode the wireless adb port (e.g. `5555`). OEMs randomize it on
  every wireless-debugging restart; let `adb-connect.sh` discover it.
- **MUST** treat `adb-install-verify.sh` output as the acceptance test: install +
  launch + focus + pid + logcat + screenshot. A screenshot **< 30 KB** is a cached
  black framebuffer (lockscreen), not success.
- **MUST NOT** claim success from `BUILD SUCCESSFUL` or `install Success` alone.
- When a binary capture crosses a **Windows** host, redirect inside `cmd`
  (`cmd /c "adb ... > shot.png"`); PowerShell's `>` writes UTF-16 and corrupts
  binaries.
- On a remote adb host, set `ADB_REMOTE_HOST` / `ADB_REMOTE_BIN` in `config.sh`;
  do not reimplement the ssh quoting — `{baseDir}/scripts/lib/adb.sh` handles it.
- The aapt2 override is marked **experimental** by AGP: re-test after any AGP
  major upgrade.

## Key facts

- aapt2 override:
  `android.aapt2FromMavenOverride=/usr/lib/android-sdk/build-tools/debian/aapt2`
- `d8` / `apksigner` are JVM wrappers → architecture-independent.
- Self-test suite: `{baseDir}/tests/run-tests.sh`

## Troubleshooting

See `{baseDir}/docs/troubleshooting.md` — every trap was hit for real: `Exec
format error`, `UP-TO-DATE` false success, dynamic wireless port, `unauthorized`
key mismatch, `device offline`, VPN deep sleep, PowerShell UTF-16 corruption,
stale/empty mounts, black screenshot with focus held.

## Cross-references

- Windows / macOS host → the Android Studio workflow skill.
- DGX-Spark-specific operational notes (canonical layout, shell-rc env block,
  dynamic-port workflow) → the host manual under `.agent/`.

## Scope

Debug APKs only — not for Play Store release signing.
