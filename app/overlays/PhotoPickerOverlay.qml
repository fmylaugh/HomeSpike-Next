/**
 * @file PhotoPickerOverlay
 * @description A simple full-screen photo browser used by the Photo widget's
 *   settings. Lists folders + image files from the user's home (starting at
 *   ~/Pictures) with a FolderListModel; tap a folder to descend, "Up" to go
 *   back, tap an image to choose it. open(callback) shows it and calls back with
 *   the picked file:// URL. Self-contained — no ContentHub.
 *
 * @status New.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Qt.labs.folderlistmodel 2.1
import Lomiri.Components 1.3

Rectangle {
    id: root

    property real leftReserve: 0

    readonly property string _home: "file:///home/phablet"
    property string folder: _home + "/Pictures"
    property var _cb: null

    anchors.fill: parent
    z: 950
    visible: false
    color: "#cc000000"

    /** Show the picker; `cb` receives the chosen file:// URL (a string). */
    function open(cb) {
        _cb = cb;
        folder = _home + "/Pictures";
        visible = true;
    }

    function _pick(url) {
        var cb = _cb;
        _cb = null;
        visible = false;
        if (cb) cb("" + url);
    }

    function _up() {
        var s = ("" + folder).replace(/\/+$/, "");
        var i = s.lastIndexOf("/");
        if (i > root._home.length - 1) root.folder = s.substring(0, i);
    }

    // Tap outside the card cancels.
    MouseArea { anchors.fill: parent; onClicked: root.visible = false }

    Rectangle {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.92, units.gu(60))
        height: parent.height * 0.85
        radius: units.gu(2)
        color: "#262d4d"

        MouseArea { anchors.fill: parent }   // eat clicks inside the card

        // ---- header ----
        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: units.gu(2) }
            height: units.gu(5)

            Rectangle {
                id: upBtn
                width: units.gu(5); height: units.gu(5); radius: units.gu(1)
                color: upMouse.pressed ? "#3d5af1" : "#1d2540"
                anchors.verticalCenter: parent.verticalCenter
                Icon { anchors.centerIn: parent; width: units.gu(2.5); height: width; name: "go-up"; color: "white" }
                MouseArea { id: upMouse; anchors.fill: parent; onClicked: root._up() }
            }
            Column {
                anchors { left: upBtn.right; right: cancelBtn.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                Label { text: "Choose a photo"; color: "white"; font.bold: true }
                Label {
                    width: parent.width
                    text: ("" + root.folder).replace("file://", "")
                    color: "#9fa9c0"; fontSize: "small"; elide: Text.ElideLeft
                }
            }
            Rectangle {
                id: cancelBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: cancelLabel.width + units.gu(3); height: units.gu(5); radius: units.gu(1)
                color: cancelMouse.pressed ? "#3d5af1" : "#1d2540"
                Label { id: cancelLabel; anchors.centerIn: parent; text: "Cancel"; color: "white"; fontSize: "small" }
                MouseArea { id: cancelMouse; anchors.fill: parent; onClicked: root.visible = false }
            }
        }

        FolderListModel {
            id: folderModel
            folder: root.folder
            showDirs: true
            showDirsFirst: true
            showHidden: false
            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.webp"]
        }

        GridView {
            id: grid
            anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: units.gu(2); topMargin: units.gu(1) }
            clip: true
            cellWidth: Math.floor(width / Math.max(2, Math.floor(width / units.gu(13))))
            cellHeight: units.gu(15)
            model: folderModel

            delegate: Item {
                width: grid.cellWidth
                height: grid.cellHeight

                Column {
                    anchors.centerIn: parent
                    spacing: units.gu(0.5)
                    width: parent.width - units.gu(1.5)

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: units.gu(10)
                        radius: units.gu(1)
                        color: "#1d2540"
                        clip: true

                        // Folder tile.
                        Icon {
                            anchors.centerIn: parent
                            visible: fileIsDir
                            width: units.gu(5); height: width
                            name: "folder"
                            color: "#9fa9c0"
                        }
                        // Image thumbnail.
                        Image {
                            anchors.fill: parent
                            visible: !fileIsDir
                            source: fileIsDir ? "" : fileURL
                            sourceSize.width: units.gu(20)
                            sourceSize.height: units.gu(20)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: fileName
                        color: "white"; fontSize: "x-small"
                        elide: Text.ElideRight; maximumLineCount: 1
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: fileIsDir ? (root.folder = fileURL) : root._pick(fileURL)
                }
            }

            Label {
                anchors.centerIn: parent
                visible: folderModel.count === 0 && folderModel.status === FolderListModel.Ready
                text: "No images here"
                color: "#9fa9c0"
            }
        }
    }
}
