import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import "../services"

Item {
    id: root

    property bool interactive: true
    property bool editMode: false
    property var anchorWindow: null
    property bool transparentBg: false

    readonly property real defaultHeight: 50
    readonly property bool isVertical: root.height > root.width * 1.2
    readonly property real crossAxisLength: isVertical ? root.width : root.height
    readonly property real scaleFactor: Math.max(0.6, Math.min(crossAxisLength / defaultHeight, (isVertical ? root.height : root.width) / 60))
    readonly property int iconSize: Math.max(16, Math.min(48, Math.round(24 * (crossAxisLength / defaultHeight))))
    readonly property int iconSpacing: Math.max(4, Math.round(12 * (crossAxisLength / defaultHeight)))

    property real contentWidth: Math.max(50, trayItemsRow.implicitWidth + 30)

    DesktopWidgetBackground {
        transparentBg: root.transparentBg
    }

    QsMenuAnchor {
        id: menuAnchor
        anchor.window: root.anchorWindow
    }

    // Placeholder in edit mode when no tray items are present
    Item {
        anchors.fill: parent
        visible: root.editMode && (SystemTray.items.values.length === 0)

        Grid {
            anchors.centerIn: parent
            spacing: root.isVertical ? 4 : 8
            rows: root.isVertical ? -1 : 1
            columns: root.isVertical ? 1 : -1
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            Text {
                text: "󰀻"
                color: Theme.onPrimaryContainerColor
                font.family: "CaskaydiaCove Nerd Font Mono"
                font.pixelSize: Math.max(14, Math.round(18 * root.scaleFactor))
            }
            Text {
                text: "Tray"
                color: Theme.onPrimaryContainerColor
                font.family: "CaskaydiaCove Nerd Font Mono"
                font.pixelSize: Math.max(11, Math.round(14 * root.scaleFactor))
                font.bold: true
            }
        }
    }

    Grid {
        id: trayItemsRow
        anchors.centerIn: parent
        spacing: root.iconSpacing
        visible: SystemTray.items.values.length > 0
        rows: root.isVertical ? -1 : 1
        columns: root.isVertical ? 1 : -1
        flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight

        Repeater {
            model: SystemTray.items

            delegate: MouseArea {
                id: itemDelegate
                width: root.iconSize
                height: root.iconSize
                hoverEnabled: root.interactive
                enabled: root.interactive
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                IconImage {
                    anchors.fill: parent
                    source: modelData.icon || ""
                    opacity: itemDelegate.containsMouse ? 0.7 : 1.0
                }

                onClicked: (mouse) => {
                    if (!root.interactive) return;
                    if (mouse.button === Qt.LeftButton) {
                        modelData.activate();
                    } else if (mouse.button === Qt.RightButton) {
                        if (modelData.hasMenu && menuAnchor.anchor.window) {
                            let p = itemDelegate.mapToItem(null, 0, 0);
                            menuAnchor.anchor.rect = Qt.rect(p.x, p.y + height + 5, width, 0);
                            menuAnchor.anchor.edges = Qt.BottomEdge;
                            menuAnchor.menu = modelData.menu;
                            menuAnchor.open();
                        } else {
                            modelData.secondaryActivate();
                        }
                    }
                }
            }
        }
    }
}
