/**
 * @file CalendarWidget
 * @description Calendar widget. Two size variants:
 *   - "small" (2x2): short month name over a big day number.
 *   - "wide"  (4x3): left column weekday + big day; right a full
 *     month grid with locale weekday headers (starting on the locale's first
 *     day) and today highlighted.
 *   All month/weekday names + the week start come from the injected
 *   LocaleClock's Qt.locale(). Recomputes when the clock's date rolls over.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

WidgetBase {
    id: root

    readonly property var _now: clock ? clock.now : new Date()
    readonly property int _y: _now.getFullYear()
    readonly property int _m: _now.getMonth()
    readonly property int _d: _now.getDate()
    readonly property int _firstDow: clock ? clock.firstDayOfWeek : 0

    // Offset of the 1st within its week, relative to the locale's first day.
    readonly property int _offset: (new Date(_y, _m, 1).getDay() - _firstDow + 7) % 7
    readonly property int _daysInMonth: new Date(_y, _m + 1, 0).getDate()
    // Weeks the month actually spans (4–6). The grid renders exactly this many
    // rows so there's no empty trailing row leaving dead space at the bottom.
    readonly property int _weeks: Math.ceil((_offset + _daysInMonth) / 7)
    // _weeks×7 cells, each a day-of-month number or 0 for leading/trailing blanks.
    readonly property var _cells: {
        var arr = [];
        var total = _weeks * 7;
        for (var i = 0; i < total; ++i) {
            var dayNum = i - _offset + 1;
            arr.push((dayNum >= 1 && dayNum <= _daysInMonth) ? dayNum : 0);
        }
        return arr;
    }

    // ---------------- small variant ----------------
    Column {
        visible: root.variant === "small"
        anchors.centerIn: parent
        spacing: units.gu(0.1)
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.clock ? root.clock.monthShort(root._now).toUpperCase() : ""
            color: root.colorOf("month", "#e94560")
            font.weight: Font.DemiBold
            font.pixelSize: units.gu(2.4)
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._d
            color: root.colorOf("day", "#ffffff")
            font.pixelSize: units.gu(6)
        }
    }

    // ---------------- wide variant ----------------
    Row {
        visible: root.variant === "wide"
        anchors.fill: parent
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1.5)

        // Left: weekday + big day number, centred in the column. The labels
        // fill the column width and fit their font to it, so they shrink (not
        // overflow) when the widget rotates and this column gets narrower.
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.3
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.clock ? root.clock.dayShort(root._now.getDay()).toUpperCase() : ""
                color: root.colorOf("weekday", "#e94560")
                font.weight: Font.DemiBold
                font.pixelSize: units.gu(2.6)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: units.gu(1)
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root._d
                color: root.colorOf("day", "#ffffff")
                font.pixelSize: units.gu(7)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: units.gu(2)
            }
        }

        // Right: weekday header row + 6x7 day grid.
        Column {
            id: gridCol
            width: parent.width * 0.62
            height: parent.height
            spacing: units.gu(0.3)

            Row {
                width: parent.width
                height: units.gu(1.8)
                Repeater {
                    model: 7
                    delegate: Item {
                        width: gridCol.width / 7
                        height: parent.height
                        Label {
                            anchors.centerIn: parent
                            text: root.clock ? root.clock.dayNarrow((root._firstDow + index) % 7) : ""
                            color: root.colorOf("header", "#9fa9c0")
                            font.pixelSize: units.gu(1.3)
                        }
                    }
                }
            }

            Grid {
                id: dayGrid
                width: parent.width
                height: parent.height - units.gu(1.8) - gridCol.spacing
                columns: 7
                Repeater {
                    model: root._cells
                    delegate: Item {
                        width: dayGrid.width / 7
                        height: dayGrid.height / Math.max(1, root._weeks)

                        // Today highlight: rounded box (its colour is the
                        // "today" slot) with dark text for contrast.
                        Rectangle {
                            anchors.centerIn: parent
                            visible: modelData === root._d
                            width: Math.min(parent.width, parent.height) - units.gu(0.2)
                            height: width
                            radius: width / 2
                            color: root.colorOf("today", "#ffffff")
                        }
                        Label {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: modelData > 0
                            text: modelData
                            color: modelData === root._d ? "#11162b" : root.colorOf("dates", "#ffffff")
                            font.pixelSize: units.gu(1.5)
                            fontSizeMode: Text.Fit
                            minimumPixelSize: units.gu(0.8)
                            font.weight: modelData === root._d ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
        }
    }
}
