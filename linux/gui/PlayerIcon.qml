import QtQuick

Canvas {
    id: icon

    property color accent: "#5cb3c2"
    property real discAngle: 0
    property color ground: "#050608"
    property color ink: "#9ea8b0"
    property string name: ""
    property bool running: false

    onAccentChanged: requestPaint()
    onHeightChanged: requestPaint()
    onInkChanged: requestPaint()
    onNameChanged: requestPaint()
    onPaint: {
        let c = getContext("2d");
        c.reset();
        c.translate(width / 2, height / 2);
        let z = Math.min(width, height) / 24;
        c.scale(z, z);
        c.strokeStyle = ink;
        c.fillStyle = ink;
        c.lineWidth = 1.6;
        c.lineCap = "round";
        c.lineJoin = "round";
        function triangle(x, direction) {
            c.beginPath();
            c.moveTo(x - direction * 3, -5);
            c.lineTo(x + direction * 4, 0);
            c.lineTo(x - direction * 3, 5);
            c.closePath();
            c.fill();
        }
        if (name === "download") {
            c.beginPath();
            c.moveTo(0, -7);
            c.lineTo(0, 3);
            c.moveTo(-4, -1);
            c.lineTo(0, 3);
            c.lineTo(4, -1);
            c.moveTo(-6, 4);
            c.lineTo(-6, 7);
            c.lineTo(6, 7);
            c.lineTo(6, 4);
            c.stroke();
        } else if (name === "stop")
            c.fillRect(-4, -4, 8, 8);
        else if (name === "play")
            triangle(0, 1);
        else if (name === "pause") {
            c.fillRect(-4, -5, 3, 10);
            c.fillRect(1, -5, 3, 10);
        } else if (name === "next" || name === "previous") {
            let d = name === "next" ? 1 : -1;
            triangle(-d, d);
            c.fillRect(d * 6 - 1, -5, 2, 10);
        } else if (name === "shuffle") {
            c.beginPath();
            c.moveTo(-7, -5);
            c.lineTo(-4, -5);
            c.lineTo(4, 5);
            c.lineTo(8, 5);
            c.moveTo(-7, 5);
            c.lineTo(-4, 5);
            c.lineTo(4, -5);
            c.lineTo(8, -5);
            c.moveTo(5, -8);
            c.lineTo(8, -5);
            c.lineTo(5, -2);
            c.moveTo(5, 2);
            c.lineTo(8, 5);
            c.lineTo(5, 8);
            c.stroke();
        } else if (name.startsWith("back") || name.startsWith("forward")) {
            let back = name.startsWith("back");
            c.save();
            if (!back)
                c.scale(-1, 1);
            c.beginPath();
            c.arc(0, 1, 7, -Math.PI * .9, Math.PI * .8);
            c.stroke();
            c.beginPath();
            c.moveTo(-8, -3);
            c.lineTo(-4, -5);
            c.lineTo(-4, -1);
            c.stroke();
            c.restore();
            c.font = "bold 7px sans-serif";
            c.textAlign = "center";
            c.textBaseline = "middle";
            c.fillText(name.endsWith("30") ? "30" : "10", 0, 1);
        } else if (name === "discPlay" || name === "discPause" || name === "discEmblem") {
            c.fillStyle = accent;
            c.beginPath();
            c.arc(0, 0, 10, 0, Math.PI * 2);
            c.fill();
            c.strokeStyle = ground;
            c.lineWidth = 1;
            for (let i = 0; i < 9; ++i) {
                let a = i * Math.PI * 2 / 9 + discAngle * Math.PI / 180;
                c.beginPath();
                c.moveTo(Math.cos(a) * 3, Math.sin(a) * 3);
                c.lineTo(Math.cos(a + .15) * 10, Math.sin(a + .15) * 10);
                c.stroke();
            }
            c.fillStyle = ground;
            c.beginPath();
            c.arc(0, 0, 4, 0, Math.PI * 2);
            c.fill();
            c.fillStyle = "white";
            if (name === "discPause") {
                c.fillRect(-2, -2.5, 1.5, 5);
                c.fillRect(.5, -2.5, 1.5, 5);
            } else if (name !== "discEmblem") {
                c.beginPath();
                c.moveTo(-1.5, -2.5);
                c.lineTo(2, 0);
                c.lineTo(-1.5, 2.5);
                c.closePath();
                c.fill();
            }
        }
    }
    onWidthChanged: requestPaint()

    Timer {
        interval: 33
        repeat: true
        running: icon.running

        onTriggered: {
            icon.discAngle = (icon.discAngle + 360 / (2.7 * 30)) % 360;
            icon.requestPaint();
        }
    }
}
