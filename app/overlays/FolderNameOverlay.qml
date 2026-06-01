/**
 * @file FolderNameOverlay
 * @description Full-screen modal shown the moment one app is dropped onto
 *   another. Asks the user to name the new folder, or cancel. Self-contained
 *   scrim + centered card (same pattern as ConfirmRemoveOverlay — no
 *   PopupUtils, so vol-key screenshots capture it and z-ordering Just Works).
 *
 *   The drop's merge context (which page + the two appIds) is captured by
 *   show() and echoed back on confirmed() so main.qml can call
 *   pages.createFolder(). Cancel emits cancelled() — main.qml reverts the
 *   un-persisted drag with a rebuild.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    // ---- Pending merge context (set by show, echoed on confirmed) ----
    property int    page: -1
    property string targetAppId: ""
    property string sourceAppId: ""

    /** Emitted when the user confirms a name (page/target/source echoed). */
    signal confirmed(int page, string targetAppId, string sourceAppId, string folderName)

    /** Emitted when the user cancels (tap-outside or Cancel). */
    signal cancelled()

    /** Px width of the Lomiri launcher panel overlapping us — shifts the card
     *  right so it stays centered in the visible content area. */
    property real leftReserve: 0

    anchors.fill: parent
    z: 1100
    visible: false
    color: "#aa000000"

    function show(p, target, source) {
        page = p;
        targetAppId = target;
        sourceAppId = source;
        nameField.text = "Folder";
        visible = true;
        nameField.forceActiveFocus();
        nameField.selectAll();
    }

    function _commit() {
        var n = nameField.text.trim().length > 0 ? nameField.text.trim() : "Folder";
        root.confirmed(root.page, root.targetAppId, root.sourceAppId, n);
        root.visible = false;
    }

    function _cancel() {
        root.visible = false;
        root.cancelled();
    }

    // Tap outside the card cancels.
    MouseArea {
        anchors.fill: parent
        onClicked: root._cancel()
    }

    Rectangle {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.85, units.gu(50))
        height: cardCol.height + units.gu(4)
        radius: units.gu(2)
        color: "#262d4d"

        // Swallow taps on the card so they don't bubble to the dismiss area.
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
                text: "New folder"
                color: "white"
                font.bold: true
                fontSize: "large"
                width: parent.width
                wrapMode: Text.WordWrap
            }
            TextField {
                id: nameField
                width: parent.width
                inputMethodHints: Qt.ImhNoPredictiveText
                placeholderText: "Folder name"
                onAccepted: root._commit()
            }
            Row {
                anchors.right: parent.right
                spacing: units.gu(1)
                Button {
                    text: "Cancel"
                    onClicked: root._cancel()
                }
                Button {
                    text: "Create"
                    color: "#3d5af1"
                    onClicked: root._commit()
                }
            }
        }
    }
}
