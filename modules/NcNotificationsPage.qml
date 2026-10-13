// NcNotificationsPage.qml — grouped list + "N notifications · Silent · Clear"
import QtQuick
import QtQuick.Layouts
import "../services"

Item {
    id: root

    readonly property color fg: Theme.onPrimaryContainerColor

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: NotificationManager.groupModel
                delegate: NcNotificationGroup {}

                // opacity / scale / x are render-thread animators; y (list layout) stays a NumberAnimation
                add: Transition {
                    ParallelAnimation {
                        OpacityAnimator { from: 0; to: 1; duration: 220 }
                        ScaleAnimator   { from: 0.96; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        OpacityAnimator { to: 0; duration: 180 }
                        XAnimator       { to: list.width * 0.5; duration: 220; easing.type: Easing.InCubic }
                    }
                }
                addDisplaced:    Transition { NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic } }
                removeDisplaced: Transition { NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic } }
                move:            Transition { NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic } }
                moveDisplaced:   Transition { NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic } }
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: NotificationManager.count === 0
                opacity: 0.6

                NcIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "bell"
                    size: 34
                    slashed: NotificationManager.silent
                    color: root.fg
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: NotificationManager.silent ? "Silent mode is on" : "No notifications"
                    color: root.fg
                    font.pixelSize: 14
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: NotificationManager.count === 0 ? "No notifications"
                    : NotificationManager.count === 1 ? "1 notification"
                    : NotificationManager.count + " notifications"
                color: root.fg
                font.pixelSize: 14
            }

            NcButton {
                text: "Silent"
                iconName: "bell"
                active: NotificationManager.silent
                onClicked: NotificationManager.toggleSilent()
            }
            NcButton {
                text: "Clear"
                iconName: "close"
                enabled: NotificationManager.count > 0
                onClicked: NotificationManager.clearAll()
            }
        }
    }
}
