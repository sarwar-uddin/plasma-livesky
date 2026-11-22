import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: form
    property alias cfg_placeName: placeField.text
    property real cfg_latitude
    property real cfg_longitude
    property int cfg_facing
    property int cfg_skyMode
    property alias cfg_showLabels: labelsBox.checked
    property alias cfg_meteors: meteorsBox.checked
    property alias cfg_showClock: clockBox.checked
    property alias cfg_showInfo: infoBox.checked
    property alias cfg_use24h: h24Box.checked
    property string cfg_prayerMethod
    property bool cfg_asrHanafi
    property string cfg_landmarks
    property string cfg_tle
    property string cfg_weather

    QQC2.TextField { id: placeField; Kirigami.FormData.label: i18n("Place name:") }
    QQC2.TextField {
        Kirigami.FormData.label: i18n("Latitude:")
        text: form.cfg_latitude.toFixed(4)
        validator: DoubleValidator { bottom: -90; top: 90; notation: DoubleValidator.StandardNotation }
        onTextEdited: { const v = parseFloat(text); if (!isNaN(v) && acceptableInput) form.cfg_latitude = v }
    }
    QQC2.TextField {
        Kirigami.FormData.label: i18n("Longitude:")
        text: form.cfg_longitude.toFixed(4)
        validator: DoubleValidator { bottom: -180; top: 180; notation: DoubleValidator.StandardNotation }
        onTextEdited: { const v = parseFloat(text); if (!isNaN(v) && acceptableInput) form.cfg_longitude = v }
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Facing:")
        readonly property var azs: [180, 135, 225, 90, 270, 0]
        model: [i18n("South"), i18n("South-east"), i18n("South-west"), i18n("East"), i18n("West"), i18n("North")]
        currentIndex: Math.max(0, azs.indexOf(form.cfg_facing))
        onActivated: index => form.cfg_facing = azs[index]
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Stars:")
        model: [i18n("City sky (to magnitude 3.2)"), i18n("Suburban (4.5)"), i18n("Dark site (5.5, Milky Way)")]
        currentIndex: form.cfg_skyMode
        onActivated: index => form.cfg_skyMode = index
    }
    QQC2.CheckBox { id: labelsBox; text: i18n("Names of planets, bright stars and constellations") }
    QQC2.CheckBox { id: meteorsBox; text: i18n("Meteors (more around shower peaks)") }
    Item { Kirigami.FormData.isSection: true }
    QQC2.CheckBox { id: clockBox; Kirigami.FormData.label: i18n("Clock:"); text: i18n("Show the clock and date") }
    QQC2.CheckBox { id: h24Box; text: i18n("24-hour time") }
    QQC2.CheckBox { id: infoBox; text: i18n("Weather, prayer, Moon, planets and satellites read-out") }
}
