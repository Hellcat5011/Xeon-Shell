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
    property string customFont: ""

    // Orientation is passed in (the box shape can't be used to guess it, e.g. a 1-icon tray is nearly square)
    property bool vertical: false

    readonly property bool isVertical: root.vertical
    readonly property real crossAxisLength: isVertical ? root.width : root.height
    readonly property real scaleFactor: Math.max(0.6, crossAxisLength / 50)
    // Same formulas DesktopLayout uses to size the tray, so the icons always fill it exactly
    readonly property int iconSize: DesktopLayout.trayIconSize(crossAxisLength)
    readonly property int iconSpacing: DesktopLayout.traySpacing(crossAxisLength)

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
                font.family: Theme.widgetFont(root.customFont)
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
