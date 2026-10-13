// NcNotificationEntry.qml — one notification inside an expanded group.
// Title, full body, app actions, copy + dismiss. Flick right to dismiss.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import "../services"

Item {
    id: root

    property var  snap: null
    property bool collapsed: false

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property bool  critical: snap ? snap.urgency === NotificationUrgency.Critical : false
    readonly property var   actions: snap ? snap.actions : []
    readonly property bool  hasMedia: snap ? (snap.previewUrl !== "" || snap.iconFileUrl !== "") : false

    Layout.fillWidth: true
    Layout.preferredHeight: collapsed ? 0 : card.height
    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    clip: true

    // Slide out → collapse → actually dismiss. Used by ✕ and by the flick.
    function dismissAnimated() {
        if (dismissAnim.running || collapsed) return;
        dismissAnim.start();
    }

    SequentialAnimation {
        id: dismissAnim
        ParallelAnimation {
            XAnimator       { target: card; to: root.width; duration: 180; easing.type: Easing.InCubic }
            OpacityAnimator { target: card; to: 0; duration: 180 }
        }
        PropertyAction { target: root; property: "collapsed"; value: true }
        PauseAnimation { duration: 210 }
        ScriptAction { script: if (root.snap) NotificationManager.dismiss(root.snap.nid) }
    }

    XAnimator { id: snapBack; target: card; to: 0; duration: 160; easing.type: Easing.OutCubic }

    Rectangle {
        id: card
        width: root.width
        height: content.implicitHeight + 20
        radius: Theme.radiusSmall
        color: Qt.alpha(Theme.inversePrimary, 0.55)
        border.width: root.critical ? 1.5 : 0
        border.color: Theme.error

        DragHandler {
            target: card
            yAxis.enabled: false
            xAxis.minimum: 0
            xAxis.maximum: root.width
            onActiveChanged: {
                if (active) return;
                if (card.x > root.width * 0.35) root.dismissAnimated();
                else snapBack.start();
            }
        }

        ColumnLayout {
            id: content
            x: 10; y: 10
            width: card.width - 20
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                NcNotifIcon {
                    visible: root.hasMedia
                    Layout.alignment: Qt.AlignTop
                    iconName: root.snap ? root.snap.iconName : ""
                    iconFileUrl: root.snap ? root.snap.iconFileUrl : ""
                    previewUrl: root.snap ? root.snap.previewUrl : ""
                    size: 36
                    previewSize: 60
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: root.snap ? root.snap.summary : ""
                            color: root.fg
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: root.snap ? NotificationManager.timeLabel(root.snap.stamp, NotificationManager.clock) : ""
                            color: Qt.alpha(root.fg, 0.55)
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.snap && root.snap.body !== ""
                        text: root.snap ? root.snap.body : ""
                        textFormat: Text.StyledText
                        color: Qt.alpha(root.fg, 0.85)
                        linkColor: Theme.primary
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        maximumLineCount: 8
                        elide: Text.ElideRight
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.actions
                    delegate: NcButton {
                        required property var modelData
                        Layout.fillWidth: true
                        compact: true
                        text: modelData.text
                        onClicked: NotificationManager.invoke(root.snap.nid, modelData.identifier)
                    }
                }

                NcButton {
                    compact: true
                    iconName: "copy"
                    Layout.fillWidth: root.actions.length === 0
                    Layout.preferredWidth: root.actions.length === 0 ? 100 : 40
                    onClicked: if (root.snap) NotificationManager.copyText(root.snap.nid)
                }
                NcButton {
                    compact: true
                    iconName: "close"
                    Layout.fillWidth: root.actions.length === 0
                    Layout.preferredWidth: root.actions.length === 0 ? 100 : 40
                    onClicked: root.dismissAnimated()
                }
            }
        }
    }
}
