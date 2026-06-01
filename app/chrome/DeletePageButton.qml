/**
 * @file DeletePageButton
 * @description Round trash button shown in the bottom-right edit-mode stack.
 *   Tapping it asks to delete the current home page (the caller shows the
 *   confirmation). Hidden when only one page remains.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15

Rectangle {
    id: root

    /** Whether the button should be shown. */
    property bool active: false

    /** Emitted when the user taps the trash. */
    signal triggered()

    visible: active
    z: 200
    width: units.gu(5)
    height: width
    radius: width / 2
    color: "#e94560"

    // Simple drawn trash can (no emoji glyph dependency).
    Item {
        anchors.centerIn: parent
        width: units.gu(2.2)
        height: units.gu(2.6)

        // Handle
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: parent.width * 0.4
            height: units.gu(0.35)
            radius: height / 2
            color: "white"
        }
        // Lid
        Rectangle {
            id: lid
            anchors.horizontalCenter: parent.horizontalCenter
            y: units.gu(0.45)
            width: parent.width
            height: units.gu(0.45)
            radius: height / 2
            color: "white"
        }
        // Body (outline)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: lid.bottom
            anchors.topMargin: units.gu(0.25)
            width: parent.width * 0.82
            height: parent.height - units.gu(1.1)
            radius: units.gu(0.4)
            color: "transparent"
            border.color: "white"
            border.width: units.gu(0.28)
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.triggered()
    }
}
