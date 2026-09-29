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

    readonly property bool hasItems: SystemTray.items.values.length > 0
    readonly property real defaultTrayWidth: Math.max(50, SystemTray.items.values.length * 36 + 20)
    readonly property var geom: DesktopLayout.getWidgetGeometry("tray", DesktopLayout.screenWidth, DesktopLayout.screenHeight, root.defaultTrayWidth, 50)

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

    DesktopTrayContent {
        id: trayContent
        anchors.fill: parent
        interactive: true
        editMode: false
        anchorWindow: root
    }
}
