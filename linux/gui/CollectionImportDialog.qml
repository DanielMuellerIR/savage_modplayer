import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property var send
    required property var library
    required property var exchange

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Cancel
    title: "Sammlungsimport prüfen"

    onRejected: send("collectionCancel")

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Label {
            font.bold: true
            text: (exchange.playlists || 0) + " Playlists · " + (exchange.markers || 0) + " Songstellen"
        }
        Label {
            Layout.fillWidth: true
            text: "Titel zuordnen oder ausdrücklich überspringen. Vorhandene Musik wird nicht verändert."
            wrapMode: Text.Wrap
        }
        ScrollView {
            id: exchangeScroll

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                spacing: 10
                width: exchangeScroll.availableWidth

                Repeater {
                    model: exchange.tracks || []

                    RowLayout {
                        required property var modelData

                        Layout.fillWidth: true

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: modelData.name + (modelData.relativePath ? "\n" + modelData.relativePath : "")
                        }
                        FormCombo {
                            Layout.preferredWidth: 400
                            currentIndex: Math.max(0, model.findIndex(t => t.id === modelData.mapped))
                            model: [
                                {
                                    id: "",
                                    name: "Bitte zuordnen…"
                                },
                                {
                                    id: "__skip__",
                                    name: "Überspringen"
                                }
                            ].concat(library.tracks || [])
                            textRole: "name"
                            valueRole: "id"

                            onActivated: send("collectionMap", {
                                track: modelData.id,
                                text: currentValue
                            })
                        }
                    }
                }
                Repeater {
                    model: exchange.conflicts || []

                    RowLayout {
                        required property var modelData

                        Layout.fillWidth: true

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: modelData.name
                        }
                        FormCombo {
                            property var choices: modelData.allowed

                            currentIndex: choices.indexOf(modelData.selected) + 1
                            model: ["Konflikt entscheiden…"].concat(choices.map(c => ({
                                        keepLocal: "Lokal behalten",
                                        useIncoming: "Import übernehmen",
                                        keepBoth: "Beide behalten"
                                    })[c]))

                            onActivated: {
                                if (currentIndex > 0)
                                    send("collectionResolve", {
                                        text: modelData.key,
                                        choice: choices[currentIndex - 1]
                                    });
                            }
                        }
                    }
                }
            }
        }
        FormButton {
            enabled: exchange.ready || false
            text: "Geprüfte Sammlung importieren"

            onClicked: send("collectionApply")
        }
    }
}
