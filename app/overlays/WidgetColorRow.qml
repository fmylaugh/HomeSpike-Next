/**
 * @file WidgetColorRow
 * @description One "Label …… colour swatch" row used by the widget settings
 *   sheet. Tapping anywhere on the row emits tapped(); the parent opens the
 *   colour picker for that section.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: row

    property string label: ""
    property string swatch: "#ffffff"
    signal tapped()

    implicitHeight: units.gu(5)

    Label {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        text: row.label
        color: "white"
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: units.gu(5); height: units.gu(3.2)
        radius: units.gu(0.6)
        color: row.swatch
        border.color: "#3a456a"; border.width: 1
    }
    MouseArea { anchors.fill: parent; onClicked: row.tapped() }
}
