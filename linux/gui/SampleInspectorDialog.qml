import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property var inspection
    required property var sample
    required property bool darkTheme
    required property var send
    required property color accent
    required property color primary
    required property color secondary
    property int sampleInstrument: 0
    property string selectedSample: ""

    function requestSample() {
        send("sample", {
            text: selectedSample,
            index: sampleViewer.zoom,
            value: sampleViewer.position,
            focus: sampleViewer.focusRange || null
        });
    }
    function showSample(id, instrument) {
        selectedSample = id;
        sampleInstrument = instrument;
        sampleViewer.zoom = 1;
        sampleViewer.position = 0;
        sampleViewer.focusRange = "";
        send("sample", {
            text: id,
            index: 1
        });
        dialog.open();
    }


    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Sample-Inspektor"

    ScrollView {
        id: sampleScroll

        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            spacing: 20
            width: sampleScroll.availableWidth

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    color: secondary
                    text: "Instrument"
                }
                FormCombo {
                    Layout.fillWidth: true
                    currentIndex: Math.max(0, model.findIndex(i => i.index === sampleInstrument))
                    model: [
                        {
                            index: 0,
                            name: "Alle Samples"
                        }
                    ].concat(inspection.instruments || [])
                    textRole: "name"

                    onActivated: {
                        sampleInstrument = model[currentIndex].index;
                        let i = model[currentIndex], ids = i.sampleIDs || [];
                        let first = (inspection.samples || []).find(v => sampleInstrument === 0 || ids.indexOf(v.id) >= 0);
                        if (first)
                            showSample(first.id, sampleInstrument);
                    }
                }
                Label {
                    color: secondary
                    text: "Sample"
                }
                FormCombo {
                    property var ids: ((inspection.instruments || []).find(i => i.index === sampleInstrument) || {}).sampleIDs || []

                    Layout.fillWidth: true
                    currentIndex: Math.max(0, model.findIndex(v => v.id === selectedSample))
                    displayText: currentIndex >= 0 && model[currentIndex] ? model[currentIndex].number + " · " + (model[currentIndex].name || "—") : "Kein Sample vorhanden"
                    model: (inspection.samples || []).filter(v => sampleInstrument === 0 || ids.indexOf(v.id) >= 0)
                    textRole: "name"

                    onActivated: showSample(model[currentIndex].id, sampleInstrument)
                }
            }
            SampleWaveform {
                id: sampleViewer

                Layout.fillWidth: true
                accent: dialog.accent
                dark: dialog.darkTheme
                primary: dialog.primary
                sample: dialog.sample
                secondary: dialog.secondary

                onRequest: requestSample()
            }
            Repeater {
                model: [["Frames", sample.frames || 0], ["Kanäle", (sample.right || []).length ? "Stereo" : "Mono"], ["Lautstärke", (sample.volume || 0) + "/64"], ["Finetune", sample.finetune || 0]].concat(inspection.formatCode === "xm" ? [["Relative Note", sample.relativeNote || 0]] : []).concat(["it", "s3m"].indexOf(inspection.formatCode) >= 0 ? [[inspection.formatCode === "it" ? "Referenzrate bei C-5" : "Referenzrate bei C-4", ((sample.itProperties || {}).c5Speed || sample.c2spd || 0) + " Hz"]] : [])

                RowLayout {
                    required property var modelData

                    Layout.fillWidth: true

                    Label {
                        text: modelData[0]
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Label {
                        text: modelData[1]
                    }
                }
            }
            Label {
                color: secondary
                text: sampleInstrument ? "Tastenzuordnung" : "Instrument wählen, um die Tastenzuordnung zu sehen."
            }
            Repeater {
                model: sampleInstrument ? ((inspection.instruments || []).find(i => i.index === sampleInstrument) || {}).keyZones || [] : []

                Label {
                    required property var modelData

                    text: modelData.start + "–" + modelData.end + " → " + modelData.targetStart + "–" + modelData.targetEnd + " · " + modelData.sample
                }
            }
        }
    }
}
