/**
 * @file SysInfoWidget
 * @description A fastfetch-style system-info widget: an ASCII logo beside a
 *   bordered list of icon + label rows (user, host, uptime, distro, kernel,
 *   desktop, shell) with their values in a column to the right. Everything is
 *   auto-fetched via the injected SysInfoService (read once, cached); uptime
 *   stays live off the injected clock. Every element has its own colour slot.
 *
 *   Row icons are either Suru theme icons (recoloured by Icon.color) or bundled
 *   monochrome SVGs — the latter are tinted with a ColorOverlay, because
 *   Lomiri's Icon.color does NOT colourise a custom `source` svg.
 *
 *   The whole cluster is centred and scaled to fit, so it stays inside the box
 *   in both portrait and the (narrower) landscape layout.
 *
 * @status New.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3

WidgetBase {
    id: root

    /** Injected SysInfoService (cached system facts + uptime). */
    property var sysInfo: null

    readonly property real _rowH: units.gu(2.3)
    readonly property real _fontPx: units.gu(1.5)

    // ASCII logo. Backslashes are doubled for the string; rendered verbatim in
    // a monospace font so the art lines up.
    readonly property string _ascii:
        "             .-.\n" +
        "       .-'``(|||)\n" +
        "    ,`\\ \\    `-`.\n" +
        "   /   \\ '``-.   `\n" +
        " .-.  ,       `___:\n" +
        "(:::) :        ___\n" +
        " `-`  `       ,   :\n" +
        "   \\   / ,..-`   ,\n" +
        "    `./ /    .-.`\n" +
        "       `-..-(   )\n" +
        "             `-`"

    // Field rows: {key (also colour slot), label, and either a theme `icon`
    // name or a bundled `src` svg}. Static (no clock dep), so the Repeaters
    // build once; only the uptime value re-evaluates on tick.
    readonly property var _fields: [
        { key: "user",    icon: "account",              label: "user" },
        { key: "host",    icon: "computer-symbolic",    label: "host" },
        { key: "uptime",  icon: "clock",                label: "uptime" },
        { key: "distro",  icon: "ubuntu-logo-symbolic", label: "distro" },
        { key: "kernel",  src:  "../icons/tux.svg",     label: "kernel" },
        { key: "desktop", icon: "view-grid-symbolic",   label: "desktop" },
        { key: "shell",   src:  "../icons/shell.svg",   label: "shell" }
    ]

    function _valueFor(key) {
        if (!sysInfo) return "";
        var v = "";
        switch (key) {
        case "user":    v = sysInfo.user; break;
        case "host":    v = sysInfo.hostname; break;
        case "uptime":  v = clock ? sysInfo.uptimeText(clock.now) : sysInfo.uptimeText(null); break;
        case "distro":  v = sysInfo.distro; break;
        case "kernel":  v = sysInfo.kernel; break;
        case "desktop": v = sysInfo.desktop; break;
        case "shell":   v = sysInfo.shell; break;
        }
        return (v || "").toLowerCase();
    }

    Component.onCompleted: if (sysInfo) sysInfo.ensureLoaded()
    onSysInfoChanged: if (sysInfo) sysInfo.ensureLoaded()

    // Centred cluster, scaled down to fit whatever space the (rotating) box
    // gives us — so it never overflows in landscape.
    Row {
        id: content
        anchors.centerIn: parent
        spacing: units.gu(1.5)
        scale: Math.min(1,
            (parent.width  - units.gu(1)) / Math.max(1, implicitWidth),
            (parent.height - units.gu(1)) / Math.max(1, implicitHeight))

        // ---- ASCII logo ----
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root._ascii
            textFormat: Text.PlainText
            wrapMode: Text.NoWrap
            font.family: "Ubuntu Mono"
            font.pixelSize: root._fontPx
            lineHeight: 1.0
            color: root.colorOf("ascii", "#e95420")
        }

        // ---- bordered icon + label box ----
        Rectangle {
            id: infoBox
            anchors.verticalCenter: parent.verticalCenter
            width: labelCol.width + units.gu(2)
            height: labelCol.height + units.gu(1.4)
            radius: units.gu(1)
            color: "transparent"
            border.color: root.colorOf("border", "#3a4262")
            border.width: 1

            Column {
                id: labelCol
                anchors.centerIn: parent
                spacing: units.gu(0.5)
                Repeater {
                    model: root._fields
                    delegate: Row {
                        height: root._rowH
                        spacing: units.gu(0.7)

                        // Theme icon (Icon.color) OR bundled svg (ColorOverlay).
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(1.7); height: width
                            Icon {
                                anchors.fill: parent
                                visible: !modelData.src
                                name: modelData.icon ? modelData.icon : ""
                                color: root.colorOf(modelData.key, "#9fa9c0")
                            }
                            Image {
                                id: srcImg
                                anchors.fill: parent
                                visible: false
                                source: modelData.src ? modelData.src : ""
                                sourceSize.width: width
                                sourceSize.height: height
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            ColorOverlay {
                                anchors.fill: parent
                                visible: !!modelData.src
                                source: srcImg
                                color: root.colorOf(modelData.key, "#9fa9c0")
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: root.colorOf(modelData.key, "#9fa9c0")
                            font.family: "Ubuntu Mono"
                            font.pixelSize: root._fontPx
                        }
                    }
                }
            }
        }

        // ---- values ----
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: units.gu(0.5)
            Repeater {
                model: root._fields
                delegate: Label {
                    height: root._rowH
                    verticalAlignment: Text.AlignVCenter
                    text: root._valueFor(modelData.key)
                    color: root.colorOf("value", "#ffffff")
                    font.family: "Ubuntu Mono"
                    font.pixelSize: root._fontPx
                    elide: Text.ElideRight
                }
            }
        }
    }
}
