import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../services"

OverlayWindow {
    id: nc
    panelWidth: 400
    panelHeight: 1000 // We can set this to screen height using anchors or let Wayland handle it.
    anchorPos: "left"
    enterAnimation: "slideLeft"
    cardRadius: 3
    cardColor: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.65)
    hasBorder: true

    signal openSettings()

    // Wayland margins
    margins.top: 10
    margins.bottom: 10
    margins.left: 0
    
    Component.onCompleted: {
        nc.panelHeight = Qt.binding(function() { return nc.height - 20 })
    }
    
    onShownChanged: {
        if (shown) {
            SystemMonitor.refreshAudio();
        } else {
            if (sinkMenuIsOpen) sinkMenuIsOpen = false;
        }
    }
    
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (sinkMenuIsOpen) sinkMenuIsOpen = false;
            else nc.hide();
        }
    }
    
    property bool sinkMenuIsOpen: false

    // Static process objects to avoid Qt.createQmlObject memory leaks
    Process { id: volumeProcess }
    Process { id: brightnessProcess }
    Process { id: sinkSwitchProcess }
    Timer {
        id: sinkRefreshTimer
        interval: 500
        onTriggered: SystemMonitor.refreshAudio()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // --- Header: Control Centre & Settings ---
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Control Centre"
                color: Theme.onPrimaryContainerColor
                font.pixelSize: 18
                font.bold: true
                Layout.fillWidth: true
            }

            Rectangle {
                id: gearBtn
                width: 32
                height: 32
                radius: 16
                border.width: 1
                border.color: Theme.onPrimaryContainerColor
                color: gearMouse.containsMouse ? Theme.onPrimaryContainerColor : "transparent"

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 18 / 24
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        strokeColor: gearMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                        strokeWidth: 2
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        capStyle: ShapePath.RoundCap
                        PathSvg {
                            path: "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"
                        }
                    }
                    ShapePath {
                        strokeColor: gearMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                        strokeWidth: 2
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        capStyle: ShapePath.RoundCap
                        PathSvg {
                            path: "M 12 9 A 3 3 0 0 1 12 15 A 3 3 0 0 1 12 9"
                        }
                    }
                }

                MouseArea {
                    id: gearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        nc.hide();
                        nc.openSettings();
                    }
                }
            }
        }

        // --- Header: Bluetooth & Caffeinate ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: Theme.radiusSmall
                color: SystemMonitor.btConnected ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.85) : Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.2)
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    spacing: 12
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Shape {
                        width: 24; height: 24
                        Layout.alignment: Qt.AlignVCenter
                        ShapePath {
                            strokeWidth: 0; fillColor: SystemMonitor.btConnected ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                            Behavior on fillColor { ColorAnimation { duration: 150 } }
                            PathSvg { path: "M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88z" }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: SystemMonitor.btConnected ? SystemMonitor.btName : "Bluetooth Disconnected"
                        color: SystemMonitor.btConnected ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                        Behavior on color { ColorAnimation { duration: 150 } }
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: SystemMonitor.btConnected
                        text: SystemMonitor.btBattery ? (SystemMonitor.btBattery + "%") : ""
                        color: SystemMonitor.btConnected ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                        Behavior on color { ColorAnimation { duration: 150 } }
                        font.pixelSize: 14
                        font.bold: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: Theme.radiusSmall
                color: SystemMonitor.caffeinateEnabled ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.85) : Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.2)
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    spacing: 12
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Shape {
                        width: 24; height: 24
                        Layout.alignment: Qt.AlignVCenter
                        ShapePath {
                            strokeWidth: 0; fillColor: SystemMonitor.caffeinateEnabled ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                            Behavior on fillColor { ColorAnimation { duration: 150 } }
                            PathSvg { path: "M4,19h16v2H4V19z M20,3H4v10c0,2.21,1.79,4,4,4h6c2.21,0,4-1.79,4-4v-3h2c1.11,0,2-0.89,2-2V5C22,3.89,21.11,3,20,3z M18,8h-2V5h2V8z" }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Caffeinate"
                        color: SystemMonitor.caffeinateEnabled ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                        Behavior on color { ColorAnimation { duration: 150 } }
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: SystemMonitor.caffeinateEnabled = !SystemMonitor.caffeinateEnabled
                }
            }
        }

        // --- Sliders ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 20

            // Audio Group
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: contentCol.implicitHeight + (sinkMenuIsOpen ? 16 : 0) // account for margins
                radius: Theme.radiusSmall
                color: sinkMenuIsOpen ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.1) : "transparent"
                
                Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                ColumnLayout {
                    id: contentCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: sinkMenuIsOpen ? 8 : 0
                    spacing: 8

                    // Audio
                    RowLayout {
                        id: audioRow
                        Layout.fillWidth: true
                        spacing: 12

                        Shape {
                            width: 24; height: 24
                            layer.enabled: true; layer.samples: 4
                            ShapePath {
                                strokeWidth: 2; strokeColor: Theme.onPrimaryContainerColor; fillColor: "transparent"
                                joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
                                PathSvg { path: "M11 5L6 9H2v6h4l5 4V5zM15.54 8.46a5 5 0 0 1 0 7.07M19.07 4.93a10 10 0 0 1 0 14.14" }
                            }
                        }

                        Slider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: SystemMonitor.currentVolume
                            
                            background: Rectangle {
                                x: parent.leftPadding
                                y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                width: parent.availableWidth
                                height: 6
                                radius: 3
                                color: Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.3)
                                Rectangle {
                                    width: parent.parent.visualPosition * parent.width
                                    height: parent.height
                                    color: Theme.onPrimaryContainerColor
                                    radius: 3
                                }
                            }
                            handle: Rectangle {
                                x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                                y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                width: 14; height: 14
                                radius: 7
                                color: Theme.onPrimaryContainerColor
                            }

                            onMoved: {
                                let vol = value / 100.0;
                                volumeProcess.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", vol.toFixed(2)];
                                volumeProcess.running = true;
                                SystemMonitor.currentVolume = value;
                            }
                        }

                        Rectangle {
                            width: 32; height: 32; radius: 16
                            color: hoverAudio.containsMouse ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.2) : "transparent"
                            Shape {
                                anchors.centerIn: parent
                                width: 24; height: 24
                                layer.enabled: true; layer.samples: 4
                                ShapePath {
                                    strokeWidth: 2; strokeColor: Theme.onPrimaryContainerColor; fillColor: "transparent"
                                    joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
                                    PathSvg { path: "m6 9 6 6 6-6" } // Chevron down
                                }
                                rotation: sinkMenuIsOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.animMed } }
                            }
                            MouseArea {
                                id: hoverAudio
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: nc.sinkMenuIsOpen = !nc.sinkMenuIsOpen
                            }
                        }
                    }

                    // Sink menu list
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: sinkMenuIsOpen ? sinkList.contentHeight : 0
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }
                        clip: true

                        ListView {
                            id: sinkList
                            anchors.fill: parent
                            model: SystemMonitor.audioSinks
                            spacing: 4
                            delegate: Rectangle {
                                width: sinkList.width; height: 36
                                radius: Theme.radiusSmall
                                color: sinkMouse.containsMouse ? Theme.onPrimaryContainerColor : "transparent"
                                
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8
                                    
                                    // Radio Button
                                    Rectangle {
                                        width: 14; height: 14; radius: 7
                                        color: "transparent"
                                        border.width: 1
                                        border.color: sinkMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                        
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8; height: 8; radius: 4
                                            color: sinkMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                            visible: SystemMonitor.defaultSinkName === modelData.name
                                        }
                                    }
                                    
                                    // Output Type Icon
                                    Item {
                                        width: 16; height: 16
                                        Layout.alignment: Qt.AlignVCenter
                                        Shape {
                                            width: 24; height: 24
                                            scale: 16/24
                                            transformOrigin: Item.TopLeft
                                            ShapePath {
                                                strokeWidth: 0; fillColor: sinkMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                                Behavior on fillColor { ColorAnimation { duration: 150 } }
                                                PathSvg {
                                                    path: {
                                                        let d = modelData.description.toLowerCase();
                                                        let n = modelData.name.toLowerCase();
                                                        if (n.includes("bluez") || d.includes("blue") || d.includes("1800") || d.includes("headset") || d.includes("buds") || d.includes("airpods") || d.includes("earbuds")) {
                                                            return "M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88z"; // Bluetooth
                                                        } else if (n.includes("hdmi") || d.includes("hdmi") || d.includes("monitor") || d.includes("display")) {
                                                            return "M21 3H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h5v2h8v-2h5c1.1 0 1.99-.9 1.99-2L23 5c0-1.1-.9-2-2-2zm0 14H3V5h18v12z"; // Monitor
                                                        } else {
                                                            return "M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"; // Speaker
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    Text {
                                        text: modelData.description
                                        color: sinkMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                        font.pixelSize: 13
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                                
                                MouseArea {
                                    id: sinkMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        sinkSwitchProcess.command = ["pactl", "set-default-sink", modelData.name];
                                        sinkSwitchProcess.running = true;
                                        nc.sinkMenuIsOpen = false;
                                        sinkRefreshTimer.restart();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Brightness
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Shape {
                    width: 24; height: 24
                    layer.enabled: true; layer.samples: 4
                    ShapePath {
                        strokeWidth: 2; strokeColor: Theme.onPrimaryContainerColor; fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
                        PathSvg { path: "M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8z" }
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0; to: 100
                    value: 50
                    
                    background: Rectangle {
                        x: parent.leftPadding
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: parent.availableWidth
                        height: 6
                        radius: 3
                        color: Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.3)
                        Rectangle {
                            width: parent.parent.visualPosition * parent.width
                            height: parent.height
                            color: Theme.onPrimaryContainerColor
                            radius: 3
                        }
                    }
                    handle: Rectangle {
                        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: 14; height: 14
                        radius: 7
                        color: Theme.onPrimaryContainerColor
                    }

                    onMoved: {
                        brightnessProcess.command = ["ddcutil", "-b", "4", "setvcp", "10", Math.round(value).toString()];
                        brightnessProcess.running = true;
                    }
                }
                
                Item { width: 32; height: 32 } // Spacer to align with audio dropdown button
            }
        }

        // --- Notifications ---
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Notifications"
                        color: Theme.onPrimaryContainerColor
                        font.pixelSize: 18
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: 80; height: 32; radius: 16
                        color: clearMouse.containsMouse ? Theme.onPrimaryContainerColor : "transparent"
                        border.width: 1; border.color: Theme.onPrimaryContainerColor
                        
                        Text {
                            anchors.centerIn: parent
                            text: "Clear All"
                            color: clearMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: NotificationManager.clearAll()
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: NotificationManager.groupedNotifications
                    spacing: 16
                    clip: true
                    
                    delegate: Item {
                        id: groupDelegate
                        property int groupIndex: index
                        property bool expanded: modelData.expanded
                        property var notifications: modelData.notifications
                        property string appName: modelData.appName
                        property string appIcon: modelData.appIcon
                        
                        width: ListView.view.width
                        height: col.height
                        
                        Column {
                            id: col
                            width: parent.width
                            spacing: 0
                            
                            // App Header
                            Rectangle {
                                width: parent.width
                                height: headerRow.implicitHeight + 16
                                radius: 4
                                color: (groupDelegate.notifications.length > 1 && headerMouse.containsMouse) ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.4) : (groupDelegate.notifications.length > 1 ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.2) : "transparent")
                                Behavior on color { ColorAnimation { duration: 150 } }
                                
                                // Square bottom corners when expanded
                                Rectangle {
                                    visible: groupDelegate.expanded && groupDelegate.notifications.length > 1
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 4
                                    color: parent.color
                                }
                                
                                MouseArea {
                                    id: headerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: groupDelegate.notifications.length > 1
                                    onClicked: NotificationManager.toggleGroup(groupDelegate.groupIndex)
                                }
                                
                                RowLayout {
                                    id: headerRow
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: 8
                                    spacing: 8
                                    Item {
                                        width: 20; height: 20
                                        
                                        IconImage {
                                            anchors.fill: parent
                                            visible: !(groupDelegate.appIcon && groupDelegate.appIcon.startsWith("/"))
                                            source: Quickshell.iconPath(groupDelegate.appIcon || "dialog-information")
                                        }
                                        
                                        Image {
                                            anchors.fill: parent
                                            visible: groupDelegate.appIcon && groupDelegate.appIcon.startsWith("/")
                                            source: visible ? "file://" + groupDelegate.appIcon : ""
                                            fillMode: Image.PreserveAspectFit
                                        }
                                    }
                                    Text {
                                        text: groupDelegate.appName
                                        color: Theme.onPrimaryContainerColor
                                        font.pixelSize: 14
                                        font.bold: true
                                        Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        visible: groupDelegate.notifications.length > 1
                                        width: 24; height: 24; radius: 12
                                        color: Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.4)
                                        Text {
                                            anchors.centerIn: parent
                                            text: groupDelegate.notifications.length.toString()
                                            color: Theme.onPrimaryContainerColor
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                            
                            // Notification Cards Dropdown
                            Rectangle {
                                width: parent.width
                                height: (groupDelegate.expanded || groupDelegate.notifications.length === 1) ? expandedCol.implicitHeight : 0
                                Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                clip: true
                                color: groupDelegate.notifications.length > 1 ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.2) : "transparent"
                                radius: 4
                                
                                // Square top corners when expanded
                                Rectangle {
                                    visible: groupDelegate.expanded && groupDelegate.notifications.length > 1
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 4
                                    color: parent.color
                                }
                                
                                // Expanded view
                                Column {
                                    id: expandedCol
                                    width: parent.width
                                    spacing: 8
                                    anchors.top: parent.top
                                    
                                    // Add top padding if it has a background
                                    Item { width: 1; height: groupDelegate.notifications.length > 1 ? 8 : 0 }
                                    
                                    Repeater {
                                        model: groupDelegate.notifications
                                        delegate: Rectangle {
                                            id: notifCard
                                            width: groupDelegate.notifications.length > 1 ? parent.width - 16 : parent.width
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            height: notifCol.height + 24
                                            radius: 3
                                            color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.85)
                                            border.width: modelData.urgency === NotificationUrgency.Critical ? 2 : 1
                                            border.color: modelData.urgency === NotificationUrgency.Critical ? Theme.error : Theme.onPrimaryContainerColor
                                            layer.enabled: true
                                            
                                            ColumnLayout {
                                                id: notifCol
                                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                                anchors.margins: 12
                                                spacing: 4
                                                
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text {
                                                        text: modelData.summary
                                                        color: Theme.onPrimaryContainerColor
                                                        font.pixelSize: 15
                                                        font.bold: true
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        text: modelData.timestamp
                                                        color: Theme.onPrimaryContainerColor
                                                        opacity: 0.6
                                                        font.pixelSize: 12
                                                    }
                                                }
                                                
                                                Text {
                                                    text: modelData.body
                                                    color: Theme.onPrimaryContainerColor
                                                    opacity: 0.9
                                                    font.pixelSize: 14
                                                    Layout.fillWidth: true
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 3
                                                    elide: Text.ElideRight
                                                }
                                                
                                                Item {
                                                    width: 32; height: 32
                                                    visible: modelData.icon && modelData.icon !== ""
                                                    
                                                    IconImage {
                                                        anchors.fill: parent
                                                        visible: !(modelData.icon && modelData.icon.startsWith("/"))
                                                        source: Quickshell.iconPath(modelData.icon || "dialog-information")
                                                    }
                                                    
                                                    Image {
                                                        anchors.fill: parent
                                                        visible: modelData.icon && modelData.icon.startsWith("/")
                                                        source: visible ? "file://" + modelData.icon : ""
                                                        fillMode: Image.PreserveAspectFit
                                                    }
                                                }
                                            }
                                            
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: NotificationManager.toggleGroup(groupDelegate.groupIndex)
                                            }
                                        }
                                    }
                                    
                                    // Add bottom padding if it has a background
                                    Item { width: 1; height: groupDelegate.notifications.length > 1 ? 8 : 0 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
