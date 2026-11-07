import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: dashboard

    property color accent: "#5cb3c2"
    property bool dark: true
    property string loopMode: "playlist"
    property var module: ({})
    property color primary: "#eceef0"
    property color secondary: "#9ea8b0"
    property var sound: ({})
    property string sourceName: ""
    property var state: ({})
    property real textScale: 1

    signal command(string name, var values)
    signal setting(string name, var value)

    boundsBehavior: Flickable.StopAtBounds
    clip: true
    contentHeight: Math.max(height, card.height + 32)
    contentWidth: width

    ScrollBar.vertical: ScrollBar {
    }

    Rectangle {
        id: card

        border.color: Qt.alpha(secondary, dark ? .16 : .18)
        color: dark ? "#131518" : "#f6f7fa"
        height: content.implicitHeight + 40
        radius: 16
        width: Math.min(720, dashboard.width - 32)
        x: (dashboard.width - width) / 2
        y: Math.max(16, (dashboard.height - height) / 2)

        ColumnLayout {
            id: content

            spacing: 16
            width: card.width - 40
            x: 20
            y: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 18

                Rectangle {
                    Layout.preferredHeight: 84
                    Layout.preferredWidth: 84
                    color: Qt.alpha(accent, dark ? .15 : .1)
                    radius: 42

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 7
                        border.color: Qt.alpha(accent, .32)
                        color: "transparent"
                        radius: width / 2
                    }
                    PlayerIcon {
                        accent: dashboard.accent
                        anchors.centerIn: parent
                        ground: dark ? "#131518" : "#f6f7fa"
                        height: 62
                        name: "discEmblem"
                        width: 62
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        color: accent
                        text: "JETZT LÄUFT"

                        font {
                            bold: true
                            letterSpacing: 1.2
                            pixelSize: 9 * textScale
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        color: primary
                        elide: Text.ElideMiddle
                        maximumLineCount: 2
                        text: module.title || ""
                        wrapMode: Text.Wrap

                        font {
                            bold: true
                            pixelSize: 18 * textScale
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        color: secondary
                        elide: Text.ElideMiddle
                        font.pixelSize: 10 * textScale
                        text: sourceName
                    }
                    Text {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 8 * textScale
                        text: "♧  CPU-SPARMODUS  Pattern und Oszilloskope pausiert"
                        wrapMode: Text.Wrap
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columnSpacing: 10
                columns: Math.max(1, Math.floor((width + 10) / 115))
                rowSpacing: 10

                Repeater {
                    model: [[module.usedChannels || 0, "KANÄLE"], [(module.instruments || []).length, "INSTRUMENTE"], [module.patterns || 0, "PATTERN"], [(module.orders || []).length, "POSITIONEN"]]

                    Rectangle {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(51, stat.implicitHeight + 18)
                        color: dark ? Qt.alpha("#050608", .65) : "#edf0f4"
                        radius: 8

                        Column {
                            id: stat

                            spacing: 3
                            x: 12
                            y: 9

                            Text {
                                color: primary
                                text: modelData[0]

                                font {
                                    bold: true
                                    pixelSize: 16 * textScale
                                }
                            }
                            Text {
                                color: secondary
                                text: modelData[1]

                                font {
                                    bold: true
                                    pixelSize: 8 * textScale
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: channelContent.implicitHeight + 24
                color: dark ? Qt.alpha("#050608", .48) : Qt.alpha("#edf0f4", .72)
                radius: 10

                ColumnLayout {
                    id: channelContent

                    spacing: 7
                    width: parent.width - 24
                    x: 12
                    y: 12

                    Text {
                        color: secondary
                        text: "KANALSTEUERUNG"

                        font {
                            bold: true
                            pixelSize: 8 * textScale
                        }
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: (module.displayChannels || []).length <= 8 ? 18 : (module.displayChannels || []).length <= 24 ? 40 : 76
                        clip: true
                        contentHeight: channelGrid.implicitHeight
                        contentWidth: width

                        ScrollBar.vertical: ScrollBar {
                        }

                        Flow {
                            id: channelGrid

                            spacing: 8
                            width: parent.width

                            Repeater {
                                model: module.displayChannels || []

                                Row {
                                    required property int modelData

                                    height: 18
                                    spacing: 3
                                    width: 52

                                    Text {
                                        color: secondary
                                        horizontalAlignment: Text.AlignRight
                                        text: modelData + 1
                                        width: 16

                                        font {
                                            bold: true
                                            pixelSize: 9
                                        }
                                    }
                                    ChannelTag {
                                        active: (state.muted || [])[modelData] || false
                                        text: "M"

                                        onClicked: dashboard.command("mute", {
                                            index: modelData
                                        })
                                    }
                                    ChannelTag {
                                        active: (state.solo || [])[modelData] || false
                                        text: "S"

                                        onClicked: dashboard.command("solo", {
                                            index: modelData
                                        })
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 16

                Row {
                    height: 28
                    spacing: 14

                    PlayerCheckBox {
                        checked: sound.ledFilterActive || false
                        dark: dashboard.dark
                        text: "LED FILTER"
                        textScale: dashboard.textScale

                        onClicked: dashboard.setting("ledFilterActive", checked)
                    }
                    PlayerCheckBox {
                        checked: sound.useInterpolation !== false
                        dark: dashboard.dark
                        text: "HI-FI INT."
                        textScale: dashboard.textScale

                        onClicked: dashboard.setting("useInterpolation", checked)
                    }
                }
                Row {
                    height: 28
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: secondary
                        font.pixelSize: 9 * textScale
                        text: "LOOP:"
                    }
                    FormCombo {
                        currentIndex: ({
                                playlist: 0,
                                track: 1,
                                none: 2
                            })[loopMode] || 0
                        font.pixelSize: 11
                        model: ["Wiederhole Playlist", "Wiederhole Song", "Einmal abspielen"]
                        width: 167

                        onActivated: dashboard.setting("loop", ["playlist", "track", "none"][currentIndex])
                    }
                }
            }
        }
    }
}
