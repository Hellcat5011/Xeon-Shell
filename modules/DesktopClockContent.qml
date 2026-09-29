import QtQuick
import QtQuick.Layouts
import Quickshell
import "../services"

Item {
    id: root

    property bool interactive: true

    readonly property real defaultWidth: 360
    readonly property real defaultHeight: 180
    readonly property real scaleFactor: Math.max(0.45, Math.min(width / defaultWidth, height / defaultHeight))

    property var currentDate: new Date()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.currentDate = new Date()
    }

    DesktopWidgetBackground {}

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        anchors.margins: Math.round(15 * root.scaleFactor)
        spacing: Math.round(4 * root.scaleFactor)

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: {
                let h = root.currentDate.getHours() % 12 || 12;
                let m = root.currentDate.getMinutes().toString().padStart(2, '0');
                return h + ":" + m;
            }
            color: Theme.onPrimaryContainerColor
            font.family: "CaskaydiaCove Nerd Font Mono"
            font.bold: true
            font.pixelSize: Math.max(24, Math.round(84 * root.scaleFactor))
            elide: Text.ElideRight
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(root.currentDate, "dddd, MMMM dd")
            color: Theme.onPrimaryContainerColor
            font.family: "CaskaydiaCove Nerd Font Mono"
            font.pixelSize: Math.max(10, Math.round(18 * root.scaleFactor))
            elide: Text.ElideRight
        }
    }
}
