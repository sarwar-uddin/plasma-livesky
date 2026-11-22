import QtQuick
import org.kde.plasma.plasmoid

// Live Sky: the real sky over you, right now, as a wallpaper or a lock screen.
WallpaperItem {
    id: root
    accentColor: "#E0203F"

    Rectangle { anchors.fill: parent; color: "#030308" }

    LiveSky {
        anchors.fill: parent
        config: root.configuration
    }
}
