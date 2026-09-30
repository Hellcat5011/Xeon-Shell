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

    readonly property var geom: DesktopLayout.getWidgetGeometry("mpris", DesktopLayout.screenWidth, DesktopLayout.screenHeight)

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
    visible: root.geom.visible

    DepthMask {
        anchors.fill: parent
        screenX: Math.round(root.geom.x)
        screenY: Math.round(root.geom.y)
        screenWidth: root.screen ? root.screen.width : DesktopLayout.screenWidth
        screenHeight: root.screen ? root.screen.height : DesktopLayout.screenHeight

        DesktopMprisContent {
            anchors.fill: parent
            interactive: true
            transparentBg: root.geom.transparentBg
        }
    }
}
