import QtQuick
import QtCore
import "../code/view.js" as View

// Real aircraft, from OpenSky via livesky-planes.
//
// Between reports every plane is flown on by dead reckoning, every frame: along an arc
// at the turn rate seen between its last two reports (so arrivals swing onto final
// instead of overshooting), at its speed and climb or descent rate. When a new report
// lands, the jump between where we'd flown it and where it really is gets eased away
// over a few seconds rather than snapping.
//
// Each one is drawn at its true angular size: side-on when it's low (as arrivals are),
// seen from below when it's high overhead. Only the wingtip light on your side shows
// (red if you're off its left wing, green off its right), the beacon and strobes
// flash, and the landing lights blaze only when it's pointed at you.
Item {
    id: air

    property var cam
    property real lat: 23.8103
    property real lng: 90.4125
    property real sunAlt: -30
    readonly property real s: cam ? Math.max(0.6, cam.h / 1440) : 1

    readonly property string file: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/livesky/planes.qml"
    property var tracks: ({})        // id -> { rep, turn, corr: { n, e, a, at } }
    property var slots: []           // ids currently shown, in a stable order
    property real fetched: 0
    property real frameTime: Date.now()
    property real maxAltitude: 1000          // metres; higher traffic is out of earshot

    // ---- data -------------------------------------------------------------------------
    property int gen: 0
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: air.gen++ }
    Loader {
        source: air.file + "?" + air.gen          // fresh URL, so the engine re-reads the file
        onLoaded: air.ingest(item.planes || [], item.fetched || 0)
    }

    function ingest(planes, fetchedAt) {
        if (fetchedAt <= fetched) return
        fetched = fetchedAt
        const now = Date.now(), next = {}
        for (const r of planes) {
            const old = tracks[r.id]
            const tr = { rep: r, turn: 0, corr: { n: 0, e: 0, a: 0, at: now } }
            if (old) {
                if (r.t <= old.rep.t) { next[r.id] = old; continue }       // nothing new for this one
                // turn rate from consecutive reports (deg/s), within reason
                const dt = (r.t - old.rep.t) / 1000
                if (dt > 3 && dt < 150) {
                    let dh = r.trk - old.rep.trk
                    dh = ((dh + 540) % 360) - 180
                    tr.turn = Math.max(-3.5, Math.min(3.5, dh / dt))
                    if (Math.abs(tr.turn) < 0.08) tr.turn = 0
                }
                // ease the jump: where we'd have flown it, minus where it is
                const was = position(old, now), is = position(tr, now)
                tr.corr = { n: was.n - is.n, e: was.e - is.e, a: was.alt - is.alt, at: now }
            }
            next[r.id] = tr
        }
        tracks = next
        // keep slot order stable: survivors keep their place, newcomers go to free slots
        const ids = Object.keys(next)
        const kept = slots.filter(id => next[id])
        for (const id of ids) if (kept.indexOf(id) < 0) kept.push(id)
        slots = kept.slice(0, 12)
    }

    // position at time t, in metres north/east of the report plus altitude, with corrections
    function position(tr, t) {
        const r = tr.rep
        const dt = Math.min(240, Math.max(0, (t - r.t) / 1000))
        const v = r.v, h0 = r.trk * Math.PI / 180, w = tr.turn * Math.PI / 180
        let n, e
        const tt = Math.min(dt, 45)                                 // a turn rarely lasts longer
        if (Math.abs(w) > 1e-4) {
            n = v / w * (Math.sin(h0 + w * tt) - Math.sin(h0))
            e = v / w * (Math.cos(h0) - Math.cos(h0 + w * tt))
        } else { n = v * tt * Math.cos(h0); e = v * tt * Math.sin(h0) }
        const h1 = h0 + w * tt
        n += v * (dt - tt) * Math.cos(h1); e += v * (dt - tt) * Math.sin(h1)
        const k = Math.exp(-(t - tr.corr.at) / 4000)
        return { n: n + tr.corr.n * k, e: e + tr.corr.e * k, alt: Math.max(0, r.alt + r.vr * dt + tr.corr.a * k),
                 heading: h1 * 180 / Math.PI }
    }
    // as seen from here: { alt, az, dist, lat, lon, alt_m, heading }
    function sight(tr, t) {
        const r = tr.rep, p = position(tr, t)
        const plat = r.lat + p.n / 110540, plon = r.lon + p.e / (111320 * Math.cos(plat * Math.PI / 180))
        const e = (plon - lng) * 111320 * Math.cos(lat * Math.PI / 180), n = (plat - lat) * 110540
        const d = Math.hypot(e, n)
        const up = p.alt - 20 - d * d / (2 * 6371000)               // you're on a rooftop, ~20 m up
        return { alt: Math.atan2(up, d) * 180 / Math.PI, az: (Math.atan2(e, n) * 180 / Math.PI + 360) % 360,
                 dist: Math.hypot(d, up), ground: d, e: e, n: n, altm: p.alt, heading: p.heading }
    }

    // smooth: one update per rendered frame while anything is being tracked
    FrameAnimation {
        running: air.slots.length > 0 && Date.now() - air.fetched < 600000
        onTriggered: air.frameTime = Date.now()
    }

    // rough size from the airline: wide-bodies, regional turboprops, the rest
    function lengthOf(cs) {
        const p = (cs || "").slice(0, 3)
        if (["UAE", "QTR", "ETD", "THY", "SVA", "SIA", "CPA", "MAS", "KAL", "CSN", "ETH", "OMA"].indexOf(p) >= 0) return 64
        if (["NVQ", "AWA"].indexOf(p) >= 0) return 27
        return 36
    }

    Repeater {
        model: 12
        Item {
            id: plane
            required property int index
            readonly property string pid: index < air.slots.length ? air.slots[index] : ""
            readonly property var tr: pid ? air.tracks[pid] : null
            // everything about where it is this frame
            readonly property var st: {
                air.frameTime
                if (!tr || !air.cam) return null
                const a = air.sight(tr, air.frameTime)
                // only the low ones you can hear: arrivals and departures below 1000 m
                if (a.altm < 15 || a.alt < 0.2 || a.altm > air.maxAltitude) return null
                const p = View.projectAltAz(air.cam, a.alt, a.az)
                if (!View.onScreen(air.cam, p, 80)) return null
                const b = air.sight(tr, air.frameTime + 3000)
                const q = View.projectAltAz(air.cam, b.alt, b.az)
                const len = Math.hypot(q.x - p.x, q.y - p.y) || 1
                // size on screen: true length at its distance
                const deg = tr.rep && air.lengthOf(tr.rep.cs) / a.dist * 180 / Math.PI
                const px = Math.max(6 * air.s, deg * View.scaleAt(air.cam, a.alt, a.az))
                // which side of it are you on? (cross product of its heading with the line to you)
                const hx = Math.sin(a.heading * Math.PI / 180), hy = Math.cos(a.heading * Math.PI / 180)
                const toYou = { e: -a.e, n: -a.n }
                const rightSide = hx * toYou.n - hy * toYou.e < 0
                // landing lights: low, descending or slow, and pointed your way
                const gd = Math.hypot(toYou.e, toYou.n) || 1
                const facing = (hx * toYou.e + hy * toYou.n) / gd
                const lights = (a.altm < 2500 && (tr.rep.vr < -0.5 || a.altm < 700)) ? Math.max(0, facing) : 0
                return { fade: Math.max(0, Math.min(1, (air.maxAltitude - a.altm) / 120)), x: p.x, y: p.y, dx: (q.x - p.x) / len, dy: (q.y - p.y) / len, px: px, side: a.alt < 28,
                         green: rightSide, lights: lights, near: a.dist < 4000,
                         label: (tr.rep.cs || tr.rep.id) + "  " + Math.round(a.altm / 10) * 10 + " m" + (tr.rep.vr < -1 && a.altm < 2500 ? "  ↓ DAC" : "") }
            }
            visible: st !== null
            opacity: st ? st.fade : 0
            x: st ? st.x : 0
            y: st ? st.y : 0

            // landing-light glare, sized by how straight at you it's pointing
            Rectangle {
                visible: !!plane.st && plane.st.lights > 0.05
                readonly property real d: plane.st ? (plane.st.px * 1.4 + 26 * air.s) * (0.4 + plane.st.lights) : 0
                width: d; height: d; radius: d / 2
                x: -d / 2 + (plane.st ? plane.st.dx * plane.st.px * 0.45 : 0); y: -d / 2 + (plane.st ? plane.st.dy * plane.st.px * 0.45 : 0)
                opacity: plane.st ? Math.min(1, plane.st.lights * 1.3) : 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.42; color: "#66FFF4DC" }
                    GradientStop { position: 0.5; color: "#FFFFFDF4" }
                    GradientStop { position: 0.58; color: "#66FFF4DC" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // the aircraft itself, drawn pointing right and turned to its direction of travel
            Canvas {
                id: body
                readonly property real len: plane.st ? Math.round(plane.st.px) : 10
                readonly property bool side: plane.st ? plane.st.side : true
                width: len * 1.2; height: len * 1.2
                x: -width / 2; y: -height / 2
                readonly property bool goingLeft: !!plane.st && plane.st.dx < 0
                transform: [
                    Scale { origin.x: body.width / 2; origin.y: body.height / 2; xScale: body.goingLeft ? -1 : 1 },
                    Rotation { origin.x: body.width / 2; origin.y: body.height / 2
                               angle: plane.st ? Math.atan2(plane.st.dy, body.goingLeft ? -plane.st.dx : plane.st.dx) * 180 / Math.PI * (body.goingLeft ? -1 : 1) : 0 }
                ]
                onLenChanged: requestPaint()
                onSideChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const L = body.len, cx = width / 2, cy = height / 2
                    const g = ctx.createLinearGradient(0, cy - L * 0.08, 0, cy + L * 0.08)
                    g.addColorStop(0, "#5C636B"); g.addColorStop(1, "#9AA2AA")   // belly lit by the city below
                    ctx.fillStyle = g
                    if (body.side) {
                        // fuselage
                        ctx.beginPath(); ctx.ellipse(cx - L / 2, cy - L * 0.055, L, L * 0.11); ctx.fill()
                        // tail fin and stabiliser
                        ctx.beginPath()
                        ctx.moveTo(cx - L * 0.40, cy - L * 0.03); ctx.lineTo(cx - L * 0.50, cy - L * 0.26)
                        ctx.lineTo(cx - L * 0.43, cy - L * 0.26); ctx.lineTo(cx - L * 0.28, cy - L * 0.04); ctx.closePath(); ctx.fill()
                        ctx.fillRect(cx - L * 0.48, cy - L * 0.025, L * 0.16, L * 0.03)
                        // wing and engine
                        ctx.fillRect(cx - L * 0.12, cy + L * 0.02, L * 0.3, L * 0.03)
                        ctx.beginPath(); ctx.ellipse(cx - L * 0.02, cy + L * 0.04, L * 0.13, L * 0.06); ctx.fill()
                    } else {
                        // seen from below: fuselage, swept wings, tailplane
                        ctx.beginPath(); ctx.ellipse(cx - L / 2, cy - L * 0.05, L, L * 0.1); ctx.fill()
                        ctx.beginPath()
                        ctx.moveTo(cx + L * 0.08, cy); ctx.lineTo(cx - L * 0.14, cy - L * 0.5); ctx.lineTo(cx - L * 0.22, cy - L * 0.5)
                        ctx.lineTo(cx - L * 0.1, cy); ctx.lineTo(cx - L * 0.22, cy + L * 0.5); ctx.lineTo(cx - L * 0.14, cy + L * 0.5)
                        ctx.closePath(); ctx.fill()
                        ctx.beginPath()
                        ctx.moveTo(cx - L * 0.36, cy); ctx.lineTo(cx - L * 0.47, cy - L * 0.16); ctx.lineTo(cx - L * 0.5, cy - L * 0.16)
                        ctx.lineTo(cx - L * 0.46, cy); ctx.lineTo(cx - L * 0.5, cy + L * 0.16); ctx.lineTo(cx - L * 0.47, cy + L * 0.16)
                        ctx.closePath(); ctx.fill()
                    }
                }
            }

            // navigation light on your side, steady
            Rectangle {
                readonly property real d: Math.max(2.4 * air.s, (plane.st ? plane.st.px : 10) * 0.07)
                width: d; height: d; radius: d / 2
                x: -d / 2 + (plane.st ? -plane.st.dx * plane.st.px * 0.05 : 0)
                y: -d / 2 + (plane.st ? (plane.st.side ? plane.st.px * 0.04 : 0) : 0)
                color: plane.st && plane.st.green ? "#40FF7A" : "#FF3A3A"
            }
            // red anti-collision beacon
            Rectangle {
                readonly property real d: Math.max(2.8 * air.s, (plane.st ? plane.st.px : 10) * 0.06)
                width: d; height: d; radius: d / 2
                x: -d / 2; y: -d / 2 - (plane.st ? plane.st.px * 0.06 : 2)
                color: "#FF2020"
                opacity: 0
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    PauseAnimation { duration: 300 + plane.index * 170 }
                    NumberAnimation { to: 1; duration: 60 }
                    PauseAnimation { duration: 120 }
                    NumberAnimation { to: 0; duration: 160 }
                    PauseAnimation { duration: 900 }
                }
            }
            // white strobes, double flash (wingtip and tail)
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    readonly property real d: Math.max(4.5 * air.s, (plane.st ? plane.st.px : 10) * 0.09)
                    width: d; height: d; radius: d / 2
                    x: -d / 2 + (plane.st ? (index ? -0.5 : 0.08) * plane.st.dx * plane.st.px : 0)
                    y: -d / 2 + (plane.st ? (index ? -0.5 : 0.08) * plane.st.dy * plane.st.px : 0)
                    color: "white"
                    opacity: 0
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        PauseAnimation { duration: 700 + plane.index * 230 }
                        NumberAnimation { to: 1; duration: 30 }
                        NumberAnimation { to: 0; duration: 70 }
                        PauseAnimation { duration: 90 }
                        NumberAnimation { to: 1; duration: 30 }
                        NumberAnimation { to: 0; duration: 70 }
                        PauseAnimation { duration: 230 }
                    }
                }
            }
            Text {
                text: plane.st ? plane.st.label : ""
                x: (plane.st ? plane.st.px * 0.5 : 10) + 8 * air.s; y: 10 * air.s
                font.pixelSize: (plane.st && plane.st.near ? 14 : 12) * air.s
                font.family: "JetBrains Mono"
                color: "#9AA2AE"
                opacity: 0.7
            }
        }
    }
}
