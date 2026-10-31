import QtQuick
import QtQuick.Layouts
import "../services"

// A row (or column) of icon buttons that open parts of the shell.
// Which icons appear is controlled by the `shortcuts` map, e.g.
//   { launcher: true, notifications: true, settings: false, power: true }
// A missing key counts as enabled.
Item {
    id: root

    property bool interactive: true
    property bool editMode: false
    property bool transparentBg: false
    // Kept for parity with the other widget contents (the widget draws no text)
    property string customFont: ""
    property var shortcuts: ({ launcher: true, notifications: true, settings: true, power: true })

    // Emitted with the shortcut key when an icon is clicked
    signal triggered(string key)

    readonly property string iconFont: "CaskaydiaCove Nerd Font Mono"

    // Single source of truth for the available shortcuts
    readonly property var allItems: [
        { key: "launcher",      label: "App launcher",  glyph: String.fromCodePoint(0xF003B) },
        { key: "notifications", label: "Notifications", glyph: String.fromCodePoint(0xF009A) },
        { key: "settings",      label: "Settings",      glyph: String.fromCodePoint(0xF0493) },
        { key: "power",         label: "Power",         glyph: String.fromCodePoint(0xF0425) }
    ]

    readonly property var enabledItems: root.allItems.filter(it => !root.shortcuts || root.shortcuts[it.key] !== false)
    readonly property int count: root.enabledItems.length
    // When explicitly set, overrides the shape-based auto-detection
    property var vertical: undefined
    readonly property bool isVertical: (typeof root.vertical === "boolean") ? root.vertical : (root.height > root.width * 1.2)

    DesktopWidgetBackground {
        transparentBg: root.transparentBg
    }

    // Edit-mode placeholder when every icon is switched off
    Text {
        anchors.centerIn: parent
        visible: root.editMode && root.count === 0
        text: "Shortcuts: no icons enabled"
        color: Theme.onPrimaryContainerColor
        font.family: Theme.widgetFont(root.customFont)
        font.pixelSize: 12
        font.bold: true
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: 6
        visible: root.count > 0
        columns: root.isVertical ? 1 : Math.max(1, root.count)
        rows: root.isVertical ? Math.max(1, root.count) : 1
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 4
        columnSpacing: 4

        Repeater {
            model: root.enabledItems

            delegate: Item {
                id: cell
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Largest square that fits the cell; icons scale with the widget
                readonly property real cellSize: Math.min(width, height)

                Rectangle {
                    anchors.centerIn: parent
                    width: cell.cellSize
                    height: cell.cellSize
                    radius: width / 2
                    color: (btnMouse.containsMouse && root.interactive)
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, btnMouse.pressed ? 0.35 : 0.22)
                        : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    color: Theme.onPrimaryContainerColor
                    font.family: root.iconFont
                    font.pixelSize: Math.max(12, Math.round(cell.cellSize * 0.5))
                }

                MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    enabled: root.interactive
                    hoverEnabled: root.interactive
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.triggered(modelData.key)
                }
            }
        }
    }
}
