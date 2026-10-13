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

    // Shortcut key -> IPC target handled in shell.qml
    readonly property var ipcTargets: ({
        launcher: "launcher",
        notifications: "notif",
        settings: "settings",
        power: "power"
    })

    function trigger(key) {
        let target = root.ipcTargets[key];
        if (!target) return;
        Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", target, "toggle"]);
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

    // Optional widget: hidden until added from the "+" menu in edit mode,
    // and hidden while every icon is switched off.
    visible: root.geom.visible && shortcutsContent.count > 0

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
            onTriggered: key => root.trigger(key)
        }
    }
}
