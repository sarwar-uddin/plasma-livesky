// Satellites for the Cosmic Observatory: TLE parsing, SGP4 (near-Earth branch),
// look angles from the observer, Earth's shadow, brightness and visible passes.
//
// SGP4 follows Vallado, Crawford, Hujsak & Kelso, "Revisiting Spacetrack Report #3"
// (AIAA 2006-6753) with WGS-72 constants, as the reference implementation does.
// Only the near-Earth model is here (periods under 225 minutes): everything you can
// see pass overhead with the naked eye. Deep-space objects are skipped.
//
// An ES module, so the panel, the sky chart and the pass-finding WorkerScript can all
// import it, and node can test it directly.

const TWO_PI = 2 * Math.PI
const DEG = Math.PI / 180
const MU = 398600.8, RE = 6378.135                     // WGS-72
const XKE = 60 / Math.sqrt(RE * RE * RE / MU)
const J2 = 0.001082616, J3 = -0.00000253881, J4 = -0.00000165597, J3OJ2 = J3 / J2
const X2O3 = 2 / 3

// Standard magnitudes (at 1000 km range, half lit) for the ones we name.
export const STD_MAG = { 25544: -1.8, 48274: -0.8, 20580: 2.2 }
export const NAMES = { 25544: "ISS", 48274: "Tiangong", 20580: "Hubble" }

// ---- TLE ---------------------------------------------------------------------------

function tleNum(s) { return parseFloat(s.trim()) }
function tleExp(s) {            // " 14903-3" -> 0.14903e-3
    s = s.trim()
    if (!s) return 0
    const sign = s[0] === "-" ? -1 : 1
    if (s[0] === "-" || s[0] === "+") s = s.slice(1)
    const m = s.match(/^(\d+)([-+]\d)$/)
    return m ? sign * parseFloat("0." + m[1]) * Math.pow(10, +m[2]) : sign * parseFloat(s)
}

// Three-line TLE text -> [{ name, id, epochJd, ... }] (near-Earth only).
export function parseTLEs(text) {
    const lines = text.split(/\r?\n/).map(l => l.replace(/\s+$/, "")).filter(l => l.length)
    const out = []
    for (let i = 0; i + 2 < lines.length + 1; i++) {
        if (!lines[i + 1] || !lines[i + 2] || lines[i + 1][0] !== "1" || lines[i + 2][0] !== "2") continue
        const rec = parseTLE(lines[i].trim(), lines[i + 1], lines[i + 2])
        if (rec) out.push(rec)
        i += 2
    }
    return out
}

export function parseTLE(name, l1, l2) {
    const id = parseInt(l1.slice(2, 7))
    const yy = parseInt(l1.slice(18, 20)), day = tleNum(l1.slice(20, 32))
    const year = yy < 57 ? 2000 + yy : 1900 + yy
    const epochJd = Date.UTC(year, 0, 1) / 86400000 + 2440587.5 + day - 1
    const s = {
        name: name, id: id, label: NAMES[id] || name, epochJd: epochJd,
        bstar: tleExp(l1.slice(53, 61)),
        inclo: tleNum(l2.slice(8, 16)) * DEG, nodeo: tleNum(l2.slice(17, 25)) * DEG,
        ecco: parseFloat("0." + l2.slice(26, 33).trim()), argpo: tleNum(l2.slice(34, 42)) * DEG,
        mo: tleNum(l2.slice(43, 51)) * DEG, noKozai: tleNum(l2.slice(52, 63)) * TWO_PI / 1440
    }
    return init(s)
}

// ---- SGP4 -------------------------------------------------------------------------------

