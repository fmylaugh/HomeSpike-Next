/**
 * @file SysMonitorWidget
 * @description A real-time, Conky-style system monitor. Shows a user-chosen set
 *   of sections — System, CPU (overall + per-core), Memory (+ swap), Network,
 *   Battery, Temperature — each with a coloured header and bar/text rows fed
 *   live by the injected SysMonitorService. The section set is toggled in the ⚙
 *   sheet; header / bar / label / value colours are all customisable. Content is
 *   scaled to fit the tile, so it stays readable as you add or remove sections.
 *
 * @status New.
 * @issues CPU / network need one poll interval before their first values show.
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

WidgetBase {
    id: root

    /** Injected SysMonitorService. */
    property var monitor: null

    readonly property var _defaultSections: ["cpu", "memory", "network"]
    readonly property var _sections: (settings && settings.sections && settings.sections.length !== undefined)
                                     ? settings.sections : _defaultSections
    function _on(k) { return _sections.indexOf(k) >= 0; }

    readonly property real _fontPx: units.gu(1.4)
    readonly property real _hdrPx: units.gu(1.4)
    readonly property color _cHeader: root.colorOf("header", "#e9a23b")
    readonly property color _cBar:    root.colorOf("bar",    "#3d5af1")
    readonly property color _cLabel:  root.colorOf("label",  "#9fa9c0")
    readonly property color _cValue:  root.colorOf("value",  "#ffffff")

    onMonitorChanged: { if (monitor) { monitor.attach(); _applyInterval(); } }
    onSettingsChanged: _applyInterval()
    Component.onDestruction: if (monitor) monitor.detach()
    function _applyInterval() {
        if (monitor && settings && typeof settings.refresh === "number" && settings.refresh > 0)
            monitor.intervalMs = settings.refresh * 1000;
    }

    // Scale-to-fit so any set of sections fits the tile height.
    Item {
        anchors.fill: parent
        anchors.margins: units.gu(0.8)
        clip: true

        Column {
            id: content
            width: parent.width
            transformOrigin: Item.Top
            scale: Math.min(1, parent.height / Math.max(1, implicitHeight))
            spacing: units.gu(0.8)

            // ---------------- SYSTEM ----------------
            Column {
                visible: root._on("system")
                width: parent.width
                spacing: units.gu(0.1)
                Label { text: "SYSTEM"; color: root._cHeader; font.bold: true; font.pixelSize: root._hdrPx }
                MonitorText { width: parent.width; label: "os";     value: root.monitor ? root.monitor.distro : "";   labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
                MonitorText { width: parent.width; label: "kernel"; value: root.monitor ? root.monitor.kernel : "";   labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
                MonitorText { width: parent.width; label: "cpu";    value: root.monitor ? root.monitor.cpuModel : ""; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
                MonitorText { width: parent.width; label: "uptime"; value: (root.monitor && root.clock) ? root.monitor.uptimeText(root.clock.now) : ""; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
            }

            // ---------------- CPU ----------------
            Column {
                visible: root._on("cpu")
                width: parent.width
                spacing: units.gu(0.2)
                Label { text: "CPU"; color: root._cHeader; font.bold: true; font.pixelSize: root._hdrPx }
                MonitorBar {
                    width: parent.width; label: "all"
                    pct: root.monitor ? root.monitor.cpu : 0
                    value: (root.monitor ? root.monitor.cpu : 0).toFixed(0) + "%"
                    barColor: root._cBar; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx
                }
                Repeater {
                    model: root.monitor ? root.monitor.cores.length : 0
                    delegate: MonitorBar {
                        width: parent.width
                        label: "cpu" + index
                        pct: (root.monitor && root.monitor.cores[index] !== undefined) ? root.monitor.cores[index] : 0
                        value: pct.toFixed(0) + "%"
                        barColor: root._cBar; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx
                    }
                }
            }

            // ---------------- MEMORY ----------------
            Column {
                visible: root._on("memory")
                width: parent.width
                spacing: units.gu(0.2)
                Label { text: "MEMORY"; color: root._cHeader; font.bold: true; font.pixelSize: root._hdrPx }
                MonitorBar {
                    width: parent.width; label: "ram"
                    pct: root.monitor ? root.monitor.memPct : 0
                    value: root.monitor ? (root.monitor.fmtSize(root.monitor.memUsed) + "/" + root.monitor.fmtSize(root.monitor.memTotal)) : ""
                    barColor: root._cBar; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx; valueW: units.gu(9)
                }
                MonitorBar {
                    visible: root.monitor && root.monitor.swapTotal > 0
                    width: parent.width; label: "swap"
                    pct: root.monitor ? root.monitor.swapPct : 0
                    value: root.monitor ? (root.monitor.fmtSize(root.monitor.swapUsed) + "/" + root.monitor.fmtSize(root.monitor.swapTotal)) : ""
                    barColor: root._cBar; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx; valueW: units.gu(9)
                }
            }

            // ---------------- NETWORK ----------------
            Column {
                visible: root._on("network")
                width: parent.width
                spacing: units.gu(0.1)
                Label { text: "NETWORK"; color: root._cHeader; font.bold: true; font.pixelSize: root._hdrPx }
                MonitorText { width: parent.width; label: "down"; value: root.monitor ? root.monitor.fmtSpeed(root.monitor.netDown) : ""; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
                MonitorText { width: parent.width; label: "up";   value: root.monitor ? root.monitor.fmtSpeed(root.monitor.netUp) : "";   labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
                MonitorText { width: parent.width; label: "↓ tot"; value: root.monitor ? root.monitor.fmtSize(root.monitor.netRxTotal) : ""; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
                MonitorText { width: parent.width; label: "↑ tot"; value: root.monitor ? root.monitor.fmtSize(root.monitor.netTxTotal) : ""; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx }
            }

            // ---------------- BATTERY ----------------
            Column {
                visible: root._on("battery")
                width: parent.width
                spacing: units.gu(0.2)
                Label { text: "BATTERY"; color: root._cHeader; font.bold: true; font.pixelSize: root._hdrPx }
                MonitorBar {
                    width: parent.width; label: "batt"
                    pct: root.monitor && root.monitor.battery >= 0 ? root.monitor.battery : 0
                    value: root.monitor && root.monitor.battery >= 0
                           ? (root.monitor.battery + "%" + (root.monitor.batteryStatus === "Charging" ? " ⚡" : ""))
                           : "—"
                    barColor: root._cBar; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx
                }
            }

            // ---------------- TEMPERATURE ----------------
            Column {
                visible: root._on("temp")
                width: parent.width
                spacing: units.gu(0.2)
                Label { text: "TEMP"; color: root._cHeader; font.bold: true; font.pixelSize: root._hdrPx }
                MonitorBar {
                    width: parent.width; label: "soc"
                    pct: root.monitor ? Math.min(100, root.monitor.temp) : 0
                    value: root.monitor ? root.monitor.temp.toFixed(0) + "°C" : "—"
                    barColor: root._cBar; labelColor: root._cLabel; valueColor: root._cValue; fontPx: root._fontPx
                }
            }
        }
    }
}
