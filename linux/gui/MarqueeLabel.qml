import QtQuick

Item {
    id: label

    property bool bold: false
    property color ink: "white"
    property real pointSize: 17
    property string text: ""

    clip: true
    implicitHeight: content.implicitHeight

    onTextChanged: {
        content.x = 0;
        movement.restart();
    }

    Text {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        color: label.ink
        text: label.text

        font {
            bold: label.bold
            pixelSize: label.pointSize
        }
    }
    SequentialAnimation {
        id: movement

        loops: Animation.Infinite
        running: label.visible && content.implicitWidth > label.width + 1

        PauseAnimation {
            duration: 1200
        }
        NumberAnimation {
            duration: Math.max(1500, (content.implicitWidth - label.width) / 24 * 1000)
            from: 0
            property: "x"
            target: content
            to: -Math.max(0, content.implicitWidth - label.width)
        }
        PauseAnimation {
            duration: 1200
        }
        NumberAnimation {
            duration: 0
            property: "x"
            target: content
            to: 0
        }
    }
}
