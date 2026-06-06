/**
 * @file main
 * @description HomeSpike composition root. Wires every module together —
 *   persistence, wallpaper, app source, page/dock models, drag controller,
 *   cross-process inbox, tiles, overlays, and edit-mode chrome — and
 *   defines the visual stack (wallpaper → pages → page dots → dock →
 *   chrome → overlays).
 *
 *   Each module lives in its own subdir under app/ and is responsible for
 *   one slice of behaviour. main.qml owns nothing — every line here is
 *   either a module instantiation or a binding between modules.
 *
 * @status Stable.
 * @issues None
 * @todo
 *   - [ ] Extract the inline pagesView ListView + page-dots Row into
 *         a PagesView module once the design settles (currently fine
 *         since it's the canvas everything else binds to).
 */
import QtQuick 2.15
import GSettings 1.0
import Lomiri.Components 1.3
import "persistence"
import "wallpaper"
import "models"
import "drag"
import "tiles"
import "widgets"
import "chrome"
import "overlays"

// HomeSpike root is now an Item, not a Window — loaded inline by Lomiri's
// Stage.qml as the background layer (z=-2). HomeSpike no longer runs as a
// separate process; it lives inside the lomiri shell process.
Item {
    id: root
    anchors.fill: parent

    // Solid background under everything (the WallpaperResolver Image draws
    // over this; the colour shows for the brief moment before it loads).
    Rectangle { anchors.fill: parent; color: "#1d2540" }

    // ============================================================
    // State
    // ============================================================
    property bool editMode: false
    readonly property real dockHeight: units.gu(12)

    // Lomiri's Stage.qml writes the launcher's current visible width here
    // (via the Loader's binding) so we can inset our grid/dock/dots and
    // not let the launcher panel cover the leftmost icon column.
    property real leftReserve: 0

    // Exposed for Lomiri's Shell.qml to read — when true, the left launcher
    // panel is force-collapsed (lockedVisible=false) so the dock owns the
    // bottom row of launcher icons and the grid uses the full width.
    readonly property bool dockEnabled: persist.dockEnabled

    /** Fired when the user taps any tile (grid or dock) to launch its app.
     *  Stage.qml's wallpaper Loader Connections listens for this and drops
     *  homeShown immediately — without it, Mir's focus-echo can be
     *  misread as the launch and the home overlay stays stuck on top. */
    signal launchRequested(string appId)

    // Master kill-switch (Settings → Personal → HomeSpike). When false,
    // HomeSpike's UI hides — wallpaper Image stays visible so the screen
    // still has a backdrop, but the grid, dock, page dots, edit chrome,
    // and overlays all vanish. Override files in lomiri-overrides also
    // bind to this same gsettings key, so the rest of the shell reverts
    // to stock behavior in lockstep.
    GSettings {
        id: hsSettings
        schema.id: "com.lomiri.HomeSpike"
    }
    readonly property bool uiEnabled: hsSettings.enabled

    // Reactive "Add to HomeSpike" inbox: the patched Drawer appends an appId to
    // the `pending-adds` gsettings key; we place it on the grid and clear the
    // key. We mirror the key into a NORMAL property and watch THAT — an inline
    // onXChanged handler on the GSettings object itself is a fatal load error,
    // because its keys are added dynamically (unknown at QML compile time).
    // Replaces the old polled file inbox (no timer, no file:// XHR spam).
    property string pendingInbox: hsSettings.pendingAdds
    onPendingInboxChanged: _drainPendingAdds()

    /** Drain the gsettings inbox: parse appIds, add them, clear the key. */
    function _drainPendingAdds() {
        var v = hsSettings.pendingAdds || "";
        if (v === "") return;
        var raw = v.split("\n"), ids = [];
        for (var i = 0; i < raw.length; ++i) {
            var t = raw[i].replace(/^\s+|\s+$/g, "");
            if (t.length > 0) ids.push(t);
        }
        if (ids.length > 0) pages.addAppsToHome(ids);
        hsSettings.pendingAdds = "";   // re-entrant change is a no-op (guard above)
    }

    // ---- Device orientation (iOS-style: the home stays portrait — the shell
    // override locks it — and the icons/labels/widget-content re-orient instead
    // of the whole screen). The PHYSICAL device angle comes from the orientation
    // sensor (the shell's own angle is pinned to portrait). Loaded via a Loader
    // so a missing QtSensors plugin degrades gracefully (angle stays 0) instead
    // of breaking the whole home. 0 = upright portrait; 90/180/270 as it turns. ----
    property int deviceAngle: orientationProbe.item ? orientationProbe.item.angle : 0
    Loader {
        id: orientationProbe
        source: Qt.resolvedUrl("sensors/OrientationProbe.qml")
        active: root.uiEnabled
        asynchronous: true
    }

    // ---- Core modules ----
    PersistedSettings { id: persist }
    WallpaperResolver { id: wallpaper }
    AppHarvester      { id: appHarvest }

    // Widget framework: shared clock/locale source + the type registry + the
    // weather data layer (network/icon helpers, injected into weather widgets).
    LocaleClock    { id: localeClock }
    WidgetCatalog  { id: widgetCatalog }
    // ids differ from the `weatherService` / `sysInfoService` properties they
    // feed, otherwise the `xxx: xxx` bindings below self-reference (loop).
    WeatherService { id: weatherSvc }
    SysInfoService { id: sysInfoSvc }
    SysMonitorService { id: sysMonSvc }

    PageModelRegistry {
        id: pages
        persist: persist
        appHarvest: appHarvest
        catalog: widgetCatalog
        // Fixed 4-column portrait layout — identical in every orientation. The
        // home no longer reflows; rotating just re-orients items in place.
        cols: 4
        // Canonical portrait row count (for widget-footprint room). Derived from
        // the LONG screen edge so it's stable across rotation — a widget's "does
        // it fit" check doesn't change when the viewport becomes shorter.
        gridRows: Math.max(1, Math.floor(Math.max(pagesView.width, pagesView.height) / units.gu(11)))
    }

    Component.onCompleted: {
        pages.rebuildVisible();
        _drainPendingAdds();   // pick up anything queued while HomeSpike was down
    }
    Connections {
        target: appHarvest
        function onCountChanged() { pages.rebuildVisible() }
    }

    // The "Add to HomeSpike" inbox is now the reactive `hsSettings.pendingAdds`
    // key handled above — no separate poller component.

    // TileBody now lives in tiles/TileBody.qml — instantiated as
    // a Component below where the per-page and per-dock delegates live.

    // ============================================================
    // Visual stack
    // ============================================================
    // Wallpaper Image — stays visible even when HomeSpike is disabled,
    // since we replaced Lomiri's original Wallpaper element. Without
    // this, "HomeSpike off" would mean "no wallpaper" — broken.
    Image {
        anchors.fill: parent
        source: wallpaper.uri
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }
    // Dim overlay — only applied when HomeSpike's UI is shown, so it
    // doesn't darken the wallpaper when the user has HomeSpike disabled.
    Rectangle {
        anchors.fill: parent; color: "#000000"; opacity: 0.4
        visible: root.uiEnabled
    }

    // ----- Horizontal pages ListView -----
    ListView {
        id: pagesView
        visible: root.uiEnabled
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            bottom: pageDots.top
            topMargin: units.gu(5)
            bottomMargin: units.gu(1)
            leftMargin: root.leftReserve
        }
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        boundsBehavior: Flickable.StopAtBounds
        // SwipeView-style strict paging: pins the current page to the viewport
        // and, crucially, RE-ALIGNS to that same page when the viewport resizes
        // (e.g. rotating to landscape). Without this the view stays at a stale
        // contentX after a rotation — pages end up half-scrolled, icons get
        // clipped at the fold, and the page dots desync from what's shown.
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: 0
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 150
        // Snappier settle when flicking between pages.
        flickDeceleration: units.gu(800)
        interactive: !dragController.dragging
        clip: true
        model: persist.pageCount
        // Keep every page instantiated so a tile dragged across pages isn't
        // destroyed when its origin page scrolls off-screen — that would drop
        // the touch grab and strand the drag. Cheap for a handful of pages.
        cacheBuffer: width * Math.max(1, persist.pageCount)

        // The page filling the viewport (indicators + drag drop target).
        // currentIndex stays correct across resize/rotation; deriving from
        // contentX/width did not.
        readonly property int currentPage: currentIndex

        // Shared grid geometry — used for autoFill + snap rendering AND
        // by DragController to translate a drop point into (col,row).
        readonly property real gridLeftMargin: units.gu(1)
        readonly property real gridRightMargin: units.gu(1)
        // The grid is a fixed, portrait-proportioned block: its width tracks the
        // SHORTER screen edge, so it looks identical in portrait and is centered
        // (wallpaper on the sides) in landscape — nothing reflows or stretches.
        readonly property real blockW: Math.min(width, height)
        readonly property real blockOffsetX: Math.max(0, (width - blockW) / 2)
        readonly property real cellW: blockW > 0
            ? (blockW - gridLeftMargin - gridRightMargin) / pages.cols : units.gu(9)
        // Row pitch is derived from the live viewport height: fit as many
        // ~11gu rows as possible, then stretch so they divide the height
        // EXACTLY. This guarantees the bottom row is never sliced off and
        // (since rows tile the height evenly) snap neighbours never overlap —
        // no y-clamping needed. Falls back to 11gu before height is known.
        readonly property int  gridRows: Math.max(1, Math.floor(height / units.gu(11)))
        readonly property real cellH: height > 0 ? height / gridRows : units.gu(11)
        readonly property real tileW: units.gu(9)
        // Tile box fills its row band so the centred icon+label sits mid-band.
        readonly property real tileH: cellH

        delegate: Item {
            id: pageDelegate
            width: pagesView.width
            height: pagesView.height
            property int pageIndex: index

            // Long-press bare grid space toggles edit mode. Declared BEFORE the
            // tile Repeater so tiles (declared after) win presses on their own
            // area; this only fires on the empty background. No preventStealing,
            // so the ListView can still flick between pages.
            MouseArea {
                anchors.fill: parent
                enabled: root.uiEnabled
                pressAndHoldInterval: 500
                // Long-press toggles edit mode; a tap on empty space leaves it.
                onPressAndHold: root.editMode = !root.editMode
                onClicked: if (root.editMode) root.editMode = false
            }

            // One Repeater drives all three placement modes — only the
            // x/y bindings differ based on persist.placementMode.
            Repeater {
                id: tileRepeater
                model: pages.pageModels[pageDelegate.pageIndex]
                delegate: Item {
                    id: tileWrap

                    // Widgets span multiple cells and sit top-left in their
                    // footprint; apps/folders are a single centred cell.
                    readonly property bool isWidget: model.kind === "widget"
                    width: isWidget ? Math.max(1, model.widgetW) * pagesView.cellW
                                    : pagesView.tileW
                    height: isWidget ? Math.max(1, model.widgetH) * pagesView.cellH
                                     : pagesView.tileH

                    // Swell slightly when a dragged app is hovering over this
                    // tile to merge into it — the "drop here to make a folder"
                    // cue (mirrors the dock's targeting highlight).
                    scale: (dragController.dragging
                            && dragController.sourcePage === pageDelegate.pageIndex
                            && dragController.mergeTargetIndex === index) ? 1.18 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    // Read positional roles ourselves so the binding can
                    // switch source field when placementMode changes.
                    readonly property string mode: persist.placementMode
                    x: {
                        // All branches sit inside the centered, fixed-width grid
                        // block (off = blockOffsetX; cw = block cell width), so
                        // the layout is identical in portrait and just centered
                        // in landscape.
                        var off = pagesView.blockOffsetX;
                        var cw = pagesView.cellW;
                        if (tileWrap.isWidget) {
                            // Top-left placement (no per-cell centering).
                            if (mode === "free") {
                                var fx = (model.xFrac > 0.001) ? model.xFrac : 0.08;
                                return off + Math.max(0, Math.min(fx * pagesView.blockW,
                                                                  pagesView.blockW - width));
                            }
                            var wc = model.col >= 0
                                     ? Math.min(model.col, Math.max(0, pages.cols - Math.max(1, model.widgetW)))
                                     : 0;
                            return off + pagesView.gridLeftMargin + wc * cw;
                        }
                        if (mode === "autoFill") {
                            return off + pagesView.gridLeftMargin
                                 + (index % pages.cols) * cw + (cw - width) / 2;
                        }
                        if (mode === "snap") {
                            var c = model.col >= 0 ? Math.min(model.col, pages.cols - 1) : 0;
                            return off + pagesView.gridLeftMargin
                                 + c * cw + (cw - width) / 2;
                        }
                        // free — values <= 0.001 are treated as "unset" (covers
                        // both the -0.5 sentinel and stale rows truncated to 0).
                        var f = (model.xFrac > 0.001) ? model.xFrac : 0.5;
                        return off + f * pagesView.blockW - width / 2;
                    }
                    y: {
                        if (tileWrap.isWidget) {
                            if (mode === "free") {
                                var fy = (model.yFrac > 0.001) ? model.yFrac : 0.08;
                                return Math.max(0, Math.min(fy * pageDelegate.height,
                                                            pageDelegate.height - height));
                            }
                            // Clamp against the CANONICAL portrait row count so
                            // the widget keeps its saved row (and just clips below
                            // the fold in landscape) instead of jumping to row 0.
                            var wr = model.row >= 0
                                     ? Math.min(model.row, Math.max(0, pages.gridRows - Math.max(1, model.widgetH)))
                                     : 0;
                            return wr * pagesView.cellH;
                        }
                        if (mode === "autoFill") {
                            return Math.floor(index / pages.cols) * pagesView.cellH;
                        }
                        if (mode === "snap") {
                            var r = model.row >= 0 ? model.row : 0;
                            return r * pagesView.cellH;
                        }
                        // free — continuous fractional placement. Clamp so a
                        // tile dropped near the bottom isn't sliced in half by
                        // pagesView's clip (free mode permits overlap anyway).
                        var f = (model.yFrac > 0.001) ? model.yFrac : 0.5;
                        var raw = f * pageDelegate.height - height / 2;
                        return Math.max(0, Math.min(raw, pageDelegate.height - height));
                    }
                    // Smooth re-flow when models reorder or modes change.
                    // Disabled while THIS tile is being dragged so it
                    // doesn't fight the floating-icon visual.
                    Behavior on x {
                        enabled: !(dragController.dragging
                                   && dragController.sourceContainer === "grid"
                                   && dragController.sourcePage === pageDelegate.pageIndex
                                   && dragController.sourceIndex === index)
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: !(dragController.dragging
                                   && dragController.sourceContainer === "grid"
                                   && dragController.sourcePage === pageDelegate.pageIndex
                                   && dragController.sourceIndex === index)
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    opacity: (dragController.dragging
                              && dragController.sourceContainer === "grid"
                              && dragController.sourcePage === pageDelegate.pageIndex
                              && dragController.sourceIndex === index) ? 0.0 : 1.0

                    TileBody {
                        anchors.fill: parent
                        visible: !tileWrap.isWidget
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "grid"
                        showLabel: persist.gridLabels
                        contentAngle: root.deviceAngle
                        sourcePage: pageDelegate.pageIndex
                        indexInModel: index
                        editMode: root.editMode
                        controller: dragController
                        // Folder fields — inert for app rows (kind === "app").
                        kind: model.kind
                        folderId: model.folderId
                        folderName: model.folderName
                        folderIcons: {
                            if (model.kind !== "folder") return [];
                            var ids = [];
                            try { ids = JSON.parse(model.appsJson || "[]"); } catch (e) { ids = []; }
                            var icons = [];
                            for (var i = 0; i < ids.length && icons.length < 4; ++i) {
                                var info = pages.appInfo(ids[i]);
                                if (info) icons.push(info.icon);
                            }
                            return icons;
                        }
                        onRemoveRequested: (id, name) => confirmRemove.show(id, name)
                        onFolderOpenRequested: (fid) => folderOverlay.open(fid, root.editMode)
                        onFolderDeleteRequested: (fid) => pages.deleteFolder(fid)
                        onEditModeRequested: root.editMode = true
                        onLaunchRequested: (id) => root.launchRequested(id)
                    }

                    // Widget rows render through a WidgetHost, loaded only when
                    // the row is a widget. It owns the widget's drag + edit
                    // chrome and injects the shared clock + catalog.
                    Loader {
                        active: tileWrap.isWidget
                        anchors.fill: parent
                        sourceComponent: Component {
                            WidgetHost {
                                widgetId: model.widgetId
                                widgetType: model.widgetType
                                widgetVariant: model.widgetVariant
                                widgetSettings: model.widgetSettings
                                sourcePage: pageDelegate.pageIndex
                                indexInModel: index
                                editMode: root.editMode
                                controller: dragController
                                clock: localeClock
                                catalog: widgetCatalog
                                weatherService: weatherSvc
                                sysInfoService: sysInfoSvc
                                sysMonitorService: sysMonSvc
                                contentAngle: root.deviceAngle
                                onRemoveRequested: (id) => pages.removeWidget(id)
                                onSettingsRequested: (id) => widgetSettingsOverlay.open(id)
                                onEditModeRequested: root.editMode = true
                            }
                        }
                    }
                }
            }
        }
    }

    // ----- Page indicator dots -----
    Row {
        id: pageDots
        anchors {
            horizontalCenter: parent.horizontalCenter
            // Keep the dots optically centered in the content area (the area
            // to the right of the launcher panel) by shifting them by half
            // the reserved left margin.
            horizontalCenterOffset: root.leftReserve / 2
            bottom: persist.dockEnabled ? dockBar.top : parent.bottom
            bottomMargin: units.gu(2)
        }
        spacing: units.gu(1)
        visible: root.uiEnabled && persist.pageCount > 1
        Repeater {
            model: persist.pageCount
            delegate: Rectangle {
                width: units.gu(0.8); height: width
                radius: width / 2
                color: pagesView.currentPage === index ? "white" : "#88ffffff"
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ----- Dock zone (always full icon-height for hit-testing) -----
    Item {
        id: dockBar
        visible: root.uiEnabled && persist.dockEnabled
        anchors {
            bottom: parent.bottom; left: parent.left; right: parent.right
            // Smaller bottom margin sits the dock closer to the screen edge,
            // matching the iOS-style "icons near the bottom" feel.
            bottomMargin: units.gu(0.25); leftMargin: root.leftReserve + units.gu(2); rightMargin: units.gu(2)
        }
        height: root.dockHeight

        // ----- Adaptive dock item sizing -----
        // The dock's usable width (parent.width here) shrinks when Lomiri's
        // side panel pushes us right via leftReserve. Cap each tile at the
        // normal 9gu, but shrink it to share whatever width is available so
        // all dockApps stay visible — never clipped or pushed off the edge.
        readonly property real dockGap: units.gu(1)
        readonly property int  dockCount: pages.dockApps.count
        readonly property real dockItemW: dockCount > 0
            ? Math.min(units.gu(9), (width - (dockCount - 1) * dockGap) / dockCount)
            : units.gu(9)

        // Drop-target plate: transparent normally, shows a white outline
        // while a tile is being dragged onto the dock. Sized to dockBgHeight
        // (a fixed default — no longer user-adjustable) so the outline frames
        // the icon row.
        Rectangle {
            id: dockBg
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: units.gu(persist.dockBgHeight)
            radius: Math.min(units.gu(2.5), height / 2)
            color: "transparent"
            border.color: dragController.targetingDock ? "white" : "transparent"
            border.width: 1
            Behavior on color  { ColorAnimation  { duration: 120 } }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Row {
            anchors.centerIn: parent
            spacing: dockBar.dockGap
            Repeater {
                model: pages.dockApps
                delegate: Item {
                    width: dockBar.dockItemW
                    height: root.dockHeight - units.gu(2)
                    opacity: (dragController.dragging
                              && dragController.sourceContainer === "dock"
                              && dragController.sourceIndex === index) ? 0.0 : 1.0

                    TileBody {
                        anchors.fill: parent
                        // Keep the icon within the (possibly shrunk) tile so a
                        // full dock fits when the side panel narrows us.
                        iconSize: Math.min(units.gu(6), parent.width)
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "dock"
                        showLabel: persist.dockLabels
                        contentAngle: root.deviceAngle
                        indexInModel: index
                        editMode: root.editMode
                        controller: dragController
                        onRemoveRequested: (id, name) => confirmRemove.show(id, name)
                        onEditModeRequested: root.editMode = true
                        onLaunchRequested: (id) => root.launchRequested(id)
                    }
                }
            }
        }
    }

    // ============================================================
    // Edit-mode chrome
    // ============================================================
    // (No "Done" pill — tap empty space to leave edit mode.)

    // Bottom-right edit-mode button stack (top → bottom: trash, +, gear).
    // A Column so hidden buttons collapse cleanly (no gaps) — the trash hides
    // when only one page is left, the "+" hides at the page cap.
    Column {
        id: editButtons
        z: 250
        spacing: units.gu(1.5)
        anchors {
            bottom: parent.bottom; right: parent.right
            bottomMargin: persist.dockEnabled ? root.dockHeight + units.gu(2.5) : units.gu(4)
            rightMargin: units.gu(2)
        }

        DeletePageButton {
            active: root.uiEnabled && root.editMode && persist.pageCount > 1
            onTriggered: confirmDeletePage.show(pagesView.currentPage)
        }

        AddPageButton {
            active: root.uiEnabled && root.editMode && persist.pageCount < pages.maxPages
            onTriggered: {
                pages.setPageCount(persist.pageCount + 1);
                // Focus the freshly added (now last) page — deferred a tick so
                // the ListView has taken in the new page count first.
                Qt.callLater(function() {
                    pagesView.currentIndex = persist.pageCount - 1;
                });
            }
        }

        AddWidgetButton {
            active: root.uiEnabled && root.editMode
            onTriggered: widgetPicker.open()
        }

        SettingsGearButton {
            active: root.uiEnabled && root.editMode
            onTriggered: settingsOverlay.visible = true
        }
    }

    // ============================================================
    // Drag controller — owns all drag-and-drop state + visual
    // ============================================================
    DragController {
        id: dragController
        pages: pages
        persist: persist
        pagesView: pagesView
        dockBar: dockBar
        // App dropped on app → ask for a folder name, then create on confirm.
        onFolderCreateRequested: (page, targetAppId, sourceAppId) =>
            folderNameOverlay.show(page, targetAppId, sourceAppId)
    }

    // ============================================================
    // Settings + confirm-remove overlays
    // ============================================================
    SettingsOverlay {
        id: settingsOverlay
        dockEnabled: persist.dockEnabled
        placementMode: persist.placementMode
        gridLabels: persist.gridLabels
        dockLabels: persist.dockLabels
        leftReserve: root.leftReserve
        onDockToggled: (on) => pages.toggleDock(on)
        // PageModelRegistry's Connections watcher catches the persist
        // change and re-renders from the new mode's saved slot.
        onPlacementModeAdjusted: (mode) => persist.placementMode = mode
        onGridLabelsToggled: (show) => persist.gridLabels = show
        onDockLabelsToggled: (show) => persist.dockLabels = show
    }

    ConfirmRemoveOverlay {
        id: confirmRemove
        leftReserve: root.leftReserve
        onConfirmed: (appId) => pages.hideApp(appId)
    }

    ConfirmDeletePageOverlay {
        id: confirmDeletePage
        leftReserve: root.leftReserve
        onConfirmed: (pageIndex) => {
            pages.deletePage(pageIndex);
            // Land on a valid page (the shifted-in one, or the new last) once
            // the ListView has taken in the reduced page count.
            Qt.callLater(function() {
                pagesView.currentIndex = Math.min(pageIndex, persist.pageCount - 1);
            });
        }
    }

    // ----- Folder overlays -----
    // Name popup shown when an app is dropped onto another app. Confirm
    // creates the folder; cancel reverts the (un-persisted) drag with a rebuild.
    FolderNameOverlay {
        id: folderNameOverlay
        leftReserve: root.leftReserve
        onConfirmed: (page, targetAppId, sourceAppId, folderName) =>
            pages.createFolder(page, targetAppId, sourceAppId, folderName)
        onCancelled: () => pages.rebuildVisible()
    }

    // Open-folder view: launch / rename / remove / reorder / drag-out members.
    FolderOverlay {
        id: folderOverlay
        pages: pages
        dragController: dragController
        leftReserve: root.leftReserve
        onLaunchRequested: (id) => root.launchRequested(id)
    }

    // ----- Widget overlays -----
    // Picker: add a widget to the current page (snap/free only; shows a hint
    // in autoFill). Settings sheet: per-widget background / accent / size.
    WidgetPickerOverlay {
        id: widgetPicker
        catalog: widgetCatalog
        clock: localeClock
        placementMode: persist.placementMode
        leftReserve: root.leftReserve
        onChosen: (type, variant) => {
            // addWidget spills to the first page with room (adding one if
            // needed) and returns it — jump there so the new widget is in view.
            var p = pages.addWidget(pagesView.currentPage, type, variant);
            if (p >= 0) Qt.callLater(function() { pagesView.currentIndex = p; });
        }
    }

    WidgetSettingsOverlay {
        id: widgetSettingsOverlay
        pages: pages
        catalog: widgetCatalog
        weatherService: weatherSvc
        photoPicker: photoPickerOverlay
        leftReserve: root.leftReserve
    }

    // Photo browser opened from a Photo widget's settings (id differs from the
    // `photoPicker` property it feeds, to avoid a self-referencing binding).
    PhotoPickerOverlay {
        id: photoPickerOverlay
        leftReserve: root.leftReserve
    }
}
