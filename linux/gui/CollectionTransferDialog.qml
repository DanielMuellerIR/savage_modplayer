import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property var send
    required property var saveFile
    required property var importCollection

    anchors.centerIn: parent
    font.pixelSize: 13
    height: 420
    modal: true
    standardButtons: Dialog.Close
    title: "Sammlung übertragen"
    width: 650

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        Label {
            Layout.fillWidth: true
            text: "Playlists, Favoriten, Songstellen und Klangwerte werden übertragen. Musikdateien, Lautstärke, Timer und Warteschlange bleiben lokal."
            wrapMode: Text.Wrap
        }
        FormButton {
            text: "Sammlung exportieren…"

            onClicked: {
                let path = dialog.saveFile("Sammlung exportieren", "Sammlung.savagecollection", "Savage-Sammlung (*.savagecollection)");
                if (path)
                    send("collectionExport", {
                        path: path
                    });
            }
        }
        FormButton {
            text: "Sammlung importieren…"

            onClicked: dialog.importCollection()
        }
        Label {
            Layout.fillWidth: true
            color: secondary
            text: "Vor dem Import werden lokale Titelzuordnung und Konfliktentscheidungen geprüft."
            wrapMode: Text.Wrap
        }
    }
}
