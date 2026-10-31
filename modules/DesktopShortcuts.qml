import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"

PanelWindow {
    id: root
    screen: DesktopLayout.primaryScreen

    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "desktop"
    color: "transparent"

    readonly property var geom: DesktopLayout.getWidgetGeometry("shortcuts", DesktopLayout.screenWidth, DesktopLayout.screenHeight)

    // Count enabled shortcuts directly from geom data (avoids a forward-reference
    // to the child shortcutsContent, which hasn't been created yet when PanelWindow
    // first evaluates its own `visible` binding — causing it to permanently stick at false).
    readonly property int enabledShortcutCount: {
        let sc = root.geom.shortcuts;
        let keys = ["launcher", "notifications", "settings", "power"];
        let n = 0;
        for (let i = 0; i < keys.length; i++) {
            if (!sc || sc[keys[i]] !== false) n++;
        }
        return n;
    }

    signal shortcutTriggered(string key)

    function trigger(key) {
        root.shortcutTriggered(key);
    }

    anchors {
        top: true
        left: true
    }

    margins {
        top: Math.round(root.geom.y)
        left: Math.round(root.geom.x)
    }

    implicitWidth: Math.round(root.geom.w)
    implicitHeight: Math.round(root.geom.h)

    // Hidden until added from the "+" menu in edit mode, and while every icon is off.
    // Uses enabledShortcutCount (a root property) instead of shortcutsContent.count
    // to avoid the forward-reference timing bug.
    visible: root.geom.visible && root.enabledShortcutCount > 0

    DepthMask {
        anchors.fill: parent
        enabled: root.geom.sendToBackground === true
        screenX: Math.round(root.geom.x)
        screenY: Math.round(root.geom.y)
        screenWidth: root.screen ? root.screen.width : DesktopLayout.screenWidth
        screenHeight: root.screen ? root.screen.height : DesktopLayout.screenHeight

        DesktopShortcutsContent {
            id: shortcutsContent
            anchors.fill: parent
            interactive: true
            editMode: false
            transparentBg: root.geom.transparentBg
            customFont: root.geom.fontFamily || ""
            shortcuts: root.geom.shortcuts
            vertical: root.geom.vertical
            onTriggered: key => root.trigger(key)
        }
    }
}
