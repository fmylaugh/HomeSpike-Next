/**
 * @file ClockWidget
 * @description Digital clock widget. Two size variants:
 *   - "wide"  (4x2): large time over a weekday/date subtitle.
 *   - "small" (2x2): time only.
 *   Time follows the system 12/24-hour preference and the date uses locale
 *   names, both via the injected LocaleClock. Display-only in v1.
 *
 * @status Stable.
 * @issues None
 * @todo
 *   - [ ] Optional "next alarm" line (needs the alarm backend).
 */
import QtQuick 2.15
import Lomiri.Components 1.3

WidgetBase {
    id: root

    readonly property var _now: clock ? clock.now : new Date()
    readonly property bool _small: variant === "small"

    // Fill the width (with a small margin) and centre vertically, so the
    // labels have a width to fit against — the font shrinks to fit when the
    // widget is rotated and the content area becomes narrower than its box.
    Column {
        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: units.gu(0.5); rightMargin: units.gu(0.5)
        }
        spacing: units.gu(0.4)

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.clock ? root.clock.timeText(root._now)
                             : Qt.formatTime(root._now, "h:mm")
            color: root.colorOf("time", "#ffffff")
            font.weight: Font.DemiBold
            font.pixelSize: root._small ? units.gu(4.5) : units.gu(7)   // max size
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: units.gu(1.5)
        }

        Label {
            visible: !root._small
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.clock ? root.clock.dateText(root._now).toUpperCase() : ""
            color: root.colorOf("date", "#ffffff")
            font.weight: Font.DemiBold
            font.pixelSize: units.gu(1.8)
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: units.gu(1)
            elide: Text.ElideRight
        }
    }
}
