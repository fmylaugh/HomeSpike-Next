/**
 * @file SysMonitorService
 * @description Real-time system metrics source for the System Monitor widget.
 *   ONE instance in main.qml, injected like the other widget services. While at
 *   least one monitor widget is attached it polls /proc + /sys every
 *   `intervalMs` and exposes live values: overall + per-core CPU %, memory and
 *   swap use, network down/up speed + totals, battery, and SoC temperature.
 *   Static facts (distro, kernel, CPU model, boot time) are read once.
 *
 *   Reads are synchronous XHR on local files. That logs a Qt deprecation
 *   warning per read UNLESS QML_XHR_ALLOW_FILE_READ=1 is set — which the deploy
 *   does via a user systemd drop-in on lomiri-full-greeter.service, so a polling
 *   monitor doesn't flood the journal.
 *
 * @status New.
 * @issues CPU/net values appear after the second poll (they need a delta).
 * @todo None
 */
import QtQuick 2.15

Item {
    id: svc
    visible: false; width: 0; height: 0

    property int intervalMs: 2000
    property int _clients: 0

    // ---- live ----
    property real cpu: 0            // overall %
    property var  cores: []         // per-core %
    property real memUsed: 0        // bytes
    property real memTotal: 0
    property real memPct: 0
    property real swapUsed: 0
    property real swapTotal: 0
    property real swapPct: 0
    property real netDown: 0        // bytes/s
    property real netUp: 0
    property real netRxTotal: 0     // bytes
    property real netTxTotal: 0
    property int  battery: -1
    property string batteryStatus: ""
    property real temp: 0           // °C
    // ---- static ----
    property string distro: ""
    property string kernel: ""
    property string cpuModel: ""
    property real   bootEpoch: 0

    property var _prevCpu: ({})
    property var _prevNet: null
    property bool _staticLoaded: false

    /** Widgets call attach()/detach() so polling only runs while one is shown. */
    function attach() { _clients++; if (_clients === 1) { _loadStatic(); _poll(); } }
    function detach() { if (_clients > 0) _clients--; }

    Timer {
        interval: svc.intervalMs
        running: svc._clients > 0
        repeat: true
        onTriggered: svc._poll()
    }

    function _poll() {
        _readCpu();
        _readMem();
        _readNet();
        _readBattery();
        _readTemp();
    }

    // ---- formatting helpers (used by the widget) ----
    function fmtSize(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + "G";
        if (b >= 1048576)    return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1) + "M";
        if (b >= 1024)       return (b / 1024).toFixed(0) + "K";
        return Math.round(b) + "B";
    }
    function fmtSpeed(b) { return fmtSize(b) + "/s"; }
    function uptimeText(now) {
        if (bootEpoch <= 0) return "—";
        var s = Math.floor((now ? now.getTime() : Date.now()) / 1000 - bootEpoch);
        if (s < 0) s = 0;
        var d = Math.floor(s / 86400); s -= d * 86400;
        var h = Math.floor(s / 3600);  s -= h * 3600;
        var m = Math.floor(s / 60);
        if (d > 0) return d + "d " + h + "h";
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    // ---- readers ----
    function _readCpu() {
        var t = _read("/proc/stat"); if (t === "") return;
        var lines = t.split("\n"), next = {}, cs = [];
        for (var i = 0; i < lines.length; ++i) {
            var l = lines[i];
            if (l.substring(0, 3) !== "cpu") continue;
            var p = l.replace(/\s+/g, " ").trim().split(" ");
            var key = p[0], total = 0;
            for (var j = 1; j < p.length; ++j) total += (parseInt(p[j]) || 0);
            var idle = (parseInt(p[4]) || 0) + (parseInt(p[5]) || 0);  // idle + iowait
            next[key] = { total: total, idle: idle };
            var pv = _prevCpu[key];
            if (pv) {
                var dt = total - pv.total, di = idle - pv.idle;
                var pct = dt > 0 ? Math.max(0, Math.min(100, 100 * (dt - di) / dt)) : 0;
                if (key === "cpu") svc.cpu = pct; else cs.push(pct);
            }
        }
        _prevCpu = next;
        if (cs.length > 0) svc.cores = cs;
    }

    function _readMem() {
        var t = _read("/proc/meminfo"); if (t === "") return;
        var total = _kv(t, "MemTotal"), avail = _kv(t, "MemAvailable");
        var st = _kv(t, "SwapTotal"), sf = _kv(t, "SwapFree");
        if (total > 0) { svc.memTotal = total * 1024; svc.memUsed = (total - avail) * 1024; svc.memPct = 100 * (total - avail) / total; }
        if (st > 0) { svc.swapTotal = st * 1024; svc.swapUsed = (st - sf) * 1024; svc.swapPct = 100 * (st - sf) / st; }
        else { svc.swapTotal = 0; svc.swapUsed = 0; svc.swapPct = 0; }
    }

    function _readNet() {
        var t = _read("/proc/net/dev"); if (t === "") return;
        var lines = t.split("\n"), rx = 0, tx = 0;
        for (var i = 0; i < lines.length; ++i) {
            var c = lines[i].indexOf(":"); if (c < 0) continue;
            var iface = lines[i].substring(0, c).trim();
            if (iface === "lo" || iface === "") continue;
            var f = lines[i].substring(c + 1).replace(/\s+/g, " ").trim().split(" ");
            rx += parseInt(f[0]) || 0;
            tx += parseInt(f[8]) || 0;
        }
        var now = Date.now();
        svc.netRxTotal = rx; svc.netTxTotal = tx;
        if (_prevNet) {
            var dt = (now - _prevNet.t) / 1000;
            if (dt > 0) { svc.netDown = Math.max(0, (rx - _prevNet.rx) / dt); svc.netUp = Math.max(0, (tx - _prevNet.tx) / dt); }
        }
        _prevNet = { rx: rx, tx: tx, t: now };
    }

    function _readBattery() {
        var c = _read("/sys/class/power_supply/battery/capacity");
        var s = _read("/sys/class/power_supply/battery/status");
        if (c !== "") svc.battery = parseInt(c);
        if (s !== "") svc.batteryStatus = s.replace(/\s+$/, "");
    }

    function _readTemp() {
        var t = _read("/sys/class/thermal/thermal_zone0/temp");
        if (t !== "") { var v = parseInt(t); if (!isNaN(v)) svc.temp = v > 1000 ? v / 1000 : v; }
    }

    function _loadStatic() {
        if (_staticLoaded) return;
        _staticLoaded = true;
        svc.distro = _pretty(_read("/etc/os-release"));
        svc.kernel = _firstLine(_read("/proc/sys/kernel/osrelease"));
        var ci = _read("/proc/cpuinfo");
        var m = ci.match(/^(?:model name|Hardware|Processor)\s*:\s*(.+)$/m);
        var n = (ci.match(/^processor\s*:/gm) || []).length;
        svc.cpuModel = (m ? m[1].trim() : "CPU") + (n ? "  ×" + n : "");
        var up = parseFloat(_read("/proc/uptime"));
        if (!isNaN(up)) svc.bootEpoch = Date.now() / 1000 - up;
    }

    // ---- low-level ----
    function _read(path) {
        var x = new XMLHttpRequest();
        try { x.open("GET", "file://" + path, false); x.send(); return x.responseText || ""; }
        catch (e) { return ""; }
    }
    function _kv(t, k) { var m = t.match(new RegExp("^" + k + ":\\s*(\\d+)", "m")); return m ? parseInt(m[1]) : 0; }
    function _firstLine(s) { return (s || "").split("\n")[0].replace(/^\s+|\s+$/g, ""); }
    function _pretty(s) {
        var ls = (s || "").split("\n");
        for (var i = 0; i < ls.length; ++i) { var m = ls[i].match(/^PRETTY_NAME=(.*)$/); if (m) return m[1].replace(/^"|"$/g, ""); }
        return "";
    }
}
