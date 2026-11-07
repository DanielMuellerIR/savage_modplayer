import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia

ApplicationWindow {
    id: window

    property color accent: dark ? "#5cb3c2" : "#0055b5"
    property color backdrop: dark ? "#050608" : "#edf0f4"
    property bool compact: false
    property string contextTrack: ""
    property bool dark: (prefs.theme || "Dark") !== "Light"
    property string errorMessage: ""
    property var exchange: ({})
    property var expanded: ({})
    property real exportProgress: 0
    property var exportReport: ({})
    property string exportResult: ""
    property string exportTitle: ""
    property bool exporting: false
    property real fontScale: Math.max(0.7, Math.min(1.8, 1 + (prefs.zoom || 0) * 0.13))
    property bool hasModule: !!m.title
    property var indexStatus: ({})
    property var inspection: ({})
    property var instrumentDetails: ({})
    property var library: desktop.library
    property var m: desktop.module
    property string markerRevision: ""
    property bool pendingSamples: false
    property string playlistID: ""
    property var prefs: desktop.preferences
    property color primary: dark ? "#eceef0" : "#13171d"
    property bool queryActive: !!((library.query || {}).search || (library.query || {}).favoritesOnly || (library.query || {}).format || (library.query || {}).minimumChannels || (library.query || {}).unheardOnly || (library.query || {}).addedWithinDays || (library.query || {}).reversed || ((library.query || {}).sort && library.query.sort !== "sourceOrder"))
    property var s: desktop.state
    property var sample: ({})
    property int sampleInstrument: 0
    property color secondary: dark ? "#9ea8b0" : "#576170"
    property var sectionEnd: ({
            position: -1,
            row: 0
        })
    property var sectionStart: ({
            position: -1,
            row: 0
        })
    property var selectedPlaylist: (library.playlists || []).find(p => p.id === playlistID) || ({
            tracks: []
        })
    property string selectedSample: ""
    property int sidebarTab: 0
    property var sound: s.sound || prefs
    property var stableMutes: []
    property color surface: dark ? "#131518" : "#f6f7fa"
    property bool validSection: sectionStart.position >= 0 && sectionEnd.position >= 0 && (sectionEnd.position > sectionStart.position || sectionEnd.position === sectionStart.position && sectionEnd.row >= sectionStart.row)
    property bool videoPreparing: false
    property string videoPreviewPath: ""

    function addressText(a) {
        return a.position < 0 ? "—" : (a.position + 1) + ":" + a.row;
    }
    function changeQuery(key, value) {
        let q = Object.assign({}, library.query || {});
        q[key] = value;
        send("query", {
            query: q
        });
    }
    function option(name, value) {
        desktop.option(name, value);
    }
    function requestSample() {
        send("sample", {
            text: selectedSample,
            index: sampleViewer.zoom,
            value: sampleViewer.position,
            focus: sampleViewer.focusRange || null
        });
    }
    function reviewView(name) {
        if (name !== "signals")
            send("pause");
        send("seek", {
            index: 0,
            row: 0
        });
        if (name === "stopped") {
            send("stop");
            return;
        }
        if (name === "paused") {
            send("pause");
            send("seek", {
                index: 0,
                row: 0
            });
            return;
        }
        if (name === "compact") {
            window.width = 780;
            window.height = 600;
            return;
        }
        if (name === "light") {
            option("theme", "Light");
            return;
        }
        if (name === "zoom") {
            option("zoom", 5);
            return;
        }
        if (name === "timer") {
            timerDialog.open();
            return;
        }
        if (name === "sound") {
            trackSettings.open();
            return;
        }
        if (name === "instruments") {
            sidebarTab = 1;
            return;
        }
        if (name === "settings")
            settings.open();
        else if (name === "filters")
            filters.open();
        else if (name === "markers")
            markers.open();
        else if (name === "module")
            showInspector();
        else if (name === "samples")
            showSamples();
        else if (name === "playlists")
            playlists.open();
        else if (name === "queue")
            queueDialog.open();
        else if (name === "export")
            exportDialog.open();
        else if (name === "batch")
            batchDialog.open();
        else if (name === "video")
            videoDialog.open();
        else if (name === "collection")
            collection.open();
        else if (name === "noteRain") {
            noteWindow.show();
            send("notes", {
                enabled: true
            });
        }
    }
    function send(name, values) {
        desktop.command(name, values || {});
    }
    function showInspector() {
        send("inspect");
        inspector.open();
    }
    function showSample(id, instrument) {
        selectedSample = id;
        sampleInstrument = instrument;
        sampleViewer.zoom = 1;
        sampleViewer.position = 0;
        sampleViewer.focusRange = "";
        send("sample", {
            text: id,
            index: 1
        });
        sampleDialog.open();
    }
    function showSamples() {
        pendingSamples = true;
        send("inspect");
    }
    function time(seconds) {
        seconds = Math.max(0, Math.floor(seconds || 0));
        return Math.floor(seconds / 60).toString().padStart(2, "0") + ":" + (seconds % 60).toString().padStart(2, "0");
    }
    function treeRows() {
        let tracks = library.tracks || [], visible = library.visible || [], q = library.query || {};
        if (queryActive) {
            let byID = new Map(tracks.map(t => [t.id, t]));
            return visible.map(id => byID.get(id)).filter(t => !!t);
        }
        let root = {
            children: [],
            tracks: []
        };
        for (let t of tracks) {
            let node = root, path = "";
            for (let name of t.folders || []) {
                path += "/" + name;
                let child = node.children.find(c => c.path === path);
                if (!child) {
                    child = {
                        name: name,
                        path: path,
                        children: [],
                        tracks: []
                    };
                    node.children.push(child);
                }
                node = child;
            }
            node.tracks.push(t);
        }
        let result = [];
        function walk(node, depth) {
            for (let child of node.children) {
                let folder = child.path.substring(1);
                let containsCurrent = tracks.some(t => t.id === library.currentID && ((t.folders || []).join("/") === folder || (t.folders || []).join("/").startsWith(folder + "/")));
                let open = expanded[child.path] === undefined ? containsCurrent : expanded[child.path];
                result.push({
                    name: child.name,
                    folder: true,
                    id: child.path,
                    depth: depth,
                    expanded: open
                });
                if (open)
                    walk(child, depth + 1);
            }
            for (let t of node.tracks)
                result.push(Object.assign({
                    depth: depth
                }, t));
        }
        walk(root, 0);
        return result;
    }
    function updateCompact() {
        let next = compact ? !(window.width >= 900 && main.height >= 640) : window.width < 820 || main.height < 560;
        if (next !== compact) {
            compact = next;
            send("compact", {
                enabled: compact
            });
        }
    }

    color: backdrop
    font.family: "sans-serif"
    font.pixelSize: 11 * window.fontScale
    height: 900
    minimumHeight: 560
    minimumWidth: 760
    palette.base: backdrop
    palette.button: surface
    palette.buttonText: primary
    palette.dark: dark ? "#050608" : "#c8d0db"
    palette.highlight: accent
    palette.highlightedText: dark ? "#050608" : "white"
    palette.light: dark ? "#25363b" : "#ffffff"
    palette.mid: dark ? "#29424a" : "#c8d0db"
    palette.text: primary
    palette.window: surface
    palette.windowText: primary
    title: "Savage Mod Player"
    visible: true
    width: 1440

    menuBar: MenuBar {
        font.pixelSize: 13

        Menu {
            title: "Datei"

            MenuItem {
                text: "Öffnen…"

                onTriggered: desktop.open()

                Shortcut {
                    sequences: [StandardKey.Open]

                    onActivated: desktop.open()
                }
            }
            MenuItem {
                text: "Ordner öffnen…"

                onTriggered: desktop.open(true)
            }
            MenuSeparator {}
            MenuItem {
                text: "Einstellungen…"

                onTriggered: settings.open()
            }
            MenuItem {
                text: "Beenden"

                onTriggered: window.close()
            }
        }
        Menu {
            title: "Wiedergabe"

            MenuItem {
                text: "Abspielen / Pause"

                onTriggered: send("play")
            }
            MenuItem {
                text: "Stopp"

                onTriggered: send("stop")
            }
            MenuItem {
                text: "Vorheriger Titel"

                onTriggered: send("previous")
            }
            MenuItem {
                text: "Nächster Titel"

                onTriggered: send("next")
            }
            MenuSeparator {}
            MenuItem {
                enabled: hasModule
                text: "Songstellen und A/B…"

                onTriggered: markers.open()
            }
            MenuItem {
                text: "Einschlaftimer…"

                onTriggered: timerDialog.open()
            }
        }
        Menu {
            title: "Darstellung"

            MenuItem {
                text: "Notenregen öffnen"

                onTriggered: {
                    noteWindow.show();
                    send("notes", {
                        enabled: true
                    });
                }
            }
            MenuItem {
                text: "Größere Schrift"

                onTriggered: option("zoom", Math.min(5, (prefs.zoom || 0) + 1))
            }
            MenuItem {
                text: "Kleinere Schrift"

                onTriggered: option("zoom", Math.max(-3, (prefs.zoom || 0) - 1))
            }
            MenuItem {
                text: "Standard-Schriftgröße"

                onTriggered: option("zoom", 0)
            }
        }
        Menu {
            title: "Sammlung"

            MenuItem {
                text: "Playlists…"

                onTriggered: playlists.open()
            }
            MenuItem {
                text: "Als Nächstes…"

                onTriggered: queueDialog.open()
            }
            MenuItem {
                text: "Sammlung übertragen…"

                onTriggered: collection.open()
            }
            MenuItem {
                text: "Sammlung abgleichen…"

                onTriggered: syncDialog.open()
            }
        }
        Menu {
            title: "Export"

            MenuItem {
                enabled: hasModule
                text: "Stereo-Mix oder Kanalspuren…"

                onTriggered: exportDialog.open()
            }
            MenuItem {
                enabled: (library.tracks || []).length > 0
                text: "WAV-Stapelexport…"

                onTriggered: batchDialog.open()
            }
            MenuItem {
                enabled: hasModule
                text: "Notenregen als Video…"

                onTriggered: videoDialog.open()
            }
        }
        Menu {
            title: "Hilfe"

            MenuItem {
                text: "Tastenkürzel"

                onTriggered: keyboardDialog.open()
            }
            MenuItem {
                text: "Über Savage Mod Player"

                onTriggered: aboutDialog.open()
            }
        }
    }

    onSectionEndChanged: if (s.sectionActive || s.sectionPreparing)
        send("sectionCancel")
    onSectionStartChanged: if (s.sectionActive || s.sectionPreparing)
        send("sectionCancel")

    Connections {
        function onMessage(event, values) {
            if (event === "loading" && values.active) {
                expanded = {};
                sidebarTab = 0;
            } else if (event === "state") {
                if (JSON.stringify(stableMutes) !== JSON.stringify(values.muted))
                    stableMutes = values.muted;
            } else if (event === "error" || event === "notice") {
                errorMessage = values.message;
                errorDialog.open();
                exporting = false;
            } else if (event === "module") {
                if (markerRevision && markerRevision !== values.revision) {
                    markers.close();
                    sectionStart = {
                        position: -1,
                        row: 0
                    };
                    sectionEnd = {
                        position: -1,
                        row: 0
                    };
                }
                markerRevision = values.revision;
            } else if (event === "inspection") {
                inspection = values;
                if (pendingSamples) {
                    pendingSamples = false;
                    let first = (values.samples || [])[0];
                    if (first)
                        showSample(first.id, 0);
                    else
                        sampleDialog.open();
                }
                if ((values.instruments || []).length)
                    send("instrument", {
                        index: values.instruments[0].index
                    });
            } else if (event === "instrument")
                instrumentDetails = values;
            else if (event === "sampleExportPrepared") {
                let path = desktop.saveFile("Instrumenten-Sample als WAV sichern", values.name.replace(/[\/: ]/g, "_") + ".wav", "WAV (*.wav)", true);
                if (path)
                    send("sampleExport", {
                        path: path,
                        token: values.token,
                        overwrite: desktop.overwriteApproved(path)
                    });
                else
                    send("sampleExportCancel");
            } else if (event === "sample")
                sample = values;
            else if (event === "collectionPreview") {
                exchange = values;
                exchangeDialog.open();
            } else if (event === "collectionApplied") {
                exchangeDialog.close();
                collection.close();
            } else if (event === "exportPrepared")
                exportTitle = values.title;
            else if (event === "videoPreviewState")
                videoPreparing = values.active;
            else if (event === "videoPreview") {
                videoPreviewPath = values.path;
                exporting = false;
            } else if (event === "cancelled") {
                exporting = false;
                videoPreparing = false;
            } else if (event === "indexing")
                indexStatus = values;
            else if (event === "progress") {
                exportProgress = values.value;
                exporting = true;
            } else if (event === "complete") {
                exporting = false;
                exportProgress = 1;
                exportResult = values.path;
                exportReport = values.report || {};
            }
        }

        target: desktop
    }
    Shortcut {
        sequence: "Ctrl+,"

        onActivated: settings.open()
    }
    Shortcut {
        sequence: "Ctrl+Shift+N"

        onActivated: {
            noteWindow.show();
            send("notes", {
                enabled: true
            });
        }
    }
    Shortcut {
        sequence: "Ctrl++"

        onActivated: option("zoom", Math.min(5, (prefs.zoom || 0) + 1))
    }
    Shortcut {
        sequence: "Ctrl+-"

        onActivated: option("zoom", Math.max(-3, (prefs.zoom || 0) - 1))
    }
    Shortcut {
        sequence: "Ctrl+0"

        onActivated: option("zoom", 0)
    }
    Shortcut {
        sequence: "Ctrl+F"

        onActivated: search.forceActiveFocus()
    }
    Shortcut {
        sequence: "Ctrl+P"

        onActivated: send("play")
    }
    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space) {
                send("play");
                event.accepted = true;
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                send("previous");
                event.accepted = true;
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                send("next");
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                search.focus = false;
                event.accepted = true;
            }
        }

        SplitView {
            id: split

            anchors.fill: parent
            orientation: Qt.Horizontal

            handle: Rectangle {
                color: dark ? "#29424a" : "#c8d0db"
                implicitWidth: 1
            }

            Rectangle {
                id: sidebar

                SplitView.maximumWidth: Math.min(640, window.width - 521)
                SplitView.minimumWidth: 220
                SplitView.preferredWidth: prefs.sidebarWidth || 260
                color: surface

                onWidthChanged: if (split.resizing)
                    sidebarSave.restart()

                Timer {
                    id: sidebarSave

                    interval: 500

                    onTriggered: option("sidebarWidth", sidebar.width)
                }
                ColumnLayout {
                    anchors.fill: parent
                    objectName: "sidebarLayout"
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        color: "transparent"

                        RowLayout {
                            spacing: 4

                            anchors {
                                left: parent.left
                                margins: 16
                                right: parent.right
                                top: parent.top
                                topMargin: 10
                            }
                            PlayerButton {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                accent: window.accent
                                active: sidebarTab === 0
                                dark: window.dark
                                text: "PLAYLIST"
                                textScale: window.fontScale

                                onClicked: sidebarTab = 0
                            }
                            PlayerButton {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                accent: window.accent
                                active: sidebarTab === 1
                                dark: window.dark
                                text: "INSTRUMENTE"
                                textScale: window.fontScale

                                onClicked: sidebarTab = 1
                            }
                        }
                    }
                    RowLayout {
                        Layout.bottomMargin: 6
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        spacing: 4
                        visible: sidebarTab === 0

                        PlayerButton {
                            dark: window.dark
                            text: "Playlists…"
                            textScale: window.fontScale

                            onClicked: playlists.open()
                        }
                        PlayerButton {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            dark: window.dark
                            text: "Als Nächstes (" + (library.queue || []).length + ")"
                            textScale: window.fontScale

                            onClicked: queueDialog.open()
                        }
                    }
                    TextField {
                        id: search

                        Layout.bottomMargin: 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.preferredHeight: 28
                        Layout.rightMargin: 8
                        color: primary
                        font.pixelSize: 12 * window.fontScale
                        placeholderText: "⌕  Datei oder Metadaten…"
                        selectByMouse: true
                        text: (library.query || {}).search || ""
                        visible: sidebarTab === 0

                        background: Rectangle {
                            border.color: search.activeFocus ? accent : "transparent"
                            color: backdrop
                            radius: dark ? 6 : 0
                        }

                        onTextEdited: changeQuery("search", text)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 6
                        visible: sidebarTab === 0

                        FormButton {
                            flat: true
                            font.pixelSize: 11 * window.fontScale
                            implicitHeight: 14
                            padding: 0
                            text: "Anzeige und Filter…"

                            onClicked: filters.open()
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: indexStatus.active || false

                            Label {
                                Layout.fillWidth: true
                                color: secondary
                                font.pixelSize: 10 * window.fontScale
                                text: (indexStatus.completed || 0) + " / " + (indexStatus.total || 0) + " indiziert"
                            }
                            FormButton {
                                text: "Abbrechen"

                                onClicked: send("indexCancel")
                            }
                        }
                        FormButton {
                            enabled: hasModule
                            flat: true
                            font.pixelSize: 11 * window.fontScale
                            implicitHeight: 14
                            padding: 0
                            text: "♧  Songstellen…"

                            onClicked: markers.open()
                        }
                        FormButton {
                            enabled: (library.visible || []).length > 0
                            flat: true
                            font.pixelSize: 11 * window.fontScale
                            implicitHeight: 14
                            padding: 0
                            text: "Stapel-Export … (" + (library.visible || []).length + ")"

                            onClicked: batchDialog.open()
                        }
                    }
                    RowLayout {
                        Layout.bottomMargin: 6
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 8
                        Layout.topMargin: 6
                        visible: sidebarTab === 0

                        Text {
                            Layout.fillWidth: true
                            color: secondary
                            text: "TITEL (" + (library.visible || []).length + ")"

                            font {
                                bold: true
                                pixelSize: 11 * window.fontScale
                            }
                        }
                        PlayerButton {
                            active: (library.query || {}).favoritesOnly || false
                            dark: window.dark
                            hint: "Nur Favoriten"
                            text: "★"

                            onClicked: changeQuery("favoritesOnly", !((library.query || {}).favoritesOnly))
                        }
                        PlayerButton {
                            dark: window.dark
                            text: "Leeren"
                            textScale: window.fontScale

                            onClicked: send("clear")
                        }
                    }
                    RowLayout {
                        Layout.bottomMargin: 6
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        visible: sidebarTab === 0 && queryActive

                        PlayerButton {
                            dark: window.dark
                            text: "Diese Ergebnisse abspielen"

                            onClicked: send("selection", {
                                ids: library.visible || []
                            })
                        }
                        PlayerButton {
                            dark: window.dark
                            text: "Alle"

                            onClicked: send("selection")
                        }
                    }
                    ListView {
                        id: tracks

                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        Layout.minimumHeight: 80
                        Layout.preferredHeight: 1
                        clip: true
                        model: treeRows()
                        objectName: "playlistList"
                        visible: sidebarTab === 0

                        ScrollBar.vertical: ScrollBar {}
                        delegate: ItemDelegate {
                            id: track

                            required property var modelData

                            height: modelData.folder ? 32 : (modelData.metadata && modelData.metadata.metadata ? 48 : 38)
                            highlighted: modelData.id === library.currentID
                            width: tracks.width

                            background: Rectangle {
                                anchors.fill: parent
                                color: track.highlighted ? Qt.alpha(accent, 0.15) : (track.hovered ? Qt.alpha(accent, 0.06) : "transparent")
                                radius: dark ? 6 : 0
                            }
                            contentItem: RowLayout {
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: (track.modelData.depth || 0) * 12
                                }
                                Text {
                                    color: track.highlighted ? accent : secondary
                                    font.pixelSize: 13
                                    text: track.modelData.folder ? (track.modelData.expanded ? "▾" : "▸") : (track.highlighted ? "♫" : "♪")
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        color: track.highlighted ? primary : secondary
                                        elide: Text.ElideMiddle
                                        text: track.modelData.name

                                        font {
                                            pixelSize: 11 * window.fontScale
                                            weight: track.highlighted ? Font.Bold : Font.Medium
                                        }
                                    }
                                    Text {
                                        property var meta: track.modelData.metadata ? track.modelData.metadata.metadata : null

                                        Layout.fillWidth: true
                                        color: secondary
                                        elide: Text.ElideRight
                                        font.pixelSize: 9 * window.fontScale
                                        text: meta ? (meta.format.toUpperCase() + " · " + meta.channelCount + "ch · " + time(meta.durationSeconds) + " · " + meta.title) : ""
                                        visible: !!meta
                                    }
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "Sammlung übertragen"
                                    implicitWidth: 28
                                    text: "↕"

                                    onClicked: collection.open()
                                }
                                PlayerButton {
                                    dark: window.dark
                                    implicitWidth: 28
                                    text: track.modelData.favorite ? "★" : "☆"
                                    visible: !track.modelData.folder

                                    onClicked: send("favorite", {
                                        text: track.modelData.id
                                    })
                                }
                            }

                            onClicked: {
                                if (modelData.folder) {
                                    let e = Object.assign({}, expanded);
                                    e[modelData.id] = !modelData.expanded;
                                    expanded = e;
                                } else
                                    send("load", {
                                        text: modelData.id
                                    });
                            }

                            MouseArea {
                                acceptedButtons: Qt.RightButton
                                anchors.fill: parent

                                onClicked: {
                                    contextTrack = track.modelData.id;
                                    if (!track.modelData.folder)
                                        trackMenu.popup();
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: 12
                        spacing: 6
                        visible: sidebarTab === 1

                        PlayerButton {
                            dark: window.dark
                            enabled: hasModule
                            text: "Modul-Inspektor…"

                            onClicked: showInspector()
                        }
                        PlayerButton {
                            dark: window.dark
                            enabled: hasModule
                            text: "Sample-Inspektor…"

                            onClicked: showSamples()
                        }
                        PlayerButton {
                            dark: window.dark
                            enabled: !!m.sourceID
                            text: "Songstellen…"

                            onClicked: markers.open()
                        }
                    }
                    ListView {
                        id: instruments

                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        clip: true
                        model: (m.instruments || []).filter(i => i.playable)
                        visible: sidebarTab === 1

                        ScrollBar.vertical: ScrollBar {}
                        delegate: ItemDelegate {
                            required property var modelData

                            height: 62 * window.fontScale
                            width: instruments.width

                            contentItem: RowLayout {
                                spacing: 6

                                Label {
                                    color: accent
                                    text: modelData.index.toString().padStart(2, "0")

                                    font {
                                        family: "monospace"
                                        pixelSize: 11 * window.fontScale
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: modelData.name

                                        font {
                                            bold: true
                                            pixelSize: 11 * window.fontScale
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        color: Qt.alpha(accent, .15)
                                        height: 3

                                        Rectangle {
                                            color: accent
                                            height: 3
                                            width: parent.width * Math.min(1, modelData.frames / 65536)
                                        }
                                    }
                                    Label {
                                        color: secondary
                                        text: "LEN " + modelData.frames + "  FT " + modelData.finetune + "  VOL " + modelData.volume + (modelData.looped ? "  LOOP" : "")

                                        font {
                                            family: "monospace"
                                            pixelSize: 8 * window.fontScale
                                        }
                                    }
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "Sample als WAV exportieren"
                                    iconName: "download"
                                    text: "↓"

                                    onClicked: send("prepareSampleExport", {
                                        index: modelData.index,
                                        revision: m.revision
                                    })
                                }
                            }

                            onClicked: send("preview", {
                                index: modelData.index
                            })
                        }

                        Label {
                            anchors.centerIn: parent
                            color: secondary
                            text: hasModule ? "Keine spielbaren Instrumente" : "Kein Modul geladen"
                            visible: instruments.count === 0
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        visible: sidebarTab === 0

                        Rectangle {
                            color: Qt.alpha(secondary, .22)
                            height: 1

                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            property real startHeight: 96
                            property real startY: 0

                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor

                            onPositionChanged: mouse => {
                                if (pressed)
                                    option("recentHeight", Math.max(48, Math.min(360, startHeight - (mapToGlobal(mouse.x, mouse.y).y - startY))));
                            }
                            onPressed: mouse => {
                                startY = mapToGlobal(mouse.x, mouse.y).y;
                                startHeight = prefs.recentHeight || 96;
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillHeight: false
                        Layout.fillWidth: true
                        Layout.margins: 12
                        Layout.maximumHeight: prefs.recentHeight || 96
                        Layout.preferredHeight: prefs.recentHeight || 96
                        objectName: "recentSection"
                        spacing: 6
                        visible: sidebarTab === 0

                        Text {
                            color: secondary
                            text: "ZULETZT GESPIELT"

                            font {
                                bold: true
                                pixelSize: 9 * window.fontScale
                            }
                        }
                        ListView {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            clip: true
                            model: library.recent || []
                            objectName: "recentList"

                            delegate: ItemDelegate {
                                required property var modelData

                                font.pixelSize: 12 * window.fontScale
                                height: Math.max(20, 16 * window.fontScale + 4)
                                leftPadding: 8
                                padding: 0
                                rightPadding: 8
                                text: modelData.name
                                width: ListView.view.width

                                contentItem: Text {
                                    color: primary
                                    elide: Text.ElideRight
                                    font.pixelSize: 12 * window.fontScale
                                    text: parent.text
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: send("recentLoad", {
                                    text: modelData.id
                                })
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: main

                SplitView.fillWidth: true
                color: backdrop

                onHeightChanged: updateCompact()
                onWidthChanged: updateCompact()

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70 + Math.max(0, window.fontScale - 1) * 36
                        color: dark ? "#0a0c0e" : surface

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: compact ? 12 : 16
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: compact ? 8 : 16

                                Rectangle {
                                    Layout.preferredHeight: 16
                                    Layout.preferredWidth: badge.implicitWidth + 8
                                    color: accent
                                    radius: dark ? 3 : 0

                                    Text {
                                        id: badge

                                        anchors.centerIn: parent
                                        color: dark ? "black" : "white"
                                        text: ({
                                                xm: "FASTTRACKER II",
                                                it: "IMPULSE TRACKER",
                                                s3m: "S3M",
                                                multichannel: "MULTICHANNEL",
                                                soundtracker: "SOUNDTRACKER"
                                            })[m.format] || "PROTRACKER"

                                        font {
                                            bold: true
                                            pixelSize: 8 * window.fontScale
                                        }
                                    }
                                }
                                MarqueeLabel {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24 * window.fontScale
                                    bold: !dark || compact
                                    ink: dark ? "white" : accent
                                    pointSize: (compact ? 16 : (dark ? 17 : 20)) * window.fontScale
                                    text: m.title || "Kein Song geladen"
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "Einschlaftimer"
                                    text: s.timerActive ? time(s.timerSeconds) : "◷ Timer"
                                    textScale: window.fontScale

                                    onClicked: timerDialog.open()
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "Klang für diesen Titel"
                                    text: "☷ Klang"

                                    onClicked: trackSettings.open()
                                }
                                RowLayout {
                                    spacing: 4

                                    PlayerButton {
                                        active: !dark
                                        dark: window.dark
                                        text: "LIGHT"
                                        textScale: window.fontScale
                                        visible: !compact || dark

                                        onClicked: option("theme", "Light")
                                    }
                                    PlayerButton {
                                        active: dark
                                        dark: window.dark
                                        text: "DARK"
                                        textScale: window.fontScale
                                        visible: !compact || !dark

                                        onClicked: option("theme", "Dark")
                                    }
                                }
                                PlayerButton {
                                    accentFill: true
                                    dark: window.dark
                                    hint: "Module, Ordner oder Archive öffnen"
                                    text: "♧ ÖFFNEN"
                                    textScale: window.fontScale

                                    onClicked: desktop.open()
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: "☷  CH: " + (m.usedChannels || 0)
                                    visible: hasModule
                                }
                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: "♩  BPM: " + (s.bpm || 125)
                                }
                                PlayerButton {
                                    dark: window.dark
                                    implicitHeight: 16
                                    implicitWidth: 16
                                    text: "−"
                                    visible: !compact

                                    onClicked: send("bpm", {
                                        index: (s.bpm || 125) - 1
                                    })
                                }
                                PlayerButton {
                                    dark: window.dark
                                    implicitHeight: 16
                                    implicitWidth: 16
                                    text: "+"
                                    visible: !compact

                                    onClicked: send("bpm", {
                                        index: (s.bpm || 125) + 1
                                    })
                                }
                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: "◴  SPD: " + (s.speed || 6)
                                }
                                PlayerButton {
                                    dark: window.dark
                                    implicitHeight: 16
                                    implicitWidth: 16
                                    text: "−"
                                    visible: !compact

                                    onClicked: send("speed", {
                                        index: (s.speed || 6) - 1
                                    })
                                }
                                PlayerButton {
                                    dark: window.dark
                                    implicitHeight: 16
                                    implicitWidth: 16
                                    text: "+"
                                    visible: !compact

                                    onClicked: send("speed", {
                                        index: (s.speed || 6) + 1
                                    })
                                }
                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: "☷  PAT: " + ((s.position || 0) + 1) + "/" + (m.orders || []).length
                                    visible: hasModule
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.margins: 6
                        color: "#cf922b"
                        text: "⚠ " + (m.warnings || []).join(" · ")
                        visible: (m.warnings || []).length > 0
                        wrapMode: Text.Wrap
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        color: Qt.alpha(accent, 0.15)
                        height: 1
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 39
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        contentWidth: orderRow.width + 32
                        visible: !compact && hasModule

                        Row {
                            id: orderRow

                            spacing: 4
                            x: 16
                            y: 5

                            Repeater {
                                model: m.orders || []

                                PlayerButton {
                                    required property int index
                                    required property var modelData

                                    active: s.position === index
                                    dark: window.dark
                                    implicitHeight: 26
                                    implicitWidth: 24
                                    text: index.toString().padStart(2, "0") + "\nP" + modelData
                                    textScale: 0.82

                                    onClicked: send("seek", {
                                        index: index
                                    })

                                    Rectangle {
                                        anchors.fill: parent
                                        border.color: validSection && index >= sectionStart.position && index <= sectionEnd.position ? accent : "transparent"
                                        border.width: 1
                                        color: validSection && index >= sectionStart.position && index <= sectionEnd.position ? Qt.alpha(accent, .12) : "transparent"
                                        radius: dark ? 4 : 0
                                    }
                                    Rectangle {
                                        color: accent
                                        height: 4
                                        radius: 2
                                        visible: (m.markers || []).some(v => v.address.position === index)
                                        width: 4

                                        anchors {
                                            bottom: parent.bottom
                                            margins: 2
                                            right: parent.right
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 142 + Math.max(0, window.fontScale - 1) * 8
                        color: dark ? "#080a0b" : backdrop
                        visible: !compact

                        Rectangle {
                            anchors.bottomMargin: 12
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 12
                            color: dark ? "#0b0d0f" : surface
                            radius: dark ? 8 : 0

                            ColumnLayout {
                                anchors.bottomMargin: 8
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                anchors.topMargin: 8
                                spacing: 8

                                Flickable {
                                    id: channelScroller

                                    Layout.fillHeight: false
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 70
                                    Layout.preferredHeight: 70
                                    clip: true
                                    contentWidth: Math.max(width, channelsRow.width)
                                    objectName: "channelScopes"

                                    ScrollBar.horizontal: ScrollBar {}

                                    Row {
                                        id: channelsRow

                                        spacing: (m.displayChannels || []).length > 8 ? 6 : 12

                                        Repeater {
                                            model: m.displayChannels || [0, 1, 2, 3]

                                            Column {
                                                required property var modelData
                                                property real vuWidth: Math.min(24, Math.max(6, width * 0.2))

                                                spacing: 4
                                                width: Math.max(26, (channelScroller.width - parent.spacing * ((m.displayChannels || [0, 1, 2, 3]).length - 1)) / Math.max(1, (m.displayChannels || [0, 1, 2, 3]).length))

                                                Row {
                                                    spacing: 4

                                                    Column {
                                                        spacing: 2
                                                        y: 2

                                                        Repeater {
                                                            model: 12

                                                            Rectangle {
                                                                required property int index
                                                                property real threshold: (11 - index) / 12

                                                                color: ((s.vu || [])[parent.parent.parent.modelData] || 0) >= threshold ? (threshold > .85 ? "#ff3b30" : threshold > .65 ? "#ff9500" : threshold > .4 ? (dark ? "#9eb3c2" : accent) : (dark ? accent : Qt.alpha(accent, .65))) : (dark ? Qt.rgba(1, 1, 1, .04) : Qt.rgba(0, 0, 0, .07))
                                                                height: 2
                                                                radius: 1
                                                                width: parent.parent.parent.vuWidth
                                                            }
                                                        }
                                                    }
                                                    ScopeView {
                                                        accent: window.accent
                                                        dark: window.dark
                                                        height: 50
                                                        samples: (s.waves || [])[parent.parent.modelData] || []
                                                        width: parent.parent.width - parent.parent.vuWidth - 4
                                                    }
                                                }
                                                Row {
                                                    spacing: 3

                                                    Text {
                                                        color: secondary
                                                        text: modelData + 1
                                                        width: 12

                                                        font {
                                                            bold: true
                                                            pixelSize: 8
                                                        }
                                                    }
                                                    ChannelTag {
                                                        active: (s.muted || [])[modelData] || false
                                                        text: "M"

                                                        onClicked: send("mute", {
                                                            index: modelData
                                                        })
                                                    }
                                                    ChannelTag {
                                                        active: (s.solo || [])[modelData] || false
                                                        text: "S"

                                                        onClicked: send("solo", {
                                                            index: modelData
                                                        })
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16

                                    PlayerCheckBox {
                                        checked: sound.ledFilterActive || false
                                        dark: window.dark
                                        font.pixelSize: 9 * window.fontScale
                                        text: "LED FILTER"
                                        textScale: window.fontScale

                                        onClicked: option("ledFilterActive", checked)
                                    }
                                    PlayerCheckBox {
                                        checked: sound.useInterpolation !== false
                                        dark: window.dark
                                        font.pixelSize: 9 * window.fontScale
                                        text: "HI-FI INT."
                                        textScale: window.fontScale

                                        onClicked: option("useInterpolation", checked)
                                    }
                                    Text {
                                        color: secondary
                                        font.pixelSize: 9 * window.fontScale
                                        text: "LOOP:"
                                    }
                                    FormCombo {
                                        currentIndex: ({
                                                playlist: 0,
                                                track: 1,
                                                none: 2
                                            })[prefs.loop || "playlist"]
                                        font.pixelSize: 11 * window.fontScale
                                        implicitContentWidthPolicy: ComboBox.WidestText
                                        implicitHeight: 24
                                        model: ["Wiederhole Playlist", "Wiederhole Song", "Einmal abspielen"]

                                        onActivated: option("loop", ["playlist", "track", "none"][currentIndex])
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        Layout.fillHeight: true
                        Layout.fillWidth: true

                        TrackerView {
                            accent: window.accent
                            anchors.fill: parent
                            anchors.margins: 16
                            channels: m.displayChannels || [0, 1, 2, 3]
                            currentRow: s.row || 0
                            dark: window.dark
                            markerRows: (m.markers || []).filter(v => v.address.position === s.position).map(v => v.address.row)
                            muted: stableMutes
                            pattern: desktop.pattern
                            sectionEndRow: validSection ? (s.position === sectionEnd.position ? sectionEnd.row : 1024) : -1
                            sectionStartRow: validSection && s.position >= sectionStart.position && s.position <= sectionEnd.position ? (s.position === sectionStart.position ? sectionStart.row : 0) : -1
                            visible: !compact && hasModule

                            onBoundary: (start, row) => {
                                if (start)
                                    sectionStart = {
                                        position: s.position || 0,
                                        row: row
                                    };
                                else
                                    sectionEnd = {
                                        position: s.position || 0,
                                        row: row
                                    };
                            }
                            onSeek: row => send("seek", {
                                    index: s.position || 0,
                                    row: row
                                })
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 20
                            visible: !hasModule

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                color: accent
                                font.pixelSize: 80
                                text: "◉"
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                color: primary
                                text: "PROTRACKER MOD PLAYER"

                                font {
                                    bold: true
                                    letterSpacing: dark ? 2 : 0
                                    pixelSize: (dark ? 18 : 16) * window.fontScale
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                color: secondary
                                font.pixelSize: 13
                                text: "Ziehe Modul-Dateien oder Ordner direkt in dieses Fenster"
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 12

                                PlayerButton {
                                    accentFill: true
                                    dark: window.dark
                                    implicitHeight: 36
                                    text: "DATEIEN AUSWÄHLEN"

                                    onClicked: desktop.open()
                                }
                                PlayerButton {
                                    accent: "#34c759"
                                    accentFill: true
                                    dark: window.dark
                                    implicitHeight: 36
                                    text: "DEMO ABSPIELEN"

                                    onClicked: send("demo")
                                }
                            }
                        }
                        CompactDashboard {
                            accent: window.accent
                            anchors.fill: parent
                            dark: window.dark
                            loopMode: prefs.loop || "playlist"
                            module: m
                            primary: window.primary
                            secondary: window.secondary
                            sound: window.sound
                            sourceName: ((library.tracks || []).find(t => t.id === m.sourceID) || {}).name || m.title || ""
                            state: s
                            textScale: window.fontScale
                            visible: compact && hasModule

                            onCommand: (name, values) => send(name, values)
                            onSetting: (name, value) => option(name, value)
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        color: dark ? "#080a0b" : surface
                        visible: !compact

                        RowLayout {
                            anchors.bottomMargin: 10
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.topMargin: 10
                            spacing: 16

                            Text {
                                Layout.preferredWidth: 140
                                color: secondary
                                text: "MASTER OSCILLOSCOPE"
                                wrapMode: Text.Wrap

                                font {
                                    bold: true
                                    pixelSize: 10 * window.fontScale
                                }
                            }
                            ScopeView {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                accent: window.accent
                                dark: window.dark
                                master: true
                                samples: s.master || []
                            }
                            Text {
                                color: secondary
                                text: "↔"
                            }
                            PlayerSlider {
                                Layout.preferredWidth: 80
                                dark: window.dark
                                from: 0
                                to: 1
                                value: sound.stereoSeparation === undefined ? 0.8 : sound.stereoSeparation

                                onMoved: option("stereoSeparation", value)
                            }
                            Text {
                                color: secondary
                                font.pixelSize: 10 * window.fontScale
                                text: Math.round((sound.stereoSeparation === undefined ? 0.8 : sound.stereoSeparation) * 100) + "%"
                            }
                            RowLayout {
                                spacing: 4
                                visible: m.amigaClock || false

                                PlayerButton {
                                    active: sound.palClock !== false
                                    dark: window.dark
                                    text: "PAL (3.546MHz)"
                                    textScale: window.fontScale * 0.82

                                    onClicked: option("palClock", true)
                                }
                                PlayerButton {
                                    active: sound.palClock === false
                                    dark: window.dark
                                    text: "NTSC (3.580MHz)"
                                    textScale: window.fontScale * 0.82

                                    onClicked: option("palClock", false)
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        color: Qt.alpha(accent, 0.25)
                        height: 1
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: compact ? 80 : 72
                        color: dark ? "#090b0d" : surface

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: compact ? 8 : 16
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                visible: compact && hasModule

                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: time(s.elapsed)
                                }
                                PlayerSlider {
                                    Layout.fillWidth: true
                                    dark: window.dark
                                    enabled: (m.orders || []).length > 1
                                    from: 0
                                    stepSize: 1
                                    to: Math.max(1, (m.orders || []).length - 1)
                                    value: s.position || 0

                                    onMoved: send("seek", {
                                        index: Math.round(value)
                                    })
                                }
                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: time(s.duration)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                PlayerButton {
                                    dark: window.dark
                                    enabled: hasModule
                                    hint: "Abspielen / Pause (Leertaste)"
                                    iconName: s.playing && !s.paused ? "discPause" : "discPlay"
                                    implicitHeight: 40
                                    implicitWidth: 40
                                    opacity: s.playing ? 1 : .6
                                    round: true
                                    spinning: !!s.playing && !s.paused

                                    onClicked: send("play")
                                }
                                PlayerButton {
                                    dark: window.dark
                                    enabled: s.playing || false
                                    hint: "Stopp"
                                    iconName: "stop"
                                    round: true

                                    onClicked: send("stop")
                                }
                                PlayerButton {
                                    dark: window.dark
                                    iconName: "back30"
                                    round: true
                                    visible: !compact

                                    onClicked: send("seekSeconds", {
                                        value: -30
                                    })
                                }
                                PlayerButton {
                                    dark: window.dark
                                    enabled: s.playing || false
                                    iconName: compact ? "back30" : "back10"
                                    round: true

                                    onClicked: send("seekSeconds", {
                                        value: compact ? -30 : -10
                                    })
                                }
                                PlayerButton {
                                    dark: window.dark
                                    enabled: s.playing || false
                                    iconName: compact ? "forward30" : "forward10"
                                    round: true

                                    onClicked: send("seekSeconds", {
                                        value: compact ? 30 : 10
                                    })
                                }
                                PlayerButton {
                                    dark: window.dark
                                    iconName: "forward30"
                                    round: true
                                    visible: !compact

                                    onClicked: send("seekSeconds", {
                                        value: 30
                                    })
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "Vorheriger Titel"
                                    iconName: "previous"
                                    round: true

                                    onClicked: send("previous")
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "Nächster Titel"
                                    iconName: "next"
                                    round: true

                                    onClicked: send("next")
                                }
                                PlayerButton {
                                    active: prefs.shuffle || false
                                    dark: window.dark
                                    hint: "Zufallswiedergabe"
                                    iconName: "shuffle"
                                    round: true

                                    onClicked: option("shuffle", !prefs.shuffle)
                                }
                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: time(s.elapsed)
                                    visible: !compact
                                }
                                PlayerSlider {
                                    Layout.fillWidth: true
                                    dark: window.dark
                                    enabled: (m.orders || []).length > 1
                                    from: 0
                                    stepSize: 1
                                    to: Math.max(1, (m.orders || []).length - 1)
                                    value: s.position || 0
                                    visible: !compact

                                    onMoved: send("seek", {
                                        index: Math.round(value)
                                    })
                                }
                                Text {
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: time(s.duration)
                                    visible: !compact
                                }
                                Item {
                                    Layout.fillWidth: true
                                    visible: compact
                                }
                                PlayerButton {
                                    dark: window.dark
                                    text: "⌨"
                                    visible: !compact

                                    onClicked: keyboardDialog.open()
                                }
                                PlayerButton {
                                    dark: window.dark
                                    text: "ⓘ"
                                    visible: !compact

                                    onClicked: aboutDialog.open()
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "WAV exportieren"
                                    text: "⇧"
                                    visible: !compact && hasModule

                                    onClicked: exportDialog.open()
                                }
                                PlayerButton {
                                    dark: window.dark
                                    hint: "Notenregen als Video"
                                    text: "▣"
                                    visible: !compact && hasModule

                                    onClicked: videoDialog.open()
                                }
                                Text {
                                    color: secondary
                                    text: "◖))"
                                }
                                PlayerSlider {
                                    Layout.preferredWidth: compact ? 80 : 90
                                    dark: window.dark
                                    from: 0
                                    to: 1
                                    value: prefs.volume === undefined ? 0.6 : prefs.volume

                                    onMoved: send("volume", {
                                        value: value
                                    })
                                }
                            }
                        }
                    }
                }
            }
        }
        DropArea {
            anchors.fill: parent

            onDropped: drop => desktop.drop(drop.urls)
        }
    }
    Menu {
        id: trackMenu

        MenuItem {
            text: "Favorit umschalten"

            onTriggered: send("favorite", {
                text: contextTrack
            })
        }
        MenuItem {
            text: "Als Nächstes abspielen"

            onTriggered: send("enqueue", {
                text: contextTrack,
                next: true
            })
        }
        MenuItem {
            text: "An Warteschlange anhängen"

            onTriggered: send("enqueue", {
                text: contextTrack
            })
        }
        MenuItem {
            enabled: !!((library.tracks || []).find(t => t.id === contextTrack) || {}).heard
            text: "Als ungehört markieren"

            onTriggered: send("markUnheard", {
                text: contextTrack
            })
        }
        Menu {
            title: "Zu Playlist hinzufügen"

            Repeater {
                model: library.playlists || []

                MenuItem {
                    required property var modelData

                    text: modelData.name

                    onTriggered: send("playlistAdd", {
                        text: contextTrack,
                        playlist: modelData.id
                    })
                }
            }
        }
    }
    Dialog {
        id: errorDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        modal: true
        standardButtons: Dialog.Ok
        title: "Savage Mod Player"
        width: Math.min(560, window.width - 40)

        Label {
            color: primary
            text: errorMessage
            width: parent.width
            wrapMode: Text.Wrap
        }
    }
    Dialog {
        id: settings

        anchors.centerIn: parent
        font.pixelSize: 13
        modal: true
        standardButtons: Dialog.Close
        title: "Einstellungen"
        width: Math.min(460, window.width - 40)

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            GroupBox {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 8
                    width: parent.width

                    Label {
                        font.bold: true
                        text: "Autoplay-Ordner:"
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: prefs.autoplayFolder || "Nicht gesetzt"
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        FormButton {
                            text: "Auswählen…"

                            onClicked: {
                                let p = desktop.chooseFolder("Autoplay-Ordner wählen");
                                if (p)
                                    option("autoplayFolder", p);
                            }
                        }
                        FormButton {
                            text: "Entfernen"
                            visible: !!prefs.autoplayFolder

                            onClicked: option("autoplayFolder", "")
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 11 * window.fontScale
                        text: "Aus diesem Ordner (inklusive Unterordnern und Zip-/7z-Archiven) füllt der Player beim Start die Playlist und beginnt zu spielen. Änderungen wirken ab dem nächsten Start."
                        wrapMode: Text.Wrap
                    }
                }
            }
            GroupBox {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 8
                    width: parent.width

                    Label {
                        text: "Bildrate der Visualisierungen:"
                    }
                    FormCombo {
                        Layout.fillWidth: true
                        currentIndex: model.indexOf(prefs.visualizerHz || 30)
                        displayText: currentValue === 30 ? "30 Hz (Standard)" : currentValue + " Hz"
                        model: [30, 24, 15, 10]

                        onActivated: option("visualizerHz", model[currentIndex])
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 11 * window.fontScale
                        text: "Wie oft Pegel, Oszilloskope und Spielzeit neu gezeichnet werden. Die Änderung wirkt sofort; der Klang bleibt unverändert. Im kompakten Fenster sind es unabhängig davon 5 Hz."
                        wrapMode: Text.Wrap
                    }
                }
            }
            GroupBox {
                Layout.fillWidth: true
                title: "Updates"

                ColumnLayout {
                    spacing: 8
                    width: parent.width

                    PlayerCheckBox {
                        baseFontSize: 13
                        dark: window.dark
                        enabled: false
                        text: "Automatisch nach Updates suchen"
                        textScale: 1
                    }
                    FormButton {
                        enabled: false
                        text: "Nach Updates suchen…"
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 11 * window.fontScale
                        text: "Die Linux-Ausgabe wird über ihre Installation aktualisiert. Sparkle setzt macOS voraus; für Linux besteht noch kein signierter Updatekanal."
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
    Dialog {
        id: filters

        property var failures: filters.records.filter(t => !!t.metadata.failure)
        property string filterID: ""
        property var records: filters.tracks.filter(t => !!t.metadata)
        property var tracks: library.tracks || []

        function formatCount(format) {
            return filters.records.filter(t => {
                let f = (t.metadata.metadata || {}).format || "";
                return (["protracker", "soundtracker", "multichannel"].indexOf(f) >= 0 ? "MOD" : f.toUpperCase()) === format;
            }).length;
        }

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(720, window.height - 40)
        modal: true
        standardButtons: Dialog.Close
        title: "Anzeige und Filter"
        width: Math.min(700, window.width - 40)

        ColumnLayout {
            anchors.fill: parent
            spacing: 14

            Label {
                Layout.fillWidth: true
                color: secondary
                text: "Die Anzeige ersetzt die laufende Wiedergabeauswahl erst mit „Diese Ergebnisse abspielen“."
                wrapMode: Text.Wrap
            }
            SplitView {
                Layout.fillHeight: true
                Layout.fillWidth: true

                ColumnLayout {
                    SplitView.preferredWidth: 210

                    Label {
                        font.bold: true
                        text: "Gespeicherte Filter"
                    }
                    ListView {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        clip: true
                        model: library.savedFilters || []

                        delegate: ItemDelegate {
                            required property var modelData

                            highlighted: filters.filterID === modelData.id
                            text: modelData.name
                            width: ListView.view.width

                            onClicked: {
                                filters.filterID = modelData.id;
                                send("filterOpen", {
                                    text: modelData.id
                                });
                            }
                        }
                    }
                    FormButton {
                        enabled: !!filters.filterID
                        text: "Ausgewählten Filter löschen"

                        onClicked: {
                            send("filterDelete", {
                                text: filters.filterID
                            });
                            filters.filterID = "";
                        }
                    }
                }
                ColumnLayout {
                    Layout.leftMargin: 12
                    SplitView.fillWidth: true
                    spacing: 8

                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "Datei, Titel oder Instrument"
                        text: (library.query || {}).search || ""

                        onTextEdited: changeQuery("search", text)
                    }
                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: "Format"
                        }
                        FormCombo {
                            currentIndex: Math.max(0, model.indexOf((library.query || {}).format || "Alle"))
                            model: ["Alle", "MOD", "S3M", "XM", "IT"]

                            onActivated: changeQuery("format", currentIndex === 0 ? null : currentText)
                        }
                    }
                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: "Mindestens Kanäle"
                        }
                        SpinBox {
                            from: 0
                            to: 64
                            value: (library.query || {}).minimumChannels || 0

                            onValueModified: changeQuery("minimumChannels", value)
                        }
                    }
                    PlayerCheckBox {
                        baseFontSize: 13
                        checked: (library.query || {}).favoritesOnly || false
                        dark: window.dark
                        text: "Nur Favoriten"
                        textScale: 1

                        onClicked: changeQuery("favoritesOnly", checked)
                    }
                    PlayerCheckBox {
                        baseFontSize: 13
                        checked: (library.query || {}).unheardOnly || false
                        dark: window.dark
                        text: "Nur ungehörte Titel"
                        textScale: 1

                        onClicked: changeQuery("unheardOnly", checked)
                    }
                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: "Neu hinzugefügt"
                        }
                        FormCombo {
                            currentIndex: [null, 7, 30].indexOf((library.query || {}).addedWithinDays || null)
                            model: ["Alle", "Letzte 7 Tage", "Letzte 30 Tage"]

                            onActivated: changeQuery("addedWithinDays", [null, 7, 30][currentIndex])
                        }
                    }
                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: "Sortierung"
                        }
                        FormCombo {
                            currentIndex: ["sourceOrder", "filename", "title", "format", "channels", "duration", "newest"].indexOf((library.query || {}).sort || "sourceOrder")
                            model: ["Ordnerreihenfolge", "Dateiname", "Interner Modultitel", "Format", "Kanalzahl", "Spieldauer", "Neueste zuerst"]

                            onActivated: changeQuery("sort", ["sourceOrder", "filename", "title", "format", "channels", "duration", "newest"][currentIndex])
                        }
                    }
                    PlayerCheckBox {
                        baseFontSize: 13
                        checked: (library.query || {}).reversed || false
                        dark: window.dark
                        text: "Reihenfolge umkehren"
                        textScale: 1

                        onClicked: changeQuery("reversed", checked)
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                }
            }
            RowLayout {
                TextField {
                    id: filterName

                    Layout.fillWidth: true
                    placeholderText: "Name des Filters"
                }
                FormButton {
                    enabled: filterName.text.trim().length > 0
                    text: "Aktuellen Filter speichern"

                    onClicked: {
                        send("filterSave", {
                            text: filterName.text
                        });
                        filterName.clear();
                    }
                }
            }
            GroupBox {
                Layout.fillWidth: true
                title: "Sammlung"

                ColumnLayout {
                    spacing: 5
                    width: parent.width

                    Label {
                        text: "Indiziert: " + filters.records.length + " von " + filters.tracks.length + " · Fehler: " + filters.failures.length
                    }
                    Label {
                        color: secondary
                        text: ["MOD", "S3M", "XM", "IT"].map(f => f + ": " + filters.formatCount(f)).join(" · ")
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: (indexStatus.warnings || []).map(w => ({
                                    capacityLimited: "Indexgrenze erreicht; einige Metadaten fehlen.",
                                    cacheWriteFailed: "Metadatenindex konnte nicht gesichert werden.",
                                    invalidSource: "Einige Quellen konnten nicht indiziert werden."
                                })[w] || "").filter(v => v).join("\n")
                        visible: !!text
                        wrapMode: Text.Wrap
                    }
                    FormCombo {
                        Layout.fillWidth: true
                        model: filters.failures.map(t => t.name + " · " + (t.metadata.detail || t.metadata.failure))
                        visible: filters.failures.length > 0
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        value: (indexStatus.completed || 0) / Math.max(1, indexStatus.total || 1)
                        visible: indexStatus.active || false
                    }
                    FormButton {
                        text: "Indizierung abbrechen"
                        visible: indexStatus.active || false

                        onClicked: send("indexCancel")
                    }
                }
            }
            RowLayout {
                FormButton {
                    text: "Anzeige zurücksetzen"

                    onClicked: send("query", {
                        query: {
                            search: "",
                            minimumChannels: 0,
                            favoritesOnly: false,
                            unheardOnly: false,
                            sort: "sourceOrder",
                            reversed: false
                        }
                    })
                }
                FormButton {
                    text: "Metadaten erneut prüfen"

                    onClicked: send("indexRefresh")
                }
            }
        }
    }
    Dialog {
        id: playlists

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(520, window.height - 40)
        modal: true
        standardButtons: Dialog.Close
        title: "Gespeicherte Playlists"
        width: Math.min(720, window.width - 40)

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
                                playlists.close();
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
                font.pixelSize: 11 * window.fontScale
                text: "Weitere Titel: Rechtsklick auf einen Titel → Zu Playlist hinzufügen."
            }
        }
    }
    Dialog {
        id: deletePlaylist

        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        title: "Playlist löschen?"
        width: Math.min(450, window.width - 40)

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
    Dialog {
        id: queueDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(500, window.height - 60)
        modal: true
        standardButtons: Dialog.Close
        title: "Als Nächstes"
        width: 650

        ColumnLayout {
            anchors.fill: parent

            Label {
                Layout.fillWidth: true
                color: secondary
                text: "Eingereihte Titel haben Vorrang. Danach setzt sich die bisherige Playlist fort."
                wrapMode: Text.Wrap
            }
            ListView {
                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                model: library.queue || []

                delegate: RowLayout {
                    required property var modelData

                    height: 40
                    width: ListView.view.width

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: modelData.name
                    }
                    FormButton {
                        text: "↑"

                        onClicked: send("queueMove", {
                            text: modelData.id,
                            index: -1
                        })
                    }
                    FormButton {
                        text: "↓"

                        onClicked: send("queueMove", {
                            text: modelData.id,
                            index: 1
                        })
                    }
                    FormButton {
                        text: "Entfernen"

                        onClicked: send("queueRemove", {
                            text: modelData.id
                        })
                    }
                }
            }
            FormButton {
                text: "Warteschlange leeren"

                onClicked: send("queueClear")
            }
        }
    }
    Dialog {
        id: timerDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        height: 480
        modal: true
        title: "Einschlaftimer"
        width: 380

        onOpened: timerMinutes.value = prefs.sleepTimerMinutes || 15

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
                        })[s.timerPhase || "inactive"]
                }
                Label {
                    font.pixelSize: 24
                    text: time(s.timerSeconds)
                }
            }
            RowLayout {
                visible: s.timerPhase !== "inactive" && !!s.timerPhase

                FormButton {
                    text: "+15 Minuten"
                    visible: s.timerActive || false

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

                    onClicked: timerDialog.close()
                }
                Item {
                    Layout.fillWidth: true
                }
                FormButton {
                    text: s.timerActive ? "Neu starten" : "Timer starten"

                    onClicked: send("timer", {
                        index: timerMinutes.value
                    })
                }
            }
        }
    }
    Dialog {
        id: trackSettings

        property bool editingDefaults: false

        function update(key, value) {
            if (editingDefaults) {
                send("defaultOption", {
                    text: key,
                    setting: value
                });
                return;
            }
            let v = Object.assign({}, m.trackSettings || {});
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
                text: trackSettings.editingDefaults ? "Globale Klangvorgaben" : m.title || "Kein Song geladen"
                wrapMode: Text.Wrap

                font {
                    bold: true
                    pixelSize: 20
                }
            }
            TabBar {
                Layout.fillWidth: true
                currentIndex: trackSettings.editingDefaults ? 1 : 0

                TabButton {
                    text: "Dieser Titel"

                    onClicked: trackSettings.editingDefaults = false
                }
                TabButton {
                    text: "Globale Vorgaben"

                    onClicked: trackSettings.editingDefaults = true
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
                        text: trackSettings.editingDefaults ? "Diese Vorgaben gelten für alle Titel ohne passenden Override." : "Jeder Titelwert ersetzt nur seine passende globale Vorgabe."
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
                            visible: modelData.key !== "palClock" || trackSettings.editingDefaults || !!m.amigaClock

                            Label {
                                text: modelData.label
                            }
                            FormCombo {
                                Layout.fillWidth: true
                                currentIndex: trackSettings.editingDefaults ? (prefs[modelData.key] === false ? 1 : 0) : (m.trackSettings || {})[modelData.key] === undefined ? 0 : ((m.trackSettings || {})[modelData.key] ? 1 : 2)
                                enabled: trackSettings.editingDefaults || !!m.sourceID
                                model: trackSettings.editingDefaults ? modelData.choices : ["Globale Vorgabe"].concat(modelData.choices)

                                onActivated: trackSettings.update(modelData.key, trackSettings.editingDefaults ? currentIndex === 0 : currentIndex === 0 ? null : currentIndex === 1)
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: "Dieses Format verwendet ein festes Frequenzmodell; PAL/NTSC ist nicht anwendbar."
                        visible: !trackSettings.editingDefaults && !m.amigaClock
                        wrapMode: Text.Wrap
                    }
                    PlayerCheckBox {
                        baseFontSize: 13
                        checked: (m.trackSettings || {}).stereoSeparation !== undefined
                        dark: window.dark
                        enabled: !!m.sourceID
                        text: "Stereoabstand für diesen Titel"
                        visible: !trackSettings.editingDefaults

                        onClicked: trackSettings.update("stereoSeparation", checked ? (sound.stereoSeparation === undefined ? .8 : sound.stereoSeparation) : null)
                    }
                    Label {
                        text: "Separation: " + Math.round((trackSettings.editingDefaults ? (prefs.stereoSeparation === undefined ? .8 : prefs.stereoSeparation) : (sound.stereoSeparation || 0)) * 100) + " %"
                    }
                    PlayerSlider {
                        Layout.fillWidth: true
                        dark: window.dark
                        enabled: trackSettings.editingDefaults || (m.trackSettings || {}).stereoSeparation !== undefined
                        from: 0
                        to: 1
                        value: trackSettings.editingDefaults ? (prefs.stereoSeparation === undefined ? .8 : prefs.stereoSeparation) : sound.stereoSeparation || 0

                        onMoved: trackSettings.update("stereoSeparation", value)
                    }
                }
            }
            FormButton {
                enabled: !!m.sourceID
                text: "Titel zurücksetzen"
                visible: !trackSettings.editingDefaults

                onClicked: send("trackSettings", {
                    settings: {}
                })
            }
        }
    }
    Dialog {
        id: markers

        property string editingID: ""

        function chooseCurrent() {
            markerPosition.value = Math.max(1, (s.position || 0) + 1);
            markerRow.value = Math.max(0, s.row || 0);
        }

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(760, window.height - 40)
        modal: true
        standardButtons: Dialog.Close
        title: "Songstellen und Bereich"
        width: Math.min(760, window.width - 40)

        onOpened: {
            editingID = "";
            markerName.clear();
            chooseCurrent();
        }

        ScrollView {
            id: markerScroll

            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                spacing: 20
                width: markerScroll.availableWidth

                Label {
                    font.bold: true
                    text: m.title || ""
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
                        enabled: !s.markerSaving
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
                                to: Math.max(1, (m.orders || []).length)
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
                                to: Math.max(0, ((m.rowCounts || [])[markerPosition.value - 1] || 1) - 1)
                            }
                        }
                        RowLayout {
                            FormButton {
                                text: "Aktuelle Stelle"

                                onClicked: markers.chooseCurrent()
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            FormButton {
                                enabled: hasModule
                                text: "Zum Ziel springen"

                                onClicked: send("seek", {
                                    index: markerPosition.value - 1,
                                    row: markerRow.value
                                })
                            }
                        }
                        TextField {
                            id: markerName

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
                                enabled: !!m.sourceID && markerName.text.trim().length > 0 && markerName.text.trim().length <= 200
                                text: markers.editingID ? "Änderungen speichern" : "Songstelle hinzufügen"

                                onClicked: {
                                    send(markers.editingID ? "markerRename" : "markerAdd", {
                                        id: markers.editingID,
                                        text: markerName.text.trim(),
                                        position: markerPosition.value - 1,
                                        row: markerRow.value
                                    });
                                    markers.editingID = "";
                                    markerName.clear();
                                }
                            }
                            FormButton {
                                text: "Neu"
                                visible: !!markers.editingID

                                onClicked: {
                                    markers.editingID = "";
                                    markerName.clear();
                                    markers.chooseCurrent();
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

                                onClicked: sectionStart = {
                                    position: markerPosition.value - 1,
                                    row: markerRow.value
                                }
                            }
                            FormButton {
                                text: "Ende (B)"

                                onClicked: sectionEnd = {
                                    position: markerPosition.value - 1,
                                    row: markerRow.value
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            FormButton {
                                text: "Lösen"

                                onClicked: {
                                    sectionStart = {
                                        position: -1,
                                        row: 0
                                    };
                                    sectionEnd = {
                                        position: -1,
                                        row: 0
                                    };
                                }
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
                                enabled: !s.sectionPreparing && !s.sectionActive && validSection
                                text: s.sectionPreparing ? "A/B wird vorbereitet …" : s.sectionActive ? "A/B-Schleife aktiv" : "A/B vorbereiten und abspielen"

                                onClicked: send("section", {
                                    start: sectionStart,
                                    end: sectionEnd
                                })
                            }
                            FormButton {
                                text: s.sectionPreparing ? "Abbrechen" : "A/B ausschalten"
                                visible: !!s.sectionActive || !!s.sectionPreparing

                                onClicked: send("sectionCancel")
                            }
                        }
                        ProgressBar {
                            Layout.fillWidth: true
                            value: s.sectionProgress || 0
                            visible: s.sectionPreparing || false
                        }
                        Label {
                            Layout.fillWidth: true
                            color: "#e5503a"
                            text: s.sectionError || ""
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
                            visible: !(m.markers || []).length
                        }
                        Repeater {
                            model: m.markers || []

                            ColumnLayout {
                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 6

                                FormButton {
                                    Layout.fillWidth: true
                                    flat: true
                                    text: modelData.name + "   " + addressText(modelData.address)

                                    onClicked: {
                                        markers.editingID = modelData.id;
                                        markerName.text = modelData.name;
                                        markerPosition.value = modelData.address.position + 1;
                                        markerRow.value = modelData.address.row;
                                    }
                                }
                                RowLayout {
                                    FormButton {
                                        text: "Springen"

                                        onClicked: send("seek", {
                                            index: modelData.address.position,
                                            row: modelData.address.row
                                        })
                                    }
                                    FormButton {
                                        text: "Löschen"

                                        onClicked: send("markerDelete", {
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
    Dialog {
        id: inspector

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(760, window.height - 40)
        modal: true
        standardButtons: Dialog.Close
        title: "Modul-Inspektor"
        width: Math.min(760, window.width - 40)

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: inspection.title || ""

                font {
                    bold: true
                    pixelSize: 20 * window.fontScale
                }
            }
            TabBar {
                id: inspectorTabs

                Layout.fillWidth: true

                TabButton {
                    text: "Übersicht"
                }
                TabButton {
                    text: "Instrumente"
                }
                TabButton {
                    text: "Effekte"
                }
            }
            StackLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true
                currentIndex: inspectorTabs.currentIndex

                ScrollView {
                    id: overviewScroll

                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        spacing: 8
                        width: overviewScroll.availableWidth

                        Repeater {
                            model: [["Format", inspection.format || ""], ["Songpositionen / Patterns", (inspection.orders || []).length + " / " + (inspection.patternCount || 0)], ["Kanalplätze / benutzt", (inspection.channels || 0) + " / " + (inspection.usedChannels || 0)], ["Instrumente / Samples", (inspection.instrumentCount || 0) + " / " + (inspection.sampleCount || 0)], ["Starttempo / Ticks pro Zeile", (inspection.initialTempo || 0) + " BPM / " + (inspection.initialSpeed || 0)], ["Startlautstärke", (inspection.initialVolume || 0) + "/" + (inspection.volumeScale || 64)], ["Frequenzmodell", inspection.linearFrequency ? "Linear" : "Amiga"]]

                            RowLayout {
                                required property var modelData

                                Layout.fillWidth: true

                                Label {
                                    Layout.preferredWidth: 220
                                    color: secondary
                                    text: modelData[0]
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData[1]
                                }
                            }
                        }
                        GroupBox {
                            Layout.fillWidth: true
                            title: "Herkunft"

                            ColumnLayout {
                                spacing: 8
                                width: parent.width

                                Label {
                                    Layout.fillWidth: true
                                    color: secondary
                                    text: inspection.tracker ? "Tracker: " + inspection.tracker : "Trackerherkunft ist im geladenen Modell nicht enthalten."
                                    wrapMode: Text.Wrap
                                }
                                Label {
                                    color: secondary
                                    text: inspection.artist ? "Künstlerfeld: " + inspection.artist : "Kein explizites Künstlerfeld vorhanden."
                                }
                                Repeater {
                                    model: Object.keys(inspection.origin || {})

                                    RowLayout {
                                        required property var modelData

                                        Layout.fillWidth: true

                                        Label {
                                            text: modelData
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: inspection.origin[modelData]
                                        }
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    color: secondary
                                    font.pixelSize: 11 * window.fontScale
                                    text: "Namen und Textzeilen werden nicht als Künstlerangaben interpretiert."
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                        Label {
                            font.bold: true
                            text: "Songpositionen und Pattern-Aufbau"
                        }
                        Repeater {
                            model: inspection.orders || []

                            RowLayout {
                                required property var modelData

                                Layout.fillWidth: true

                                Label {
                                    Layout.fillWidth: true
                                    text: "Position " + modelData.position + " · Pattern " + modelData.pattern + " · " + modelData.rows + " Zeilen"
                                }
                                FormButton {
                                    text: "Springen"

                                    onClicked: send("seek", {
                                        index: modelData.position
                                    })
                                }
                            }
                        }
                        Repeater {
                            model: inspection.patternRows || []

                            RowLayout {
                                required property var modelData

                                Layout.fillWidth: true

                                Label {
                                    text: "Pattern " + modelData.index
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: modelData.rows + " Zeilen · " + modelData.uses + "× in der Liste"
                                }
                            }
                        }
                        Label {
                            font.bold: true
                            text: "Kompatibilität"
                        }
                        Label {
                            color: secondary
                            text: !(inspection.warnings || []).length ? "Keine erfassten Kompatibilitätswarnungen." : ""
                            visible: !!text
                        }
                        Repeater {
                            model: inspection.findings || []

                            ColumnLayout {
                                required property var modelData

                                Layout.fillWidth: true

                                Label {
                                    Layout.fillWidth: true
                                    font.bold: true
                                    text: modelData.identifier + " · " + ({
                                            supported: "Unterstützt",
                                            irrelevantForPCM: "Keine PCM-Wirkung",
                                            metadataOnly: "Nur Metadaten",
                                            midiOrPluginOnly: "Externer MIDI-/Pluginpfad",
                                            unsupported: "Nicht unterstützt",
                                            differentPlayback: "Abweichende Wiedergabe"
                                        })[modelData.support]
                                    wrapMode: Text.Wrap
                                }
                                Label {
                                    color: secondary
                                    text: modelData.used ? "Verwendet" : "Gespeichert, nicht verwendet"
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.detail
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            color: "#cf922b"
                            text: (inspection.warnings || []).join("\n")
                            wrapMode: Text.Wrap
                        }
                    }
                }
                ScrollView {
                    id: instrumentScroll

                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        spacing: 20
                        width: instrumentScroll.availableWidth

                        Label {
                            color: secondary
                            text: "Instrument"
                        }
                        FormCombo {
                            Layout.fillWidth: true
                            displayText: currentIndex >= 0 && model[currentIndex] ? model[currentIndex].index + " · " + model[currentIndex].name : "Keine Instrumentplätze vorhanden."
                            model: inspection.instruments || []
                            textRole: "name"

                            onActivated: send("instrument", {
                                index: model[currentIndex].index
                            })
                        }
                        InstrumentDetails {
                            Layout.fillWidth: true
                            accent: window.accent
                            backdrop: window.backdrop
                            details: instrumentDetails
                            primary: window.primary
                            secondary: window.secondary
                            textScale: 1
                        }
                    }
                }
                ListView {
                    clip: true
                    model: inspection.effects || []

                    delegate: ColumnLayout {
                        required property var modelData

                        spacing: 4
                        width: ListView.view.width

                        Label {
                            font.bold: true
                            text: modelData.code + " · " + modelData.name + " · " + modelData.count + "×"
                        }
                        Label {
                            color: secondary
                            text: modelData.volumeColumn ? "Volume-Spalte" : "Effektspalte"
                        }
                        Label {
                            Layout.fillWidth: true
                            color: secondary
                            text: modelData.detail
                            wrapMode: Text.Wrap
                        }
                        Label {
                            color: "#e7a04b"
                            text: "Derzeit ignoriert"
                            visible: !modelData.implemented
                        }
                        Label {
                            Layout.fillWidth: true
                            font.family: "monospace"
                            text: "Übernommene Parameter: " + (modelData.parameters || []).slice(0, 32).map(v => modelData.volumeColumn && inspection.formatCode !== "xm" ? v : v.toString(16).toUpperCase().padStart(2, "0")).join(" ")
                            wrapMode: Text.Wrap
                        }
                        Item {
                            height: 10
                        }
                    }
                }
            }
        }
    }
    Dialog {
        id: sampleDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(760, window.height - 40)
        modal: true
        standardButtons: Dialog.Close
        title: "Sample-Inspektor"
        width: Math.min(760, window.width - 40)

        ScrollView {
            id: sampleScroll

            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                spacing: 20
                width: sampleScroll.availableWidth

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        color: secondary
                        text: "Instrument"
                    }
                    FormCombo {
                        Layout.fillWidth: true
                        currentIndex: Math.max(0, model.findIndex(i => i.index === sampleInstrument))
                        model: [
                            {
                                index: 0,
                                name: "Alle Samples"
                            }
                        ].concat(inspection.instruments || [])
                        textRole: "name"

                        onActivated: {
                            sampleInstrument = model[currentIndex].index;
                            let i = model[currentIndex], ids = i.sampleIDs || [];
                            let first = (inspection.samples || []).find(v => sampleInstrument === 0 || ids.indexOf(v.id) >= 0);
                            if (first)
                                showSample(first.id, sampleInstrument);
                        }
                    }
                    Label {
                        color: secondary
                        text: "Sample"
                    }
                    FormCombo {
                        property var ids: ((inspection.instruments || []).find(i => i.index === sampleInstrument) || {}).sampleIDs || []

                        Layout.fillWidth: true
                        currentIndex: Math.max(0, model.findIndex(v => v.id === selectedSample))
                        displayText: currentIndex >= 0 && model[currentIndex] ? model[currentIndex].number + " · " + (model[currentIndex].name || "—") : "Kein Sample vorhanden"
                        model: (inspection.samples || []).filter(v => sampleInstrument === 0 || ids.indexOf(v.id) >= 0)
                        textRole: "name"

                        onActivated: showSample(model[currentIndex].id, sampleInstrument)
                    }
                }
                SampleWaveform {
                    id: sampleViewer

                    Layout.fillWidth: true
                    accent: window.accent
                    dark: window.dark
                    primary: window.primary
                    sample: window.sample
                    secondary: window.secondary

                    onRequest: requestSample()
                }
                Repeater {
                    model: [["Frames", sample.frames || 0], ["Kanäle", (sample.right || []).length ? "Stereo" : "Mono"], ["Lautstärke", (sample.volume || 0) + "/64"], ["Finetune", sample.finetune || 0]].concat(inspection.formatCode === "xm" ? [["Relative Note", sample.relativeNote || 0]] : []).concat(["it", "s3m"].indexOf(inspection.formatCode) >= 0 ? [[inspection.formatCode === "it" ? "Referenzrate bei C-5" : "Referenzrate bei C-4", ((sample.itProperties || {}).c5Speed || sample.c2spd || 0) + " Hz"]] : [])

                    RowLayout {
                        required property var modelData

                        Layout.fillWidth: true

                        Label {
                            text: modelData[0]
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Label {
                            text: modelData[1]
                        }
                    }
                }
                Label {
                    color: secondary
                    text: sampleInstrument ? "Tastenzuordnung" : "Instrument wählen, um die Tastenzuordnung zu sehen."
                }
                Repeater {
                    model: sampleInstrument ? ((inspection.instruments || []).find(i => i.index === sampleInstrument) || {}).keyZones || [] : []

                    Label {
                        required property var modelData

                        text: modelData.start + "–" + modelData.end + " → " + modelData.targetStart + "–" + modelData.targetEnd + " · " + modelData.sample
                    }
                }
            }
        }
    }
    Dialog {
        id: exportDialog

        property bool validFolder: exportFolder.text.trim().length > 0 && exportFolder.text !== "." && exportFolder.text !== ".." && !/[\/\x00:]/.test(exportFolder.text)

        anchors.centerIn: parent
        font.pixelSize: 11 * window.fontScale
        modal: true
        title: "OFFLINE-WAV-EXPORT"
        width: Math.min(420, window.width - 40)

        onOpened: {
            exportProgress = 0;
            exportResult = "";
            send("prepareExport");
            exportFolder.text = (m.title || "Modul").replace(/[\/:]/g, "_") + "-Kanalspuren";
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Label {
                Layout.fillWidth: true
                text: exportTitle
                wrapMode: Text.Wrap
            }
            TabBar {
                id: exportKind

                Layout.fillWidth: true

                TabButton {
                    text: "Stereo-Mix"
                }
                TabButton {
                    text: "Kanalspuren"
                }
            }
            Label {
                Layout.fillWidth: true
                text: exportKind.currentIndex ? "Eine Stereo-Float32-WAV je logischem Kanal, dazu Referenzmix und Begleitdatei. Alle Dateien beginnen gemeinsam und verwenden denselben Pegelfaktor." : "Exportiert den gesamten Titel offline in eine Stereo-WAV-Datei."
                wrapMode: Text.Wrap
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: exportKind.currentIndex === 1

                Label {
                    text: "Neuer Ordnername"
                }
                TextField {
                    id: exportFolder

                    Layout.fillWidth: true
                    placeholderText: "Kanalspuren"
                }
            }
            Label {
                Layout.fillWidth: true
                color: secondary
                text: "Übernimmt Mute/Solo, Clock, Interpolation und Separation. Limiter, Mixerlautstärke und externer LED-Ausgabefilter sind nicht enthalten."
                visible: exportKind.currentIndex === 1
                wrapMode: Text.Wrap
            }
            RowLayout {
                Label {
                    text: "Dauer begrenzen:"
                }
                FormCombo {
                    id: exportSeconds

                    Layout.fillWidth: true
                    currentIndex: 1
                    displayText: currentValue / 60 + " Minuten"
                    model: [60, 180, 300, 600]
                }
            }
            ProgressBar {
                Layout.fillWidth: true
                value: exportProgress
                visible: exporting || exportProgress > 0
            }
            Label {
                Layout.fillWidth: true
                text: exportResult ? "Erfolgreich gesichert!" : ""
                visible: !!exportResult
                wrapMode: Text.Wrap
            }
            RowLayout {
                FormButton {
                    text: exporting ? "Abbrechen" : "Schließen"

                    onClicked: {
                        if (exporting)
                            send("exportCancel");
                        else
                            exportDialog.close();
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                FormButton {
                    text: "Ordner zeigen"
                    visible: !!exportResult

                    onClicked: desktop.reveal(exportResult)
                }
                FormButton {
                    enabled: !exporting && (exportKind.currentIndex === 0 || exportDialog.validFolder)
                    text: "Ziel wählen …"

                    onClicked: {
                        let path = exportKind.currentIndex === 0 ? desktop.saveFile("Song als WAV exportieren", exportTitle.replace(/[\/:]/g, "_") + ".wav", "WAV (*.wav)", true) : desktop.chooseFolder("Zielverzeichnis für Kanalspuren");
                        if (path) {
                            if (exportKind.currentIndex === 1)
                                path += "/" + exportFolder.text.trim();
                            exporting = true;
                            send("export", {
                                path: path,
                                kind: exportKind.currentIndex ? "stems" : "mix",
                                overwrite: exportKind.currentIndex === 0 && desktop.overwriteApproved(path),
                                seconds: exportSeconds.currentValue
                            });
                        }
                    }
                }
            }
        }
    }
    Dialog {
        id: batchDialog

        property var items: []
        property var selected: []

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(640, window.height - 40)
        modal: true
        standardButtons: Dialog.Close
        title: "Stapel-Export"
        width: Math.min(600, window.width - 40)

        onClosed: if (exporting)
            send("exportCancel")
        onOpened: {
            items = (library.tracks || []).filter(t => (library.visible || []).indexOf(t.id) >= 0);
            selected = items.map(t => t.id);
            exportReport = {};
            exportResult = "";
            exportProgress = 0;
            let o = prefs.batchSettings || {};
            batchKind.currentIndex = o.stems ? 1 : 0;
            batchConflict.currentIndex = o.rename ? 1 : 0;
            batchDuration.currentIndex = Math.max(0, [60, 180, 300, 600].indexOf(o.seconds || 300));
            batchPAL.currentIndex = o.pal === false ? 1 : 0;
            batchInterpolation.checked = o.interpolation !== false;
            batchSeparation.value = o.separation === undefined ? .8 : o.separation;
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 14

            ScrollView {
                id: batchScroll

                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    spacing: 14
                    width: batchScroll.availableWidth

                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        text: "Die Titelliste ist beim Öffnen festgehalten. Jeder Titel beginnt am Songanfang; die normale Wiedergabe kann weiterlaufen."
                        wrapMode: Text.Wrap
                    }
                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: batchDialog.selected.length + " von " + batchDialog.items.length + " Titeln ausgewählt"
                        }
                        FormButton {
                            text: "Alle"

                            onClicked: batchDialog.selected = batchDialog.items.map(t => t.id)
                        }
                        FormButton {
                            text: "Keine"

                            onClicked: batchDialog.selected = []
                        }
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 160
                        clip: true
                        model: batchDialog.items

                        delegate: CheckDelegate {
                            required property var modelData

                            checked: batchDialog.selected.indexOf(modelData.id) >= 0
                            enabled: !exporting
                            text: modelData.name
                            width: ListView.view.width

                            onClicked: {
                                let a = batchDialog.selected.slice(), i = a.indexOf(modelData.id);
                                if (checked && i < 0)
                                    a.push(modelData.id);
                                else if (!checked && i >= 0)
                                    a.splice(i, 1);
                                batchDialog.selected = a;
                            }
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        enabled: !exporting

                        Label {
                            text: "Ausgabe"
                        }
                        FormCombo {
                            id: batchKind

                            Layout.fillWidth: true
                            model: ["Stereo-Mix", "Kanalspuren und Referenzmix"]
                        }
                        Label {
                            text: "Vorhandene Ziele"
                        }
                        FormCombo {
                            id: batchConflict

                            Layout.fillWidth: true
                            model: ["Überspringen", "Beide behalten (neuer Name)"]
                        }
                        Label {
                            text: "Dauer je Titel"
                        }
                        FormCombo {
                            id: batchDuration

                            Layout.fillWidth: true
                            currentIndex: 2
                            displayText: currentValue / 60 + " Minuten"
                            model: [60, 180, 300, 600]
                        }
                        Label {
                            text: "MOD-Clock"
                        }
                        FormCombo {
                            id: batchPAL

                            model: ["PAL", "NTSC"]
                        }
                        Label {
                            text: "Sample-Interpolation"
                        }
                        PlayerCheckBox {
                            id: batchInterpolation

                            baseFontSize: 13
                            checked: true
                            dark: window.dark
                            textScale: 1
                        }
                        Label {
                            text: "Separation: " + Math.round(batchSeparation.value * 100) + " %"
                        }
                        PlayerSlider {
                            id: batchSeparation

                            Layout.fillWidth: true
                            dark: window.dark
                            from: 0
                            to: 1
                            value: .8
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        color: secondary
                        font.pixelSize: 11 * window.fontScale
                        text: "Stereo-Float32 mit 44.100 Hz. Kanalspuren verwenden einen gemeinsamen Pegelfaktor je Titel. Mute/Solo aus dem Player, Mixerlautstärke und externer LED-Ausgabefilter werden nicht übernommen."
                        wrapMode: Text.Wrap
                    }
                }
            }
            ProgressBar {
                Layout.fillWidth: true
                value: exportProgress
                visible: exporting
            }
            Label {
                Layout.fillWidth: true
                text: (exportReport.wasCancelled ? "Abgebrochen: " : "Stapel beendet: ") + (exportReport.results || []).filter(r => r.status === "exported").length + " exportiert, " + (exportReport.results || []).filter(r => r.status === "skipped").length + " übersprungen, " + (exportReport.results || []).filter(r => r.status === "failed").length + " fehlgeschlagen."
                visible: !!exportReport.results
                wrapMode: Text.Wrap
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                clip: true
                model: exportReport.results || []
                visible: !!exportReport.results

                delegate: Label {
                    required property var modelData

                    text: modelData.sourceName + ": " + modelData.status + (modelData.detail ? " – " + modelData.detail : "")
                    width: ListView.view.width
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                FormButton {
                    text: "Abbrechen"
                    visible: exporting

                    onClicked: send("exportCancel")
                }
                Item {
                    Layout.fillWidth: true
                }
                FormButton {
                    text: "Im Dateimanager zeigen"
                    visible: !!exportResult && !exporting

                    onClicked: desktop.reveal(exportResult)
                }
                FormButton {
                    enabled: !exporting && batchDialog.selected.length > 0 && batchDialog.selected.length <= 10000
                    text: "Ziel wählen …"

                    onClicked: {
                        let path = desktop.chooseFolder("Stapelexport: Zielordner");
                        if (path) {
                            exporting = true;
                            send("batchExport", {
                                path: path,
                                ids: batchDialog.selected,
                                stems: batchKind.currentIndex === 1,
                                rename: batchConflict.currentIndex === 1,
                                seconds: batchDuration.currentValue,
                                pal: batchPAL.currentIndex === 0,
                                interpolation: batchInterpolation.checked,
                                separation: batchSeparation.value
                            });
                        }
                    }
                }
            }
        }
    }
    Dialog {
        id: videoDialog

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
        height: Math.min(720, window.height - 40)
        modal: true
        standardButtons: Dialog.Close
        title: "Notenregen als Video"
        width: 640

        onClosed: {
            previewPlayer.stop();
            if (videoPreparing)
                send("exportCancel");
        }
        onOpened: {
            videoPreviewPath = "";
            exportResult = "";
            exportProgress = 0;
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
                            pixelSize: 20 * window.fontScale
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        font.bold: true
                        text: exportTitle
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
                            text: videoPreparing ? "Vorschau wird vorbereitet…" : "Vorschau vorbereiten"
                            visible: videoPreparing || !videoPreviewPath
                        }
                    }
                    MediaPlayer {
                        id: previewPlayer

                        source: videoPreviewPath ? desktop.fileURL(videoPreviewPath) : ""
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
                            enabled: !exporting && !videoPreparing
                            text: "Vorschau vorbereiten"

                            onClicked: {
                                videoPreviewPath = "";
                                send("videoPreview", videoDialog.options());
                            }
                        }
                        FormButton {
                            enabled: !!videoPreviewPath && !videoPreparing
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
                        enabled: !exporting && !videoPreparing
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
                            currentIndex: dark ? 0 : 1
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
                value: exportProgress
                visible: exporting || videoPreparing
            }
            RowLayout {
                FormButton {
                    enabled: !exporting && !videoPreparing
                    text: "Video exportieren…"

                    onClicked: {
                        let path = desktop.saveFile("Notenregen exportieren", "Notenregen.mov", "QuickTime (*.mov)");
                        if (path) {
                            exporting = true;
                            send("videoExport", Object.assign({
                                path: path
                            }, videoDialog.options()));
                        }
                    }
                }
                FormButton {
                    enabled: exporting || videoPreparing
                    text: "Abbrechen"

                    onClicked: send("exportCancel")
                }
                FormButton {
                    text: "Im Dateimanager zeigen"
                    visible: !!exportResult && !exporting

                    onClicked: desktop.reveal(exportResult)
                }
            }
        }
    }
    Dialog {
        id: collection

        anchors.centerIn: parent
        font.pixelSize: 13
        height: 420
        modal: true
        standardButtons: Dialog.Close
        title: "Sammlung übertragen"
        width: 650

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            Label {
                Layout.fillWidth: true
                text: "Playlists, Favoriten, Songstellen und Klangwerte werden übertragen. Musikdateien, Lautstärke, Timer und Warteschlange bleiben lokal."
                wrapMode: Text.Wrap
            }
            FormButton {
                text: "Sammlung exportieren…"

                onClicked: {
                    let path = desktop.saveFile("Sammlung exportieren", "Sammlung.savagecollection", "Savage-Sammlung (*.savagecollection)");
                    if (path)
                        send("collectionExport", {
                            path: path
                        });
                }
            }
            FormButton {
                text: "Sammlung importieren…"

                onClicked: desktop.importCollection()
            }
            Label {
                Layout.fillWidth: true
                color: secondary
                text: "Vor dem Import werden lokale Titelzuordnung und Konfliktentscheidungen geprüft."
                wrapMode: Text.Wrap
            }
        }
    }
    Dialog {
        id: exchangeDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        height: Math.min(680, window.height - 60)
        modal: true
        standardButtons: Dialog.Cancel
        title: "Sammlungsimport prüfen"
        width: Math.min(950, window.width - 60)

        onRejected: send("collectionCancel")

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                font.bold: true
                text: (exchange.playlists || 0) + " Playlists · " + (exchange.markers || 0) + " Songstellen"
            }
            Label {
                Layout.fillWidth: true
                text: "Titel zuordnen oder ausdrücklich überspringen. Vorhandene Musik wird nicht verändert."
                wrapMode: Text.Wrap
            }
            ScrollView {
                id: exchangeScroll

                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    spacing: 10
                    width: exchangeScroll.availableWidth

                    Repeater {
                        model: exchange.tracks || []

                        RowLayout {
                            required property var modelData

                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: modelData.name + (modelData.relativePath ? "\n" + modelData.relativePath : "")
                            }
                            FormCombo {
                                Layout.preferredWidth: 400
                                currentIndex: Math.max(0, model.findIndex(t => t.id === modelData.mapped))
                                model: [
                                    {
                                        id: "",
                                        name: "Bitte zuordnen…"
                                    },
                                    {
                                        id: "__skip__",
                                        name: "Überspringen"
                                    }
                                ].concat(library.tracks || [])
                                textRole: "name"
                                valueRole: "id"

                                onActivated: send("collectionMap", {
                                    track: modelData.id,
                                    text: currentValue
                                })
                            }
                        }
                    }
                    Repeater {
                        model: exchange.conflicts || []

                        RowLayout {
                            required property var modelData

                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: modelData.name
                            }
                            FormCombo {
                                property var choices: modelData.allowed

                                currentIndex: choices.indexOf(modelData.selected) + 1
                                model: ["Konflikt entscheiden…"].concat(choices.map(c => ({
                                            keepLocal: "Lokal behalten",
                                            useIncoming: "Import übernehmen",
                                            keepBoth: "Beide behalten"
                                        })[c]))

                                onActivated: {
                                    if (currentIndex > 0)
                                        send("collectionResolve", {
                                            text: modelData.key,
                                            choice: choices[currentIndex - 1]
                                        });
                                }
                            }
                        }
                    }
                }
            }
            FormButton {
                enabled: exchange.ready || false
                text: "Geprüfte Sammlung importieren"

                onClicked: send("collectionApply")
            }
        }
    }
    Dialog {
        id: syncDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        modal: true
        standardButtons: Dialog.Close
        title: "Sammlung abgleichen"
        width: 580

        Label {
            text: "CloudKit setzt Apples iCloud-Framework und eine von Apple signierte App voraus. Diese Schnittstelle steht unter Linux nicht zur Verfügung. Sammlungen lassen sich über ‚Sammlung übertragen…‘ mit Mac und iPhone austauschen."
            width: parent.width
            wrapMode: Text.Wrap
        }
    }
    Dialog {
        id: keyboardDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        modal: true
        standardButtons: Dialog.Close
        title: "Tastenkürzel"
        width: 500

        Label {
            font.family: "monospace"
            lineHeight: 1.7
            text: "Leertaste                 Abspielen / Pause\nPfeile                    Vorheriger / nächster Titel\nCtrl+O                    Öffnen\nCtrl+,                    Einstellungen\nCtrl+F                    Titel filtern\nCtrl+Shift+N              Notenregen\nCtrl+Plus / Minus / 0     Schriftgröße\nEsc                       Suche verlassen"
            width: parent.width
        }
    }
    Dialog {
        id: aboutDialog

        anchors.centerIn: parent
        font.pixelSize: 13
        modal: true
        standardButtons: Dialog.Close
        title: "Über Savage Mod Player"
        width: 600

        Rectangle {
            border.color: "#e5503a"
            border.width: 2
            color: "black"
            height: 240
            width: parent.width

            Column {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    color: "#e5503a"
                    text: "Software Failure. Press left mouse button to continue."

                    font {
                        family: "monospace"
                        pixelSize: 12
                    }
                }
                Text {
                    color: "#e5503a"
                    text: "Guru Meditation #53415641.47454D4F"

                    font {
                        family: "monospace"
                        pixelSize: 14
                    }
                }
                Text {
                    color: "#e5503a"
                    text: "Savage Mod Player " + desktopVersion + " · Daniel Müller\nEigenständige Swift-Replay-Engine · WTFPL"

                    font {
                        family: "monospace"
                        pixelSize: 12
                    }
                }
            }
        }
    }
    Window {
        id: noteWindow

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
            palette: window.palette

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
                            text: m.title || ""
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
                            currentIndex: prefs.noteRainZoomToSong ? 1 : 0
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
                            currentIndex: Math.max(0, model.indexOf(prefs.noteRainHorizon || 4))
                            displayText: currentValue + " s"
                            model: [2, 4, 8]

                            onActivated: option("noteRainHorizon", currentValue)
                        }
                        PlayerButton {
                            dark: window.dark
                            enabled: hasModule
                            hint: s.playing && !s.paused ? "Pause" : "Abspielen"
                            iconName: s.playing && !s.paused ? "pause" : "play"

                            onClicked: send("play")
                        }
                        PlayerButton {
                            dark: window.dark
                            enabled: s.playing || false
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

                        accent: window.accent
                        anchors.fill: parent
                        dark: window.dark
                        data: desktop.notes
                        horizon: horizon.currentValue || 4
                        muted: stableMutes
                        solo: s.solo || []
                        songKeys: m.songKeyRange || []
                        zoomToSong: songRange.currentIndex === 1

                        onRangeChanged: if (noteWindow.visible && zoomToSong && fixedKeyWidth > 0)
                            noteWindow.width = Math.max(420, fixedKeyWidth * geometry().whites.length + 60)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        color: Qt.alpha(backdrop, .96)
                        height: messageColumn.implicitHeight + 48
                        radius: 10
                        visible: !!(!hasModule || !s.playing || desktop.notes.overflow || desktop.notes.preparing && !(desktop.notes.notes || []).length)
                        width: Math.min(parent.width - 48, 480)

                        ColumnLayout {
                            id: messageColumn

                            anchors.centerIn: parent
                            spacing: 8
                            width: parent.width - 48

                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: !hasModule ? "Keine Musik geladen" : !s.playing ? "Bereit für den nächsten Anschlag" : desktop.notes.overflow ? "Vorschau neu starten" : "Notenvorschau wird berechnet …"
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
                                text: !hasModule ? "Öffne ein MOD-, S3M-, XM- oder IT-Modul im Player." : !s.playing ? "Starte die Wiedergabe. Die kommenden Noten fallen zur Klaviatur." : desktop.notes.overflow ? "Starte die Wiedergabe erneut, um die Notenvorschau zu synchronisieren." : ""
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
                                position: s.position || 0,
                                row: s.row || 0
                            })
                        }
                    }
                    PlayerButton {
                        dark: window.dark
                        text: "Songstellen…"

                        onClicked: {
                            window.show();
                            markers.open();
                        }
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
                                    model: m.displayChannels || []

                                    Row {
                                        required property int modelData

                                        opacity: stableMutes[modelData] || (s.solo || []).some(v => v) && !s.solo[modelData] ? .3 : 1
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
                            text: !hasModule ? "Kein Modul" : !s.playing ? "Gestoppt" : s.paused ? "Pausiert" : desktop.notes.preparing ? "Vorschau wird ergänzt …" : "Spielt"
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
}
