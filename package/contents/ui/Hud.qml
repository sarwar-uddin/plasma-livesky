import QtQuick
import QtQuick.Layouts
import "../code/sky.js" as Sky
import "../code/solar.js" as Solar

// The clock and the read-out, sitting on the dark ground in the two lower corners.
Item {
    id: hud

    property real now: Date.now()
    property real lat: 23.8103
    property real lng: 90.4125
    property string place: "Dhaka"
    property bool use24h: true
    property bool showInfo: true
    property string prayerMethod: "karachi"
    property bool asrHanafi: true
    property var weather: null          // { temp, code, isDay, aqi, pm25, t }
    property var passes: []
    property var sats: []

    readonly property real u: height / 1440          // design unit: 1 at 1440p
    readonly property color crimson: "#E0203F"
    readonly property color text: "#D6D6DA"
    readonly property color dim: "#8C8C94"
    readonly property color faint: "#5E5E66"

    readonly property var d: new Date(now)
    readonly property string dayKey: d.toDateString()
    readonly property var today: { dayKey; lat; lng; prayerMethod; asrHanafi
        return Solar.compute(d, lat, lng, prayerMethod, asrHanafi ? 2 : 1, [0, 0, 0, 0, 0, 0]) }
    readonly property var tomorrow: { dayKey; lat; lng; prayerMethod; asrHanafi
        return Solar.compute(new Date(now + 86400000), lat, lng, prayerMethod, asrHanafi ? 2 : 1, [0, 0, 0, 0, 0, 0]) }
    readonly property var nextPrayer: {
        for (const e of today.events) if (e.time && e.time.getTime() > now && e.name !== "Sunrise") return e
        return tomorrow.events[0]
    }
    readonly property real tick10: Math.floor(now / 600000)     // real, not var: a var re-notifies every second
    readonly property var moon: { tick10; return Solar.moonState(d, lat, lng) }
    // in the dark: what's up now; in daylight: what will be up once it's dark
    readonly property bool daylight: { tick10; return Sky.body("Sun", now, lat, lng).alt > -6 }
    readonly property real darkAt: { tick10
        const ev = Sky.events("Sun", now, 24, lat, lng)
        return ev.set ? ev.set + 75 * 60000 : now }
    readonly property var planetsUp: { tick10
        const t = daylight ? darkAt : now
        return Sky.NAKED_EYE.map(n => Sky.body(n, t, lat, lng)).filter(b => b.alt > 8).sort((a, b) => a.mag - b.mag) }
    readonly property var nextPass: { tick10; return passes.filter(p => p.end > now)[0] || null }

    function t(ms) { return new Date(ms).toLocaleTimeString(Qt.locale(), use24h ? "HH:mm" : "h:mm AP") }
    function span(ms) {
        const m = Math.max(0, Math.round(ms / 60000)), h = Math.floor(m / 60)
        return h ? h + "h " + (m % 60) + "m" : m + " min"
    }
    function wmoText(c) {
        const T = { 0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast", 45: "Fog", 48: "Fog",
                    51: "Drizzle", 53: "Drizzle", 55: "Drizzle", 61: "Light rain", 63: "Rain", 65: "Heavy rain",
                    80: "Showers", 81: "Showers", 82: "Heavy showers", 95: "Thunderstorm", 96: "Thunderstorm", 99: "Thunderstorm" }
        return T[c] || ""
    }
    function aqiColor(a) {
        return a <= 50 ? "#4FAF7C" : a <= 100 ? "#D4B13A" : a <= 150 ? "#E07B2A" : a <= 200 ? "#E0203F" : a <= 300 ? "#A04AB8" : "#8A1028"
    }

    // a soft dark fade along the bottom, so the text reads over the roofs
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 520 * hud.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.55; color: "#7A000000" }
            GradientStop { position: 1.0; color: "#C8000000" }
        }
    }

    // ---- the clock ------------------------------------------------------------------
    ColumnLayout {
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 96 * hud.u; bottomMargin: 70 * hud.u }
        spacing: 6 * hud.u

        Row {
            spacing: 10 * hud.u
            Text {
                id: hm
                text: hud.d.toLocaleTimeString(Qt.locale(), hud.use24h ? "HH:mm" : "h:mm")
                font.family: "JetBrains Mono"
                font.weight: Font.ExtraLight
                font.pixelSize: 190 * hud.u
                color: hud.text
            }
            Column {
                anchors.baseline: hm.baseline
                spacing: 0
                Text {
                    visible: !hud.use24h
                    text: hud.d.toLocaleTimeString(Qt.locale(), "AP")
                    font.family: "JetBrains Mono"
                    font.pixelSize: 34 * hud.u
                    color: hud.dim
                }
                Text {
                    text: hud.d.toLocaleTimeString(Qt.locale(), "ss")
                    font.family: "JetBrains Mono"
                    font.weight: Font.Light
                    font.pixelSize: 46 * hud.u
                    color: hud.crimson
                }
            }
        }
        Text {
            text: hud.d.toLocaleDateString(Qt.locale(), "dddd, d MMMM yyyy")
            font.pixelSize: 38 * hud.u
            font.weight: Font.Light
            color: hud.text
        }
    }

    // ---- the read-out -----------------------------------------------------------------
    ColumnLayout {
        visible: hud.showInfo
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 96 * hud.u; bottomMargin: 78 * hud.u }
        spacing: 10 * hud.u

        component Info: Text {
            Layout.alignment: Qt.AlignRight
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 26 * hud.u
            font.weight: Font.Light
            color: hud.dim
            textFormat: Text.StyledText
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            visible: !!hud.weather && hud.now - hud.weather.t < 3 * 3600000
            spacing: 14 * hud.u
            Text {
                text: hud.weather ? Math.round(hud.weather.temp) + "°  " + hud.wmoText(hud.weather.code) : ""
                font.pixelSize: 34 * hud.u
                font.weight: Font.Light
                color: hud.text
            }
            Rectangle {
                visible: !!hud.weather && hud.weather.aqi !== null && hud.weather.aqi !== undefined
                implicitWidth: aqiText.implicitWidth + 22 * hud.u
                implicitHeight: aqiText.implicitHeight + 8 * hud.u
                radius: 5 * hud.u
                color: Qt.rgba(Qt.color(hud.aqiColor(hud.weather ? hud.weather.aqi : 0)).r,
                               Qt.color(hud.aqiColor(hud.weather ? hud.weather.aqi : 0)).g,
                               Qt.color(hud.aqiColor(hud.weather ? hud.weather.aqi : 0)).b, 0.22)
                border.color: hud.aqiColor(hud.weather ? hud.weather.aqi : 0)
                border.width: Math.max(1, 1.5 * hud.u)
                Text {
                    id: aqiText
                    anchors.centerIn: parent
                    text: hud.weather ? "AQI " + hud.weather.aqi : ""
                    font.pixelSize: 24 * hud.u
                    color: "#F2F2F5"
                }
            }
        }
        Info {
            text: hud.nextPrayer ? "<font color='" + hud.crimson + "'>" + hud.nextPrayer.name + "</font>  " + hud.t(hud.nextPrayer.time.getTime())
                                   + "  ·  in " + hud.span(hud.nextPrayer.time.getTime() - hud.now) : ""
            color: hud.text
        }
        Info {
            text: "Moon " + Math.round(hud.moon.phase.illum * 100) + "%, " + hud.moon.phase.name.toLowerCase()
                  + (hud.moon.up && hud.moon.nextSet ? "  ·  sets " + hud.t(hud.moon.nextSet.getTime())
                     : hud.moon.nextRise ? "  ·  rises " + hud.t(hud.moon.nextRise.getTime()) : "")
        }
        Info {
            visible: hud.planetsUp.length > 0
            text: (hud.daylight ? "After dark (" + hud.t(hud.darkAt) + "): " : "Up now: ") + hud.planetsUp.map(b => b.name).join(", ")
        }
        Info {
            visible: !!hud.nextPass
            readonly property bool on: !!hud.nextPass && hud.nextPass.start <= hud.now
            color: on ? hud.crimson : hud.dim
            text: !hud.nextPass ? "" : on ? "▶ " + hud.nextPass.label + " overhead now, look " + Sky.compass(hud.nextPass.peakAz)
                  : hud.nextPass.label + " visible " + new Date(hud.nextPass.start).toLocaleDateString(Qt.locale(), "ddd d MMM")
                    + " " + hud.t(hud.nextPass.start) + ", max " + Math.round(hud.nextPass.maxAlt) + "°"
        }
        Info {
            text: hud.place + "  ·  " + Math.abs(hud.lat).toFixed(2) + "°" + (hud.lat >= 0 ? "N" : "S") + " "
                  + Math.abs(hud.lng).toFixed(2) + "°" + (hud.lng >= 0 ? "E" : "W") + "  ·  the sky right now"
            color: hud.faint
            font.pixelSize: 20 * hud.u
        }
    }
}
