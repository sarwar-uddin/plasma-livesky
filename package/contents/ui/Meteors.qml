import QtQuick
import "../code/view.js" as View
import "../code/sky.js" as Sky

// Now and then, a meteor. The sporadic background is a few an hour; around a major
// shower's peak the rate climbs with its ZHR and the height of its radiant, and those
// meteors streak away from the radiant like the real thing. Checked once a second.
Item {
    id: met

    property var cam
    property real time: Date.now()
    property real lat: 23.8103
    property real lng: 90.4125
    property real nightK: 1
    clip: true

    // the shower situation, worked out once every ten minutes (bound to `tick`, which only
    // changes every ten minutes, not to `time`, which changes every second)
    readonly property real tick: Math.floor(time / 600000) * 600000
    readonly property var state: {
        const t = tick
        const s = Sky.nextShower(t - 2 * 86400000, lat, lng)
        const rad = Sky.horizontal(s.ra, s.dec, Sky.jdOf(t), lat, lng)
        const dtDays = (t - s.t) / 86400000
        const active = Math.abs(dtDays) < 2.5 && rad.alt > 0
        // hourly rate we'd see in this window of sky
        const rate = 5 + (active ? s.zhr * Math.sin(rad.alt * Math.PI / 180) * Math.exp(-dtDays * dtDays / 0.5) * 0.35 : 0)
        return { rate: rate, active: active, rad: rad }
    }

    onTimeChanged: {
        if (!enabled || !cam || nightK < 0.9 || Math.random() > state.rate / 3600) return
        const rad = state.rad
        const shower = state.active && Math.random() < 0.8
        // start somewhere in the upper sky
        const alt = 20 + Math.random() * 55, az = cam.az0 - 80 + Math.random() * 160
        const p = View.projectAltAz(cam, alt, az)
        if (!View.onScreen(cam, p)) return
        let ang
        if (shower) {
            const r = View.projectAltAz(cam, rad.alt, rad.az)
            ang = r.ok ? Math.atan2(p.y - r.y, p.x - r.x) : Math.random() * 2 * Math.PI
        } else ang = Math.PI * (0.15 + Math.random() * 0.7)        // mostly falling
        meteor.createObject(met, { x: p.x, y: p.y, rotation: ang * 180 / Math.PI,
                                   len: (shower ? 160 : 110) + Math.random() * 220 * Math.max(1, cam.w / 1920) })
    }

    Component {
        id: meteor
        Item {
            id: m
            property real len: 200
            width: 1; height: 1
            transformOrigin: Item.TopLeft
            Rectangle {
                id: streak
                y: -1
                height: 2
                width: 0
                radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.8; color: "#88C8D0FF" }
                    GradientStop { position: 1.0; color: "#FFFFFFFF" }
                }
            }
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: streak; property: "width"; to: m.len; duration: 420; easing.type: Easing.OutQuad }
                    NumberAnimation { target: streak; property: "x"; to: m.len * 0.35; duration: 420; easing.type: Easing.InQuad }
                }
                NumberAnimation { target: m; property: "opacity"; to: 0; duration: 260 }
                ScriptAction { script: m.destroy() }
            }
        }
    }
}
