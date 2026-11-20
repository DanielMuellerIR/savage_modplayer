import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

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
    property real fontScale: Math.max(0.7, Math.min(1.8, 1 + (prefs.zoom || 0) * 0.13))
    property bool hasModule: !!m.title
    property var indexStatus: ({})
    property var inspection: ({})
    property var instrumentDetails: ({})
    property var library: desktop.library
    property var m: desktop.module
    property string markerRevision: ""
    property bool pendingSamples: false
    property var prefs: desktop.preferences
    property color primary: dark ? "#eceef0" : "#13171d"
    property bool queryActive: !!((library.query || {}).search || (library.query || {}).favoritesOnly || (library.query || {}).format || (library.query || {}).minimumChannels || (library.query || {}).unheardOnly || (library.query || {}).addedWithinDays || (library.query || {}).reversed || ((library.query || {}).sort && library.query.sort !== "sourceOrder"))
    property var visuals: desktop.visualizer
    property var s: desktop.state
    property var sample: ({})
    property color secondary: dark ? "#9ea8b0" : "#576170"
    property var sectionEnd: ({
            position: -1,
            row: 0
        })
    property var sectionStart: ({
            position: -1,
            row: 0
        })
    property int sidebarTab: 0
    property var sound: s.sound || prefs
    property var stableMutes: []
    property color surface: dark ? "#131518" : "#f6f7fa"
    property bool validSection: sectionStart.position >= 0 && sectionEnd.position >= 0 && (sectionEnd.position > sectionStart.position || sectionEnd.position === sectionStart.position && sectionEnd.row >= sectionStart.row)

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
    function clearSectionSelection() {
        sectionStart = { position: -1, row: 0 };
        sectionEnd = { position: -1, row: 0 };
    }
    function option(name, value) {
        desktop.option(name, value);
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
        if (name === "updates") {
            desktopUpdates.check();
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
        }
    }

    function syncVisualizerVisibility() {
        send("compact", { enabled: compact || !visible || visibility === Window.Minimized });
    }
    onCompactChanged: syncVisualizerVisibility()
    onVisibilityChanged: syncVisualizerVisibility()

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
                text: "Nach Updates suchen…"
                onTriggered: desktopUpdates.check()
            }
            MenuSeparator {}
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
            if (event === "ready") {
                syncVisualizerVisibility();
            } else if (event === "loading" && values.active) {
                expanded = {};
                sidebarTab = 0;
            } else if (event === "state") {
                if (JSON.stringify(stableMutes) !== JSON.stringify(values.muted))
                    stableMutes = values.muted;
            } else if (event === "error" || event === "notice") {
                errorMessage = values.message;
                errorDialog.open();
                exportSession.exporting = false;
            } else if (event === "module") {
                if (markerRevision && markerRevision !== values.revision) {
                    markers.close();
                    clearSectionSelection();
                }
                markerRevision = values.revision;
            } else if (event === "inspection") {
                inspection = values;
                if (pendingSamples) {
                    pendingSamples = false;
                    let first = (values.samples || [])[0];
                    if (first)
                        sampleDialog.showSample(first.id, 0);
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
                exportSession.exportTitle = values.title;
            else if (event === "videoPreviewState")
                exportSession.videoPreparing = values.active;
            else if (event === "videoPreview") {
                exportSession.videoPreviewPath = values.path;
                exportSession.exporting = false;
            } else if (event === "cancelled") {
                exportSession.exporting = false;
                exportSession.videoPreparing = false;
            } else if (event === "indexing")
                indexStatus = values;
            else if (event === "progress") {
                exportSession.exportProgress = values.value;
                exportSession.exporting = true;
            } else if (event === "complete") {
                exportSession.exporting = false;
                exportSession.exportProgress = 1;
                exportSession.exportResult = values.path;
                exportSession.exportReport = values.report || {};
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

                                                                color: ((visuals.vu || [])[parent.parent.parent.modelData] || 0) >= threshold ? (threshold > .85 ? "#ff3b30" : threshold > .65 ? "#ff9500" : threshold > .4 ? (dark ? "#9eb3c2" : accent) : (dark ? accent : Qt.alpha(accent, .65))) : (dark ? Qt.rgba(1, 1, 1, .04) : Qt.rgba(0, 0, 0, .07))
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
                                                        samples: (visuals.waves || [])[parent.parent.modelData] || []
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
                                samples: visuals.master || []
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
    Connections {
        target: desktopUpdates
        function onShowDialog() { updateDialog.open(); }
    }
    UpdateDialog {
        id: updateDialog

        secondary: window.secondary
        fontScale: window.fontScale
        updates: desktopUpdates
        width: Math.min(520, window.width - 40)
        height: Math.min(implicitHeight, window.height - 40)
    }
    SettingsDialog {
        id: settings

        secondary: window.secondary
        fontScale: window.fontScale
        darkTheme: window.dark
        preferences: window.prefs
        option: window.option
        updates: desktopUpdates
        chooseFolder: title => desktop.chooseFolder(title)
        width: Math.min(460, window.width - 40)
        height: Math.min(implicitHeight, window.height - 40)
    }
    LibraryFiltersDialog {
        id: filters

        secondary: window.secondary
        darkTheme: window.dark
        library: window.library
        send: window.send
        indexStatus: window.indexStatus
        changeQuery: window.changeQuery
        width: Math.min(700, window.width - 40)
        height: Math.min(720, window.height - 40)
    }
    SavedPlaylistsDialog {
        id: playlists

        secondary: window.secondary
        send: window.send
        library: window.library
        fontScale: window.fontScale
        confirmationWidth: Math.min(450, window.width - 40)
        width: Math.min(720, window.width - 40)
        height: Math.min(520, window.height - 40)
    }
    TrackQueueDialog {
        id: queueDialog

        secondary: window.secondary
        send: window.send
        entries: window.library.queue || []
        height: Math.min(500, window.height - 60)
    }
    SleepTimerDialog {
        id: timerDialog

        secondary: window.secondary
        send: window.send
        option: window.option
        savedMinutes: window.prefs.sleepTimerMinutes || 15
        playbackState: window.s
        time: window.time
    }
    TrackSettingsDialog {
        id: trackSettings

        send: window.send
        preferences: window.prefs
        darkTheme: window.dark
        moduleInfo: window.m
        sound: window.sound
    }
    QtObject {
        id: exportSession

        property bool exporting: false
        property real exportProgress: 0
        property var exportReport: ({})
        property string exportResult: ""
        property string exportTitle: ""
        property bool videoPreparing: false
        property string videoPreviewPath: ""
    }
    MarkerDialog {
        id: markers

        addressText: window.addressText
        height: Math.min(760, window.height - 40)
        moduleInfo: window.m
        playbackState: window.s
        secondary: window.secondary
        sectionEnd: window.sectionEnd
        sectionStart: window.sectionStart
        validSection: window.validSection
        width: Math.min(760, window.width - 40)

        onBoundaryRequested: (isStart, position, row) => {
            const address = { position, row };
            if (isStart)
                window.sectionStart = address;
            else
                window.sectionEnd = address;
        }
        onClearSectionRequested: window.clearSectionSelection()
        onCommandRequested: (name, values) => window.send(name, values)
    }
    ModuleInspectorDialog {
        id: inspector

        accent: window.accent
        backdrop: window.backdrop
        primary: window.primary
        secondary: window.secondary
        send: window.send
        fontScale: window.fontScale
        inspection: window.inspection
        instrumentDetails: window.instrumentDetails
        width: Math.min(760, window.width - 40)
        height: Math.min(760, window.height - 40)
    }
    SampleInspectorDialog {
        id: sampleDialog

        inspection: window.inspection
        sample: window.sample
        darkTheme: window.dark
        send: window.send
        accent: window.accent
        primary: window.primary
        secondary: window.secondary
        width: Math.min(760, window.width - 40)
        height: Math.min(760, window.height - 40)
    }
    WAVExportDialog {
        id: exportDialog

        secondary: window.secondary
        send: window.send
        fontScale: window.fontScale
        session: exportSession
        fileDialogs: desktop
        moduleInfo: window.m
        width: Math.min(420, window.width - 40)
    }
    BatchExportDialog {
        id: batchDialog

        secondary: window.secondary
        send: window.send
        fontScale: window.fontScale
        session: exportSession
        fileDialogs: desktop
        darkTheme: window.dark
        library: window.library
        preferences: window.prefs
        width: Math.min(600, window.width - 40)
        height: Math.min(640, window.height - 40)
    }
    VideoExportDialog {
        id: videoDialog

        secondary: window.secondary
        send: window.send
        fontScale: window.fontScale
        session: exportSession
        fileDialogs: desktop
        darkTheme: window.dark
        playbackState: window.s
        height: Math.min(720, window.height - 40)
    }
    CollectionTransferDialog {
        id: collection

        secondary: window.secondary
        send: window.send
        saveFile: (title, name, filter) => desktop.saveFile(title, name, filter)
        importCollection: () => desktop.importCollection()
    }
    CollectionImportDialog {
        id: exchangeDialog

        send: window.send
        library: window.library
        exchange: window.exchange
        width: Math.min(950, window.width - 60)
        height: Math.min(680, window.height - 60)
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
    AboutDialog {
        id: aboutDialog

        version: desktopVersion
    }
    NoteRainWindow {
        id: noteWindow

        backdrop: window.backdrop
        accent: window.accent
        secondary: window.secondary
        darkTheme: window.dark
        playerPalette: window.palette
        moduleInfo: window.m
        hasModule: window.hasModule
        mutedChannels: window.stableMutes
        notes: desktop.notes
        playbackState: window.s
        preferences: window.prefs
        send: window.send
        option: window.option
        sectionStart: window.sectionStart
        sectionEnd: window.sectionEnd
        validSection: window.validSection
        addressText: window.addressText

        onMarkersRequested: {
            window.show();
            markers.open();
        }
    }
}
