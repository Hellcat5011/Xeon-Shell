// NcFooter.qml — volume + brightness, pinned below every tab.
//
// Slider writes are throttled and always flush the LAST value. (The old code
// set `process.running = true` on every move; while a process was still
// running that was silently ignored, so the final position could be lost.)
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io
import "../services"

Rectangle {
    id: root

    property bool sinkMenuOpen: false
    function closeMenu() { sinkMenuOpen = false }

    readonly property color fg: Theme.onPrimaryContainerColor

    implicitHeight: col.implicitHeight + 24
    radius: Theme.radiusSmall
    color: Qt.alpha(fg, 0.08)

    // ── Backend plumbing (unchanged commands) ───────────────────────────
    property real pendingVolume: 0
    property real pendingBrightness: 0

    Process { id: volumeProcess }
    Process { id: brightnessProcess }
    Process { id: sinkSwitchProcess }

    Timer {
        id: volumeTimer
        interval: 40
        onTriggered: {
            if (volumeProcess.running) { volumeTimer.restart(); return; }
            volumeProcess.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (root.pendingVolume / 100).toFixed(2)];
            volumeProcess.running = true;
        }
    }
    Timer {
        id: brightnessTimer
        interval: 150
        onTriggered: {
            if (brightnessProcess.running) { brightnessTimer.restart(); return; }
            brightnessProcess.command = ["ddcutil", "-b", "4", "setvcp", "10", Math.round(root.pendingBrightness).toString()];
            brightnessProcess.running = true;
        }
    }
    Timer {
        id: sinkRefreshTimer
        interval: 500
        onTriggered: SystemMonitor.refreshAudio()
    }

    component FlatSlider: Slider {
        id: s
        from: 0
        to: 100
        background: Rectangle {
            x: s.leftPadding
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: s.availableWidth
            height: 6
            radius: 3
            color: Qt.alpha(Theme.onPrimaryContainerColor, 0.3)
            Rectangle {
                width: s.visualPosition * parent.width
                height: parent.height
                radius: 3
                color: Theme.onPrimaryContainerColor
            }
        }
        handle: Rectangle {
            x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: 14; height: 14; radius: 7
            color: Theme.onPrimaryContainerColor
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // ── Output device menu (grows upward, pushes the tab area up) ───
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.sinkMenuOpen ? Math.min(sinkList.contentHeight, 170) : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }
            clip: true

            ListView {
                id: sinkList
                anchors.fill: parent
                model: SystemMonitor.audioSinks
                spacing: 4
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: sinkRow
                    required property var modelData
                    width: sinkList.width
                    height: 36
                    radius: Theme.radiusSmall
                    color: sinkMouse.containsMouse ? Theme.onPrimaryContainerColor : "transparent"

                    readonly property color content: sinkMouse.containsMouse ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                    readonly property string desc: (modelData.description || "").toLowerCase()
                    readonly property string nm: (modelData.name || "").toLowerCase()
                    readonly property string iconKind: {
                        if (nm.includes("bluez") || desc.includes("blue") || desc.includes("headset") || desc.includes("buds") || desc.includes("airpods")) return "bluetooth";
                        if (nm.includes("hdmi") || desc.includes("hdmi") || desc.includes("monitor") || desc.includes("display")) return "monitor";
                        return "speaker";
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: "transparent"
                            border.width: 1
                            border.color: sinkRow.content
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 4
                                color: sinkRow.content
                                visible: SystemMonitor.defaultSinkName === sinkRow.modelData.name
                            }
                        }
                        NcIcon { name: sinkRow.iconKind; size: 16; color: sinkRow.content }
                        Text {
                            Layout.fillWidth: true
                            text: sinkRow.modelData.description
                            color: sinkRow.content
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: sinkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            sinkSwitchProcess.command = ["pactl", "set-default-sink", sinkRow.modelData.name];
                            sinkSwitchProcess.running = true;
                            root.sinkMenuOpen = false;
                            sinkRefreshTimer.restart();
                        }
                    }
                }
            }
        }

        // ── Volume ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            NcIcon { name: "volume"; size: 22; color: root.fg }

            FlatSlider {
                Layout.fillWidth: true
                value: SystemMonitor.currentVolume
                onMoved: {
                    root.pendingVolume = value;
                    SystemMonitor.currentVolume = value;
                    volumeTimer.restart();
                }
            }

            Rectangle {
                width: 32; height: 32; radius: 16
                color: chevMouse.containsMouse ? Qt.alpha(root.fg, 0.2) : "transparent"
                NcIcon {
                    anchors.centerIn: parent
                    name: "chevron-down"
                    size: 18
                    color: root.fg
                    rotation: root.sinkMenuOpen ? 0 : 180   // menu opens upward: ^ when closed, v when open
                    Behavior on rotation { RotationAnimator { duration: Theme.animMed; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    id: chevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sinkMenuOpen = !root.sinkMenuOpen
                }
            }
        }

        // ── Brightness ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            NcIcon { name: "sun"; size: 22; color: root.fg }

            FlatSlider {
                Layout.fillWidth: true
                value: 50
                onMoved: {
                    root.pendingBrightness = value;
                    brightnessTimer.restart();
                }
            }

            Item { width: 32; height: 32 }   // aligns with the volume chevron
        }
    }
}
