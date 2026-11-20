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
    required property bool darkTheme
    required property var library
    required property var preferences

    property var items: []
    property var selected: []

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Stapel-Export"

    onClosed: if (session.exporting)
        send("exportCancel")
    onOpened: {
        items = (library.tracks || []).filter(t => (library.visible || []).indexOf(t.id) >= 0);
        selected = items.map(t => t.id);
        session.exportReport = {};
        session.exportResult = "";
        session.exportProgress = 0;
        let o = preferences.batchSettings || {};
        batchKind.currentIndex = o.stems ? 1 : 0;
        batchConflict.currentIndex = o.rename ? 1 : 0;
        batchDuration.currentIndex = Math.max(0, [60, 180, 300, 600].indexOf(o.seconds || 300));
        batchPAL.currentIndex = o.pal === false ? 1 : 0;
        batchInterpolation.checked = o.interpolation !== false;
        batchSeparation.value = o.separation === undefined ? .8 : o.separation;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        ScrollView {
            id: batchScroll

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                spacing: 14
                width: batchScroll.availableWidth

                Label {
                    Layout.fillWidth: true
                    color: secondary
                    text: "Die Titelliste ist beim Öffnen festgehalten. Jeder Titel beginnt am Songanfang; die normale Wiedergabe kann weiterlaufen."
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: dialog.selected.length + " von " + dialog.items.length + " Titeln ausgewählt"
                    }
                    FormButton {
                        text: "Alle"

                        onClicked: dialog.selected = dialog.items.map(t => t.id)
                    }
                    FormButton {
                        text: "Keine"

                        onClicked: dialog.selected = []
                    }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 160
                    clip: true
                    model: dialog.items

                    delegate: CheckDelegate {
                        required property var modelData

                        checked: dialog.selected.indexOf(modelData.id) >= 0
                        enabled: !session.exporting
                        text: modelData.name
                        width: ListView.view.width

                        onClicked: {
                            let a = dialog.selected.slice(), i = a.indexOf(modelData.id);
                            if (checked && i < 0)
                                a.push(modelData.id);
                            else if (!checked && i >= 0)
                                a.splice(i, 1);
                            dialog.selected = a;
                        }
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    enabled: !session.exporting

                    Label {
                        text: "Ausgabe"
                    }
                    FormCombo {
                        id: batchKind

                        Layout.fillWidth: true
                        model: ["Stereo-Mix", "Kanalspuren und Referenzmix"]
                    }
                    Label {
                        text: "Vorhandene Ziele"
                    }
                    FormCombo {
                        id: batchConflict

                        Layout.fillWidth: true
                        model: ["Überspringen", "Beide behalten (neuer Name)"]
                    }
                    Label {
                        text: "Dauer je Titel"
                    }
                    FormCombo {
                        id: batchDuration

                        Layout.fillWidth: true
                        currentIndex: 2
                        displayText: currentValue / 60 + " Minuten"
                        model: [60, 180, 300, 600]
                    }
                    Label {
                        text: "MOD-Clock"
                    }
                    FormCombo {
                        id: batchPAL

                        model: ["PAL", "NTSC"]
                    }
                    Label {
                        text: "Sample-Interpolation"
                    }
                    PlayerCheckBox {
                        id: batchInterpolation

                        baseFontSize: 13
                        checked: true
                        dark: dialog.darkTheme
                        textScale: 1
                    }
                    Label {
                        text: "Separation: " + Math.round(batchSeparation.value * 100) + " %"
                    }
                    PlayerSlider {
                        id: batchSeparation

                        Layout.fillWidth: true
                        dark: dialog.darkTheme
                        from: 0
                        to: 1
                        value: .8
                    }
                }
                Label {
                    Layout.fillWidth: true
                    color: secondary
                    font.pixelSize: 11 * dialog.fontScale
                    text: "Stereo-Float32 mit 44.100 Hz. Kanalspuren verwenden einen gemeinsamen Pegelfaktor je Titel. Mute/Solo aus dem Player, Mixerlautstärke und externer LED-Ausgabefilter werden nicht übernommen."
                    wrapMode: Text.Wrap
                }
            }
        }
        ProgressBar {
            Layout.fillWidth: true
            value: session.exportProgress
            visible: session.exporting
        }
        Label {
            Layout.fillWidth: true
            text: (session.exportReport.wasCancelled ? "Abgebrochen: " : "Stapel beendet: ") + (session.exportReport.results || []).filter(r => r.status === "exported").length + " exportiert, " + (session.exportReport.results || []).filter(r => r.status === "skipped").length + " übersprungen, " + (session.exportReport.results || []).filter(r => r.status === "failed").length + " fehlgeschlagen."
            visible: !!session.exportReport.results
            wrapMode: Text.Wrap
        }
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            clip: true
            model: session.exportReport.results || []
            visible: !!session.exportReport.results

            delegate: Label {
                required property var modelData

                text: modelData.sourceName + ": " + modelData.status + (modelData.detail ? " – " + modelData.detail : "")
                width: ListView.view.width
                wrapMode: Text.Wrap
            }
        }
        RowLayout {
            FormButton {
                text: "Abbrechen"
                visible: session.exporting

                onClicked: send("exportCancel")
            }
            Item {
                Layout.fillWidth: true
            }
            FormButton {
                text: "Im Dateimanager zeigen"
                visible: !!session.exportResult && !session.exporting

                onClicked: fileDialogs.reveal(session.exportResult)
            }
            FormButton {
                enabled: !session.exporting && dialog.selected.length > 0 && dialog.selected.length <= 10000
                text: "Ziel wählen …"

                onClicked: {
                    let path = fileDialogs.chooseFolder("Stapelexport: Zielordner");
                    if (path) {
                        session.exporting = true;
                        send("batchExport", {
                            path: path,
                            ids: dialog.selected,
                            stems: batchKind.currentIndex === 1,
                            rename: batchConflict.currentIndex === 1,
                            seconds: batchDuration.currentValue,
                            pal: batchPAL.currentIndex === 0,
                            interpolation: batchInterpolation.checked,
                            separation: batchSeparation.value
                        });
                    }
                }
            }
        }
    }
}
