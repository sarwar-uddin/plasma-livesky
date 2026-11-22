// Kept for the Chronos clock widget (not used by Live Sky): Bangla (2019 revision) and
// Hijri by Yallop crescent visibility. Depends on sky.js and solar.js.
.pragma library
.import "sky.js" as Sky
.import "solar.js" as Solar

// The three calendars on the clock: Gregorian, Bangla (Bangabda) and Hijri.

// ---- Bangla: the Bangladesh calendar as revised in 2019 ---------------------------
// 1 Boishakh is always 14 April. The first six months have 31 days, the rest 30,
// except Falgun: 29 days, or 30 when the Gregorian year it falls in is a leap year.

var BN_MONTHS = ["বৈশাখ", "জ্যৈষ্ঠ", "আষাঢ়", "শ্রাবণ", "ভাদ্র", "আশ্বিন",
                 "কার্তিক", "অগ্রহায়ণ", "পৌষ", "মাঘ", "ফাল্গুন", "চৈত্র"]
var BN_DIGITS = "০১২৩৪৫৬৭৮৯"

function bnDigits(n) { return String(n).replace(/[0-9]/g, d => BN_DIGITS[+d]) }

function isLeap(y) { return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 }

// { day, month (0-11), year, text }
function bangla(date) {
    const y = date.getFullYear()
    const startYear = (date.getMonth() > 3 || (date.getMonth() === 3 && date.getDate() >= 14)) ? y : y - 1
    const start = Date.UTC(startYear, 3, 14)
    let days = Math.round((Date.UTC(y, date.getMonth(), date.getDate()) - start) / 86400000)
    const lengths = [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, isLeap(startYear + 1) ? 30 : 29, 30]
    let m = 0
    while (m < 11 && days >= lengths[m]) { days -= lengths[m]; m++ }
    const year = startYear - 593
    return { day: days + 1, month: m, year: year,
             text: bnDigits(days + 1) + " " + BN_MONTHS[m] + " " + bnDigits(year) }
}

// ---- Hijri: by predicted crescent sighting ------------------------------------------
// Each month starts the day after the first evening on which the new crescent can be
// seen from the observer, judged by Yallop's q-test (NAO Technical Note 69, 1997) at
// sunset: q > -0.160 (classes A-C, visible to the eye, perhaps after finding it with
// optics). That follows South Asian sightings far better than the fixed tabular
// calendar. `offset` (days) covers a committee deciding otherwise.

var HIJRI_MONTHS = ["Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani", "Jumada al-Awwal",
                    "Jumada al-Akhirah", "Rajab", "Sha'ban", "Ramadan", "Shawwal",
                    "Dhu al-Qa'dah", "Dhu al-Hijjah"]
var SYNODIC = 29.530588861

function elongation(ms) {           // Moon minus Sun ecliptic longitude, -180..180
    const jd = Sky.jdOf(ms)
    return Sky.wrap180(Solar.moonPosition(jd).lon - Sky.sunApparent(jd).lon)
}

// The new moon (conjunction) closest to ms.
function newMoonNear(ms) {
    // step to the zero crossing of the elongation, then bisect
    let t = ms - elongation(ms) / 360 * SYNODIC * 86400000
    for (let k = 0; k < 3; k++) t -= elongation(t) / 360 * SYNODIC * 86400000
    let lo = t - 6 * 3600000, hi = t + 6 * 3600000
    for (let k = 0; k < 30; k++) {
        const mid = (lo + hi) / 2
        if (elongation(mid) < 0) lo = mid; else hi = mid
    }
    return (lo + hi) / 2
}

function localMidnight(ms) { const d = new Date(ms); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() }

// Yallop's q at time t: ARCV (Moon's height above the Sun) against the crescent's width W.
function yallopQ(t, lat, lng) {
    const moon = Sky.body("Moon", t, lat, lng), sun = Sky.body("Sun", t, lat, lng)
    const arcv = moon.alt - sun.alt
    const arcl = Sky.separation(moon, sun)
    const sd = 0.2725 * 6378.14 / (moon.dist * 149597870.7) / Math.PI * 180 * 60   // semi-diameter, arcmin
    const W = sd * (1 - Math.cos(arcl * Math.PI / 180))
    return (arcv - (11.8371 - 6.3226 * W + 0.7319 * W * W - 0.1018 * W * W * W)) / 10
}

// Local midnight starting day 1 of the month that begins after conjunction `conj`.
function monthStart(conj, lat, lng) {
    let day = localMidnight(conj)
    for (let k = 0; k < 4; k++, day += 86400000) {
        const sunset = Solar.compute(new Date(day + 12 * 3600000), lat, lng, "karachi", 2, [0, 0, 0, 0, 0, 0]).sunset
        if (!sunset || sunset.getTime() < conj) continue
        const t = sunset.getTime()
        if (yallopQ(t, lat, lng) > -0.160) return day + 86400000
    }
    return day + 86400000      // a month never runs past 30 days
}

// Anchor: 1 Jumada al-Akhirah 1448 follows the conjunction of 9 November 2026.
var ANCHOR_CONJ = Date.UTC(2026, 10, 9, 7, 0)
var ANCHOR_INDEX = (1448 - 1) * 12 + 5

var hijriCache = {}
// { day, month (0-11), year, text } for the local calendar date of ms.
function hijri(ms, lat, lng, offset) {
    const today = localMidnight(ms) - (offset || 0) * 86400000
    const key = today + ":" + lat.toFixed(2) + ":" + lng.toFixed(2)
    if (hijriCache[key]) return hijriCache[key]
    let conj = newMoonNear(today)
    if (conj > today) conj = newMoonNear(conj - SYNODIC * 86400000)
    let start = monthStart(conj, lat, lng)
    if (start > today) {                    // crescent not seen yet: still last month
        conj = newMoonNear(conj - SYNODIC * 86400000)
        start = monthStart(conj, lat, lng)
    }
    const index = ANCHOR_INDEX + Math.round((conj - ANCHOR_CONJ) / (SYNODIC * 86400000))
    const month = ((index % 12) + 12) % 12, year = Math.floor(index / 12) + 1
    const day = Math.round((today - start) / 86400000) + 1
    const r = { day: day, month: month, year: year, text: day + " " + HIJRI_MONTHS[month] + " " + year + " AH" }
    hijriCache[key] = r
    return r
}
