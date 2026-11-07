import QtQuick
import QtQuick.Controls

Canvas {
    id: rain

    property color accent: "#5cb3c2"
    property bool dark: true
    property var data: ({})
    property real fixedKeyWidth: 0
    property real horizon: 4
    property string hoverText: ""
    property var keyRange: range()
    property var layout: ({})
    property var muted: []
    property var solo: []
    property var songKeys: []
    property bool zoomToSong: false

    signal rangeChanged

    function audible(n) {
        return !muted[n.channel] && (!solo.some(v => v) || solo[n.channel]);
    }
    function bar(n, g) {
        let w = Math.max(3, g.kw * (black(n.key) ? .52 : .68)), bottom = g.strike - (n.start - (data.time || 0)) * g.scale, top = g.strike - (n.end - (data.time || 0)) * g.scale;
        return {
            x: center(n.key, g) - w / 2,
            y: top,
            w: w,
            h: Math.max(2, bottom - top)
        };
    }
    function black(k) {
        return [1, 3, 6, 8, 10].indexOf(k % 12) >= 0;
    }
    function center(k, g) {
        return g.left + g.whites.filter(v => v < k).length * g.kw + (black(k) ? 0 : g.kw / 2);
    }
    function channelColor(k) {
        return Qt.hsva((k * 0.381966 + 0.54) % 1, 0.58, 0.88, 1);
    }
    function fullKeyWidth() {
        let r = range(true), whites = 0;
        for (let k = r[0]; k <= r[1]; ++k)
            if (!black(k))
                ++whites;
        return Math.max(1, Math.min(Math.max(1, width - 60) / Math.max(1, whites), Math.min(144, height * .28) / 4.8));
    }
    function geometry() {
        let whites = [];
        for (let k = keyRange[0]; k <= keyRange[1]; ++k)
            if (!black(k))
                whites.push(k);
        let available = Math.max(1, width - 60), kw = fixedKeyWidth || Math.max(1, Math.min(available / Math.max(1, whites.length), Math.min(144, height * .28) / 4.8));
        let left = 42 + (available - kw * whites.length) / 2, strike = height - kw * 4.8;
        return {
            whites: whites,
            kw: kw,
            left: left,
            right: left + kw * whites.length,
            strike: strike,
            top: 18,
            scale: Math.max(1, strike - 18) / Math.max(1, horizon)
        };
    }
    function noteName(k) {
        return ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"][k % 12] + Math.floor(k / 12);
    }
    function range(forceFull) {
        let keys = (songKeys || []).concat((data.notes || []).map(n => n.key)), low = 9, high = 96;
        if (keys.length) {
            let min = Math.min(...keys), max = Math.max(...keys);
            low = Math.min(low, min);
            high = Math.max(high, max);
            if (zoomToSong && !forceFull) {
                low = Math.max(low, Math.floor(min / 12) * 12);
                high = Math.min(Math.max(96, max), Math.max(low + 23, (Math.floor(max / 12) + 1) * 12 - 1));
                low = Math.max(Math.min(9, min), Math.min(low, high - 23));
            }
        }
        if (black(low))
            --low;
        if (black(high))
            ++high;
        return [low, high];
    }
    function rounded(c, x, y, w, h, r) {
        c.beginPath();
        c.moveTo(x + r, y);
        c.lineTo(x + w - r, y);
        c.quadraticCurveTo(x + w, y, x + w, y + r);
        c.lineTo(x + w, y + h - r);
        c.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
        c.lineTo(x + r, y + h);
        c.quadraticCurveTo(x, y + h, x, y + h - r);
        c.lineTo(x, y + r);
        c.quadraticCurveTo(x, y, x + r, y);
        c.closePath();
        c.fill();
    }

    Accessible.name: "Fallende Tracker-Noten über einer Klaviatur"
    ToolTip.text: hoverText
    ToolTip.visible: hoverText !== ""

    onDarkChanged: requestPaint()
    onDataChanged: requestPaint()
    onHeightChanged: requestPaint()
    onHorizonChanged: requestPaint()
    onKeyRangeChanged: {
        requestPaint();
        rangeChanged();
    }
    onMutedChanged: requestPaint()
    onPaint: {
        let c = getContext("2d");
        c.reset();
        c.fillStyle = dark ? "#050608" : "#f6f7fa";
        c.fillRect(0, 0, width, height);
        let g = geometry(), time = data.time || 0, notes = (data.notes || []).filter(n => audible(n)), grid = dark ? Qt.rgba(1, 1, 1, .08) : Qt.rgba(0, 0, 0, .08);
        for (let k = keyRange[0]; k <= keyRange[1]; ++k) {
            let x = center(k, g);
            if (black(k)) {
                c.fillStyle = dark ? Qt.rgba(1, 1, 1, .025) : Qt.rgba(0, 0, 0, .035);
                c.fillRect(x - g.kw * .31, g.top, g.kw * .62, g.strike - g.top);
            }
            if (k % 12 === 0) {
                c.strokeStyle = grid;
                c.beginPath();
                c.moveTo(x - g.kw / 2, g.top);
                c.lineTo(x - g.kw / 2, g.strike);
                c.stroke();
            }
        }
        c.font = "500 9px monospace";
        c.textAlign = "right";
        c.textBaseline = "middle";
        for (let sec = 0; sec <= horizon; ++sec) {
            let y = g.strike - sec * g.scale;
            c.strokeStyle = grid;
            c.beginPath();
            c.moveTo(g.left, y);
            c.lineTo(g.right, y);
            c.stroke();
            c.fillStyle = dark ? "#9ea8b0" : "#576170";
            c.fillText(sec === 0 ? "JETZT" : "+" + sec + "s", g.left - 6, y);
        }
        c.save();
        c.beginPath();
        c.rect(g.left, g.top, g.right - g.left, g.strike - g.top);
        c.clip();
        for (let n of notes) {
            if (n.key < keyRange[0] || n.key > keyRange[1] || n.end <= time || n.start >= time + horizon)
                continue;
            let r = bar(n, g), bottom = Math.min(g.strike, r.y + r.h), top = Math.max(g.top, r.y), visible = bottom - top;
            c.fillStyle = channelColor(n.channel);
            rounded(c, r.x, r.y, r.w, r.h, Math.min(3, r.w * .15));
            if (r.w >= 12 && visible >= 15) {
                c.font = "600 " + (r.w >= 18 ? 10 : 9) + "px monospace";
                c.fillStyle = Qt.rgba(0, 0, 0, .85);
                c.textAlign = "center";
                let label = noteName(n.key), tw = c.measureText(label).width;
                if (r.w >= tw + 4 && visible >= 18)
                    c.fillText(label, r.x + r.w / 2, bottom - 9);
                else if (r.w >= 12 && visible >= tw + 6) {
                    c.save();
                    c.translate(r.x + r.w / 2, bottom - tw / 2 - 3);
                    c.rotate(-Math.PI / 2);
                    c.fillText(label, 0, 0);
                    c.restore();
                }
            }
        }
        c.restore();
        let active = notes.filter(n => n.start <= time && n.end > time);
        for (let isBlack of [false, true])
            for (let k = keyRange[0]; k <= keyRange[1]; ++k) {
                if (black(k) !== isBlack)
                    continue;
                let kw = g.kw * (isBlack ? .62 : 1), kh = g.kw * 4.8 * (isBlack ? .63 : 1), x = center(k, g) - kw / 2, voices = active.filter(n => n.key === k);
                c.fillStyle = isBlack ? "#1a1a1a" : "#e6e6e6";
                c.fillRect(x, g.strike, kw, kh);
                if (voices.length) {
                    c.fillStyle = Qt.alpha(channelColor(voices[0].channel), isBlack ? .32 : .22);
                    c.fillRect(x, g.strike, kw, kh);
                }
                c.strokeStyle = Qt.rgba(0, 0, 0, .5);
                c.lineWidth = .6;
                c.strokeRect(x, g.strike, kw, kh);
                for (let i = 0; i < voices.length; ++i) {
                    c.fillStyle = channelColor(voices[i].channel);
                    c.fillRect(x + i * kw / voices.length, g.strike, kw / voices.length, 3);
                }
                if (k % 12 === 0 || (voices.length && kw > 22)) {
                    c.fillStyle = isBlack ? Qt.rgba(1, 1, 1, .9) : Qt.rgba(0, 0, 0, .7);
                    c.font = "500 9px monospace";
                    c.textAlign = "center";
                    c.fillText(noteName(k), x + kw / 2, g.strike + kh - 14);
                }
            }
        c.strokeStyle = accent;
        c.lineWidth = 2;
        c.beginPath();
        c.moveTo(g.left, g.strike);
        c.lineTo(g.right, g.strike);
        c.stroke();
    }
    onSoloChanged: requestPaint()
    onWidthChanged: requestPaint()

    MouseArea {
        acceptedButtons: Qt.NoButton
        anchors.fill: parent
        hoverEnabled: true

        onExited: rain.hoverText = ""
        onPositionChanged: mouse => {
            let g = rain.geometry(), found = "";
            if (mouse.x >= g.left && mouse.x <= g.right && mouse.y >= g.top && mouse.y <= g.strike) {
                let notes = rain.data.notes || [];
                for (let i = notes.length - 1; i >= 0; --i) {
                    let n = notes[i], r = rain.bar(n, g);
                    if (rain.audible(n) && mouse.x >= r.x && mouse.x <= r.x + r.w && mouse.y >= r.y - 2 && mouse.y <= r.y + r.h + 2) {
                        found = rain.noteName(n.key) + " · K" + (n.channel + 1) + " · " + (n.isOpen ? "≥ " : "") + (n.end - n.start).toFixed(2) + " s";
                        break;
                    }
                }
            }
            rain.hoverText = found;
        }
    }
}
