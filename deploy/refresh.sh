#!/usr/bin/env bash
# @file refresh.sh
# @description Dev-iteration deploy. Syncs the entire app/ tree to
#   /opt/home-spike/ and restarts Lomiri so the new code loads.
#
#   The Lomiri shell overrides (app/lomiri-overrides/*.qml) live under
#   /usr/share/lomiri and are only replaced when they actually change: the
#   script AUTO-DETECTS when any override differs from what's on the device
#   (md5 compare) and enables that path automatically — so you never have to
#   remember LOMIRI=1. Force it on with LOMIRI=1 or off with LOMIRI=0. When the
#   overrides are copied, Lomiri restarts to the greeter (unlock to continue).
#
# @status Stable.
# @issues Restarting Lomiri logs the user out to the greeter — that's the
#   cost of getting a clean QML reload. Lomiri caches QML aggressively,
#   so a graceful restart doesn't reliably reload changed files.
# @todo None
#
# Usage:  PIN=<phablet-sudo-pin>            ./refresh.sh   # auto-detects overrides
#         PIN=<phablet-sudo-pin> LOMIRI=1   ./refresh.sh   # force override path
#         PIN=<phablet-sudo-pin> LOMIRI=0   ./refresh.sh   # skip override path
#         (legacy alias: DRAWER=1 also works)
set -euo pipefail

