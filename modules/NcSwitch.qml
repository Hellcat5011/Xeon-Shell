// NcSwitch.qml — toggle switch. Does not flip itself: bind `checked` to the
// real state and act on `toggled()`. The knob slides with an XAnimator and
// the track/knob colours cross-fade via opacity — all render-thread work.
import QtQuick
import "../services"

Item {
    id: root

    property bool checked: false
    signal toggled()

    readonly property color fg: Theme.onPrimaryContainerColor

    implicitWidth: 42
    implicitHeight: 24
    opacity: enabled ? 1 : 0.45

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(root.fg, 0.25)
    }
    NcStateFill {
        anchors.fill: parent
        radius: track.radius
        color: root.fg
        level: 0.85
        shown: root.checked
    }

    Rectangle {
        id: knob
        width: 18; height: 18; radius: 9
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        color: root.fg
        Behavior on x { XAnimator { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        NcStateFill {
            anchors.fill: parent
            radius: knob.radius
            color: Theme.inversePrimary
            shown: root.checked
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
