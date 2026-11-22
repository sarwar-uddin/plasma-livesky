.pragma library
.import "solar.js" as Solar
.import "catalog.js" as Cat

// Cosmic Observatory: the local sky. Planets from JPL's approximate Keplerian
// elements (Standish, valid 1800-2050, ported from the Orrery app's astro.py), the
// Sun and Moon from solar.js (Meeus ch. 47), stars from the catalog.

var RAD = Math.PI / 180
function sind(d) { return Math.sin(d * RAD) }
function cosd(d) { return Math.cos(d * RAD) }
function norm360(x) { x = x % 360; return x < 0 ? x + 360 : x }
function wrap180(x) { x = norm360(x); return x > 180 ? x - 360 : x }

var LIGHT_DAYS_PER_AU = 499.004784 / 86400
var AU_KM = 149597870.7

function jdOf(ms) { return ms / 86400000 + 2440587.5 }
function centuries(jd) { return (jd - 2451545.0) / 36525 }
function gmst(jd) {
    const t = centuries(jd)
    return norm360(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - t * t * t / 38710000)
}
function obliquity(jd) { return 23.439291 - 0.0130042 * centuries(jd) }
function precessionLon(jd) { const t = centuries(jd); return 1.396971 * t + 0.0003086 * t * t }

// ---- planets -------------------------------------------------------------------

