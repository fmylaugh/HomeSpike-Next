# Changelog

All notable changes to HomeSpike are documented here.

## [2.0.0] — 2026-06-05

### Added
- **Home-screen widgets.** A reusable widget framework plus the first widgets: a **Clock** (large time over a weekday/date subtitle, or a compact time-only size) and a **Calendar** (small month-over-day, or a wide month grid with today highlighted). Add them from a new grid button in edit mode; each widget's **⚙** opens a sheet to toggle its **background** (plate ↔ transparent over the wallpaper), recolour **each section individually** (e.g. the clock's time, the calendar's month/day/weekday/today) with a full **HSV + opacity colour picker** (hex and R/G/B/A entry so colours can be matched exactly between sections), and choose a **size preset**. Time follows the system 12/24-hour setting (the same source as the top-bar clock) and all month/weekday names plus the first day of the week come from the device locale. Widgets drag and carry across pages like any tile. Widgets live in the **Snap to grid** and **Place anywhere** layouts; the picker shows a hint in Auto-fill.
- **App folders.** Drop one app onto another to create a folder; a popup names it (or cancel). Open a folder to launch its apps; tap the name above the card to rename; long-press a member to rearrange it inside, or drag it past the card edge to pull it back onto the home grid; drop another app onto a folder to add it. A folder auto-dissolves to a normal icon when one member is left; the edit-mode "×" deletes the folder and removes its apps from HomeSpike (they stay installed). Folders are grid-only and carry across pages intact.
- **Add / remove pages from edit mode.** A "+" button above the settings gear adds a page (cap 5) and jumps to it; a trash button removes the current page after a confirmation, removing the apps that were on it.
- **Long-press empty space to toggle edit mode** (in addition to long-pressing a tile).
- **Edit-mode jiggle.** Every icon rocks side-to-side in edit mode as a "you can rearrange now" cue, and snaps upright when you leave edit mode.
- **The home stays portrait and doesn't rotate (iOS-style).** Turning the phone sideways re-orients the app icons, their labels, and widget content *in place* — they spin to stay upright — while the grid itself never moves or reflows. The home is pinned to portrait at the shell level while the launcher is in focus (the same mechanism Lomiri uses to portrait-lock official phones), so it stays put **even with auto-rotate on (Rotation Lock off)**; a focused app you open still rotates normally. The physical angle comes from the orientation sensor. The **drawer and side-panel launcher icons re-orient the same way**, and the drawer **relays out for landscape** so its items read left-to-right with the search field and view-mode button repositioned. With **Rotation Lock on, nothing re-orients** — the home, drawer, and launcher all stay portrait.
- **System Settings integration.** New entry at *Settings → Personal → HomeSpike* with a master on/off toggle. Flipping it takes effect live — no restart, no logout. When off, the phone reverts to stock Lomiri behavior (BFB opens the drawer, spread home button hides, "Add to HomeSpike" drawer menu hides, launcher panel stops auto-collapsing, HomeSpike's UI is invisible while the wallpaper stays).
- **gsettings schema** `com.lomiri.HomeSpike` (single `enabled` boolean key, default `true`). Single source of truth for the toggle. Survives HomeSpike crashes since the override files read it directly.
- **[`docs/ClickInstaller.md`](docs/ClickInstaller.md)** — scoping doc for a future Click package that would ship HomeSpike through OpenStore (one-tap install, no `PIN=… ./install.sh` dance).
- **Drawer view modes — Standard / A-Z / Categories.** New pill button under the drawer's search field cycles through three layouts: *Standard* (stock Lomiri flat alphabetical grid, default), *A-Z* (same icons sectioned by single-letter sticky headers), *Categories* (XDG-bucket sections — Internet, Office, Multimedia, Games, Utilities, Development, Settings, Other; empty buckets hidden). Built initially as a POC for UBports bounty issue #127 (since claimed by another contributor); shipping it as a HomeSpike feature regardless.

### Changed
- **Dock restyle.** Transparent background (only a drop-target outline shows while you drag a tile in), icons only (labels removed), and the icons shrink so all of them stay visible when Lomiri's launcher panel slides in.
- **Folder open view styling.** Translucent blue card with the folder name centred *above* it; tap the name to rename, tap outside to close (no Done button). Tapping a folder while in edit mode opens it ready to rearrange.
- **Grid row height now derives from the viewport** so a whole number of rows fits exactly — the bottom row is never sliced off, and Snap-to-grid neighbours never overlap.
- **Page paging reworked to a strict-range pager** (SwipeView-style) so it re-aligns to the current page on resize/rotation and the page dots stay in sync.
- **Faster page transitions** — shorter snap animation and snappier flick deceleration.
- **Reworked the "go home" mechanism.** The previous design minimised every running app on `showHome()` and then tried to un-minimise them when the user switched back — that needed a grace timer, a focused-app snapshot, Mir-focus-echo handling, and an unminimise pass on every focus change. It also broke the right-edge spread (cards tapped to resume an app dropped to HomeSpike instead). New design: `showHome()` just promotes the wallpaper Loader to z:9999 so HomeSpike visually covers everything. Apps stay alive at their normal staged positions, hidden behind HomeSpike. When the user focuses any app again, `homeShown` drops, the Loader sinks to z:-2, and the app is already there at full size.
- `deploy/install.sh`, `deploy/refresh.sh`, `deploy/uninstall.sh` now also install/remove the gsettings schema (with `glib-compile-schemas`) and the system-settings plugin.
- **Reference / test device is now the Poco X3 NFC (`surya`, aarch64).**

### Removed
- **"Number of pages" setting** from the HomeSpike Settings menu — pages are now managed with the edit-mode "+" and trash buttons.
- **"Dock background height" setting** — the dock plate is a fixed default now (it still sizes the drag drop-target outline).

### Fixed
- **Drag between the grid and the dock froze and clipped.** Removing the dragged tile from its model mid-drag destroyed the delegate that owned the touch, stranding the gesture until the next tap. Cross-container moves now commit at release, so the grab survives the whole drag.
- **Drag between pages had the same freeze.** Edge-flip now only scrolls (wrapping from the last page back to the first), the move commits at release, and every page stays instantiated so the dragged tile isn't destroyed when its origin page scrolls off-screen.
- **Snap-to-grid vertical overlap.** Adjacent rows could overlap near the bottom; the row pitch now divides the available height evenly, with no position clamping for grid modes.
- **Landscape was broken** — icons vanished, overlapped, not all pages were reachable, and the page dots pointed at the wrong page. The home is now pinned to portrait and the icons re-orient in place instead, so nothing reflows, jumps, or overlaps on rotation.
- **Moving a folder across pages dropped all but its first app.** The cross-page carry now copies the whole folder row (identity + members) instead of rebuilding it as a single app tile.
- **Dragging a folder showed its first app's icon.** The floating drag visual now mirrors the folder's 2×2 preview.
- **`install.sh` failed with `f: unbound variable`.** The `$f` in the override-listing loop was being expanded by the outer shell before the script reached the device; it's escaped now.
- **Right-edge spread broken after going home.** Tapping any app card in the spread (or the same app the user came from) dropped them back to HomeSpike instead of returning to the app. Root cause was the minimise-then-restore chain in the previous architecture; the rewrite above eliminates it.
- **Settings switch did nothing.** Lomiri.Components `Switch` fires `onTriggered` (not `onClicked`); the toggle is wired correctly now.

## [1.0] — 2026-05-30

First release.

### Added
- **HomeSpike home surface** loaded as a QML tree inside Lomiri's `Stage.qml` at the wallpaper layer (`z: -2`), replacing the original `Wallpaper` element. No separate process, no `.desktop`, no autostart.
- **Multi-page swipeable home grid** (1–5 pages, configurable in HomeSpike's own settings overlay).
- **Three placement modes** with per-mode saved layouts that survive mode switches:
  - *Auto-fill* — icons flow left-to-right with no gaps (default).
  - *Snap to grid* — icons sit on a 4-column grid but can leave gaps; drop on an occupied cell swaps with the occupant.
  - *Place anywhere* — fractional positioning, overlaps allowed.
- **Optional iOS-style dock** at the bottom (max 5 apps, persistent across pages, adjustable plate height). When enabled, Lomiri's left launcher panel auto-collapses so HomeSpike owns the full width.
- **Edit mode** (long-press a tile): drag-to-reorder, drag-to-edge auto-flips page, × badge hides an app from HomeSpike (stays installed), drag between dock and grid.
- **Home button in the right-edge spread** — drop straight back to HomeSpike from the task switcher.
- **Drawer integration**: long-press any app in Lomiri's drawer → "Add to HomeSpike" menu → it appears on your home grid within ~2 seconds (file-inbox IPC, no D-Bus).
- **App enumeration via `AppDrawerModel`** (same model the drawer uses) sorted A–Z via `AppDrawerProxyModel`.
- **Wallpaper inherits whatever you set in Settings → Background** (same `AccountsService.backgroundFile` precedence as stock Lomiri).
- **Per-mode auto-place on new install:** new apps auto-append to the last page in `autoFill`/`snap`; `free` mode skips since placement is intentionally manual.
- **Cross-process inbox** at `/home/phablet/.config/home-spike/pending-adds.txt`, polled ~1.5 s by HomeSpike.
- **Per-mode persistence** at `~/.config/home-spike/home-spike.conf` (`Qt.labs.Settings`). Holds page-data per mode, dock contents, hidden apps, page count, dock-bg height, placement mode.
- **Click installer scaffolding**: bash-based `deploy/install.sh`, `deploy/refresh.sh`, `deploy/uninstall.sh` driven over ADB with the phablet sudo PIN. Idempotent + OTA-survivable (re-run after a system update).

### Fixed
- **Apps stay alive when going home.** A late-cycle architectural fix: tapping the Ubuntu logo (BFB) or the spread home button now reliably returns to HomeSpike with running apps still resumable from the spread. Lomiri's staged mode is designed around always rendering one app full-screen — there was no "show desktop" concept until HomeSpike added one. (The mechanism this introduced was simplified further in Unreleased above.)
- **Free-mode placement quantised to a grid** when it shouldn't have. Caused by `ListModel` inferring the `xFrac` role as `int` from the first appended row (`-1`), which truncated subsequent fractional writes. Fixed by using `-0.5` as the unset sentinel so the role is `real` from the start.
- **Drag drop position was offset half a row.** `(x, y)` came in as DragController-local but the renderer applied them to pageDelegate-local. New `_toPagesViewLocal()` helper subtracts the offset.
- **Tile re-taps within ~800 ms after `showHome()`** were classified as Mir focus-echoes and ignored, so HomeSpike stayed stuck on top. Fixed via an explicit `launchRequested` signal from HomeSpike tiles that drops `homeShown` immediately. (Mechanism fully removed in Unreleased.)
- **Settings dialog hidden behind launcher panel** when the dock was disabled. SettingsOverlay + ConfirmRemoveOverlay now carry `leftReserve` and shift their centred card right by half that.
- **Icon column cut off on the left** when launcher was visible. New `leftReserve` property is wired from Lomiri's `launcher.visibleWidth` into HomeSpike's grid/dock/dots insets.

### Lomiri files modified (full overrides, no sed)
- `/usr/share/lomiri/Shell.qml` — BFB rewire to `stage.showHome()`; `launcher.lockedVisible` also ORs in `stage.homeShown` and ANDs out `stage.homeSpikeDockEnabled`.
- `/usr/share/lomiri/Stage/Stage.qml` — `Wallpaper` element replaced with a `Loader` pointing at `/opt/home-spike/main.qml`; exposes `homeShown`, `homeSpikeDockEnabled`, `launcherLeftMargin` to children/siblings; wires the spread's `homeRequested` signal to `showHome()`.
- `/usr/share/lomiri/Stage/Spread/Spread.qml` — home button at the bottom-centre of the right-edge spread.
- `/usr/share/lomiri/Launcher/Drawer.qml` — long-press context menu with an "Add to HomeSpike" item that appends an `appId` to the inbox file.

### Tested on
- OnePlus Nord N100 (`billie2`, aarch64) running Ubuntu Touch 24.04 noble.

---

[2.0.0]: https://github.com/fmylaugh/HomeSpike-Next/releases/tag/v2.0.0
[1.0]: https://github.com/fmylaugh/HomeSpike-Next/releases/tag/v1.0.0
