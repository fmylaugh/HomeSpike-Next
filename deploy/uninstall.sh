#!/usr/bin/env bash
# Revert HomeSpike: restore Shell.qml from .orig backup and delete the
# home-spike files. Safe to run even if install never happened.
#
# Usage:  PIN=<phablet-sudo-pin> ./uninstall.sh
set -euo pipefail

[ -z "${PIN:-}" ] && { echo "usage: PIN=<sudo-pin> $0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBRELLA_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"

if [ -n "${ADB:-}" ] && [ -x "$ADB" ]; then
  :
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
elif [ -x "$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb" ]; then
  ADB="$UMBRELLA_ROOT/research/n100-be2012-crossflash/host-tools/platform-tools/adb"
else
  echo "ERROR: no adb found. install Android platform-tools or set ADB=<path>."
  exit 1
fi

"$ADB" devices | grep -q "device$" || { echo "ERROR: no device."; exit 1; }

"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  set -e
  mount -o remount,rw /
  if test -f /usr/share/lomiri/Shell.qml.orig; then
    mv /usr/share/lomiri/Shell.qml.orig /usr/share/lomiri/Shell.qml
    echo restored Shell.qml
  else
    echo no Shell.qml backup found
  fi
  if test -f /usr/share/lomiri/Launcher/Drawer.qml.orig; then
    mv /usr/share/lomiri/Launcher/Drawer.qml.orig /usr/share/lomiri/Launcher/Drawer.qml
    echo restored Drawer.qml
  else
    echo no Drawer.qml backup found
  fi
  rm -rf /opt/home-spike /usr/share/applications/home-spike.desktop
  rm -rf /home/phablet/.config/home-spike/pending-adds.txt
  mount -o remount,ro /
'"

"$ADB" shell "echo '$PIN' | sudo -S reboot" 2>&1 | grep -v '^\[sudo\]' || true
echo "done. reverted."
