import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../services"

PanelWindow {
    id: root
    
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "osd"
    exclusiveZone: -1
    color: "transparent"
    anchors { top: true; left: true }
    
    // Wayland margins
    margins.top: 20
    margins.left: 0
    
    implicitWidth: 420
    implicitHeight: popupList.height
    
    visible: popupModel.count > 0 || hideTimer.running

    Timer {
        id: hideTimer
        interval: 300
    }

    ListModel {
        id: popupModel
        onCountChanged: {
            if (count === 0) {
                hideTimer.restart();
            } else {
                hideTimer.stop();
            }
        }
    }
    
    // Window stays alive to allow exit animations on items
    
    Connections {
        target: NotificationManager
        function onIncomingNotification(notif) {
            popupModel.append({
                "id": notif.id,
                "appName": notif.appName,
                "appIcon": notif.appIcon,
                "summary": notif.summary,
                "body": notif.body,
                "image": notif.image,
                "icon": notif.icon,
                "urgency": notif.urgency
            });
            
            // Removed forced deletion of index 0 when count > 5.
            // This prevents sudden transition overlaps. The list will naturally 
            // auto-dismiss them safely one by one.
        }
    }
    
    property bool isListAnimating: false
    
    Timer {
        id: animCooldown
        interval: 800
        onTriggered: root.isListAnimating = false
    }
    
    function requestDismiss(idx, idStr) {
        if (idx !== 0) return false;
        if (isListAnimating) return false;
        
        isListAnimating = true;
        
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).id == idStr) {
                popupModel.remove(i, 1);
                break;
            }
        }
        
        animCooldown.restart();
        return true;
    }
    
    function dismissPopupByIndex(idx) {
        if (idx >= 0 && idx < popupModel.count) {
            popupModel.remove(idx, 1);
        }
    }
    
    ListView {
        id: popupList
        x: 10
        width: parent.width - 10
        height: contentHeight
        Behavior on height {
            enabled: popupList.contentHeight < popupList.height
            SequentialAnimation {
                PauseAnimation { duration: 300 }
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
        }
        interactive: false
        spacing: 12
        model: popupModel
        
        remove: Transition {
            PropertyAction { property: "z"; value: 100 }
            ParallelAnimation {
                NumberAnimation { property: "x"; to: -400; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { property: "y"; duration: 300; easing.type: Easing.OutCubic }
            }
        }
        addDisplaced: Transition {
            NumberAnimation { property: "y"; duration: 300; easing.type: Easing.OutCubic }
        }
        removeDisplaced: Transition {
            SequentialAnimation {
                PauseAnimation { duration: 300 }
                NumberAnimation { property: "y"; duration: 300; easing.type: Easing.OutCubic }
            }
        }
        move: Transition {
            NumberAnimation { property: "y"; duration: 300; easing.type: Easing.OutCubic }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: 300; easing.type: Easing.OutCubic }
        }
        
        delegate: Rectangle {
            width: 360
            height: notifCol.height + 24
            
            // Auto-dismiss timer — skipped for critical/priority notifications
            Timer {
                id: dismissTimer
                interval: 5000
                running: model.urgency !== NotificationUrgency.Critical
                onTriggered: checkDismiss()
            }
            
            Timer {
                id: retryTimer
                interval: 100
                repeat: true
                onTriggered: checkDismiss()
            }
            
            function checkDismiss() {
                if (index === 0) {
                    if (root.requestDismiss(index, model.id)) {
                        retryTimer.stop();
                    } else {
                        retryTimer.start();
                    }
                } else {
                    retryTimer.start();
                }
            }
            
            NumberAnimation on x {
                from: -400; to: 0
                duration: 300
                easing.type: Easing.OutBack
                easing.overshoot: 2.0
            }
            
            radius: Config.windowRadius
                color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, Config.backgroundOpacity)
                border.width: model.urgency === NotificationUrgency.Critical ? 2 : 1
                border.color: model.urgency === NotificationUrgency.Critical ? Theme.error : Theme.inversePrimary
                
                // Readability shadow
                layer.enabled: true
                
                RowLayout {
                    id: notifCol
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: 12
                    spacing: 12
                    
                    Item {
                        width: 48; height: 48
                        Layout.alignment: Qt.AlignTop
                        
                        IconImage {
                            anchors.fill: parent
                            visible: !(model.appIcon && model.appIcon.startsWith("/"))
                            source: Quickshell.iconPath(model.appIcon || "dialog-information")
                        }
                        
                        Image {
                            anchors.fill: parent
                            visible: model.appIcon && model.appIcon.startsWith("/")
                            source: visible ? "file://" + model.appIcon : ""
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: model.summary
                                color: Theme.onPrimaryContainerColor
                                font.pixelSize: 15
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            
                            // Close button
                            Rectangle {
                                width: 24; height: 24; radius: 12
                                color: closeMouse.containsMouse ? Theme.onPrimaryContainerColor : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: closeMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                    font.pixelSize: 14
                                }
                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.dismissPopupByIndex(index)
                                }
                            }
                        }
                        
                        Text {
                            text: model.body
                            color: Theme.onPrimaryContainerColor
                            opacity: 0.9
                            font.pixelSize: 13
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        
                        // Notification Icon (if any)
                        Item {
                            width: 32; height: 32
                            Layout.alignment: Qt.AlignHCenter
                            visible: model.icon && model.icon !== ""
                            
                            IconImage {
                                anchors.fill: parent
                                visible: !(model.icon && model.icon.startsWith("/"))
                                source: Quickshell.iconPath(model.icon || "dialog-information")
                            }
                            
                            Image {
                                anchors.fill: parent
                                visible: model.icon && model.icon.startsWith("/")
                                source: visible ? "file://" + model.icon : ""
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }
                }
                
                // Click to dismiss
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: root.dismissPopupByIndex(index)
                }
        }
    }
}
