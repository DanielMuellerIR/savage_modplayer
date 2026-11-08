import QtQuick
import QtQuick.Window
import QtTest
import "../../linux/gui" as Player

TestCase {
    id: testCase
    name: "VisualizerVisibility"
    when: windowShown
    visible: true
    width: 400
    height: 300
    property var desktop: bridge
    property string desktopVersion: "test"
    property QtObject desktopUpdates: QtObject {
        property bool automaticallyChecks: false
        property bool busy: false
        property bool installed: false
        property bool canInstall: false
        property real progress: 0
        property string status: "Aktuell"
        property string offeredVersion: ""
        property string notes: ""
        signal showDialog()
        function check() { showDialog(); }
        function install() { busy = true; progress = .5; status = "Update wird installiert …"; }
        function cancel() { busy = false; status = "Aktualisierung abgebrochen."; }
    }
    QtObject {
        id: bridge
        property var state: ({})
        property var visualizer: ({})
        property var module: ({})
        property var library: ({})
        property var preferences: ({})
        property var pattern: ({})
        property var notes: ({})
        property bool visualsDisabled: false
        signal message(string event, var values)
        function command(name, values) {
            if (name === "compact") visualsDisabled = values.enabled;
        }
        function option(name, value) {}
    }
    Player.Main { id: player }

    function test_resize_hide_and_minimize_stop_visualization() {
        player.width = 1440;
        player.height = 900;
        player.show();
        bridge.message("ready", {});
        tryCompare(player, "compact", false);
        tryCompare(bridge, "visualsDisabled", false);
        let scopes = findChild(player, "channelScopes");
        verify(scopes !== null);
        compare(scopes.visible, true);
        player.width = 780;
        player.height = 600;
        tryCompare(player, "compact", true);
        tryCompare(bridge, "visualsDisabled", true);
        compare(scopes.visible, false);
        player.width = 1440;
        player.height = 900;
        tryCompare(player, "compact", false);
        tryCompare(bridge, "visualsDisabled", false);
        player.hide();
        tryCompare(bridge, "visualsDisabled", true);
        player.show();
        tryCompare(bridge, "visualsDisabled", false);
        player.showMinimized();
        tryCompare(bridge, "visualsDisabled", true);
        player.showNormal();
        tryCompare(bridge, "visualsDisabled", false);
        player.hide();
    }
    function test_settings_stay_inside_small_window_at_large_font() {
        player.width = 780;
        player.height = 600;
        bridge.preferences = ({zoom: 5});
        player.show();
        player.reviewView("settings");
        let dialog = findChild(player, "settingsDialog");
        let scroll = findChild(player, "settingsScroll");
        verify(dialog !== null && scroll !== null);
        tryCompare(dialog, "opened", true);
        verify(dialog.height <= player.height - 40);
        tryVerify(() => dialog.y >= 0 && dialog.y + dialog.height <= player.height, 1000, JSON.stringify({y:dialog.y,height:dialog.height,windowHeight:player.height,parentHeight:dialog.parent.height}));
        verify(scroll.contentHeight > scroll.availableHeight, JSON.stringify({content:scroll.contentHeight, available:scroll.availableHeight, implicit:scroll.implicitHeight, height:dialog.height, font:player.fontScale}));
        dialog.close();
        player.hide();
    }

    function test_update_controls_require_confirmation_and_keep_notes_plain() {
        player.width = 780; player.height = 600;
        bridge.preferences = ({zoom: 5}); player.show();
        player.reviewView("settings");
        let checks = findChild(player, "automaticUpdateChecks");
        desktopUpdates.automaticallyChecks = true;
        tryCompare(checks, "checked", true);
        let scroll = findChild(player, "settingsScroll");
        scroll.contentItem.contentY = scroll.contentHeight - scroll.availableHeight;
        waitForRendering(checks);
        mouseClick(checks); compare(desktopUpdates.automaticallyChecks, false);
        mouseClick(findChild(player, "checkUpdatesButton"));
        let dialog = findChild(player, "updateDialog");
        tryCompare(dialog, "opened", true);
        let install = findChild(player, "installUpdateButton");
        compare(install.visible, false);
        desktopUpdates.offeredVersion = "1.6.59";
        desktopUpdates.canInstall = true;
        desktopUpdates.notes = "<b>Plain release notes</b>";
        desktopUpdates.status = "Version 1.6.59 ist verfügbar.";
        tryCompare(install, "enabled", true);
        compare(desktopUpdates.busy, false);
        mouseClick(install); compare(desktopUpdates.busy, true);
        compare(install.enabled, false);
        mouseClick(findChild(player, "cancelUpdateButton"));
        compare(desktopUpdates.busy, false); compare(desktopUpdates.installed, false);
        mouseClick(install); compare(desktopUpdates.busy, true);
        desktopUpdates.installed = true; desktopUpdates.busy = false;
        desktopUpdates.status = "Version 1.6.59 ist installiert. Sie wird beim nächsten Start verwendet.";
        tryCompare(install, "visible", false);
        tryVerify(() => dialog.height <= player.height - 40 && dialog.y >= 0 && dialog.y + dialog.height <= player.height);
        dialog.close(); findChild(player, "settingsDialog").close(); player.hide();
    }

}
