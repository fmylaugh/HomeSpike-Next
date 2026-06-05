/**
 * @file SysInfoService
 * @description Shared system-info source for the System Info widget. ONE
 *   instance lives in main.qml and is injected like LocaleClock / WeatherService.
 *   On first use it reads a handful of /proc + /etc files ONCE (synchronous
 *   XHR), parses them, and caches the results — so any number of widgets, and
 *   any grid rebuild, cost only that single read. Uptime is derived from the
 *   boot instant plus a ticking clock, so it stays live without re-reading.
 *
 *   Lazy: nothing is read until a widget calls ensureLoaded(), so devices
 *   without a System Info widget pay nothing (and see no file-read warnings).
 *
 * @status New.
 * @issues The reads are local-file XHR — Qt logs one deprecation warning per
 *   file, once, the first time a System Info widget appears. Not polled.
 * @todo None
 */
import QtQuick 2.15

Item {
    id: svc
    visible: false
    width: 0
    height: 0

    property string user:     ""
    property string hostname: ""
    property string distro:   ""
    property string kernel:   ""
    property string desktop:  ""
    property string term:     ""
    property string shell:    ""
    /** Unix seconds at boot; uptime = now − bootEpoch. 0 = unknown. */
    property real   bootEpoch: 0

    property bool _loaded: false

    /** Read + cache everything once. Called by the widget on first show. */
    function ensureLoaded() {
        if (_loaded) return;
        _loaded = true;

        // /proc/self/environ → USER / SHELL / XDG_CURRENT_DESKTOP / TERM
        var env = _parseEnviron(_read("/proc/self/environ"));
        user    = env["USER"] || env["LOGNAME"] || "";
        shell   = _base(env["SHELL"] || "");
        desktop = env["XDG_CURRENT_DESKTOP"] || "";
        term    = env["TERM"] || "";

        distro   = _osPretty(_read("/etc/os-release"));
        kernel   = _firstLine(_read("/proc/sys/kernel/osrelease"));
        hostname = _firstLine(_read("/etc/hostname"));

        var up = parseFloat(_read("/proc/uptime"));   // first token = seconds up
        if (!isNaN(up)) bootEpoch = (Date.now() / 1000) - up;
    }

    /** Human uptime ("3d 4h" / "5h 12m" / "8m"), computed from a passed Date. */
    function uptimeText(now) {
        if (bootEpoch <= 0) return "—";
        var secs = Math.floor((now ? now.getTime() : Date.now()) / 1000 - bootEpoch);
        if (secs < 0) secs = 0;
        var d = Math.floor(secs / 86400); secs -= d * 86400;
        var h = Math.floor(secs / 3600);  secs -= h * 3600;
        var m = Math.floor(secs / 60);
        if (d > 0) return d + "d " + h + "h";
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    // ---- helpers ----

    function _read(path) {
        var x = new XMLHttpRequest();
        try { x.open("GET", "file://" + path, false); x.send(); return x.responseText || ""; }
        catch (e) { return ""; }
    }
    function _firstLine(s) { return (s || "").split("\n")[0].replace(/^\s+|\s+$/g, ""); }
    function _base(s) { var p = (s || "").split("/"); return p[p.length - 1]; }
    function _parseEnviron(s) {
        var out = {}, parts = (s || "").split("\0");
        for (var i = 0; i < parts.length; ++i) {
            var eq = parts[i].indexOf("=");
            if (eq > 0) out[parts[i].substring(0, eq)] = parts[i].substring(eq + 1);
        }
        return out;
    }
    function _osPretty(s) {
        var lines = (s || "").split("\n");
        for (var i = 0; i < lines.length; ++i) {
            var m = lines[i].match(/^PRETTY_NAME=(.*)$/);
            if (m) return m[1].replace(/^"|"$/g, "");
        }
        return "";
    }
}
