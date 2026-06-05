/**
 * @file LocaleClock
 * @description Shared ticking time source + locale-aware date/time formatting
 *   for HomeSpike widgets. ONE instance is created in main.qml and injected
 *   into every widget, so they share a single timer and a single read of the
 *   system clock-format preference instead of each spinning their own.
 *
 *   Time format follows the SAME source as Lomiri's top-bar clock: the
 *   datetime indicator's gsettings `time-format` key (locale-default /
 *   12-hour / 24-hour / custom). Date names and the first day of the week come
 *   from the device locale via Qt.locale(). This keeps widgets consistent with
 *   the rest of the UI without bundling any locale data of our own.
 *
 *   QML's Locale uses 0 = Sunday … 6 = Saturday for both `firstDayOfWeek` and
 *   day-name lookups, which lines up exactly with JS `Date.getDay()`, and
 *   0 = January … 11 = December for months, matching `Date.getMonth()`.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import GSettings 1.0

Item {
    id: clock
    visible: false
    width: 0
    height: 0

    /** Current wall-clock time, refreshed on each tick. Widgets bind to this
     *  so their displays update (and date-dependent widgets recompute on a
     *  midnight rollover). */
    property var now: new Date()

    /** Cached device locale + its first day of week (0=Sun … 6=Sat). */
    readonly property var loc: Qt.locale()
    readonly property int firstDayOfWeek: loc.firstDayOfWeek

    /** System clock-format preference, mirrored live from the datetime
     *  indicator (the value the top-bar clock uses):
     *  "locale-default" | "12-hour" | "24-hour" | "custom".
     *  The schema ships with lomiri-indicator-datetime, which is always
     *  installed on the device generation HomeSpike targets. */
    readonly property string systemTimeFormat: dateTimeSettings.timeFormat

    GSettings {
        id: dateTimeSettings
        schema.id: "com.lomiri.indicator.datetime"
    }

    // Re-read the clock once a second so minute and day rollovers land
    // promptly. Cheap for a handful of widgets; bound text only re-renders
    // when the formatted string actually changes.
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clock.now = new Date()
    }

    // ----- Formatting helpers (all default to `now` when no date passed) -----

    /** Locale/preference-aware time string, no seconds. */
    function timeText(d) {
        if (!d) d = now;
        switch (systemTimeFormat) {
        case "12-hour": return Qt.formatTime(d, "h:mm AP");
        case "24-hour": return Qt.formatTime(d, "HH:mm");
        default:        return Qt.formatTime(d, loc, Locale.ShortFormat);
        }
    }

    /** Hour-only label honouring the 12/24h preference, e.g. "4 PM" or "16".
     *  Used for the weather widget's hourly forecast columns. For the
     *  "locale-default" preference, infer 12h-vs-24h from whether the locale's
     *  short time pattern carries an am/pm field. */
    function hourText(d) {
        if (!d) d = now;
        var fmt = systemTimeFormat;
        if (fmt !== "12-hour" && fmt !== "24-hour") {
            fmt = /[Aa]/.test(loc.timeFormat(Locale.ShortFormat)) ? "12-hour" : "24-hour";
        }
        return (fmt === "12-hour") ? Qt.formatTime(d, "h AP") : Qt.formatTime(d, "HH");
    }

    /** Weekday + month + day (locale names), e.g. "Tue, Jun 25". */
    function dateText(d) {
        if (!d) d = now;
        return dayShort(d.getDay()) + ", " + monthShort(d) + " " + d.getDate();
    }

    function monthShort(d) { if (!d) d = now; return loc.standaloneMonthName(d.getMonth(), Locale.ShortFormat); }
    function monthLong(d)  { if (!d) d = now; return loc.standaloneMonthName(d.getMonth(), Locale.LongFormat); }

    /** Day names for a JS weekday index (0=Sun … 6=Sat). */
    function dayShort(weekday)  { return loc.standaloneDayName(weekday, Locale.ShortFormat); }
    function dayNarrow(weekday) { return loc.standaloneDayName(weekday, Locale.NarrowFormat); }
}
