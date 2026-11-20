import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property var moduleInfo
    required property var playbackState
    required property var sectionStart
    required property var sectionEnd
    required property bool validSection
    required property color secondary
    required property var addressText
    property string editingID: ""

    signal commandRequested(string name, var values)
    signal boundaryRequested(bool isStart, int position, int row)
    signal clearSectionRequested()

    function chooseCurrent() {
        markerPosition.value = Math.max(1, (playbackState.position || 0) + 1);
        markerRow.value = Math.max(0, playbackState.row || 0);
    }

    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    objectName: "markerDialog"
    title: "Songstellen und Bereich"

    onOpened: {
        editingID = "";
        markerName.clear();
        chooseCurrent();
    }

    ScrollView {
        id: markerScroll

        objectName: "markerScroll"

        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            spacing: 20
            width: markerScroll.availableWidth

            Label {
                font.bold: true
                text: moduleInfo.title || ""
            }
            Label {
                Layout.fillWidth: true
                color: secondary
                text: "Songpositionen beginnen bei 1, Zeilen bei 0. Ein Sprung erhält Play/Pause/Stopp; Tempo wird wie beim Tracker-Zeilenklick rekonstruiert. Laufende Stimmen und Effekte sind dabei näherungsweise."
                wrapMode: Text.Wrap
            }
            GroupBox {
                Layout.fillWidth: true
                title: "Ziel wählen"

                ColumnLayout {
                    enabled: !playbackState.markerSaving
                    spacing: 12
                    width: parent.width

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            Layout.fillWidth: true
                            text: "Songposition"
                        }
                        SpinBox {
                            id: markerPosition

                            from: 1
                            to: Math.max(1, (moduleInfo.orders || []).length)
                            value: 1
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            Layout.fillWidth: true
                            text: "Zeile"
                        }
                        SpinBox {
                            id: markerRow

                            from: 0
                            to: Math.max(0, ((moduleInfo.rowCounts || [])[markerPosition.value - 1] || 1) - 1)
                        }
                    }
                    RowLayout {
                        FormButton {
                            text: "Aktuelle Stelle"

                            onClicked: dialog.chooseCurrent()
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        FormButton {
                            enabled: !!moduleInfo.title
                            text: "Zum Ziel springen"

                            onClicked: dialog.commandRequested("seek", {
                                index: markerPosition.value - 1,
                                row: markerRow.value
                            })
                        }
                    }
                    TextField {
                        id: markerName

                        objectName: "markerName"

                        Layout.fillWidth: true
                        maximumLength: 201
                        placeholderText: "Name der Songstelle"
                    }
                    Label {
                        color: "#e5503a"
                        text: "Der Name darf höchstens 200 Zeichen haben."
                        visible: markerName.text.trim().length > 200
                    }
                    RowLayout {
                        FormButton {
                            enabled: !!moduleInfo.sourceID && markerName.text.trim().length > 0 && markerName.text.trim().length <= 200
                            objectName: "saveMarker"
                            text: dialog.editingID ? "Änderungen speichern" : "Songstelle hinzufügen"

                            onClicked: {
                                dialog.commandRequested(dialog.editingID ? "markerRename" : "markerAdd", {
                                    id: dialog.editingID,
                                    text: markerName.text.trim(),
                                    position: markerPosition.value - 1,
                                    row: markerRow.value
                                });
                                dialog.editingID = "";
                                markerName.clear();
                            }
                        }
                        FormButton {
                            text: "Neu"
                            visible: !!dialog.editingID

                            onClicked: {
                                dialog.editingID = "";
                                markerName.clear();
                                dialog.chooseCurrent();
                            }
                        }
                    }
                }
            }
            GroupBox {
                Layout.fillWidth: true
                title: "Bereich markieren"

                ColumnLayout {
                    spacing: 10
                    width: parent.width

                    RowLayout {
                        FormButton {
                            text: "Anfang (A)"

                            onClicked: dialog.boundaryRequested(true, markerPosition.value - 1, markerRow.value)
                        }
                        FormButton {
                            text: "Ende (B)"

                            onClicked: dialog.boundaryRequested(false, markerPosition.value - 1, markerRow.value)
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        FormButton {
                            text: "Lösen"

                            onClicked: dialog.clearSectionRequested()
                        }
                    }
                    Label {
                        color: secondary
                        text: "Position:Zeile   " + addressText(sectionStart) + " – " + addressText(sectionEnd)
                    }
                    Label {
                        color: "#e5503a"
                        text: "Das Ende liegt vor dem Anfang."
                        visible: sectionStart.position >= 0 && sectionEnd.position >= 0 && !validSection
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: "Die Auswahl markiert den Bereich im Tracker und in der Positionsleiste. Der gewählte Wiedergabe-Loop-Modus gilt weiter."
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        FormButton {
                            enabled: !playbackState.sectionPreparing && !playbackState.sectionActive && validSection
                            text: playbackState.sectionPreparing ? "A/B wird vorbereitet …" : playbackState.sectionActive ? "A/B-Schleife aktiv" : "A/B vorbereiten und abspielen"

                            onClicked: dialog.commandRequested("section", {
                                start: sectionStart,
                                end: sectionEnd
                            })
                        }
                        FormButton {
                            text: playbackState.sectionPreparing ? "Abbrechen" : "A/B ausschalten"
                            visible: !!playbackState.sectionActive || !!playbackState.sectionPreparing

                            onClicked: dialog.commandRequested("sectionCancel", {})
                        }
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        value: playbackState.sectionProgress || 0
                        visible: playbackState.sectionPreparing || false
                    }
                    Label {
                        Layout.fillWidth: true
                        color: "#e5503a"
                        text: playbackState.sectionError || ""
                        visible: !!text
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: "A/B beginnt mit dem rekonstruierten Zustand bei A und schließt alle Ticks von B ein. Ausschalten spielt an der aktuellen Stelle weiter. Sprünge oder Audioeinstellungen lösen die Schleife."
                        wrapMode: Text.Wrap
                    }
                }
            }
            GroupBox {
                Layout.fillWidth: true
                title: "Gespeicherte Songstellen"

                ColumnLayout {
                    spacing: 12
                    width: parent.width

                    Label {
                        color: secondary
                        text: "Noch keine Songstellen für diesen Titel."
                        visible: !(moduleInfo.markers || []).length
                    }
                    Repeater {
                        objectName: "markerEntries"
                        model: moduleInfo.markers || []

                        ColumnLayout {
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 6

                            FormButton {
                                Layout.fillWidth: true
                                flat: true
                                objectName: "editMarker"
                                text: modelData.name + "   " + addressText(modelData.address)

                                onClicked: {
                                    dialog.editingID = modelData.id;
                                    markerName.text = modelData.name;
                                    markerPosition.value = modelData.address.position + 1;
                                    markerRow.value = modelData.address.row;
                                }
                            }
                            RowLayout {
                                FormButton {
                                    text: "Springen"

                                    onClicked: dialog.commandRequested("seek", {
                                        index: modelData.address.position,
                                        row: modelData.address.row
                                    })
                                }
                                FormButton {
                                    text: "Löschen"

                                    onClicked: dialog.commandRequested("markerDelete", {
                                        id: modelData.id
                                    })
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                color: Qt.alpha(secondary, .2)
                                height: 1
                            }
                        }
                    }
                }
            }
        }
    }
}
