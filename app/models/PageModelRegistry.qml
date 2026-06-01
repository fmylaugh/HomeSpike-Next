/**
 * @file PageModelRegistry
 * @description Owns the runtime models that the UI binds against:
 *   N per-page ListModels (one per home screen) and one dock ListModel.
 *   Reconciles their contents against PersistedSettings + AppHarvester.
 *
 *   Every mutation routes through this module — there are no other writers
 *   of pageModels/dockApps. Persistence happens only via persistOrder(),
 *   which is invoked from explicit user actions (drag end, dock toggle,
 *   remove, page count change) — never from rebuildVisible().
 *
 *   Page count is fixed-pool (up to maxPages) to avoid dynamic ListModel
 *   creation, which has lifecycle headaches in QML. We just clear unused
 *   models when pageCount shrinks.
 *
 *   Each pageModels[i] row carries a uniform shape so renderers and the
 *   drag controller can read the same fields regardless of placement mode:
 *     {appId, name, icon, col, row, xFrac, yFrac}
 *   The active persist.placementMode picks which of those positional
 *   fields the renderer actually consults — the others are ignored.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15

Item {
    id: root

    /** Injected by parent. Provides persist.pageData, pageCount, etc. */
    property var persist: null

    /** Injected by parent. Provides appHarvest.count + itemAt(i). */
    property var appHarvest: null

    /** Hard cap on swipeable pages. */
    readonly property int maxPages: 5

    /** Hard cap on dock entries. */
    readonly property int dockMax: 5

    /** Number of columns in the snap/autoFill grid. */
    readonly property int cols: 4

    /** Per-page models (fixed pool — only the first pageCount are used). */
    ListModel { id: page0 }
    ListModel { id: page1 }
    ListModel { id: page2 }
    ListModel { id: page3 }
    ListModel { id: page4 }
    readonly property var pageModels: [page0, page1, page2, page3, page4]

    /** Dock contents (only populated when persist.dockEnabled). */
    ListModel { id: _dock }
    readonly property var dockApps: _dock

    // Reload the visible models whenever the user flips placementMode —
    // each mode has its own saved layout slot in pageData, so the visible
    // tiles must come from the new mode's slot.
    Connections {
        target: persist
        function onPlacementModeChanged() { rebuildVisible(); }
    }

    // --------------------------------------------------------------
    // Reconciliation: pull saved pageData → fill pageModels + dockApps
    // --------------------------------------------------------------

    /**
     * Read persisted state, populate the per-page models and dock from it,
     * skipping hidden apps and silently dropping uninstalled appIds. Any
     * newly-installed apps not yet placed get auto-appended to the last
     * page UNLESS the active mode is "free" (per-spec: free placement is
     * fully manual, autoharvest skips it). Pure read — never writes back.
     */
    function rebuildVisible() {
        var pageData  = _normalisedPageData();
        var hiddenSet = _setFromArray(persist.readJson(persist.hiddenAppIds, []));
        var dockIds   = persist.dockEnabled ? persist.readJson(persist.dockOrder, []) : [];
        var dockSet   = _setFromArray(dockIds);
        var source    = _snapshotSource();

        _fillDock(dockIds, source, hiddenSet);
        _fillPages(pageData, source, hiddenSet, dockSet);
        _autoAppendNewApps(source, hiddenSet);
        _clearUnusedPages();
    }

    /**
     * Read persist.pageData (per-mode shape), pad/truncate to current
     * pageCount. When trimming, the active-mode lists from overflow pages
     * merge into the active-mode list of the last kept page; the other
     * modes' overflow lists are dropped (they were already invisible).
     *
     * Also seeds the active mode's per-page slot from autoFill (or snap)
     * the FIRST time it's visited — so switching to a mode you've never
     * used doesn't drop you on a blank page. Once seeded, persistOrder
     * will write the current arrangement back into that slot, and future
     * switches restore it instead of re-seeding.
     */
    function _normalisedPageData() {
        var pageData = persist.readPageData();
        var pc = Math.min(Math.max(1, persist.pageCount), maxPages);
        var mode = persist.placementMode;
        while (pageData.length < pc) {
            pageData.push({ autoFill: [], snap: [], free: [] });
        }
        if (pageData.length > pc) {
            var overflow = [];
            for (var z = pc; z < pageData.length; ++z) {
                var src = pageData[z][mode] || [];
                overflow = overflow.concat(src);
            }
            pageData = pageData.slice(0, pc);
            pageData[pc - 1][mode] = (pageData[pc - 1][mode] || []).concat(overflow);
        }
        for (var p = 0; p < pc; ++p) {
            _seedEmptyModeSlot(pageData[p], mode);
        }
        return pageData;
    }

    /**
     * If bag[mode] is empty but bag.autoFill (or snap) has entries, copy
     * them in with default mode-appropriate positions. No-op when bag[mode]
     * already has data — preserves whatever the user arranged last time.
     */
    function _seedEmptyModeSlot(bag, mode) {
        if (bag[mode] && bag[mode].length > 0) return;
        var seedIds = [];
        if (bag.autoFill && bag.autoFill.length > 0) {
            seedIds = bag.autoFill.slice();
        } else if (bag.snap && bag.snap.length > 0) {
            for (var i = 0; i < bag.snap.length; ++i) {
                if (bag.snap[i] && bag.snap[i].appId) seedIds.push(bag.snap[i].appId);
            }
        } else if (bag.free && bag.free.length > 0) {
            for (var j = 0; j < bag.free.length; ++j) {
                if (bag.free[j] && bag.free[j].appId) seedIds.push(bag.free[j].appId);
            }
        }
        if (seedIds.length === 0) return;
        bag[mode] = _buildEntriesForMode(seedIds, mode);
    }

    /**
     * Lay out a list of appIds in a shape valid for `mode`. autoFill is a
     * bare array; snap/free assign default positions on a 4-column grid.
     */
    function _buildEntriesForMode(appIds, mode) {
        var out = [];
        for (var i = 0; i < appIds.length; ++i) {
            if (mode === "autoFill") {
                out.push(appIds[i]);
            } else if (mode === "snap") {
                out.push({ appId: appIds[i], col: i % cols, row: Math.floor(i / cols) });
            } else if (mode === "free") {
                var c = i % cols;
                var r = Math.floor(i / cols);
                out.push({
                    appId: appIds[i],
                    xFrac: (c + 0.5) / cols,
                    yFrac: Math.min(0.92, (r + 0.5) / 8)
                });
            }
        }
        return out;
    }

    /**
     * Snapshot AppHarvester into a {appId: {appId,name,icon,_used?}} map +
     * an ordered list of appIds. Used to populate pages/dock without
     * iterating the Repeater repeatedly.
     */
    function _snapshotSource() {
        var source = {};
        var sourceIds = [];
        for (var j = 0; j < appHarvest.count; ++j) {
            var it = appHarvest.itemAt(j);
            if (!it || !it.appId) continue;
            source[it.appId] = { appId: it.appId, name: it.name, icon: it.icon };
            sourceIds.push(it.appId);
        }
        source._order = sourceIds;
        return source;
    }

    function _fillDock(dockIds, source, hiddenSet) {
        _dock.clear();
        for (var dx = 0; dx < dockIds.length && dx < dockMax; ++dx) {
            var did = dockIds[dx];
            if (hiddenSet[did])      continue;
            if (!source[did])        continue;
            if (source[did]._used)   continue;
            _dock.append(_makeRow(source[did], -1, -1, -1, -1));
            source[did]._used = true;
        }
    }

    /**
     * Fill pageModels from pageData using the active placementMode's slot.
     * autoFill uses sequential cells (col = i%cols, row = floor(i/cols)).
     * snap reads explicit col/row. free reads explicit xFrac/yFrac. Folder
     * entries occupy a slot like an app and consume their member appIds so
     * those don't also render as standalone tiles.
     */
    function _fillPages(pageData, source, hiddenSet, dockSet) {
        var mode = persist.placementMode;
        var pc = persist.pageCount;
        for (var p = 0; p < pc; ++p) {
            pageModels[p].clear();
            var entries = (pageData[p] && pageData[p][mode]) || [];
            var seq = 0;
            for (var k = 0; k < entries.length; ++k) {
                var entry = entries[k];
                var isFolder = entry && typeof entry === "object" && entry.folder === true;

                // Slot position — identical maths for apps and folders.
                var col = -1, rowI = -1, xFrac = -1, yFrac = -1;
                if (mode === "autoFill") {
                    col  = seq % cols;
                    rowI = Math.floor(seq / cols);
                } else if (mode === "snap") {
                    col  = (entry && typeof entry.col === "number") ? entry.col  : -1;
                    rowI = (entry && typeof entry.row === "number") ? entry.row  : -1;
                } else if (mode === "free") {
                    xFrac = (entry && typeof entry.xFrac === "number") ? entry.xFrac : 0.0;
                    yFrac = (entry && typeof entry.yFrac === "number") ? entry.yFrac : 0.0;
                }

                if (isFolder) {
                    // Keep only visible, installed, not-already-placed members.
                    var members = Array.isArray(entry.apps) ? entry.apps : [];
                    var live = [];
                    for (var mi = 0; mi < members.length; ++mi) {
                        var aid = members[mi];
                        if (!aid)              continue;
                        if (hiddenSet[aid])    continue;
                        if (dockSet[aid])      continue;
                        if (!source[aid])      continue;
                        if (source[aid]._used) continue;
                        live.push(aid);
                        source[aid]._used = true;
                    }
                    if (live.length === 0) continue;  // empty folder → drop it
                    pageModels[p].append(_makeFolderRow(
                        entry.id || _newFolderId(), entry.name || "Folder",
                        live, col, rowI, xFrac, yFrac));
                    if (mode === "autoFill") seq++;
                    continue;
                }

                // App entry.
                var appId = (typeof entry === "string") ? entry : (entry ? entry.appId : null);
                if (!appId)              continue;
                if (hiddenSet[appId])    continue;
                if (dockSet[appId])      continue;
                if (!source[appId])      continue;
                if (source[appId]._used) continue;

                pageModels[p].append(_makeRow(source[appId], col, rowI, xFrac, yFrac));
                source[appId]._used = true;
                if (mode === "autoFill") seq++;
            }
        }
    }

    /**
     * Any harvested app that wasn't placed in the active mode's saved
     * layout gets auto-added to the last page, unless we're in free mode
     * (where placement is intentionally manual — user adds via Drawer
     * long-press).
     */
    function _autoAppendNewApps(source, hiddenSet) {
        if (persist.placementMode === "free") return;
        var last = persist.pageCount - 1;
        var sourceIds = source._order || [];
        for (var m = 0; m < sourceIds.length; ++m) {
            var sid = sourceIds[m];
            if (source[sid]._used) continue;
            if (hiddenSet[sid])    continue;
            _placeAtFirstFreeCell(last, source[sid]);
        }
    }

    function _clearUnusedPages() {
        for (var px = persist.pageCount; px < maxPages; ++px) pageModels[px].clear();
    }

    function _setFromArray(arr) {
        var set = {};
        for (var i = 0; i < arr.length; ++i) set[arr[i]] = true;
        return set;
    }

    /**
     * Build a ListModel row with the uniform shape.
     *
     * IMPORTANT: ListModel infers each role's type from the FIRST appended
     * value and locks it. If we initialise xFrac/yFrac to -1 (an integer),
     * the role becomes int and later `setProperty(idx, "xFrac", 0.567)`
     * silently truncates to 0 — which makes free-mode placement quantise
     * to whole xFrac values (i.e. it looks like a snap-to-grid). We use a
     * non-integer sentinel (-0.5) for the "unset" case so the role is real
     * from the start. The renderer's `model.xFrac >= 0` check is unchanged
     * since -0.5 < 0 still reads as "unset".
     */
    function _makeRow(srcApp, col, rowI, xFrac, yFrac) {
        var xf = (typeof xFrac === "number" && xFrac >= 0) ? xFrac : -0.5;
        var yf = (typeof yFrac === "number" && yFrac >= 0) ? yFrac : -0.5;
        return {
            appId: srcApp.appId,
            name:  srcApp.name,
            icon:  srcApp.icon,
            col:   col,
            row:   rowI,
            xFrac: xf,
            yFrac: yf,
            // Folder fields — present on EVERY row so ListModel locks these
            // roles as string from the first append (see the type note above).
            kind:       "app",
            folderId:   "",
            folderName: "",
            appsJson:   ""
        };
    }

    /**
     * Build a ListModel row for a folder entry. Carries the same positional
     * fields as an app row (so it lives in a grid cell like any tile) plus the
     * folder identity + member list. appId/name/icon are left empty — the
     * renderer keys off kind === "folder".
     */
    function _makeFolderRow(folderId, folderName, appIds, col, rowI, xFrac, yFrac) {
        var xf = (typeof xFrac === "number" && xFrac >= 0) ? xFrac : -0.5;
        var yf = (typeof yFrac === "number" && yFrac >= 0) ? yFrac : -0.5;
        return {
            appId: "",
            name:  folderName,
            icon:  "",
            col:   col,
            row:   rowI,
            xFrac: xf,
            yFrac: yf,
            kind:       "folder",
            folderId:   folderId,
            folderName: folderName,
            appsJson:   JSON.stringify(appIds)
        };
    }

    /**
     * Find the first {col,row} cell on a page where no row currently sits.
     * Used by snap mode's auto-place + cross-page drag drops.
     */
    function firstFreeCell(pageIdx) {
        var occupied = {};
        var m = pageModels[pageIdx];
        for (var i = 0; i < m.count; ++i) {
            var r = m.get(i);
            if (typeof r.col === "number" && typeof r.row === "number"
                && r.col >= 0 && r.row >= 0) {
                occupied[r.col + "," + r.row] = true;
            }
        }
        var rowMax = 8;  // soft cap — enough rows on portrait phone
        for (var rr = 0; rr < rowMax; ++rr) {
            for (var cc = 0; cc < cols; ++cc) {
                if (!occupied[cc + "," + rr]) return { col: cc, row: rr };
            }
        }
        return { col: 0, row: rowMax };  // overflow: stack below visible area
    }

    /**
     * Find the free {col,row} cell closest to a target cell on a page — used
     * when a tile is dropped onto the grid so it lands where the user aimed.
     * Returns the target itself if free; otherwise the nearest empty cell by
     * grid distance; falls back to firstFreeCell if the page is full.
     */
    function nearestFreeCell(pageIdx, col, row) {
        var occupied = {};
        var m = pageModels[pageIdx];
        for (var i = 0; i < m.count; ++i) {
            var r = m.get(i);
            if (typeof r.col === "number" && typeof r.row === "number"
                && r.col >= 0 && r.row >= 0) {
                occupied[r.col + "," + r.row] = true;
            }
        }
        if (!occupied[col + "," + row]) return { col: col, row: row };

        var rowMax = 8;  // matches firstFreeCell's soft cap
        var best = null, bestDist = Infinity;
        for (var rr = 0; rr < rowMax; ++rr) {
            for (var cc = 0; cc < cols; ++cc) {
                if (occupied[cc + "," + rr]) continue;
                var dc = cc - col, dr = rr - row;
                var d = dc * dc + dr * dr;
                if (d < bestDist) { bestDist = d; best = { col: cc, row: rr }; }
            }
        }
        return best || firstFreeCell(pageIdx);
    }

    /**
     * Auto-place a new entry on a page using whatever the active mode
     * considers natural: append for autoFill, first-free cell for snap,
     * roughly first-free cell mapped to xFrac/yFrac for free.
     */
    function _placeAtFirstFreeCell(pageIdx, srcApp) {
        var mode = persist.placementMode;
        var col = -1, rowI = -1, xFrac = -1, yFrac = -1;
        if (mode === "autoFill") {
            var n = pageModels[pageIdx].count;
            col  = n % cols;
            rowI = Math.floor(n / cols);
        } else if (mode === "snap") {
            var c1 = firstFreeCell(pageIdx);
            col = c1.col; rowI = c1.row;
        } else if (mode === "free") {
            var c2 = firstFreeCell(pageIdx);
            // Convert cell index to fractional position — caller can drag
            // it elsewhere later. Approximate cell size of 1/cols wide and
            // ~1/8 tall in portrait.
            xFrac = (c2.col + 0.5) / cols;
            yFrac = Math.min(0.95, (c2.row + 0.5) / 8);
        }
        pageModels[pageIdx].append(_makeRow(srcApp, col, rowI, xFrac, yFrac));
    }

    // --------------------------------------------------------------
    // User-action handlers — every write to persist routes through here
    // --------------------------------------------------------------

    /**
     * Serialize the current pageModels + dockApps back to persist. Writes
     * ONLY the active mode's per-page slot; the other modes' layouts are
     * preserved untouched so switching back restores them.
     */
    function persistOrder() {
        var existing = persist.readPageData();
        var mode = persist.placementMode;
        while (existing.length < persist.pageCount) {
            existing.push({ autoFill: [], snap: [], free: [] });
        }
        for (var p = 0; p < persist.pageCount; ++p) {
            var bag = existing[p];
            var list = [];
            for (var i = 0; i < pageModels[p].count; ++i) {
                var r = pageModels[p].get(i);
                if (r.kind === "folder") {
                    // Folder entry: same shape in every mode, plus position.
                    var fobj = { folder: true, id: r.folderId, name: r.folderName,
                                 apps: _parseApps(r.appsJson) };
                    if (mode === "snap")      { fobj.col = r.col; fobj.row = r.row; }
                    else if (mode === "free") { fobj.xFrac = r.xFrac; fobj.yFrac = r.yFrac; }
                    list.push(fobj);
                } else if (mode === "autoFill") {
                    list.push(r.appId);
                } else if (mode === "snap") {
                    list.push({ appId: r.appId, col: r.col, row: r.row });
                } else if (mode === "free") {
                    list.push({ appId: r.appId, xFrac: r.xFrac, yFrac: r.yFrac });
                }
            }
            bag[mode] = list;
            existing[p] = bag;
        }
        persist.pageData = persist.writeJson(existing.slice(0, persist.pageCount));

        var dockIds = [];
        for (var j = 0; j < _dock.count; ++j) dockIds.push(_dock.get(j).appId);
        persist.dockOrder = persist.writeJson(dockIds);
    }

    /**
     * Mark an appId as hidden from HomeSpike. Stays installed; just no
     * longer appears on any page or in the _dock. Reverse via addAppsToHome.
     */
    function hideApp(appId) {
        var hidden = persist.readJson(persist.hiddenAppIds, []);
        if (hidden.indexOf(appId) === -1) {
            hidden.push(appId);
            persist.hiddenAppIds = persist.writeJson(hidden);
        }
        rebuildVisible();
    }

    /**
     * Enable or disable the _dock. Disabling moves any docked apps to the
     * end of the last page (in whichever placement mode is active);
     * enabling starts with an empty _dock.
     */
    function toggleDock(enabled) {
        if (enabled === persist.dockEnabled) return;
        if (!enabled) {
            var dockIds = persist.readJson(persist.dockOrder, []);
            var src = _snapshotSource();
            var last = persist.pageCount - 1;
            for (var i = 0; i < dockIds.length; ++i) {
                var id = dockIds[i];
                if (!src[id]) continue;
                _placeAtFirstFreeCell(last, src[id]);
            }
            persist.dockOrder = "[]";
        }
        persist.dockEnabled = enabled;
        persistOrder();
        rebuildVisible();
    }

    /**
     * Change the number of home pages (clamped 1..maxPages). When reduced,
     * the trimmed pages' apps merge into the new last page.
     */
    function setPageCount(n) {
        n = Math.min(Math.max(1, n), maxPages);
        if (n === persist.pageCount) return;
        persist.pageCount = n;
        rebuildVisible();
    }

    /**
     * Delete a whole page and eliminate its icons: every app shown on the page
     * (folder members included) is hidden, the page's saved layout is dropped
     * from pageData, and the pages after it shift down. Never removes the last
     * remaining page. Hidden apps stay installed (re-addable from the Drawer).
     */
    function deletePage(pageIdx) {
        if (persist.pageCount <= 1) return;
        if (pageIdx < 0 || pageIdx >= persist.pageCount) return;

        // Hide every app on the page (members of folders too).
        var hidden = persist.readJson(persist.hiddenAppIds, []);
        var m = pageModels[pageIdx];
        for (var i = 0; i < m.count; ++i) {
            var r = m.get(i);
            if (r.kind === "folder") {
                var fa = _parseApps(r.appsJson);
                for (var j = 0; j < fa.length; ++j) {
                    if (hidden.indexOf(fa[j]) === -1) hidden.push(fa[j]);
                }
            } else if (r.appId) {
                if (hidden.indexOf(r.appId) === -1) hidden.push(r.appId);
            }
        }
        persist.hiddenAppIds = persist.writeJson(hidden);

        // Drop the page's saved layout (all modes) and shift the rest down.
        var data = persist.readPageData();
        if (pageIdx < data.length) data.splice(pageIdx, 1);
        persist.pageData = persist.writeJson(data);

        persist.pageCount = persist.pageCount - 1;
        rebuildVisible();
    }

    /**
     * Append a batch of appIds as if the user had asked to add each one.
     * Un-hides any previously-removed entries, skips already-placed ones,
     * and respects the active placement mode for where the new tile sits.
     * This path runs from explicit user action (Drawer long-press) so even
     * in "free" mode we DO place — the user wants something to appear and
     * can drag it after.
     */
    function addAppsToHome(appIds) {
        var placed = _indexPlacedApps();
        var hidden = persist.readJson(persist.hiddenAppIds, []);
        var hiddenSet = _setFromArray(hidden);

        var changed = false;
        var last = persist.pageCount - 1;
        for (var k = 0; k < appIds.length; ++k) {
            var appId = appIds[k];

            if (hiddenSet[appId]) {
                var idx = hidden.indexOf(appId);
                if (idx >= 0) hidden.splice(idx, 1);
                delete hiddenSet[appId];
                changed = true;
            }
            if (placed[appId]) continue;

            var src = _findSourceApp(appId);
            if (!src) continue;

            _placeAtFirstFreeCell(last, src);
            placed[appId] = true;
            changed = true;
        }

        if (changed) {
            persist.hiddenAppIds = persist.writeJson(hidden);
            persistOrder();
        }
    }

    function _indexPlacedApps() {
        var placed = {};
        for (var p = 0; p < persist.pageCount; ++p) {
            for (var ii = 0; ii < pageModels[p].count; ++ii) {
                var r = pageModels[p].get(ii);
                if (r.kind === "folder") {
                    var fa = _parseApps(r.appsJson);
                    for (var fi = 0; fi < fa.length; ++fi) placed[fa[fi]] = true;
                } else {
                    placed[r.appId] = true;
                }
            }
        }
        for (var dd = 0; dd < _dock.count; ++dd) {
            placed[_dock.get(dd).appId] = true;
        }
        return placed;
    }

    function _findSourceApp(appId) {
        for (var j = 0; j < appHarvest.count; ++j) {
            var it = appHarvest.itemAt(j);
            if (it && it.appId === appId) {
                return { appId: it.appId, name: it.name, icon: it.icon };
            }
        }
        return null;
    }

    // --------------------------------------------------------------
    // Folders
    // --------------------------------------------------------------

    /** Public {name, icon} lookup for an installed appId (folder previews +
     *  the open-folder view). Returns null if the app is gone. */
    function appInfo(appId) {
        return _findSourceApp(appId);
    }

    /** Member appIds of a folder (empty array if it no longer exists). */
    function folderApps(folderId) {
        var loc = _findRowByFolderId(folderId);
        if (!loc) return [];
        return _parseApps(pageModels[loc.page].get(loc.index).appsJson);
    }

    /** Display name of a folder ("" if it no longer exists). */
    function folderNameOf(folderId) {
        var loc = _findRowByFolderId(folderId);
        return loc ? pageModels[loc.page].get(loc.index).folderName : "";
    }

    /** Whether a folder with this id is still on the grid. */
    function hasFolder(folderId) {
        return _findRowByFolderId(folderId) !== null;
    }

    function _parseApps(json) {
        if (!json) return [];
        try {
            var a = JSON.parse(json);
            return Array.isArray(a) ? a : [];
        } catch (e) {
            return [];
        }
    }

    function _newFolderId() {
        return "f-" + Date.now() + "-" + Math.floor(Math.random() * 1000000);
    }

    /** Index of the app row matching appId on a page model, or -1. Folder
     *  rows (appId === "") never match. */
    function _indexOfRowByAppId(m, appId) {
        for (var i = 0; i < m.count; ++i) {
            var r = m.get(i);
            if (r.kind !== "folder" && r.appId === appId) return i;
        }
        return -1;
    }

    /** Locate an app row across all visible pages → {page, index} or null. */
    function _findRowByAppId(appId) {
        for (var p = 0; p < persist.pageCount; ++p) {
            var idx = _indexOfRowByAppId(pageModels[p], appId);
            if (idx >= 0) return { page: p, index: idx };
        }
        return null;
    }

    /** Locate a folder row by id across all visible pages → {page, index} or null. */
    function _findRowByFolderId(folderId) {
        for (var p = 0; p < persist.pageCount; ++p) {
            var m = pageModels[p];
            for (var i = 0; i < m.count; ++i) {
                var r = m.get(i);
                if (r.kind === "folder" && r.folderId === folderId) {
                    return { page: p, index: i };
                }
            }
        }
        return null;
    }

    /**
     * Create a folder from two apps on the same page: the dragged source app
     * (sourceAppId) dropped onto the target app (targetAppId). The folder takes
     * the target's slot; both standalone app rows are removed. Persists.
     */
    function createFolder(pageIdx, targetAppId, sourceAppId, folderName) {
        if (!targetAppId || !sourceAppId || targetAppId === sourceAppId) return;
        if (pageIdx < 0 || pageIdx >= persist.pageCount) return;
        var m = pageModels[pageIdx];
        var ti = _indexOfRowByAppId(m, targetAppId);
        if (ti < 0) return;
        var t = m.get(ti);
        var name = (folderName && folderName.length > 0) ? folderName : "Folder";
        // Replace the target row in place with the folder (keeps its slot).
        m.set(ti, _makeFolderRow(_newFolderId(), name,
                                 [targetAppId, sourceAppId],
                                 t.col, t.row, t.xFrac, t.yFrac));
        // Remove the source app row (recompute its index — it may sit anywhere).
        var si = _indexOfRowByAppId(m, sourceAppId);
        if (si >= 0) m.remove(si, 1);
        persistOrder();
    }

    /** Add an app into an existing folder; removes its standalone row. Persists. */
    function addAppToFolder(folderId, appId) {
        var loc = _findRowByFolderId(folderId);
        if (!loc) return;
        var m = pageModels[loc.page];
        var apps = _parseApps(m.get(loc.index).appsJson);
        if (apps.indexOf(appId) === -1) apps.push(appId);
        m.setProperty(loc.index, "appsJson", JSON.stringify(apps));
        var sl = _findRowByAppId(appId);
        if (sl) pageModels[sl.page].remove(sl.index, 1);
        persistOrder();
    }

    /**
     * Remove an app from a folder, applying auto-dissolve (1 member left →
     * folder becomes that single app at its slot; 0 left → folder removed).
     * Does NOT place the removed app anywhere and does NOT persist — the caller
     * decides where the app goes (first-free cell, or a drop point) and
     * persists once. Returns the folder's page index, or -1 if not found.
     */
    function takeMemberFromFolder(folderId, appId) {
        var loc = _findRowByFolderId(folderId);
        if (!loc) return -1;
        var m = pageModels[loc.page];
        var f = m.get(loc.index);
        var apps = _parseApps(f.appsJson);
        var i = apps.indexOf(appId);
        if (i < 0) return loc.page;   // not a member — nothing to remove
        apps.splice(i, 1);

        if (apps.length === 0) {
            m.remove(loc.index, 1);
        } else if (apps.length === 1) {
            // Dissolve to the remaining single app at the folder's slot.
            var keep = _findSourceApp(apps[0]);
            if (keep) m.set(loc.index, _makeRow(keep, f.col, f.row, f.xFrac, f.yFrac));
            else      m.remove(loc.index, 1);
        } else {
            m.setProperty(loc.index, "appsJson", JSON.stringify(apps));
        }
        return loc.page;
    }

    /**
     * Remove an app from a folder; the app returns to the grid (first free cell
     * on the folder's page). Used by the open-folder "×". Persists.
     */
    function removeAppFromFolder(folderId, appId) {
        var page = takeMemberFromFolder(folderId, appId);
        if (page < 0) return;
        var rm = _findSourceApp(appId);
        if (rm) _placeAtFirstFreeCell(page, rm);
        persistOrder();
    }

    /** Replace a folder's member list/order (appIds). Persists. */
    function setFolderApps(folderId, ids) {
        var loc = _findRowByFolderId(folderId);
        if (!loc) return;
        pageModels[loc.page].setProperty(loc.index, "appsJson", JSON.stringify(ids));
        persistOrder();
    }

    /** Rename a folder. Persists. */
    function renameFolder(folderId, name) {
        var loc = _findRowByFolderId(folderId);
        if (!loc) return;
        var n = (name && name.length > 0) ? name : "Folder";
        pageModels[loc.page].setProperty(loc.index, "folderName", n);
        pageModels[loc.page].setProperty(loc.index, "name", n);
        persistOrder();
    }

    /**
     * Delete a folder and its contents from HomeSpike: the folder tile is
     * removed and every member app is hidden (NOT scattered back onto the
     * grid). Apps stay installed and can be re-added from the Drawer. Persists.
     */
    function deleteFolder(folderId) {
        var loc = _findRowByFolderId(folderId);
        if (!loc) return;
        var apps = _parseApps(pageModels[loc.page].get(loc.index).appsJson);

        var hidden = persist.readJson(persist.hiddenAppIds, []);
        for (var i = 0; i < apps.length; ++i) {
            if (hidden.indexOf(apps[i]) === -1) hidden.push(apps[i]);
        }
        persist.hiddenAppIds = persist.writeJson(hidden);

        pageModels[loc.page].remove(loc.index, 1);  // drop the folder tile
        persistOrder();    // write clean pageData (no folder, no member rows)
        rebuildVisible();  // re-apply the hidden set so members stay gone
    }
}
