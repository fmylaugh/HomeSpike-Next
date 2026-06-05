/**
 * @file AddWidgetButton
 * @description Round button in the edit-mode bottom-right stack that opens the
 *   widget picker. Drawn glyph (a 2x2 grid of squares) rather than a themed
 *   icon so it has no icon-asset dependency. The caller decides when it's
 *   active; tapping it always opens the picker (which itself shows a hint when
 *   the current layout doesn't support widgets).
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

    /** Emitted when the user taps to add a widget. */
    signal triggered()

    visible: active
    z: 200
    width: units.gu(5)
    height: width
    radius: width / 2
    color: "#3d5af1"

    // 2x2 grid glyph.
    Grid {
        anchors.centerIn: parent
        columns: 2
        rowSpacing: units.gu(0.5)
        columnSpacing: units.gu(0.5)
        Repeater {
            model: 4
            delegate: Rectangle {
                width: units.gu(1.2); height: width
                radius: units.gu(0.3)
                color: "white"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.triggered()
    }
}
