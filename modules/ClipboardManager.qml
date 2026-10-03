import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import "../services"

OverlayWindow {
    id: clipboard
    panelWidth:  800
    panelHeight: 600
    
    // Refresh when shown
    onShownChanged: {
        if (shown) {
            queryField.text = ""
            refreshClipboard()
            clipboard.selectedIndex = 0
            list.positionViewAtBeginning()
            queryField.forceActiveFocus()
        }
    }

    property var allItems: []
    property var results:  []
    property int selectedIndex: 0

    function refreshClipboard() {
        cliphistListProcess.running = true
    }

    function applyFilter() {
        const q = queryField.text.toLowerCase().trim()
        results = q.length === 0
            ? allItems
            : allItems.filter(e => e.content.toLowerCase().includes(q))
        selectedIndex = 0
    }

    function moveSelection(delta) {
        if (results.length === 0) return
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta))
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function copyItem(entry) {
        if (!entry) return
        if (entry.isImage) {
            const rawPath = entry.imagePath.replace("file://", "")
            copyProcess.command = ["sh", "-c", "wl-copy -t image/png < " + rawPath]
            copyProcess.running = true
            clipboard.hide()
        } else {
            const safeContent = entry.content.replace(/'/g, "'\\''")
            copyProcess.command = ["sh", "-c", "printf '%s' '" + safeContent + "' | wl-copy"]
            copyProcess.running = true
            clipboard.hide()
        }
    }
    
    function clearClipboard() {
        clearProcess.running = true
        clipboard.allItems = []
        clipboard.applyFilter()
        clipboard.hide()
    }
    
    property Process clearProcess: Process {
        command: ["sh", "-c", "echo '[]' > \"$HOME/.cache/quickshell-clipboard/history.json\" && rm -f \"$HOME/.cache/quickshell-clipboard/images/\"*.png"]
    }

    // Process to read clipboard json
    property Process cliphistListProcess: Process {
        id: cliphistListProcess
        command: ["cat", Quickshell.env("HOME") + "/.cache/quickshell-clipboard/history.json"]
        property string fullOutput: ""
        
        onRunningChanged: {
            if (running) {
                fullOutput = ""
            } else {
                try {
                    if (fullOutput.trim() === "") return
                    const newItems = JSON.parse(fullOutput)
                    
                    let changed = false
                    if (clipboard.allItems.length !== newItems.length) {
                        changed = true
                    } else if (newItems.length > 0 && clipboard.allItems.length > 0) {
                        // Check if the most recent item changed (in case we are at the 50 item limit)
                        if (clipboard.allItems[0].id !== newItems[0].id) {
                            changed = true
                        }
                    }
                    
                    if (changed) {
                        clipboard.allItems = newItems
                        clipboard.applyFilter()
                    }
                } catch (e) {
                    console.warn("Could not parse clipboard JSON:", e)
                }
            }
        }
        
        stdout: SplitParser {
            onRead: data => {
                cliphistListProcess.fullOutput += data + "\n"
            }
        }
    }

    property Process copyProcess: Process {
        id: copyProcess
    }
    
    Timer {
        id: liveUpdateTimer
        interval: 1000
        repeat: true
        running: clipboard.shown && !cliphistListProcess.running
        onTriggered: refreshClipboard()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Search Field
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: Theme.surfaceVariant
            radius: Theme.radiusSmall
            border.width: queryField.activeFocus ? 2 : 1
            border.color: queryField.activeFocus ? Theme.primary : Theme.outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Text {
                    text: "Search Clipboard..."
                    color: Theme.surfaceVariantText
                    font.pixelSize: 16
                    visible: queryField.text.length === 0
                    Layout.fillWidth: true
                }
            }

            TextInput {
                id: queryField
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: clearBtn.left
                anchors.margins: 12
                color: Theme.surfaceText
                font.pixelSize: 16
                verticalAlignment: TextInput.AlignVCenter
                clip: true

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Up) {
                        clipboard.moveSelection(-1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        clipboard.moveSelection(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (clipboard.results.length > 0) {
                            clipboard.copyItem(clipboard.results[clipboard.selectedIndex])
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        clipboard.hide()
                        event.accepted = true
                    } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && (event.modifiers & Qt.ControlModifier)) {
                        clipboard.clearClipboard()
                        event.accepted = true
                    }
                }
                onTextChanged: clipboard.applyFilter()
            }
            
            // Clear History Button
            Rectangle {
                id: clearBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 12
                width: 28; height: 28; radius: 6
                color: clearMouse.containsMouse ? Theme.error : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "🗑"
                    color: clearMouse.containsMouse ? "#ffffff" : Theme.surfaceVariantText
                    font.pixelSize: 16
                }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: clipboard.clearClipboard()
                }
                
                // Tooltip
                Rectangle {
                    visible: clearMouse.containsMouse
                    anchors.right: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 8
                    width: tooltipText.width + 16
                    height: tooltipText.height + 8
                    color: Theme.surface
                    border.color: Theme.outlineVariant
                    radius: 4
                    Text {
                        id: tooltipText
                        anchors.centerIn: parent
                        text: "Clear History (Ctrl+Backspace)"
                        color: Theme.surfaceText
                        font.pixelSize: 12
                    }
                }
            }
        }

        // List View
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: clipboard.results
            currentIndex: clipboard.selectedIndex
            layer.enabled: true

            delegate: Rectangle {
                id: delegateRect
                width: ListView.view.width
                height: itemLayout.implicitHeight + 24
                radius: Theme.radiusSmall
                
                property bool isSelected: index === clipboard.selectedIndex
                
                color: isSelected 
                       ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.85) 
                       : "transparent"

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: clipboard.selectedIndex = index
                    onClicked: clipboard.copyItem(modelData)
                }

                ColumnLayout {
                    id: itemLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Text Content
                    Text {
                        Layout.fillWidth: true
                        text: modelData.content
                        color: delegateRect.isSelected ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                        maximumLineCount: 10
                        elide: Text.ElideRight
                        visible: !modelData.isImage
                    }

                    // Image Content (Thumbnail)
                    Image {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
                        visible: modelData.isImage
                        source: modelData.isImage ? modelData.imagePath : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
            }
            
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
