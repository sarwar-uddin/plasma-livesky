import QtQuick
import QtQml.WorkerScript
import "../code/sgp4.mjs" as G

// The whole wallpaper: the sky plus the clock, driven by the configuration.
// On the lock screen there is no network, so weather and satellite orbits arrive
// through the configuration, written by the livesky-fetch timer. On the desktop
// it can fetch for itself when that data is missing or stale.
Item {
    id: live

    property var config: ({})
    property real offset: 0              // ms added to the clock (testing)

    readonly property real lat: config.latitude !== undefined ? config.latitude : 23.8103
    readonly property real lng: config.longitude !== undefined ? config.longitude : 90.4125
    readonly property var limits: [3.2, 4.5, 5.5]

    // ---- clocks: the sky steps every 20 s, the clock and satellites every second ----
    property real now: Date.now()
    property real skyTime: Date.now()
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            live.now = Date.now() + live.offset
            if (Math.abs(live.now - live.skyTime) >= 20000) live.skyTime = live.now
        }
    }

    // ---- data from the configuration (or fetched, on the desktop) ----------------------
    property string tleText: config.tle || ""
    property var weather: { try { return config.weather ? JSON.parse(config.weather) : null } catch (e) { return null } }
    property var sats: []
    property var passes: []
    onTleTextChanged: { sats = tleText ? G.parseTLEs(tleText) : []; computePasses() }
    // the worker takes a moment to start; a message sent before then is dropped, so queue it
    property bool passesPending: false
    function computePasses() {
        if (!sats.length) return
        if (!passWorker.ready) { passesPending = true; return }
        passesPending = false
        passWorker.sendMessage({ tle: tleText, ids: [25544, 48274, 20580], fromMs: Date.now() + offset - 15 * 60000,
                                 days: 7, lat: lat, lng: lng, minAlt: 10 })
    }
    WorkerScript {
        id: passWorker
        source: Qt.resolvedUrl("../code/passworker.mjs")
        onReadyChanged: if (ready && live.passesPending) live.computePasses()
        onMessage: (m) => live.passes = m.passes
    }
    // refresh passes hourly; on the desktop also top up stale data (fails quietly on the lock screen)
    Timer {
        interval: 3600000; running: true; repeat: true
        onTriggered: { live.computePasses(); live.selfFetch() }
    }
    Component.onCompleted: { if (tleText) tleTextChanged(); selfFetch() }

    function selfFetch() {
        const fresh = weather && Date.now() - weather.t < 3 * 3600000
        if (!fresh) {
            get("https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lng
                + "&current=temperature_2m,weather_code,is_day,cloud_cover,cloud_cover_low,cloud_cover_high,"
                + "precipitation,wind_speed_10m,wind_direction_10m,visibility&timezone=auto", j => {
                const c = j.current
                const w = { temp: c.temperature_2m, code: c.weather_code, isDay: !!c.is_day, cloud: c.cloud_cover,
                            cloudLow: c.cloud_cover_low, cloudHigh: c.cloud_cover_high, rain: c.precipitation,
                            wind: c.wind_speed_10m, windDir: c.wind_direction_10m, vis: c.visibility,
                            aqi: live.weather ? live.weather.aqi : null, t: Date.now() }
                get("https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" + lat + "&longitude=" + lng
                    + "&current=us_aqi,pm2_5", a => { w.aqi = a.current.us_aqi; w.pm25 = a.current.pm2_5; live.weather = w })
                live.weather = w
            })
        }
        if (!tleText) get("https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=tle", null, t => {
            if (t.indexOf("25544U") >= 0) live.tleText = t })
    }
    function get(url, okJson, okText) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200) return
            try { if (okJson) okJson(JSON.parse(x.responseText)); else okText(x.responseText) } catch (e) {}
        }
        x.open("GET", url)
        x.send()
    }

    SkyView {
        anchors.fill: parent
        time: live.skyTime
        liveTime: live.now
        lat: live.lat
        lng: live.lng
        facing: config.facing !== undefined ? config.facing : 180
        limitMag: live.limits[config.skyMode !== undefined ? config.skyMode : 2]
        labels: config.showLabels !== undefined ? config.showLabels : true
        meteors: config.meteors !== undefined ? config.meteors : true
        sats: live.sats
        passes: live.passes
        weather: live.weather
        landmarks: { try { return config.landmarks ? JSON.parse(config.landmarks) : [] } catch (e) { return [] } }
    }

    // a gentle vignette: darker towards the edges, like looking out at night
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const g = ctx.createRadialGradient(width / 2, height * 0.42, Math.min(width, height) * 0.35,
                                               width / 2, height * 0.42, Math.hypot(width, height) * 0.62)
            g.addColorStop(0, "rgba(0,0,0,0)")
            g.addColorStop(1, "rgba(0,0,0,0.55)")
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
        }
    }

    Hud {
        anchors.fill: parent
        visible: config.showClock !== undefined ? config.showClock : true
        now: live.now
        lat: live.lat
        lng: live.lng
        place: config.placeName || "Dhaka"
        use24h: config.use24h !== undefined ? config.use24h : true
        showInfo: config.showInfo !== undefined ? config.showInfo : true
        prayerMethod: config.prayerMethod || "karachi"
        asrHanafi: config.asrHanafi !== undefined ? config.asrHanafi : true
        weather: live.weather
        passes: live.passes
        sats: live.sats
    }
}
