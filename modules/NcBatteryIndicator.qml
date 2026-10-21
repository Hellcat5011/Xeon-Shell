// NcBatteryIndicator.qml — battery icon with dynamic charge-level fill
// and percentage text. Entirely hidden when no battery is detected.
//
// Sits in the control centre header next to the settings gear.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../services"

Item {
    id: root

    visible: SystemMonitor.batteryPresent
    implicitWidth: row.implicitWidth
    implicitHeight: 32

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property int  pct: SystemMonitor.batteryPercent
    readonly property bool charging: SystemMonitor.batteryCharging

    // Colour thresholds
    readonly property color fillColor: {
        if (charging) return Qt.alpha(fg, 0.9);
        if (pct <= 10) return Theme.error || "#ef4444";
        if (pct <= 25) return "#f59e0b";
        return Qt.alpha(fg, 0.9);
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        // ── Battery icon (18 × 10 logical, drawn on a 24×24 grid) ───────
        Item {
            width: 22
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            // Battery body outline
            Rectangle {
                id: body
                x: 0; y: 1
                width: 18; height: 12
                radius: 2
                color: "transparent"
                border.width: 1.5
                border.color: root.fg

                // Charge-level fill — width scales linearly with percentage
                Rectangle {
                    x: 2; y: 2
                    width: Math.max(0, (parent.width - 4) * root.pct / 100)
                    height: parent.height - 4
                    radius: 1
                    color: root.fillColor
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
            }

            // Battery nub (positive terminal)
            Rectangle {
                x: body.x + body.width
                y: body.y + 3
                width: 3
                height: body.height - 6
                radius: 1
                color: root.fg
            }

            // Charging bolt overlay — small lightning bolt centered on the battery
            Shape {
                anchors.centerIn: body
                width: 10; height: 12
                visible: root.charging
                opacity: root.charging ? 1 : 0
                Behavior on opacity { OpacityAnimator { duration: 200 } }
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    fillColor: root.fg
                    strokeColor: "transparent"
                    strokeWidth: -1
                    PathSvg {
                        // Tiny lightning bolt: 10×12 viewBox
                        path: "M6 0 L2 6 L5 6 L4 12 L8 5 L5.5 5 Z"
                    }
                }
            }
        }

        // ── Percentage text ─────────────────────────────────────────────
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.pct + "%"
            color: root.fg
            font.pixelSize: 12
            font.bold: false
        }
    }
}
