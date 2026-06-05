/**
 * @file ColorPicker
 * @description Self-contained HSV colour picker with alpha. A saturation/value
 *   square over a hue slider and an alpha slider, plus manual entry: an
 *   editable hex field (#RRGGBB or #AARRGGBB) and R/G/B/A number boxes — so
 *   colours can be matched exactly between sections by copying values.
 *
 *   Built in-process (no native ColorDialog window) so it works inside the
 *   Lomiri shell layer. Tracks H/S/V/A internally so dragging value/sat to the
 *   extremes (or entering greys) doesn't lose the chosen hue.
 *
 *   Set `color` to seed it; it emits `edited(color)` as the user changes
 *   anything. Manual fields apply on Enter or when focus leaves them.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: picker

    /** Two-way-ish: assign to seed, read for the result. */
    property color color: "#ffffff"

    /** Emitted whenever the user changes the colour (live). */
    signal edited(color c)

    implicitHeight: contentCol.implicitHeight

    // Internal HSVA (each 0..1). Kept separate from `color` so greys / extremes
    // don't collapse the hue.
    property real _h: 0
    property real _s: 0
    property real _v: 1
    property real _a: 1
    property bool _seeding: false

    // ---- hex helpers ----
    function _chan(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s; }
    function _hexOf(c) {
        var a = Math.round(c.a * 255);
        var rgb = _chan(c.r) + _chan(c.g) + _chan(c.b);
        return ("#" + (a < 255 ? _chan(c.a) + rgb : rgb)).toUpperCase();
    }

    // Decompose a colour into H/S/V/A (keeps the current hue when achromatic).
    function _decompose(c) {
        picker.color = c;
        var col = picker.color;
        var hh = col.hsvHue;
        if (hh >= 0) _h = hh;
        _s = col.hsvSaturation;
        _v = col.hsvValue;
        _a = col.a;
    }

    /** Seed from an incoming colour or hex string (no emit). */
    function seed(c) {
        _seeding = true;
        _decompose(c);
        _syncFields();
        _seeding = false;
    }

    // Rebuild the colour from the sliders/square and emit.
    function _recompose() {
        if (_seeding) return;
        picker.color = Qt.hsva(_h, _s, _v, _a);
        _syncFields();
        edited(picker.color);
    }

    // Apply a colour entered manually (hex / rgba) and emit.
    function _applyManual(c) {
        _seeding = true;
        _decompose(c);
        _seeding = false;
        _syncFields();
        edited(picker.color);
    }

    // Push current colour into the text fields (skip any the user is editing
    // or not yet created).
    function _syncFields() {
        if (!hexField.activeFocus) hexField.text = _hexOf(picker.color);
        if (rField && !rField.activeFocus) rField.text = Math.round(picker.color.r * 255);
        if (gField && !gField.activeFocus) gField.text = Math.round(picker.color.g * 255);
        if (bField && !bField.activeFocus) bField.text = Math.round(picker.color.b * 255);
        if (aField && !aField.activeFocus) aField.text = Math.round(picker.color.a * 255);
    }

    function _clamp255(t) { var n = parseInt(t, 10); if (isNaN(n)) n = 0; return Math.max(0, Math.min(255, n)); }

    function _applyHex() {
        var t = hexField.text.trim();
        if (t.charAt(0) === "#") t = t.substring(1);
        if (!/^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(t)) { _syncFields(); return; }  // revert invalid
        _applyManual("#" + t);   // Qt parses #RRGGBB and #AARRGGBB
    }
    function _applyRgba() {
        _applyManual(Qt.rgba(_clamp255(rField.text) / 255, _clamp255(gField.text) / 255,
                             _clamp255(bField.text) / 255, _clamp255(aField.text) / 255));
    }

    Component.onCompleted: seed(color)

    Column {
        id: contentCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: units.gu(1.5)

        // Preview (over a checkerboard so alpha is visible) + editable hex.
        Row {
            width: parent.width
            spacing: units.gu(1.5)
            Item {
                width: units.gu(4); height: units.gu(4)
                Canvas {
                    anchors.fill: parent
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d"); var s = units.gu(0.7);
                        for (var y = 0; y < height; y += s)
                            for (var x = 0; x < width; x += s) {
                                ctx.fillStyle = ((Math.round(x / s) + Math.round(y / s)) % 2 === 0) ? "#bbbbbb" : "#ffffff";
                                ctx.fillRect(x, y, s, s);
                            }
                    }
                }
                Rectangle { anchors.fill: parent; radius: units.gu(0.5); color: picker.color; border.color: "#3a456a"; border.width: 1 }
            }
            TextField {
                id: hexField
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - units.gu(4) - units.gu(1.5)
                maximumLength: 9
                inputMethodHints: Qt.ImhNoPredictiveText
                onAccepted: picker._applyHex()
                onActiveFocusChanged: if (!activeFocus) picker._applyHex()
            }
        }

        // Saturation (x) / Value (y) square.
        Rectangle {
            id: svSquare
            width: parent.width
            height: units.gu(20)
            radius: units.gu(0.5)
            color: Qt.hsva(picker._h, 1, 1, 1)
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#ffffffff" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#ff000000" }
                }
            }
            Rectangle {
                width: units.gu(2); height: width; radius: width / 2
                color: "transparent"; border.color: "white"; border.width: 2
                x: picker._s * parent.width - width / 2
                y: (1 - picker._v) * parent.height - height / 2
            }
            MouseArea {
                anchors.fill: parent
                function setAt(mx, my) {
                    picker._s = Math.max(0, Math.min(1, mx / width));
                    picker._v = Math.max(0, Math.min(1, 1 - my / height));
                    picker._recompose();
                }
                onPressed: setAt(mouse.x, mouse.y)
                onPositionChanged: setAt(mouse.x, mouse.y)
            }
        }

        // Hue slider.
        Rectangle {
            id: hueSlider
            width: parent.width
            height: units.gu(3)
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.000; color: "#ff0000" }
                GradientStop { position: 0.167; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.500; color: "#00ffff" }
                GradientStop { position: 0.667; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1.000; color: "#ff0000" }
            }
            Rectangle {
                width: units.gu(1.4); height: parent.height + units.gu(0.8)
                radius: units.gu(0.4); color: "white"; border.color: "#202840"; border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                x: picker._h * parent.width - width / 2
            }
            MouseArea {
                anchors.fill: parent
                function setAt(mx) { picker._h = Math.max(0, Math.min(1, mx / width)); picker._recompose(); }
                onPressed: setAt(mouse.x)
                onPositionChanged: setAt(mouse.x)
            }
        }

        // Alpha slider — transparent → opaque current colour, over a checker.
        Item {
            width: parent.width
            height: units.gu(3)
            Canvas {
                anchors.fill: parent
                Component.onCompleted: requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); var s = units.gu(0.7);
                    for (var y = 0; y < height; y += s)
                        for (var x = 0; x < width; x += s) {
                            ctx.fillStyle = ((Math.round(x / s) + Math.round(y / s)) % 2 === 0) ? "#bbbbbb" : "#ffffff";
                            ctx.fillRect(x, y, s, s);
                        }
                }
            }
            Rectangle {
                id: alphaSlider
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.hsva(picker._h, picker._s, picker._v, 0) }
                    GradientStop { position: 1.0; color: Qt.hsva(picker._h, picker._s, picker._v, 1) }
                }
                Rectangle {
                    width: units.gu(1.4); height: parent.height + units.gu(0.8)
                    radius: units.gu(0.4); color: "white"; border.color: "#202840"; border.width: 1
                    anchors.verticalCenter: parent.verticalCenter
                    x: picker._a * parent.width - width / 2
                }
                MouseArea {
                    anchors.fill: parent
                    function setAt(mx) { picker._a = Math.max(0, Math.min(1, mx / width)); picker._recompose(); }
                    onPressed: setAt(mouse.x)
                    onPositionChanged: setAt(mouse.x)
                }
            }
        }

        // Manual R / G / B / A entry (0–255).
        Row {
            width: parent.width
            spacing: units.gu(1)
            Repeater {
                model: [ { id: "r" }, { id: "g" }, { id: "b" }, { id: "a" } ]
                delegate: Column {
                    width: (parent.width - units.gu(3)) / 4
                    spacing: units.gu(0.3)
                    Label { text: modelData.id.toUpperCase(); color: "#9fa9c0"; fontSize: "small" }
                    TextField {
                        width: parent.width
                        maximumLength: 3
                        inputMethodHints: Qt.ImhDigitsOnly
                        // Bind each field to its own id via the shared ids below.
                        property string channel: modelData.id
                        Component.onCompleted: {
                            if (channel === "r") picker.rField = this;
                            else if (channel === "g") picker.gField = this;
                            else if (channel === "b") picker.bField = this;
                            else picker.aField = this;
                        }
                        onAccepted: picker._applyRgba()
                        onActiveFocusChanged: if (!activeFocus) picker._applyRgba()
                    }
                }
            }
        }
    }

    // Field handles (assigned by the Repeater delegates above).
    property var rField: null
    property var gField: null
    property var bField: null
    property var aField: null
}
