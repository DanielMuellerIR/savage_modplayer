import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property real fontScale
    required property bool darkTheme
    required property var preferences
    required property var option
    required property var updates
    required property var chooseFolder

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Einstellungen"
    objectName: "settingsDialog"

    ScrollView {
        id: settingsScroll
        objectName: "settingsScroll"
        anchors.fill: parent
        implicitHeight: settingsContent.implicitHeight
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: settingsContent
            width: settingsScroll.availableWidth
            spacing: 16

            GroupBox {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 8
                    width: parent.width

                    Label {
                        font.bold: true
                        text: "Autoplay-Ordner:"
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: preferences.autoplayFolder || "Nicht gesetzt"
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        FormButton {
                            text: "Auswählen…"

                            onClicked: {
                                let p = dialog.chooseFolder("Autoplay-Ordner wählen");
                                if (p)
                                    option("autoplayFolder", p);
                            }
                        }
                        FormButton {
                            text: "Entfernen"
                            visible: !!preferences.autoplayFolder

                            onClicked: option("autoplayFolder", "")
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 11 * dialog.fontScale
                        text: "Aus diesem Ordner (inklusive Unterordnern und Zip-/7z-Archiven) füllt der Player beim Start die Playlist und beginnt zu spielen. Änderungen wirken ab dem nächsten Start."
                        wrapMode: Text.Wrap
                    }
                }
            }
            GroupBox {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 8
                    width: parent.width

                    Label {
                        text: "Bildrate der Visualisierungen:"
                    }
                    FormCombo {
                        Layout.fillWidth: true
                        currentIndex: model.indexOf(preferences.visualizerHz || 60)
                        displayText: currentValue === 60 ? "60 Bilder/s (Standard)" : currentValue === 15 ? "15 Bilder/s (Sparmodus)" : currentValue + " Bilder/s"
                        model: [60, 30, 24, 15, 10]

                        onActivated: option("visualizerHz", model[currentIndex])
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 11 * dialog.fontScale
                        text: "60 Bilder pro Sekunde sorgen für flüssige Pegel und Oszilloskope; der Sparmodus verwendet 15 Bilder pro Sekunde. Die Änderung wirkt sofort. Verkleinere das Fenster, um die Visualizer ganz auszublenden: Erfassung, Übertragung und Zeichnen entfallen dann. Nur Transport und Spielzeit werden weiter aktualisiert. Der Klang bleibt unverändert."
                        wrapMode: Text.Wrap
                    }
                }
            }
            GroupBox {
                Layout.fillWidth: true
                title: "Updates"

                ColumnLayout {
                    spacing: 8
                    width: parent.width

                    PlayerCheckBox {
                        baseFontSize: 13
                        dark: dialog.darkTheme
                        objectName: "automaticUpdateChecks"
                        checked: updates.automaticallyChecks
                        onClicked: updates.automaticallyChecks = checked
                        text: "Automatisch nach Updates suchen"
                        textScale: 1
                    }
                    FormButton {
                        objectName: "checkUpdatesButton"
                        enabled: !updates.busy
                        onClicked: updates.check()
                        text: "Nach Updates suchen…"
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 11 * dialog.fontScale
                        text: "Der Player prüft höchstens einmal täglich auf neue Versionen. Nach Bestätigung lädt er das signierte Paket von GitHub und installiert es für den nächsten Start. Die Wiedergabe läuft weiter. Es werden keine Musikdateien oder Bibliotheksdaten übertragen."
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
