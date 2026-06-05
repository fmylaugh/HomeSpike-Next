/**
 * @file WeatherWidget
 * @description Weather widget. Two size variants:
 *   - "small" (2x2): condition icon (top-right), big current temperature, and
 *     the location name below.
 *   - "wide"  (4x2): a header (location + big temp on the left, condition icon +
 *     label on the right) over a row of ~6 hourly forecast cells {hour, icon,
 *     temp}.
 *   Location is set per widget (a city, geocoded in the settings sheet to
 *   lat/lon stored in `settings`); until then it shows a "Set a city" hint.
 *   Units follow `settings.unit` ("C"/"F"), or the system locale when "auto".
 *   Data is fetched on load and every ~20 min via the injected WeatherService;
 *   hour labels use the injected LocaleClock (12/24h-aware). Icons come from the
 *   system Suru theme. Display-only — a tap does nothing.
 *
 * @status New.
 * @issues Needs network egress (offline → keeps last value / "Unavailable").
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

WidgetBase {
    id: root

    /** Injected WeatherService (network + icon/label helpers). */
    property var service: null

    readonly property bool _small: variant === "small"

    // ---- Resolved location + unit from this widget's settings ----
    readonly property real _lat: (settings && settings.lat !== undefined && settings.lat !== null)
                                 ? settings.lat : NaN
    readonly property real _lon: (settings && settings.lon !== undefined && settings.lon !== null)
                                 ? settings.lon : NaN
    readonly property bool _haveCoords: !isNaN(_lat) && !isNaN(_lon)
    readonly property string _city: (settings && settings.city) ? settings.city : ""
    // unit "" / undefined → follow the locale (via the service).
    readonly property string _unit: (settings && settings.unit)
                                    ? settings.unit : (service ? service.localeUnit : "C")

    // ---- Live weather state ----
    property int     _temp: 0
    property int     _code: -1
    property bool    _isDay: true
    property var     _hourly: []
    property bool    _loading: false
    property string  _error: ""
    property bool    _haveData: false
    property string  _fetchedKey: ""

    // ---- Display text (placeholder-aware) ----
    readonly property string _placeText: _city !== "" ? _city : "Set a city"
    readonly property string _tempText:  _haveData ? _temp + "°" : "—"
    readonly property string _conditionText: {
        if (_haveData && service) return service.labelFor(_code);
        if (_loading)             return "Updating…";
        if (_error !== "")        return "Unavailable";
        return "";
    }

    // Minutes between auto-refreshes (0 = off). Defaults to 30 when unset.
    readonly property int _refreshMins: (settings && typeof settings.refresh === "number")
                                        ? settings.refresh : 30

    // Short status line shown while there's no data (so failures aren't silent).
    readonly property string _statusText: {
        if (!_haveCoords)  return "";
        if (_haveData)     return "";
        if (_loading)      return "Updating…";
        if (_error === "network" || _error === "nocoords") return "Offline — tap to retry";
        if (_error !== "") return "Tap to retry";
        return "Loading…";
    }

    /** Public: tap-to-refresh hook, called by WidgetHost on a tap. */
    function handleTap() { _refresh(true); }

    function _refresh(force) {
        if (!service || !_haveCoords) return;
        var key = _lat + "," + _lon + "," + _unit;
        if (!force && key === _fetchedKey && _haveData) return;
        root._loading = true;
        service.fetchForecast(_lat, _lon, _unit, function (res) {
            // The widget delegate can be destroyed (page/grid rebuild) before the
            // async reply lands — `root` goes null. Bail rather than throw.
            if (!root) return;
            root._loading = false;
            if (!res.ok) {
                root._error = res.error;   // keep any last value
                console.warn("[HomeSpike] weather fetch error: " + res.error
                             + " at " + root._lat + "," + root._lon);
                return;
            }
            root._temp = res.temp;
            root._code = res.code;
            root._isDay = res.isDay;
            root._hourly = res.hourly;
            root._error = "";
            root._haveData = true;
            root._fetchedKey = key;
        });
    }

    // Refetch when the location/unit actually changes (settings is re-pushed on
    // every settings edit — colours included — so _refresh de-dupes on the key).
    onSettingsChanged: _refresh(false)
    onServiceChanged:  _refresh(false)
    Component.onCompleted: _refresh(false)

    // Auto-refresh on the user-chosen cadence (Off / 15m / 30m / 1h / 3h).
    Timer {
        interval: Math.max(1, root._refreshMins) * 60 * 1000
        running: root._refreshMins > 0 && root._haveCoords
        repeat: true
        onTriggered: root._refresh(true)
    }

    // ================= small (2x2) =================
    Item {
        visible: root._small
        anchors.fill: parent
        anchors.margins: units.gu(1.2)

        Image {
            visible: root._haveData
            anchors { top: parent.top; right: parent.right }
            width: units.gu(4.5); height: width
            source: root.service ? root.service.iconFor(root._code, root._isDay) : ""
            sourceSize.width: width; sourceSize.height: height
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: units.gu(0.2)

            // Big current temperature — shown once we have data.
            Label {
                visible: root._haveData
                width: parent.width
                text: root._tempText
                color: root.colorOf("temp", "#ffffff")
                font.weight: Font.Light
                font.pixelSize: units.gu(5)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: units.gu(2)
            }
            // Location (or the "Set a city" hint).
            Label {
                width: parent.width
                text: root._placeText
                color: root.colorOf("place", "#9fa9c0")
                font.pixelSize: units.gu(1.6)
                elide: Text.ElideRight
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: units.gu(1)
            }
            // Status while there's no data — so a failure is never silent.
            Label {
                visible: root._statusText !== ""
                width: parent.width
                text: root._statusText
                color: "#e9a23b"
                font.pixelSize: units.gu(1.4)
                elide: Text.ElideRight
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: units.gu(0.9)
            }
        }
    }

    // ================= wide (4x2) =================
    Column {
        visible: !root._small
        anchors.fill: parent
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1)

        // ---- header: location + temp (left), icon + condition (right) ----
        Item {
            width: parent.width
            height: parent.height * 0.5

            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.6
                spacing: units.gu(0.1)
                Label {
                    width: parent.width
                    text: root._placeText
                    color: root.colorOf("place", "#9fa9c0")
                    font.weight: Font.DemiBold
                    font.pixelSize: units.gu(2.2)
                    elide: Text.ElideRight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: units.gu(1.2)
                }
                Label {
                    width: parent.width
                    text: root._tempText
                    color: root.colorOf("temp", "#ffffff")
                    font.weight: Font.Light
                    font.pixelSize: units.gu(5)
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: units.gu(2)
                }
            }

            Column {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.36
                spacing: units.gu(0.2)
                Image {
                    visible: root._haveData
                    anchors.right: parent.right
                    width: units.gu(4.5); height: width
                    source: root.service ? root.service.iconFor(root._code, root._isDay) : ""
                    sourceSize.width: width; sourceSize.height: height
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Label {
                    anchors.right: parent.right
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: root._conditionText
                    color: root.colorOf("condition", "#9fa9c0")
                    font.pixelSize: units.gu(1.5)
                    elide: Text.ElideRight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: units.gu(1)
                }
            }
        }

        // ---- hourly forecast row ----
        Row {
            id: forecastRow
            visible: root._haveData && root._hourly.length > 0
            width: parent.width
            height: parent.height * 0.5 - units.gu(1)

            Repeater {
                model: root._hourly
                delegate: Column {
                    width: forecastRow.width / Math.max(1, root._hourly.length)
                    height: forecastRow.height
                    spacing: units.gu(0.2)

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.clock ? root.clock.hourText(modelData.t) : ""
                        color: root.colorOf("hour", "#9fa9c0")
                        font.pixelSize: units.gu(1.3)
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: units.gu(0.9)
                    }
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: units.gu(2.6); height: width
                        source: root.service ? root.service.iconFor(modelData.code, modelData.isDay) : ""
                        sourceSize.width: width; sourceSize.height: height
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.temp + "°"
                        color: root.colorOf("forecastTemp", "#ffffff")
                        font.weight: Font.DemiBold
                        font.pixelSize: units.gu(1.5)
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: units.gu(0.9)
                    }
                }
            }
        }
    }
}
