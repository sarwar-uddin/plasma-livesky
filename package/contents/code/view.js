.pragma library

// The camera: a stereographic projection centred on (az0, alt0), the way a very wide
// lens (or Stellarium) sees the sky. Conformal, so constellations keep their shapes;
// the horizon becomes a big circle, sky inside, ground outside.
// Horizontal vectors are (east, north, up).

var RAD = Math.PI / 180

function dir(alt, az) {
    const ca = Math.cos(alt * RAD)
    return [ca * Math.sin(az * RAD), ca * Math.cos(az * RAD), Math.sin(alt * RAD)]
}

// w, h: screen size; az0: the direction you face; alt0: how far up the centre looks.
function make(w, h, az0, alt0) {
    const k = w * 0.97 / 4                 // east and west horizon land near the screen edges
    const cx = w / 2, cy = h * 0.62      // centre low on the screen: lots of sky, the city along the bottom
    const f = dir(alt0, az0), r = dir(0, az0 + 90), u = dir(alt0 + 90, az0)
    const v = {
        w: w, h: h, k: k, cx: cx, cy: cy, az0: az0, alt0: alt0, f: f, r: r, u: u,
        // the horizon circle: through the points below (S) and behind (N) the centre
        dS: 2 * k * Math.tan(alt0 / 2 * RAD), dN: 2 * k * Math.tan((180 - alt0) / 2 * RAD)
    }
    v.hx = cx
    v.hy = cy + (v.dS - v.dN) / 2
    v.hr = (v.dS + v.dN) / 2
    return v
}

// (east, north, up) -> { x, y, ok } ; ok is false for points too far behind the camera
function project(v, e, n, z) {
    const X = e * v.r[0] + n * v.r[1] + z * v.r[2]
    const Y = e * v.u[0] + n * v.u[1] + z * v.u[2]
    const Z = e * v.f[0] + n * v.f[1] + z * v.f[2]
    const d = 1 + Z
    if (d < 0.08) return { x: 0, y: 0, ok: false }
    return { x: v.cx + 2 * v.k * X / d, y: v.cy - 2 * v.k * Y / d, ok: true }
}

// Like project(), but points behind the camera are pushed far off-screen in their own
// direction instead of being dropped, so big filled shapes keep their outline.
function projectClamped(v, e, n, z) {
    const X = e * v.r[0] + n * v.r[1] + z * v.r[2]
    const Y = e * v.u[0] + n * v.u[1] + z * v.u[2]
    const Z = e * v.f[0] + n * v.f[1] + z * v.f[2]
    const d = Math.max(0.08, 1 + Z)
    return { x: v.cx + 2 * v.k * X / d, y: v.cy - 2 * v.k * Y / d, ok: true }
}

function projectAltAz(v, alt, az) { const d = dir(alt, az); return project(v, d[0], d[1], d[2]) }

function onScreen(v, p, margin) {
    const m = margin || 0
    return p.ok && p.x > -m && p.x < v.w + m && p.y > -m && p.y < v.h + m
}

// Pixels per degree near a point (for sizing the Moon etc.).
function scaleAt(v, alt, az) {
    const a = projectAltAz(v, alt, az), b = projectAltAz(v, alt + 0.5, az)
    return Math.hypot(a.x - b.x, a.y - b.y) * 2
}
