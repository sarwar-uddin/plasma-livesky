.pragma library

// Sun and Moon positions and Islamic prayer times.
// Algorithm after praytimes.org (Hamid Zarrabi-Zadeh, LGPL) and the US Naval
// Observatory's approximate solar coordinates. Accurate to about a minute
// at low and mid latitudes, which is the precision prayer timetables use.

const RAD = Math.PI / 180

function dsin(d) { return Math.sin(d * RAD) }
function dcos(d) { return Math.cos(d * RAD) }
function dtan(d) { return Math.tan(d * RAD) }
function darcsin(x) { return Math.asin(x) / RAD }
function darccos(x) { return Math.acos(x) / RAD }
function darctan2(y, x) { return Math.atan2(y, x) / RAD }
function darccot(x) { return Math.atan(1 / x) / RAD }
function fix(a, b) { a = a - b * Math.floor(a / b); return a < 0 ? a + b : a }

// Twilight angles (degrees below the horizon). ishaMinutes = fixed delay after Maghrib.
var METHODS = {
    karachi: { name: "University of Islamic Sciences, Karachi", fajr: 18, isha: 18 },
    mwl:     { name: "Muslim World League", fajr: 18, isha: 17 },
    isna:    { name: "Islamic Society of North America", fajr: 15, isha: 15 },
    egypt:   { name: "Egyptian General Authority of Survey", fajr: 19.5, isha: 17.5 },
    makkah:  { name: "Umm al-Qura, Makkah", fajr: 18.5, ishaMinutes: 90 }
}

var NAMES = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

function julian(date) { return date.getTime() / 86400000 + 2440587.5 }

// Declination (degrees) and equation of time (hours) at a Julian day.
function sunPosition(jd) {
    const D = jd - 2451545.0
    const g = fix(357.529 + 0.98560028 * D, 360)
    const q = fix(280.459 + 0.98564736 * D, 360)
    const L = fix(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g), 360)
    const e = 23.439 - 0.00000036 * D
    const ra = fix(darctan2(dcos(e) * dsin(L), dcos(L)) / 15, 24)
    let eqt = q / 15 - ra
    if (eqt > 12) eqt -= 24
    if (eqt < -12) eqt += 24
    return { decl: darcsin(dsin(e) * dsin(L)), eqt: eqt, lon: L, ra: ra * 15 }
}

// Solar altitude in degrees at an instant.
function altitude(date, lat, lng) {
    const p = sunPosition(julian(date))
    const utcHours = (date.getTime() / 3600000) % 24
    const H = 15 * (utcHours + lng / 15 + p.eqt - 12)
    return darcsin(dsin(lat) * dsin(p.decl) + dcos(lat) * dcos(p.decl) * dcos(H))
}

