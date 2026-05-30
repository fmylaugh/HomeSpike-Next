#!/usr/bin/env bash
# HomeSpike installer: push the app, patch Lomiri so that
#   (1) tapping the Ubuntu logo (BFB) launches HomeSpike instead of the drawer
#   (2) HomeSpike auto-launches at shell startup, so it's visible after unlock
#   (3) Long-press on any app in the drawer adds it to HomeSpike's home grid
# Reboots when done. Idempotent — re-run safely after a Lomiri OTA.
#
# Usage:  PIN=<phablet-sudo-pin> ./install.sh
set -euo pipefail

[ -z "${PIN:-}" ] && { echo "usage: PIN=<sudo-pin> $0"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UMBRELLA_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"

# adb discovery: env override → PATH → umbrella's research-bundled copy
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

echo "[1/5] adb=$ADB, checking device..."
"$ADB" devices | grep -q "device$" || { echo "ERROR: no device. plug in phone, enable developer mode."; exit 1; }

echo "[2/5] Pushing app files..."
"$ADB" push "$REPO_ROOT/app/main.qml"           /tmp/home-spike.main.qml     >/dev/null
"$ADB" push "$REPO_ROOT/app/home-spike"         /tmp/home-spike.launcher     >/dev/null
"$ADB" push "$REPO_ROOT/app/home-spike.desktop" /tmp/home-spike.desktop      >/dev/null

echo "[3/5] Pushing patched Drawer.qml..."
"$ADB" push "$REPO_ROOT/app/lomiri-overrides/Drawer.qml" /tmp/home-spike.Drawer.qml >/dev/null

echo "[4/5] Remount rw, install files, patch Shell.qml + Drawer.qml..."
"$ADB" shell "echo '$PIN' | sudo -S sh -c '
  set -e
  mount -o remount,rw /
  mkdir -p /opt/home-spike
  mv /tmp/home-spike.main.qml  /opt/home-spike/main.qml
  mv /tmp/home-spike.launcher  /opt/home-spike/home-spike
  mv /tmp/home-spike.desktop   /usr/share/applications/home-spike.desktop
  chmod 755 /opt/home-spike/home-spike
  chmod 644 /opt/home-spike/main.qml /usr/share/applications/home-spike.desktop

  # ----- Shell.qml: BFB rewire + autostart -----
  test -f /usr/share/lomiri/Shell.qml.orig || cp /usr/share/lomiri/Shell.qml /usr/share/lomiri/Shell.qml.orig
  sed -i \"s|onShowDashHome: showHome()|onShowDashHome: shell.activateApplication(\\\"home-spike\\\")|\" /usr/share/lomiri/Shell.qml
  if ! grep -q HOME_SPIKE_AUTOSTART /usr/share/lomiri/Shell.qml; then
    sed -i \"/finishStartUpTimer\\.start();/a\\        shell.activateApplication(\\\"home-spike\\\"); // HOME_SPIKE_AUTOSTART\" /usr/share/lomiri/Shell.qml
  fi

  # ----- Drawer.qml: long-press → add to HomeSpike -----
  test -f /usr/share/lomiri/Launcher/Drawer.qml.orig || cp /usr/share/lomiri/Launcher/Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml.orig
  mv /tmp/home-spike.Drawer.qml /usr/share/lomiri/Launcher/Drawer.qml
  chmod 644 /usr/share/lomiri/Launcher/Drawer.qml

  # ----- Inbox file used by Drawer→HomeSpike IPC -----
  mkdir -p /home/phablet/.config/home-spike
  touch /home/phablet/.config/home-spike/pending-adds.txt
  chown -R phablet:phablet /home/phablet/.config/home-spike

  echo --- BFB patch ---
  grep -n onShowDashHome /usr/share/lomiri/Shell.qml
  echo --- autostart patch ---
  grep -n -A1 finishStartUpTimer /usr/share/lomiri/Shell.qml
  echo --- Drawer.qml patched ---
  grep -n pending-adds /usr/share/lomiri/Launcher/Drawer.qml | head -3
  mount -o remount,ro /
'"

echo "[5/5] Rebooting device. Wait ~30s, unlock, HomeSpike should already be there."
"$ADB" shell "echo '$PIN' | sudo -S reboot" 2>&1 | grep -v '^\[sudo\]' || true
echo "done. installed."
