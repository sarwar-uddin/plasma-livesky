import QtQuick
import "../code/view.js" as View

// The city as you see it from an 8th-floor rooftop: you look DOWN on most of it.
// Rows of buildings from ~45 m out to ~3 km, each placed by real perspective from your
// eye height: a roof lower than your eye sits below the horizon, nearer rows sit bigger
// and lower, and only the tall ones break the skyline. You see the roofs (tanks, stair
// huts, antenna arrays, rebar) as well as the facades, in Dhaka's colours: exposed
// brick in concrete frames, peach, cream, teal and green paint, white striped towers.
// The haze swallows the distance. Windows light up in the evening and go dark through
// the night. Drawn once and repainted only when the light changes.
Item {
    id: city

    property var cam
    property real time: Date.now()
    property real sunAlt: -30
    property real eye: 31                     // metres above the street: an 8th floor above lower blocks
    property var landmarks: []                // optional [{ az, dist, width, height, kind }]
    // the lights in the sky, to light the city by
    property real sunAz: 180
    property real moonAlt: -10
    property real moonAz: 0
    property real moonlight: 0                // Moon's brightness x height, 0..1 (from the sky)
    property real cloud: 0                    // cloud cover 0..1, dims the Moon
    readonly property real moonK: moonlight * (1 - 0.65 * cloud)
    readonly property real golden: sunAlt > -2 && sunAlt < 14 ? 1 - Math.abs(sunAlt - 4) / 10 : 0
    // repaint when the light has changed enough to see
    readonly property int lightKey: Math.round(moonK * 12) * 10000 + Math.round(golden * 8) * 1000
                                    + Math.round(((moonK > 0.05 ? moonAz : 0) + (golden > 0 ? sunAz : 0)) / 12)

    readonly property real s: cam ? Math.max(0.6, cam.h / 1440) : 1
    readonly property real litFraction: {
        if (sunAlt > 2) return 0.03
        const d = new Date(time), h = d.getHours() + d.getMinutes() / 60
        const k = h >= 17 ? (h < 20 ? 0.5 : h < 23 ? 0.5 - (h - 20) * 0.08 : 0.24 - (h - 23) * 0.05)
                          : h < 5 ? Math.max(0.09, 0.19 - h * 0.02) : h < 7 ? 0.2 : 0.05
        return Math.max(0.06, k)
    }
    readonly property real dayK: Math.max(0, Math.min(1, (sunAlt + 6) / 16))
    property real paintedLit: -1
    property real paintedDay: -1
    onLitFractionChanged: if (Math.abs(litFraction - paintedLit) > 0.02) canvas.requestPaint()
    onDayKChanged: if (Math.abs(dayK - paintedDay) > 0.06) canvas.requestPaint()
    onLightKeyChanged: canvas.requestPaint()
    onCamChanged: canvas.requestPaint()

    // facade colours by day; at night they're dimmed and lit by the haze
    readonly property var colours: [
        [200, 194, 176], [214, 214, 210], [180, 182, 180], [128, 130, 130],     // cream, white, light grey, grey
        [148, 80, 60], [214, 140, 96], [72, 150, 150], [64, 150, 108], [200, 184, 122]  // brick, peach, teal, green, yellow
    ]
    readonly property var weights: [0.2, 0.14, 0.12, 0.1, 0.12, 0.1, 0.08, 0.06, 0.08]

    // is (az, D) inside an open sector from the landmarks list?
    function open(az, D) {
        for (const l of landmarks)
            if (l.kind === "green" && D >= l.dmin && D <= l.dmax && ((az - l.az1) % 360 + 360) % 360 <= ((l.az2 - l.az1) % 360 + 360) % 360)
                return true
        return false
    }

    function build() {
        let seed = 8282
        const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
        const pick = () => { let r = rnd(), i = 0; while (i < weights.length - 1 && r > weights[i]) { r -= weights[i]; i++ } return i }
        const out = []
        const az0 = cam.az0, span = 140
        for (let D = 3000; D >= 34; D /= 1.1) {
            let az = az0 - span + rnd() * 2
            while (az < az0 + span) {
                const w = 8 + rnd() * 16, gap = 1 + rnd() * (D > 400 ? 2 : 6)
                // close by, you look down on lower blocks; further out, anything goes
                // mostly 3-6 storeys all round; only a rare one reaches your level
                const tall = D > 90 && rnd() < (D < 400 ? 0.015 : 0.02)
                const floors = D < 70 ? 2 + Math.floor(rnd() * 4) : tall ? 9 + Math.floor(rnd() * 6) : 3 + Math.floor(rnd() * rnd() * 5)
                // scattered distances, and a street now and then, so the city doesn't sit in tiers
                const Dj = D * (0.85 + rnd() * 0.3)
                if (rnd() < 0.07 || open(az, Dj)) { az += (w + gap) / D / View.RAD; continue }
                out.push({ D: Dj, az1: az, az2: az + w / Dj / View.RAD, H: floors * 3.1 + 1.2,
                           floors: floors, color: pick(), striped: rnd() < 0.12, brickFrame: rnd() < 0.5,
                           roof: rnd(), seed: Math.floor(rnd() * 1e6), depth: 10 + rnd() * 10 })
                az += (w + gap) / D / View.RAD
            }
        }
        for (const l of landmarks) {
            if (l.kind === "green") {           // open ground: drawn as a patch of greenery at its far edge
                out.push({ D: l.dmax, kind: "green", az1: l.az1, az2: l.az2, dmin: l.dmin, dmax: l.dmax, seed: Math.round(l.az1 * 100) })
                continue
            }
            if (l.kind === "road") {             // street lamps along a straight road, each at its own distance
                const toEN = p => [p.dist * Math.sin(p.az * View.RAD), p.dist * Math.cos(p.az * View.RAD)]
                const A = toEN(l.from), B = toEN(l.to), len = Math.hypot(B[0] - A[0], B[1] - A[1])
                for (let x = 0; x <= len; x += 55) {
                    const e = A[0] + (B[0] - A[0]) * x / len, n = A[1] + (B[1] - A[1]) * x / len
                    out.push({ D: Math.hypot(e, n), kind: "lamp", az: Math.atan2(e, n) / View.RAD, seed: Math.round(x) })
                }
                continue
            }
            out.push({ D: l.dist, az1: l.az - l.width / l.dist / View.RAD / 2, az2: l.az + l.width / l.dist / View.RAD / 2,
                       H: l.height, floors: Math.round(l.height / 3.1), color: l.color !== undefined ? l.color : 1,
                       striped: l.kind === "striped", brickFrame: false, roof: l.kind === "antennas" ? 0.995 : 0.5,
                       kind: l.kind, label: l.label || "", seed: Math.round(l.az * 100), depth: 18 })
        }
        out.sort((a, b) => b.D - a.D)
        return out
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!city.cam) return
            city.paintedLit = city.litFraction
            city.paintedDay = city.dayK
            const v = city.cam, s = city.s, eye = city.eye, lit = city.litFraction, day = city.dayK
            const R = View.RAD
            const P = (alt, az) => View.projectAltAz(v, alt, az)
            const altOf = (h, d) => Math.atan2(h - eye, d) / R            // elevation of height h at distance d
            const haze = day > 0.5 ? [176, 178, 176] : [92, 88, 80]        // warm grey, as in the photos
            const mix = (a, b, f) => [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f]
            const rgb = (c, a) => "rgba(" + Math.round(c[0]) + "," + Math.round(c[1]) + "," + Math.round(c[2]) + "," + (a === undefined ? 1 : a) + ")"
            const quad = (a1, a2, lo, hi) => {
                const p1 = P(hi, a1), p2 = P(hi, a2), p3 = P(lo, a2), p4 = P(lo, a1)
                if (!p1.ok || !p2.ok || !p3.ok || !p4.ok) return false
                ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.lineTo(p3.x, p3.y); ctx.lineTo(p4.x, p4.y); ctx.closePath()
                return true
            }
            const visible = az => Math.abs(((az - v.az0) % 360 + 540) % 360 - 180) < 125

            for (const b of city.build()) {
                if (b.kind === "lamp") {
                    if (!visible(b.az) || day > 0.6) continue
                    const p = P(altOf(9, b.D), b.az)
                    if (!p.ok) continue
                    const r = Math.max(1.8, 320 / b.D) * s
                    const fade = Math.exp(-b.D / 1600)
                    const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, r * 3)
                    g.addColorStop(0, "rgba(255,196,120," + (0.95 * fade + 0.2).toFixed(2) + ")")
                    g.addColorStop(0.2, "rgba(255,170,90," + (0.3 * fade).toFixed(2) + ")")
                    g.addColorStop(1, "rgba(255,160,80,0)")
                    ctx.fillStyle = g; ctx.fillRect(p.x - r * 3, p.y - r * 3, r * 6, r * 3 * 2)
                    // traffic: head- and tail-lights now and then
                    if (b.seed % 3 === 0) {
                        const q = P(altOf(1, b.D), b.az + 0.3)
                        ctx.fillStyle = (b.seed % 2) ? "rgba(255,60,50,0.8)" : "rgba(255,250,235,0.85)"
                        if (q.ok) ctx.fillRect(q.x, q.y, Math.max(1.5, 120 / b.D) * s, Math.max(1, 60 / b.D) * s)
                    }
                    continue
                }
                if (b.kind === "green") {
                    if (!visible((b.az1 + b.az2) / 2)) continue
                    // dark open ground with clumps of trees
                    ctx.fillStyle = rgb(mix(mix([42, 70, 44], [0, 0, 0], 0.78 * (1 - day)), haze, Math.min(0.85, 1 - Math.exp(-b.dmin / 1100))))
                    if (quad(b.az1, b.az2, altOf(0, b.dmin), altOf(0, b.dmax))) ctx.fill()
                    let sd = b.seed || 7
                    const rnd = () => { sd = (sd * 16807) % 2147483647; return sd / 2147483647 }
                    for (let k = 0; k < 40; k++) {
                        const az = b.az1 + (b.az2 - b.az1) * rnd(), d = b.dmin + (b.dmax - b.dmin) * rnd() * rnd()
                        const p = P(altOf(4, d), az)
                        if (!p.ok) continue
                        const r = Math.max(2, 7 / d / R * View.scaleAt(v, altOf(4, d), az))
                        ctx.fillStyle = rgb(mix(mix([30, 56, 34], [0, 0, 0], 0.82 * (1 - day)), haze, Math.min(0.85, 1 - Math.exp(-d / 1100))))
                        ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, 2 * Math.PI); ctx.fill()
                    }
                    continue
                }
                if (!visible((b.az1 + b.az2) / 2)) continue
                const far = 1 - Math.exp(-b.D / 1100)                    // how much haze is in front of it
                const base = altOf(0, b.D), top = altOf(b.H, b.D)
                const pa = P(top, b.az1), pb = P(top, b.az2)
                if (!pa.ok && !pb.ok) continue
                if (Math.min(pa.y, pb.y) > v.h + 50) continue
                // facade colour: day colour, dimmed at night, then hazed by distance
                let c = city.colours[b.color]
                // light on this facade: daylight, plus moonlight (cool) and a low Sun (warm),
                // stronger on faces turned towards them. A facade faces you: its normal points
                // from the building back towards you, at bearing + 180.
                const normal = (b.az1 + b.az2) / 2 + 180
                const toward = az => Math.max(0, Math.cos((normal - az) * R))
                const dirM = toward(city.moonAz), dirS = toward(city.sunAz)
                const L = Math.min(1, day + city.moonK * (0.22 + 0.34 * dirM))
                c = mix(c, [0, 0, 0], 0.86 * (1 - L))
                c = mix(c, [150, 172, 220], 0.22 * city.moonK * (0.4 + 0.6 * dirM) * (1 - day))   // silvered by the Moon
                c = mix(c, [255, 160, 96], 0.42 * dirS * city.golden)                    // golden hour
                c = mix(c, [20, 21, 23], 0.15 * (1 - L))
                c = mix(c, haze, Math.min(0.92, far * (day > 0.5 ? 0.9 : 1)))
                // facade
                if (!quad(b.az1, b.az2, base, top)) continue
                if (b.D < 120) {                                         // close: shade the facade downwards
                    const g = ctx.createLinearGradient(0, Math.min(pa.y, pb.y), 0, P(base, b.az1).y)
                    g.addColorStop(0, rgb(c)); g.addColorStop(1, rgb(mix(c, [0, 0, 0], 0.55)))
                    ctx.fillStyle = g
                } else ctx.fillStyle = rgb(c)
                ctx.fill()
                const px = Math.abs(pb.x - pa.x)                         // how wide it is on screen
                const night = day < 0.4
                if (b.kind === "dome") {                                  // a lit glass dome on its base
                    const mid = (b.az1 + b.az2) / 2, hw = (b.az2 - b.az1) / 2
                    // a glass sphere rising out of its base: centre a little above the roof line,
                    // clipped at the roof so it sits in the building instead of floating
                    const pc = P(top, mid), rx = Math.abs(pb.x - pa.x) / 2, cyS = pc.y - rx * 0.45
                    ctx.save()
                    ctx.beginPath(); ctx.rect(pc.x - rx * 1.2, cyS - rx * 1.3, rx * 2.4, (pc.y - (cyS - rx * 1.3))); ctx.clip()
                    const g = ctx.createRadialGradient(pc.x - rx * 0.3, cyS - rx * 0.45, rx * 0.08, pc.x, cyS, rx)
                    g.addColorStop(0, night ? "rgba(246,250,255,1)" : "rgba(220,226,232,1)")
                    g.addColorStop(0.7, night ? "rgba(196,210,224,1)" : "rgba(170,180,190,1)")
                    g.addColorStop(1, night ? "rgba(120,136,152,1)" : "rgba(120,130,140,1)")
                    ctx.fillStyle = g
                    ctx.beginPath(); ctx.arc(pc.x, cyS, rx, 0, 2 * Math.PI); ctx.fill()
                    ctx.strokeStyle = "rgba(60,72,86,0.5)"; ctx.lineWidth = Math.max(1, rx * 0.025)
                    for (let f = -0.75; f <= 0.8; f += 0.25) {                 // the floors showing through the glass
                        const yy = cyS + f * rx, ww = rx * Math.sqrt(Math.max(0, 1 - f * f))
                        ctx.beginPath(); ctx.moveTo(pc.x - ww, yy); ctx.lineTo(pc.x + ww, yy); ctx.stroke()
                    }
                    ctx.restore()
                    const ry = rx
                    if (night) {
                        const gl = ctx.createRadialGradient(pc.x, pc.y - ry * 0.7, 0, pc.x, pc.y - ry * 0.7, rx * 3)
                        gl.addColorStop(0, "rgba(220,235,255,0.22)"); gl.addColorStop(1, "rgba(220,235,255,0)")
                        ctx.fillStyle = gl; ctx.fillRect(pc.x - rx * 3, pc.y - ry * 0.7 - rx * 3, rx * 6, rx * 6)
                    }
                    continue
                }
                if (b.kind === "office" && night) {                       // white block, every floor lit
                    ctx.strokeStyle = "rgba(232,242,255,0.95)"; ctx.lineWidth = Math.max(1.5, 1.8 * s)
                    for (let f = 1; f < b.floors; f++) {
                        const al = altOf(f * 3.4, b.D), q1 = P(al, b.az1 + (b.az2 - b.az1) * 0.04), q2 = P(al, b.az2 - (b.az2 - b.az1) * 0.04)
                        ctx.beginPath(); ctx.moveTo(q1.x, q1.y); ctx.lineTo(q2.x, q2.y); ctx.stroke()
                    }
                    continue
                }
                if (b.kind === "led" && night) {                          // outlined in warm LED strips, its name on top
                    const glowLine = (pts, w) => {
                        for (const [lw, a] of [[w * 5, 0.10], [w * 2.4, 0.24], [w, 0.95]]) {
                            ctx.strokeStyle = "rgba(255,214,150," + a + ")"; ctx.lineWidth = lw
                            ctx.beginPath(); pts.forEach((q, i) => { if (i) ctx.lineTo(q.x, q.y); else ctx.moveTo(q.x, q.y) }); ctx.stroke()
                        }
                    }
                    const w = Math.max(1, 1.4 * s)
                    glowLine([P(base, b.az1), pa, pb, P(base, b.az2)], w)
                    for (const f of [0.25, 0.5, 0.75]) glowLine([P(base + (top - base) * 0.2, b.az1 + (b.az2 - b.az1) * f), P(top, b.az1 + (b.az2 - b.az1) * f)], w)
                    for (const f of [0.45, 0.75]) glowLine([P(base + (top - base) * f, b.az1), P(base + (top - base) * f, b.az2)], w * 0.8)
                    if (b.label) {
                        const pt = P(top, (b.az1 + b.az2) / 2)
                        ctx.font = "bold " + Math.max(9, Math.round(px * 0.17)) + "px sans-serif"
                        ctx.textAlign = "center"; ctx.textBaseline = "bottom"
                        ctx.fillStyle = "rgba(150,140,255,0.35)"
                        for (const dx of [-1.5, 1.5]) ctx.fillText(b.label, pt.x + dx, pt.y - 2 * s)
                        ctx.fillStyle = "rgba(205,200,255,0.95)"
                        ctx.fillText(b.label, pt.x, pt.y - 2 * s)
                    }
                    continue
                }
                // roof: seen from above when it's below your eye
                if (b.H < eye) {
                    const back = altOf(b.H, b.D + b.depth)
                    // flat concrete roof
                    // roofs face the sky: lit by how high the Moon (or Sun) stands
                    const up = Math.min(1, day + city.moonK * 0.4 * Math.max(0.3, Math.sin(Math.max(0, city.moonAlt) * R)))
                    let roofC = mix([112, 110, 104], [0, 0, 0], 0.88 * (1 - up))
                    roofC = mix(roofC, [150, 172, 220], 0.14 * city.moonK * (1 - day))
                    roofC = mix(roofC, [255, 170, 110], 0.25 * city.golden)
                    roofC = mix(roofC, haze, Math.min(0.9, far))
                    if (quad(b.az1, b.az2, top, back)) { ctx.fillStyle = rgb(roofC); ctx.fill() }
                    // a parapet lip along the roof's front edge
                    if (px > 30) { const lip = altOf(b.H + 0.9, b.D); if (quad(b.az1, b.az2, top, lip)) { ctx.fillStyle = rgb(mix(c, [255, 255, 255], 0.08)); ctx.fill() } }
                    // rooftop furniture, only where it's big enough to see
                    if (px > 14) {
                        ctx.fillStyle = rgb(mix(c, [0, 0, 0], 0.5))
                        const mid = (b.az1 + b.az2) / 2, w = b.az2 - b.az1
                        if (b.roof < 0.4) {                               // water tank
                            const ta = b.az1 + w * 0.2, t0 = altOf(b.H, b.D + b.depth * 0.5), t1 = altOf(b.H + 2.2, b.D + b.depth * 0.5)
                            if (quad(ta, ta + w * 0.22, t0, t1)) ctx.fill()
                        } else if (b.roof < 0.65) {                       // stair hut
                            const t0 = altOf(b.H, b.D + 3), t1 = altOf(b.H + 2.6, b.D + 3)
                            if (quad(mid + w * 0.1, mid + w * 0.35, t0, t1)) ctx.fill()
                        } else if (b.roof < 0.72) {                       // rebar sticking up: still building
                            ctx.strokeStyle = rgb(mix(c, [0, 0, 0], 0.6)); ctx.lineWidth = 1
                            for (let k = 0; k < 5; k++) {
                                const az = b.az1 + w * (0.1 + 0.2 * k), q0 = P(top, az), q1 = P(altOf(b.H + 1.6, b.D), az)
                                ctx.beginPath(); ctx.moveTo(q0.x, q0.y); ctx.lineTo(q1.x, q1.y); ctx.stroke()
                            }
                        }
                    }
                }
                if (b.roof > 0.99) {                                     // a rooftop telecom array
                    ctx.strokeStyle = rgb(mix(c, [0, 0, 0], 0.4)); ctx.lineWidth = 1.4 * s
                    const mid = (b.az1 + b.az2) / 2
                    for (let k = -2; k <= 2; k++) {
                        const az = mid + k * (b.az2 - b.az1) * 0.07
                        const q0 = P(top, az), q1 = P(altOf(b.H + 6 + (k % 2) * 2, b.D), az)
                        ctx.beginPath(); ctx.moveTo(q0.x, q0.y); ctx.lineTo(q1.x, q1.y); ctx.stroke()
                    }
                }
                // detail on the nearer ones: balcony bands, brick in a concrete frame
                if (px > 22) {
                    const fl = b.floors
                    if (b.color === 4 && b.brickFrame) {
                        ctx.fillStyle = rgb(mix(c, [210, 208, 200], 0.35))
                        for (let f = 1; f <= fl; f++) { const al = altOf(f * 3.1, b.D); if (quad(b.az1, b.az2, al - 0.12 * 3.1 / b.D / R, al)) ctx.fill() }
                        for (const fx of [0, 0.5, 1]) {
                            const az = b.az1 + (b.az2 - b.az1) * fx, hw = 0.35 / b.D / R
                            if (quad(az - hw, az + hw, base, top)) ctx.fill()
                        }
                    } else if (b.striped) {
                        ctx.fillStyle = rgb(mix(c, [0, 0, 0], 0.55))
                        for (let f = 1; f <= fl; f++) { const al = altOf(f * 3.1 - 1, b.D), a2 = altOf(f * 3.1 - 0.1, b.D); if (quad(b.az1 + (b.az2 - b.az1) * 0.35, b.az2, al, a2)) ctx.fill() }
                    }
                }
                // windows
                const fl = b.floors
                const cols = Math.max(1, Math.round((b.az2 - b.az1) * R * b.D / 3.2))
                const tiny = px < 10
                for (let f = 0; f < fl; f++) {
                    for (let i = 0; i < cols; i++) {
                        const id = b.seed + f * 131 + i * 17
                        const q = ((id * 9301 + 49297) % 233280) / 233280
                        if (q > lit) continue
                        const az = b.az1 + (b.az2 - b.az1) * (i + 0.5) / cols
                        const al = altOf(f * 3.1 + 1.4, b.D)
                        const p = P(al, az)
                        if (!p.ok) continue
                        const t = (id * 7919) % 100
                        const a = (0.45 + 0.45 * ((id * 37) % 97) / 97) * (1 - far * 0.65) * (b.D < 60 ? 0.6 : 0.8)
                        const col = t < 22 ? [255, 192, 112] : t < 92 ? [222, 238, 255] : [150, 205, 255]
                        ctx.fillStyle = rgb(col, a.toFixed(2))
                        if (tiny) {
                            // far away, a lit window is a point of light softened by the haze
                            if (a > 0.3 && t < 40) {
                                const gl = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, 4 * s)
                                gl.addColorStop(0, rgb(col, (a * 0.35).toFixed(2))); gl.addColorStop(1, rgb(col, 0))
                                ctx.fillStyle = gl; ctx.fillRect(p.x - 4 * s, p.y - 4 * s, 8 * s, 8 * s)
                                ctx.fillStyle = rgb(col, a.toFixed(2))
                            }
                            ctx.fillRect(p.x, p.y, 1.2, 1.2)
                        }
                        else {
                            const ww = Math.max(1.4, 1.3 / b.D / R * View.scaleAt(v, al, az)), hh = Math.max(1.4, 1.4 / b.D / R * View.scaleAt(v, al, az))
                            ctx.fillRect(p.x - ww / 2, p.y - hh / 2, ww, hh)
                            if (ww > 9) {                                  // frame and the grille every Dhaka window has
                                ctx.strokeStyle = "rgba(20,20,22,0.75)"; ctx.lineWidth = Math.max(1, ww * 0.07)
                                ctx.strokeRect(p.x - ww / 2, p.y - hh / 2, ww, hh)
                                ctx.lineWidth = Math.max(0.8, ww * 0.035)
                                ctx.beginPath()
                                for (let g = 1; g < 4; g++) { ctx.moveTo(p.x - ww / 2 + ww * g / 4, p.y - hh / 2); ctx.lineTo(p.x - ww / 2 + ww * g / 4, p.y + hh / 2) }
                                ctx.moveTo(p.x - ww / 2, p.y); ctx.lineTo(p.x + ww / 2, p.y)
                                ctx.stroke()
                            }
                        }
                    }
                }
            }

            // your own roof: rebar and bamboo poles rising out of the corners
            ctx.strokeStyle = "rgba(10,10,12,0.95)"
            const poles = [[0.015, 0.55, 0.02], [0.03, 0.62, -0.01], [0.045, 0.7, 0.015], [0.955, 0.6, -0.02], [0.97, 0.52, 0.01], [0.985, 0.66, -0.015]]
            for (const p of poles) {
                ctx.lineWidth = 3 * s
                ctx.beginPath(); ctx.moveTo(v.w * p[0], v.h + 10); ctx.lineTo(v.w * (p[0] + p[2]), v.h * p[1]); ctx.stroke()
            }
        }
    }
}
