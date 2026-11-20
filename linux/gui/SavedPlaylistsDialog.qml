import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog

    required property color secondary
    required property var send
    required property var library
    required property real fontScale
    required property real confirmationWidth
    property string playlistID: ""
    property var selectedPlaylist: (library.playlists || []).find(p => p.id === playlistID) || ({ tracks: [] })


    anchors.centerIn: parent
    font.pixelSize: 13
    modal: true
    standardButtons: Dialog.Close
    title: "Gespeicherte Playlists"

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label {
            Layout.fillWidth: true
            color: secondary
            text: "Die Listen verweisen auf Originaldateien und Archive. Musikdateien werden nicht dauerhaft kopiert."
            wrapMode: Text.Wrap
        }
        SplitView {
            Layout.fillHeight: true
            Layout.fillWidth: true

            ListView {
                SplitView.preferredWidth: 210
                clip: true
                model: library.playlists || []

                delegate: ItemDelegate {
                    required property var modelData

                    highlighted: playlistID === modelData.id
                    text: modelData.name + "\n" + modelData.tracks.length + " Titel"
                    width: ListView.view.width

                    onClicked: {
                        playlistID = modelData.id;
                        newPlaylistName.text = modelData.name;
                    }
                }
            }
            ColumnLayout {
                Layout.leftMargin: 8
                SplitView.fillWidth: true

                Label {
                    font.bold: true
                    text: selectedPlaylist.name || "Eine Playlist auswählen."
                }
                ListView {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    clip: true
                    model: selectedPlaylist.tracks

                    delegate: RowLayout {
                        required property int index
                        required property var modelData

                        height: 44
                        width: ListView.view.width

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: modelData.displayName
                        }
                        FormButton {
                            enabled: index > 0
                            text: "↑"

                            onClicked: send("playlistTrackMove", {
                                playlist: playlistID,
                                text: modelData.id,
                                index: -1
                            })
                        }
                        FormButton {
                            enabled: index < selectedPlaylist.tracks.length - 1
                            text: "↓"

                            onClicked: send("playlistTrackMove", {
                                playlist: playlistID,
                                text: modelData.id,
                                index: 1
                            })
                        }
                        FormButton {
                            text: "−"

                            onClicked: send("playlistTrackRemove", {
                                playlist: playlistID,
                                text: modelData.id
                            })
                        }
                    }
                }
                RowLayout {
                    FormButton {
                        enabled: selectedPlaylist.tracks.length > 0
                        text: "Playlist öffnen"

                        onClicked: {
                            send("playlistOpen", {
                                text: playlistID
                            });
                            dialog.close();
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    FormButton {
                        enabled: !!playlistID
                        text: "Löschen…"

                        onClicked: deletePlaylist.open()
                    }
                }
            }
        }
        RowLayout {
            TextField {
                id: newPlaylistName

                Layout.fillWidth: true
                placeholderText: "Name der Playlist"
            }
            FormButton {
                enabled: !!playlistID && newPlaylistName.text.trim().length > 0
                text: "Umbenennen"

                onClicked: send("playlistRename", {
                    playlist: playlistID,
                    text: newPlaylistName.text.trim()
                })
            }
            FormButton {
                enabled: newPlaylistName.text.trim().length > 0 && (library.visible || []).length > 0
                text: "Aktuelle Titel speichern (" + (library.visible || []).length + ")"

                onClicked: {
                    send("playlistSave", {
                        text: newPlaylistName.text.trim()
                    });
                    newPlaylistName.clear();
                }
            }
        }
        Label {
            color: secondary
            font.pixelSize: 11 * dialog.fontScale
            text: "Weitere Titel: Rechtsklick auf einen Titel → Zu Playlist hinzufügen."
        }
    }
    Dialog {
        id: deletePlaylist

        parent: dialog.parent
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        title: "Playlist löschen?"
        width: dialog.confirmationWidth

        onAccepted: {
            send("playlistDelete", {
                text: playlistID
            });
            playlistID = "";
            newPlaylistName.clear();
        }

        Label {
            text: "Nur die gespeicherte Liste wird entfernt. Musikdateien bleiben erhalten."
            width: parent.width
            wrapMode: Text.Wrap
        }
    }
}
