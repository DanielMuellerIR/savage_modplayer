import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property var send
    required property var preferences
    required property bool darkTheme
    required property var moduleInfo
    required property var sound

    property bool editingDefaults: false

    function update(key, value) {
        if (editingDefaults) {
            send("defaultOption", {
                text: key,
                setting: value
            });
            return;
        }
        let v = Object.assign({}, moduleInfo.trackSettings || {});
        if (value === null)
            delete v[key];
        else
            v[key] = value;
        send("trackSettings", {
            settings: v
        });
    }

    anchors.centerIn: parent
    font.pixelSize: 13
    height: 560
    modal: true
    standardButtons: Dialog.Close
    title: "Klang"
    width: 440

    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        Label {
            Layout.fillWidth: true
            text: dialog.editingDefaults ? "Globale Klangvorgaben" : moduleInfo.title || "Kein Song geladen"
            wrapMode: Text.Wrap

            font {
                bold: true
                pixelSize: 20
            }
        }
        TabBar {
            Layout.fillWidth: true
            currentIndex: dialog.editingDefaults ? 1 : 0

            TabButton {
                text: "Dieser Titel"

                onClicked: dialog.editingDefaults = false
            }
            TabButton {
                text: "Globale Vorgaben"

                onClicked: dialog.editingDefaults = true
            }
        }
        ScrollView {
            id: soundScroll

            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                spacing: 16
                width: soundScroll.availableWidth

                Label {
                    Layout.fillWidth: true
                    color: secondary
                    text: dialog.editingDefaults ? "Diese Vorgaben gelten für alle Titel ohne passenden Override." : "Jeder Titelwert ersetzt nur seine passende globale Vorgabe."
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: [
                        {
                            key: "palClock",
                            label: "MOD-Clock",
                            choices: ["PAL", "NTSC"]
                        },
                        {
                            key: "useInterpolation",
                            label: "Lineare Interpolation",
                            choices: ["Ein", "Aus"]
                        },
                        {
                            key: "ledFilterActive",
                            label: "LED-Ausgabefilter",
                            choices: ["Ein", "Aus"]
                        }
                    ]

                    ColumnLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 6
                        visible: modelData.key !== "palClock" || dialog.editingDefaults || !!moduleInfo.amigaClock

                        Label {
                            text: modelData.label
                        }
                        FormCombo {
                            Layout.fillWidth: true
                            currentIndex: dialog.editingDefaults ? (preferences[modelData.key] === false ? 1 : 0) : (moduleInfo.trackSettings || {})[modelData.key] === undefined ? 0 : ((moduleInfo.trackSettings || {})[modelData.key] ? 1 : 2)
                            enabled: dialog.editingDefaults || !!moduleInfo.sourceID
                            model: dialog.editingDefaults ? modelData.choices : ["Globale Vorgabe"].concat(modelData.choices)

                            onActivated: dialog.update(modelData.key, dialog.editingDefaults ? currentIndex === 0 : currentIndex === 0 ? null : currentIndex === 1)
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    color: secondary
                    text: "Dieses Format verwendet ein festes Frequenzmodell; PAL/NTSC ist nicht anwendbar."
                    visible: !dialog.editingDefaults && !moduleInfo.amigaClock
                    wrapMode: Text.Wrap
                }
                PlayerCheckBox {
                    baseFontSize: 13
                    checked: (moduleInfo.trackSettings || {}).stereoSeparation !== undefined
                    dark: dialog.darkTheme
                    enabled: !!moduleInfo.sourceID
                    text: "Stereoabstand für diesen Titel"
                    visible: !dialog.editingDefaults

                    onClicked: dialog.update("stereoSeparation", checked ? (sound.stereoSeparation === undefined ? .8 : sound.stereoSeparation) : null)
                }
                Label {
                    text: "Separation: " + Math.round((dialog.editingDefaults ? (preferences.stereoSeparation === undefined ? .8 : preferences.stereoSeparation) : (sound.stereoSeparation || 0)) * 100) + " %"
                }
                PlayerSlider {
                    Layout.fillWidth: true
                    dark: dialog.darkTheme
                    enabled: dialog.editingDefaults || (moduleInfo.trackSettings || {}).stereoSeparation !== undefined
                    from: 0
                    to: 1
                    value: dialog.editingDefaults ? (preferences.stereoSeparation === undefined ? .8 : preferences.stereoSeparation) : sound.stereoSeparation || 0

                    onMoved: dialog.update("stereoSeparation", value)
                }
            }
        }
        FormButton {
            enabled: !!moduleInfo.sourceID
            text: "Titel zurücksetzen"
            visible: !dialog.editingDefaults

            onClicked: send("trackSettings", {
                settings: {}
            })
        }
    }
}
