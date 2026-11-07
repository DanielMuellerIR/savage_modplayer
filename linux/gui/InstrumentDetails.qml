import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: detailView

    property color accent: "#5cb3c2"
    property color backdrop: "#050608"
    property var details: ({})
    property color primary: "#eceef0"
    property color secondary: "#9ea8b0"
    property real textScale: 1

    spacing: 20

    Label {
        text: details.index + " · " + (details.name || "")

        font {
            bold: true
            pixelSize: 18 * textScale
        }
    }
    Label {
        color: secondary
        text: "Fadeout: " + (details.fadeout || 0)
    }
    Label {
        color: secondary
        text: "Keine aktivierten Hüllkurven gespeichert."
        visible: !details.volumeEnvelope && !details.panningEnvelope && !details.pitchEnvelope
    }
    Repeater {
        model: ["volumeEnvelope", "panningEnvelope", "pitchEnvelope"]

        ColumnLayout {
            property var envelope: details[modelData]
            required property var modelData

            Layout.fillWidth: true
            visible: !!envelope

            Label {
                font.bold: true
                text: ({
                        volumeEnvelope: "Lautstärke-Hüllkurve",
                        panningEnvelope: "Panning-Hüllkurve",
                        pitchEnvelope: "Tonhöhe / Filter"
                    })[modelData]
            }
            Canvas {
                property var env: parent.envelope

                Layout.fillWidth: true
                Layout.preferredHeight: 150

                onEnvChanged: requestPaint()
                onPaint: {
                    let c = getContext("2d");
                    c.reset();
                    c.fillStyle = backdrop;
                    c.fillRect(0, 0, width, height);
                    if (!env || !(env.points || []).length)
                        return;
                    let points = env.points, maximum = Math.max(1, points[points.length - 1].frame), yMax = 64;
                    function x(t) {
                        return 20 + t / maximum * (width - 40);
                    }
                    function y(v) {
                        return height - 16 - v / yMax * (height - 32);
                    }
                    for (let region of [
                        {
                            enabled: env.loopEnabled,
                            start: env.loopStart,
                            end: env.loopEnd,
                            color: accent
                        },
                        {
                            enabled: env.sustainEnabled,
                            start: env.sustainStart,
                            end: env.sustainEnd,
                            color: "#e7a04b"
                        }
                    ]) {
                        if (region.enabled && points[region.start] && points[region.end]) {
                            c.fillStyle = Qt.alpha(region.color, 0.15);
                            c.fillRect(x(points[region.start].frame), 0, Math.max(2, x(points[region.end].frame) - x(points[region.start].frame)), height);
                        }
                    }
                    c.strokeStyle = accent;
                    c.lineWidth = 1.5;
                    c.beginPath();
                    for (let i = 0; i < points.length; ++i) {
                        if (i === 0)
                            c.moveTo(x(points[i].frame), y(points[i].value));
                        else
                            c.lineTo(x(points[i].frame), y(points[i].value));
                    }
                    c.stroke();
                    c.fillStyle = accent;
                    for (let p of points) {
                        c.beginPath();
                        c.arc(x(p.frame), y(p.value), 3, 0, 2 * Math.PI);
                        c.fill();
                    }
                }
                onWidthChanged: requestPaint()
            }
            FormButton {
                text: pointList.visible ? "Hüllkurvenpunkte ▴" : "Hüllkurvenpunkte ▾"

                onClicked: pointList.visible = !pointList.visible
            }
            ColumnLayout {
                id: pointList

                Layout.fillWidth: true
                visible: false

                Repeater {
                    model: envelope ? envelope.points || [] : []

                    Label {
                        required property var modelData

                        font.family: "monospace"
                        text: "Tick " + modelData.frame + " · Wert " + modelData.value
                    }
                }
            }
            Label {
                color: secondary
                text: envelope ? "Loop: " + (envelope.loopEnabled ? envelope.loopStart + "–" + envelope.loopEnd : "aus") + " · Sustain: " + (envelope.sustainEnabled ? envelope.sustainStart + "–" + envelope.sustainEnd : "aus") + " · Carry: " + (envelope.carryEnabled ? "ein" : "aus") : ""
            }
        }
    }
    Label {
        font.bold: true
        text: "Auto-Vibrato"
        visible: !!details.autoVibrato
    }
    Label {
        Layout.fillWidth: true
        text: "Wellenform: " + ["Sinus", "Rechteck", "Rampe", "Umgekehrte Rampe"][(details.autoVibrato || {}).type || 0] + " · Anlauf: " + ((details.autoVibrato || {}).sweep || 0) + " · Tiefe / Rate: " + ((details.autoVibrato || {}).depth || 0) + " / " + ((details.autoVibrato || {}).rate || 0)
        visible: !!details.autoVibrato
        wrapMode: Text.Wrap
    }
    Label {
        font.bold: true
        text: "Tastenzuordnung"
    }
    Repeater {
        model: details.keyZones || []

        Label {
            required property var modelData

            text: modelData.start + "–" + modelData.end + " → " + modelData.targetStart + "–" + modelData.targetEnd + " · " + (modelData.sample || "kein Sample")
        }
    }
    Repeater {
        model: Object.keys(details.itProperties || {})

        RowLayout {
            required property var modelData

            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                color: secondary
                text: ({
                        newNoteAction: "Neue Note (NNA)",
                        duplicateCheckType: "Duplikatprüfung",
                        duplicateCheckAction: "Duplikataktion",
                        globalVolume: "Globale Instrumentlautstärke",
                        defaultPanning: "Standard-Panning",
                        pitchPanSeparation: "Pitch-Pan-Separation",
                        pitchPanCenter: "Pitch-Pan-Zentrum",
                        randomVolumeVariation: "Zufalls-Lautstärke",
                        randomPanningVariation: "Zufalls-Panning",
                        initialFilterCutoff: "Filter-Cutoff",
                        initialFilterResonance: "Filterresonanz",
                        midiChannel: "MIDI-Kanal",
                        midiProgram: "MIDI-Programm",
                        midiBank: "MIDI-Bank",
                        pluginSlot: "Plugin-Slot",
                        midiPitchWheelDepth: "MIDI-Pitchwheel-Tiefe"
                    })[modelData] || modelData
            }
            Label {
                text: String(details.itProperties[modelData])
            }
        }
    }
}
