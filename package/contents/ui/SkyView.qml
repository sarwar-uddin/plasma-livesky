import QtQuick
import "../code/view.js" as View
import "../code/sky.js" as Sky
import "../code/solar.js" as Solar
import "../code/catalog.js" as Cat
import "../code/milkyway.js" as MW
import "../code/sgp4.mjs" as G

// The sky, full screen, in layers:
//   sky colour + skyglow  ->  Milky Way (blurred)  ->  stars, figures, planets, Moon, Sun
//   ->  ground + compass  ->  satellites (1 Hz)  ->  meteors
// The heavy layers repaint when the sky steps (20 s); satellites move every second.
Item {
    id: view

    property real time: Date.now()          // the sky's time (ms), stepped
    property real liveTime: Date.now()      // every second, for satellites
    property real lat: 23.8103
    property real lng: 90.4125
    property real facing: 180               // azimuth at the centre of the screen
    property real limitMag: 5.5
    property bool labels: true
    property var sats: []
    property var passes: []
    property bool meteors: true
    property var weather: null
    property var landmarks: []
    property var brightStars: []

    readonly property var cam: View.make(width, height, facing, 12)     // near level (a flatter horizon), centred low so the sky still fills the screen
    readonly property real sunAlt: Sky.body("Sun", time, lat, lng).alt
    readonly property real nightK: Math.max(0, Math.min(1, (-sunAlt - 4) / 12))     // 0 day .. 1 full night
    // a bright Moon high up washes out the Milky Way and the faintest stars
    readonly property real moonlight: {
        const m = Sky.body("Moon", time, lat, lng)
        if (m.alt <= 0) return 0
        return Solar.moonPhase(new Date(time)).illum * Math.min(1, m.alt / 25)
    }

    // the ground only changes with daylight; the Milky Way slowly enough for 2 minutes
    property real groundDay: -1
    onTimeChanged: {
        bg.requestPaint(); stars.requestPaint(); trackLayer.requestPaint()
        const d = Math.round(smooth(-6, 10, sunAlt) * 20)
        if (d !== groundDay) { groundDay = d; ground.requestPaint() }
        if (Math.abs(time - mw.paintedAt) > 120000) mw.requestPaint()
    }
    onPassesChanged: trackLayer.requestPaint()
    onWidthChanged: repaintAll()
    onHeightChanged: repaintAll()
    onFacingChanged: repaintAll()
    onLimitMagChanged: repaintAll()
    function repaintAll() { bg.requestPaint(); mw.requestPaint(); stars.requestPaint(); ground.requestPaint(); trackLayer.requestPaint() }

    function smooth(e0, e1, x) { const t = Math.max(0, Math.min(1, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t) }
    function mix(a, b, f) { return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f] }
    function rgba(c, a) { return "rgba(" + Math.round(c[0]) + "," + Math.round(c[1]) + "," + Math.round(c[2]) + "," + a + ")" }

    // equatorial (ra, dec of date) -> screen, via the local sidereal time
    function eqProjector(t, clamped) {
        const jd = Sky.jdOf(t), sφ = Math.sin(lat * View.RAD), cφ = Math.cos(lat * View.RAD)
        const lst = Sky.gmst(jd) + lng
        const proj = clamped ? View.projectClamped : View.project
        return (ra, sd, cd) => {
            const H = (lst - ra) * View.RAD, cH = Math.cos(H)
            const z = sφ * sd + cφ * cd * cH
            const p = proj(cam, -cd * Math.sin(H), sd * cφ - cd * sφ * cH, z)
            p.z = z
            return p
        }
    }

    // ---- sky colour, skyglow, twilight ----------------------------------------------
    Canvas {
        id: bg
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const v = view.cam, sa = view.sunAlt
            // night colours sampled from rooftop photos: near-black above, a grey-green haze
            // glow over the horizon from the city's lights, stronger in dirtier air
            const nightTop = [3, 4, 5], nightLow = [15, 17, 17]
            const dayTop = [24, 52, 96], dayLow = [92, 124, 160]
            const twiTop = [14, 18, 44], twiLow = [70, 52, 78]
            const dk = view.smooth(-2, 12, sa), tk = 1 - Math.abs(Math.max(-18, Math.min(6, sa)) + 6) / 12
            let top = view.mix(nightTop, dayTop, dk), low = view.mix(nightLow, dayLow, dk)
            if (sa < 6 && sa > -18) { top = view.mix(top, twiTop, 0.5 * tk); low = view.mix(low, twiLow, 0.7 * tk) }
            // vertical: zenith -> horizon
            const zen = View.projectAltAz(v, 90, v.az0)
            const g = ctx.createLinearGradient(0, Math.min(0, zen.y), 0, v.hy + v.hr * 0.98)
            g.addColorStop(0, view.rgba(top, 1))
            g.addColorStop(0.75, view.rgba(view.mix(top, low, 0.6), 1))
            g.addColorStop(1, view.rgba(low, 1))
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
            // city skyglow: light scattered off the haze, all the way round the horizon
            const haze = Math.max(0, Math.min(1, ((view.weather && view.weather.pm25) || 40) / 120))
            const gk = view.nightK * (0.55 + 0.45 * haze)
            const glow = ctx.createRadialGradient(v.hx, v.hy, v.hr * 0.72, v.hx, v.hy, v.hr)
            glow.addColorStop(0, "rgba(88,90,88,0)")
            glow.addColorStop(0.6, "rgba(96,98,94," + (0.10 * gk + 0.02).toFixed(3) + ")")
            glow.addColorStop(0.9, "rgba(118,116,106," + (0.22 * gk + 0.04).toFixed(3) + ")")
            glow.addColorStop(1, "rgba(140,132,114," + (0.32 * gk + 0.05).toFixed(3) + ")")
            ctx.fillStyle = glow
            ctx.fillRect(0, 0, width, height)
            // the Sun's side of the sky in twilight
            if (sa > -18 && sa < 10) {
                const sun = Sky.body("Sun", view.time, view.lat, view.lng)
                const p = View.projectAltAz(v, Math.max(-3, sa), sun.az)
                if (p.ok) {
                    const k = tk
                    const sg = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, v.k * 1.6)
                    sg.addColorStop(0, "rgba(255,150,80," + (0.55 * k).toFixed(3) + ")")
                    sg.addColorStop(0.25, "rgba(224,32,63," + (0.25 * k).toFixed(3) + ")")
                    sg.addColorStop(1, "rgba(60,30,80,0)")
                    ctx.fillStyle = sg
                    ctx.fillRect(0, 0, width, height)
                }
            }
        }
    }

    // ---- the Milky Way: five nested glows, blurred on the GPU ---------------------------
    Canvas {
        id: mw
        anchors.fill: parent
        property real paintedAt: 0
        opacity: view.nightK * (view.limitMag >= 5 ? 1 : 0.5) * (1 - 0.75 * view.moonlight)
        onPaint: {
            paintedAt = view.time
            const ctx = getContext("2d")
            ctx.reset()
            if (view.nightK <= 0 || view.limitMag < 4) return
            const P = view.eqProjector(view.time, true)
            const years = (Sky.jdOf(view.time) - 2451545) / 365.25
            const alphas = [0.035, 0.04, 0.05, 0.06, 0.07]
            const scale = Math.max(1, view.cam.w / 1920)
            ctx.lineJoin = "round"
            for (let l = 0; l < MW.LEVELS.length; l++) {
                ctx.fillStyle = "rgba(205,215,255," + alphas[l] + ")"
                for (const poly of MW.LEVELS[l]) {
                    ctx.beginPath()
                    let pen = false
                    for (let i = 0; i < poly.length; i += 2) {
                        const pr = Sky.precess(poly[i], poly[i + 1], years)
                        const p = P(pr[0], Math.sin(pr[1] * View.RAD), Math.cos(pr[1] * View.RAD))
                        if (!p.ok) { pen = false; continue }
                        if (pen) ctx.lineTo(p.x, p.y); else { ctx.moveTo(p.x, p.y); pen = true }
                    }
                    ctx.closePath()
                    ctx.fill()
                    // soft edges without a shader: wide, faint strokes around each level
                    for (const [wdt, k] of [[80, 0.12], [62, 0.14], [46, 0.16], [32, 0.18], [20, 0.2], [10, 0.22]]) {
                        ctx.lineWidth = wdt * scale
                        ctx.strokeStyle = "rgba(205,215,255," + (alphas[l] * k).toFixed(4) + ")"
                        ctx.stroke()
                    }
                }
            }
        }
    }

    // ---- stars, figures, planets, Moon, Sun -------------------------------------------
    Canvas {
        id: stars
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const v = view.cam, t = view.time
            const P = view.eqProjector(t)
            const jd = Sky.jdOf(t), years = (jd - 2451545) / 365.25
            const sa = view.sunAlt
            const skyLimit = sa > -1 ? -1.5 : sa > -6 ? 1 : sa > -12 ? 1 + (-6 - sa) / 6 * 2.5 : sa > -18 ? 3.5 + (-12 - sa) / 6 * 2 : 6
            const lim = Math.min(view.limitMag - 1.2 * view.moonlight, skyLimit)
            const scale = Math.max(1, v.w / 1920)

            // constellation figures
            if (lim > 2.5) {
                ctx.strokeStyle = "rgba(120,140,210," + (0.22 * view.smooth(2.5, 4.5, lim)).toFixed(3) + ")"
                ctx.lineWidth = 1 * scale
                for (const L of Cat.LINES) {
                    ctx.beginPath()
                    let pen = false
                    for (let i = 0; i < L.length; i += 2) {
                        const pr = Sky.precess(L[i], L[i + 1], years)
                        const p = P(pr[0], Math.sin(pr[1] * View.RAD), Math.cos(pr[1] * View.RAD))
                        if (!p.ok || p.z < -0.15) { pen = false; continue }
                        if (pen) ctx.lineTo(p.x, p.y); else { ctx.moveTo(p.x, p.y); pen = true }
                    }
                    ctx.stroke()
                }
            }

            // stars
            const S = Sky.stars(jd)
            const bright = []
            for (let i = 0; i < S.n; i++) {
                const m = S.mag[i]
                if (m > lim) continue
                const p = P(S.ra[i], S.sd[i], S.cd[i])
                if (p.z < 0 || !View.onScreen(v, p, 10)) continue
                const fade = view.smooth(0, 0.2, p.z) * Math.min(1, (lim + 0.7 - m) / 1.8)
                if (fade < 0.03) continue
                const c = Sky.bvColor(S.bv[i])
                const r = Math.max(0.6, 3.0 - 0.45 * m) * scale
                if (m < 2.2) {
                    const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, r * 4.5)
                    g.addColorStop(0, view.rgba(c, (0.32 * fade).toFixed(3)))
                    g.addColorStop(1, view.rgba(c, 0))
                    ctx.fillStyle = g
                    ctx.beginPath(); ctx.arc(p.x, p.y, r * 4.5, 0, 2 * Math.PI); ctx.fill()
                }
                ctx.fillStyle = view.rgba(view.mix(c, [255, 255, 255], 0.4), fade.toFixed(3))
                ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * Math.PI); ctx.fill()
                if (m < 1.7 && p.z > 0.03 && fade > 0.5) bright.push({ x: p.x, y: p.y, r: r, c: c, z: p.z })
            }
            view.brightStars = bright

            // names: bright stars and constellations
            if (view.labels && lim > 1) {
                ctx.textBaseline = "middle"
                ctx.font = Math.round(11 * scale) + "px sans-serif"
                ctx.textAlign = "left"
                for (const s of Cat.NAMED) {
                    if (s[3] > Math.min(1.6, lim)) continue
                    const pr = Sky.precess(s[1], s[2], years)
                    const p = P(pr[0], Math.sin(pr[1] * View.RAD), Math.cos(pr[1] * View.RAD))
                    if (p.z < 0.06 || !View.onScreen(v, p)) continue
                    ctx.fillStyle = "rgba(185,190,215,0.45)"
                    ctx.fillText(s[0], p.x + 8 * scale, p.y + 1)
                }
                if (lim > 3.5) {
                    ctx.font = Math.round(10 * scale) + "px sans-serif"
                    ctx.textAlign = "center"
                    ctx.fillStyle = "rgba(120,140,210,0.38)"
                    for (const c of Cat.CONSTELLATIONS) {
                        if (c[3] > 1) continue
                        const pr = Sky.precess(c[1], c[2], years)
                        const p = P(pr[0], Math.sin(pr[1] * View.RAD), Math.cos(pr[1] * View.RAD))
                        if (p.z < 0.12 || !View.onScreen(v, p)) continue
                        ctx.fillText(c[0].toUpperCase().split("").join(" "), p.x, p.y)
                    }
                }
            }

            // planets
            ctx.font = "bold " + Math.round(12 * scale) + "px sans-serif"
            for (const name of Sky.PLANETS) {
                const b = Sky.body(name, t, view.lat, view.lng)
                if (b.alt < -0.5) continue
                const p = View.projectAltAz(v, b.alt, b.az)
                if (!View.onScreen(v, p, 20)) continue
                if (b.mag > lim + 1) continue
                const col = Qt.color(b.color)
                const r = Math.max(1.6, Math.min(5.5, 3.6 - 0.5 * b.mag)) * scale
                const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, r * 5)
                g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.5))
                g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0))
                ctx.fillStyle = g
                ctx.beginPath(); ctx.arc(p.x, p.y, r * 5, 0, 2 * Math.PI); ctx.fill()
                const gb = ctx.createRadialGradient(p.x - r * 0.3, p.y - r * 0.3, r * 0.1, p.x, p.y, r)
                gb.addColorStop(0, "#FFFFFF"); gb.addColorStop(0.55, b.color); gb.addColorStop(1, Qt.darker(b.color, 1.6))
                ctx.fillStyle = gb
                ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * Math.PI); ctx.fill()
                if (name === "Saturn") {
                    ctx.strokeStyle = "rgba(230,204,144,0.85)"
                    ctx.lineWidth = 1.2 * scale
                    ctx.beginPath(); ctx.ellipse(p.x - r * 2.1, p.y - r * 0.65, r * 4.2, r * 1.3); ctx.stroke()
                }
                if (view.labels) {
                    ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.9)
                    ctx.textAlign = "left"
                    ctx.fillText(name, p.x + r + 7 * scale, p.y - r - 4 * scale)
                }
            }

            // the Moon, drawn about four times its real size so its face reads
            const moon = Sky.body("Moon", t, view.lat, view.lng)
            if (moon.alt > -1) {
                const p = View.projectAltAz(v, moon.alt, moon.az)
                if (View.onScreen(v, p, 60)) {
                    const d = new Date(t)
                    const phase = Solar.moonPhase(d)
                    const r = Math.max(26 * Math.max(1, v.h / 1440), View.scaleAt(v, moon.alt, moon.az) * 0.26 * 5)
                    const halo = ctx.createRadialGradient(p.x, p.y, r * 0.9, p.x, p.y, r * 6)
                    halo.addColorStop(0, "rgba(215,220,240," + (0.06 + 0.22 * phase.illum).toFixed(3) + ")")
                    halo.addColorStop(1, "rgba(215,220,240,0)")
                    ctx.fillStyle = halo
                    ctx.beginPath(); ctx.arc(p.x, p.y, r * 6, 0, 2 * Math.PI); ctx.fill()
                    Solar.drawMoon(ctx, p.x, p.y, r, phase, Solar.moonView(d, view.lat, view.lng), view.lat < 0)
                }
            }
            // the Sun
            if (sa > -1) {
                const sun = Sky.body("Sun", t, view.lat, view.lng)
                const p = View.projectAltAz(v, sa, sun.az)
                if (View.onScreen(v, p, 80)) {
                    const glare = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, 160 * scale)
                    glare.addColorStop(0, "rgba(255,240,210,0.55)")
                    glare.addColorStop(1, "rgba(255,200,150,0)")
                    ctx.fillStyle = glare
                    ctx.beginPath(); ctx.arc(p.x, p.y, 160 * scale, 0, 2 * Math.PI); ctx.fill()
                    Solar.drawSun(ctx, p.x, p.y, 14 * scale, sa)
                }
            }
        }
    }

    Life {
        anchors.fill: parent
        cam: view.cam
        brightStars: view.nightK > 0.6 ? view.brightStars : []
        sunAlt: view.sunAlt
        time: view.liveTime
    }

    Atmosphere {
        id: atmosphere
        anchors.fill: parent
        cam: view.cam
        weather: view.weather
        sunAlt: view.sunAlt
        moonlight: view.moonlight
        time: view.time
    }

    // ---- ground ---------------------------------------------------------------------------
    Canvas {
        id: ground
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const v = view.cam
            const scale = Math.max(1, v.w / 1920)
            // everything outside the horizon circle
            ctx.fillRule = Qt.OddEvenFill
            ctx.beginPath()
            ctx.rect(-10, -10, width + 20, height + 20)
            ctx.arc(v.hx, v.hy, v.hr, 0, 2 * Math.PI)
            const g = ctx.createRadialGradient(v.hx, v.hy, v.hr, v.hx, v.hy, v.hr + v.h * 0.5)
            const day = view.smooth(-6, 10, view.sunAlt)
            g.addColorStop(0, view.rgba(view.mix([16, 10, 12], [36, 34, 34], day), 1))
            g.addColorStop(0.15, view.rgba(view.mix([8, 6, 8], [22, 21, 22], day), 1))
            g.addColorStop(1, view.rgba(view.mix([3, 3, 4], [12, 12, 13], day), 1))
            ctx.fillStyle = g
            ctx.fill()
            // a thin glowing horizon
            ctx.strokeStyle = "rgba(150,160,158,0.2)"
            ctx.lineWidth = 1.2 * scale
            ctx.beginPath(); ctx.arc(v.hx, v.hy, v.hr, 0, 2 * Math.PI); ctx.stroke()
            // compass points along it
            ctx.font = Math.round(12 * scale) + "px sans-serif"
            ctx.textAlign = "center"
            ctx.textBaseline = "top"
            const pts = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            for (let i = 0; i < 8; i++) {
                const p = View.projectAltAz(v, -1.6, i * 45)
                if (!View.onScreen(v, p, -20)) continue
                ctx.fillStyle = i % 2 ? "rgba(154,154,162,0.55)" : "rgba(224,32,63,0.8)"
                ctx.fillText(pts[i], p.x, p.y)
            }
            for (let az = 0; az < 360; az += 15) {
                if (az % 45 === 0) continue
                const a = View.projectAltAz(v, 0, az), b = View.projectAltAz(v, -0.8, az)
                if (!View.onScreen(v, a, -20)) continue
                ctx.strokeStyle = "rgba(154,154,162,0.35)"
                ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke()
            }
        }
    }

    City {
        anchors.fill: parent
        cam: view.cam
        time: view.time
        sunAlt: view.sunAlt
        landmarks: view.landmarks
    }

    Planes {
        anchors.fill: parent
        cam: view.cam
        lat: view.lat
        lng: view.lng
        sunAlt: view.sunAlt
    }

    // ---- satellites -------------------------------------------------------------------------
    // Every 15 s the whole list is scanned for the ones that are up (or about to be);
    // every second only those few are moved. They're small QML items, not a canvas,
    // so a moving dot costs next to nothing.
    readonly property var satObs: G.observer(lat, lng, 0)
    property var satCandidates: []
    property var satPoints: []
    property real satScannedAt: 0
    function updateSats() {
        const t = liveTime
        if (G.sunAlt(t, satObs) >= -6) { if (satPoints.length) satPoints = []; satCandidates = []; return }
        if (Math.abs(t - satScannedAt) > 15000) {
            satScannedAt = t
            satCandidates = sats.filter(s => { const l = G.look(s, t, satObs); return l && l.alt > -8 })
        }
        const pts = []
        for (const s of satCandidates) {
            const l = G.look(s, t, satObs)
            if (!l || l.alt < 1 || !l.sunlit) continue
            const p = View.projectAltAz(cam, l.alt, l.az)
            if (!View.onScreen(cam, p)) continue
            pts.push({ x: p.x, y: p.y, label: G.NAMES[s.id] || "" })
        }
        if (pts.length || satPoints.length) satPoints = pts
    }
    onLiveTimeChanged: updateSats()
    onSatsChanged: satScannedAt = 0

    // the tracks of passes happening soon: static paths, redrawn with the sky
    Canvas {
        id: trackLayer
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const v = view.cam, t = view.time
            const scale = Math.max(1, v.w / 1920)
            for (const p of view.passes) {
                if (p.end < t - 60000 || p.start > t + 45 * 60000) continue
                ctx.setLineDash([6, 5])
                ctx.strokeStyle = "rgba(224,32,63,0.7)"
                ctx.lineWidth = 1.4 * scale
                ctx.beginPath()
                let pen = false
                for (const q of p.track) {
                    const s = View.projectAltAz(v, q.alt, q.az)
                    if (!s.ok) { pen = false; continue }
                    if (pen) ctx.lineTo(s.x, s.y); else { ctx.moveTo(s.x, s.y); pen = true }
                }
                ctx.stroke()
                ctx.setLineDash([])
                const a = View.projectAltAz(v, p.startAlt, p.startAz)
                if (a.ok) {
                    ctx.fillStyle = "rgba(224,32,63,0.95)"
                    ctx.font = Math.round(12 * scale) + "px sans-serif"
                    ctx.textAlign = "left"
                    ctx.fillText(p.label + " " + new Date(p.start).toLocaleTimeString(Qt.locale(), Locale.ShortFormat), a.x + 8, a.y - 8)
                }
            }
        }
    }
    Repeater {
        model: 48                       // a fixed pool: no items created or destroyed per tick
        Item {
            required property int index
            readonly property var pt: index < view.satPoints.length ? view.satPoints[index] : null
            readonly property real u: Math.max(1, view.width / 1920)
            visible: pt !== null
            x: pt ? pt.x : 0
            y: pt ? pt.y : 0
            Rectangle {                 // crimson halo for the named ones
                visible: !!parent.pt && parent.pt.label !== ""
                width: 26 * parent.u; height: width; radius: width / 2
                x: -width / 2; y: -height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#66E0203F" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                readonly property real d: (parent.pt && parent.pt.label ? 5.6 : 2.6) * parent.u
                width: d; height: d; radius: d / 2
                x: -d / 2; y: -d / 2
                color: parent.pt && parent.pt.label ? "#F4F4F8" : "#D8F0F0FA"
            }
            Text {
                visible: !!parent.pt && parent.pt.label !== ""
                text: parent.pt ? parent.pt.label : ""
                x: 10 * parent.u; y: -22 * parent.u
                font.pixelSize: 13 * parent.u
                font.bold: true
                color: "#E0203F"
            }
        }
    }

    Rain {
        anchors.fill: parent
        weather: view.weather
        drift: atmosphere.drift
        dayK: atmosphere.dayK
    }

    // ---- meteors ------------------------------------------------------------------------------
    Meteors {
        anchors.fill: parent
        enabled: view.meteors
        cam: view.cam
        time: view.liveTime
        lat: view.lat
        lng: view.lng
        nightK: view.nightK
    }
}
