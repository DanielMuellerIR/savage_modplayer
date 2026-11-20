import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

Dialog {
    id: dialog

    required property color secondary
    required property var send
    required property real fontScale
    required property var session
    required property var fileDialogs
    required property var playbackState
    required property bool darkTheme

    function options() {
        let width = [640, 1280, 1920][videoSize.currentIndex];
        return {
            width: width,
            height: width * 9 / 16,
            fps: videoFPS.currentValue,
            compact: videoQuality.currentIndex === 1,
            seconds: videoDuration.currentValue,
            light: videoAppearance.currentIndex === 1,
            horizon: videoLookahead.currentValue
        };
    }

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Notenregen als Video"
    width: 640

    onClosed: {
        previewPlayer.stop();
        if (session.videoPreparing)
            send("exportCancel");
    }
    onOpened: {
        session.videoPreviewPath = "";
        session.exportResult = "";
        session.exportProgress = 0;
        send("prepareExport", {
            video: true
        });
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        ScrollView {
            id: videoScroll

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                spacing: 14
                width: videoScroll.availableWidth

                Label {
                    text: "Notenregen als Video"

                    font {
                        bold: true
                        pixelSize: 20 * dialog.fontScale
                    }
                }
                Label {
                    Layout.fillWidth: true
                    font.bold: true
                    text: session.exportTitle
                    wrapMode: Text.Wrap
                }
                Label {
                    Layout.fillWidth: true
                    color: secondary
                    text: "Titel und Klang sind beim Öffnen festgehalten. Der Export beginnt am Songanfang; die normale Wiedergabe kann weiterlaufen."
                    wrapMode: Text.Wrap
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 240
                    color: "black"

                    VideoOutput {
                        id: previewOutput

                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                    Label {
                        anchors.centerIn: parent
                        color: "white"
                        text: session.videoPreparing ? "Vorschau wird vorbereitet…" : "Vorschau vorbereiten"
                        visible: session.videoPreparing || !session.videoPreviewPath
                    }
                }
                MediaPlayer {
                    id: previewPlayer

                    source: session.videoPreviewPath ? fileDialogs.fileURL(session.videoPreviewPath) : ""
                    videoOutput: previewOutput

                    audioOutput: AudioOutput {
                        muted: true
                    }

                    onMediaStatusChanged: {
                        if (mediaStatus === MediaPlayer.LoadedMedia) {
                            play();
                            previewPause.restart();
                        }
                    }
                }
                Timer {
                    id: previewPause

                    interval: 120

                    onTriggered: {
                        previewPlayer.pause();
                        previewPlayer.position = 0;
                    }
                }
                RowLayout {
                    FormButton {
                        enabled: !session.exporting && !session.videoPreparing
                        text: "Vorschau vorbereiten"

                        onClicked: {
                            session.videoPreviewPath = "";
                            send("videoPreview", dialog.options());
                        }
                    }
                    FormButton {
                        enabled: !!session.videoPreviewPath && !session.videoPreparing
                        text: previewPlayer.playbackState === MediaPlayer.PlayingState ? "Pause" : "5-s-Vorschau abspielen"

                        onClicked: {
                            if (previewPlayer.playbackState === MediaPlayer.PlayingState)
                                previewPlayer.pause();
                            else
                                previewPlayer.play();
                        }
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    enabled: !session.exporting && !session.videoPreparing
                    rowSpacing: 10

                    Label {
                        text: "Auflösung"
                    }
                    FormCombo {
                        id: videoSize

                        Layout.fillWidth: true
                        currentIndex: 1
                        model: ["640 × 360 · klein", "1280 × 720 · HD", "1920 × 1080 · Full HD"]
                    }
                    Label {
                        text: "Bildrate"
                    }
                    FormCombo {
                        id: videoFPS

                        Layout.fillWidth: true
                        currentIndex: 2
                        model: [24, 25, 30, 60]
                    }
                    Label {
                        text: "Bildqualität"
                    }
                    FormCombo {
                        id: videoQuality

                        Layout.fillWidth: true
                        model: ["Hoch · größere Datei", "Kompakt · kleinere Datei"]
                    }
                    Label {
                        text: "Darstellung"
                    }
                    FormCombo {
                        id: videoAppearance

                        Layout.fillWidth: true
                        currentIndex: darkTheme ? 0 : 1
                        model: ["Dunkel", "Hell"]
                    }
                    Label {
                        text: "Vorlauf"
                    }
                    FormCombo {
                        id: videoLookahead

                        Layout.fillWidth: true
                        currentIndex: 1
                        model: [2, 4, 8]
                    }
                    Label {
                        text: "Dauer begrenzen"
                    }
                    FormCombo {
                        id: videoDuration

                        Layout.fillWidth: true
                        currentIndex: 3
                        model: [60, 180, 300, 600, 1800, 3600]
                    }
                }
                Label {
                    Layout.fillWidth: true
                    color: secondary
                    text: "MOV mit H.264-Bild und verlustfreiem Float32-Stereo bei 48 kHz. Mute/Solo, Clock, Interpolation und Separation werden übernommen. Mixerlautstärke, externer LED-Filter und manuelle Tempoänderungen bleiben außerhalb des Exports."
                    wrapMode: Text.Wrap
                }
            }
        }
        ProgressBar {
            Layout.fillWidth: true
            value: session.exportProgress
            visible: session.exporting || session.videoPreparing
        }
        RowLayout {
            FormButton {
                enabled: !session.exporting && !session.videoPreparing
                text: "Video exportieren…"

                onClicked: {
                    let path = fileDialogs.saveFile("Notenregen exportieren", "Notenregen.mov", "QuickTime (*.mov)");
                    if (path) {
                        session.exporting = true;
                        send("videoExport", Object.assign({
                            path: path
                        }, dialog.options()));
                    }
                }
            }
            FormButton {
                enabled: session.exporting || session.videoPreparing
                text: "Abbrechen"

                onClicked: send("exportCancel")
            }
            FormButton {
                text: "Im Dateimanager zeigen"
                visible: !!session.exportResult && !session.exporting

                onClicked: fileDialogs.reveal(session.exportResult)
            }
        }
    }
}
