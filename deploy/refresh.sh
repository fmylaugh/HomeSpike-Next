#!/usr/bin/env bash
# Dev iteration: push the QML/launcher to the device and kill the running
# home-spike instance so the next BFB tap respawns with new code.
# Does NOT touch Shell.qml or reboot.
#
# By default this only refreshes HomeSpike itself (main.qml + wrapper).
# Pass DRAWER=1 to ALSO push the patched Drawer.qml and restart Lomiri
# so the new drawer code is loaded — note that restarting Lomiri will
# log you back to the greeter.
#
# Usage:  PIN=<phablet-sudo-pin>            ./refresh.sh
#         PIN=<phablet-sudo-pin> DRAWER=1   ./refresh.sh
set -euo pipefail

[ -z "${PIN:-}" ] && { echo "usage: PIN=<sudo-pin> [DRAWER=1] $0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBRELLA_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
WITH_DRAWER="${DRAWER:-0}"

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

"$ADB" push "$REPO_ROOT/app/main.qml"   /tmp/home-spike.main.qml     >/dev/null
"$ADB" push "$REPO_ROOT/app/home-spike" /tmp/home-spike.launcher     >/dev/null

if [ "$WITH_DRAWER" = "1" ]; then
  "$ADB" push "$REPO_ROOT/app/lomiri-overrides/Drawer.qml" /tmp/home-spike.Drawer.qml >/dev/null
fi

"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  mount -o remount,rw /
  mv /tmp/home-spike.main.qml /opt/home-spike/main.qml
  mv /tmp/home-spike.launcher /opt/home-spike/home-spike
  chmod 644 /opt/home-spike/main.qml
  chmod 755 /opt/home-spike/home-spike

  if [ \"$WITH_DRAWER\" = \"1\" ]; then
    test -f /usr/share/lomiri/Launcher/Drawer.qml.orig || cp /usr/share/lomiri/Launcher/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml.orig
    mv /tmp/home-spike.Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml
    chmod 644 /usr/share/lomiri/Launcher/Drawer.qml
  fi

  mount -o remount,ro /

  # SIGTERM first so Qt can flush Settings to disk; SIGKILL after grace.
  pkill -TERM -f qmlscene.*home-spike || true
  for i in 1 2 3 4 5; do
    pgrep -f qmlscene.*home-spike >/dev/null || break
    sleep 0.2
  done
  pkill -KILL -f qmlscene.*home-spike || true

  if [ \"$WITH_DRAWER\" = \"1\" ]; then
    echo \"Restarting Lomiri so the new Drawer.qml gets reloaded...\"
    pkill -TERM -x lomiri || true
  fi
'"

if [ "$WITH_DRAWER" = "1" ]; then
  echo "refreshed (incl. Drawer.qml). Lomiri restarting — unlock when greeter appears."
else
  echo "refreshed. tap BFB (or wait for autostart) to see changes."
fi
