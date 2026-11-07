import QtQuick
import QtQuick.Controls as Controls

Controls.Slider {
    id: slider

    property bool dark: true

    implicitHeight: 18
    implicitWidth: 120
    padding: 0

    background: Rectangle {
        color: slider.dark ? "#34383d" : "#c7cdd6"
        height: 4
        radius: 2
        width: slider.availableWidth
        x: slider.leftPadding
        y: slider.topPadding + (slider.availableHeight - height) / 2

        Rectangle {
            color: slider.dark ? "#989da3" : "#7c8796"
            height: parent.height
            opacity: slider.enabled ? 1 : .4
            radius: 2
            width: slider.visualPosition * parent.width
        }
    }
    handle: Rectangle {
        border.color: slider.dark ? "#92969c" : "#adb5c0"
        color: slider.dark ? "#d8dadd" : "#ffffff"
        height: 14
        opacity: slider.enabled ? 1 : .5
        radius: 7
        width: 14
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + (slider.availableHeight - height) / 2
    }
}
