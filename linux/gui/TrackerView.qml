import QtQuick
import QtQuick.Controls

Item {
    id: grid

    property color accent: "#5cb3c2"
    readonly property real baseCell: showVolume ? 98 : 72
    readonly property real cellWidth: channels.length > 4 ? baseCell * (fontSize / 12) + 1 : (width - numberWidth) / Math.max(1, channels.length)
    property var channels: [0, 1, 2, 3]
    property int contextRow: 0
    property int currentRow: 0
    property bool dark: true
    readonly property real fontSize: needsScroll ? 11 : 12
    property var markerRows: []
    property var muted: []
    readonly property bool needsScroll: channels.length > 4 && channels.length * (baseCell + 1) > width - numberWidth
    readonly property int numberWidth: 38
    property var pattern: ({})
    readonly property real rowHeight: fontSize + 6
    readonly property var rows: pattern.rows || []
    property int sectionEndRow: -1
    property int sectionStartRow: -1
    readonly property bool showVolume: rows.some(row => row.some(n => n.volume >= 0))

    signal boundary(bool start, int row)
    signal seek(int row)

    function effect(n) {
        return n.effectText || "...";
    }
    function follow() {
        let target = Math.max(0, currentRow * rowHeight - scroller.height / 2 + rowHeight / 2);
        scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height), target);
    }
    function noteName(n) {
        return n.noteText || "---";
    }

    onCellWidthChanged: painting.requestPaint()
    onChannelsChanged: painting.requestPaint()
    onCurrentRowChanged: follow()
    onDarkChanged: painting.requestPaint()
    onMarkerRowsChanged: {
        painting.requestPaint();
        numbers.requestPaint();
    }
    onMutedChanged: painting.requestPaint()
    onPatternChanged: {
        painting.requestPaint();
        follow();
    }
    onSectionEndRowChanged: painting.requestPaint()
    onSectionStartRowChanged: painting.requestPaint()

    Rectangle {
        anchors.fill: parent
        clip: true
        color: grid.dark ? "#131518" : "#edf0f4"
        radius: grid.dark ? 8 : 0

        Flickable {
            id: scroller

            anchors.fill: parent
            anchors.leftMargin: grid.numberWidth
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            contentHeight: grid.rows.length * grid.rowHeight
            contentWidth: Math.max(width, grid.channels.length * grid.cellWidth)

            ScrollBar.horizontal: ScrollBar {
            }
            ScrollBar.vertical: ScrollBar {
            }

            onContentXChanged: painting.requestPaint()
            onContentYChanged: {
                painting.requestPaint();
                numbers.requestPaint();
            }

            Canvas {
                id: painting

                height: scroller.height
                width: scroller.width
                x: scroller.contentX
                y: scroller.contentY

                onPaint: {
                    let c = getContext("2d");
                    c.reset();
                    c.translate(-scroller.contentX, -scroller.contentY);
                    c.font = "600 " + grid.fontSize + "px monospace";
                    c.textBaseline = "middle";
                    let first = Math.max(0, Math.floor(scroller.contentY / grid.rowHeight)), end = Math.min(grid.rows.length, Math.ceil((scroller.contentY + height) / grid.rowHeight));
                    for (let r = first; r < end; ++r) {
                        let y = r * grid.rowHeight;
                        if (grid.sectionStartRow >= 0 && r >= grid.sectionStartRow && r <= grid.sectionEndRow) {
                            c.fillStyle = Qt.alpha(grid.accent, 0.08);
                            c.fillRect(scroller.contentX, y, width, grid.rowHeight);
                        }
                        for (let ch = 0; ch < grid.channels.length; ++ch) {
                            let index = grid.channels[ch], n = grid.rows[r][index];
                            if (!n)
                                continue;
                            let x = ch * grid.cellWidth + 5, charWidth = grid.fontSize * 0.62;
                            c.globalAlpha = grid.muted[index] ? 0.3 : 1;
                            const note = grid.noteName(n);
                            c.fillStyle = note === "---" ? (grid.dark ? "#3e4a4d" : "#a5afbc") : (grid.dark ? "#a8d1b8" : "#13171d");
                            c.fillText(note, x, y + grid.rowHeight / 2);
                            c.fillStyle = n.instrument ? (grid.dark ? "#e3c26b" : "#576170") : (grid.dark ? "#3e4a4d" : "#a5afbc");
                            c.fillText(n.instrumentText || "--", x + 3 * charWidth + 4, y + grid.rowHeight / 2);
                            if (grid.showVolume) {
                                c.fillStyle = n.volume >= 0 ? (grid.dark ? "#e3c26b" : "#576170") : (grid.dark ? "#3e4a4d" : "#a5afbc");
                                c.fillText(n.volumeText || "...", x + 5 * charWidth + 8, y + grid.rowHeight / 2);
                            }
                            c.fillStyle = n.effect || n.data ? (grid.dark ? "#85b3d6" : "#0055b5") : (grid.dark ? "#3e4a4d" : "#a5afbc");
                            c.fillText(grid.effect(n), x + (grid.showVolume ? 8 * charWidth + 12 : 5 * charWidth + 8), y + grid.rowHeight / 2);
                            c.globalAlpha = 1;
                        }
                    }
                    c.strokeStyle = grid.dark ? "#29424a" : "#c8d0db";
                    c.lineWidth = 1;
                    for (let ch = 0; ch <= grid.channels.length; ++ch) {
                        let x = ch * grid.cellWidth + 0.5;
                        c.beginPath();
                        c.moveTo(x, scroller.contentY);
                        c.lineTo(x, scroller.contentY + height);
                        c.stroke();
                    }
                }
            }
            Rectangle {
                color: grid.accent
                height: grid.rowHeight
                opacity: 0.14
                width: scroller.contentWidth
                x: 0
                y: grid.currentRow * grid.rowHeight
            }
            MouseArea {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                anchors.fill: painting

                onClicked: mouse => {
                    let row = Math.floor((mouse.y + scroller.contentY) / grid.rowHeight);
                    if (mouse.button === Qt.RightButton) {
                        grid.contextRow = row;
                        rowMenu.popup();
                    } else
                        grid.seek(row);
                }
            }
        }
        Item {
            clip: true
            height: parent.height
            width: grid.numberWidth

            Canvas {
                id: numbers

                property var data: grid.rows

                height: parent.height
                width: grid.numberWidth

                onDataChanged: requestPaint()
                onPaint: {
                    let c = getContext("2d");
                    c.reset();
                    c.font = "600 " + (grid.fontSize - 1) + "px monospace";
                    c.fillStyle = grid.dark ? "#9eb3c2" : "#0055b5";
                    c.textAlign = "center";
                    c.textBaseline = "middle";
                    let first = Math.max(0, Math.floor(scroller.contentY / grid.rowHeight)), end = Math.min(grid.rows.length, Math.ceil((scroller.contentY + height) / grid.rowHeight));
                    for (let r = first; r < end; ++r) {
                        let y = r * grid.rowHeight - scroller.contentY + grid.rowHeight / 2;
                        c.fillText(r.toString().padStart(2, "0"), grid.numberWidth / 2, y);
                        if (grid.markerRows.indexOf(r) >= 0) {
                            c.fillStyle = grid.accent;
                            c.fillRect(2, y - 2, 4, 4);
                            c.fillStyle = grid.dark ? "#9eb3c2" : "#0055b5";
                        }
                    }
                }
            }
            Rectangle {
                color: grid.accent
                height: grid.rowHeight
                opacity: 0.14
                width: parent.width
                y: grid.currentRow * grid.rowHeight - scroller.contentY
            }
            MouseArea {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                anchors.fill: parent

                onClicked: mouse => {
                    let row = Math.floor((mouse.y + scroller.contentY) / grid.rowHeight);
                    if (mouse.button === Qt.RightButton) {
                        grid.contextRow = row;
                        rowMenu.popup();
                    } else
                        grid.seek(row);
                }
            }
        }
    }
    Menu {
        id: rowMenu

        MenuItem {
            text: "Als Anfang markieren"

            onTriggered: grid.boundary(true, grid.contextRow)
        }
        MenuItem {
            text: "Als Ende markieren"

            onTriggered: grid.boundary(false, grid.contextRow)
        }
    }
}
