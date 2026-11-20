import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property bool darkTheme
    required property var library
    required property var send
    required property var indexStatus
    required property var changeQuery

    property var failures: dialog.records.filter(t => !!t.metadata.failure)
    property string filterID: ""
    property var records: dialog.tracks.filter(t => !!t.metadata)
    property var tracks: library.tracks || []

    function formatCount(format) {
        return dialog.records.filter(t => {
            let f = (t.metadata.metadata || {}).format || "";
            return (["protracker", "soundtracker", "multichannel"].indexOf(f) >= 0 ? "MOD" : f.toUpperCase()) === format;
        }).length;
    }

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Anzeige und Filter"

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label {
            Layout.fillWidth: true
            color: secondary
            text: "Die Anzeige ersetzt die laufende Wiedergabeauswahl erst mit „Diese Ergebnisse abspielen“."
            wrapMode: Text.Wrap
        }
        SplitView {
            Layout.fillHeight: true
            Layout.fillWidth: true

            ColumnLayout {
                SplitView.preferredWidth: 210

                Label {
                    font.bold: true
                    text: "Gespeicherte Filter"
                }
                ListView {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    clip: true
                    model: library.savedFilters || []

                    delegate: ItemDelegate {
                        required property var modelData

                        highlighted: dialog.filterID === modelData.id
                        text: modelData.name
                        width: ListView.view.width

                        onClicked: {
                            dialog.filterID = modelData.id;
                            send("filterOpen", {
                                text: modelData.id
                            });
                        }
                    }
                }
                FormButton {
                    enabled: !!dialog.filterID
                    text: "Ausgewählten Filter löschen"

                    onClicked: {
                        send("filterDelete", {
                            text: dialog.filterID
                        });
                        dialog.filterID = "";
                    }
                }
            }
            ColumnLayout {
                Layout.leftMargin: 12
                SplitView.fillWidth: true
                spacing: 8

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "Datei, Titel oder Instrument"
                    text: (library.query || {}).search || ""

                    onTextEdited: changeQuery("search", text)
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: "Format"
                    }
                    FormCombo {
                        currentIndex: Math.max(0, model.indexOf((library.query || {}).format || "Alle"))
                        model: ["Alle", "MOD", "S3M", "XM", "IT"]

                        onActivated: changeQuery("format", currentIndex === 0 ? null : currentText)
                    }
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: "Mindestens Kanäle"
                    }
                    SpinBox {
                        from: 0
                        to: 64
                        value: (library.query || {}).minimumChannels || 0

                        onValueModified: changeQuery("minimumChannels", value)
                    }
                }
                PlayerCheckBox {
                    baseFontSize: 13
                    checked: (library.query || {}).favoritesOnly || false
                    dark: dialog.darkTheme
                    text: "Nur Favoriten"
                    textScale: 1

                    onClicked: changeQuery("favoritesOnly", checked)
                }
                PlayerCheckBox {
                    baseFontSize: 13
                    checked: (library.query || {}).unheardOnly || false
                    dark: dialog.darkTheme
                    text: "Nur ungehörte Titel"
                    textScale: 1

                    onClicked: changeQuery("unheardOnly", checked)
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: "Neu hinzugefügt"
                    }
                    FormCombo {
                        currentIndex: [null, 7, 30].indexOf((library.query || {}).addedWithinDays || null)
                        model: ["Alle", "Letzte 7 Tage", "Letzte 30 Tage"]

                        onActivated: changeQuery("addedWithinDays", [null, 7, 30][currentIndex])
                    }
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: "Sortierung"
                    }
                    FormCombo {
                        currentIndex: ["sourceOrder", "filename", "title", "format", "channels", "duration", "newest"].indexOf((library.query || {}).sort || "sourceOrder")
                        model: ["Ordnerreihenfolge", "Dateiname", "Interner Modultitel", "Format", "Kanalzahl", "Spieldauer", "Neueste zuerst"]

                        onActivated: changeQuery("sort", ["sourceOrder", "filename", "title", "format", "channels", "duration", "newest"][currentIndex])
                    }
                }
                PlayerCheckBox {
                    baseFontSize: 13
                    checked: (library.query || {}).reversed || false
                    dark: dialog.darkTheme
                    text: "Reihenfolge umkehren"
                    textScale: 1

                    onClicked: changeQuery("reversed", checked)
                }
                Item {
                    Layout.fillHeight: true
                }
            }
        }
        RowLayout {
            TextField {
                id: filterName

                Layout.fillWidth: true
                placeholderText: "Name des Filters"
            }
            FormButton {
                enabled: filterName.text.trim().length > 0
                text: "Aktuellen Filter speichern"

                onClicked: {
                    send("filterSave", {
                        text: filterName.text
                    });
                    filterName.clear();
                }
            }
        }
        GroupBox {
            Layout.fillWidth: true
            title: "Sammlung"

            ColumnLayout {
                spacing: 5
                width: parent.width

                Label {
                    text: "Indiziert: " + dialog.records.length + " von " + dialog.tracks.length + " · Fehler: " + dialog.failures.length
                }
                Label {
                    color: secondary
                    text: ["MOD", "S3M", "XM", "IT"].map(f => f + ": " + dialog.formatCount(f)).join(" · ")
                }
                Label {
                    Layout.fillWidth: true
                    color: secondary
                    text: (indexStatus.warnings || []).map(w => ({
                                capacityLimited: "Indexgrenze erreicht; einige Metadaten fehlen.",
                                cacheWriteFailed: "Metadatenindex konnte nicht gesichert werden.",
                                invalidSource: "Einige Quellen konnten nicht indiziert werden."
                            })[w] || "").filter(v => v).join("\n")
                    visible: !!text
                    wrapMode: Text.Wrap
                }
                FormCombo {
                    Layout.fillWidth: true
                    model: dialog.failures.map(t => t.name + " · " + (t.metadata.detail || t.metadata.failure))
                    visible: dialog.failures.length > 0
                }
                ProgressBar {
                    Layout.fillWidth: true
                    value: (indexStatus.completed || 0) / Math.max(1, indexStatus.total || 1)
                    visible: indexStatus.active || false
                }
                FormButton {
                    text: "Indizierung abbrechen"
                    visible: indexStatus.active || false

                    onClicked: send("indexCancel")
                }
            }
        }
        RowLayout {
            FormButton {
                text: "Anzeige zurücksetzen"

                onClicked: send("query", {
                    query: {
                        search: "",
                        minimumChannels: 0,
                        favoritesOnly: false,
                        unheardOnly: false,
                        sort: "sourceOrder",
                        reversed: false
                    }
                })
            }
            FormButton {
                text: "Metadaten erneut prüfen"

                onClicked: send("indexRefresh")
            }
        }
    }
}
