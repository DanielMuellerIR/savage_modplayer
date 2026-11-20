import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property string version

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Über Savage Mod Player"
    width: 600

    Rectangle {
        border.color: "#e5503a"
        border.width: 2
        color: "black"
        height: 240
        width: parent.width

        Column {
            anchors.centerIn: parent
            spacing: 16

            Text {
                color: "#e5503a"
                text: "Software Failure. Press left mouse button to continue."

                font {
                    family: "monospace"
                    pixelSize: 12
                }
            }
            Text {
                color: "#e5503a"
                text: "Guru Meditation #53415641.47454D4F"

                font {
                    family: "monospace"
                    pixelSize: 14
                }
            }
            Text {
                color: "#e5503a"
                text: "Savage Mod Player " + dialog.version + " · Daniel Müller\nEigenständige Swift-Replay-Engine · WTFPL"

                font {
                    family: "monospace"
                    pixelSize: 12
                }
            }
        }
    }
}
