/**
 * @file FolderOverlay
 * @description Full-screen modal that opens a folder: an editable name plus a
 *   grid of the member apps. Tap an app to launch it; long-press to enter the
 *   overlay's edit mode, then the "×" badge removes an app from the folder
 *   (it returns to the home grid). The folder auto-dissolves in the model when
 *   it drops to one member — this overlay closes itself when that happens.
 *
 *   Self-contained scrim + card (same pattern as the other overlays). Members
 *   are rendered with the shared TileBody in "folder" container mode; drag is
 *   disabled here (controller: null) — see WidgetAPI/plan note on drag-out.
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

    /** Px width of the Lomiri launcher panel overlapping us. */
    property real leftReserve: 0

    /** The folder currently shown. */
    property string folderId: ""

    /** Local edit mode — long-press a member to toggle on; reveals the "×". */
    property bool editMode: false

    /** Re-emitted up to Stage so the home overlay drops on launch. */
    signal launchRequested(string appId)

    anchors.fill: parent
    z: 1050
    visible: false
    color: "#cc000000"

    // Live member tiles, rebuilt from the model by refresh().
    ListModel { id: memberModel }

    function open(fid) {
        folderId = fid;
        editMode = false;
        nameField.text = pages ? pages.folderNameOf(fid) : "";
        refresh();
        visible = true;
    }

    function close() {
        _commitName();
        editMode = false;
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
            if (visible) { visible = false; editMode = false; }
            return;
        }
        var ids = pages.folderApps(folderId);
        for (var i = 0; i < ids.length; ++i) {
            var info = pages.appInfo(ids[i]);
            if (!info) continue;  // uninstalled — skip
            memberModel.append({ appId: info.appId, name: info.name, icon: info.icon });
        }
    }

    // Tap outside the card closes (committing the name).
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.9, units.gu(48))
        height: cardCol.height + units.gu(4)
        radius: units.gu(2)
        color: "#262d4d"

        // Swallow taps on the card background (so they don't dismiss), and a
        // tap on empty card space exits edit mode.
        MouseArea {
            anchors.fill: parent
            onClicked: root.editMode = false
        }

        Column {
            id: cardCol
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(2); rightMargin: units.gu(2)
            }
            spacing: units.gu(2)

            TextField {
                width: parent.width
                id: nameField
                inputMethodHints: Qt.ImhNoPredictiveText
                placeholderText: "Folder name"
                onAccepted: root._commitName()
            }

            // Member apps — wraps to multiple rows.
            Flow {
                width: parent.width
                spacing: units.gu(1)
                Repeater {
                    model: memberModel
                    delegate: Item {
                        width: units.gu(9)
                        height: units.gu(11)
                        TileBody {
                            anchors.fill: parent
                            appId: model.appId
                            appName: model.name
                            iconSrc: model.icon
                            container: "folder"
                            controller: null          // no drag inside the folder (v1)
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

            Row {
                anchors.right: parent.right
                Button {
                    text: "Done"
                    color: "#3d5af1"
                    onClicked: root.close()
                }
            }
        }
    }
}
