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

    // ---- Live drag state ----
    readonly property bool dragging: sourceIndex >= 0
    property int    sourceIndex: -1
    property int    sourcePage:  -1
    property string sourceContainer: ""
    property string sourceAppId: ""
    property string sourceName:  ""
    property string sourceIcon:  ""

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
    // Edge-flip: after holding near the screen edge for 600ms, jump
    // to the adjacent page AND carry the dragged icon with us.
    // ============================================================
    Timer {
        id: edgeFlipTimer
        interval: 600
        property int direction: 0   // -1 left, +1 right

        onTriggered: {
            var target = pagesView.currentPage + direction;
            if (target < 0 || target >= persist.pageCount) return;

            if (_canCarryToPage(target)) _carryToPage(target);
            pagesView.positionViewAtIndex(target, ListView.Beginning);
        }
    }

    function _canCarryToPage(targetPage) {
        return root.dragging
            && sourceContainer === "grid"
            && sourcePage !== targetPage
            && sourcePage >= 0
            && sourceIndex >= 0
            && sourceIndex < pages.pageModels[sourcePage].count;
    }

    function _carryToPage(targetPage) {
        var item = _newGridRowForCurrentMode(targetPage);
        pages.pageModels[sourcePage].remove(sourceIndex, 1);
        pages.pageModels[targetPage].append(item);
        sourcePage = targetPage;
        sourceIndex = pages.pageModels[targetPage].count - 1;
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

    // ============================================================
    // Public API: called from TileBody MouseArea handlers
    // ============================================================

    /**
     * Begin a drag. (container, page, idx) are hints from the press delegate;
     * the real source is whichever model actually has appId. Bail silently
     * if appId can't be located.
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
        // Snapshot the pre-drag positional fields so snap-mode collision
        // resolution can swap (give the displaced tile our old cell)
        // instead of overwriting. Safe to read on dock rows too; sentinels.
        if (loc.container === "grid") {
            var r = pages.pageModels[loc.page].get(loc.index);
            sourcePrevCol   = (typeof r.col   === "number") ? r.col   : -1;
            sourcePrevRow   = (typeof r.row   === "number") ? r.row   : -1;
            sourcePrevXFrac = (typeof r.xFrac === "number") ? r.xFrac : -1;
            sourcePrevYFrac = (typeof r.yFrac === "number") ? r.yFrac : -1;
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

        if (_isOverDock(x, y)) _handleOverDock(x, y);
        else _handleOverGrid(x, y);
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
            if (sourceContainer === "grid" && overDock) {
                _commitGridToDock(lastDragX, lastDragY);
            } else if (sourceContainer === "dock" && !overDock) {
                _commitDockToGrid();
            } else if (sourceContainer === "grid" && persist.placementMode === "snap") {
                _snapResolveCollision();
            }
            pages.persistOrder();
        }
        targetingDock = false;
        sourceIndex = -1;
        sourcePage  = -1;
        sourceContainer = "";
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
        sourceIndex = -1;
        sourcePage  = -1;
        sourceContainer = "";
        sourceAppId = "";
        sourcePrevCol = -1; sourcePrevRow = -1;
        sourcePrevXFrac = -1; sourcePrevYFrac = -1;
    }

    // ============================================================
    // moveDrag helpers
    // ============================================================

    /**
     * Re-find the source's index by appId. Index can shift between moveDrag
     * calls because other drags may have reordered the models. Returns true
     * on success, false (after calling endDrag) if the source vanished.
     */
    function _relocateSource() {
        var foundIdx = -1;
        if (sourceContainer === "grid") {
            if (sourcePage < 0 || sourcePage >= persist.pageCount) return false;
            var m = pages.pageModels[sourcePage];
            for (var i = 0; i < m.count; ++i) {
                if (m.get(i).appId === sourceAppId) { foundIdx = i; break; }
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
     * the drop point. No-op (tile stays in the grid) if the dock is full or
     * the source row has gone missing. Called only from endDrag.
     */
    function _commitGridToDock(x, y) {
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
        if (mode === "autoFill")    _autoFillReorder(x, y);
        else if (mode === "snap")   _snapMoveSource(x, y);
        else                        _freeMoveSource(x, y);
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

    /**
     * Find which model (and at what index) actually contains appId.
     * Returns {container, page, index} or null.
     */
    function _findAppLocation(appId) {
        for (var p = 0; p < persist.pageCount; ++p) {
            var m = pages.pageModels[p];
            for (var i = 0; i < m.count; ++i) {
                if (m.get(i).appId === appId) return { container: "grid", page: p, index: i };
            }
        }
        for (var d = 0; d < pages.dockApps.count; ++d) {
            if (pages.dockApps.get(d).appId === appId) {
                return { container: "dock", page: -1, index: d };
            }
        }
        return null;
    }

    // ============================================================
    // Visual: the floating icon that tracks the drag cursor
    // ============================================================
    LomiriShape {
        id: floatingIcon
        visible: root.dragging
        width: units.gu(6) * 1.15
        height: 7.5 / 8 * width
        radius: "medium"
        borderSource: "undefined"
        sourceFillMode: LomiriShape.PreserveAspectCrop
        opacity: 0.92
        source: Image {
            asynchronous: true
            sourceSize.width: floatingIcon.width
            source: root.sourceIcon
        }
    }
}
