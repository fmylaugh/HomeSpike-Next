/**
 * @file FolderOverlay
 * @description Full-screen modal that opens a folder: a centered, editable name
 *   above a translucent card holding the member apps. Tap outside the card to
 *   close. Tap an app to launch it; long-press to enter edit mode, then drag a
 *   member to rearrange it within the folder, or drag it past the card edge to
 *   pull it out onto the home screen. The "×" badge removes an app (returns it
 *   to the grid); the folder auto-dissolves to a normal icon at one member and
 *   this overlay closes itself when that happens.
 *
 *   Drag is handled by a self-contained `folderDrag` controller that implements
 *   the same interface TileBody already calls, so member tiles reuse TileBody's
 *   gesture detection unchanged. Drag-OUT works by hiding the chrome with
 *   `card.opacity = 0` (NOT visible:false) so the dragging tile's MouseArea
 *   keeps its touch grab while the home grid shows through; on release outside
 *   the app is removed from the folder and dropped on the grid at that point.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3
import "../tiles"

Rectangle {
    id: root

    /** PageModelRegistry — folder reads + mutations route through it. */
    property var pages: null

    /** Global DragController — reused for grid placement on drag-out. */
    property var dragController: null

    /** Px width of the Lomiri launcher panel overlapping us. */
    property real leftReserve: 0

    /** The folder currently shown. */
    property string folderId: ""

    /** Local edit mode — long-press a member to toggle on; reveals the "×". */
    property bool editMode: false

    /** True while a member is being dragged outside the card: the chrome fades
     *  (card.opacity → 0, scrim transparent) so the home grid shows through. */
    property bool dragOut: false

    /** Re-emitted up to Stage so the home overlay drops on launch. */
    signal launchRequested(string appId)

    anchors.fill: parent
    z: 1050
    visible: false
    color: dragOut ? "transparent" : "#cc000000"
    Behavior on color { ColorAnimation { duration: 120 } }

    // Live member tiles, rebuilt from the model by refresh().
    ListModel { id: memberModel }

    function open(fid, editing) {
        folderId = fid;
        // Opening from home edit mode lands straight in edit mode so the user
        // can rearrange/remove without a fresh long-press.
        editMode = editing === true;
        dragOut = false;
        nameField.text = pages ? pages.folderNameOf(fid) : "";
        refresh();
        visible = true;
    }

    function close() {
        _commitName();
        editMode = false;
        dragOut = false;
        visible = false;
    }

    function _commitName() {
        if (!pages || folderId === "") return;
        var n = nameField.text.trim();
        if (n.length > 0 && n !== pages.folderNameOf(folderId)) {
            pages.renameFolder(folderId, n);
        }
    }

    // Repopulate from the folder's current members; close if it's gone (it
    // dissolved to a single app, or emptied).
    function refresh() {
        memberModel.clear();
        if (!pages || !pages.hasFolder(folderId)) {
            if (visible) { visible = false; editMode = false; dragOut = false; }
            return;
        }
        var ids = pages.folderApps(folderId);
        for (var i = 0; i < ids.length; ++i) {
            var info = pages.appInfo(ids[i]);
            if (!info) continue;  // uninstalled — skip
            memberModel.append({ appId: info.appId, name: info.name, icon: info.icon });
        }
    }

    // True if a folderDrag-local point falls within the card.
    function cardContains(x, y) {
        var pt = folderDrag.mapToItem(card, x, y);
        return pt.x >= 0 && pt.x <= card.width && pt.y >= 0 && pt.y <= card.height;
    }

    // folderDrag-local point → member index within the Flow (for reordering).
    function memberIndexAt(x, y) {
        if (memberModel.count === 0) return 0;
        var pt = folderDrag.mapToItem(memberFlow, x, y);
        var cellW = units.gu(9) + memberFlow.spacing;
        var cellH = units.gu(11) + memberFlow.spacing;
        var cols = Math.max(1, Math.floor((memberFlow.width + memberFlow.spacing) / cellW));
        var col = Math.floor(Math.max(0, pt.x) / cellW);
        if (col >= cols) col = cols - 1;
        var r = Math.floor(Math.max(0, pt.y) / cellH);
        var idx = r * cols + col;
        if (idx < 0) idx = 0;
        if (idx >= memberModel.count) idx = memberModel.count - 1;
        return idx;
    }

    // Tap outside the card closes (committing the name).
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // Folder name — centered above the card. Plain text that becomes editable
    // when tapped; commits on Enter or when it loses focus.
    TextInput {
        id: nameField
        anchors.bottom: card.top
        anchors.bottomMargin: units.gu(1.5)
        anchors.horizontalCenter: card.horizontalCenter
        width: card.width
        horizontalAlignment: TextInput.AlignHCenter
        color: "white"
        font.bold: true
        font.pixelSize: units.gu(2.4)
        inputMethodHints: Qt.ImhNoPredictiveText
        selectByMouse: true
        opacity: root.dragOut ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        onAccepted: { root._commitName(); focus = false; }
        onActiveFocusChanged: if (!activeFocus) root._commitName()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.9, units.gu(48))
        height: memberFlow.height + units.gu(4)
        radius: units.gu(2)
        // Blue accent, semi-transparent so the wallpaper shows through.
        color: "#cc262d4d"
        // Fade out (but stay visible:true so the dragging tile keeps its grab)
        // while a member is being pulled out onto the grid.
        opacity: root.dragOut ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }

        // Swallow taps on the card background; a tap on empty space exits edit.
        MouseArea {
            anchors.fill: parent
            onClicked: root.editMode = false
        }

        // Member apps — wraps to multiple rows.
        Flow {
            id: memberFlow
            anchors.centerIn: parent
            width: parent.width - units.gu(4)
            spacing: units.gu(1)
            Repeater {
                model: memberModel
                delegate: Item {
                    width: units.gu(9)
                    height: units.gu(11)
                    // The dragged member rides the floating icon instead.
                    opacity: folderDrag.draggingIndex === index ? 0 : 1
                    TileBody {
                        anchors.fill: parent
                        appId: model.appId
                        appName: model.name
                        iconSrc: model.icon
                        container: "folder"
                        indexInModel: index
                        controller: folderDrag
                        editMode: root.editMode
                        onEditModeRequested: root.editMode = true
                        onLaunchRequested: (id) => { root.launchRequested(id); root.close(); }
                        onRemoveRequested: (id, name) => {
                            pages.removeAppFromFolder(root.folderId, id);
                            root.refresh();
                        }
                    }
                }
            }
        }
    }

    // ============================================================
    // Folder drag controller — implements the interface TileBody calls.
    // Reorders members live while inside the card; pulls a member out to the
    // home grid when released outside.
    // ============================================================
    Item {
        id: folderDrag
        anchors.fill: parent

        property int    draggingIndex: -1
        property string dragAppId: ""
        property string dragName:  ""
        property string dragIcon:  ""
        property real   lastX: 0
        property real   lastY: 0
        readonly property bool dragging: draggingIndex >= 0

        function abort() {
            draggingIndex = -1;
            root.dragOut = false;
        }

        function startDrag(container, page, idx, key, name, icon, x, y) {
            draggingIndex = idx;
            dragAppId = key;     // folder members are apps → key === appId
            dragName  = name;
            dragIcon  = icon;
            lastX = x; lastY = y;
            floatIcon.x = x - floatIcon.width / 2;
            floatIcon.y = y - floatIcon.height / 2;
            root.dragOut = false;
        }

        function moveDrag(x, y) {
            if (draggingIndex < 0) return;
            lastX = x; lastY = y;
            floatIcon.x = x - floatIcon.width / 2;
            floatIcon.y = y - floatIcon.height / 2;

            if (root.cardContains(x, y)) {
                root.dragOut = false;
                var ti = root.memberIndexAt(x, y);
                if (ti >= 0 && ti !== draggingIndex && ti < memberModel.count) {
                    memberModel.move(draggingIndex, ti, 1);
                    draggingIndex = ti;
                }
            } else {
                // Outside the card → reveal the grid for positioning.
                root.dragOut = true;
            }
        }

        function endDrag() {
            if (draggingIndex < 0) { root.dragOut = false; return; }
            var appId = dragAppId, nm = dragName, ic = dragIcon;
            var fid = root.folderId;
            var dropX = lastX, dropY = lastY;
            var inside = root.cardContains(lastX, lastY);
            draggingIndex = -1;

            if (inside) {
                // Commit the new member order.
                root.dragOut = false;
                var ids = [];
                for (var i = 0; i < memberModel.count; ++i) ids.push(memberModel.get(i).appId);
                if (root.pages) root.pages.setFolderApps(fid, ids);
            } else {
                // Pull the app out of the folder onto the grid where released.
                root.close();
                if (root.pages) root.pages.takeMemberFromFolder(fid, appId);
                if (root.dragController) root.dragController.placeAppAtPoint(appId, nm, ic, dropX, dropY);
            }
        }
    }

    // Floating drag icon — a child of root (sibling of the card), so it stays
    // visible while the card fades to 0 during a drag-out.
    LomiriShape {
        id: floatIcon
        z: 100
        visible: folderDrag.dragging
        width: units.gu(6) * 1.15
        height: 7.5 / 8 * width
        radius: "medium"
        borderSource: "undefined"
        sourceFillMode: LomiriShape.PreserveAspectCrop
        opacity: 0.92
        source: Image {
            asynchronous: true
            sourceSize.width: floatIcon.width
            source: folderDrag.dragIcon
        }
    }
}