function init(s) {
    const ss = 78 / RE + 1, qzms2t = Math.pow((120 - 78) / RE, 4)
    const eccsq = s.ecco * s.ecco, omeosq = 1 - eccsq, rteosq = Math.sqrt(omeosq)
    const cosio = Math.cos(s.inclo), cosio2 = cosio * cosio
    // un-Kozai the mean motion
    const ak = Math.pow(XKE / s.noKozai, X2O3)
    const d1 = 0.75 * J2 * (3 * cosio2 - 1) / (rteosq * omeosq)
    let del = d1 / (ak * ak)
    const adel = ak * (1 - del * del - del * (1 / 3 + 134 * del * del / 81))
    del = d1 / (adel * adel)
    const no = s.noKozai / (1 + del)
    const ao = Math.pow(XKE / no, X2O3)
    if (TWO_PI / no >= 225) return null                    // deep space: not handled
    const sinio = Math.sin(s.inclo), po = ao * omeosq, con42 = 1 - 5 * cosio2
    const con41 = -con42 - cosio2 - cosio2, posq = po * po, rp = ao * (1 - s.ecco)

    let isimp = rp < 220 / RE + 1 ? 1 : 0
    let sfour = ss, qzms24 = qzms2t
    const perige = (rp - 1) * RE
    if (perige < 156) {
        sfour = perige < 98 ? 20 : perige - 78
        qzms24 = Math.pow((120 - sfour) / RE, 4)
        sfour = sfour / RE + 1
    }
    const pinvsq = 1 / posq, tsi = 1 / (ao - sfour)
    const eta = ao * s.ecco * tsi, etasq = eta * eta, eeta = s.ecco * eta
    const psisq = Math.abs(1 - etasq), coef = qzms24 * Math.pow(tsi, 4)
    const coef1 = coef / Math.pow(psisq, 3.5)
    const cc2 = coef1 * no * (ao * (1 + 1.5 * etasq + eeta * (4 + etasq))
                + 0.375 * J2 * tsi / psisq * con41 * (8 + 3 * etasq * (8 + etasq)))
    const cc1 = s.bstar * cc2
    const cc3 = s.ecco > 1e-4 ? -2 * coef * tsi * J3OJ2 * no * sinio / s.ecco : 0
    const x1mth2 = 1 - cosio2
    const cc4 = 2 * no * coef1 * ao * omeosq * (eta * (2 + 0.5 * etasq) + s.ecco * (0.5 + 2 * etasq)
                - J2 * tsi / (ao * psisq) * (-3 * con41 * (1 - 2 * eeta + etasq * (1.5 - 0.5 * eeta))
                + 0.75 * x1mth2 * (2 * etasq - eeta * (1 + etasq)) * Math.cos(2 * s.argpo)))
    const cc5 = 2 * coef1 * ao * omeosq * (1 + 2.75 * (etasq + eeta) + eeta * etasq)
    const cosio4 = cosio2 * cosio2
    const temp1 = 1.5 * J2 * pinvsq * no, temp2 = 0.5 * temp1 * J2 * pinvsq, temp3 = -0.46875 * J4 * pinvsq * pinvsq * no
    const mdot = no + 0.5 * temp1 * rteosq * con41 + 0.0625 * temp2 * rteosq * (13 - 78 * cosio2 + 137 * cosio4)
    const argpdot = -0.5 * temp1 * con42 + 0.0625 * temp2 * (7 - 114 * cosio2 + 395 * cosio4)
                    + temp3 * (3 - 36 * cosio2 + 49 * cosio4)
    const xhdot1 = -temp1 * cosio
    const nodedot = xhdot1 + (0.5 * temp2 * (4 - 19 * cosio2) + 2 * temp3 * (3 - 7 * cosio2)) * cosio
    const c = {
        no: no, ao: ao, isimp: isimp, cc1: cc1, cc4: cc4, cc5: cc5, mdot: mdot, argpdot: argpdot, nodedot: nodedot,
        omgcof: s.bstar * cc3 * Math.cos(s.argpo),
        xmcof: s.ecco > 1e-4 ? -X2O3 * coef * s.bstar / eeta : 0,
        nodecf: 3.5 * omeosq * xhdot1 * cc1, t2cof: 1.5 * cc1,
        xlcof: -0.25 * J3OJ2 * sinio * (3 + 5 * cosio) / (Math.abs(cosio + 1) > 1.5e-12 ? 1 + cosio : 1.5e-12),
        aycof: -0.5 * J3OJ2 * sinio, delmo: Math.pow(1 + eta * Math.cos(s.mo), 3), sinmao: Math.sin(s.mo),
        x7thm1: 7 * cosio2 - 1, eta: eta, con41: con41, x1mth2: x1mth2, d2: 0, d3: 0, d4: 0, t3cof: 0, t4cof: 0, t5cof: 0
    }
    if (!isimp) {
        const cc1sq = cc1 * cc1
        c.d2 = 4 * ao * tsi * cc1sq
        const temp = c.d2 * tsi * cc1 / 3
        c.d3 = (17 * ao + sfour) * temp
        c.d4 = 0.5 * temp * ao * tsi * (221 * ao + 31 * sfour) * cc1
        c.t3cof = c.d2 + 2 * cc1sq
        c.t4cof = 0.25 * (3 * c.d3 + cc1 * (12 * c.d2 + 10 * cc1sq))
        c.t5cof = 0.2 * (3 * c.d4 + 12 * cc1 * c.d3 + 6 * c.d2 * c.d2 + 15 * cc1sq * (2 * c.d2 + cc1sq))
    }
    s.c = c
    return s
}

