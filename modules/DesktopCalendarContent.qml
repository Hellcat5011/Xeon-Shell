import QtQuick
import QtQuick.Layouts
import Qt.labs.qmlmodels
import Quickshell
import "../services"

Item {
    id: root

    property bool interactive: true
    property bool transparentBg: false

    readonly property real defaultWidth: 360
    readonly property real defaultHeight: 320
    readonly property real scaleFactor: Math.max(0.65, Math.min(width / defaultWidth, height / defaultHeight))

    property var selectedDate: new Date()
    property string viewMode: "days" // "days", "months", "years"

    DesktopWidgetBackground {
        transparentBg: root.transparentBg
    }

    Item {
        anchors.fill: parent
        anchors.margins: Math.round(16 * root.scaleFactor)

        // HEADER
        RowLayout {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(22, Math.round(30 * root.scaleFactor))

            // Left arrow (only in days mode)
            Text {
                text: ""
                font.family: "CaskaydiaCove Nerd Font Mono"
                font.pixelSize: Math.max(11, Math.round(16 * root.scaleFactor))
                color: Theme.onPrimaryContainerColor
                visible: root.viewMode === "days"
                MouseArea {
                    anchors.fill: parent
                    enabled: root.interactive
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        let d = new Date(root.selectedDate);
                        d.setMonth(d.getMonth() - 1);
                        root.selectedDate = d;
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: Math.max(4, Math.round(10 * root.scaleFactor))
                
                // Month Selector
                Text {
                    text: Qt.formatDate(root.selectedDate, "MMMM")
                    color: Theme.onPrimaryContainerColor
                    font.family: "CaskaydiaCove Nerd Font Mono"
                    font.bold: true
                    font.pixelSize: Math.max(12, Math.round(16 * root.scaleFactor))
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewMode = (root.viewMode === "months") ? "days" : "months"
                    }
                }

                // Year Selector
                Text {
                    text: Qt.formatDate(root.selectedDate, "yyyy")
                    color: Theme.onPrimaryContainerColor
                    font.family: "CaskaydiaCove Nerd Font Mono"
                    font.bold: true
                    font.pixelSize: Math.max(12, Math.round(16 * root.scaleFactor))
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewMode = (root.viewMode === "years") ? "days" : "years"
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Right arrow (only in days mode)
            Text {
                text: ""
                font.family: "CaskaydiaCove Nerd Font Mono"
                font.pixelSize: Math.max(11, Math.round(16 * root.scaleFactor))
                color: Theme.onPrimaryContainerColor
                visible: root.viewMode === "days"
                MouseArea {
                    anchors.fill: parent
                    enabled: root.interactive
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        let d = new Date(root.selectedDate);
                        d.setMonth(d.getMonth() + 1);
                        root.selectedDate = d;
                    }
                }
            }
        }

        // DAYS VIEW
        GridLayout {
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Math.round(8 * root.scaleFactor)
            anchors.bottomMargin: Math.round(4 * root.scaleFactor)
            columns: 7
            columnSpacing: Math.max(2, Math.round(4 * root.scaleFactor))
            rowSpacing: Math.max(2, Math.round(4 * root.scaleFactor))
            visible: root.viewMode === "days"

            Repeater {
                model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: Theme.onPrimaryContainerColor
                        font.family: "CaskaydiaCove Nerd Font Mono"
                        font.pixelSize: Math.max(10, Math.round(13 * root.scaleFactor))
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Repeater {
                model: {
                    let d = new Date(root.selectedDate);
                    d.setDate(1);
                    let daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
                    let startDay = d.getDay();
                    let arr = [];
                    for (let i = 0; i < startDay; i++) arr.push("");
                    for (let i = 1; i <= daysInMonth; i++) arr.push(i.toString());
                    let totalCells = (arr.length > 35) ? 42 : 35;
                    while (arr.length < totalCells) arr.push("");
                    return arr;
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(16, Math.min(parent.width, parent.height) - 4)
                        height: width
                        radius: width / 2
                        property bool isToday: {
                            if (modelData === "") return false;
                            let now = new Date();
                            return (now.getDate().toString() === modelData) && 
                                   (now.getMonth() === root.selectedDate.getMonth()) && 
                                   (now.getFullYear() === root.selectedDate.getFullYear());
                        }
                        color: isToday ? Theme.primary : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: parent.isToday ? Theme.background : Theme.onPrimaryContainerColor
                            font.family: "CaskaydiaCove Nerd Font Mono"
                            font.pixelSize: Math.max(10, Math.round(13 * root.scaleFactor))
                            font.bold: parent.isToday
                        }
                    }
                }
            }
        }

        // MONTHS VIEW
        GridLayout {
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Math.round(8 * root.scaleFactor)
            columns: 3
            columnSpacing: Math.max(4, Math.round(8 * root.scaleFactor))
            rowSpacing: Math.max(4, Math.round(8 * root.scaleFactor))
            visible: root.viewMode === "months"

            Repeater {
                model: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 3
                    property bool isSelected: index === root.selectedDate.getMonth()
                    color: isSelected ? Theme.primary : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: parent.isSelected ? Theme.background : Theme.onPrimaryContainerColor
                        font.family: "CaskaydiaCove Nerd Font Mono"
                        font.pixelSize: Math.max(11, Math.round(15 * root.scaleFactor))
                        font.bold: parent.isSelected
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let d = new Date(root.selectedDate);
                            d.setMonth(index);
                            root.selectedDate = d;
                            root.viewMode = "days";
                        }
                    }
                }
            }
        }

        // YEARS VIEW
        GridLayout {
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Math.round(8 * root.scaleFactor)
            columns: 3
            columnSpacing: Math.max(4, Math.round(8 * root.scaleFactor))
            rowSpacing: Math.max(4, Math.round(8 * root.scaleFactor))
            visible: root.viewMode === "years"

            Repeater {
                model: {
                    let y = root.selectedDate.getFullYear();
                    let arr = [];
                    for (let i = y - 4; i <= y + 7; i++) {
                        arr.push(i);
                    }
                    return arr;
                }
                
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 3
                    property bool isSelected: modelData === root.selectedDate.getFullYear()
                    color: isSelected ? Theme.primary : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData.toString()
                        color: parent.isSelected ? Theme.background : Theme.onPrimaryContainerColor
                        font.family: "CaskaydiaCove Nerd Font Mono"
                        font.pixelSize: Math.max(11, Math.round(15 * root.scaleFactor))
                        font.bold: parent.isSelected
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let d = new Date(root.selectedDate);
                            d.setFullYear(modelData);
                            root.selectedDate = d;
                            root.viewMode = "days";
                        }
                    }
                }
            }
        }
    }
}
