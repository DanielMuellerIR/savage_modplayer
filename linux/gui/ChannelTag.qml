import QtQuick
import QtQuick.Controls

AbstractButton {
    id: control

    property bool active: false
    property color tagColor: text === "M" ? "#ff3b30" : "#34c759"

    implicitHeight: 14
    implicitWidth: 13

    background: Rectangle {
        color: control.active ? control.tagColor : "transparent"
        radius: 2
    }
    contentItem: Text {
        color: control.active ? "white" : control.tagColor
        horizontalAlignment: Text.AlignHCenter
        text: control.text
        verticalAlignment: Text.AlignVCenter

        font {
            bold: true
            pixelSize: 8
        }
    }
}