function fmod2p(x) { x = x % TWO_PI; return x < 0 ? x + TWO_PI : x }

// TEME position (km) at `tsince` minutes from epoch, or null if the orbit has decayed.
export function propagate(s, tsince) {
    const c = s.c, t = tsince
    const xmdf = s.mo + c.mdot * t, argpdf = s.argpo + c.argpdot * t, nodedf = s.nodeo + c.nodedot * t
    let argpm = argpdf, mm = xmdf
    const t2 = t * t
    let nodem = nodedf + c.nodecf * t2
    let tempa = 1 - c.cc1 * t, tempe = s.bstar * c.cc4 * t, templ = c.t2cof * t2
    if (!c.isimp) {
        const delomg = c.omgcof * t
        const delm = c.xmcof * (Math.pow(1 + c.eta * Math.cos(xmdf), 3) - c.delmo)
        const temp = delomg + delm
        mm = xmdf + temp
        argpm = argpdf - temp
        const t3 = t2 * t, t4 = t3 * t
        tempa = tempa - c.d2 * t2 - c.d3 * t3 - c.d4 * t4
        tempe = tempe + s.bstar * c.cc5 * (Math.sin(mm) - c.sinmao)
        templ = templ + c.t3cof * t3 + t4 * (c.t4cof + t * c.t5cof)
    }
    const am = Math.pow(XKE / c.no, X2O3) * tempa * tempa
    const nm = XKE / Math.pow(am, 1.5)
    let em = s.ecco - tempe
    if (em >= 1 || em < -0.001 || am < 0.95) return null
    if (em < 1e-6) em = 1e-6
    mm = mm + c.no * templ
    let xlm = mm + argpm + nodem
    nodem = fmod2p(nodem); argpm = fmod2p(argpm); xlm = fmod2p(xlm)
    mm = fmod2p(xlm - argpm - nodem)

    const sinip = Math.sin(s.inclo), cosip = Math.cos(s.inclo)
    const axnl = em * Math.cos(argpm)
    let temp = 1 / (am * (1 - em * em))
    const aynl = em * Math.sin(argpm) + temp * c.aycof
    const xl = mm + argpm + nodem + temp * c.xlcof * axnl
    const u = fmod2p(xl - nodem)
    let eo1 = u, tem5 = 9999.9, ktr = 1, sineo1 = 0, coseo1 = 0
    while (Math.abs(tem5) >= 1e-12 && ktr <= 10) {
        sineo1 = Math.sin(eo1); coseo1 = Math.cos(eo1)
        tem5 = 1 - coseo1 * axnl - sineo1 * aynl
        tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
        if (Math.abs(tem5) >= 0.95) tem5 = tem5 > 0 ? 0.95 : -0.95
        eo1 += tem5
        ktr++
    }
    const ecose = axnl * coseo1 + aynl * sineo1, esine = axnl * sineo1 - aynl * coseo1
    const el2 = axnl * axnl + aynl * aynl, pl = am * (1 - el2)
    if (pl < 0) return null
    const rl = am * (1 - ecose), betal = Math.sqrt(1 - el2)
    temp = esine / (1 + betal)
    const sinu = am / rl * (sineo1 - aynl - axnl * temp), cosu = am / rl * (coseo1 - axnl + aynl * temp)
    let su = Math.atan2(sinu, cosu)
    const sin2u = (cosu + cosu) * sinu, cos2u = 1 - 2 * sinu * sinu
    temp = 1 / pl
    const temp1 = 0.5 * J2 * temp, temp2 = temp1 * temp
    const mrt = rl * (1 - 1.5 * temp2 * betal * c.con41) + 0.5 * temp1 * c.x1mth2 * cos2u
    su = su - 0.25 * temp2 * c.x7thm1 * sin2u
    const xnode = nodem + 1.5 * temp2 * cosip * sin2u
    const xinc = s.inclo + 1.5 * temp2 * cosip * sinip * cos2u
    if (mrt < 1) return null
    const sinsu = Math.sin(su), cossu = Math.cos(su), snod = Math.sin(xnode), cnod = Math.cos(xnode)
    const sini = Math.sin(xinc), cosi = Math.cos(xinc)
    const xmx = -snod * cosi, xmy = cnod * cosi
    const k = mrt * RE
    return [(xmx * sinsu + cnod * cossu) * k, (xmy * sinsu + snod * cossu) * k, sini * sinsu * k]
}

