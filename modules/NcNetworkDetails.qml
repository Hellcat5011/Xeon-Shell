// NcNetworkDetails.qml — connection details, grouped like a details dialog:
//
//            General
//   Interface            Ethernet (enp42s0)
//   Speed                1000 Mb/s
//            IPv4
//   IP Address           192.168.0.20
//
// `rows` = [{header: "General"}, {label, value}, …]. Click a value row to copy it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../services"

Column {
    id: root

    property var rows: []
    readonly property color fg: Theme.onPrimaryContainerColor

    spacing: 2

    Repeater {
        model: root.rows
        delegate: Item {
            id: line
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined

            width: root.width
            height: isHeader ? 30 : 26

            HoverHandler { id: hover; enabled: !line.isHeader }

            Text {
                visible: line.isHeader
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignBottom
                bottomPadding: 3
                text: line.isHeader ? line.modelData.header : ""
                color: root.fg
                font.pixelSize: 13
                font.bold: true
            }

            NcStateFill {
                visible: !line.isHeader
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                radius: Theme.radiusSmall
                color: root.fg
                level: 0.1
                shown: hover.hovered
            }

            RowLayout {
                visible: !line.isHeader
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: line.isHeader ? "" : line.modelData.label
                    color: Qt.alpha(root.fg, 0.6)
                    font.pixelSize: 12
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: line.isHeader ? "" : line.modelData.value
                    color: root.fg
                    font.pixelSize: 13
                    elide: Text.ElideMiddle
                }
                NcIcon {
                    name: "copy"
                    size: 13
                    color: root.fg
                    opacity: hover.hovered ? 0.8 : 0
                }
            }

            MouseArea {
                enabled: !line.isHeader
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["wl-copy", line.modelData.value])
            }
        }
    }
}
