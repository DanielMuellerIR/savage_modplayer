import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property var send
    required property var option
    required property int savedMinutes
    required property var playbackState
    required property var time

    anchors.centerIn: parent
    font.pixelSize: 13
    height: 480
    modal: true
    title: "Einschlaftimer"
    width: 380

    onOpened: timerMinutes.value = dialog.savedMinutes

    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        ScrollView {
            id: timerScroll

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                spacing: 18
                width: timerScroll.availableWidth

                Label {
                    text: "Einschlaftimer"

                    font {
                        bold: true
                        pixelSize: 20
                    }
                }
                Label {
                    Layout.fillWidth: true
                    color: secondary
                    text: "Die letzten zehn Sekunden blenden sanft aus. Der Lautstärkeregler bleibt unverändert."
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Label {
                        Layout.fillWidth: true
                        text: "Dauer in Minuten"
                    }
                    SpinBox {
                        id: timerMinutes

                        from: 1
                        to: 720
                        value: 15

                        onValueModified: option("sleepTimerMinutes", value)
                    }
                }
                RowLayout {
                    Repeater {
                        model: [15, 30, 60]

                        FormButton {
                            required property int modelData

                            text: modelData + " Min."

                            onClicked: timerMinutes.value = modelData
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    color: secondary
                    font.pixelSize: 11
                    text: "Der Timer läuft auch bei Pause und Titelwechsel weiter. Nach Ablauf bleibt die Wiedergabe aus, bis du sie bewusst startest. Nach einem App-Neustart ist der Timer aus."
                    wrapMode: Text.Wrap
                }
            }
        }
        RowLayout {
            Label {
                Layout.fillWidth: true
                font.bold: true
                text: ({
                        inactive: "Ausgeschaltet",
                        countingDown: "Restzeit",
                        fading: "Ausblenden …",
                        expired: "Wiedergabe beendet"
                    })[playbackState.timerPhase || "inactive"]
            }
            Label {
                font.pixelSize: 24
                text: time(playbackState.timerSeconds)
            }
        }
        RowLayout {
            visible: playbackState.timerPhase !== "inactive" && !!playbackState.timerPhase

            FormButton {
                text: "+15 Minuten"
                visible: playbackState.timerActive || false

                onClicked: send("timerExtend")
            }
            FormButton {
                text: "Timer abbrechen"

                onClicked: send("timer", {
                    index: 0
                })
            }
        }
        RowLayout {
            FormButton {
                text: "Schließen"

                onClicked: dialog.close()
            }
            Item {
                Layout.fillWidth: true
            }
            FormButton {
                text: playbackState.timerActive ? "Neu starten" : "Timer starten"

                onClicked: send("timer", {
                    index: timerMinutes.value
                })
            }
        }
    }
}
