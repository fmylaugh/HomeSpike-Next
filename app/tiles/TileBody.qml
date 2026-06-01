/**
 * @file TileBody
 * @description One app tile — the icon + label + interaction surface used
 *   by both the page grids and the dock. Renders the app icon via
 *   LomiriShape (same primitive Lomiri's own drawer uses), shows a small
 *   "×" remove badge in edit mode, and routes touch into the injected
 *   DragController for drag-and-drop reordering.
 *
 *   Layout note: the tile-wide MouseArea is declared BEFORE Column on
 *   purpose. QML hit-tests siblings in declaration order with later
 *   declarations winning. Putting Column after the MouseArea means the
 *   X-badge MouseArea inside Column wins on its hit area, while taps
 *   anywhere else on the tile fall through to the tile MouseArea below.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: body

    // ---- Tile content (set by parent for each model row) ----
    property string appId:   ""
    property string appName: ""
    property string iconSrc: ""

    /** Whether to draw the app-name label under the icon. Dock tiles set
     *  this false — the dock shows icons only. */
    property bool showLabel: true

    /** Icon edge size. Dock tiles shrink this so a full row of items fits
     *  when Lomiri's side panel narrows the available width. */
    property real iconSize: units.gu(6)

    // ---- Folder fields (kind === "folder") ----
    /** "app" (single icon, launches) or "folder" (2x2 preview, opens). */
    property string kind: "app"
    /** Stable folder id — the drag key and open/dissolve target. */
    property string folderId: ""
    /** Folder display name (shown as the label). */
    property string folderName: ""
    /** Up to 4 member icon URIs for the 2x2 preview. */
    property var folderIcons: []

    // ---- Source-of-truth hints for the drag controller ----
    /** Either "grid" or "dock". */
    property string container: "grid"
    /** Page index when container === "grid"; ignored for dock. */
    property int sourcePage: -1
    /** Row index within the model. */
    property int indexInModel: -1

    // ---- Injected dependencies ----
    /** Whether HomeSpike is in edit mode (controls wiggle + X badge). */
    property bool editMode: false
    /** DragController instance for routing drag events. */
    property var controller: null

    /** Emitted when the user taps the X badge on an app tile. */
    signal removeRequested(string appId, string appName)

    /** Emitted when the user taps a folder (not in edit mode) — open it. */
    signal folderOpenRequested(string folderId)

    /** Emitted when the user taps the X badge on a folder — dissolve it. */
    signal folderDissolveRequested(string folderId)

    /** Emitted on long-press while NOT in edit mode (caller should enable it). */
    signal editModeRequested()

    /** Emitted the instant the user taps the tile to launch its app.
     *  HomeSpike re-emits this up to Lomiri's Stage so the home overlay
     *  drops immediately (without waiting for Mir's focus round-trip,
     *  which can be misread as a stale-echo and ignored). */
    signal launchRequested(string appId)

    // ============================================================
    // Touch / drag handling (declared FIRST — see file header)
    // ============================================================
    MouseArea {
        id: tileMouse
        anchors.fill: parent
        pressAndHoldInterval: 400
        // In edit mode, claim the touch so the GridView/ListView parents
        // can't steal it as a flick before our drag threshold triggers.
        preventStealing: body.editMode

        // A tap (or jittery tap) must NOT start a drag — measure distance
        // from the press point first.
        property real pressX: 0
        property real pressY: 0
        property bool dragStarted: false
        readonly property real dragThreshold: units.gu(2)

        onClicked: {
            if (body.editMode) return;
            if (body.kind === "folder") {
                body.folderOpenRequested(body.folderId);
                return;
            }
            body.launchRequested(body.appId);
            Qt.openUrlExternally("application:///" + body.appId + ".desktop");
        }
        onPressAndHold: {
            // Long-press outside edit mode = ask the parent to enter edit mode.
            if (!body.editMode) body.editModeRequested();
        }
        onPressed: {
            pressX = mouseX;
            pressY = mouseY;
            dragStarted = false;
            // Defensive: if a previous drag's onReleased never fired
            // (delegate destroyed during a cross-page scroll), clear
            // leftover state without persisting it.
            if (controller && controller.dragging) controller.abort();
        }
        onPositionChanged: {
            if (!body.editMode || !controller) return;
            var dx = mouseX - pressX;
            var dy = mouseY - pressY;
            if (!dragStarted) {
                if (Math.sqrt(dx*dx + dy*dy) < dragThreshold) return;
                dragStarted = true;
                var startPt = mapToItem(controller, mouseX, mouseY);
                // Drag key is the folderId for folders, appId for apps. The
                // floating-icon preview uses the first member icon for folders.
                var key  = (body.kind === "folder") ? body.folderId : body.appId;
                var nm   = (body.kind === "folder") ? body.folderName : body.appName;
                var icon = (body.kind === "folder")
                           ? ((body.folderIcons && body.folderIcons.length > 0) ? body.folderIcons[0] : "")
                           : body.iconSrc;
                controller.startDrag(body.container, body.sourcePage, body.indexInModel,
                                         key, nm, icon, startPt.x, startPt.y);
            }
            var pt = mapToItem(controller, mouseX, mouseY);
            controller.moveDrag(pt.x, pt.y);
        }
        onReleased: {
            if (controller && controller.dragging) controller.endDrag();
            dragStarted = false;
        }
        onCanceled: {
            if (controller && controller.dragging) controller.endDrag();
            dragStarted = false;
        }
    }

    // ============================================================
    // Visual content
    // ============================================================
    Column {
        anchors.centerIn: parent
        spacing: units.gu(0.5)

        Item {
            id: iconHolder
            width: body.iconSize
            height: 7.5 / 8 * width
            anchors.horizontalCenter: parent.horizontalCenter

            // Rotating content wrapper — the jiggle rocks this, so it covers
            // both the app icon and the folder preview while leaving the "×"
            // badge upright.
            Item {
                id: iconContent
                anchors.fill: parent

                // App icon (single shape).
                LomiriShape {
                    id: shape
                    anchors.fill: parent
                    visible: body.kind !== "folder"
                    radius: "medium"
                    borderSource: "undefined"
                    sourceFillMode: LomiriShape.PreserveAspectCrop
                    source: Image {
                        asynchronous: true
                        sourceSize.width: shape.width
                        source: body.iconSrc
                    }
                }

                // Folder preview: frosted plate with up to 4 mini icons (2x2).
                Rectangle {
                    id: folderPlate
                    visible: body.kind === "folder"
                    anchors.fill: parent
                    radius: units.gu(1.2)
                    color: "#40ffffff"

                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        rowSpacing: units.gu(0.4)
                        columnSpacing: units.gu(0.4)
                        Repeater {
                            model: body.folderIcons
                            delegate: LomiriShape {
                                width: (folderPlate.width - units.gu(1.6)) / 2
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

                // Edit-mode jiggle: a clear side-to-side rock so the user can
                // see tiles are now draggable. Paused while a drag is in flight
                // so the lifted tile doesn't jitter. A one-shot random head
                // start desyncs neighbouring tiles for a more organic feel, and
                // onStopped snaps the icon back upright when edit mode ends.
                SequentialAnimation {
                    running: body.editMode && (!controller || !controller.dragging)
                    PauseAnimation { duration: Math.round(Math.random() * 140) }
                    SequentialAnimation {
                        loops: Animation.Infinite
                        NumberAnimation { target: iconContent; property: "rotation"; from: -3; to: 3; duration: 140; easing.type: Easing.InOutSine }
                        NumberAnimation { target: iconContent; property: "rotation"; from: 3; to: -3; duration: 140; easing.type: Easing.InOutSine }
                    }
                    onStopped: iconContent.rotation = 0
                }
            }

            // Remove badge ("×") — top-left corner, edit mode only.
            // Dissolves a folder; hides an app from home.
            Rectangle {
                visible: body.editMode
                anchors {
                    top: iconHolder.top
                    horizontalCenter: iconHolder.left
                    topMargin: -units.gu(0.5)
                }
                width: units.gu(2.5)
                height: width
                radius: width / 2
                color: "white"
                border.color: "#202840"
                border.width: 1
                z: 20

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "#202840"
                    font.pixelSize: parent.height * 0.8
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    // Slightly larger hit target than the visible circle
                    anchors.margins: -units.gu(0.5)
                    onClicked: {
                        if (body.kind === "folder") body.folderDissolveRequested(body.folderId);
                        else body.removeRequested(body.appId, body.appName);
                    }
                }
            }
        }

        Label {
            visible: body.showLabel
            text: body.kind === "folder" ? body.folderName : body.appName
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