// a (AU), e, I, L, long. perihelion, long. node, then rates per century
var ELEMENTS = {
    Mercury: [[0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
              [0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081]],
    Venus:   [[0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
              [0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418]],
    Earth:   [[1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
              [0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]],
    Mars:    [[1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
              [0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]],
    Jupiter: [[5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
              [-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]],
    Saturn:  [[9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
              [-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794]],
    Uranus:  [[19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
              [-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589]],
    Neptune: [[30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574],
              [0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]]
}
var PLANETS = ["Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]
var NAKED_EYE = ["Mercury", "Venus", "Mars", "Jupiter", "Saturn"]
var COLORS = { Sun: "#FFD27A", Moon: "#E4E4EA", Mercury: "#BBAE9F", Venus: "#F4EAD0", Mars: "#E8714A",
               Jupiter: "#EAD6B2", Saturn: "#E6CC90", Uranus: "#9FD8E0", Neptune: "#7895EA" }

function heliocentric(name, jd) {
    const el = ELEMENTS[name], t = centuries(jd)
    const a = el[0][0] + el[1][0] * t, e = el[0][1] + el[1][1] * t, i = el[0][2] + el[1][2] * t
    const L = el[0][3] + el[1][3] * t, peri = el[0][4] + el[1][4] * t, node = el[0][5] + el[1][5] * t
    const m = wrap180(L - peri) * RAD
    let E = m + e * Math.sin(m)
    for (let k = 0; k < 12; k++) {
        const d = (E - e * Math.sin(E) - m) / (1 - e * Math.cos(E))
        E -= d
        if (Math.abs(d) < 1e-12) break
    }
    const xp = a * (Math.cos(E) - e), yp = a * Math.sqrt(1 - e * e) * Math.sin(E)
    const w = peri - node
    const co = cosd(w), so = sind(w), cn = cosd(node), sn = sind(node), ci = cosd(i), si = sind(i)
    return [(co * cn - so * sn * ci) * xp + (-so * cn - co * sn * ci) * yp,
            (co * sn + so * cn * ci) * xp + (-so * sn + co * cn * ci) * yp,
            (so * si) * xp + (co * si) * yp]
}

function eclToEq(lon, lat, eps) {
    const ra = Math.atan2(sind(lon) * cosd(eps) - Math.tan(lat * RAD) * sind(eps), cosd(lon)) / RAD
    const dec = Math.asin(sind(lat) * cosd(eps) + cosd(lat) * sind(eps) * sind(lon)) / RAD
    return [norm360(ra), dec]
}

function fromVector(g, jd, r) {
    const dist = Math.hypot(g[0], g[1], g[2])
    const lon0 = norm360(Math.atan2(g[1], g[0]) / RAD)
    const lat = Math.asin(g[2] / dist) / RAD
    const lon = norm360(lon0 + precessionLon(jd))
    const eq = eclToEq(lon, lat, obliquity(jd))
    return { lon: lon, lat: lat, lon2000: lon0, ra: eq[0], dec: eq[1], dist: dist, r: r }
}

function planetApparent(name, jd) {
    const E = heliocentric("Earth", jd)
    let p = heliocentric(name, jd)
    const r = Math.hypot(p[0], p[1], p[2])
    const d = Math.hypot(p[0] - E[0], p[1] - E[1], p[2] - E[2])
    p = heliocentric(name, jd - d * LIGHT_DAYS_PER_AU)
    return fromVector([p[0] - E[0], p[1] - E[1], p[2] - E[2]], jd, r)
}

function sunApparent(jd) {
    const E = heliocentric("Earth", jd)
    const a = fromVector([-E[0], -E[1], -E[2]], jd, 0)
    a.lon = norm360(a.lon - 20.4898 / 3600 / a.dist)
    const eq = eclToEq(a.lon, a.lat, obliquity(jd))
    a.ra = eq[0]; a.dec = eq[1]
    return a
}

function moonApparent(jd) {
    const m = Solar.moonPosition(jd)
    return { lon: m.lon, lat: m.lat, lon2000: norm360(m.lon - precessionLon(jd)), ra: m.ra, dec: m.dec,
             dist: m.dist / AU_KM, r: 1 }
}

// Visual magnitude (Meeus 41; Saturn's rings ignored).
function planetMag(name, a, sunDist) {
    const r = a.r, d = a.dist
    const ci = (r * r + d * d - sunDist * sunDist) / (2 * r * d)
    const i = Math.acos(Math.max(-1, Math.min(1, ci))) / RAD
    const base = 5 * Math.log10(r * d)
    switch (name) {
    case "Mercury": return -0.42 + base + 0.0380 * i - 0.000273 * i * i + 0.000002 * i * i * i
    case "Venus": return -4.40 + base + 0.0009 * i + 0.000239 * i * i - 0.00000065 * i * i * i
    case "Mars": return -1.52 + base + 0.016 * i
    case "Jupiter": return -9.40 + base + 0.005 * i
    case "Saturn": return -8.88 + base + 0.044 * i
    case "Uranus": return -7.19 + base
    }
    return -6.87 + base
}

var ZODIAC = [[28.69, "Pisces"], [53.42, "Aries"], [90.14, "Taurus"], [117.99, "Gemini"],
              [138.01, "Cancer"], [173.86, "Leo"], [217.81, "Virgo"], [241.03, "Libra"],
              [248.04, "Scorpius"], [266.28, "Ophiuchus"], [299.73, "Sagittarius"],
              [327.48, "Capricornus"], [351.57, "Aquarius"], [360.01, "Pisces"]]
function constellationOf(lon2000) {
    const lon = norm360(lon2000)
    for (const z of ZODIAC) if (lon < z[0]) return z[1]
    return "Pisces"
}

// ---- the local sky ----------------------------------------------------------------

// (ra, dec) -> { alt, az } in degrees, azimuth from north through east.
function horizontal(ra, dec, jd, lat, lng) {
    const H = gmst(jd) + lng - ra
    const alt = Math.asin(sind(lat) * sind(dec) + cosd(lat) * cosd(dec) * cosd(H)) / RAD
    const az = Math.atan2(-cosd(dec) * sind(H), sind(dec) * cosd(lat) - cosd(dec) * sind(lat) * cosd(H)) / RAD
    return { alt: alt, az: norm360(az) }
}

// One body's place in the local sky: { name, alt, az, ra, dec, mag, color, dist, constellation }.
function body(name, ms, lat, lng) {
    const jd = jdOf(ms)
    let a, mag = null
    if (name === "Sun") { a = sunApparent(jd); mag = -26.7 }
    else if (name === "Moon") { a = moonApparent(jd); mag = -12 }
    else { a = planetApparent(name, jd); mag = planetMag(name, a, sunApparent(jd).dist) }
    const h = horizontal(a.ra, a.dec, jd, lat, lng)
    if (name === "Moon") h.alt -= Math.asin(6378.14 / (a.dist * AU_KM)) / RAD * cosd(h.alt)
    return { name: name, alt: h.alt, az: h.az, ra: a.ra, dec: a.dec, mag: mag, color: COLORS[name],
             dist: a.dist, constellation: constellationOf(a.lon2000) }
}

function altOf(name, ms, lat, lng) {
    if (name === "Sun") return Solar.altitude(new Date(ms), lat, lng)
    return body(name, ms, lat, lng).alt
}

var H0 = { Sun: -0.833, Moon: -0.583 }

// Next rise, set and highest point within `hours` from fromMs:
// { rise, set, transit, transitAlt, up } (ms or null).
function events(name, fromMs, hours, lat, lng) {
    const h0 = H0[name] !== undefined ? H0[name] : -0.567
    const step = 10 * 60000, end = fromMs + hours * 3600000
    let t0 = fromMs, f0 = altOf(name, t0, lat, lng) - h0
    const out = { rise: null, set: null, transit: null, transitAlt: -90, up: f0 > 0 }
    let bestT = t0, bestA = f0 + h0
    while (t0 < end) {
        const t1 = t0 + step, f1 = altOf(name, t1, lat, lng) - h0
        if (f1 + h0 > bestA) { bestA = f1 + h0; bestT = t1 }
        if ((f0 < 0) !== (f1 < 0)) {
            let lo = t0, hi = t1, flo = f0
            for (let k = 0; k < 12; k++) {
                const mid = (lo + hi) / 2, fm = altOf(name, mid, lat, lng) - h0
                if ((fm < 0) === (flo < 0)) { lo = mid; flo = fm } else hi = mid
            }
            if (f0 < 0 && out.rise === null) out.rise = (lo + hi) / 2
            if (f0 >= 0 && out.set === null) out.set = (lo + hi) / 2
        }
        t0 = t1; f0 = f1
    }
    out.transit = bestT; out.transitAlt = bestA
    return out
}

// The next stretch of astronomical night (sun below -18°) starting from fromMs:
// { start, end } in ms; start = fromMs if it is already dark.
function darkness(fromMs, lat, lng) {
    const step = 10 * 60000
    let t = fromMs, dark = Solar.altitude(new Date(t), lat, lng) < -18
    let start = dark ? fromMs : null, end = null
    for (let k = 0; k < 6 * 40 && end === null; k++) {
        const t1 = t + step, d1 = Solar.altitude(new Date(t1), lat, lng) < -18
        if (d1 !== dark) {
            if (d1) start = t1; else if (start !== null) end = t1
        }
        t = t1; dark = d1
    }
    return { start: start, end: end }
}

// Principal Moon phases in the next `days`: [{ name, t }]
function nextPhases(fromMs, days) {
    const elong = ms => {
        const jd = jdOf(ms)
        return norm360(Solar.moonPosition(jd).lon - sunApparent(jd).lon)
    }
    const names = ["New Moon", "First Quarter", "Full Moon", "Last Quarter"]
    const out = [], step = 12 * 3600000
    let t0 = fromMs, e0 = elong(t0)
    while (t0 < fromMs + days * 86400000) {
        const t1 = t0 + step, e1 = elong(t1)
        for (let q = 0; q < 4; q++) {
            const a = wrap180(e0 - q * 90), b = wrap180(e1 - q * 90)
            if (a < 0 && b >= 0 && b - a < 30) {
                let lo = t0, hi = t1
                for (let k = 0; k < 25; k++) {
                    const mid = (lo + hi) / 2
                    if (wrap180(elong(mid) - q * 90) < 0) lo = mid; else hi = mid
                }
                out.push({ name: names[q], t: (lo + hi) / 2 })
            }
        }
        t0 = t1; e0 = e1
    }
    return out
}

// ---- stars -------------------------------------------------------------------------

// Precessed once per session (to the current epoch; the shift is ~0.36° since 2000).
var starCache = null
function stars(jd) {
    if (starCache && Math.abs(starCache.jd - jd) < 3650) return starCache
    const years = (jd - 2451545.0) / 365.25
    const S = Cat.STARS, n = S.length / 4
    const ra = new Float32Array(n), sd = new Float32Array(n), cd = new Float32Array(n)
    const mag = new Float32Array(n), bv = new Float32Array(n)
    for (let i = 0; i < n; i++) {
        let a = S[i * 4], d = S[i * 4 + 1]
        const da = (3.075 + 1.336 * sind(a) * Math.tan(Math.min(89, Math.abs(d)) * RAD) * Math.sign(d)) * 15 / 3600 * years
        const dd = 20.04 * cosd(a) / 3600 * years
        a += da; d += dd
        ra[i] = a; sd[i] = sind(d); cd[i] = cosd(d); mag[i] = S[i * 4 + 2]; bv[i] = S[i * 4 + 3]
    }
    starCache = { jd: jd, n: n, ra: ra, sd: sd, cd: cd, mag: mag, bv: bv, years: years }
    return starCache
}

// Precess one J2000 (ra, dec) the same way.
function precess(a, d, years) {
    const da = (3.075 + 1.336 * sind(a) * Math.tan(Math.min(89, Math.abs(d)) * RAD) * Math.sign(d)) * 15 / 3600 * years
    return [a + da, d + 20.04 * cosd(a) / 3600 * years]
}

// Star colour from B-V (blackbody-ish, gently desaturated).
function bvColor(bv) {
    const stops = [[-0.4, 155, 176, 255], [0.0, 202, 215, 255], [0.4, 248, 247, 255],
                   [0.6, 255, 244, 234], [0.9, 255, 222, 180], [1.3, 255, 196, 140], [2.0, 255, 166, 100]]
    if (bv <= stops[0][0]) return stops[0].slice(1)
    for (let i = 1; i < stops.length; i++) {
        if (bv <= stops[i][0]) {
            const a = stops[i - 1], b = stops[i], f = (bv - a[0]) / (b[0] - a[0])
            return [a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f]
        }
    }
    return stops[stops.length - 1].slice(1)
}

// ---- meteor showers ----------------------------------------------------------------

// [name, month (1-12), day of peak, ZHR, radiant RA, radiant Dec] (IMO working list)
var SHOWERS = [
    ["Quadrantids", 1, 3, 80, 230, 49], ["Lyrids", 4, 22, 18, 271, 34],
    ["Eta Aquariids", 5, 6, 50, 338, -1], ["Southern Delta Aquariids", 7, 30, 25, 340, -16],
    ["Perseids", 8, 12, 100, 48, 58], ["Draconids", 10, 8, 10, 262, 54],
    ["Orionids", 10, 21, 20, 95, 16], ["Leonids", 11, 17, 15, 152, 22],
    ["Geminids", 12, 14, 150, 113, 32], ["Ursids", 12, 22, 10, 217, 76]
]

// The next shower peak after fromMs (peak night = local 02:00 on the peak date):
// { name, t, zhr, moonIllum, radiantAlt (at 02:00), days }
function nextShower(fromMs, lat, lng) {
    const now = new Date(fromMs)
    let best = null
    for (let y = now.getFullYear(); y <= now.getFullYear() + 1 && !best; y++) {
        for (const s of SHOWERS) {
            const t = new Date(y, s[1] - 1, s[2], 2, 0).getTime()
            if (t + 86400000 < fromMs) continue
            if (!best || t < best.t) best = { name: s[0], t: t, zhr: s[3], ra: s[4], dec: s[5] }
        }
    }
    const p = Solar.moonPhase(new Date(best.t))
    best.moonIllum = p.illum
    best.radiantAlt = horizontal(best.ra, best.dec, jdOf(best.t), lat, lng).alt
    best.days = Math.max(0, Math.round((best.t - fromMs) / 86400000))
    return best
}

var COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
function compass(az) { return COMPASS[Math.floor((norm360(az) + 11.25) / 22.5) % 16] }

function fmtClock(ms) { return ms ? Qt.formatTime(new Date(ms), Qt.locale().timeFormat(1)) : "—" }

// Angle between two (ra, dec) points, degrees.
function separation(a, b) {
    const c = sind(a.dec) * sind(b.dec) + cosd(a.dec) * cosd(b.dec) * cosd(a.ra - b.ra)
    return Math.acos(Math.max(-1, Math.min(1, c))) / RAD
}

// Everything the "tonight" side of the popup needs, from now:
// { dark, moon (events), phases, shower, planets: [{ name, color, mag, alt, az, status }] }
function almanac(nowMs, lat, lng) {
    const sun = body("Sun", nowMs, lat, lng)
    const sunEv = events("Sun", nowMs, 30, lat, lng)
    const firstLight = sunEv.rise ? sunEv.rise - 40 * 60000 : null      // ~ sun at -9°
    const lastLight = sunEv.set ? sunEv.set + 40 * 60000 : null
    const planets = PLANETS.map(n => {
        const b = body(n, nowMs, lat, lng)
        const ev = events(n, nowMs, 24, lat, lng)
        const elong = separation(b, sun)
        let status
        const atDusk = lastLight ? body(n, lastLight, lat, lng) : null
        const atDawn = firstLight ? body(n, firstLight, lat, lng) : null
        const transitDark = ev.transit && Solar.altitude(new Date(ev.transit), lat, lng) < -6
        const where = d => Math.round(d.alt) + "° " + compass(d.az)
        if (elong < 12) status = "lost in the Sun's glare (" + Math.round(elong) + "°)"
        else if (sun.alt < -6 && b.alt > 0) status = "up · " + where(b) + " · sets " + fmtClock(ev.set)
        else if (sun.alt >= -6 && atDusk && atDusk.alt > 5) status = "evening sky, " + where(atDusk) + " at dusk · sets " + fmtClock(ev.set)
        else if (transitDark) status = "rises " + fmtClock(ev.rise) + " · highest " + fmtClock(ev.transit) + " at " + Math.round(ev.transitAlt) + "°"
        else if (atDawn && atDawn.alt > 5) status = "rises " + fmtClock(ev.rise) + " · morning sky, " + where(atDawn) + " at first light"
        else status = "too low in twilight to see"
        if (elong >= 12 && b.mag > 5.5) status += " · binoculars"
        return { name: n, color: b.color, mag: b.mag, alt: b.alt, az: b.az, status: status }
    })
    return { dark: darkness(nowMs, lat, lng), moon: events("Moon", nowMs, 30, lat, lng),
             phases: nextPhases(nowMs, 35), shower: nextShower(nowMs, lat, lng), planets: planets }
}
