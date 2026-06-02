/**
 * @file AddPageButton
 * @description Round "+" button shown in the bottom-right corner while
 *   HomeSpike is in edit mode, sitting just above the settings gear. Tapping
 *   it adds a new home page. The caller hides it once the page cap is reached.
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

    /** Distance from the bottom of the parent (caller stacks it above the gear). */
    property real bottomOffset: units.gu(2)

    /** Emitted when the user taps to add a page. */
    signal triggered()

    visible: active
    z: 200
    width: units.gu(5)
    height: width
    radius: width / 2
    color: "#3d5af1"

    Icon {
        anchors.centerIn: parent
        width: parent.width * 0.5
        height: width
        source: "../icons/ui-add.svg"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.triggered()
    }
}
