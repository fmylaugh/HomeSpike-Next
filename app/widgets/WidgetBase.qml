/**
 * @file WidgetBase
 * @description Common base for every HomeSpike widget. Provides the shared
 *   per-widget settings (background plate on/off, per-section colours), the injected
 *   locale clock, and the active size variant. Concrete widgets (ClockWidget,
 *   CalendarWidget) just declare their content as children — those children
 *   are drawn ABOVE the background plate, which sits at z:-1.
 *
 *   No `default property alias` is used on purpose: a child slot aliased over
 *   the root's own children would try to reparent the plate into itself. Plain
 *   z-ordering (plate at z:-1) keeps it simple and cycle-free.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: base

    /** Whether to draw the background plate. When false the widget's content
     *  sits directly over the wallpaper. */
    property bool background: true

    /** Per-section colours, keyed by slot (e.g. "time", "month", "day",
     *  "background"). WidgetHost injects a complete map (catalog defaults +
     *  user overrides); concrete widgets read slots via colorOf(). */
    property var colors: ({})

    /** Injected LocaleClock — time source + locale/12-24h formatting. */
    property var clock: null

    /** Active size variant key (e.g. "wide" / "small"); concrete widgets read
     *  this to switch their internal layout. */
    property string variant: ""

    /** Colour for a section slot, with a fallback if unset/empty. */
    function colorOf(key, fallback) {
        return (colors && colors[key] !== undefined && colors[key] !== "") ? colors[key] : fallback;
    }

    // Background plate — behind all content (z:-1). Toggled by `background`,
    // tinted by the "background" colour slot.
    Rectangle {
        id: plate
        anchors.fill: parent
        z: -1
        visible: base.background
        radius: units.gu(2)
        color: base.colorOf("background", "#cc11162b")
    }
}
