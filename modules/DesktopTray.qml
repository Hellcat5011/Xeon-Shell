import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import "../services"

PanelWindow {
    id: root
    screen: DesktopLayout.primaryScreen

    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "desktop"
    color: "transparent"

    readonly property int itemCount: SystemTray.items.values.length
    readonly property bool hasItems: itemCount > 0
    // Length follows the icon count; position/edge-pinning come from the saved layout
    readonly property var geom: DesktopLayout.getTrayGeometry(root.itemCount, DesktopLayout.screenWidth, DesktopLayout.screenHeight)

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

    // Auto-hide on live desktop when empty
    visible: root.geom.visible && root.hasItems

    DepthMask {
        anchors.fill: parent
        enabled: root.geom.sendToBackground === true
        screenX: Math.round(root.geom.x)
        screenY: Math.round(root.geom.y)
        screenWidth: root.screen ? root.screen.width : DesktopLayout.screenWidth
        screenHeight: root.screen ? root.screen.height : DesktopLayout.screenHeight

        DesktopTrayContent {
            id: trayContent
            anchors.fill: parent
            interactive: true
            editMode: false
            vertical: root.geom.vertical
            anchorWindow: root
            transparentBg: root.geom.transparentBg
            customFont: root.geom.fontFamily || ""
        }
    }
}
