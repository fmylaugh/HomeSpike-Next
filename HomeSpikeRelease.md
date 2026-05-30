# HomeSpike v1.0 — a real home screen for Ubuntu Touch

> Title for the post — pick whichever fits the venue:
>
> **UBports forum:** `[Release] HomeSpike v1.0 — multi-page home, dock, drag-to-reorder, three placement modes (auto-fill / snap-to-grid / place-anywhere)`
>
> **r/UbuntuTouch / r/mobilelinux:** `I built a proper home screen for Ubuntu Touch — multi-page, dock, three layout modes, integrates with the Lomiri drawer and spread`

---

## What it is

HomeSpike is a fullscreen home surface for **Ubuntu Touch (Lomiri)** that replaces "drawer-as-default" with what most people actually expect from a phone: a wallpapered home grid you land on after unlock, swipeable pages of icons, an iOS-style dock, and an edit mode where you long-press to drag icons around or remove them. New apps you install auto-add to your last page. The Lomiri drawer is still there (the patched long-press inside it gives you an "Add to HomeSpike?" prompt), but it's no longer the first thing you see.

v1.0 adds three different **placement modes** so you can lay icons out the way you actually want: auto-fill (icons reflow with no gaps), snap-to-grid (place on any cell, gaps allowed), or place-anywhere (drop wherever, overlaps OK). Each mode keeps its own saved layout — switching modes never destroys the previous arrangement.

I built it because Ubuntu Touch in 2014 made a bet on "scopes as cards" replacing home screens with widgets, and that bet hasn't aged well. Every other mobile Linux shell since (Plasma Mobile, Phosh, even Android-via-Halium) has done the opposite. After daily-driving UT on a OnePlus Nord N100 and finding myself wanting *somewhere to put apps in an order I chose*, I stopped wishing for it and wrote it.

## How it works

It's all QML on top of stock Lomiri — no shell fork. HomeSpike loads as a `Loader` at `z: -2` **inside Lomiri's own `Stage.qml`**, replacing the original Wallpaper element. Because it lives in the lomiri process and isn't a separate application surface, it never appears in the app spread, never needs autostart, and never has a `.desktop` file. The four Lomiri files we touch (`Shell.qml`, `Stage.qml`, `Stage/Spread/Spread.qml`, `Launcher/Drawer.qml`) are shipped as full replacement copies under `app/lomiri-overrides/` — install is plain backup-and-replace, no sed. Original files are kept as `.orig` and `uninstall.sh` cleanly reverts. Installer is idempotent and OTA-survivable (re-run after a system update).

HomeSpike itself reuses Lomiri's own primitives instead of reinventing: app inventory comes from `AppDrawerModel` (the same model the drawer uses), wallpaper comes from `AccountsService.backgroundFile` (the same one Settings writes when you change wallpaper), icons render with `LomiriShape` (same rounded-rect tile primitive). State (per-mode layouts, dock contents, hidden apps, page count, dock settings) persists to `~/.config/home-spike/home-spike.conf` via `Qt.labs.Settings`. The Drawer→HomeSpike "add" is a file-inbox the running HomeSpike polls every 1.5 seconds — no D-Bus dance, just a file.

## Features

- **Multi-page swipeable home** (1–5 pages, configurable)
- **Optional iOS-style dock** at the bottom (max 5 apps, persistent across pages, adjustable plate height). When the dock is on, Lomiri's left launcher panel auto-collapses so HomeSpike owns the full screen.
- **Three placement modes** with independent saved layouts:
  - Auto-fill (reflow, no gaps)
  - Snap to grid (place on cells, gaps allowed, swap on collision)
  - Place anywhere (drop anywhere on the page, overlaps allowed)
- **Edit mode (long-press):** drag-to-reorder, drag-to-edge auto-flips page, X-badge removes an icon (stays installed, just hidden from home)
- **Drag between dock and grid** in both directions
- **Home button in the right-swipe app spread** — tap to return to HomeSpike without minimizing each app individually
- **Wallpaper inherits whatever you set in Settings → Background**
- **New installs auto-append** to the last page (snap → first free cell; place-anywhere skips, since it's intentionally manual)
- **Long-press an app in the swipe-left drawer** → "Add to HomeSpike?" prompt → it appears on your home within ~2 seconds
- **Per-arch portable** — no `qmlscene` wrapper script, no arch-specific paths; HomeSpike runs inside lomiri so it picks up whatever Lomiri sees

## Tested on

OnePlus Nord N100 (`billie2`), Ubuntu Touch 24.04 noble. The design is generic to Lomiri 24.04 — should work on every device on that channel. If you try it on something else, please let me know.

## How to install

Currently distributed as a self-hosted installer (not OpenStore — see "Why not OpenStore" below). Phone connected via adb, developer mode on:

```sh
git clone <repo url>
cd HomeSpike
PIN=<your-phablet-sudo-pin> ./deploy/install.sh
```

To revert:

```sh
PIN=<your-phablet-sudo-pin> ./deploy/uninstall.sh
```

## Why not OpenStore

OpenStore ships Click packages, which are AppArmor-sandboxed and explicitly cannot modify system files, remount `/` rw, or hook into Lomiri's shell QML — i.e., every single thing that makes HomeSpike *the home* rather than *an app you open*. A confined Click version would just be "HomeSpike Launcher: an app drawer you have to tap to enter," which loses 90% of the value. So this ships as a self-hosted installer for now. A clean long-term answer is upstreaming the home-surface mechanism into Lomiri proper — I'd like to do that once the design has settled in real-world use.

## Caveats up front

- **Modifies four Lomiri shell files.** Read `install.sh` before running. Backups are made for each (`.orig` next to the live file); `uninstall.sh` restores them.
- **OTA wipes overrides.** Re-run `install.sh` after any system update. Takes a couple seconds.
- **Iterating on the overrides logs you out to the greeter.** Lomiri caches QML aggressively, so the dev refresh path `pkill`s lomiri — you'll see the greeter, unlock to continue.
- **Removes the OpenStore-link long-press in the drawer.** That gesture now goes to "Add to HomeSpike?" instead. Can be restored as a different gesture later if there's demand.
- **No widget API yet.** This release is the home surface itself. A widget system (with a real provider API) is the next milestone — the current QML is the scaffolding for an eventual ImGui+Lua reimplementation that'll host third-party widgets behind the same load-point.

## Source + issues

GitHub / Gitea: **<repo url here>**

License: GPL-2.0-or-later. No warranty. PRs welcome — especially "tested on `<your device>`" confirmations and Lomiri-version-drift fixes for the override copies.

## TL;DR

> "I wanted a home screen on Ubuntu Touch. UT doesn't really have one — the
> drawer is the default surface and there's no place to arrange icons how
> you want. So I wrote one. It's a QML tree loaded inside Lomiri's own
> Stage.qml + four small Lomiri shell-file overrides. Multi-page, dock,
> drag-to-reorder, three layout modes (auto-fill / snap-to-grid /
> place-anywhere — each with its own saved layout), long-press in the
> system drawer adds apps to it, spread gets a home button. Backups +
> uninstaller included. Source linked below."
