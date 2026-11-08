import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: view

    property color accent: "#5cb3c2"
    property bool dark: true
    property string focusRange: ""
    property real position: 0
    property color primary: "#eceef0"
    property var sample: ({})
    property color secondary: "#9ea8b0"
    property int zoom: 1

    signal request

    spacing: 12

    Canvas {
        id: graph

        property var data: view.sample

        Accessible.description: (sample.start || 0) + " – " + (sample.end || 0)
        Accessible.name: "Sample-Wellenform"
        Layout.fillWidth: true
        Layout.preferredHeight: (sample.right || []).length ? 240 : 180

        onDataChanged: requestPaint()
        onPaint: {
            let c = getContext("2d");
            c.reset();
            c.fillStyle = dark ? Qt.rgba(1, 1, 1, .07) : Qt.rgba(0, 0, 0, .07);
            c.fillRect(0, 0, width, height);
            let a = sample.start || 0, b = Math.max(a + 1, sample.end || 1), span = b - a, channels = [sample.left || []];
            if ((sample.right || []).length)
                channels.push(sample.right);
            for (let region of [
                {
                    start: sample.loopStart || 0,
                    length: sample.loopLength || 0,
                    color: accent,
                    type: sample.loopType
                },
                {
                    start: (sample.sustainLoop || {}).start || 0,
                    length: (sample.sustainLoop || {}).length || 0,
                    color: "#e7a04b",
                    type: (sample.sustainLoop || {}).type
                }
            ]) {
                if (region.length > 0 && region.type !== "none") {
                    let x = Math.max(0, (region.start - a) / span * width), end = Math.min(width, (region.start + region.length - a) / span * width);
                    if (end > x) {
                        c.fillStyle = Qt.alpha(region.color, .13);
                        c.fillRect(x, 0, end - x, height);
                        c.strokeStyle = region.color;
                        c.beginPath();
                        c.moveTo(x, 0);
                        c.lineTo(x, height);
                        c.moveTo(end, 0);
                        c.lineTo(end, height);
                        c.stroke();
                    }
                }
            }
            for (let ch = 0; ch < channels.length; ++ch) {
                let values = channels[ch], h = height / channels.length, center = h * (ch + .5);
                c.strokeStyle = Qt.alpha(secondary, .25);
                c.beginPath();
                c.moveTo(0, center);
                c.lineTo(width, center);
                c.stroke();
                c.strokeStyle = accent;
                c.lineWidth = 1;
                c.beginPath();
                for (let i = 0; i < values.length; ++i) {
                    let x = i * width / values.length;
                    c.moveTo(x, center - values[i][0] * h * .4);
                    c.lineTo(x, center - values[i][1] * h * .4);
                }
                c.stroke();
                c.fillStyle = secondary;
                c.font = "10px sans-serif";
                c.fillText(channels.length === 1 ? "Mono" : ch === 0 ? "Links" : "Rechts", 8, h * ch + 15);
            }
        }
        onWidthChanged: requestPaint()
    }
    Label {
        color: secondary
        text: "Frames   " + (sample.start || 0) + " – " + (sample.end || 0) + " / " + (sample.frames || 0)
    }
    Label {
        color: secondary
        text: "Zoom"
    }
    FormCombo {
        Layout.fillWidth: true
        currentIndex: model.indexOf(zoom)
        displayText: focusRange ? "Bereich" : zoom + "×"
        model: [1, 2, 4, 8, 16, 32, 64]

        onActivated: {
            zoom = model[currentIndex];
            focusRange = "";
            view.request();
        }
    }
    RowLayout {
        Label {
            color: secondary
            text: "Position"
        }
        PlayerSlider {
            objectName: "samplePositionSlider"
            Layout.fillWidth: true
            dark: view.dark
            enabled: sample.end - sample.start < sample.frames
            from: 0
            to: 1
            value: view.position

            onMoved: {
                view.position = value;
                view.request();
            }
        }
    }
    RowLayout {
        FormButton {
            text: "Gesamt"

            onClicked: {
                zoom = 1;
                position = 0;
                focusRange = "";
                view.request();
            }
        }
        FormButton {
            text: "Loop"
            visible: (sample.loopLength || 0) > 0 && sample.loopType !== "none"

            onClicked: {
                position = 0;
                focusRange = "loop";
                view.request();
            }
        }
        FormButton {
            text: "Sustain"
            visible: !!sample.sustainLoop && (sample.sustainLoop.length || 0) > 0 && sample.sustainLoop.type !== "none"

            onClicked: {
                position = 0;
                focusRange = "sustain";
                view.request();
            }
        }
    }
    Label {
        Layout.fillWidth: true
        color: accent
        text: "Loop: " + (sample.loopType || "none") + " · " + (sample.loopStart || 0) + " + " + (sample.loopLength || 0)
        wrapMode: Text.Wrap
    }
    Label {
        Layout.fillWidth: true
        color: "#e7a04b"
        text: "Sustain: " + ((sample.sustainLoop || {}).type || "none") + " · " + ((sample.sustainLoop || {}).start || 0) + " + " + ((sample.sustainLoop || {}).length || 0)
        visible: !!sample.sustainLoop
        wrapMode: Text.Wrap
    }
}
