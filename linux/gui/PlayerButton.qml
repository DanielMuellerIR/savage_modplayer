import QtQuick
import QtQuick.Controls

Button {
    id: control

    property color accent: dark ? "#5cb3c2" : "#0055b5"
    property bool accentFill: false
    property bool active: false
    property bool dark: true
    property string hint: ""
    property string iconName: ""
    property bool round: false
    property bool spinning: false
    property real textScale: 1

    ToolTip.delay: 700
    ToolTip.text: hint || text
    ToolTip.visible: hovered && (hint.length > 0 || label.truncated)
    implicitHeight: round ? 30 : 28
    implicitWidth: round ? 30 : Math.max(28, label.implicitWidth + 20)
    opacity: enabled ? 1 : 0.35
    padding: 0

    background: Rectangle {
        border.color: control.hovered ? control.accent : (control.dark ? "#25363b" : "#d7dce3")
        border.width: control.round || control.hovered ? 1 : 0
        color: control.active || control.accentFill ? control.accent : (control.dark ? "#131518" : "#edf0f4")
        opacity: control.down ? 0.65 : 1
        radius: control.dark ? (control.round ? height / 2 : 5) : 0
    }
    contentItem: Item {
        Text {
            id: label

            anchors.fill: parent
            color: control.active || control.accentFill ? "white" : (control.dark ? "#9ea8b0" : "#576170")
            elide: Text.ElideRight
            font.pixelSize: 11 * control.textScale
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            text: control.text
            verticalAlignment: Text.AlignVCenter
            visible: !control.iconName
        }
        PlayerIcon {
            accent: control.accent
            anchors.centerIn: parent
            ground: control.dark ? "#050608" : "#f6f7fa"
            height: width
            ink: control.dark ? "#eceef0" : "#13171d"
            name: control.iconName
            running: control.spinning
            visible: !!control.iconName
            width: control.iconName.startsWith("disc") ? 36 : 21
        }
    }
}
