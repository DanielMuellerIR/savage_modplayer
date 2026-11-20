import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property var send
    required property var entries

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Als Nächstes"
    width: 650

    ColumnLayout {
        anchors.fill: parent

        Label {
            Layout.fillWidth: true
            color: secondary
            text: "Eingereihte Titel haben Vorrang. Danach setzt sich die bisherige Playlist fort."
            wrapMode: Text.Wrap
        }
        ListView {
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            model: dialog.entries

            delegate: RowLayout {
                required property var modelData

                height: 40
                width: ListView.view.width

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: modelData.name
                }
                FormButton {
                    text: "↑"

                    onClicked: send("queueMove", {
                        text: modelData.id,
                        index: -1
                    })
                }
                FormButton {
                    text: "↓"

                    onClicked: send("queueMove", {
                        text: modelData.id,
                        index: 1
                    })
                }
                FormButton {
                    text: "Entfernen"

                    onClicked: send("queueRemove", {
                        text: modelData.id
                    })
                }
            }
        }
        FormButton {
            text: "Warteschlange leeren"

            onClicked: send("queueClear")
        }
    }
}
