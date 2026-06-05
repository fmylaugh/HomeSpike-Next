/**
 * @file WidgetPickerOverlay
 * @description Edit-mode modal for adding a widget. Shows a card per catalog
 *   variant (a live, non-interactive preview + title); tapping one emits
 *   `chosen(type, variant)` and closes. Widgets live only in the Snap-to-grid
 *   and Place-anywhere layouts, so in Auto-fill the picker shows a hint instead
 *   of the grid.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    /** Injected: WidgetCatalog (entries + preview components) and the shared
     *  LocaleClock so previews render real content. */
    property var catalog: null
    property var clock: null

    /** Active placement mode — widgets need "snap" or "free". */
    property string placementMode: "autoFill"
    readonly property bool _supported: placementMode === "snap" || placementMode === "free"

    /** Px width of the launcher panel overlapping us — keep the card centered
     *  in the visible content area (matches the other overlays). */
    property real leftReserve: 0

    /** Emitted when the user picks a widget to add. */
    signal chosen(string type, string variant)

    anchors.fill: parent
    z: 905
    visible: false
    color: "#aa000000"

    function open() { visible = true; }

    MouseArea { anchors.fill: parent; onClicked: root.visible = false }

    Rectangle {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.9, units.gu(60))
        height: col.height + units.gu(4)
        radius: units.gu(2)
        color: "#262d4d"

        MouseArea { anchors.fill: parent }   // swallow taps so they don't close

        Column {
            id: col
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(2); rightMargin: units.gu(2)
            }
            spacing: units.gu(2)

            Label {
                text: "Add widget"
                color: "white"; font.bold: true; fontSize: "large"
            }

            // ---- Auto-fill hint ----
            Label {
                visible: !root._supported
                width: parent.width
                text: "Widgets need the Snap to grid or Place anywhere layout. "
                      + "Switch layout in HomeSpike Settings, then add a widget."
                color: "#9fa9c0"
                wrapMode: Text.WordWrap
            }

            // ---- Widget cards ----
            Flow {
                visible: root._supported
                width: parent.width
                spacing: units.gu(2)

                Repeater {
                    model: root._supported && root.catalog ? root.catalog.pickerEntries() : []
                    delegate: Rectangle {
                        width: units.gu(20)
                        // Preview keeps the widget's aspect (w:h cells).
                        height: units.gu(20) * (modelData.h / modelData.w) * 0.62 + units.gu(4)
                        radius: units.gu(1.5)
                        color: "#1d2540"
                        border.color: "#3a456a"; border.width: 1

                        Column {
                            anchors.fill: parent
                            anchors.margins: units.gu(1)
                            spacing: units.gu(0.8)

                            // Live preview — the widget is rendered at its
                            // natural footprint size, then scaled down to fit
                            // the card so its text shrinks proportionally
                            // instead of clipping.
                            Item {
                                id: previewBox
                                width: parent.width
                                height: parent.height - title.height - parent.spacing
                                clip: true
                                Item {
                                    id: natural
                                    width: modelData.w * units.gu(11)
                                    height: modelData.h * units.gu(11)
                                    anchors.centerIn: parent
                                    scale: Math.min(previewBox.width / width, previewBox.height / height)
                                    Loader {
                                        anchors.fill: parent
                                        sourceComponent: root.catalog ? root.catalog.componentFor(modelData.type) : null
                                        onLoaded: {
                                            if (!item) return;
                                            item.clock = root.clock;
                                            item.variant = modelData.variant;
                                            item.background = true;
                                            item.colors = root.catalog ? root.catalog.colorDefaults(modelData.type) : ({});
                                        }
                                    }
                                }
                            }

                            Label {
                                id: title
                                width: parent.width
                                text: modelData.title
                                color: "white"
                                fontSize: "small"
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.chosen(modelData.type, modelData.variant);
                                root.visible = false;
                            }
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                Button { text: "Close"; color: "#3d5af1"; onClicked: root.visible = false }
            }
        }
    }
}