function localMidnight(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

// All times below are hours after local midnight (jd0) in a zone tz hours from UTC.
function midDay(ctx, t) {
    const eqt = sunPosition(ctx.jd0 + t / 24).eqt
    return 12 + ctx.tz - ctx.lng / 15 - eqt
}

// Time the sun is `angle` degrees below the horizon; before noon if ccw.
function sunAngleTime(ctx, angle, t, ccw) {
    const decl = sunPosition(ctx.jd0 + t / 24).decl
    const noon = midDay(ctx, t)
    const c = (-dsin(angle) - dsin(decl) * dsin(ctx.lat)) / (dcos(decl) * dcos(ctx.lat))
    if (c < -1 || c > 1) return NaN          // sun never reaches that angle (high latitudes)
    const T = darccos(c) / 15
    return noon + (ccw ? -T : T)
}

// Asr: shadow length = factor * object height + noon shadow (1 Shafi'i, 2 Hanafi).
function asrTime(ctx, factor, t) {
    const decl = sunPosition(ctx.jd0 + t / 24).decl
    const angle = -darccot(factor + dtan(Math.abs(ctx.lat - decl)))
    return sunAngleTime(ctx, angle, t, false)
}

// Prayer times for the local calendar day containing `date`.
// Returns { events: [{ name, time: Date|null }], sunrise, sunset, noon (Dates) }.
// `offsets` is an optional array of six minute adjustments.
function compute(date, lat, lng, methodKey, asrFactor, offsets) {
    const m = METHODS[methodKey] || METHODS.karachi
    const base = localMidnight(date)
    const ctx = {
        jd0: julian(base),
        tz: -base.getTimezoneOffset() / 60,
        lat: lat, lng: lng
    }
    // two refinement passes, each using the previous estimate as the sun-position instant
    let t = { fajr: 5, sunrise: 6, dhuhr: 12, asr: 15, sunset: 18, isha: 19 }
    for (let i = 0; i < 2; i++) {
        t = {
            fajr: sunAngleTime(ctx, m.fajr, t.fajr, true),
            sunrise: sunAngleTime(ctx, 0.833, t.sunrise, true),
            dhuhr: midDay(ctx, t.dhuhr),
            asr: asrTime(ctx, asrFactor, t.asr),
            sunset: sunAngleTime(ctx, 0.833, t.sunset, false),
            isha: m.ishaMinutes ? NaN : sunAngleTime(ctx, m.isha, t.isha, false)
        }
        if (isNaN(t.fajr)) t.fajr = 5
        if (isNaN(t.isha)) t.isha = 19
    }
    let isha = m.ishaMinutes ? t.sunset + m.ishaMinutes / 60 : sunAngleTime(ctx, m.isha, t.isha, false)
    const hours = [sunAngleTime(ctx, m.fajr, t.fajr, true), t.sunrise, t.dhuhr, t.asr, t.sunset, isha]
    const toDate = (h, i) => {
        if (isNaN(h)) return null
        const off = offsets && offsets[i] ? offsets[i] : 0
        // round to the nearest minute, as published timetables do
        const ms = Math.round((h * 60 + off)) * 60000
        return new Date(base.getTime() + ms)
    }
    const events = hours.map((h, i) => ({ name: NAMES[i], time: toDate(h, i) }))
    return {
        events: events,
        sunrise: toDate(t.sunrise, -1),
        sunset: toDate(t.sunset, -1),
        noon: toDate(t.dhuhr, -1)
    }
}

// Altitude samples across the local day of `date`: [{ h: hours, alt: degrees }].
function dayCurve(date, lat, lng, stepMinutes) {
    const base = localMidnight(date).getTime()
    const out = []
    for (let m = 0; m <= 24 * 60; m += stepMinutes)
        out.push({ h: m / 60, alt: altitude(new Date(base + m * 60000), lat, lng) })
    return out
}

function parseOffsets(s) {
    const parts = String(s || "").split(/[,\s]+/).filter(x => x.length)
    const out = [0, 0, 0, 0, 0, 0]
    for (let i = 0; i < 6 && i < parts.length; i++) {
        const v = parseInt(parts[i], 10)
        out[i] = isNaN(v) ? 0 : v
    }
    return out
}

// ---------------------------------------------------------------- moon
// Meeus, Astronomical Algorithms ch. 47 (the larger terms of tables 47.A/B),
// the same series the Orrery app uses. Good to a few arcminutes, i.e. rise and
// set times to a minute or two.

// [D, M, M', F, longitude 1e-6 deg, distance 1e-3 km]
var MOON_LR = [
    [0, 0, 1, 0, 6288774, -20905355], [2, 0, -1, 0, 1274027, -3699111],
    [2, 0, 0, 0, 658314, -2955968], [0, 0, 2, 0, 213618, -569925],
    [0, 1, 0, 0, -185116, 48888], [0, 0, 0, 2, -114332, -3149],
    [2, 0, -2, 0, 58793, 246158], [2, -1, -1, 0, 57066, -152138],
    [2, 0, 1, 0, 53322, -170733], [2, -1, 0, 0, 45758, -204586],
    [0, 1, -1, 0, -40923, -129620], [1, 0, 0, 0, -34720, 108743],
    [0, 1, 1, 0, -30383, 104755], [2, 0, 0, -2, 15327, 10321],
    [0, 0, 1, 2, -12528, 0], [0, 0, 1, -2, 10980, 79661],
    [4, 0, -1, 0, 10675, -34782], [0, 0, 3, 0, 10034, -23210],
    [4, 0, -2, 0, 8548, -21636], [2, 1, -1, 0, -7888, 24208],
    [2, 1, 0, 0, -6766, 30824], [1, 0, -1, 0, -5163, -8379],
    [1, 1, 0, 0, 4987, -16675], [2, -1, 1, 0, 4036, -12831],
    [2, 0, 2, 0, 3994, -10445], [4, 0, 0, 0, 3861, -11650],
    [2, 0, -3, 0, 3665, 14403], [0, 1, -2, 0, -2689, -7003],
    [2, 0, -1, 2, -2602, 0], [2, -1, -2, 0, 2390, 10056],
    [1, 0, 1, 0, -2348, 6322], [2, -2, 0, 0, 2236, -9884]
]
// [D, M, M', F, latitude 1e-6 deg]
var MOON_B = [
    [0, 0, 0, 1, 5128122], [0, 0, 1, 1, 280602], [0, 0, 1, -1, 277693],
    [2, 0, 0, -1, 173237], [2, 0, -1, 1, 55413], [2, 0, -1, -1, 46271],
    [2, 0, 0, 1, 32573], [0, 0, 2, 1, 17198], [2, 0, 1, -1, 9266],
    [0, 0, 2, -1, 8822], [2, -1, 0, -1, 8216], [2, 0, -2, -1, 4324],
    [2, 0, 1, 1, 4200], [2, 1, 0, -1, -3359], [2, -1, -1, 1, 2463],
    [2, -1, 0, 1, 2211], [2, -1, -1, -1, 2065], [0, 1, -1, -1, -1870],
    [4, 0, -1, -1, 1828], [0, 1, 0, 1, -1794]
]

// Geocentric ecliptic lon/lat (deg), distance (km), RA/Dec (deg) at a Julian day.
function moonPosition(jd) {
    const t = (jd - 2451545.0) / 36525
    const lp = fix(218.3164477 + 481267.88123421 * t - 0.0015786 * t * t, 360)
    const d = fix(297.8501921 + 445267.1114034 * t - 0.0018819 * t * t, 360)
    const m = fix(357.5291092 + 35999.0502909 * t - 0.0001536 * t * t, 360)
    const mp = fix(134.9633964 + 477198.8675055 * t + 0.0087414 * t * t, 360)
    const f = fix(93.2720950 + 483202.0175233 * t - 0.0036539 * t * t, 360)
    const a1 = fix(119.75 + 131.849 * t, 360)
    const a2 = fix(53.09 + 479264.290 * t, 360)
    const a3 = fix(313.45 + 481266.484 * t, 360)
    const ecc = 1 - 0.002516 * t - 0.0000074 * t * t
    let sl = 0, sr = 0, sb = 0
    for (const r of MOON_LR) {
        const arg = r[0] * d + r[1] * m + r[2] * mp + r[3] * f
        const k = Math.pow(ecc, Math.abs(r[1]))
        sl += r[4] * k * dsin(arg)
        sr += r[5] * k * dcos(arg)
    }
    for (const r of MOON_B)
        sb += r[4] * Math.pow(ecc, Math.abs(r[1])) * dsin(r[0] * d + r[1] * m + r[2] * mp + r[3] * f)
    sl += 3958 * dsin(a1) + 1962 * dsin(lp - f) + 318 * dsin(a2)
    sb += -2235 * dsin(lp) + 382 * dsin(a3) + 175 * dsin(a1 - f) + 175 * dsin(a1 + f)
          + 127 * dsin(lp - mp) - 115 * dsin(lp + mp)
    const lon = fix(lp + sl / 1e6, 360), lat = sb / 1e6
    const eps = 23.439291 - 0.0130042 * t
    const ra = fix(darctan2(dsin(lon) * dcos(eps) - dtan(lat) * dsin(eps), dcos(lon)), 360)
    const dec = darcsin(dsin(lat) * dcos(eps) + dcos(lat) * dsin(eps) * dsin(lon))
    return { lon: lon, lat: lat, dist: 385000.56 + sr / 1000, ra: ra, dec: dec }
}

// Topocentric altitude of the Moon's centre in degrees (parallax is ~1°).
function moonAltitude(date, lat, lng) {
    const jd = julian(date)
    const p = moonPosition(jd)
    const gmst = fix(280.46061837 + 360.98564736629 * (jd - 2451545.0), 360)
    const H = gmst + lng - p.ra
    const alt = darcsin(dsin(lat) * dsin(p.dec) + dcos(lat) * dcos(p.dec) * dcos(H))
    return alt - darcsin(6378.14 / p.dist) * dcos(alt)
}

var PHASE_NAMES = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                   "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]

// { illum 0..1, waxing, elong (deg, 0 new .. 180 full), age (days), name }
function moonPhase(date) {
    const jd = julian(date)
    const mo = moonPosition(jd)
    const sunLon = sunPosition(jd).lon
    const elong = fix(mo.lon - sunLon, 360)
    const psi = Math.acos(dcos(mo.lat) * dcos(mo.lon - sunLon))
    const sunKm = 149597870.7
    const i = Math.atan2(sunKm * Math.sin(psi), mo.dist - sunKm * Math.cos(psi))
    let name = PHASE_NAMES[Math.floor(elong / 90) * 2 + 1]
    for (let q = 0; q < 4; q++) {
        let dd = Math.abs(elong - q * 90); if (dd > 180) dd = 360 - dd
        if (dd < 7) name = PHASE_NAMES[q * 2]
    }
    return { illum: (1 + Math.cos(i)) / 2, waxing: elong < 180, elong: elong,
             age: elong / 360 * 29.530589, name: name }
}

var MOON_H0 = -0.583     // topocentric centre at rise/set: refraction + semidiameter

// Moonrise/moonset events between two Dates: [{ type: "rise"|"set", time: Date }].
function moonCrossings(from, to, lat, lng) {
    const step = 10 * 60000
    const out = []
    let t0 = from.getTime()
    let f0 = moonAltitude(new Date(t0), lat, lng) - MOON_H0
    while (t0 < to.getTime()) {
        const t1 = Math.min(t0 + step, to.getTime())
        const f1 = moonAltitude(new Date(t1), lat, lng) - MOON_H0
        if ((f0 < 0) !== (f1 < 0)) {
            let lo = t0, hi = t1, flo = f0
            for (let k = 0; k < 14; k++) {
                const mid = (lo + hi) / 2
                const fm = moonAltitude(new Date(mid), lat, lng) - MOON_H0
                if ((fm < 0) === (flo < 0)) { lo = mid; flo = fm } else hi = mid
            }
            out.push({ type: f0 < 0 ? "rise" : "set", time: new Date(Math.round((lo + hi) / 2 / 60000) * 60000) })
        }
        t0 = t1; f0 = f1
    }
    return out
}

// The Moon right now: whether it is up, the crossing before and after `now`
// (so the panel can place it along its own arc), today's rise/set and the phase.
function moonState(now, lat, lng) {
    const span = 40 * 3600000
    const ev = moonCrossings(new Date(now.getTime() - span), new Date(now.getTime() + span), lat, lng)
    const alt = moonAltitude(now, lat, lng)
    let prev = null, next = null
    for (const e of ev) {
        if (e.time <= now) prev = e
        else if (!next) next = e
    }
    const base = localMidnight(now).getTime()
    let rise = null, set = null
    for (const e of ev) {
        const t = e.time.getTime()
        if (t < base || t >= base + 86400000) continue
        if (e.type === "rise" && !rise) rise = e.time
        if (e.type === "set" && !set) set = e.time
    }
    let nextRise = null, nextSet = null
    for (const e of ev) {
        if (e.time <= now) continue
        if (e.type === "rise" && !nextRise) nextRise = e.time
        if (e.type === "set" && !nextSet) nextSet = e.time
    }
    return {
        up: alt > MOON_H0, alt: alt,
        from: prev ? prev.time : null, to: next ? next.time : null,
        rise: rise, set: set, nextRise: nextRise, nextSet: nextSet,
        phase: moonPhase(now), view: moonView(now, lat, lng)
    }
}

function moonDayCurve(date, lat, lng, stepMinutes) {
    const base = localMidnight(date).getTime()
    const out = []
    for (let m = 0; m <= 24 * 60; m += stepMinutes)
        out.push({ h: m / 60, alt: moonAltitude(new Date(base + m * 60000), lat, lng) })
    return out
}

// How the Moon looks from (lat, lng) with the zenith straight up: the angle of the
// bright limb (Meeus 48.5) and of celestial north, both in degrees from the zenith,
// counter-clockwise (towards east). Subtracting the parallactic angle is what tips an
// evening crescent over into a "boat" in the tropics.
function moonView(date, lat, lng) {
    const jd = julian(date)
    const mo = moonPosition(jd), su = sunPosition(jd)
    const da = su.ra - mo.ra
    const chi = darctan2(dcos(su.decl) * dsin(da),
                         dsin(su.decl) * dcos(mo.dec) - dcos(su.decl) * dsin(mo.dec) * dcos(da))
    const gmst = fix(280.46061837 + 360.98564736629 * (jd - 2451545.0), 360)
    const H = gmst + lng - mo.ra
    const q = darctan2(dsin(H), dtan(lat) * dcos(mo.dec) - dsin(mo.dec) * dcos(H))
    return { limb: chi - q, north: -q }
}

// Near-side maria and a few bright ray craters: [lat, lon (east +), radius, albedo], degrees.
// The blobs overlap so they merge into the familiar connected seas.
var MARIA = [
    [35, -18, 17, 0.62], [28, -2, 10, 0.66], [27, 17, 10, 0.6], [15, 24, 9, 0.64],
    [8, 31, 11, 0.62], [2, 40, 8, 0.65], [17, 58, 8, 0.6], [-6, 51, 9, 0.66],
    [-15, 35, 6, 0.66], [-20, -15, 10, 0.68], [-12, -25, 8, 0.68], [-24, -39, 7, 0.64],
    [26, -52, 15, 0.64], [10, -55, 16, 0.64], [-5, -45, 13, 0.66], [7, -30, 9, 0.68],
    [12, 4, 5, 0.68], [0, 0, 4, 0.72], [56, -25, 7, 0.72], [56, 0, 7, 0.72], [57, 25, 6, 0.72],
    [13, 86, 6, 0.74], [-2, 86, 6, 0.74]
]
var CRATERS = [[-43, -11, 2.6, 1.3], [10, -20, 2.2, 1.2], [24, -47, 1.4, 1.4], [8, -38, 1.4, 1.15]]

function smooth(e0, e1, x) { const t = Math.max(0, Math.min(1, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t) }

// Cheap value noise for the highlands' mottling.
function hash2(i, j) { const h = Math.sin(i * 127.1 + j * 311.7) * 43758.5453; return h - Math.floor(h) }
function vnoise(x, y) {
    const i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j
    const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
    const a = hash2(i, j), b = hash2(i + 1, j), c = hash2(i, j + 1), d = hash2(i + 1, j + 1)
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
}

// Albedo of the near side, baked once into a texture over the orthographic disc
// (x right, y up, north up as seen from the northern hemisphere). QML's JS engine is
// slow at trig in loops, so the per-pixel work later is just a bilinear lookup.
var ALBEDO_N = 64
var albedoTex = null

function unitVec(la, lo) { return [dcos(la) * dsin(lo), dsin(la), dcos(la) * dcos(lo)] }

function buildAlbedo() {
    const n = ALBEDO_N, tex = new Float32Array(n * n)
    const maria = MARIA.map(m => ({ v: unitVec(m[0], m[1]), r: m[2], k: 1 - m[3], c: dcos(m[2] * 1.2) }))
    const craters = CRATERS.map(c => ({ v: unitVec(c[0], c[1]), r: c[2], k: c[3] - 1, c: dcos(c[2] * 2.2) }))
    for (let j = 0; j < n; j++) {
        const y = 1 - 2 * (j + 0.5) / n
        for (let i = 0; i < n; i++) {
            const x = 2 * (i + 0.5) / n - 1
            const z = Math.sqrt(Math.max(0, 1 - x * x - y * y))
            let a = 1
            for (let q = 0; q < maria.length; q++) {
                const m = maria[q], dot = x * m.v[0] + y * m.v[1] + z * m.v[2]
                if (dot > m.c) a = Math.min(a, 1 - m.k * smooth(m.r * 1.2, m.r * 0.3, Math.acos(Math.min(1, dot)) / RAD))
            }
            const la = Math.asin(Math.max(-1, Math.min(1, y))) / RAD, lo = Math.atan2(x, z) / RAD
            a *= 0.9 + 0.12 * vnoise(la / 9, lo / 9) + 0.06 * vnoise(la / 3.5 + 17, lo / 3.5)
            for (let q = 0; q < craters.length; q++) {
                const c = craters[q], dot = x * c.v[0] + y * c.v[1] + z * c.v[2]
                if (dot > c.c) a *= 1 + c.k * smooth(c.r * 2.2, c.r * 0.4, Math.acos(Math.min(1, dot)) / RAD)
            }
            tex[j * n + i] = a
        }
    }
    return tex
}

function albedoAt(x, y) {
    if (!albedoTex) albedoTex = buildAlbedo()
    const n = ALBEDO_N
    const fx = Math.max(0, Math.min(n - 1.001, (x + 1) / 2 * n - 0.5))
    const fy = Math.max(0, Math.min(n - 1.001, (1 - y) / 2 * n - 0.5))
    const i = Math.floor(fx), j = Math.floor(fy), u = fx - i, v = fy - j
    const t = albedoTex, k = j * n + i
    return (t[k] * (1 - u) + t[k + 1] * u) * (1 - v) + (t[k + n] * (1 - u) + t[k + n + 1] * u) * v
}

// Rendered moon sprites (colour + coverage per pixel), keyed by size, sub-pixel
// offset, phase and tilt, so the once-a-minute repaint only has to blend.
var spriteCache = {}
var spriteKeys = []

function moonSprite(r, ox, oy, n, illum, L, N) {
    const key = [r.toFixed(2), ox.toFixed(2), oy.toFixed(2), illum.toFixed(3), L.toFixed(2), N.toFixed(2)].join()
    if (spriteCache[key]) return spriteCache[key]
    const ci = Math.max(-1, Math.min(1, 2 * illum - 1)), si = Math.sqrt(1 - ci * ci)
    const sx = -Math.sin(L) * si, sy = Math.cos(L) * si, sz = ci      // toward the Sun, y up
    const cN = Math.cos(N), sN = Math.sin(N)
    const earth = 0.15 + 0.85 * Math.pow(1 - illum, 3)               // earthshine, strongest near new
    const SS = r < 8 ? 4 : 2
    const out = new Float32Array(n * n * 4)
    for (let j = 0; j < n; j++) {
        for (let i = 0; i < n; i++) {
            let cr = 0, cg = 0, cb = 0, cov = 0
            for (let b = 0; b < SS; b++) {
                for (let a = 0; a < SS; a++) {
                    const u = (i + (a + 0.5) / SS - ox) / r
                    const v = -(j + (b + 0.5) / SS - oy) / r
                    const rr = u * u + v * v
                    if (rr > 1) continue
                    const nz = Math.sqrt(1 - rr)
                    const A = albedoAt(u * cN + v * sN, -u * sN + v * cN)   // into moon-fixed axes
                    const mu0 = u * sx + v * sy + nz * sz
                    let lit = 0
                    if (mu0 > 0) lit = 2 * mu0 / (mu0 + nz + 1e-6) * smooth(-0.02, 0.10, mu0)
                    const dark = earth * (1 - smooth(-0.1, 0.05, mu0))
                    cr += A * (lit * 236 + 16 + dark * 26)
                    cg += A * (lit * 232 + 17 + dark * 31)
                    cb += A * (lit * 222 + 22 + dark * 42)
                    cov++
                }
            }
            const k = (j * n + i) * 4
            if (cov) { out[k] = cr / cov; out[k + 1] = cg / cov; out[k + 2] = cb / cov; out[k + 3] = cov / (SS * SS) }
        }
    }
    spriteCache[key] = out
    spriteKeys.push(key)
    if (spriteKeys.length > 12) delete spriteCache[spriteKeys.shift()]
    return out
}

// Draw the Moon at (x, y), radius r, shaded per pixel as a sphere: Lommel-Seeliger
// light (why the full Moon looks flat, not ball-like), maria, a soft terminator and
// earthshine on the dark side.
//   phase: Solar.moonPhase(); view: Solar.moonView() or null (then waxing = lit on
//   the right, mirrored if flip); alpha: overall opacity.
function drawMoon(ctx, x, y, r, phase, view, flip, alpha) {
    if (alpha === undefined) alpha = 1
    const L = (view ? view.limb : ((phase.waxing !== !!flip) ? -90 : 90)) * RAD
    const N = (view ? view.north : 0) * RAD
    const x0 = Math.floor(x - r - 1), y0 = Math.floor(y - r - 1)
    const n = Math.ceil(2 * r + 3)
    const sp = moonSprite(r, x - x0, y - y0, n, phase.illum, L, N)
    // one 1px rect per pixel rather than putImageData: Qt's get/putImageData disagree
    // about premultiplied alpha, and this way the normal compositing does the blend
    ctx.save()
    ctx.globalAlpha = alpha
    for (let j = 0; j < n; j++) {
        for (let i = 0; i < n; i++) {
            const k = (j * n + i) * 4
            if (sp[k + 3] <= 0) continue
            ctx.fillStyle = "rgba(" + Math.round(Math.min(255, sp[k])) + "," + Math.round(Math.min(255, sp[k + 1])) + ","
                            + Math.round(Math.min(255, sp[k + 2])) + "," + sp[k + 3].toFixed(3) + ")"
            ctx.fillRect(x0 + i, y0 + j, 1, 1)
        }
    }
    ctx.restore()
}

// Draw the Sun at (x, y), radius r: a limb-darkened disc in a warm corona that
// reddens as it nears the horizon (alt in degrees).
function drawSun(ctx, x, y, r, alt, alpha) {
    if (alpha === undefined) alpha = 1
    const low = 1 - smooth(0, 14, alt)                                 // 1 at the horizon
    const mix = (p, q) => Math.round(p + (q - p) * low)
    const rgb = (a, b, al) => "rgba(" + mix(a[0], b[0]) + "," + mix(a[1], b[1]) + "," + mix(a[2], b[2]) + "," + al + ")"
    ctx.save()
    ctx.globalAlpha = alpha
    const R = r * 2.4
    const halo = ctx.createRadialGradient(x, y, r * 0.6, x, y, R)
    halo.addColorStop(0, rgb([255, 214, 140], [240, 90, 50], 0.55 + 0.15 * low))
    halo.addColorStop(0.35, rgb([255, 170, 80], [224, 32, 63], 0.22 + 0.12 * low))
    halo.addColorStop(1, rgb([224, 32, 63], [180, 20, 40], 0))
    ctx.fillStyle = halo
    ctx.beginPath(); ctx.arc(x, y, R, 0, 2 * Math.PI); ctx.fill()
    const disc = ctx.createRadialGradient(x, y, 0, x, y, r)
    disc.addColorStop(0, rgb([255, 253, 244], [255, 214, 150], 1))
    disc.addColorStop(0.55, rgb([255, 242, 205], [255, 170, 90], 1))
    disc.addColorStop(0.85, rgb([255, 214, 130], [245, 120, 60], 1))
    disc.addColorStop(1, rgb([248, 168, 70], [215, 60, 40], 1))
    ctx.fillStyle = disc
    ctx.beginPath(); ctx.arc(x, y, r, 0, 2 * Math.PI); ctx.fill()
    ctx.restore()
}
