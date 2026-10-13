// NcNotificationGroup.qml — one app's notifications.
//
// Collapsed: icon/preview · app name · time · [count ⌄]
//            latest "title body" line + previous line (dimmer)
// Expanded:  header stays; the preview lines collapse away and every
//            notification is listed as an inset card with its actions.
// Accordion: only one group is open at a time (NotificationManager.expandedGroup).
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import "../services"

Item {
    id: root

    required property string key                       // ListModel role

    readonly property color fg: Theme.onPrimaryContainerColor

    // Live data, plus a last-known copy so the card keeps rendering while the
    // list plays its remove transition (the manager has already dropped it).
    readonly property var items: NotificationManager.groupsMap[key] ?? []
    property var snap: []
    onItemsChanged: if (items.length > 0) snap = items
    Component.onCompleted: if (items.length > 0) snap = items

    readonly property var  latest: snap.length > 0 ? snap[0] : null
    readonly property var  previous: snap.length > 1 ? snap[1] : null
    readonly property int  total: snap.length
    readonly property bool expanded: NotificationManager.expandedGroup === key
    readonly property bool critical: latest ? latest.urgency === NotificationUrgency.Critical : false

    width: ListView.view ? ListView.view.width : 360
    height: card.height

    // One "title  body" line. Title bold, body dim and elided.
    component PreviewLine: RowLayout {
        property string title: ""
        property string text: ""
        property real dim: 1.0
        property bool boldTitle: true
        spacing: 6
        Text {
            visible: parent.title !== ""
            text: parent.title
            color: Qt.alpha(Theme.onPrimaryContainerColor, parent.dim)
            font.pixelSize: 14
            font.bold: parent.boldTitle
            elide: Text.ElideRight
            Layout.maximumWidth: parent.width * 0.62
        }
        Text {
            Layout.fillWidth: true
            text: parent.text
            color: Qt.alpha(Theme.onPrimaryContainerColor, 0.6 * parent.dim)
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: card
        width: parent.width
        height: headRow.y + headRow.height + detailsClip.height + 12
        radius: Theme.radiusSmall
        color: Qt.alpha(root.fg, 0.12)
        border.width: root.critical ? 1.5 : 0
        border.color: Theme.error

        // Expanded tint: opacity cross-fade (GPU) instead of ColorAnimation
        NcStateFill {
            anchors.fill: parent
            radius: card.radius
            color: root.fg
            level: 0.05
            shown: root.expanded
        }

        // ── Header ──────────────────────────────────────────────────────
        Item {
            id: headRow
            x: 12; y: 12
            width: card.width - 24
            height: Math.max(icon.height, textCol.implicitHeight)

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: NotificationManager.toggleGroup(root.key)
            }

            NcNotifIcon {
                id: icon
                x: 0; y: 0
                iconName: root.latest ? root.latest.iconName : ""
                iconFileUrl: root.latest ? root.latest.iconFileUrl : ""
                previewUrl: root.latest ? root.latest.previewUrl : ""
                size: 46
                previewSize: 64
            }

            ColumnLayout {
                id: textCol
                anchors.left: icon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.latest ? root.latest.appName : ""
                        color: Qt.alpha(root.fg, 0.65)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.latest ? NotificationManager.timeLabel(root.latest.stamp, NotificationManager.clock) : ""
                        color: Qt.alpha(root.fg, 0.65)
                        font.pixelSize: 11
                    }
                    Rectangle {
                        implicitWidth: pill.implicitWidth + 14
                        implicitHeight: 20
                        radius: 10
                        color: Qt.alpha(root.fg, 0.18)
                        NcStateFill {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.fg
                            level: 0.14
                            shown: pillMouse.containsMouse
                        }
                        Row {
                            id: pill
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                visible: root.total > 1
                                text: root.total
                                color: root.fg
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            NcIcon {
                                name: root.expanded ? "chevron-up" : "chevron-down"
                                size: 12
                                color: root.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationManager.toggleGroup(root.key)
                        }
                    }
                }

                // Preview lines — fade/collapse when the group expands
                Item {
                    id: previewWrap
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.expanded ? 0 : previewCol.implicitHeight
                    opacity: root.expanded ? 0 : 1
                    clip: true
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }
                    Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }

                    ColumnLayout {
                        id: previewCol
                        width: parent.width
                        spacing: 2

                        PreviewLine {
                            Layout.fillWidth: true
                            title: root.latest ? root.latest.summary : ""
                            text: root.total > 1 ? (root.latest ? root.latest.bodyPlain : "") : ""
                        }
                        PreviewLine {
                            Layout.fillWidth: true
                            visible: text !== "" || title !== ""
                            // Single notification: body goes on line 2.
                            // Group: previous notification, dimmed.
                            title: root.total > 1 ? (root.previous ? root.previous.summary : "") : ""
                            text: root.total > 1 ? (root.previous ? root.previous.bodyPlain : "")
                                                 : (root.latest ? root.latest.bodyPlain : "")
                            dim: root.total > 1 ? 0.7 : 1.0
                            boldTitle: false
                        }
                    }
                }
            }
        }

        // ── Expanded details (loaded only while open / animating) ───────
        Item {
            id: detailsClip
            x: 0
            y: headRow.y + headRow.height
            width: card.width
            clip: true
            height: root.expanded && detailsLoader.item ? detailsLoader.item.implicitHeight + 10 : 0
            Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }

            Loader {
                id: detailsLoader
                x: 10; y: 10
                width: detailsClip.width - 20
                active: root.expanded || detailsClip.height > 0
                sourceComponent: detailsComp
            }
        }
    }

    Component {
        id: detailsComp

        ColumnLayout {
            spacing: 8

            Repeater {
                model: root.snap
                delegate: NcNotificationEntry {
                    required property var modelData
                    snap: modelData
                }
            }

            NcButton {
                visible: root.total > 1
                Layout.alignment: Qt.AlignRight
                compact: true
                text: "Clear " + root.total
                onClicked: NotificationManager.clearGroup(root.key)
            }
        }
    }
}
