import QtQuick

// The real weather, drawn into the sky: clouds from the live cloud cover, drifting the
// way the wind actually blows and lit by whatever is lighting them (city glow, Moon,
// sunset, day); haze near the horizon from the real PM2.5 (a bad-air Dhaka night goes
// murky brown); and fog. Rain is its own layer (Rain.qml), in front of the city.
Item {
    id: atm

    property var cam
    property var weather: null
    property real sunAlt: -30
    property real moonlight: 0
    property real time: Date.now()
    clip: true

    readonly property real s: cam ? Math.max(0.6, cam.h / 1440) : 1
    readonly property real cover: weather && weather.cloud !== undefined ? weather.cloud / 100 : 0
    readonly property real pm25: weather && weather.pm25 ? weather.pm25 : 0
    readonly property bool raining: !!weather && ((weather.rain || 0) > 0.05 || [51, 53, 55, 61, 63, 65, 80, 81, 82, 95, 96, 99].indexOf(weather.code) >= 0)
    readonly property bool foggy: !!weather && (weather.code === 45 || weather.code === 48 || (weather.vis !== undefined && weather.vis < 2000))
    // wind -> screen drift: we face south, so east is to the left; wind FROM the west blows left
    readonly property real drift: {
        if (!weather || weather.wind === undefined || !cam) return -6
        const toward = (weather.windDir + 180) * Math.PI / 180            // direction the air moves to
        const east = Math.sin(toward)                                        // + = towards the east
        const dx = -east * Math.cos((cam.az0 - 180) * Math.PI / 180)        // east is screen-left
        return dx * Math.max(4, weather.wind * 2.2) * s                      // px per second
    }

    // light on the clouds: 0 night .. 1 day, plus a sunset tint
    readonly property real dayK: Math.max(0, Math.min(1, (sunAlt + 4) / 14))
    readonly property real sunsetK: Math.max(0, 1 - Math.abs(sunAlt - 1) / 8)
    readonly property int lightKey: Math.round(dayK * 10) * 100 + Math.round(sunsetK * 10) * 10 + Math.round(moonlight * 5)
    onLightKeyChanged: clouds.requestPaint()
    onCoverChanged: clouds.requestPaint()
    onCamChanged: { clouds.requestPaint(); haze.requestPaint() }
    onPm25Changed: haze.requestPaint()
    onFoggyChanged: haze.requestPaint()
    onDayKChanged: haze.requestPaint()

    // ---- clouds: one wide, seamless strip, drifting --------------------------------------
    Item {
        id: strip
        width: atm.width * 2
        height: atm.height
        property real offset: 0
        x: -((offset % atm.width) + atm.width) % atm.width
        NumberAnimation on offset {
            from: 0; to: atm.drift >= 0 ? -atm.width : atm.width
            duration: Math.max(60000, atm.width / Math.max(1, Math.abs(atm.drift)) * 1000)
            loops: Animation.Infinite
            running: atm.cover > 0.02
        }
        Canvas {
            id: clouds
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                if (atm.cover <= 0.02 || !atm.cam) return
                const W = atm.width, H = atm.height, s = atm.s
                let seed = 4242
                const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
                // colours: tops and undersides
                const mix = (a, b, f) => a.map((x, i) => x + (b[i] - x) * f)
                let top = mix([46, 44, 58], [236, 238, 244], atm.dayK)
                let under = mix([120, 52, 44], [176, 180, 192], atm.dayK)        // city-lit orange at night
                top = mix(top, [255, 170, 140], atm.sunsetK * 0.6)
                under = mix(under, [190, 70, 80], atm.sunsetK * 0.7)
                top = mix(top, [150, 155, 175], atm.moonlight * (1 - atm.dayK) * 0.6)
                const rgba = (c, a) => "rgba(" + c.map(Math.round).join(",") + "," + a.toFixed(3) + ")"
                // the clouds, made once ...
                const n = Math.round(4 + atm.cover * 22), puffs = []
                for (let k = 0; k < n; k++) {
                    const cx = rnd() * W, cy = H * (0.06 + 0.5 * rnd())
                    const cw = (180 + 380 * rnd()) * s * (0.6 + atm.cover), ch = cw * (0.22 + 0.12 * rnd())
                    const m = 10 + Math.floor(rnd() * 14)
                    for (let i = 0; i < m; i++)
                        puffs.push({ x: cx + (rnd() - 0.5) * cw, y: cy + (rnd() - 0.6) * ch, r: ch * (0.35 + 0.55 * rnd()) })
                }
                // ... and stamped twice, so the strip wraps without a seam
                const a = 0.10 + 0.22 * atm.cover
                for (const dx of [0, W]) {
                    for (const p of puffs) {
                        const px = p.x + dx, py = p.y, r = p.r
                        const g = ctx.createRadialGradient(px, py - r * 0.25, r * 0.1, px, py, r)
                        g.addColorStop(0, rgba(top, a))
                        g.addColorStop(0.55, rgba(mix(top, under, 0.6), a * 0.8))
                        g.addColorStop(1, rgba(under, 0))
                        ctx.fillStyle = g
                        ctx.beginPath(); ctx.arc(px, py, r, 0, 2 * Math.PI); ctx.fill()
                    }
                }
            }
        }
    }

    // ---- haze and fog, hugging the horizon ----------------------------------------------------
    Canvas {
        id: haze
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!atm.cam) return
            const v = atm.cam
            // PM2.5: 15 is clean, 150 is a thick Dhaka winter night
            let k = Math.max(0, Math.min(1, (atm.pm25 - 15) / 135))
            if (atm.foggy) k = Math.max(k, 0.9)
            if (k <= 0.01) return
            const c = atm.foggy ? (atm.dayK > 0.5 ? [200, 200, 205] : [70, 66, 70])
                                : (atm.dayK > 0.5 ? [196, 174, 150] : [96, 64, 48])
            const g = ctx.createRadialGradient(v.hx, v.hy, v.hr * (0.78 - 0.12 * k), v.hx, v.hy, v.hr)
            g.addColorStop(0, "rgba(" + c.join(",") + ",0)")
            g.addColorStop(0.7, "rgba(" + c.join(",") + "," + (0.25 * k).toFixed(3) + ")")
            g.addColorStop(1, "rgba(" + c.join(",") + "," + (0.6 * k).toFixed(3) + ")")
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
        }
    }
}
