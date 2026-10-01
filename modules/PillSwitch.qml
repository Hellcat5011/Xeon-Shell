import QtQuick
import "../services"

Item {
    id: root
    width: 50
    height: 28
    implicitWidth: 50
    implicitHeight: 28

    property bool checked: false
    signal toggled(bool value)

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.primary : Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.4)
        
        Behavior on color {
            ColorAnimation { duration: 200; easing.type: Theme.easeOut }
        }

        Rectangle {
            id: thumb
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: root.checked ? (track.width - width - 3) : 3
            color: root.checked ? Theme.primaryText : Theme.onPrimaryContainerColor

            Behavior on x {
                NumberAnimation { duration: 200; easing.type: Theme.easeOut }
            }
            Behavior on color {
                ColorAnimation { duration: 200; easing.type: Theme.easeOut }
            }

            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.1)
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
