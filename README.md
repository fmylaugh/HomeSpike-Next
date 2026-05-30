# HomeSpike

> A [TeamIDE](https://teamide.dev) project. If this changed how you use your phone, [chip in](https://teamide.dev/support).

Join the community on [Discord](https://discord.gg/YVcsHXSCYG) · Follow on [X](https://x.com/TeamIDElab) · Subreddit: [r/TeamIDELabs](https://www.reddit.com/r/TeamIDELabs/) · YouTube: [@TeamIDElabs](https://www.youtube.com/@TeamIDElabs).

Licensed [GPL-2.0-or-later](LICENSE.md). No warranty. Modifies Lomiri shell files in `/usr/share/lomiri/` and remounts `/` as rw — read [`install.sh`](deploy/install.sh) before running. If something goes wrong, [`uninstall.sh`](deploy/uninstall.sh) restores the original Shell.qml from the backup it makes. If you want help adapting this to a different device, port, or use case, see [HIRE.md](HIRE.md).

---

A custom **home surface** for Ubuntu Touch (Lomiri). Replaces the swipe-from-left → app-drawer flow with a fullscreen QML app that sits under everything, shows the user's chosen wallpaper, and renders the installed apps in a 4-wide icon grid. swipe from left click the ubuntu logo and your home.

This is the proof-of-concept for the long-term plan of writing our own ImGui+Lua-based home/widget surface. The Lomiri integration (patches + appid wiring + autostart + AccountsService wallpaper read + app enumeration) is what's validated here. The actual UI is intentionally small QML — it will eventually be replaced by an ImGui+Lua binary behind the same `home-spike` appid.

## Device support

Works on **any Ubuntu Touch 24.04 (noble) device running Lomiri**, regardless of CPU architecture. Built and tested on the OnePlus Nord N100 (`billie2`, aarch64); the design has no device-specific assumptions and the wrapper script globs `/usr/lib/*-linux-gnu*/lomiri/qml` so it picks up Lomiri's modules on aarch64, armhf, and x86_64 alike.

Requirements:

- Ubuntu Touch with **Lomiri** as the shell (pre-Lomiri Unity 8 won't work)

- Developer mode enabled (Settings → About → Developer Mode)

- Known phablet **sudo PIN** (set under Privacy → Security)

- `adb` connection from a host (Mac or Linux)

- Comfortable with the install touching `/usr/share/lomiri/Shell.qml` — the script backs the original up as `Shell.qml.orig` and `uninstall.sh` restores it cleanly

What's **not** guaranteed:

- **Older or pre-noble UT releases.** The two sed targets (`onShowDashHome: showHome()` and `finishStartUpTimer.start();`) are pattern-matched, not line-pinned, so they survive minor layout drift, but a major Lomiri rewrite can break them silently. The install script's tail-grep prints whether each patch applied — if either shows no match, you're on a Lomiri version we haven't seen.

- **Non-Lomiri shells** (Plasma Mobile on Droidian, Phosh, Sailfish, postmarketOS Sxmo) — entirely different shell stacks, would need a separate port.

If you run it on a device the README doesn't list and it works (or doesn't), let us know on [Discord](https://discord.gg/YVcsHXSCYG) — we'll add the device to the tested list.

## What you get after `install.sh`

- Boot → unlock → **HomeSpike is already there**, fullscreen, over your wallpaper. No drawer, no taps required.

- Tap the **Ubuntu logo** (BFB) on the launcher → returns to HomeSpike.

- App grid (4 columns, A–Z sorted) of every installed app. Tap an icon → launches that app via the URL dispatcher.

- Open another app → it stacks on top. Close it → HomeSpike revealed again (Lomiri's surface-stacking default).

## How it works

| Piece                                                                                                             | Lives at (on device)                       | Source                 |
| ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ---------------------- |
| The QML app                                                                                                       | /opt/home-spike/main.qml                   | app/main.qml           |
| Exec wrapper (globs /usr/lib/*-linux-gnu*/lomiri/qml into QML2_IMPORT_PATH so Lomiri modules resolve on any arch) | /opt/home-spike/home-spike                 | app/home-spike         |
| .desktop for appid home-spike                                                                                     | /usr/share/applications/home-spike.desktop | app/home-spike.desktop |
| Lomiri patches (BFB rewire + autostart)                                                                           | /usr/share/lomiri/Shell.qml                | applied by install.sh  |
| Original Shell.qml backup                                                                                         | /usr/share/lomiri/Shell.qml.orig           | created by install.sh  |

### Lomiri patches (two of them)

1. **BFB rewire** — one-line edit in `Shell.qml`: \`\`\`

   - onShowDashHome: showHome()


   - onShowDashHome: shell.activateApplication("home-spike") \`\`\`

2. **Autostart at session start** — append one line to the existing `Component.onCompleted` block, marked with `// HOME_SPIKE_AUTOSTART` for idempotency.

`install.sh` is idempotent — re-running won't double-patch. It also keeps `Shell.qml.orig` so `uninstall.sh` can cleanly revert.

### Wallpaper resolution

Same precedence Lomiri's own shell uses:

1. `AccountsService.backgroundFile` (the user's choice from Settings)

2. `com.lomiri.Shell` gsettings → `background-picture-uri`

3. Hardcoded default

`AccountsService.backgroundFile` returns a bare path; we prefix it with `file://` before handing it to the Image source.

### App enumeration

- `AppDrawerModel` from `Lomiri.Launcher 0.1` — the same model the drawer uses.

- Wrapped in `AppDrawerProxyModel` from `Utils 0.1` (different plugin, easy to miss) for A–Z sort.

- Tap → `Qt.openUrlExternally("application:///" + model.appId + ".desktop")` → Lomiri's URL dispatcher hands off to UAL.

## Usage

Phone connected via adb, developer mode on:

```
# fresh install (pushes files, patches Lomiri, reboots)
PIN=<sudo-pin> ./deploy/install.sh

# dev iteration (push QML+wrapper only, kill running instance, no patch, no reboot)
PIN=<sudo-pin> ./deploy/refresh.sh

# revert everything (restore Shell.qml.orig, remove files, reboot)
PIN=<sudo-pin> ./deploy/uninstall.sh
```

The `PIN` is the same one used for the existing `n100-be2012-crossflash/installer/*.sh` scripts. `adb` is discovered in this order: `$ADB` env override → on PATH → `research/n100-be2012-crossflash/host-tools/`.

## Known limitations / next steps

- **OTA wipes patches.** Re-run `install.sh` after any system update.

- **Long-edge-swipe gesture** — probably aimed at the same target, hasn't been audited.

- **Surface-stack fallback** — if Lomiri ever drops HomeSpike out of the surface stack (memory pressure, crash), the wallpaper shows instead of us. Need to hook the "stack went empty" path to refire `activateApplication`.

- **AppArmor / confinement** — currently running unconfined as a system app (`/opt/...`). When this graduates to real ImGui+Lua we may need a custom apparmor template for widget data access.

- **App launch from cards** — uses `Qt.openUrlExternally("application:///")` which works through the URL dispatcher. If apparmor ever blocks it, the fallback is direct `ApplicationManager.startApplication()` — but that needs more shell-level privileges.

## Patch-site reference (current noble Lomiri)

Line numbers are from the billie2 reference unit at the time of writing; the install script's sed is pattern-based, not line-pinned, so these numbers are for orientation only.

- `Shell.qml ~ line 681` — `onShowDashHome` (BFB target — patched)

- `Shell.qml ~ line 259-261` — `Component.onCompleted` block (autostart insertion point)

- `Shell.qml ~ line 217` — `activateApplication(appId)` function we call into

- `Shell.qml ~ line 552` — `showHome()` (what BFB used to call)

- `Launcher/LauncherPanel.qml ~ line 89-145` — BFB Rectangle + click handler

- QML modules used: `GSettings 1.0`, `AccountsService 0.1`, `Lomiri.Launcher 0.1`, `Utils 0.1`

- Lomiri modules live under `/usr/lib/<arch>-linux-gnu/lomiri/qml/`; the wrapper's glob (`/usr/lib/*-linux-gnu*/lomiri/qml`) makes them visible to our app regardless of arch.

## Tested devices

| Device            | Codename | Arch    | UT version  | Notes                                                               |
| ----------------- | -------- | ------- | ----------- | ------------------------------------------------------------------- |
| OnePlus Nord N100 | billie2  | aarch64 | 24.04 noble | Reference device. Cross-flashed BE2012; see n100-be2012-crossflash. |

