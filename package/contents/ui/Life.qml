import QtQuick

// Small life in the sky: the brightest stars twinkle (harder near the horizon, where
// there's more air to look through), and at dawn and dusk a flock of birds now and
// then crosses on its way to or from the river.
Item {
    id: life

    property var cam
    property var brightStars: []        // [{ x, y, r, c (rgb), z }] from the star layer
    property real sunAlt: -30
    property real time: Date.now()
    readonly property real s: cam ? Math.max(0.6, cam.h / 1440) : 1

    // ---- twinkling -----------------------------------------------------------------
    Repeater {
        model: life.brightStars
        Item {
            id: tw
            required property var modelData
            readonly property real depth: 1 - Math.min(1, modelData.z / 0.6)   // 1 at the horizon
            x: modelData.x; y: modelData.y
            Rectangle {
                id: flare
                readonly property real d: tw.modelData.r * 5
                width: d; height: d; radius: d / 2
                x: -d / 2; y: -d / 2
                color: Qt.rgba(tw.modelData.c[0] / 255, tw.modelData.c[1] / 255, tw.modelData.c[2] / 255, 0.35)
                opacity: 0
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25 + 0.75 * tw.depth * Math.random(); duration: 90 + Math.random() * 260 }
                    NumberAnimation { to: 0; duration: 120 + Math.random() * 380 }
                    PauseAnimation { duration: 200 + Math.random() * 900 * (1 - tw.depth) }
                }
            }
        }
    }

    // ---- birds at dawn and dusk ------------------------------------------------------
    readonly property bool twilight: sunAlt > -7 && sunAlt < 7
    Timer {
        interval: 45000; running: life.twilight; repeat: true
        onTriggered: if (Math.random() < 0.35 && life.cam) flock.createObject(life, {})
    }
    Component {
        id: flock
        Item {
            id: f
            readonly property bool rtl: Math.random() < 0.5
            readonly property int n: 4 + Math.floor(Math.random() * 7)
            readonly property real y0: life.height * (0.15 + Math.random() * 0.3)
            readonly property real scale0: life.s * (0.7 + Math.random() * 0.6)
            x: rtl ? life.width + 80 : -200
            y: y0
            NumberAnimation on x {
                to: f.rtl ? -260 : life.width + 120
                duration: 38000 + Math.random() * 26000
                onFinished: f.destroy()
            }
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { to: f.y0 - 14 * life.s; duration: 4200; easing.type: Easing.InOutSine }
                NumberAnimation { to: f.y0 + 10 * life.s; duration: 4600; easing.type: Easing.InOutSine }
            }
            Repeater {
                model: f.n
                Item {
                    id: bird
                    required property int index
                    // a loose V
                    x: (f.rtl ? 1 : -1) * index * 18 * f.scale0 + (Math.random() - 0.5) * 10 * f.scale0
                    y: (index % 2 ? 1 : -1) * Math.ceil(index / 2) * 11 * f.scale0 + (Math.random() - 0.5) * 6 * f.scale0
                    property real flap: 0
                    SequentialAnimation on flap {
                        loops: Animation.Infinite
                        PauseAnimation { duration: Math.random() * 400 }
                        NumberAnimation { to: 1; duration: 210; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 230; easing.type: Easing.InOutSine }
                    }
                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            width: 8 * f.scale0; height: Math.max(1, 1.6 * f.scale0); radius: height / 2
                            color: "#0A0A0E"
                            antialiasing: true
                            transformOrigin: index ? Item.Left : Item.Right
                            x: index ? 0 : -width
                            rotation: (index ? -1 : 1) * (10 + 32 * bird.flap)
                        }
                    }
                }
            }
        }
    }
}
