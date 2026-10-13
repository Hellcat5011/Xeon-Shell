// NcRefreshButton.qml — small round rescan button; the icon spins on the GPU
// (RotationAnimator) while `spinning` is true.
import QtQuick
import "../services"

Item {
    id: root

    property bool spinning: false
    signal clicked()

    readonly property color fg: Theme.onPrimaryContainerColor

    implicitWidth: 30
    implicitHeight: 30

    NcStateFill {
        anchors.fill: parent
        radius: width / 2
        color: root.fg
        level: 0.2
        shown: mouse.containsMouse
    }

    NcIcon {
        id: glyph
        anchors.centerIn: parent
        name: "refresh"
        size: 16
        color: root.fg
    }

    RotationAnimator {
        target: glyph
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: root.spinning
        onRunningChanged: if (!running) glyph.rotation = 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
