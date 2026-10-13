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

    readonly property var geom: DesktopLayout.getWidgetGeometry("analogclock", DesktopLayout.screenWidth, DesktopLayout.screenHeight)

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

    // Optional widget: hidden until the user adds it from the "+" menu in edit mode
    visible: root.geom.visible

    DepthMask {
        anchors.fill: parent
        enabled: root.geom.sendToBackground === true
        screenX: Math.round(root.geom.x)
        screenY: Math.round(root.geom.y)
        screenWidth: root.screen ? root.screen.width : DesktopLayout.screenWidth
        screenHeight: root.screen ? root.screen.height : DesktopLayout.screenHeight

        DesktopAnalogClockContent {
            anchors.fill: parent
            interactive: true
            editMode: false
            running: root.geom.visible
            transparentBg: root.geom.transparentBg
            customFont: root.geom.fontFamily || ""
        }
    }
}
