import QtQuick
import QtQuick.Layouts
import Quickshell
import "../services"

Item {
    id: root

    property bool interactive: true
    property bool transparentBg: false
    property bool hideDate: false
    property string customFont: ""

    readonly property real defaultWidth: 360
    readonly property real defaultHeight: root.hideDate ? 120 : 180
    readonly property real scaleFactor: Math.max(0.45, Math.min(width / defaultWidth, height / defaultHeight))

    property var currentDate: new Date()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.currentDate = new Date()
    }

    DesktopWidgetBackground {
        transparentBg: root.transparentBg
    }

    Item {
        id: container
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Math.round(16 * root.scaleFactor)

        ColumnLayout {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Math.round(4 * root.scaleFactor)

            Text {
                id: timeText
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: {
                    let h = root.currentDate.getHours() % 12 || 12;
                    let m = root.currentDate.getMinutes().toString().padStart(2, '0');
                    return h + ":" + m;
                }
                color: Theme.onPrimaryContainerColor
                font.family: Theme.widgetFont(root.customFont)
                font.bold: true
                font.pixelSize: Math.max(24, Math.round(Math.min(container.width * 0.6, container.height * (root.hideDate ? 0.95 : 0.8))))
                fontSizeMode: Text.Fit
                minimumPixelSize: 18
                elide: Text.ElideRight
            }

            Text {
                id: dateText
                visible: !root.hideDate
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Math.max(16, Math.round(Math.min(36, container.height * 0.18))) : 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Qt.formatDate(root.currentDate, "dddd, MMMM dd")
                color: Theme.onPrimaryContainerColor
                font.family: Theme.widgetFont(root.customFont)
                font.pixelSize: Math.max(10, Math.round(Math.min(24, container.height * 0.14)))
                fontSizeMode: Text.Fit
                minimumPixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}
