import QtQuick
import QtQuick.Particles

// Rain, when the live weather says it's raining, slanted by the wind. In front of
// everything, as rain is.
Item {
    id: rain
    property var weather: null
    property real drift: 0
    property real dayK: 0
    readonly property real s: Math.max(0.6, height / 1440)
    readonly property real mm: weather ? (weather.rain || 0) : 0
    readonly property bool raining: !!weather && (mm > 0.05 || [51, 53, 55, 61, 63, 65, 80, 81, 82, 95, 96, 99].indexOf(weather.code) >= 0)
    visible: raining

    ParticleSystem {
        id: sys
        anchors.fill: parent
        running: rain.raining
        ItemParticle {
            delegate: Rectangle {
                width: Math.max(1, 1.2 * rain.s); height: (18 + Math.random() * 16) * rain.s
                color: rain.dayK > 0.5 ? "#55C8D4E0" : "#40A0A8C0"
                rotation: -rain.drift * 0.4
            }
        }
        Emitter {
            width: parent.width * 1.2; x: -parent.width * 0.1; y: -40
            emitRate: rain.raining ? Math.min(900, 140 + rain.mm * 260) : 0
            lifeSpan: 1400
            velocity: PointDirection { x: rain.drift * 6; y: 1300 * rain.s; yVariation: 200 * rain.s }
        }
    }
}
