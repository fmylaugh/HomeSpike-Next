/**
 * @file MonitorText
 * @description A simple [ label ........ value ] text row for the System
 *   Monitor widget's non-bar sections (System, Network).
 *
 * @status New.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: row
    property string label: ""
    property string value: ""
    property color labelColor: "#9fa9c0"
    property color valueColor: "#ffffff"
    property real fontPx: units.gu(1.4)
    property real labelW: units.gu(6.5)

    height: units.gu(2.0)

    Label {
        id: l
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: row.labelW
        text: row.label
        color: row.labelColor
        font.pixelSize: row.fontPx
        elide: Text.ElideRight
    }
    Label {
        anchors { left: l.right; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: units.gu(0.5) }
        horizontalAlignment: Text.AlignRight
        text: row.value
        color: row.valueColor
        font.pixelSize: row.fontPx
        elide: Text.ElideRight
    }
}
