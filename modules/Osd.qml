import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../services"

PanelWindow {
    id: root
    
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "osd"
    exclusiveZone: -1
    color: "transparent"
    anchors { bottom: true }
    margins.bottom: 0 // Touch the physical bottom of the screen
    
    visible: shown || fadeOutTimer.running
    implicitWidth: 320
    implicitHeight: 224 // 60 (top padding) + 64 (card height) + 100 (padding from bottom)
    
    property bool shown: false
    property string osdType: "volume" // "volume" or "brightness"
    property int osdValue: 0
    
    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: root.shown = false
    }
    
    Timer {
        id: fadeOutTimer
        interval: 250
    }
    
    onShownChanged: {
        if (shown) {
            animOut.stop();
            animIn.start();
        } else {
            animIn.stop();
            animOut.start();
            fadeOutTimer.start();
        }
    }
    
    NumberAnimation { id: animIn; target: cardTranslate; property: "y"; to: 60; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
    NumberAnimation { id: animOut; target: cardTranslate; property: "y"; to: 260; duration: 200; easing.type: Easing.InCubic }
    
    function showOsd(type, value) {
        root.osdType = type;
        root.osdValue = parseInt(value) || 0;
        root.shown = true;
        hideTimer.restart();
    }
    
    Rectangle {
        id: card
        y: 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: 320
        height: 64
        radius: Theme.radiusSmall

        color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, Config.backgroundOpacity)
        border.width: 1
        border.color: Theme.inversePrimary
        layer.enabled: true
        
        transform: Translate {
            id: cardTranslate
            y: 260
        }
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16
            
            Shape {
                width: 24; height: 24
                layer.enabled: true; layer.samples: 4
                ShapePath {
                    strokeWidth: 2; strokeColor: Theme.primary; fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
                    PathSvg {
                        path: {
                            if (root.osdType === "brightness") 
                                return "M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8z";
                            
                            // Audio
                            if (root.osdValue === 0) 
                                return "M11 5L6 9H2v6h4l5 4V5zM23 9l-6 6M17 9l6 6"; // Muted with X
                            if (root.osdValue < 30) 
                                return "M11 5L6 9H2v6h4l5 4V5z"; // Low (no arcs)
                            if (root.osdValue < 70) 
                                return "M11 5L6 9H2v6h4l5 4V5zM15.54 8.46a5 5 0 0 1 0 7.07"; // Medium (one arc)
                            return "M11 5L6 9H2v6h4l5 4V5zM15.54 8.46a5 5 0 0 1 0 7.07M19.07 4.93a10 10 0 0 1 0 14.14"; // High
                        }
                    }
                }
            }
            
            Rectangle {
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: Theme.surface
                
                Rectangle {
                    width: parent.width * (root.osdValue / 100.0)
                    height: parent.height
                    radius: 4
                    color: Theme.primary
                    
                    Behavior on width { NumberAnimation { duration: Theme.animFast } }
                }
            }
            
            Text {
                text: root.osdValue + "%"
                color: Theme.primary
                font.pixelSize: 14
                font.bold: true
                Layout.minimumWidth: 40
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
