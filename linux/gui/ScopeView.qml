import QtQuick

Canvas {
    id: canvas

    property color accent: "#5cb3c2"
    property bool dark: true
    property bool master: false
    property var samples: []

    onAccentChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        let c = getContext("2d");
        c.reset();
        c.fillStyle = dark ? Qt.rgba(0, 0, 0, master ? .3 : .2) : "white";
        let r = master ? 4 : 3;
        function outline() {
            c.beginPath();
            c.moveTo(r, 0);
            c.lineTo(width - r, 0);
            c.quadraticCurveTo(width, 0, width, r);
            c.lineTo(width, height - r);
            c.quadraticCurveTo(width, height, width - r, height);
            c.lineTo(r, height);
            c.quadraticCurveTo(0, height, 0, height - r);
            c.lineTo(0, r);
            c.quadraticCurveTo(0, 0, r, 0);
            c.closePath();
        }
        outline();
        c.fill();
        c.strokeStyle = accent;
        c.lineWidth = master ? 1.5 : 1.2;
        c.beginPath();
        let count = samples ? samples.length : 0;
        if (count < 2) {
            c.moveTo(0, height / 2);
            c.lineTo(width, height / 2);
        } else
            for (let i = 0; i < count; ++i) {
                let x = i * width / (count - 1), y = height / 2 - Math.max(-1, Math.min(1, samples[i])) * height * 0.5;
                if (i === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
        c.stroke();
        if (master) {
            c.strokeStyle = dark ? Qt.alpha(accent, .15) : Qt.alpha("#576170", .35);
            c.lineWidth = 1;
            outline();
            c.stroke();
        }
    }
    onSamplesChanged: requestPaint()
    onWidthChanged: requestPaint()
}
