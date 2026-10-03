import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Wayland
import "../services"

OverlayWindow {
    id: powerMenu
    WlrLayershell.namespace: "power"
    
    // 70% of screen width
    panelWidth: width > 0 ? width * 0.70 : 1344
    panelHeight: 340

    property int selectedIndex: -1

    onShownChanged: {
        if (shown) {
            selectedIndex = -1;
            keyHandler.forceActiveFocus();
        }
    }

    property Process powerProcess: Process {
        id: powerProcess
    }

    function executeCommand(cmd) {
        powerProcess.command = ["sh", "-c", cmd]
        powerProcess.running = true
        powerMenu.hide()
    }

    component PowerButton: Rectangle {
        property int index
        property string iconSvg
        property string label
        property string command
        property color highlightColor: Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.85)
        property color unselectedIconColor: Theme.onPrimaryContainerColor
        property color selectedIconColor: Theme.inversePrimary

        property bool isSelected: powerMenu.selectedIndex === index || mArea.containsMouse
        
        onIsSelectedChanged: {
            if (mArea.containsMouse) {
                powerMenu.selectedIndex = index
            }
        }

        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radiusLarge
        color: isSelected ? highlightColor : "transparent"
        border.width: isSelected ? 2 : 1
        border.color: isSelected ? selectedIconColor : Theme.outlineVariant

        // Offload composition to GPU to prevent stuttering on hover
        layer.enabled: true

        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 24

            Image {
                Layout.alignment: Qt.AlignHCenter
                sourceSize.width: 128
                sourceSize.height: 128
                source: "data:image/svg+xml;utf8," + encodeURIComponent(
                    "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + (isSelected ? selectedIconColor : unselectedIconColor) + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>" + iconSvg + "</svg>"
                )
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: label
                color: isSelected ? selectedIconColor : unselectedIconColor
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: mArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: powerMenu.executeCommand(command)
        }
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                powerMenu.hide();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left) {
                if (powerMenu.selectedIndex > 0) powerMenu.selectedIndex--;
                else if (powerMenu.selectedIndex === -1) powerMenu.selectedIndex = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                if (powerMenu.selectedIndex < 3) powerMenu.selectedIndex++;
                else if (powerMenu.selectedIndex === -1) powerMenu.selectedIndex = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                let buttons = [lockBtn, logoutBtn, rebootBtn, shutdownBtn];
                if (powerMenu.selectedIndex >= 0 && powerMenu.selectedIndex < buttons.length)
                    powerMenu.executeCommand(buttons[powerMenu.selectedIndex].command);
                event.accepted = true;
            } else if (event.key === Qt.Key_1 || event.key === Qt.Key_L) {
                powerMenu.executeCommand("loginctl lock-session");
                event.accepted = true;
            } else if (event.key === Qt.Key_2 || event.key === Qt.Key_E) {
                powerMenu.executeCommand("hyprctl dispatch 'hl.dsp.exit()'");
                event.accepted = true;
            } else if (event.key === Qt.Key_3 || event.key === Qt.Key_R) {
                powerMenu.executeCommand("systemctl reboot");
                event.accepted = true;
            } else if (event.key === Qt.Key_4 || event.key === Qt.Key_S) {
                powerMenu.executeCommand("systemctl poweroff");
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 40
            spacing: 40

            PowerButton {
                id: lockBtn
                index: 0
                label: "Lock"
                command: "loginctl lock-session"
                iconSvg: "<rect x='4' y='10' width='16' height='12' rx='3' ry='3'></rect><path d='M7 10V6a5 5 0 0 1 10 0v4'></path>"
            }

            PowerButton {
                id: logoutBtn
                index: 1
                label: "Logout"
                command: "hyprctl dispatch 'hl.dsp.exit()'"
                iconSvg: "<path d='M10 22H5a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h5'></path><polyline points='16 17 21 12 16 7'></polyline><line x1='21' y1='12' x2='9' y2='12'></line>"
            }

            PowerButton {
                id: rebootBtn
                index: 2
                label: "Reboot"
                command: "systemctl reboot"
                iconSvg: "<path d='M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8'></path><polyline points='21 3 21 8 16 8'></polyline>"
            }

            PowerButton {
                id: shutdownBtn
                index: 3
                label: "Shutdown"
                command: "systemctl poweroff"
                iconSvg: "<path d='M18.36 6.64a9 9 0 1 1-12.73 0'></path><line x1='12' y1='2' x2='12' y2='12'></line>"
            }
        }
    }
}
