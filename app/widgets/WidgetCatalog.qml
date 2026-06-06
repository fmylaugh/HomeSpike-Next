/**
 * @file WidgetCatalog
 * @description The widget API surface: a declarative registry of every
 *   available widget type, its size variants (footprint in grid cells), its
 *   default per-widget settings, and the Component used to instantiate it.
 *   WidgetHost, the picker, and the per-widget settings sheet all read from
 *   here — adding a new widget is one array entry plus one QML file.
 *
 *   One instance lives in main.qml and is injected into PageModelRegistry
 *   (which needs variant footprints + defaults) and WidgetHost (which needs
 *   the Component to load).
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15

Item {
    id: catalog

    // Components wrapping the concrete widgets (same directory → resolved by
    // type name without an explicit import).
    Component { id: clockComponent;    ClockWidget {} }
    Component { id: calendarComponent; CalendarWidget {} }
    Component { id: weatherComponent;  WeatherWidget {} }
    Component { id: sysInfoComponent;  SysInfoWidget {} }
    Component { id: photoComponent;    PhotoWidget {} }
    Component { id: sysMonComponent;   SysMonitorWidget {} }

    /** Default plate colour (translucent navy) — the universal "background"
     *  colour slot every widget has. */
    readonly property string defaultBackground: "#cc11162b"

    /**
     * The registry. Each type:
     *   type       stable key persisted in pageData
     *   title      display name (picker / settings sheet)
     *   variants   size presets — {key, w, h} in grid cells; first is default
     *   defaults   initial per-widget settings {background}
     *   colorSlots per-section colour controls — {key, label, def, variants[]}
     *              where `variants` lists which size presets the section
     *              applies to (so the settings sheet only shows relevant ones)
     *   component  Component instantiated by WidgetHost
     */
    readonly property var types: [
        {
            type: "clock", title: "Clock",
            variants: [ { key: "wide", w: 4, h: 2 }, { key: "small", w: 2, h: 2 } ],
            defaults: { background: true },
            colorSlots: [
                { key: "time", label: "Time", def: "#ffffff", variants: ["wide", "small"] },
                { key: "date", label: "Date", def: "#ffffff", variants: ["wide"] }
            ],
            component: clockComponent
        },
        {
            type: "calendar", title: "Calendar",
            variants: [ { key: "small", w: 2, h: 2 }, { key: "wide", w: 4, h: 3 } ],
            defaults: { background: true },
            colorSlots: [
                { key: "month",   label: "Month",          def: "#e94560", variants: ["small"] },
                { key: "day",     label: "Day",            def: "#ffffff", variants: ["small", "wide"] },
                { key: "weekday", label: "Weekday",        def: "#e94560", variants: ["wide"] },
                { key: "header",  label: "Weekday labels", def: "#9fa9c0", variants: ["wide"] },
                { key: "dates",   label: "Dates",          def: "#ffffff", variants: ["wide"] },
                { key: "today",   label: "Today",          def: "#ffffff", variants: ["wide"] }
            ],
            component: calendarComponent
        },
        {
            type: "weather", title: "Weather",
            variants: [ { key: "small", w: 2, h: 2 }, { key: "wide", w: 4, h: 2 } ],
            // unit "" = follow the system locale; city/lat/lon set in settings.
            defaults: { background: true, unit: "", city: "", lat: null, lon: null },
            colorSlots: [
                { key: "temp",         label: "Temperature",   def: "#ffffff", variants: ["small", "wide"] },
                { key: "place",        label: "Location",      def: "#9fa9c0", variants: ["small", "wide"] },
                { key: "condition",    label: "Condition",     def: "#9fa9c0", variants: ["wide"] },
                { key: "hour",         label: "Forecast time", def: "#9fa9c0", variants: ["wide"] },
                { key: "forecastTemp", label: "Forecast temp", def: "#ffffff", variants: ["wide"] }
            ],
            // Non-colour settings rendered by WidgetSettingsOverlay. `def` is the
            // value shown selected when the setting is unset.
            options: [
                { key: "city", kind: "place", label: "City" },
                { key: "unit", kind: "segmented", label: "Units", def: "",
                  choices: [ { v: "", t: "Auto" }, { v: "C", t: "°C" }, { v: "F", t: "°F" } ] },
                { key: "refresh", kind: "segmented", label: "Auto-refresh", def: 30,
                  choices: [ { v: 0, t: "Off" }, { v: 15, t: "15m" }, { v: 30, t: "30m" },
                             { v: 60, t: "1h" }, { v: 180, t: "3h" } ] }
            ],
            component: weatherComponent
        },
        {
            type: "sysinfo", title: "System Info",
            // One size — it's an inherently wide, info-dense widget.
            variants: [ { key: "default", w: 4, h: 3 } ],
            defaults: { background: true },
            // Every element is individually recolourable (slots apply to the
            // single variant, so no `variants` filter needed).
            colorSlots: [
                { key: "ascii",   label: "Logo",     def: "#e95420" },
                { key: "user",    label: "User",     def: "#e06c9a" },
                { key: "host",    label: "Host",     def: "#e5c07b" },
                { key: "uptime",  label: "Uptime",   def: "#61afef" },
                { key: "distro",  label: "Distro",   def: "#98c379" },
                { key: "kernel",  label: "Kernel",   def: "#c678dd" },
                { key: "desktop", label: "Desktop",  def: "#56b6c2" },
                { key: "shell",   label: "Shell",    def: "#c678dd" },
                { key: "value",   label: "Values",   def: "#ffffff" },
                { key: "border",  label: "Border",   def: "#3a4262" }
            ],
            component: sysInfoComponent
        },
        {
            type: "photo", title: "Photo",
            // Two clock-style sizes plus a tall portrait one.
            variants: [ { key: "small", w: 2, h: 2 }, { key: "wide", w: 4, h: 2 },
                        { key: "tall", w: 2, h: 4 } ],
            // A photo fills the tile, so the background plate is never visible:
            // default it off and hide the toggle (see hidesBackground()).
            defaults: { background: false },
            hideBackground: true,
            colorSlots: [
                { key: "border", label: "Border colour", def: "#ffffff" }
            ],
            options: [
                { key: "image", kind: "image", label: "Photo" },
                { key: "borderWidth", kind: "segmented", label: "Border size", def: 0.5,
                  choices: [ { v: 0, t: "None" }, { v: 0.5, t: "Thin" }, { v: 1, t: "Med" }, { v: 2, t: "Thick" } ] },
                { key: "borderRadius", kind: "segmented", label: "Corners", def: 1.5,
                  choices: [ { v: 0, t: "Square" }, { v: 1, t: "Soft" }, { v: 2.5, t: "Round" }, { v: 5, t: "Pill" } ] }
            ],
            component: photoComponent
        },
        {
            type: "sysmon", title: "System Monitor",
            // Vertical, 2- or 4-wide.
            variants: [ { key: "narrow", w: 2, h: 4 }, { key: "wide", w: 4, h: 4 } ],
            defaults: { background: true },
            colorSlots: [
                { key: "header", label: "Headers", def: "#e9a23b" },
                { key: "bar",    label: "Bars",    def: "#3d5af1" },
                { key: "label",  label: "Labels",  def: "#9fa9c0" },
                { key: "value",  label: "Values",  def: "#ffffff" }
            ],
            options: [
                { key: "sections", kind: "toggles", label: "Sections",
                  def: ["cpu", "memory", "network"],
                  items: [ { k: "system", t: "System" }, { k: "cpu", t: "CPU" },
                           { k: "memory", t: "Memory" }, { k: "network", t: "Network" },
                           { k: "battery", t: "Battery" }, { k: "temp", t: "Temperature" } ] },
                { key: "refresh", kind: "segmented", label: "Refresh", def: 2,
                  choices: [ { v: 1, t: "1s" }, { v: 2, t: "2s" }, { v: 5, t: "5s" } ] }
            ],
            component: sysMonComponent
        }
    ]

    // ---- Lookup helpers (null-safe; never throw) ----

    function typeDef(type) {
        for (var i = 0; i < types.length; ++i) {
            if (types[i].type === type) return types[i];
        }
        return null;
    }

    /** Resolve a {key,w,h} variant; falls back to the type's first variant,
     *  then to a 2x2 default if the type is unknown. */
    function variant(type, key) {
        var t = typeDef(type);
        if (!t) return { key: key || "", w: 2, h: 2 };
        for (var i = 0; i < t.variants.length; ++i) {
            if (t.variants[i].key === key) return t.variants[i];
        }
        return t.variants[0];
    }

    function defaultsFor(type) {
        var t = typeDef(type);
        return t ? t.defaults : { background: true };
    }

    /** Non-colour settings controls for a type (city, units, …), or []. */
    function optionsFor(type) {
        var t = typeDef(type);
        return (t && t.options) ? t.options : [];
    }

    /** Whether to hide the background plate toggle/colour for a type (e.g. the
     *  photo widget, where the picture covers any plate). */
    function hidesBackground(type) {
        var t = typeDef(type);
        return !!(t && t.hideBackground);
    }

    function componentFor(type) {
        var t = typeDef(type);
        return t ? t.component : null;
    }

    /** Colour slots a given variant actually shows (for the settings sheet). */
    function colorSlotsFor(type, variant) {
        var t = typeDef(type);
        if (!t || !t.colorSlots) return [];
        var out = [];
        for (var i = 0; i < t.colorSlots.length; ++i) {
            var s = t.colorSlots[i];
            if (!s.variants || s.variants.indexOf(variant) >= 0) out.push(s);
        }
        return out;
    }

    /** Full {slot → default colour} map for a type (every slot across all
     *  variants, plus the universal "background"). WidgetHost merges saved
     *  overrides on top so the widget always reads a complete map. */
    function colorDefaults(type) {
        var out = { background: defaultBackground };
        var t = typeDef(type);
        if (t && t.colorSlots) {
            for (var i = 0; i < t.colorSlots.length; ++i) {
                out[t.colorSlots[i].key] = t.colorSlots[i].def;
            }
        }
        return out;
    }

    /** Flat list of every {type, variant, title, w, h} for the picker. */
    function pickerEntries() {
        var out = [];
        for (var i = 0; i < types.length; ++i) {
            var t = types[i];
            for (var j = 0; j < t.variants.length; ++j) {
                var v = t.variants[j];
                out.push({
                    type: t.type,
                    variant: v.key,
                    w: v.w, h: v.h,
                    title: t.title + (t.variants.length > 1 ? " (" + v.key + ")" : "")
                });
            }
        }
        return out;
    }
}
