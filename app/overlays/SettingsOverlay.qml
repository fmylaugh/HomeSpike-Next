/**
 * @file SettingsOverlay
 * @description Full-screen modal showing HomeSpike user-configurable
 *   settings: page count stepper and bottom-dock toggle. Both controls
 *   emit signals on user action — the parent owns the side effects
 *   (re-running rebuildVisible, etc.) so this module stays UI-only.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    /** Current page count (bound to persist.pageCount externally). */
    property int pageCount: 1

    /** Hard cap on page count, displayed in the help text. */
    property int maxPages: 5

    /** Current dock-enabled state (bound to persist.dockEnabled). */
    property bool dockEnabled: false

    /** Current dock background height in grid units (bound to persist.dockBgHeight). */
    property real dockBgHeight: 12.0

    /** Current tile placement mode (bound to persist.placementMode). */
    property string placementMode: "autoFill"

    /** Emitted when the user changes the page count via +/-. */
    signal pageCountAdjusted(int newCount)

    /** Emitted when the user flips the dock switch. */
    signal dockToggled(bool enabled)

    /** Emitted as the user drags the dock-height slider. */
    signal dockBgHeightAdjusted(real newGu)

    /** Emitted when the user picks a different layout mode. */
    signal placementModeAdjusted(string newMode)

    /** Px width of the Lomiri launcher panel currently overlapping us.
     *  We shift the dialog box right by half this so it stays centered in
     *  the visible content area instead of slipping under the panel. */
    property real leftReserve: 0

    anchors.fill: parent
    z: 900
    visible: false
    color: "#aa000000"

    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    Rectangle {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.85, units.gu(50))
        height: settingsCol.height + units.gu(4)
        radius: units.gu(2)
        color: "#262d4d"

        MouseArea { anchors.fill: parent }

        Column {
            id: settingsCol
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(2); rightMargin: units.gu(2)
            }
            spacing: units.gu(2)

            Label {
                text: "HomeSpike Settings"
                color: "white"
                font.bold: true
                fontSize: "large"
            }

            // ---- Pages stepper ----
            Row {
                width: parent.width
                spacing: units.gu(2)
                Column {
                    width: parent.width - pagesStepper.width - units.gu(2)
                    Label { text: "Pages"; color: "white" }
                    Label {
                        text: "Number of swipeable home screens (1–" + root.maxPages + "). When reduced, extra pages merge into the last."
                        color: "#9fa9c0"
                        fontSize: "small"
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
                Row {
                    id: pagesStepper
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: units.gu(0.5)
                    Button {
                        text: "−"
                        width: units.gu(4)
                        enabled: root.pageCount > 1
                        onClicked: root.pageCountAdjusted(root.pageCount - 1)
                    }
                    Label {
                        text: root.pageCount
                        color: "white"
                        font.bold: true
                        width: units.gu(3)
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Button {
                        text: "+"
                        width: units.gu(4)
                        enabled: root.pageCount < root.maxPages
                        onClicked: root.pageCountAdjusted(root.pageCount + 1)
                    }
                }
            }

            // ---- Dock toggle ----
            Row {
                width: parent.width
                spacing: units.gu(2)
                Column {
                    width: parent.width - dockSwitch.width - units.gu(2)
                    Label { text: "Bottom dock"; color: "white" }
                    Label {
                        text: "Up to 5 apps. Drag any tile to the dock. Turning this off returns dock apps to the last page."
                        color: "#9fa9c0"
                        fontSize: "small"
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
                Switch {
                    id: dockSwitch
                    checked: root.dockEnabled
                    anchors.verticalCenter: parent.verticalCenter
                    onCheckedChanged: {
                        if (checked !== root.dockEnabled) root.dockToggled(checked);
                    }
                }
            }

            // ---- Layout mode selector ----
            Column {
                width: parent.width
                spacing: units.gu(0.5)
                Label { text: "Layout"; color: "white" }
                Label {
                    text: "How icons are placed. Switching modes saves your current layout, so you can flip back without losing it."
                    color: "#9fa9c0"
                    fontSize: "small"
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Column {
                    width: parent.width
                    spacing: units.gu(0.5)
                    Repeater {
                        model: [
                            { key: "autoFill", title: "Auto-fill",     blurb: "Icons flow left to right, no gaps." },
                            { key: "snap",     title: "Snap to grid",  blurb: "Place icons on any grid cell; gaps OK." },
                            { key: "free",     title: "Place anywhere", blurb: "No grid; icons go anywhere you drop them." }
                        ]
                        delegate: Rectangle {
                            width: parent.width
                            height: optRow.implicitHeight + units.gu(1.5)
                            radius: units.gu(1)
                            color: root.placementMode === modelData.key ? "#3d5af1" : "#1d2540"
                            border.color: root.placementMode === modelData.key ? "white" : "#3a456a"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (modelData.key !== root.placementMode) {
                                        root.placementModeAdjusted(modelData.key);
                                    }
                                }
                            }
                            Row {
                                id: optRow
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(1.5); rightMargin: units.gu(1.5)
                                }
                                spacing: units.gu(1)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(1.4); height: width
                                    radius: width / 2
                                    color: root.placementMode === modelData.key ? "white" : "transparent"
                                    border.color: "white"
                                    border.width: 1
                                }
                                Column {
                                    width: parent.width - units.gu(2.4)
                                    Label {
                                        text: modelData.title
                                        color: "white"
                                        font.bold: true
                                    }
                                    Label {
                                        text: modelData.blurb
                                        color: "#cad2e8"
                                        fontSize: "small"
                                        wrapMode: Text.WordWrap
                                        width: parent.width
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- Dock background height slider ----
            Column {
                width: parent.width
                spacing: units.gu(0.5)
                visible: root.dockEnabled
                Label { text: "Dock background height"; color: "white" }
                Label {
                    text: "Thin line under the icons → full wrap around them."
                    color: "#9fa9c0"
                    fontSize: "small"
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
                Slider {
                    width: parent.width
                    minimumValue: 1.0
                    maximumValue: 12.0
                    value: root.dockBgHeight
                    live: true
                    function formatValue(v) { return Number(v).toFixed(1) + " gu"; }
                    onValueChanged: {
                        if (Math.abs(value - root.dockBgHeight) > 0.01) {
                            root.dockBgHeightAdjusted(value);
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                Button {
                    text: "Done"
                    color: "#3d5af1"
                    onClicked: root.visible = false
                }
            }
        }
    }
}