// ---- where it is in your sky -------------------------------------------------------------------

export function jdOf(ms) { return ms / 86400000 + 2440587.5 }

function gmstRad(jd) {           // IAU-82, as the reference SGP4 uses
    const t = (jd - 2451545.0) / 36525
    let g = -6.2e-6 * t * t * t + 0.093104 * t * t + (876600 * 3600 + 8640184.812866) * t + 67310.54841
    g = (g * DEG / 240) % TWO_PI
    return g < 0 ? g + TWO_PI : g
}

// Observer on the WGS-84 ellipsoid: ECEF position (km).
export function observer(lat, lng, heightKm) {
    const a = 6378.137, f = 1 / 298.257223563, e2 = f * (2 - f)
    const sl = Math.sin(lat * DEG), cl = Math.cos(lat * DEG)
    const N = a / Math.sqrt(1 - e2 * sl * sl), h = heightKm || 0
    return { lat: lat, lng: lng, sl: sl, cl: cl, so: Math.sin(lng * DEG), co: Math.cos(lng * DEG),
             x: (N + h) * cl * Math.cos(lng * DEG), y: (N + h) * cl * Math.sin(lng * DEG), z: (N * (1 - e2) + h) * sl }
}

// Low-precision Sun direction (unit vector, true equator of date ~ TEME). Good to ~0.01°.
export function sunVector(jd) {
    const n = jd - 2451545.0
    const L = (280.460 + 0.9856474 * n) * DEG, g = (357.528 + 0.9856003 * n) * DEG
    const lam = L + (1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * DEG
    const eps = (23.439 - 0.0000004 * n) * DEG
    return [Math.cos(lam), Math.cos(eps) * Math.sin(lam), Math.sin(eps) * Math.sin(lam)]
}

// Look angles for satellite s at time ms from observer o:
// { alt, az (deg), range (km), sunlit, mag (or null), eci }
export function look(s, ms, o) {
    const jd = jdOf(ms)
    const r = propagate(s, (jd - s.epochJd) * 1440)
    if (!r) return null
    const g = gmstRad(jd), cg = Math.cos(g), sg = Math.sin(g)
    const x = cg * r[0] + sg * r[1], y = -sg * r[0] + cg * r[1], z = r[2]     // ECEF
    const dx = x - o.x, dy = y - o.y, dz = z - o.z
    // topocentric south-east-zenith
    const S = o.sl * o.co * dx + o.sl * o.so * dy - o.cl * dz
    const E = -o.so * dx + o.co * dy
    const Z = o.cl * o.co * dx + o.cl * o.so * dy + o.sl * dz
    const range = Math.sqrt(dx * dx + dy * dy + dz * dz)
    const alt = Math.asin(Z / range) / DEG
    let az = Math.atan2(E, -S) / DEG
    if (az < 0) az += 360
    // Earth's shadow, as a cylinder (plenty for the umbra edge at LEO heights)
    const sv = sunVector(jd)
    const rs = r[0] * sv[0] + r[1] * sv[1] + r[2] * sv[2]
    const px = r[0] - rs * sv[0], py = r[1] - rs * sv[1], pz = r[2] - rs * sv[2]
    const sunlit = rs > 0 || Math.sqrt(px * px + py * py + pz * pz) > 6371
    // brightness: a diffuse sphere seen at phase angle phi
    let mag = null
    if (STD_MAG[s.id] !== undefined && sunlit) {
        // observer -> sat in TEME: rotate the topocentric vector back
        const ox = cg * o.x - sg * o.y, oy = sg * o.x + cg * o.y
        const vx = r[0] - ox, vy = r[1] - oy, vz = r[2] - o.z
        const cosphi = -(vx * sv[0] + vy * sv[1] + vz * sv[2]) / range
        const phi = Math.acos(Math.max(-1, Math.min(1, cosphi)))
        const F = ((Math.PI - phi) * Math.cos(phi) + Math.sin(phi)) / Math.PI
        mag = STD_MAG[s.id] + 5 * Math.log10(range / 1000) - 2.5 * Math.log10(Math.max(1e-4, F * Math.PI))
    }
    return { alt: alt, az: az, range: range, sunlit: sunlit, mag: mag }
}

// Sun altitude at the observer (degrees), same low-precision Sun.
export function sunAlt(ms, o) {
    const jd = jdOf(ms), sv = sunVector(jd), g = gmstRad(jd)
    const x = Math.cos(g) * sv[0] + Math.sin(g) * sv[1], y = -Math.sin(g) * sv[0] + Math.cos(g) * sv[1], z = sv[2]
    return Math.asin(o.cl * o.co * x + o.cl * o.so * y + o.sl * z) / DEG
}

// Visible passes of s in [fromMs, fromMs + days): above minAlt, sunlit, with the sky dark
// enough (Sun below -6°). Each: { start, end, peak (ms), maxAlt, startAz, endAz, peakAz,
// mag (brightest), track: [{ t, alt, az }] } covering the visible part.
export function passes(s, fromMs, days, o, minAlt) {
    minAlt = minAlt === undefined ? 10 : minAlt
    const out = [], end = fromMs + days * 86400000
    const visible = l => l && l.alt >= minAlt && l.sunlit
    let t = fromMs
    while (t < end) {
        const l = look(s, t, o)
        if (!l) break
        if (l.alt < -15) { t += 120000; continue }          // far below: stride
        if (l.alt < minAlt) { t += 20000; continue }
        // above the horizon limit: walk the pass at 10 s
        let start = null, last = null, best = null, track = []
        let tt = t
        while (true) {
            const q = look(s, tt, o)
            if (!q || q.alt < minAlt) break
            const dark = sunAlt(tt, o) < -6
            if (dark && q.sunlit) {
                if (start === null) start = tt
                last = tt
                if (!best || q.alt > best.alt) best = { t: tt, alt: q.alt, az: q.az }
                track.push({ t: tt, alt: q.alt, az: q.az, mag: q.mag })
            }
            tt += 10000
        }
        if (start !== null && last - start >= 30000) {
            let mag = null
            for (const p of track) if (p.mag !== null && (mag === null || p.mag < mag)) mag = p.mag
            out.push({ id: s.id, label: s.label, start: start, end: last, peak: best.t, maxAlt: best.alt, peakAz: best.az,
                       startAz: track[0].az, startAlt: track[0].alt, endAz: track[track.length - 1].az,
                       endAlt: track[track.length - 1].alt, mag: mag,
                       track: track.filter((p, i) => i % 3 === 0 || i === track.length - 1) })
        }
        t = tt + 60000
    }
    return out
}
