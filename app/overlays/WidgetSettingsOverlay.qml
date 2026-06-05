/**
 * @file WidgetSettingsOverlay
 * @description Per-widget settings sheet, opened from a widget's edit-mode "⚙"
 *   badge. Two panes inside one card:
 *     • list   — background on/transparent, a colour row per visible section
 *                (Time, Date, Month, Day, …) each with a swatch, and the size
 *                preset selector.
 *     • picker — an HSV ColorPicker for the section the user tapped.
 *   Colour edits apply live to the model (so the widget repaints as you drag)
 *   and are persisted once when the picker closes. Background toggle and size
 *   preset persist immediately.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    /** Injected: PageModelRegistry (mutators) + WidgetCatalog (slots/variants). */
    property var pages: null
    property var catalog: null

    property real leftReserve: 0

    // Current widget being edited.
    property string widgetId: ""
    property string widgetType: ""
    property string widgetVariant: ""
    property bool background: true
    // Effective {slot → colour} map (catalog defaults + saved overrides).
    property var colors: ({})

    // "" = section list; otherwise the slot key being colour-picked.
    property string editingSlot: ""
    property string editingLabel: ""

    readonly property var _variants: (catalog && widgetType && catalog.typeDef(widgetType))
                                      ? catalog.typeDef(widgetType).variants : []
    readonly property var _slots: (catalog && widgetType)
                                  ? catalog.colorSlotsFor(widgetType, widgetVariant) : []

    anchors.fill: parent
    z: 910
    visible: false
    color: "#aa000000"

    function _hex(c) {
        function h(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s; }
        var a = Math.round(c.a * 255);
        var rgb = h(c.r) + h(c.g) + h(c.b);
        return "#" + (a < 255 ? h(c.a) + rgb : rgb);   // #AARRGGBB when translucent
    }

    /** Populate from the live widget row and show (list pane). */
    function open(id) {
        if (!pages) return;
        var info = pages.widgetInfo(id);
        if (!info) return;
        widgetId = id;
        widgetType = info.type;
        widgetVariant = info.variant;
        background = (info.settings.background !== undefined) ? info.settings.background : true;

        var eff = {};
        var defs = catalog ? catalog.colorDefaults(info.type) : {};
        for (var k in defs) eff[k] = defs[k];
        var saved = info.settings.colors || {};
        for (var s in saved) eff[s] = saved[s];
        colors = eff;

        editingSlot = "";
        visible = true;
    }

    function _openPicker(slot, label) {
        editingSlot = slot;
        editingLabel = label;
        colorPicker.seed(colors[slot] !== undefined ? colors[slot] : "#ffffff");
    }

    function _applyPicked(c) {
        var hex = _hex(c);
        var nc = {};
        for (var k in colors) nc[k] = colors[k];
        nc[editingSlot] = hex;
        colors = nc;                                   // refresh swatches
        if (pages) pages.setWidgetColor(widgetId, editingSlot, hex);   // live, no persist
    }

    function _closePicker() {
        editingSlot = "";
        if (pages) pages.persistOrder();               // commit the colour change
    }

    // Persist any live (un-committed) colour preview if the sheet is dismissed
    // by tapping outside while still in the picker.
    onVisibleChanged: { if (!visible && pages) pages.persistOrder(); }

    MouseArea { anchors.fill: parent; onClicked: root.visible = false }

    Rectangle {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.85, units.gu(48))
        height: Math.min(parent.height * 0.9, inner.implicitHeight + units.gu(4))
        radius: units.gu(2)
        color: "#262d4d"

        MouseArea { anchors.fill: parent }

        Flickable {
            anchors.fill: parent
            anchors.margins: units.gu(2)
            contentHeight: inner.implicitHeight
            clip: true
            interactive: contentHeight > height

            Item {
                id: inner
                width: parent.width
                // A Column skips invisible children, so implicitHeight tracks
                // whichever pane is showing.
                implicitHeight: (root.editingSlot === "") ? listCol.implicitHeight
                                                          : pickerCol.implicitHeight

                // ---------------- list pane ----------------
                Column {
                    id: listCol
                    visible: root.editingSlot === ""
                    width: parent.width
                    spacing: units.gu(2)

                    Label { text: "Widget settings"; color: "white"; font.bold: true; fontSize: "large" }

                    // Background on/off.
                    Row {
                        width: parent.width
                        spacing: units.gu(2)
                        Column {
                            width: parent.width - bgSwitch.width - units.gu(2)
                            Label { text: "Background"; color: "white" }
                            Label {
                                text: "Show a plate behind the widget, or let it sit transparent over the wallpaper."
                                color: "#9fa9c0"; fontSize: "small"; wrapMode: Text.WordWrap; width: parent.width
                            }
                        }
                        Switch {
                            id: bgSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.background
                            onCheckedChanged: {
                                if (checked === root.background) return;
                                root.background = checked;
                                if (root.pages) root.pages.updateWidgetSettings(root.widgetId, { background: checked });
                            }
                        }
                    }

                    Label { text: "Colours"; color: "white"; font.bold: true }

                    // Background colour (only when the plate is shown) + one
                    // row per visible section.
                    Column {
                        width: parent.width
                        spacing: units.gu(1)

                        // Background colour row.
                        WidgetColorRow {
                            visible: root.background
                            width: parent.width
                            label: "Background"
                            swatch: root.colors["background"] !== undefined ? root.colors["background"] : "#cc11162b"
                            onTapped: root._openPicker("background", "Background")
                        }

                        Repeater {
                            model: root._slots
                            delegate: WidgetColorRow {
                                width: parent.width
                                label: modelData.label
                                swatch: root.colors[modelData.key] !== undefined ? root.colors[modelData.key] : modelData.def
                                onTapped: root._openPicker(modelData.key, modelData.label)
                            }
                        }
                    }

                    // Size preset.
                    Column {
                        visible: root._variants.length > 1
                        width: parent.width
                        spacing: units.gu(1)
                        Label { text: "Size"; color: "white"; font.bold: true }
                        Row {
                            spacing: units.gu(1)
                            Repeater {
                                model: root._variants
                                delegate: Rectangle {
                                    height: units.gu(4.5)
                                    width: sizeLabel.width + units.gu(3)
                                    radius: units.gu(1)
                                    color: root.widgetVariant === modelData.key ? "#3d5af1" : "#1d2540"
                                    border.color: root.widgetVariant === modelData.key ? "white" : "#3a456a"
                                    border.width: 1
                                    Label {
                                        id: sizeLabel
                                        anchors.centerIn: parent
                                        text: modelData.key + "  " + modelData.w + "×" + modelData.h
                                        color: "white"; fontSize: "small"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.widgetVariant === modelData.key) return;
                                            root.widgetVariant = modelData.key;
                                            if (root.pages) root.pages.setWidgetVariant(root.widgetId, modelData.key);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        Button { text: "Done"; color: "#3d5af1"; onClicked: root.visible = false }
                    }
                }

                // ---------------- picker pane ----------------
                Column {
                    id: pickerCol
                    visible: root.editingSlot !== ""
                    width: parent.width
                    spacing: units.gu(2)

                    Row {
                        width: parent.width
                        spacing: units.gu(1)
                        Rectangle {
                            width: units.gu(4); height: units.gu(4); radius: width / 2
                            color: "#1d2540"
                            Label { anchors.centerIn: parent; text: "‹"; color: "white"; fontSize: "large" }
                            MouseArea { anchors.fill: parent; onClicked: root._closePicker() }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.editingLabel
                            color: "white"; font.bold: true; fontSize: "large"
                        }
                    }

                    ColorPicker {
                        id: colorPicker
                        width: parent.width
                        onEdited: (c) => root._applyPicked(c)
                    }

                    Row {
                        anchors.right: parent.right
                        Button { text: "Done"; color: "#3d5af1"; onClicked: root._closePicker() }
                    }
                }
            }
        }
    }
}
