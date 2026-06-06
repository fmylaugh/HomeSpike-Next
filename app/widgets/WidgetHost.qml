/**
 * @file WidgetHost
 * @description The widget analogue of TileBody: the interaction + edit-mode
 *   chrome wrapped around a loaded widget. It loads the concrete widget for
 *   `widgetType` from the catalog, injects its clock/variant/settings, shows
 *   the edit-mode remove ("×") and settings ("⚙") badges plus the jiggle, and
 *   routes drag gestures into the shared DragController (drag key = widgetId).
 *
 *   Like TileBody, the full-bleed drag MouseArea is declared FIRST so the
 *   later-declared badge MouseAreas win on their own hit areas while the rest
 *   of the surface falls through to the drag handler.
 *
 *   Widgets are display-only in v1 — a tap does nothing; long-press outside
 *   edit mode asks the parent to enter edit mode.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: host

    // ---- Identity + content (set by the delegate from the model row) ----
    property string widgetId: ""
    property string widgetType: ""
    property string widgetVariant: ""
    property string widgetSettings: ""   // JSON {background, colors:{slot:hex}}

    // ---- Drag source hints ----
    property int sourcePage: -1
    property int indexInModel: -1

    // ---- Injected dependencies ----
    property bool editMode: false
    property var controller: null
    property var clock: null
    property var catalog: null
    /** Shared weather data layer — injected into widgets that expose a
     *  `service` property (the weather widget); ignored by the rest. */
    property var weatherService: null
    /** Shared system-info source — injected into widgets that expose a
     *  `sysInfo` property (the system-info widget); ignored by the rest. */
    property var sysInfoService: null
    /** Shared real-time monitor source — injected into widgets that expose a
     *  `monitor` property (the system-monitor widget); ignored by the rest. */
    property var sysMonitorService: null

    /** Device orientation angle (deg). The widget's box stays put in the
     *  (portrait) grid; its CONTENT rotates by this so it stays upright as the
     *  phone turns. At 90/270 the content is laid out in the box's swapped
     *  dimensions so it still fills the box. 0 in portrait. */
    property int contentAngle: 0

    /** Tap the "×" badge — remove this widget. */
    signal removeRequested(string widgetId)
    /** Tap the "⚙" badge — open this widget's settings sheet. */
    signal settingsRequested(string widgetId)
    /** Long-press outside edit mode — parent should enter edit mode. */
    signal editModeRequested()

    // Parsed settings with catalog fallbacks.
    readonly property var _settings: {
        try { var o = JSON.parse(widgetSettings || "{}"); return (o && typeof o === "object") ? o : {}; }
        catch (e) { return {}; }
    }
    readonly property var _defaults: catalog ? catalog.defaultsFor(widgetType) : { background: true }
    readonly property bool _background: _settings.background !== undefined ? _settings.background : _defaults.background

    // Complete per-section colour map = catalog defaults with saved overrides
    // merged on top, so the widget always reads every slot it needs.
    readonly property var _colors: {
        var out = {};
        var defs = catalog ? catalog.colorDefaults(widgetType) : {};
        for (var k in defs) out[k] = defs[k];
        var saved = _settings.colors || {};
        for (var s in saved) out[s] = saved[s];
        return out;
    }

    // ============================================================
    // Drag MouseArea (declared FIRST — see file header)
    // ============================================================
    MouseArea {
        id: hostMouse
        anchors.fill: parent
        pressAndHoldInterval: 400
        preventStealing: host.editMode

        property real pressX: 0
        property real pressY: 0
        property bool dragStarted: false
        readonly property real dragThreshold: units.gu(2)

        onPressAndHold: { if (!host.editMode) host.editModeRequested(); }
        // Outside edit mode, a tap asks the widget to refresh (if it offers a
        // handleTap hook — the weather widget does). A drag/long-press won't fire
        // onClicked, so this only catches genuine taps.
        onClicked: {
            if (host.editMode) return;
            var w = widgetLoader.item;
            if (w && w.handleTap) w.handleTap();
        }
        onPressed: {
            pressX = mouseX; pressY = mouseY; dragStarted = false;
            if (controller && controller.dragging) controller.abort();
        }
        onPositionChanged: {
            if (!host.editMode || !controller) return;
            var dx = mouseX - pressX, dy = mouseY - pressY;
            if (!dragStarted) {
                if (Math.sqrt(dx * dx + dy * dy) < dragThreshold) return;
                dragStarted = true;
                var sp = mapToItem(controller, mouseX, mouseY);
                // Key is the widgetId; name/icon unused for widgets (the
                // floating visual draws a footprint-sized ghost instead).
                controller.startDrag("grid", host.sourcePage, host.indexInModel,
                                     host.widgetId, "", "", sp.x, sp.y);
            }
            var pt = mapToItem(controller, mouseX, mouseY);
            controller.moveDrag(pt.x, pt.y);
        }
        onReleased: { if (controller && controller.dragging) controller.endDrag(); dragStarted = false; }
        onCanceled: { if (controller && controller.dragging) controller.endDrag(); dragStarted = false; }
    }

    // ============================================================
    // Content: the loaded widget. The box stays put in the (portrait) grid;
    // contentRot re-orients the content as the phone turns, and jiggleWrap
    // does the edit-mode rock independently so the two don't fight.
    // ============================================================
    Item {
        id: contentRot
        anchors.centerIn: parent
        // At 90/270 lay the content out in the box's SWAPPED dimensions, then
        // rotate it to fill the box — so a wide widget turns upright and still
        // fits its (unchanged) grid footprint.
        readonly property bool _swapped: (host.contentAngle % 180) !== 0
        width:  _swapped ? host.height : host.width
        height: _swapped ? host.width  : host.height
        rotation: host.contentAngle
        Behavior on rotation { RotationAnimation { duration: 250; direction: RotationAnimation.Shortest } }

        Item {
            id: jiggleWrap
            anchors.fill: parent

            Loader {
                id: widgetLoader
                anchors.fill: parent
                sourceComponent: host.catalog ? host.catalog.componentFor(host.widgetType) : null
                onLoaded: _apply()

                function _apply() {
                    if (!item) return;
                    item.clock = host.clock;
                    item.variant = host.widgetVariant;
                    item.background = host._background;
                    item.colors = host._colors;
                    item.settings = host._settings;
                    // Inject shared data layers only into widgets that want them.
                    if (item.hasOwnProperty("service")) item.service = host.weatherService;
                    if (item.hasOwnProperty("sysInfo")) item.sysInfo = host.sysInfoService;
                    if (item.hasOwnProperty("monitor")) item.monitor = host.sysMonitorService;
                }
            }

            // Re-push settings/variant when they change (no component reload).
            Connections {
                target: host
                function onWidgetVariantChanged()  { widgetLoader._apply(); }
                function onWidgetSettingsChanged()  { widgetLoader._apply(); }
            }

            // Edit-mode jiggle (mirrors TileBody): a small side-to-side rock,
            // paused while a drag is in flight, snapped upright when edit ends.
            SequentialAnimation {
                running: host.editMode && (!controller || !controller.dragging)
                PauseAnimation { duration: Math.round(Math.random() * 140) }
                SequentialAnimation {
                    loops: Animation.Infinite
                    NumberAnimation { target: jiggleWrap; property: "rotation"; from: -2; to: 2; duration: 160; easing.type: Easing.InOutSine }
                    NumberAnimation { target: jiggleWrap; property: "rotation"; from: 2; to: -2; duration: 160; easing.type: Easing.InOutSine }
                }
                onStopped: jiggleWrap.rotation = 0
            }
        }
    }

    // ============================================================
    // Edit badges (declared AFTER content so they win their hit areas).
    // ============================================================
    // Remove ("×") — top-left, white circle / dark glyph (matches TileBody).
    // Both badges are inset INSIDE the widget bounds (no negative overhang) so
    // they're never cropped by pagesView's clip on the top row, and adjacent
    // widgets' badges don't collide across the shared column boundary.
    Rectangle {
        visible: host.editMode
        z: 30
        anchors { top: parent.top; left: parent.left; topMargin: units.gu(0.3); leftMargin: units.gu(0.3) }
        width: units.gu(2.8); height: width; radius: width / 2
        color: "white"; border.color: "#202840"; border.width: 1
        Text {
            anchors.centerIn: parent
            text: "×"; color: "#202840"; font.pixelSize: parent.height * 0.8; font.bold: true
        }
        MouseArea {
            anchors.fill: parent; anchors.margins: -units.gu(0.5)
            onClicked: host.removeRequested(host.widgetId)
        }
    }

    // Settings ("⚙") — top-right, dark circle / white cog SVG.
    Rectangle {
        visible: host.editMode
        z: 30
        anchors { top: parent.top; right: parent.right; topMargin: units.gu(0.3); rightMargin: units.gu(0.3) }
        width: units.gu(2.8); height: width; radius: width / 2
        color: "#262d4d"; border.color: "white"; border.width: 1
        Icon {
            anchors.centerIn: parent
            width: parent.width * 0.6; height: width
            source: "../icons/cogs.svg"
        }
        MouseArea {
            anchors.fill: parent; anchors.margins: -units.gu(0.5)
            onClicked: host.settingsRequested(host.widgetId)
        }
    }
}
