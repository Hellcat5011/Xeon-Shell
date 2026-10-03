import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"

PanelWindow {
    id: root

    property bool shown: false

    function show() {
        loadConfig()
        root.shown = true
    }
    function hide() { root.shown = false }
    function toggle() { if (shown) hide(); else show() }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "screenshot-settings"
    
    // When a file picker is open, only the dialog accepts input (rest passes through to file picker)
    WlrLayershell.mask: (ssPickerProcess.running || recPickerProcess.running) ? dialogRegion : null
    Region {
        id: dialogRegion
        item: dialogRect
    }

    color: "transparent"
    focusable: root.shown
    anchors { top: true; bottom: true; left: true; right: true }

    visible: shown || closingTimer.running
    Timer {
        id: closingTimer
        interval: Theme.animMed + 100
    }
    onShownChanged: {
        if (!shown) closingTimer.start()
        else keyHandler.forceActiveFocus()
    }

    property string screenshotDir: ""
    property string recordingDir: ""

    // Config Reader
    Process {
        id: configReader
        command: ["sh", Quickshell.shellDir + "/scripts/screenshot-config.sh", "read"]
        property string jsonContent: ""

        onRunningChanged: {
            if (running) jsonContent = ""
            else if (jsonContent.trim().length > 0) {
                try {
                    var c = JSON.parse(jsonContent)
                    root.screenshotDir = c.screenshotDir || ""
                    root.recordingDir  = c.recordingDir  || ""
                } catch (e) {}
            }
        }
        stdout: SplitParser { onRead: data => { configReader.jsonContent += data + "\n" } }
    }
    function loadConfig() { configReader.running = true }

    // Config Writer
    Process { id: configWriter }
    function saveConfig(key, value) {
        configWriter.command = ["sh", Quickshell.shellDir + "/scripts/screenshot-config.sh", "write", key, String(value)]
        configWriter.running = true
    }

    // Dim background
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.hide()
    }

    // Settings Dialog
    Rectangle {
        id: dialogRect
        anchors.centerIn: parent
        width: 400
        height: mainCol.height + 40
        radius: Config.windowRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.outlineVariant
        layer.enabled: true

        transform: Translate {
            y: root.shown ? 0 : 20
            Behavior on y { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        }
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        MouseArea { anchors.fill: parent } // block clicks

        ColumnLayout {
            id: mainCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 20

            Text {
                text: "Screenshot Settings"
                color: Theme.primaryText
                font.pixelSize: 18
                font.weight: Font.Bold
            }

            // Screenshot Dir
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "Screenshot Directory"; color: Theme.surfaceText; font.pixelSize: 13 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34; radius: 8
                        color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.4)
                        border.width: ssField.activeFocus ? 2 : 1; border.color: ssField.activeFocus ? Theme.primary : Theme.outlineVariant
                        TextInput {
                            id: ssField
                            anchors.fill: parent; anchors.margins: 8; color: Theme.surfaceText; font.pixelSize: 13
                            verticalAlignment: TextInput.AlignVCenter; clip: true; text: root.screenshotDir; selectByMouse: true
                            onAccepted: { root.screenshotDir = text; root.saveConfig("screenshotDir", text) }
                        }
                    }
                    Rectangle {
                        width: 34; height: 34; radius: 8
                        color: ssFolderMouse.containsMouse ? Theme.primary : Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.4)
                        Text { anchors.centerIn: parent; text: "📁"; font.pixelSize: 16 }
                        MouseArea {
                            id: ssFolderMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { ssPickerProcess.command = ["sh", "-c", "zenity --file-selection --directory --title='Select Screenshot Folder' --filename='" + root.screenshotDir + "/'"]; ssPickerProcess.running = true }
                        }
                    }
                }
            }

            // Recording Dir
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "Recording Directory"; color: Theme.surfaceText; font.pixelSize: 13 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34; radius: 8
                        color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.4)
                        border.width: recField.activeFocus ? 2 : 1; border.color: recField.activeFocus ? Theme.primary : Theme.outlineVariant
                        TextInput {
                            id: recField
                            anchors.fill: parent; anchors.margins: 8; color: Theme.surfaceText; font.pixelSize: 13
                            verticalAlignment: TextInput.AlignVCenter; clip: true; text: root.recordingDir; selectByMouse: true
                            onAccepted: { root.recordingDir = text; root.saveConfig("recordingDir", text) }
                        }
                    }
                    Rectangle {
                        width: 34; height: 34; radius: 8
                        color: recFolderMouse.containsMouse ? Theme.primary : Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.4)
                        Text { anchors.centerIn: parent; text: "📁"; font.pixelSize: 16 }
                        MouseArea {
                            id: recFolderMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { recPickerProcess.command = ["sh", "-c", "zenity --file-selection --directory --title='Select Recording Folder' --filename='" + root.recordingDir + "/'"]; recPickerProcess.running = true }
                        }
                    }
                }
            }

            // Close button
            Rectangle {
                Layout.alignment: Qt.AlignRight
                width: 80; height: 34; radius: 17
                color: closeMouse.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
                Text { anchors.centerIn: parent; text: "Done"; color: Theme.primaryText; font.pixelSize: 13; font.weight: Font.DemiBold }
                MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.hide() }
            }
        }
    }

    Process {
        id: ssPickerProcess
        property string selectedPath: ""
        onRunningChanged: { if (running) selectedPath = "" }
        onExited: (exitCode) => {
            if (exitCode === 0 && selectedPath.trim().length > 0) {
                root.screenshotDir = selectedPath.trim()
                root.saveConfig("screenshotDir", root.screenshotDir)
            }
        }
        stdout: SplitParser { onRead: data => { ssPickerProcess.selectedPath += data } }
    }

    Process {
        id: recPickerProcess
        property string selectedPath: ""
        onRunningChanged: { if (running) selectedPath = "" }
        onExited: (exitCode) => {
            if (exitCode === 0 && selectedPath.trim().length > 0) {
                root.recordingDir = selectedPath.trim()
                root.saveConfig("recordingDir", root.recordingDir)
            }
        }
        stdout: SplitParser { onRead: data => { recPickerProcess.selectedPath += data } }
    }
}
