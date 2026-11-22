// WorkerScript: finds visible passes off the UI thread.
// in:  { tle (text), ids: [norad], fromMs, days, lat, lng, minAlt }
// out: { passes: [...] (sorted by start), computedAt }
import { parseTLEs, passes, observer } from "sgp4.mjs"

WorkerScript.onMessage = function (m) {
    const sats = parseTLEs(m.tle).filter(s => m.ids.indexOf(s.id) >= 0)
    const o = observer(m.lat, m.lng, 0)
    let all = []
    for (const s of sats) all = all.concat(passes(s, m.fromMs, m.days, o, m.minAlt))
    all.sort((a, b) => a.start - b.start)
    WorkerScript.sendMessage({ passes: all, computedAt: Date.now() })
}
