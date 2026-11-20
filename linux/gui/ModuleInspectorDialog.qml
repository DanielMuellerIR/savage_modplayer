import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color accent
    required property color backdrop
    required property color primary
    required property color secondary
    required property var send
    required property real fontScale
    required property var inspection
    required property var instrumentDetails

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Modul-Inspektor"

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Label {
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            text: inspection.title || ""

            font {
                bold: true
                pixelSize: 20 * dialog.fontScale
            }
        }
        TabBar {
            id: inspectorTabs

            Layout.fillWidth: true

            TabButton {
                text: "Übersicht"
            }
            TabButton {
                text: "Instrumente"
            }
            TabButton {
                text: "Effekte"
            }
        }
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: inspectorTabs.currentIndex

            ScrollView {
                id: overviewScroll

                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    spacing: 8
                    width: overviewScroll.availableWidth

                    Repeater {
                        model: [["Format", inspection.format || ""], ["Songpositionen / Patterns", (inspection.orders || []).length + " / " + (inspection.patternCount || 0)], ["Kanalplätze / benutzt", (inspection.channels || 0) + " / " + (inspection.usedChannels || 0)], ["Instrumente / Samples", (inspection.instrumentCount || 0) + " / " + (inspection.sampleCount || 0)], ["Starttempo / Ticks pro Zeile", (inspection.initialTempo || 0) + " BPM / " + (inspection.initialSpeed || 0)], ["Startlautstärke", (inspection.initialVolume || 0) + "/" + (inspection.volumeScale || 64)], ["Frequenzmodell", inspection.linearFrequency ? "Linear" : "Amiga"]]

                        RowLayout {
                            required property var modelData

                            Layout.fillWidth: true

                            Label {
                                Layout.preferredWidth: 220
                                color: secondary
                                text: modelData[0]
                            }
                            Label {
                                Layout.fillWidth: true
                                text: modelData[1]
                            }
                        }
                    }
                    GroupBox {
                        Layout.fillWidth: true
                        title: "Herkunft"

                        ColumnLayout {
                            spacing: 8
                            width: parent.width

                            Label {
                                Layout.fillWidth: true
                                color: secondary
                                text: inspection.tracker ? "Tracker: " + inspection.tracker : "Trackerherkunft ist im geladenen Modell nicht enthalten."
                                wrapMode: Text.Wrap
                            }
                            Label {
                                color: secondary
                                text: inspection.artist ? "Künstlerfeld: " + inspection.artist : "Kein explizites Künstlerfeld vorhanden."
                            }
                            Repeater {
                                model: Object.keys(inspection.origin || {})

                                RowLayout {
                                    required property var modelData

                                    Layout.fillWidth: true

                                    Label {
                                        text: modelData
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: inspection.origin[modelData]
                                    }
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                color: secondary
                                font.pixelSize: 11 * dialog.fontScale
                                text: "Namen und Textzeilen werden nicht als Künstlerangaben interpretiert."
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                    Label {
                        font.bold: true
                        text: "Songpositionen und Pattern-Aufbau"
                    }
                    Repeater {
                        model: inspection.orders || []

                        RowLayout {
                            required property var modelData

                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                text: "Position " + modelData.position + " · Pattern " + modelData.pattern + " · " + modelData.rows + " Zeilen"
                            }
                            FormButton {
                                text: "Springen"

                                onClicked: send("seek", {
                                    index: modelData.position
                                })
                            }
                        }
                    }
                    Repeater {
                        model: inspection.patternRows || []

                        RowLayout {
                            required property var modelData

                            Layout.fillWidth: true

                            Label {
                                text: "Pattern " + modelData.index
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Label {
                                text: modelData.rows + " Zeilen · " + modelData.uses + "× in der Liste"
                            }
                        }
                    }
                    Label {
                        font.bold: true
                        text: "Kompatibilität"
                    }
                    Label {
                        color: secondary
                        text: !(inspection.warnings || []).length ? "Keine erfassten Kompatibilitätswarnungen." : ""
                        visible: !!text
                    }
                    Repeater {
                        model: inspection.findings || []

                        ColumnLayout {
                            required property var modelData

                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                font.bold: true
                                text: modelData.identifier + " · " + ({
                                        supported: "Unterstützt",
                                        irrelevantForPCM: "Keine PCM-Wirkung",
                                        metadataOnly: "Nur Metadaten",
                                        midiOrPluginOnly: "Externer MIDI-/Pluginpfad",
                                        unsupported: "Nicht unterstützt",
                                        differentPlayback: "Abweichende Wiedergabe"
                                    })[modelData.support]
                                wrapMode: Text.Wrap
                            }
                            Label {
                                color: secondary
                                text: modelData.used ? "Verwendet" : "Gespeichert, nicht verwendet"
                            }
                            Label {
                                Layout.fillWidth: true
                                text: modelData.detail
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        color: "#cf922b"
                        text: (inspection.warnings || []).join("\n")
                        wrapMode: Text.Wrap
                    }
                }
            }
            ScrollView {
                id: instrumentScroll

                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    spacing: 20
                    width: instrumentScroll.availableWidth

                    Label {
                        color: secondary
                        text: "Instrument"
                    }
                    FormCombo {
                        Layout.fillWidth: true
                        displayText: currentIndex >= 0 && model[currentIndex] ? model[currentIndex].index + " · " + model[currentIndex].name : "Keine Instrumentplätze vorhanden."
                        model: inspection.instruments || []
                        textRole: "name"

                        onActivated: send("instrument", {
                            index: model[currentIndex].index
                        })
                    }
                    InstrumentDetails {
                        Layout.fillWidth: true
                        accent: dialog.accent
                        backdrop: dialog.backdrop
                        details: instrumentDetails
                        primary: dialog.primary
                        secondary: dialog.secondary
                        textScale: 1
                    }
                }
            }
            ListView {
                clip: true
                model: inspection.effects || []

                delegate: ColumnLayout {
                    required property var modelData

                    spacing: 4
                    width: ListView.view.width

                    Label {
                        font.bold: true
                        text: modelData.code + " · " + modelData.name + " · " + modelData.count + "×"
                    }
                    Label {
                        color: secondary
                        text: modelData.volumeColumn ? "Volume-Spalte" : "Effektspalte"
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: modelData.detail
                        wrapMode: Text.Wrap
                    }
                    Label {
                        color: "#e7a04b"
                        text: "Derzeit ignoriert"
                        visible: !modelData.implemented
                    }
                    Label {
                        Layout.fillWidth: true
                        font.family: "monospace"
                        text: "Übernommene Parameter: " + (modelData.parameters || []).slice(0, 32).map(v => modelData.volumeColumn && inspection.formatCode !== "xm" ? v : v.toString(16).toUpperCase().padStart(2, "0")).join(" ")
                        wrapMode: Text.Wrap
                    }
                    Item {
                        height: 10
                    }
                }
            }
        }
    }
}
