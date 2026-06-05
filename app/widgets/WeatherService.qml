/**
 * @file WeatherService
 * @description Shared, stateless data layer for the weather widget. ONE instance
 *   lives in main.qml and is injected into every WeatherWidget (and the settings
 *   sheet), the same way LocaleClock / WidgetCatalog are. It owns no per-location
 *   state — location is per widget — it just wraps the network calls and the
 *   weather-code → icon/label mapping so the widgets stay presentational.
 *
 *   Data comes from Open-Meteo (free, no API key, HTTPS):
 *     - geocode():       city name  → coordinates + a display label
 *     - fetchForecast(): coordinates → current conditions + a short hourly list
 *   Both use QML's XMLHttpRequest (Qt's network stack, which has TLS), and call
 *   back with a plain object {ok, ...} — never throwing, so a widget only has to
 *   branch on `ok`.
 *
 *   Icons are resolved to the system Suru theme (Icon { name }) — no bundled
 *   assets. The code→name map is day/night aware via the API's `is_day`.
 *
 * @status New.
 * @issues Needs a connected device to actually reach the endpoints (DNS +
 *   egress); offline calls resolve to {ok:false, error:"network"}.
 * @todo None
 */
import QtQuick 2.15

Item {
    id: service
    visible: false
    width: 0
    height: 0

    readonly property string _geoBase: "https://geocoding-api.open-meteo.com/v1/search"
    readonly property string _fcBase:  "https://api.open-meteo.com/v1/forecast"

    /** °C or °F to default to when a widget's unit is "auto" — from the locale. */
    readonly property string localeUnit: (Qt.locale().measurementSystem === Locale.MetricSystem) ? "C" : "F"

    /**
     * Geocode a free-text place name to coordinates. Calls back with
     *   { ok:true, lat, lon, label }            // label e.g. "Bangalore, IN"
     *   { ok:false, error:"empty|network|notfound|parse" }
     */
    function geocode(name, cb) {
        var q = (name || "").trim();
        if (q === "") { cb({ ok: false, error: "empty" }); return; }
        var lang = (Qt.locale().name || "en").substring(0, 2);
        var url = _geoBase + "?count=1&format=json&language=" + lang
                + "&name=" + encodeURIComponent(q);
        _get(url, function (ok, body) {
            if (!ok) { cb({ ok: false, error: "network" }); return; }
            try {
                var j = JSON.parse(body);
                if (!j.results || j.results.length === 0) { cb({ ok: false, error: "notfound" }); return; }
                var r = j.results[0];
                cb({ ok: true, lat: r.latitude, lon: r.longitude, label: _placeLabel(r) });
            } catch (e) { cb({ ok: false, error: "parse" }); }
        });
    }

    /**
     * Fetch current conditions + a short hourly forecast for coordinates.
     * `unit` is "C" or "F" (resolve "auto" via localeUnit before calling).
     * Calls back with
     *   { ok:true, temp, code, isDay, unit, hourly:[ {t:Date, temp, code}, … ] }
     *   { ok:false, error:"nocoords|network|parse" }
     */
    function fetchForecast(lat, lon, unit, cb) {
        if (lat === null || lat === undefined || lon === null || lon === undefined) {
            cb({ ok: false, error: "nocoords" }); return;
        }
        var tu = (unit === "F") ? "fahrenheit" : "celsius";
        var url = _fcBase + "?latitude=" + lat + "&longitude=" + lon
                + "&current=temperature_2m,weather_code,is_day"
                + "&hourly=temperature_2m,weather_code,is_day"
                + "&forecast_hours=12&timezone=auto&temperature_unit=" + tu;
        _get(url, function (ok, body) {
            if (!ok) { cb({ ok: false, error: "network" }); return; }
            try {
                var j = JSON.parse(body);
                var c = j.current || {};
                var out = {
                    ok: true,
                    temp: Math.round(c.temperature_2m),
                    code: c.weather_code,
                    isDay: (c.is_day === 1 || c.is_day === true),
                    unit: (tu === "fahrenheit") ? "F" : "C",
                    hourly: []
                };
                var h = j.hourly || {};
                var times = h.time || [], temps = h.temperature_2m || [],
                    codes = h.weather_code || [], days = h.is_day || [];
                // Start at the slot on/after the current hour (allow the current
                // hour itself, hence the one-hour grace).
                var floor = Date.now() - 3600000, start = 0;
                for (var i = 0; i < times.length; ++i) {
                    if (new Date(times[i]).getTime() >= floor) { start = i; break; }
                }
                for (var k = start; k < times.length && out.hourly.length < 6; ++k) {
                    out.hourly.push({ t: new Date(times[k]), temp: Math.round(temps[k]),
                                      code: codes[k], isDay: (days[k] === 1) });
                }
                cb(out);
            } catch (e) { cb({ ok: false, error: "parse" }); }
        });
    }

    /** WMO weather_code → Suru theme icon name (day/night aware). All names
     *  verified present in the device's Suru theme. */
    function iconFor(code, isDay) {
        var n = isDay ? "" : "-night";
        if (code === 0)                    return "weather-clear" + n;
        if (code === 1 || code === 2)      return "weather-few-clouds" + n;
        if (code === 3)                    return "weather-overcast";
        if (code === 45 || code === 48)    return "weather-fog";
        if (code >= 51 && code <= 57)      return "weather-showers-scattered";
        if (code >= 61 && code <= 67)      return "weather-showers";
        if (code >= 71 && code <= 77)      return "weather-snow";
        if (code >= 80 && code <= 82)      return "weather-showers";
        if (code === 85 || code === 86)    return "weather-snow";
        if (code >= 95)                    return "weather-storm";
        return "weather-clouds" + n;
    }

    /** WMO weather_code → short human label. */
    function labelFor(code) {
        if (code === 0)                 return "Clear";
        if (code === 1)                 return "Mainly clear";
        if (code === 2)                 return "Partly cloudy";
        if (code === 3)                 return "Overcast";
        if (code === 45 || code === 48) return "Fog";
        if (code >= 51 && code <= 57)   return "Drizzle";
        if (code >= 61 && code <= 67)   return "Rain";
        if (code >= 71 && code <= 77)   return "Snow";
        if (code >= 80 && code <= 82)   return "Showers";
        if (code === 85 || code === 86) return "Snow showers";
        if (code >= 95)                 return "Thunderstorm";
        return "—";
    }

    // ---- internals ----

    function _placeLabel(r) {
        return r.name + (r.country_code ? ", " + r.country_code : "");
    }

    function _get(url, cb) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    cb(true, xhr.responseText);
                } else {
                    console.warn("[HomeSpike] weather GET failed: status=" + xhr.status + " url=" + url);
                    cb(false, null);
                }
            }
        };
        try { xhr.open("GET", url); xhr.send(); }
        catch (e) { console.warn("[HomeSpike] weather GET threw: " + e + " url=" + url); cb(false, null); }
    }
}
