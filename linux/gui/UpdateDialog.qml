import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property real fontScale
    required property var updates
    objectName: "updateDialog"
    anchors.centerIn: parent
    modal: true
    title: "Softwareupdate"
    font.pixelSize: 13 * dialog.fontScale
    closePolicy: updates.busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    ScrollView {
        id: updateScroll
        anchors.fill: parent
        implicitHeight: updateContent.implicitHeight
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: updateContent
            width: updateScroll.availableWidth
            spacing: 14
            Label {
                Layout.fillWidth: true
                text: updates.status
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            ProgressBar {
                Layout.fillWidth: true
                visible: updates.busy
                value: updates.progress
                indeterminate: updates.progress <= 0
            }
            Label {
                Layout.fillWidth: true
                visible: !!updates.notes
                text: updates.notes
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Label {
                Layout.fillWidth: true
                text: "Updateprüfung: GitHub Pages · Download nach Bestätigung: GitHub Releases. Signatur, Größe und SHA-256 werden geprüft."
                color: secondary
                font.pixelSize: 11 * dialog.fontScale
                wrapMode: Text.Wrap
            }
        }
    }
    footer: DialogButtonBox {
        FormButton {
            objectName: "cancelUpdateButton"
            text: updates.busy ? "Abbrechen" : "Schließen"
            onClicked: updates.busy ? updates.cancel() : dialog.close()
        }
        FormButton {
            objectName: "installUpdateButton"
            text: "Update installieren"
            visible: !!updates.offeredVersion && !updates.installed
            enabled: updates.canInstall && !updates.busy
            onClicked: updates.install()
        }
    }
}
