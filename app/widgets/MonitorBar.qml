/**
 * @file MonitorBar
 * @description A labelled progress bar row for the System Monitor widget:
 *   [ label ] [ ===== track/fill ===== ] [ value ]. Colours are passed in.
 *
 * @status New.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: bar

    property string label: ""
    property real pct: 0            // 0..100
    property string value: ""
    property color barColor: "#3d5af1"
    property color labelColor: "#9fa9c0"
    property color valueColor: "#ffffff"
    property real fontPx: units.gu(1.4)
    property real labelW: units.gu(6.5)
    property real valueW: units.gu(7)

    height: units.gu(2.2)

    Label {
        id: lbl
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: bar.labelW
        text: bar.label
        color: bar.labelColor
        font.pixelSize: bar.fontPx
        elide: Text.ElideRight
    }
    Rectangle {
        anchors {
            left: lbl.right; right: val.left
            verticalCenter: parent.verticalCenter
            leftMargin: units.gu(0.5); rightMargin: units.gu(0.5)
        }
        height: units.gu(0.8)
        radius: height / 2
        color: "#33ffffff"
        Rectangle {
            width: parent.width * Math.max(0, Math.min(100, bar.pct)) / 100
            height: parent.height
            radius: height / 2
            color: bar.barColor
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
        }
    }
    Label {
        id: val
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: bar.valueW
        horizontalAlignment: Text.AlignRight
        text: bar.value
        color: bar.valueColor
        font.pixelSize: bar.fontPx
        elide: Text.ElideRight
    }
}
