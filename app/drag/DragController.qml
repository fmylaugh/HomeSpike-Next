/**
 * @file DragController
 * @description Owns every part of the drag-and-drop interaction: the
 *   live drag state, the floating icon visual, edge-flip-to-next-page
 *   timer, and the cell-targeting math. Mutates page/dock models
 *   directly via the injected PageModelRegistry.
 *
 *   Design rules:
 *   - moveDrag never crosses pages on its own. Cross-page transitions
 *     happen ONLY in edgeFlipTimer, which is the user's deliberate hover-
 *     near-edge gesture. This avoids the "stale currentPage" auto-jump
 *     bugs we fought during initial development.
 *   - startDrag's claimed (container, page, index) from the press delegate
 *     is treated as a hint. The authoritative source is _findAppLocation
 *     which scans the actual models — delegates can lie about their page
 *     index after model edits.
 *   - persistOrder fires only from endDrag, never from moveDrag (every
 *     model mutation along a drag would write to disk N times per second).
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: root

    // ---- Injected dependencies (set by parent) ----
    /** PageModelRegistry — owns pageModels[] + dockApps. */
    property var pages: null

    /** PersistedSettings — used for pageCount + dockEnabled reads. */
    property var persist: null

    /** Horizontal ListView of pages. Used for currentPage + edge-flip scrolling. */
    property var pagesView: null

    /** Dock Rectangle. Used as the geometry target for dock hit-testing. */
    property var dockBar: null

    /** Set true by moveDrag when the drag cursor is over the dock area
     *  AND the source isn't already in the dock. Caller binds dock
     *  highlighting to this. */
    property bool targetingDock: false

    /** While dragging an app, the model index (on sourcePage) of the tile the
     *  finger is hovering over to merge into — or -1. Drives the merge
     *  highlight and suppresses reorder so the drop lands on that tile. */
    property int mergeTargetIndex: -1

    // ---- Live drag state ----
    readonly property bool dragging: sourceIndex >= 0
    property int    sourceIndex: -1
    property int    sourcePage:  -1
    property string sourceContainer: ""
    property string sourceAppId: ""
    property string sourceName:  ""
    property string sourceIcon:  ""
    // "app" or "folder" — folders can be reordered/moved but never merge into
    // another tile or get dropped into the dock.
    property string sourceKind:  "app"
    // Member preview icons (up to 4) when dragging a folder, so the floating
    // visual shows the folder itself rather than its first app.
    property var    sourceFolderIcons: []

    /** Emitted when an app is dropped onto another app — caller shows the
     *  name popup, then calls pages.createFolder on confirm. */
    signal folderCreateRequested(int page, string targetAppId, string sourceAppId)

    // Pre-drag positional snapshot, captured at startDrag. Used by snap
    // mode to resolve cell collisions on release (the displaced tile is
    // sent to the source's previous cell — i.e. swap, not overwrite).
    property int  sourcePrevCol:   -1
    property int  sourcePrevRow:   -1
    property real sourcePrevXFrac: -1
    property real sourcePrevYFrac: -1

    // Most recent drag point in DragController-local coordinates. Used by
    // free-mode cross-page carries so the dragged tile lands somewhere
    // useful on the new page rather than at (0, 0).
    property real lastDragX: 0
    property real lastDragY: 0

    z: 300
    anchors.fill: parent

    // ============================================================
    // Edge-flip: while holding the dragged tile near a screen edge, page
    // through the launcher so the user can keep carrying it. We ONLY scroll
    // the view here — the dragged tile stays on its original page (opacity 0)
    // so its MouseArea keeps the touch grab; the actual move to the dropped-on
    // page happens at release in endDrag. pagesView.cacheBuffer keeps every
    // page instantiated so the source delegate survives the scroll.
    //
    // repeat:true keeps flipping every interval while held, and the target
    // wraps around: past the last page loops to the first (and vice versa).
    // ============================================================
    Timer {
        id: edgeFlipTimer
        interval: 600
        repeat: true
        property int direction: 0   // -1 left, +1 right

        onTriggered: {
            if (direction === 0 || !root.dragging) { stop(); return; }
            var n = persist.pageCount;
            if (n <= 1) { stop(); return; }
            var target = (pagesView.currentPage + direction + n) % n;  // wrap
            pagesView.currentIndex = target;  // strict-range view animates to it
        }
    }

    /**
     * Move the source grid row to `dropPage` at the current drop point, using
     * the active mode's placement. Called at release (endDrag) — never mid-drag,
     * so the dragged delegate isn't destroyed while it owns the touch.
     *
     * Copies the ENTIRE source row (not a freshly-built app row) so a folder
     * keeps its identity + members — `_newGridRowForCurrentMode` only knows the
     * app drag fields and would turn a carried folder into a single broken tile.
     */
    function _carryToPageAt(dropPage) {
        if (sourcePage < 0 || sourceIndex < 0) return;
        if (sourceIndex >= pages.pageModels[sourcePage].count) return;

        var src = pages.pageModels[sourcePage].get(sourceIndex);
        var item = {
            appId: src.appId, name: src.name, icon: src.icon,
            col: -1, row: -1, xFrac: -0.5, yFrac: -0.5,
            kind: src.kind, folderId: src.folderId,
            folderName: src.folderName, appsJson: src.appsJson
        };
        // Position on the drop page from the release point + active mode.
        var mode = persist.placementMode;
        if (mode === "snap") {
            var cell = _computeGridCell(lastDragX, lastDragY);
            var c = cell ? pages.nearestFreeCell(dropPage, cell.col, cell.row)
                         : pages.firstFreeCell(dropPage);
            item.col = c.col;
            item.row = c.row;
        } else if (mode === "free") {
            var lp = _toPagesViewLocal(lastDragX, lastDragY);
            var w = Math.max(1, pagesView.width);
            var h = Math.max(1, pagesView.height);
            item.xFrac = Math.min(0.95, Math.max(0.05, lp.x / w));
            item.yFrac = Math.min(0.95, Math.max(0.05, lp.y / h));
        }
        pages.pageModels[sourcePage].remove(sourceIndex, 1);
        pages.pageModels[dropPage].append(item);
    }

    /**
     * Build a row payload for an append into pages.pageModels[targetPage]
     * that's appropriate for the active placement mode. autoFill ignores
     * position fields (delegate reads `index`); snap lands on the cell nearest
     * the drop point; free uses the current drag point converted to xFrac/yFrac
     * on the target page.
     */
    function _newGridRowForCurrentMode(targetPage) {
        var mode = persist.placementMode;
        // -0.5 sentinel (not -1) keeps the ListModel role typed as real —
        // see PageModelRegistry._makeRow for the full reasoning.
        var item = {
            appId: sourceAppId,
            name:  sourceName,
            icon:  sourceIcon,
            col:   -1,
            row:   -1,
            xFrac: -0.5,
            yFrac: -0.5
        };
        if (mode === "snap") {
            // Land on the cell under the drop point, not the first free slot.
            // If that exact cell is taken, the nearest empty one wins.
            var cell = _computeGridCell(lastDragX, lastDragY);
            var c = cell ? pages.nearestFreeCell(targetPage, cell.col, cell.row)
                         : pages.firstFreeCell(targetPage);
            item.col = c.col;
            item.row = c.row;
        } else if (mode === "free") {
            // lastDrag is in DragController-local; translate to pagesView-
            // local (matches pageDelegate-local for the visible page) so
            // the carried tile lands where the user's finger actually is.
            var lp = _toPagesViewLocal(lastDragX, lastDragY);
            var w = Math.max(1, pagesView.width);
            var h = Math.max(1, pagesView.height);
            var xf = Math.min(0.95, Math.max(0.05, lp.x / w));
            var yf = Math.min(0.95, Math.max(0.05, lp.y / h));
            item.xFrac = xf;
            item.yFrac = yf;
        }
        return item;
    }

    /**
     * Drop a standalone app onto the current page at a point in root/controller
     * coordinates, using the active placement mode (snap → nearest free cell to
     * the point; free → fractional point; autoFill → appended). Persists. Used
     * by the folder overlay's drag-out so the app lands where it was released.
     */
    function placeAppAtPoint(appId, name, icon, rootX, rootY) {
        var page = pagesView.currentPage;
        if (page < 0 || page >= persist.pageCount) page = 0;
        var mode = persist.placementMode;
        var item = {
            appId: appId, name: name, icon: icon,
            col: -1, row: -1, xFrac: -0.5, yFrac: -0.5,
            kind: "app", folderId: "", folderName: "", appsJson: ""
        };
        if (mode === "snap") {
            var cell = _computeGridCell(rootX, rootY);
            var c = cell ? pages.nearestFreeCell(page, cell.col, cell.row)
                         : pages.firstFreeCell(page);
            item.col = c.col;
            item.row = c.row;
        } else if (mode === "free") {
            var lp = _toPagesViewLocal(rootX, rootY);
            var w = Math.max(1, pagesView.width);
            var h = Math.max(1, pagesView.height);
            item.xFrac = Math.min(0.95, Math.max(0.05, lp.x / w));
            item.yFrac = Math.min(0.95, Math.max(0.05, lp.y / h));
        }
        pages.pageModels[page].append(item);  // autoFill: position by order
        pages.persistOrder();
    }

    // ============================================================
    // Public API: called from TileBody MouseArea handlers
    // ============================================================

    /**
     * Begin a drag. (container, page, idx) are hints from the press delegate;
     * the real source is whichever model actually has this key. `appId` is a
     * generic key: an appId for app tiles, a folderId for folder tiles. Bail
     * silently if it can't be located.
     */
    function startDrag(container, page, idx, appId, name, icon, x, y) {
        var loc = _findAppLocation(appId);
        if (!loc) {
            sourceContainer = "";
            sourcePage = -1;
            sourceIndex = -1;
            return;
        }
        sourceContainer = loc.container;
        sourcePage = loc.page;
        sourceIndex = loc.index;
        sourceAppId = appId;
        sourceName = name;
        sourceIcon = icon;
        sourceKind = "app";
        sourceFolderIcons = [];
        // Snapshot the pre-drag positional fields so snap-mode collision
        // resolution can swap (give the displaced tile our old cell)
        // instead of overwriting. Safe to read on dock rows too; sentinels.
        if (loc.container === "grid") {
            var r = pages.pageModels[loc.page].get(loc.index);
            sourceKind      = (r.kind === "folder") ? "folder" : "app";
            sourcePrevCol   = (typeof r.col   === "number") ? r.col   : -1;
            sourcePrevRow   = (typeof r.row   === "number") ? r.row   : -1;
            sourcePrevXFrac = (typeof r.xFrac === "number") ? r.xFrac : -1;
            sourcePrevYFrac = (typeof r.yFrac === "number") ? r.yFrac : -1;
            // For a folder, gather member icons so the floating visual renders
            // the folder preview instead of a single app icon.
            if (sourceKind === "folder") {
                var fids = [];
                try { fids = JSON.parse(r.appsJson || "[]"); } catch (e) { fids = []; }
                var ficons = [];
                for (var fi = 0; fi < fids.length && ficons.length < 4; ++fi) {
                    var info = pages.appInfo(fids[fi]);
                    if (info) ficons.push(info.icon);
                }
                sourceFolderIcons = ficons;
            }
        } else {
            sourcePrevCol = -1; sourcePrevRow = -1;
            sourcePrevXFrac = -1; sourcePrevYFrac = -1;
        }
        lastDragX = x;
        lastDragY = y;
        floatingIcon.x = x - floatingIcon.width / 2;
        floatingIcon.y = y - floatingIcon.height / 2;
    }

    /**
     * Update the drag position. Reorders within the source page or
     * transitions in/out of the dock as appropriate. Never crosses pages —
     * that's edgeFlipTimer's job.
     */
    function moveDrag(x, y) {
        if (!dragging || sourceContainer === "") return;
        if (!_relocateSource()) return;

        lastDragX = x;
        lastDragY = y;
        floatingIcon.x = x - floatingIcon.width / 2;
        floatingIcon.y = y - floatingIcon.height / 2;

        _updateEdgeFlipDirection(x);

        if (_isOverDock(x, y)) {
            mergeTargetIndex = -1;
            _handleOverDock(x, y);
            return;
        }

        // Mid cross-page carry: the view is showing a page other than the
        // source's. Don't reorder/merge on the (off-screen) source page — just
        // track the finger and let edge-flip keep paging. The actual move to
        // the viewed page happens at release.
        if (sourceContainer === "grid" && pagesView.currentPage !== sourcePage) {
            mergeTargetIndex = -1;
            return;
        }

        // Hovering an app source directly over another tile = merge intent:
        // hold the layout (skip reorder/move) so the drop lands on that tile.
        // The floating icon still tracks the finger; neighbouring tiles
        // freezing is the "will merge here" cue.
        var mt = (sourceContainer === "grid" && sourceKind === "app")
                 ? _mergeTargetIndex(x, y) : -1;
        mergeTargetIndex = mt;
        if (mt >= 0) {
            targetingDock = false;
            return;
        }
        _handleOverGrid(x, y);
    }

    /**
     * Finalise the drag. Snap-mode collision resolution happens here (so
     * the swap only fires once, on release, instead of jittering mid-drag).
     * Persists the result.
     */
    function endDrag() {
        edgeFlipTimer.stop();
        edgeFlipTimer.direction = 0;
        if (sourceIndex >= 0 && sourceContainer !== "") {
            // Cross-container moves are committed HERE, not during moveDrag:
            // removing the source row mid-drag destroys the delegate whose
            // MouseArea owns the touch, which kills onReleased and strands
            // the drag. By the time we're in endDrag the release already
            // fired, so it's safe to mutate the models now.
            var overDock = _isOverDock(lastDragX, lastDragY);
            var persistNow = true;

            if (sourceContainer === "grid" && overDock) {
                if (sourceKind === "folder") {
                    // Folders are grid-only — discard the live reorder, stay put.
                    pages.rebuildVisible();
                    persistNow = false;
                } else {
                    _commitGridToDock(lastDragX, lastDragY);
                }
            } else if (sourceContainer === "dock" && !overDock) {
                _commitDockToGrid();
            } else if (sourceContainer === "grid" && !overDock
                       && pagesView.currentPage >= 0
                       && pagesView.currentPage < persist.pageCount
                       && pagesView.currentPage !== sourcePage) {
                // Released on a different page than it started → relocate it
                // there at the drop point (no folder-merge across pages in v1).
                _carryToPageAt(pagesView.currentPage);
            } else if (sourceContainer === "grid" && !overDock) {
                // Did we drop on top of another tile? (apps only — a folder
                // dragged onto a tile just reorders.)
                var mt = (sourceKind === "app") ? _mergeTargetIndex(lastDragX, lastDragY) : -1;
                if (mt >= 0) {
                    var tr = pages.pageModels[sourcePage].get(mt);
                    var tgtPage = sourcePage, srcAppId = sourceAppId;
                    if (tr.kind === "folder") {
                        pages.addAppToFolder(tr.folderId, srcAppId);  // persists itself
                        persistNow = false;
                    } else {
                        // app-on-app → name popup; commit on confirm. Revert the
                        // live drag now so the grid behind the popup is clean and
                        // cancel is a no-op.
                        var tgtAppId = tr.appId;
                        pages.rebuildVisible();
                        folderCreateRequested(tgtPage, tgtAppId, srcAppId);
                        persistNow = false;
                    }
                } else if (persist.placementMode === "snap") {
                    _snapResolveCollision();
                } else if (persist.placementMode === "autoFill") {
                    // autoFill reorder is deferred to here (see _handleOverGrid).
                    // Landscape also runs this path (packed reorder), which only
                    // changes list order — saved snap col/row are left intact.
                    _autoFillReorder(lastDragX, lastDragY);
                }
            }
            // else: dock && overDock — reorder already applied live.

            if (persistNow) pages.persistOrder();
        }
        targetingDock = false;
        mergeTargetIndex = -1;
        sourceIndex = -1;
        sourcePage  = -1;
        sourceContainer = "";
        sourceKind = "app";
        sourceFolderIcons = [];
        sourcePrevCol = -1; sourcePrevRow = -1;
        sourcePrevXFrac = -1; sourcePrevYFrac = -1;
    }

    /**
     * Discard any in-flight drag state WITHOUT persisting. Use for defensive
     * cleanup when a previous drag's onReleased never fired (e.g. its
     * delegate was destroyed mid-drag during a cross-page scroll).
     */
    function abort() {
        edgeFlipTimer.stop();
        edgeFlipTimer.direction = 0;
        targetingDock = false;
        mergeTargetIndex = -1;
        sourceIndex = -1;
        sourcePage  = -1;
        sourceContainer = "";
        sourceAppId = "";
        sourceKind = "app";
        sourceFolderIcons = [];
        sourcePrevCol = -1; sourcePrevRow = -1;
        sourcePrevXFrac = -1; sourcePrevYFrac = -1;
    }

    // ============================================================
    // moveDrag helpers
    // ============================================================

    /**
     * Re-find the source's index by key (appId for apps, folderId for folders).
     * Index can shift between moveDrag calls because other drags may have
     * reordered the models. Returns true on success, false (after calling
     * endDrag) if the source vanished.
     */
    function _relocateSource() {
        var foundIdx = -1;
        if (sourceContainer === "grid") {
            if (sourcePage < 0 || sourcePage >= persist.pageCount) return false;
            var m = pages.pageModels[sourcePage];
            for (var i = 0; i < m.count; ++i) {
                if (_rowKey(m.get(i)) === sourceAppId) { foundIdx = i; break; }
            }
        } else if (sourceContainer === "dock") {
            for (var j = 0; j < pages.dockApps.count; ++j) {
                if (pages.dockApps.get(j).appId === sourceAppId) { foundIdx = j; break; }
            }
        }
        if (foundIdx < 0) {
            endDrag();
            return false;
        }
        sourceIndex = foundIdx;
        return true;
    }

    function _updateEdgeFlipDirection(x) {
        var edgeMargin = units.gu(3);
        var newDir = 0;
        if (x < edgeMargin) newDir = -1;
        else if (x > width - edgeMargin) newDir = +1;
        if (newDir !== edgeFlipTimer.direction) {
            edgeFlipTimer.stop();
            edgeFlipTimer.direction = newDir;
            if (newDir !== 0) edgeFlipTimer.start();
        }
    }

    function _isOverDock(x, y) {
        if (!persist.dockEnabled || !dockBar) return false;
        var dp = root.mapToItem(dockBar, x, y);
        return dp.x >= 0 && dp.x <= dockBar.width && dp.y >= 0 && dp.y <= dockBar.height;
    }

    function _handleOverDock(x, y) {
        targetingDock = sourceContainer !== "dock";

        if (sourceContainer === "dock") {
            // Reordering within the dock is a model.move() — it preserves the
            // dragged delegate, so it's safe to do live.
            var dp = root.mapToItem(dockBar, x, y);
            _reorderInDock(dp.x);
        }
        // grid source over dock: do NOT move now — that would destroy the
        // dragged grid delegate. Just light up the dock; the move commits in
        // endDrag once the release has fired. The source tile stays in the
        // grid at opacity 0 so its MouseArea keeps tracking the finger.
    }

    /**
     * Map an x coordinate (in dockBar-local space) to a dock slot index,
     * honouring the live per-item width and the fact that the icon Row is
     * centred in dockBar. `extraItems` widens the assumed row by N items —
     * pass 1 when computing an insertion slot for a tile not yet in the dock
     * so its pre-insert width matches what the user sees.
     */
    function _dockIndexAt(dockX, extraItems) {
        var n = dockBar.dockCount + (extraItems || 0);
        if (n <= 0) return 0;
        var cellW    = dockBar.dockItemW + dockBar.dockGap;
        var rowWidth = n * dockBar.dockItemW + (n - 1) * dockBar.dockGap;
        var rowLeft  = (dockBar.width - rowWidth) / 2;
        return Math.floor((dockX - rowLeft) / cellW);
    }

    function _reorderInDock(dockX) {
        var targetIdx = _dockIndexAt(dockX, 0);
        if (targetIdx < 0) targetIdx = 0;
        if (targetIdx >= pages.dockApps.count) targetIdx = pages.dockApps.count - 1;
        if (targetIdx !== sourceIndex) {
            pages.dockApps.move(sourceIndex, targetIdx, 1);
            sourceIndex = targetIdx;
        }
    }

    /**
     * Commit a grid→dock move at release time. Inserts at the dock slot under
     * the drop point. No-op (tile stays in the grid) if the dock is full, the
     * source is a folder (grid-only), or the source row has gone missing.
     * Called only from endDrag.
     */
    function _commitGridToDock(x, y) {
        if (sourceKind === "folder") return;
        if (pages.dockApps.count >= pages.dockMax) return;
        if (sourcePage < 0 || sourceIndex < 0) return;
        if (sourceIndex >= pages.pageModels[sourcePage].count) return;

        var dp = root.mapToItem(dockBar, x, y);
        // +1 item: the tile isn't in the dock yet, so size the row as if it
        // already were to land the insertion under the finger.
        var targetIdx = _dockIndexAt(dp.x, 1);
        if (targetIdx < 0) targetIdx = 0;
        if (targetIdx > pages.dockApps.count) targetIdx = pages.dockApps.count;

        pages.pageModels[sourcePage].remove(sourceIndex, 1);
        pages.dockApps.insert(targetIdx, {
            appId: sourceAppId,
            name:  sourceName,
            icon:  sourceIcon,
            col:   -1, row: -1, xFrac: -0.5, yFrac: -0.5
        });
    }

    /**
     * Drop-over-grid dispatch. Branches by placementMode AND source
     * container (dock vs grid).
     */
    function _handleOverGrid(x, y) {
        targetingDock = false;
        if (sourceContainer === "dock") {
            // dock source over grid: defer to endDrag for the same delegate-
            // destruction reason as grid→dock. The dock tile stays put at
            // opacity 0 until release commits the move.
            return;
        }
        if (sourceContainer !== "grid") return;

        var mode = persist.placementMode;
        // autoFill is NOT reordered live: a swap-based reorder would slide the
        // target out from under the finger and defeat the merge hot-zone test.
        // It commits at endDrag instead. snap/free move the (invisible, opacity
        // 0) source live, which never displaces another tile.
        if (mode === "snap")      _snapMoveSource(x, y);
        else if (mode === "free") _freeMoveSource(x, y);
    }

    // --- autoFill: live-reorder the model by index (existing behavior) ---
    function _autoFillReorder(x, y) {
        var target = _computeGridCellIndex(x, y);
        if (target < 0) return;
        var pageModel = pages.pageModels[sourcePage];
        if (target >= pageModel.count) target = pageModel.count - 1;
        if (target !== sourceIndex) {
            pageModel.move(sourceIndex, target, 1);
            sourceIndex = target;
        }
    }

    // --- snap: move source row's (col,row) to the cell under the cursor.
    // Overlap is allowed during the drag (visually fine — source is
    // opacity:0); collision is resolved on release in _snapResolveCollision.
    function _snapMoveSource(x, y) {
        var cell = _computeGridCell(x, y);
        if (!cell) return;
        var m = pages.pageModels[sourcePage];
        var r = m.get(sourceIndex);
        if (r.col !== cell.col) m.setProperty(sourceIndex, "col", cell.col);
        if (r.row !== cell.row) m.setProperty(sourceIndex, "row", cell.row);
    }

    // --- free: continuously write xFrac/yFrac so the tile follows finger.
    function _freeMoveSource(x, y) {
        var p = _toPagesViewLocal(x, y);
        var w = Math.max(1, pagesView.width);
        var h = Math.max(1, pagesView.height);
        var xf = Math.min(0.98, Math.max(0.02, p.x / w));
        var yf = Math.min(0.98, Math.max(0.02, p.y / h));
        var m = pages.pageModels[sourcePage];
        m.setProperty(sourceIndex, "xFrac", xf);
        m.setProperty(sourceIndex, "yFrac", yf);
    }

    /**
     * Translate DragController-local (x,y) — which equal root-local since
     * DragController fills the root Item — into pagesView-local coords.
     * pagesView is offset from root by (leftReserve, topMargin) via its
     * anchor margins; the renderer expects coords in pageDelegate-local
     * which match pagesView-local for the visible page.
     */
    function _toPagesViewLocal(x, y) {
        return { x: x - pagesView.x, y: y - pagesView.y };
    }

    // --- snap collision swap (fires at endDrag, never mid-drag).
    function _snapResolveCollision() {
        if (sourcePage < 0 || sourceIndex < 0) return;
        var m = pages.pageModels[sourcePage];
        if (sourceIndex >= m.count) return;
        var src = m.get(sourceIndex);
        for (var i = 0; i < m.count; ++i) {
            if (i === sourceIndex) continue;
            var r = m.get(i);
            if (r.col === src.col && r.row === src.row) {
                // Displace the occupant into source's pre-drag cell (swap).
                m.setProperty(i, "col", sourcePrevCol);
                m.setProperty(i, "row", sourcePrevRow);
                return;
            }
        }
    }

    /**
     * Convert DragController-space (x,y) into a target cell INDEX on the
     * current page (autoFill mode). Returns -1 if above the grid area.
     */
    function _computeGridCellIndex(x, y) {
        var cell = _computeGridCell(x, y);
        if (!cell) return -1;
        return cell.row * pages.cols + cell.col;
    }

    /**
     * Convert DragController-space (x,y) into a {col, row} cell on the
     * current page. Returns null if above the grid.
     */
    function _computeGridCell(x, y) {
        var p = _toPagesViewLocal(x, y);
        var leftMargin = units.gu(1);
        var gridWidth  = pagesView.width - 2 * leftMargin;
        // Use the renderer's live row pitch (derived to tile the viewport)
        // so a drop lands on the same row the grid actually draws.
        var cellH      = pagesView.cellH;
        var cellW      = gridWidth / pages.cols;

        var pageX = p.x - leftMargin;
        var pageY = p.y;
        if (pageY < 0) return null;
        if (pageX < 0) pageX = 0;
        if (pageX >= gridWidth) pageX = gridWidth - 1;

        var col = Math.floor(pageX / cellW);
        var row = Math.floor(pageY / cellH);
        if (col < 0) col = 0;
        if (col >= pages.cols) col = pages.cols - 1;
        if (row < 0) row = 0;
        // Clamp to rows that actually fit so a low drop can't land a tile in
        // an off-screen row.
        if (row > pagesView.gridRows - 1) row = pagesView.gridRows - 1;
        return { col: col, row: row };
    }

    /**
     * Find a tile on the current page to MERGE the dragged source into — i.e.
     * the source was dropped squarely on top of another tile. Returns that
     * tile's model index, or -1 if the drop is in open space / on itself.
     *
     * Works in all three modes by comparing the drop point to each OTHER
     * tile's rendered centre (computed the same way main.qml binds x/y) and
     * accepting the nearest one within a hot-zone roughly the icon's size.
     */
    function _mergeTargetIndex(x, y) {
        if (sourcePage < 0 || sourcePage >= persist.pageCount) return -1;
        var p  = _toPagesViewLocal(x, y);
        var m  = pages.pageModels[sourcePage];
        var mode = persist.placementMode;

        var leftMargin = pagesView.gridLeftMargin;
        var gridWidth  = pagesView.width - leftMargin - pagesView.gridRightMargin;
        var cellW      = gridWidth / pages.cols;
        var cellH      = pagesView.cellH;
        var pageW      = pagesView.width;
        var pageH      = pagesView.height;
        var hot        = units.gu(4);   // ~icon radius
        var hot2       = hot * hot;

        var best = -1, bestDist = Infinity;
        for (var i = 0; i < m.count; ++i) {
            if (i === sourceIndex) continue;
            var r = m.get(i);
            var cx, cy;
            if (mode === "free") {
                var f = (r.xFrac > 0.001) ? r.xFrac : 0.5;
                var g = (r.yFrac > 0.001) ? r.yFrac : 0.5;
                cx = f * pageW;
                cy = g * pageH;
            } else {
                var col = (mode === "snap") ? (r.col >= 0 ? r.col : 0) : (i % pages.cols);
                var row = (mode === "snap") ? (r.row >= 0 ? r.row : 0) : Math.floor(i / pages.cols);
                cx = leftMargin + col * cellW + cellW / 2;
                cy = row * cellH + cellH / 2;
            }
            var dx = p.x - cx, dy = p.y - cy;
            var d2 = dx * dx + dy * dy;
            if (d2 < hot2 && d2 < bestDist) { bestDist = d2; best = i; }
        }
        return best;
    }

    /**
     * Commit a dock→grid move at release time. Drops onto the current page
     * using the active mode's natural placement. No-op if the source row has
     * gone missing. Called only from endDrag.
     */
    function _commitDockToGrid() {
        if (sourceIndex < 0 || sourceIndex >= pages.dockApps.count) return;
        var dropPage = pagesView.currentPage;
        if (dropPage < 0 || dropPage >= persist.pageCount) return;
        var item = _newGridRowForCurrentMode(dropPage);
        pages.dockApps.remove(sourceIndex, 1);
        pages.pageModels[dropPage].append(item);
    }

    // ============================================================
    // Authoritative source lookup — used by startDrag
    // ============================================================

    /** A row's drag key: folderId for folders, appId for apps. */
    function _rowKey(r) {
        return (r && r.kind === "folder") ? r.folderId : (r ? r.appId : "");
    }

    /**
     * Find which model (and at what index) actually contains this key (appId
     * for apps, folderId for folders). Returns {container, page, index} or null.
     */
    function _findAppLocation(key) {
        for (var p = 0; p < persist.pageCount; ++p) {
            var m = pages.pageModels[p];
            for (var i = 0; i < m.count; ++i) {
                if (_rowKey(m.get(i)) === key) return { container: "grid", page: p, index: i };
            }
        }
        for (var d = 0; d < pages.dockApps.count; ++d) {
            if (pages.dockApps.get(d).appId === key) {
                return { container: "dock", page: -1, index: d };
            }
        }
        return null;
    }

    // ============================================================
    // Visual: the floating tile that tracks the drag cursor. Mirrors the
    // stationary tile — a single icon for apps, the 2x2 preview for folders.
    // ============================================================
    Item {
        id: floatingIcon
        visible: root.dragging
        width: units.gu(6) * 1.15
        height: 7.5 / 8 * width
        opacity: 0.92

        // App: single icon.
        LomiriShape {
            anchors.fill: parent
            visible: root.sourceKind !== "folder"
            radius: "medium"
            borderSource: "undefined"
            sourceFillMode: LomiriShape.PreserveAspectCrop
            source: Image {
                asynchronous: true
                sourceSize.width: floatingIcon.width
                source: root.sourceIcon
            }
        }

        // Folder: frosted plate with up to 4 mini icons (matches TileBody).
        Rectangle {
            id: floatFolderPlate
            anchors.fill: parent
            visible: root.sourceKind === "folder"
            radius: units.gu(1.2)
            color: "#40ffffff"
            Grid {
                anchors.centerIn: parent
                columns: 2
                rowSpacing: units.gu(0.4)
                columnSpacing: units.gu(0.4)
                Repeater {
                    model: root.sourceFolderIcons
                    delegate: LomiriShape {
                        width: (floatFolderPlate.width - units.gu(1.6)) / 2
                        height: 7.5 / 8 * width
                        radius: "small"
                        borderSource: "undefined"
                        sourceFillMode: LomiriShape.PreserveAspectCrop
                        source: Image {
                            asynchronous: true
                            sourceSize.width: width
                            source: modelData
                        }
                    }
                }
            }
        }
    }
}
