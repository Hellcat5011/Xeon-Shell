// QuickToggle.qml — a tab tile in the top row.
//
//   • `selected` tiles are the open tab: they widen (via Layout.preferredWidth)
//     and show a title, optional subtitle and optional count pill.
//   • all other tiles collapse to an icon-only square.
//   • `on` fills a tile without widening it (used by the Caffeinate toggle).
//
// The icon keeps the same x in both states, so it never jumps while the tile
// resizes. Colour changes are an opacity cross-fade between two content layers.
import QtQuick
import QtQuick.Layouts
import "../services"

Item {
    id: root

    property string iconName: "bell"
    property string title: ""
    property string subtitle: ""
    property string countText: ""
    property bool   selected: false
    property bool   on: false
    property bool   dimmed: false      // feature is off → icon dimmed
    property bool   slashed: false
    property int    badge: 0           // red corner badge while collapsed
    property real   expandedWidth: 200
    signal clicked()

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property bool  filled: selected || on
    readonly property real  textWidth: Math.max(10, expandedWidth - 52)

    implicitHeight: 44
    Layout.preferredWidth: selected ? expandedWidth : 44
    Behavior on Layout.preferredWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    HoverHandler { id: hover }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Qt.alpha(root.fg, 0.2)
        clip: true

        StateFill {
            anchors.fill: parent
            radius: bg.radius
            color: root.fg
            level: 0.14
            shown: hover.hovered && !root.filled
        }
        StateFill {
            anchors.fill: parent
            radius: bg.radius
            color: root.fg
            level: hover.hovered ? 1.0 : 0.85
            shown: root.filled
        }

        // Layer A — idle colours
        Item {
            anchors.fill: parent
            opacity: root.filled ? 0 : 1
            Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }
            Icon {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: root.iconName
                size: 20
                slashed: root.slashed
                color: root.fg
                opacity: root.dimmed ? 0.5 : 1
            }
        }

        // Layer B — filled colours + text
        Item {
            anchors.fill: parent
            opacity: root.filled ? 1 : 0
            Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }

            Icon {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: root.iconName
                size: 20
                slashed: root.slashed
                color: Theme.inversePrimary
            }

            Column {
                x: 40
                width: root.textWidth
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                visible: root.title !== ""

                RowLayout {
                    width: parent.width
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: root.title
                        color: Theme.inversePrimary
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: root.countText !== ""
                        implicitWidth: Math.max(20, countLabel.implicitWidth + 12)
                        implicitHeight: 18
                        radius: 9
                        color: Theme.inversePrimary
                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: root.countText
                            color: Theme.onPrimaryContainerColor
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }
                Text {
                    width: parent.width
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    color: Qt.alpha(Theme.inversePrimary, 0.8)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }
    }

    Rectangle {
        visible: root.badge > 0 && !root.selected
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -4
        anchors.rightMargin: -4
        width: Math.max(18, badgeText.implicitWidth + 8)
        height: 18
        radius: 9
        color: Theme.error
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge > 99 ? "99+" : root.badge
            color: "white"
            font.pixelSize: 10
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
