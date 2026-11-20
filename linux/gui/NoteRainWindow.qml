import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: noteWindow

    required property color backdrop
    required property color accent
    required property color secondary
    required property bool darkTheme
    required property var playerPalette
    required property var moduleInfo
    required property bool hasModule
    required property var mutedChannels
    required property var notes
    required property var playbackState
    required property var preferences
    required property var send
    required property var option
    required property var sectionStart
    required property var sectionEnd
    required property bool validSection
    required property var addressText

    signal markersRequested()

    property real keyboardWindowWidth: 1100

    color: backdrop
    height: 760
    minimumHeight: 440
    minimumWidth: songRange.currentIndex === 1 ? 420 : 720
    objectName: "noteRainWindow"
    title: "Notenregen — Savage Mod Player"
    visible: false
    width: 1100

    onClosing: send("notes", {
        enabled: false
    })
    onVisibleChanged: if (visible && songRange.currentIndex === 1)
        Qt.callLater(function () {
            rainCanvas.fixedKeyWidth = rainCanvas.fullKeyWidth();
            noteWindow.width = Math.max(420, rainCanvas.fixedKeyWidth * rainCanvas.geometry().whites.length + 60);
        })

    Pane {
        anchors.fill: parent
        background: null
        padding: 0
        palette: noteWindow.playerPalette

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            GridLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                columnSpacing: 14
                columns: noteWindow.width >= 620 ? 2 : 1
                rowSpacing: 12

                Column {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        color: secondary
                        text: "NOTENREGEN"

                        font {
                            bold: true
                            family: "monospace"
                            pixelSize: 12
                        }
                    }
                    Text {
                        color: primary
                        elide: Text.ElideRight
                        text: moduleInfo.title || ""
                        width: parent.width

                        font {
                            bold: true
                            pixelSize: 18
                        }
                    }
                }
                RowLayout {
                    spacing: 8

                    FormCombo {
                        id: songRange

                        Layout.preferredWidth: 172
                        currentIndex: preferences.noteRainZoomToSong ? 1 : 0
                        model: ["Klaviatur", "Tonumfang"]

                        onActivated: {
                            option("noteRainZoomToSong", currentIndex === 1);
                            if (currentIndex === 1) {
                                noteWindow.keyboardWindowWidth = noteWindow.width;
                                rainCanvas.fixedKeyWidth = rainCanvas.fullKeyWidth();
                                noteWindow.width = Math.max(420, rainCanvas.fixedKeyWidth * rainCanvas.geometry().whites.length + 60);
                            } else {
                                rainCanvas.fixedKeyWidth = 0;
                                noteWindow.width = noteWindow.keyboardWindowWidth;
                            }
                        }
                    }
                    FormCombo {
                        id: horizon

                        Layout.preferredWidth: 70
                        currentIndex: Math.max(0, model.indexOf(preferences.noteRainHorizon || 4))
                        displayText: currentValue + " s"
                        model: [2, 4, 8]

                        onActivated: option("noteRainHorizon", currentValue)
                    }
                    PlayerButton {
                        dark: noteWindow.darkTheme
                        enabled: hasModule
                        hint: playbackState.playing && !playbackState.paused ? "Pause" : "Abspielen"
                        iconName: playbackState.playing && !playbackState.paused ? "pause" : "play"

                        onClicked: send("play")
                    }
                    PlayerButton {
                        dark: noteWindow.darkTheme
                        enabled: playbackState.playing || false
                        hint: "Stopp"
                        iconName: "stop"

                        onClicked: send("stop")
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                color: Qt.alpha(secondary, .2)
                height: 1
            }
            Item {
                Layout.fillHeight: true
                Layout.fillWidth: true

                NoteRain {
                    id: rainCanvas

                    accent: noteWindow.accent
                    anchors.fill: parent
                    dark: noteWindow.darkTheme
                    data: noteWindow.notes
                    horizon: horizon.currentValue || 4
                    muted: mutedChannels
                    solo: playbackState.solo || []
                    songKeys: moduleInfo.songKeyRange || []
                    zoomToSong: songRange.currentIndex === 1

                    onRangeChanged: if (noteWindow.visible && zoomToSong && fixedKeyWidth > 0)
                        noteWindow.width = Math.max(420, fixedKeyWidth * geometry().whites.length + 60)
                }
                Rectangle {
                    anchors.centerIn: parent
                    color: Qt.alpha(backdrop, .96)
                    height: messageColumn.implicitHeight + 48
                    radius: 10
                    visible: !!(!hasModule || !playbackState.playing || noteWindow.notes.overflow || noteWindow.notes.preparing && !(noteWindow.notes.notes || []).length)
                    width: Math.min(parent.width - 48, 480)

                    ColumnLayout {
                        id: messageColumn

                        anchors.centerIn: parent
                        spacing: 8
                        width: parent.width - 48

                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: !hasModule ? "Keine Musik geladen" : !playbackState.playing ? "Bereit für den nächsten Anschlag" : noteWindow.notes.overflow ? "Vorschau neu starten" : "Notenvorschau wird berechnet …"
                            wrapMode: Text.Wrap

                            font {
                                bold: true
                                pixelSize: 18
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            color: secondary
                            horizontalAlignment: Text.AlignHCenter
                            text: !hasModule ? "Öffne ein MOD-, S3M-, XM- oder IT-Modul im Player." : !playbackState.playing ? "Starte die Wiedergabe. Die kommenden Noten fallen zur Klaviatur." : noteWindow.notes.overflow ? "Starte die Wiedergabe erneut, um die Notenvorschau zu synchronisieren." : ""
                            visible: !!text
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                color: Qt.alpha(secondary, .2)
                height: 1
            }
            ColumnLayout {
                Layout.bottomMargin: 12
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 12
                spacing: 10

                RowLayout {
                    Label {
                        color: secondary
                        text: validSection ? "Auswahl   " + addressText(sectionStart) + " – " + addressText(sectionEnd) : "Keine Bereichsauswahl"
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Label {
                        color: secondary
                        text: "Position:Zeile   " + addressText({
                            position: playbackState.position || 0,
                            row: playbackState.row || 0
                        })
                    }
                }
                PlayerButton {
                    dark: noteWindow.darkTheme
                    text: "Songstellen…"

                    onClicked: noteWindow.markersRequested()
                }
                RowLayout {
                    Layout.fillWidth: true

                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        clip: true
                        contentWidth: legend.width

                        Row {
                            id: legend

                            spacing: 14

                            Repeater {
                                model: moduleInfo.displayChannels || []

                                Row {
                                    required property int modelData

                                    opacity: mutedChannels[modelData] || (playbackState.solo || []).some(v => v) && !playbackState.solo[modelData] ? .3 : 1
                                    spacing: 5

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: rainCanvas.channelColor(modelData)
                                        height: 8
                                        radius: 4
                                        width: 8
                                    }
                                    Text {
                                        color: primary
                                        text: "K" + (modelData + 1)

                                        font {
                                            family: "monospace"
                                            pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Label {
                        color: secondary
                        text: rainCanvas.noteName(rainCanvas.keyRange[0]) + "–" + rainCanvas.noteName(rainCanvas.keyRange[1]) + " · " + (rainCanvas.keyRange[1] - rainCanvas.keyRange[0] + 1) + " Tasten"

                        font {
                            family: "monospace"
                            pixelSize: 11
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        font.bold: true
                        text: !hasModule ? "Kein Modul" : !playbackState.playing ? "Gestoppt" : playbackState.paused ? "Pausiert" : noteWindow.notes.preparing ? "Vorschau wird ergänzt …" : "Spielt"
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Label {
                        color: secondary
                        font.pixelSize: 11
                        text: "Balken: Stimmenlaufzeit · Farbe: Kanal"
                    }
                }
            }
        }
    }
}
