// NcButton.qml — pill button. Same palette rules as the launcher rows:
// idle = onPrimaryContainer @ 20 %, active = @ 85 % with inversePrimary text.
//
// Hover/active are separate fills whose opacity is animated on the GPU, and
// the label cross-fades between its two colours (no ColorAnimation anywhere).
import QtQuick
import "../services"

Item {
    id: root

    property string text: ""
    property string iconName: ""
    property bool   active: false
    property bool   compact: false
    property real   fontSize: compact ? 12 : 13
    signal clicked()

    readonly property color fg: Theme.onPrimaryContainerColor

    implicitHeight: compact ? 28 : 34
    implicitWidth: measure.implicitWidth + (compact ? 20 : 28)
    opacity: enabled ? 1 : 0.45

    // One label+icon row; instantiated once per colour. Inputs are passed in
    // explicitly (no reliance on the outer `root` id from inside the component).
    component Content: Row {
        property color  tint: "white"
        property string label: ""
        property string glyph: ""
        property real   glyphSize: 16
        property real   fontPx: 13
        anchors.centerIn: parent
        spacing: 6
        NcIcon {
            visible: parent.glyph !== ""
            name: parent.glyph
            size: parent.glyphSize
            color: parent.tint
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: parent.label !== ""
            text: parent.label
            color: parent.tint
            font.pixelSize: parent.fontPx
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        id: base
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Qt.alpha(root.fg, 0.2)
    }
    NcStateFill {
        anchors.fill: parent
        radius: base.radius
        color: root.fg
        level: 0.14
        shown: mouse.containsMouse && !root.active
    }
    NcStateFill {
        anchors.fill: parent
        radius: base.radius
        color: root.fg
        level: mouse.containsMouse ? 1.0 : 0.85
        shown: root.active
    }

    // Sizing helper (invisible) so implicitWidth tracks the content.
    Content {
        id: measure
        visible: false
        anchors.centerIn: undefined
        tint: root.fg; label: root.text; glyph: root.iconName
        glyphSize: root.compact ? 14 : 16; fontPx: root.fontSize
    }

    Content {
        tint: root.fg; label: root.text; glyph: root.iconName
        glyphSize: root.compact ? 14 : 16; fontPx: root.fontSize
        opacity: root.active ? 0 : 1
        Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }
    }
    Content {
        tint: Theme.inversePrimary; label: root.text; glyph: root.iconName
        glyphSize: root.compact ? 14 : 16; fontPx: root.fontSize
        opacity: root.active ? 1 : 0
        Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
