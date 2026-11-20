import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property var send
    required property real fontScale
    required property var session
    required property var fileDialogs
    required property var moduleInfo

    property bool validFolder: exportFolder.text.trim().length > 0 && exportFolder.text !== "." && exportFolder.text !== ".." && !/[\/\x00:]/.test(exportFolder.text)

    anchors.centerIn: parent
    font.pixelSize: 11 * dialog.fontScale
    modal: true
    title: "OFFLINE-WAV-EXPORT"

    onOpened: {
        session.exportProgress = 0;
        session.exportResult = "";
        send("prepareExport");
        exportFolder.text = (moduleInfo.title || "Modul").replace(/[\/:]/g, "_") + "-Kanalspuren";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        Label {
            Layout.fillWidth: true
            text: session.exportTitle
            wrapMode: Text.Wrap
        }
        TabBar {
            id: exportKind

            Layout.fillWidth: true

            TabButton {
                text: "Stereo-Mix"
            }
            TabButton {
                text: "Kanalspuren"
            }
        }
        Label {
            Layout.fillWidth: true
            text: exportKind.currentIndex ? "Eine Stereo-Float32-WAV je logischem Kanal, dazu Referenzmix und Begleitdatei. Alle Dateien beginnen gemeinsam und verwenden denselben Pegelfaktor." : "Exportiert den gesamten Titel offline in eine Stereo-WAV-Datei."
            wrapMode: Text.Wrap
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: exportKind.currentIndex === 1

            Label {
                text: "Neuer Ordnername"
            }
            TextField {
                id: exportFolder

                Layout.fillWidth: true
                placeholderText: "Kanalspuren"
            }
        }
        Label {
            Layout.fillWidth: true
            color: secondary
            text: "Übernimmt Mute/Solo, Clock, Interpolation und Separation. Limiter, Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten."
            visible: exportKind.currentIndex === 1
            wrapMode: Text.Wrap
        }
        RowLayout {
            Label {
                text: "Dauer begrenzen:"
            }
            FormCombo {
                id: exportSeconds

                Layout.fillWidth: true
                currentIndex: 1
                displayText: currentValue / 60 + " Minuten"
                model: [60, 180, 300, 600]
            }
        }
        ProgressBar {
            Layout.fillWidth: true
            value: session.exportProgress
            visible: session.exporting || session.exportProgress > 0
        }
        Label {
            Layout.fillWidth: true
            text: session.exportResult ? "Erfolgreich gesichert!" : ""
            visible: !!session.exportResult
            wrapMode: Text.Wrap
        }
        RowLayout {
            FormButton {
                text: session.exporting ? "Abbrechen" : "Schließen"

                onClicked: {
                    if (session.exporting)
                        send("exportCancel");
                    else
                        dialog.close();
                }
            }
            Item {
                Layout.fillWidth: true
            }
            FormButton {
                text: "Ordner zeigen"
                visible: !!session.exportResult

                onClicked: fileDialogs.reveal(session.exportResult)
            }
            FormButton {
                enabled: !session.exporting && (exportKind.currentIndex === 0 || dialog.validFolder)
                text: "Ziel wählen …"

                onClicked: {
                    let path = exportKind.currentIndex === 0 ? fileDialogs.saveFile("Song als WAV exportieren", session.exportTitle.replace(/[\/:]/g, "_") + ".wav", "WAV (*.wav)", true) : fileDialogs.chooseFolder("Zielverzeichnis für Kanalspuren");
                    if (path) {
                        if (exportKind.currentIndex === 1)
                            path += "/" + exportFolder.text.trim();
                        session.exporting = true;
                        send("export", {
                            path: path,
                            kind: exportKind.currentIndex ? "stems" : "mix",
                            overwrite: exportKind.currentIndex === 0 && fileDialogs.overwriteApproved(path),
                            seconds: exportSeconds.currentValue
                        });
                    }
                }
            }
        }
    }
}
