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

    readonly property real screenW: root.screen ? root.screen.width : DesktopLayout.screenWidth
    readonly property real screenH: root.screen ? root.screen.height : DesktopLayout.screenHeight
    readonly property var geom: DesktopLayout.getWidgetGeometry("clock", root.screenW, root.screenH, 360, 180)

    readonly property real clampedW: Math.min(root.screenW, Math.round(root.geom.w))
    readonly property real clampedH: Math.min(root.screenH, Math.round(root.geom.h))
    readonly property real clampedX: Math.max(0, Math.min(root.screenW - root.clampedW, Math.round(root.geom.x)))
    readonly property real clampedY: Math.max(0, Math.min(root.screenH - root.clampedH, Math.round(root.geom.y)))

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.clampedY
        left: root.clampedX
    }

    implicitWidth: root.clampedW
    implicitHeight: root.clampedH
    visible: root.geom.visible

    DepthMask {
        id: depthMask
        anchors.fill: parent
        enabled: root.geom.sendToBackground === true
        screenX: root.clampedX
        screenY: root.clampedY
        screenWidth: root.screenW
        screenHeight: root.screenH

        DesktopClockContent {
            anchors.fill: parent
            interactive: true
            transparentBg: root.geom.transparentBg
            hideDate: root.geom.hideDate === true
            customFont: root.geom.fontFamily || ""
        }
    }
}