[ -z "${PIN:-}" ] && { echo "usage: PIN=<sudo-pin> [LOMIRI=1] $0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBRELLA_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
# Accept either LOMIRI=1 (new) or DRAWER=1 (legacy) for the same behavior.
WITH_LOMIRI="${LOMIRI:-${DRAWER:-0}}"

if [ -n "${ADB:-}" ] && [ -x "$ADB" ]; then
  :
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
elif [ -x "$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb" ]; then
  ADB="$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb"
else
  echo "ERROR: no adb found."; exit 1
fi

"$ADB" devices | grep -q "device$" || { echo "ERROR: no device."; exit 1; }

# ----------------------------------------------------------------------------
# Auto-enable the Lomiri-override path when any app/lomiri-overrides/*.qml
# differs from what's live on the device (md5 compare), so override changes
# never get silently skipped. Explicit LOMIRI=1 forces it on; LOMIRI=0 off.
# A missing/unreadable device file counts as "changed" (safe over-deploy).
# ----------------------------------------------------------------------------
if [ "$WITH_LOMIRI" != "1" ] && [ "${LOMIRI:-}" != "0" ]; then
  _changed=""
  while IFS='|' read -r _f _dev; do
    [ -z "$_f" ] && continue
    _local="$(md5sum "$REPO_ROOT/app/lomiri-overrides/$_f" 2>/dev/null | awk '{print $1}')"
    # </dev/null: stop `adb shell` from swallowing the loop's heredoc stdin
    # (otherwise it eats the remaining override lines and only the first is checked).
    _remote="$("$ADB" shell "md5sum '$_dev' 2>/dev/null" </dev/null | awk '{print $1}' | tr -d '\r')"
    [ "$_local" != "$_remote" ] && _changed="$_changed $_f"
  done <<'OVERRIDES'
Shell.qml|/usr/share/lomiri/Shell.qml
Drawer.qml|/usr/share/lomiri/Launcher/Drawer.qml
LauncherDelegate.qml|/usr/share/lomiri/Launcher/LauncherDelegate.qml
Spread.qml|/usr/share/lomiri/Stage/Spread/Spread.qml
Stage.qml|/usr/share/lomiri/Stage/Stage.qml
OVERRIDES
  if [ -n "$_changed" ]; then
    WITH_LOMIRI=1
    echo "NOTE: Lomiri override(s) changed:$_changed"
    echo "      -> applying the shell-override path (Lomiri will restart to the greeter)."
  fi
fi

# Let HomeSpike's widgets read /proc + /etc via XMLHttpRequest WITHOUT Qt's
# per-read deprecation warning flooding the journal (the System Monitor polls
# these continuously). lomiri runs as the user service lomiri-full-greeter; a
# user-level systemd drop-in sets the env for it. No root; survives reboots/OTA.
# daemon-reload here so the (root) lomiri restart below picks it up.
"$ADB" shell '
  d=$HOME/.config/systemd/user/lomiri-full-greeter.service.d
  mkdir -p "$d"
  printf "[Service]\nEnvironment=QML_XHR_ALLOW_FILE_READ=1\n" > "$d/homespike-xhr.conf"
  systemctl --user daemon-reload 2>/dev/null || true
' >/dev/null 2>&1 || true

# Push the whole app/ tree to a staging location, then sync into /opt/home-spike/
"$ADB" shell "rm -rf /tmp/home-spike-staging" >/dev/null
"$ADB" push "$REPO_ROOT/app" /tmp/home-spike-staging >/dev/null

"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  set -e
  mount -o remount,rw /

  # Sync app tree into /opt/home-spike (wipe + replace so deletions propagate).
  # HomeSpike now runs inside lomiri; no .desktop, no standalone wrapper.
  rm -rf /opt/home-spike
  mkdir -p /opt/home-spike
  mv /tmp/home-spike-staging/* /opt/home-spike/
  chmod -R u=rwX,go=rX /opt/home-spike
  rm -f /usr/share/applications/home-spike.desktop

  if [ \"$WITH_LOMIRI\" = \"1\" ]; then
    # Backup-and-replace each Lomiri override. Backups are created once
    # (the test -f guard); subsequent runs just overwrite the live file.
    test -f /usr/share/lomiri/Shell.qml.orig                       || cp /usr/share/lomiri/Shell.qml                       /usr/share/lomiri/Shell.qml.orig
    test -f /usr/share/lomiri/Launcher/Drawer.qml.orig             || cp /usr/share/lomiri/Launcher/Drawer.qml             /usr/share/lomiri/Launcher/Drawer.qml.orig
    test -f /usr/share/lomiri/Launcher/LauncherDelegate.qml.orig   || cp /usr/share/lomiri/Launcher/LauncherDelegate.qml   /usr/share/lomiri/Launcher/LauncherDelegate.qml.orig
    test -f /usr/share/lomiri/Stage/Spread/Spread.qml.orig         || cp /usr/share/lomiri/Stage/Spread/Spread.qml         /usr/share/lomiri/Stage/Spread/Spread.qml.orig
    test -f /usr/share/lomiri/Stage/Stage.qml.orig                 || cp /usr/share/lomiri/Stage/Stage.qml                 /usr/share/lomiri/Stage/Stage.qml.orig

    cp /opt/home-spike/lomiri-overrides/Shell.qml            /usr/share/lomiri/Shell.qml
    cp /opt/home-spike/lomiri-overrides/Drawer.qml           /usr/share/lomiri/Launcher/Drawer.qml
    cp /opt/home-spike/lomiri-overrides/LauncherDelegate.qml /usr/share/lomiri/Launcher/LauncherDelegate.qml
    cp /opt/home-spike/lomiri-overrides/Spread.qml           /usr/share/lomiri/Stage/Spread/Spread.qml
    cp /opt/home-spike/lomiri-overrides/Stage.qml            /usr/share/lomiri/Stage/Stage.qml

    chmod 644 /usr/share/lomiri/Shell.qml \
              /usr/share/lomiri/Launcher/Drawer.qml \
              /usr/share/lomiri/Launcher/LauncherDelegate.qml \
              /usr/share/lomiri/Stage/Spread/Spread.qml \
              /usr/share/lomiri/Stage/Stage.qml

    # Sync the gsettings schema + system-settings plugin too. These rarely
    # change, but the LOMIRI=1 path is the only one that touches /usr, so
    # bundle them here rather than gating on a separate flag.
    cp /opt/home-spike/system-settings-plugin/com.lomiri.HomeSpike.gschema.xml \
       /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml
    chmod 644 /usr/share/glib-2.0/schemas/com.lomiri.HomeSpike.gschema.xml
    glib-compile-schemas /usr/share/glib-2.0/schemas/

    cp /opt/home-spike/system-settings-plugin/home-spike.settings \
       /usr/share/lomiri-system-settings/home-spike.settings
    chmod 644 /usr/share/lomiri-system-settings/home-spike.settings
    mkdir -p /usr/share/lomiri-system-settings/qml-plugins/home-spike
    cp /opt/home-spike/system-settings-plugin/PageComponent.qml \
       /usr/share/lomiri-system-settings/qml-plugins/home-spike/PageComponent.qml
    chmod 644 /usr/share/lomiri-system-settings/qml-plugins/home-spike/PageComponent.qml
  fi

  mount -o remount,ro /

  # HomeSpike now lives inside lomiri — restart lomiri to reload any QML
  # change. The previous "refresh HomeSpike without restarting lomiri"
  # path is gone; both modes restart lomiri.
  echo \"Restarting Lomiri so HomeSpike + Lomiri overrides reload...\"
  pkill -9 -f \"^lomiri --\" || true
'"

echo "refreshed. Lomiri restarting — unlock when greeter appears."
