import QtQuick 2.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.0
import Lomiri.Components 1.3
import GSettings 1.0
import AccountsService 0.1
import Lomiri.Launcher 0.1
import Utils 0.1

Window {
    id: root
    visible: true
    visibility: Window.Maximized
    color: "#1d2540"
    title: "Home Spike"

    // ============================================================
    // State
    // ============================================================
    property bool editMode: false
    readonly property int dockMax: 5
    readonly property int maxPages: 5
    readonly property real dockHeight: units.gu(12)

    Settings {
        id: persist
        category: "homeSpike"
        // pageData is a JSON array of arrays of appIds, one inner array per page.
        property string pageData:     '[[]]'
        property int    pageCount:    1
        property string hiddenAppIds: "[]"
        property string dockOrder:    "[]"
        property bool   dockEnabled:  false
    }
    function _readJson(s, fallback) { try { return JSON.parse(s); } catch (e) { return fallback; } }
    function _writeJson(v) { return JSON.stringify(v); }

    GSettings {
        id: shellSettings
        schema.id: "com.lomiri.Shell"
    }
    function _toUri(p) {
        if (!p) return "";
        return p.indexOf("://") === -1 ? "file://" + p : p;
    }
    readonly property string wallpaperUri:
        _toUri(AccountsService.backgroundFile) ||
        shellSettings.backgroundPictureUri ||
        "file:///usr/share/backgrounds/lomiri-default-background.png"

    AppDrawerModel { id: appDrawerModel }
    AppDrawerProxyModel {
        id: sortedApps
        source: appDrawerModel
        sortBy: AppDrawerProxyModel.SortByAToZ
    }

    // Per-page ListModels (fixed pool up to maxPages)
    ListModel { id: page0 }
    ListModel { id: page1 }
    ListModel { id: page2 }
    ListModel { id: page3 }
    ListModel { id: page4 }
    property var pageModels: [page0, page1, page2, page3, page4]

    ListModel { id: dockApps }

    Repeater {
        id: appHarvest
        model: sortedApps
        Item {
            property string appId: model.appId || ""
            property string name:  model.name  || ""
            property string icon:  model.icon  || ""
        }
    }

    function rebuildVisible() {
        var pageData = _readJson(persist.pageData, [[]]);
        if (!Array.isArray(pageData) || pageData.length === 0) pageData = [[]];
        var pc = Math.min(Math.max(1, persist.pageCount), maxPages);
        // Pad/truncate pageData to current pageCount
        while (pageData.length < pc) pageData.push([]);
        if (pageData.length > pc) {
            // Merge overflow into last kept page
            var overflow = [];
            for (var z = pc; z < pageData.length; ++z) overflow = overflow.concat(pageData[z]);
            pageData = pageData.slice(0, pc);
            pageData[pc - 1] = pageData[pc - 1].concat(overflow);
        }

        var hidden  = _readJson(persist.hiddenAppIds, []);
        var dockIds = persist.dockEnabled ? _readJson(persist.dockOrder, []) : [];
        var hiddenSet = {}, dockSet = {};
        for (var i = 0; i < hidden.length; ++i)  hiddenSet[hidden[i]] = true;
        for (var d = 0; d < dockIds.length; ++d) dockSet[dockIds[d]] = true;

        var source = {}, sourceIds = [];
        for (var j = 0; j < appHarvest.count; ++j) {
            var it = appHarvest.itemAt(j);
            if (!it || !it.appId) continue;
            source[it.appId] = { appId: it.appId, name: it.name, icon: it.icon };
            sourceIds.push(it.appId);
        }

        // Rebuild dock
        dockApps.clear();
        var newDock = [];
        for (var dx = 0; dx < dockIds.length && newDock.length < dockMax; ++dx) {
            var did = dockIds[dx];
            if (hiddenSet[did]) continue;
            if (!source[did]) continue;
            dockApps.append(source[did]);
            newDock.push(did);
            source[did]._used = true;
        }

        // Rebuild each page from pageData (skip hidden, skip dock, skip uninstalled)
        var newPages = [];
        for (var p = 0; p < pc; ++p) {
            pageModels[p].clear();
            var newPage = [];
            var ids = pageData[p] || [];
            for (var k = 0; k < ids.length; ++k) {
                var id = ids[k];
                if (hiddenSet[id]) continue;
                if (dockSet[id])   continue;
                if (!source[id])   continue;
                if (source[id]._used) continue;
                pageModels[p].append(source[id]);
                newPage.push(id);
                source[id]._used = true;
            }
            newPages.push(newPage);
        }

        // Any apps not yet placed (new installs, or unaccounted) → last page
        for (var m = 0; m < sourceIds.length; ++m) {
            var sid = sourceIds[m];
            if (source[sid]._used) continue;
            if (hiddenSet[sid])    continue;
            pageModels[pc - 1].append(source[sid]);
            newPages[pc - 1].push(sid);
        }

        // Clear unused page models
        for (var px = pc; px < maxPages; ++px) pageModels[px].clear();

        // NOTE: do NOT persist here. rebuildVisible runs many times during
        // app startup (appHarvest populates incrementally), and each early
        // call has partial data. Writing partial state back to persist
        // would destroy the saved layout. Persistence only happens on
        // explicit user actions: persistOrder() (drag end), hideApp(),
        // toggleDock(), setPageCount().
    }

    function hideApp(appId) {
        var hidden = _readJson(persist.hiddenAppIds, []);
        if (hidden.indexOf(appId) === -1) {
            hidden.push(appId);
            persist.hiddenAppIds = _writeJson(hidden);
        }
        rebuildVisible();
    }

    function persistOrder() {
        var pages = [];
        for (var p = 0; p < persist.pageCount; ++p) {
            var ids = [];
            for (var i = 0; i < pageModels[p].count; ++i) ids.push(pageModels[p].get(i).appId);
            pages.push(ids);
        }
        persist.pageData = _writeJson(pages);

        var dock = [];
        for (var j = 0; j < dockApps.count; ++j) dock.push(dockApps.get(j).appId);
        persist.dockOrder = _writeJson(dock);
    }

    function toggleDock(enabled) {
        if (enabled === persist.dockEnabled) return;
        if (!enabled) {
            // Merge dock items into the last page, then clear dock
            var pages = _readJson(persist.pageData, [[]]);
            var dock  = _readJson(persist.dockOrder, []);
            if (pages.length === 0) pages = [[]];
            for (var i = 0; i < dock.length; ++i) {
                if (pages[pages.length - 1].indexOf(dock[i]) === -1) pages[pages.length - 1].push(dock[i]);
            }
            persist.pageData = _writeJson(pages);
            persist.dockOrder = "[]";
        }
        persist.dockEnabled = enabled;
        rebuildVisible();
    }

    function setPageCount(n) {
        n = Math.min(Math.max(1, n), maxPages);
        if (n === persist.pageCount) return;
        persist.pageCount = n;
        rebuildVisible();
    }

    Component.onCompleted: {
        rebuildVisible();
        processPendingAdds();
    }
    Connections {
        target: appHarvest
        function onCountChanged() { rebuildVisible() }
    }

    // ============================================================
    // Cross-process inbox: the patched Lomiri Drawer.qml writes appIds
    // to this file on long-press. We poll it, add each new appId to
    // the last page, then truncate the file.
    // ============================================================
    readonly property string _pendingAddsPath: "/home/phablet/.config/home-spike/pending-adds.txt"

    Timer {
        id: pendingAddsPoller
        interval: 1500
        repeat: true
        running: true
        onTriggered: processPendingAdds()
    }

    function processPendingAdds() {
        var content = "";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + _pendingAddsPath, false);
        try {
            xhr.send();
            content = xhr.responseText || "";
        } catch (e) {
            return;  // file doesn't exist yet — nothing to do
        }
        if (!content) return;

        var raw = content.split("\n");
        var lines = [];
        for (var i = 0; i < raw.length; ++i) {
            var s = raw[i].replace(/^\s+|\s+$/g, "");
            if (s.length > 0) lines.push(s);
        }
        if (lines.length === 0) { _truncateInbox(); return; }

        // Index what's currently placed
        var placed = {};
        for (var p = 0; p < persist.pageCount; ++p) {
            for (var ii = 0; ii < pageModels[p].count; ++ii) {
                placed[pageModels[p].get(ii).appId] = true;
            }
        }
        for (var dd = 0; dd < dockApps.count; ++dd) {
            placed[dockApps.get(dd).appId] = true;
        }

        var hidden = _readJson(persist.hiddenAppIds, []);
        var hiddenSet = {};
        for (var h = 0; h < hidden.length; ++h) hiddenSet[hidden[h]] = true;

        var changed = false;
        for (var k = 0; k < lines.length; ++k) {
            var appId = lines[k];

            // Un-hide if previously removed
            if (hiddenSet[appId]) {
                var idx = hidden.indexOf(appId);
                if (idx >= 0) hidden.splice(idx, 1);
                delete hiddenSet[appId];
                changed = true;
            }
            // Skip if already on a page or in the dock
            if (placed[appId]) continue;
            // Find the app in the source set
            var src = null;
            for (var j = 0; j < appHarvest.count; ++j) {
                var it = appHarvest.itemAt(j);
                if (it && it.appId === appId) {
                    src = { appId: it.appId, name: it.name, icon: it.icon };
                    break;
                }
            }
            if (!src) continue;
            // Append to last page
            pageModels[persist.pageCount - 1].append(src);
            placed[appId] = true;
            changed = true;
        }

        if (changed) {
            persist.hiddenAppIds = _writeJson(hidden);
            persistOrder();
        }
        _truncateInbox();
    }

    function _truncateInbox() {
        var xhr = new XMLHttpRequest();
        xhr.open("PUT", "file://" + _pendingAddsPath, false);
        try { xhr.send(""); } catch (e) {}
    }

    // ============================================================
    // Reusable tile body
    // ============================================================
    component TileBody : Item {
        id: body
        property string appId: ""
        property string appName: ""
        property string iconSrc: ""
        property string container: "grid"  // "grid" or "dock"
        property int sourcePage: -1        // grid only
        property int indexInModel: -1

        // tileMouse FIRST so Column subtree (with X remove badge MouseArea)
        // hit-tests above it. Touches that miss the badge pass through Column
        // (no handler) to tileMouse below.
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            pressAndHoldInterval: 400
            preventStealing: root.editMode

            property real pressX: 0
            property real pressY: 0
            property bool dragStarted: false
            readonly property real dragThreshold: units.gu(2)

            onClicked: {
                if (root.editMode) return;
                Qt.openUrlExternally("application:///" + body.appId + ".desktop");
            }
            onPressAndHold: {
                if (!root.editMode) { root.editMode = true; return; }
            }
            onPressed: {
                pressX = mouseX;
                pressY = mouseY;
                dragStarted = false;
                if (dragLayer.dragging) {
                    edgeFlipTimer.stop();
                    dockLayer.targetActive = false;
                    dragLayer.sourceIndex = -1;
                    dragLayer.sourcePage = -1;
                    dragLayer.sourceContainer = "";
                    dragLayer.sourceAppId = "";
                }
            }
            onPositionChanged: {
                if (!root.editMode) return;
                var dx = mouseX - pressX;
                var dy = mouseY - pressY;
                if (!dragStarted) {
                    if (Math.sqrt(dx*dx + dy*dy) < dragThreshold) return;
                    dragStarted = true;
                    var sp = mapToItem(dragLayer, mouseX, mouseY);
                    dragLayer.startDrag(body.container, body.sourcePage, body.indexInModel,
                                        body.appId, body.appName, body.iconSrc, sp.x, sp.y);
                }
                var pt = mapToItem(dragLayer, mouseX, mouseY);
                dragLayer.moveDrag(pt.x, pt.y);
            }
            onReleased: {
                if (dragLayer.dragging) dragLayer.endDrag();
                dragStarted = false;
            }
            onCanceled: {
                if (dragLayer.dragging) dragLayer.endDrag();
                dragStarted = false;
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: units.gu(0.5)

            Item {
                id: iconHolder
                width: units.gu(6)
                height: 7.5 / 8 * width
                anchors.horizontalCenter: parent.horizontalCenter

                LomiriShape {
                    id: shape
                    anchors.fill: parent
                    radius: "medium"
                    borderSource: "undefined"
                    sourceFillMode: LomiriShape.PreserveAspectCrop
                    source: Image {
                        asynchronous: true
                        sourceSize.width: shape.width
                        source: body.iconSrc
                    }
                    SequentialAnimation on rotation {
                        running: root.editMode && !dragLayer.dragging
                        loops: Animation.Infinite
                        NumberAnimation { from: -1.5; to: 1.5; duration: 120 }
                        NumberAnimation { from: 1.5; to: -1.5; duration: 120 }
                    }
                    Behavior on rotation { NumberAnimation { duration: 80 } }
                }

                Rectangle {  // remove badge
                    visible: root.editMode
                    anchors {
                        top: iconHolder.top; horizontalCenter: iconHolder.left
                        topMargin: -units.gu(0.5)
                    }
                    width: units.gu(2.5); height: width
                    radius: width / 2
                    color: "white"
                    border.color: "#202840"; border.width: 1
                    z: 20
                    Text {
                        anchors.centerIn: parent
                        text: "×"; color: "#202840"
                        font.pixelSize: parent.height * 0.8; font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -units.gu(0.5)
                        onClicked: {
                            confirmRemove.appId = body.appId;
                            confirmRemove.appName = body.appName;
                            confirmRemove.visible = true;
                        }
                    }
                }
            }

            Label {
                text: body.appName
                width: units.gu(9)
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
                fontSize: "x-small"
                color: "white"
                wrapMode: Text.WordWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }

    // ============================================================
    // Visual stack
    // ============================================================
    Image {
        anchors.fill: parent
        source: root.wallpaperUri
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.4 }

    // ----- Horizontal pages ListView -----
    ListView {
        id: pagesView
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            bottom: pageDots.top
            topMargin: units.gu(5)
            bottomMargin: units.gu(1)
        }
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 250
        interactive: !dragLayer.dragging
        clip: true
        model: persist.pageCount

        // Index of currently centered page (for indicators + drag drop target)
        property int currentPage: Math.round(contentX / Math.max(1, width))

        delegate: Item {
            width: pagesView.width
            height: pagesView.height
            property int pageIndex: index

            GridView {
                anchors {
                    fill: parent
                    leftMargin: units.gu(1); rightMargin: units.gu(1)
                }
                cellWidth: width / 4
                cellHeight: units.gu(11)
                model: root.pageModels[pageIndex]
                interactive: !dragLayer.dragging
                clip: true

                move:          Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }
                moveDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }

                delegate: Item {
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    opacity: (dragLayer.dragging
                              && dragLayer.sourceContainer === "grid"
                              && dragLayer.sourcePage === pageIndex
                              && dragLayer.sourceIndex === index) ? 0.0 : 1.0

                    TileBody {
                        anchors.fill: parent
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "grid"
                        sourcePage: pageIndex
                        indexInModel: index
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
            bottom: persist.dockEnabled ? dockBar.top : parent.bottom
            bottomMargin: units.gu(1.5)
        }
        spacing: units.gu(1)
        visible: persist.pageCount > 1
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

    // ----- Dock -----
    Rectangle {
        id: dockBar
        visible: persist.dockEnabled
        anchors {
            bottom: parent.bottom; left: parent.left; right: parent.right
            bottomMargin: units.gu(1.5); leftMargin: units.gu(2); rightMargin: units.gu(2)
        }
        height: root.dockHeight
        radius: units.gu(2.5)
        color: dockLayer.targetActive ? "#55ffffff" : "#33ffffff"
        border.color: dockLayer.targetActive ? "white" : "transparent"
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            anchors.centerIn: parent
            spacing: units.gu(1)
            Repeater {
                model: dockApps
                delegate: Item {
                    width: units.gu(9)
                    height: root.dockHeight - units.gu(2)
                    opacity: (dragLayer.dragging
                              && dragLayer.sourceContainer === "dock"
                              && dragLayer.sourceIndex === index) ? 0.0 : 1.0

                    TileBody {
                        anchors.fill: parent
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "dock"
                        indexInModel: index
                    }
                }
            }
        }

        Item { id: dockLayer; property bool targetActive: false; anchors.fill: parent }
    }

    // ============================================================
    // Edit-mode chrome
    // ============================================================
    Rectangle {  // Done pill (top-right)
        visible: root.editMode
        z: 200
        anchors {
            top: parent.top; right: parent.right
            topMargin: units.gu(4); rightMargin: units.gu(2)
        }
        width: doneLabel.width + units.gu(3)
        height: units.gu(4)
        radius: height / 2
        color: "#3d5af1"
        Label { id: doneLabel; anchors.centerIn: parent; text: "Done"; color: "white"; font.bold: true }
        MouseArea { anchors.fill: parent; onClicked: root.editMode = false }
    }

    Rectangle {  // Settings gear (bottom-right)
        visible: root.editMode
        z: 200
        anchors {
            bottom: parent.bottom; right: parent.right
            bottomMargin: persist.dockEnabled ? root.dockHeight + units.gu(2.5) : units.gu(4)
            rightMargin: units.gu(2)
        }
        width: units.gu(5); height: width
        radius: width / 2
        color: "#3d5af1"
        Text {
            anchors.centerIn: parent
            text: "⚙"; color: "white"
            font.pixelSize: parent.height * 0.55
        }
        MouseArea { anchors.fill: parent; onClicked: settingsOverlay.visible = true }
    }

    // ============================================================
    // Drag layer
    // ============================================================
    Item {
        id: dragLayer
        anchors.fill: parent
        z: 300

        property bool dragging: sourceIndex >= 0
        property int sourceIndex: -1
        property int sourcePage: -1
        property string sourceContainer: ""
        property string sourceAppId: ""
        property string sourceName: ""
        property string sourceIcon: ""

        // Timer that flips pages when the drag hovers near the left/right edge.
        // Also drags the in-flight icon to the new page so cross-page moves
        // happen ONLY here, not as a side-effect of moveDrag.
        Timer {
            id: edgeFlipTimer
            interval: 600
            property int direction: 0  // -1 left, +1 right
            onTriggered: {
                var target = pagesView.currentPage + direction;
                if (target < 0 || target >= persist.pageCount) return;

                // Carry the dragged icon to the new page
                if (dragLayer.dragging && dragLayer.sourceContainer === "grid"
                    && dragLayer.sourcePage !== target
                    && dragLayer.sourcePage >= 0
                    && dragLayer.sourceIndex >= 0
                    && dragLayer.sourceIndex < pageModels[dragLayer.sourcePage].count) {
                    var item = {
                        appId: dragLayer.sourceAppId,
                        name:  dragLayer.sourceName,
                        icon:  dragLayer.sourceIcon
                    };
                    pageModels[dragLayer.sourcePage].remove(dragLayer.sourceIndex, 1);
                    pageModels[target].append(item);
                    dragLayer.sourcePage = target;
                    dragLayer.sourceIndex = pageModels[target].count - 1;
                }

                pagesView.positionViewAtIndex(target, ListView.Beginning);
            }
        }

        // Look up which model actually contains an appId. Authoritative
        // — overrides whatever the press delegate claims, since cached /
        // off-screen delegates can lie about page index after model edits.
        function _findAppLocation(appId) {
            for (var p = 0; p < persist.pageCount; ++p) {
                var m = pageModels[p];
                for (var i = 0; i < m.count; ++i) {
                    if (m.get(i).appId === appId) return { container: "grid", page: p, index: i };
                }
            }
            for (var d = 0; d < dockApps.count; ++d) {
                if (dockApps.get(d).appId === appId) return { container: "dock", page: -1, index: d };
            }
            return null;
        }

        function startDrag(container, page, idx, appId, name, icon, x, y) {
            // Authoritative: ignore the delegate's claimed (container, page, idx)
            // and locate the appId by scanning the actual models. This sidesteps
            // every "stale delegate" / "wrong currentPage" race.
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
            floatingIcon.x = x - floatingIcon.width / 2;
            floatingIcon.y = y - floatingIcon.height / 2;
        }

        function moveDrag(x, y) {
            // Bail if we're not actually dragging (orphan / cleared state).
            if (!dragging || sourceContainer === "") return;

            // Re-locate source by appId — its index may have shifted because
            // of intervening model mutations (other drags, reorders, etc.).
            var foundIdx = -1;
            if (sourceContainer === "grid") {
                if (sourcePage < 0 || sourcePage >= persist.pageCount) return;
                var m = pageModels[sourcePage];
                for (var i = 0; i < m.count; ++i) {
                    if (m.get(i).appId === sourceAppId) { foundIdx = i; break; }
                }
            } else if (sourceContainer === "dock") {
                for (var j = 0; j < dockApps.count; ++j) {
                    if (dockApps.get(j).appId === sourceAppId) { foundIdx = j; break; }
                }
            }
            if (foundIdx < 0) {
                // Source vanished. Bail without inserting.
                endDrag();
                return;
            }
            sourceIndex = foundIdx;

            floatingIcon.x = x - floatingIcon.width / 2;
            floatingIcon.y = y - floatingIcon.height / 2;

            // Edge-flip detection
            var edgeMargin = units.gu(3);
            var newDir = 0;
            if (x < edgeMargin) newDir = -1;
            else if (x > width - edgeMargin) newDir = +1;
            if (newDir !== edgeFlipTimer.direction) {
                edgeFlipTimer.stop();
                edgeFlipTimer.direction = newDir;
                if (newDir !== 0) edgeFlipTimer.start();
            }

            // Dock vs grid detection
            var overDock = false;
            var dp = { x: 0, y: 0 };
            if (persist.dockEnabled) {
                dp = dragLayer.mapToItem(dockBar, x, y);
                overDock = dp.x >= 0 && dp.x <= dockBar.width && dp.y >= 0 && dp.y <= dockBar.height;
            }
            dockLayer.targetActive = overDock && sourceContainer !== "dock";

            if (overDock) {
                if (sourceContainer === "dock") {
                    var dockCellW = units.gu(10);
                    var targetIdx = Math.floor(dp.x / dockCellW);
                    if (targetIdx < 0) targetIdx = 0;
                    if (targetIdx >= dockApps.count) targetIdx = dockApps.count - 1;
                    if (targetIdx !== sourceIndex) {
                        dockApps.move(sourceIndex, targetIdx, 1);
                        sourceIndex = targetIdx;
                    }
                } else if (sourceContainer === "grid") {
                    if (dockApps.count < root.dockMax) {
                        pageModels[sourcePage].remove(sourceIndex, 1);
                        dockApps.append({ appId: sourceAppId, name: sourceName, icon: sourceIcon });
                        sourceContainer = "dock";
                        sourcePage = -1;
                        sourceIndex = dockApps.count - 1;
                    }
                }
            } else {
                // Target = grid. Same-page reorder ONLY. Cross-page transitions
                // happen via edgeFlipTimer (the user's explicit intent).
                var leftMargin = units.gu(1);
                var topMargin  = units.gu(5);
                var gridWidth  = pagesView.width - 2 * leftMargin;
                var cellH      = units.gu(11);
                var cols       = 4;
                var cellW      = gridWidth / cols;

                var pageX = x - leftMargin;
                var pageY = y - topMargin;
                if (pageY < 0) return;
                if (pageX < 0) pageX = 0;
                if (pageX >= gridWidth) pageX = gridWidth - 1;

                var col = Math.floor(pageX / cellW);
                var row = Math.floor(pageY / cellH);
                if (col < 0) col = 0; if (col >= cols) col = cols - 1;
                var target = row * cols + col;

                if (sourceContainer === "dock") {
                    // Dock → grid: drop on current page, appended at end (drop
                    // happens on release; here we just transition the source).
                    var dropPage = pagesView.currentPage;
                    if (dropPage < 0 || dropPage >= persist.pageCount) return;
                    var dockedItem = { appId: sourceAppId, name: sourceName, icon: sourceIcon };
                    dockApps.remove(sourceIndex, 1);
                    pageModels[dropPage].append(dockedItem);
                    sourceContainer = "grid";
                    sourcePage = dropPage;
                    sourceIndex = pageModels[dropPage].count - 1;
                    return;
                }

                // Grid-source, same-page reorder
                var pageModel = pageModels[sourcePage];
                if (target < 0) target = 0;
                if (target >= pageModel.count) target = pageModel.count - 1;
                if (target !== sourceIndex) {
                    pageModel.move(sourceIndex, target, 1);
                    sourceIndex = target;
                }
            }
        }

        function endDrag() {
            edgeFlipTimer.stop();
            edgeFlipTimer.direction = 0;
            dockLayer.targetActive = false;
            if (sourceIndex >= 0) root.persistOrder();
            sourceIndex = -1; sourcePage = -1; sourceContainer = "";
        }

        LomiriShape {
            id: floatingIcon
            visible: dragLayer.dragging
            width: units.gu(6) * 1.15
            height: 7.5 / 8 * width
            radius: "medium"
            borderSource: "undefined"
            sourceFillMode: LomiriShape.PreserveAspectCrop
            opacity: 0.92
            source: Image {
                asynchronous: true
                sourceSize.width: floatingIcon.width
                source: dragLayer.sourceIcon
            }
        }
    }

    // ============================================================
    // Settings overlay
    // ============================================================
    Rectangle {
        id: settingsOverlay
        anchors.fill: parent
        z: 900
        visible: false
        color: "#aa000000"

        MouseArea { anchors.fill: parent; onClicked: settingsOverlay.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.85, units.gu(50))
            height: settingsCol.height + units.gu(4)
            radius: units.gu(2)
            color: "#262d4d"

            MouseArea { anchors.fill: parent }

            Column {
                id: settingsCol
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: units.gu(2); rightMargin: units.gu(2)
                }
                spacing: units.gu(2)

                Label {
                    text: "HomeSpike Settings"
                    color: "white"; font.bold: true; fontSize: "large"
                }

                // ---- Pages stepper ----
                Row {
                    width: parent.width
                    spacing: units.gu(2)
                    Column {
                        width: parent.width - pagesStepper.width - units.gu(2)
                        Label { text: "Pages"; color: "white" }
                        Label {
                            text: "Number of swipeable home screens (1–" + root.maxPages + "). When reduced, extra pages merge into the last."
                            color: "#9fa9c0"; fontSize: "small"
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Row {
                        id: pagesStepper
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.gu(0.5)
                        Button {
                            text: "−"; width: units.gu(4)
                            onClicked: root.setPageCount(persist.pageCount - 1)
                            enabled: persist.pageCount > 1
                        }
                        Label {
                            text: persist.pageCount
                            color: "white"; font.bold: true
                            width: units.gu(3)
                            horizontalAlignment: Text.AlignHCenter
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Button {
                            text: "+"; width: units.gu(4)
                            onClicked: root.setPageCount(persist.pageCount + 1)
                            enabled: persist.pageCount < root.maxPages
                        }
                    }
                }

                // ---- Dock toggle ----
                Row {
                    width: parent.width
                    spacing: units.gu(2)
                    Column {
                        width: parent.width - dockSwitch.width - units.gu(2)
                        Label { text: "Bottom dock"; color: "white" }
                        Label {
                            text: "Up to 5 apps. Drag any tile to the dock. Turning this off returns dock apps to the last page."
                            color: "#9fa9c0"; fontSize: "small"
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Switch {
                        id: dockSwitch
                        checked: persist.dockEnabled
                        anchors.verticalCenter: parent.verticalCenter
                        onCheckedChanged: if (checked !== persist.dockEnabled) root.toggleDock(checked)
                    }
                }

                Row {
                    anchors.right: parent.right
                    Button {
                        text: "Done"; color: "#3d5af1"
                        onClicked: settingsOverlay.visible = false
                    }
                }
            }
        }
    }

    // ============================================================
    // Confirm-remove overlay
    // ============================================================
    Rectangle {
        id: confirmRemove
        anchors.fill: parent
        z: 1000
        visible: false
        color: "#aa000000"

        property string appId: ""
        property string appName: ""

        MouseArea { anchors.fill: parent; onClicked: confirmRemove.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.85, units.gu(50))
            height: cardCol.height + units.gu(4)
            radius: units.gu(2)
            color: "#262d4d"

            MouseArea { anchors.fill: parent }

            Column {
                id: cardCol
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: units.gu(2); rightMargin: units.gu(2)
                }
                spacing: units.gu(2)

                Label {
                    text: "Remove from home?"
                    color: "white"; font.bold: true; fontSize: "large"
                    width: parent.width; wrapMode: Text.WordWrap
                }
                Label {
                    text: '"' + confirmRemove.appName + '" will be hidden from HomeSpike. It stays installed; you can still launch it from the swipe-left drawer.'
                    color: "#cfd6e4"; width: parent.width; wrapMode: Text.WordWrap
                }
                Row {
                    anchors.right: parent.right
                    spacing: units.gu(1)
                    Button { text: "Cancel"; onClicked: confirmRemove.visible = false }
                    Button {
                        text: "Remove"; color: "#e94560"
                        onClicked: {
                            root.hideApp(confirmRemove.appId);
                            confirmRemove.visible = false;
                        }
                    }
                }
            }
        }
    }
}
