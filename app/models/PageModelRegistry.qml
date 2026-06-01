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
     * snap reads explicit col/row. free reads explicit xFrac/yFrac.
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
                var appId = (typeof entry === "string") ? entry : (entry ? entry.appId : null);
                if (!appId)              continue;
                if (hiddenSet[appId])    continue;
                if (dockSet[appId])      continue;
                if (!source[appId])      continue;
                if (source[appId]._used) continue;

                var col = -1, rowI = -1, xFrac = -1, yFrac = -1;
                if (mode === "autoFill") {
                    col  = seq % cols;
                    rowI = Math.floor(seq / cols);
                    seq++;
                } else if (mode === "snap") {
                    col  = (entry && typeof entry.col === "number") ? entry.col  : -1;
                    rowI = (entry && typeof entry.row === "number") ? entry.row  : -1;
                } else if (mode === "free") {
                    xFrac = (entry && typeof entry.xFrac === "number") ? entry.xFrac : 0.0;
                    yFrac = (entry && typeof entry.yFrac === "number") ? entry.yFrac : 0.0;
                }
                pageModels[p].append(_makeRow(source[appId], col, rowI, xFrac, yFrac));
                source[appId]._used = true;
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
            yFrac: yf
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
                if (mode === "autoFill") {
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
                placed[pageModels[p].get(ii).appId] = true;
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
}
