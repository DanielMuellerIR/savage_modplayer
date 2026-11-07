import QtQuick
import QtQuick.Controls

CheckBox {
    id: control

    property color accent: dark ? "#5cb3c2" : "#0055b5"
    property real baseFontSize: 9
    property bool dark: true
    property real textScale: 1

    implicitHeight: 22
    implicitWidth: label.implicitWidth + 18
    padding: 0
    spacing: 6

    contentItem: Text {
        id: label

        color: control.dark ? "#eceef0" : "#13171d"
        leftPadding: 16
        text: control.text
        verticalAlignment: Text.AlignVCenter

        font {
            pixelSize: control.baseFontSize * control.textScale
            weight: Font.DemiBold
        }
    }
    indicator: Rectangle {
        border.color: control.checked ? control.accent : (control.dark ? "#9ea8b0" : "#576170")
        color: control.checked ? control.accent : "transparent"
        height: 10
        radius: 1
        width: 10
        x: 0
        y: (control.height - height) / 2

        Text {
            anchors.centerIn: parent
            color: control.dark ? "#050608" : "white"
            text: control.checked ? "✓" : ""

            font {
                bold: true
                pixelSize: 9
            }
        }
    }
}
