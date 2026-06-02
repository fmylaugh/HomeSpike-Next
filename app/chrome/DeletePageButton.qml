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
import Lomiri.Components 1.3

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

    Icon {
        anchors.centerIn: parent
        width: parent.width * 0.5
        height: width
        source: "../icons/trash.svg"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.triggered()
    }
}
