import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"

ComboBox {
    id: control
    implicitWidth: 150
    implicitHeight: 36
    leftPadding: 24
    rightPadding: 24

    property bool searchable: (control.model && (control.model.length > 8 || (control.model.count && control.model.count > 8))) ? true : false
    property string searchPlaceholder: "Search..."
    property string searchQuery: ""

    readonly property var filteredItems: {
        if (!control.model) return [];
        let query = searchQuery.trim().toLowerCase();
        let raw = control.model;
        let len = (raw.length !== undefined) ? raw.length : (raw.count !== undefined ? raw.count : 0);
        let items = [];
        for (let i = 0; i < len; i++) {
            let val = (raw.get !== undefined) ? raw.get(i) : raw[i];
            let str = (typeof val === "string") ? val : (val && val.text !== undefined ? val.text : ("" + val));
            if (!query || str.toLowerCase().indexOf(query) !== -1) {
                items.push({ text: str, originalIndex: i });
            }
        }
        return items;
    }

    indicator: Canvas {
        x: control.width - width - 12
        y: control.topPadding + (control.availableHeight - height) / 2
        width: 10
        height: 5
        contextType: "2d"
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width / 2, height);
            ctx.closePath();
            ctx.fillStyle = Theme.onPrimaryContainerColor;
            ctx.fill();
        }
    }

    contentItem: Text {
        text: control.currentText || ((control.model && control.currentIndex >= 0 && control.model[control.currentIndex]) ? control.model[control.currentIndex] : "")
        color: Theme.onPrimaryContainerColor
        font.pixelSize: 14
        font.family: (text !== "System Default" && text !== "Default (Global)") ? text : ""
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignLeft
        leftPadding: 8
        font.capitalization: control.font.capitalization
        elide: Text.ElideRight
    }

    background: Rectangle {
        color: Theme.primary
        opacity: 0.1
        radius: 18
        border.width: 1
        border.color: control.activeFocus ? Theme.primary : Theme.outlineVariant
    }

    popup: Popup {
        id: popupControl
        x: (control.width < width) ? (control.width - width) : 0
        y: control.height + 4
        width: Math.max(control.width, 240)
        implicitHeight: {
            let searchH = control.searchable ? 44 : 0;
            let listH = Math.min(240, Math.max(36, listView.contentHeight));
            return searchH + listH + 14;
        }
        padding: 4

        onOpened: {
            if (control.searchable && searchField) {
                searchField.forceActiveFocus();
            }
            if (control.currentIndex >= 0 && listView) {
                listView.positionViewAtIndex(Math.max(0, control.currentIndex), ListView.Center);
            }
        }

        onClosed: {
            control.searchQuery = "";
            if (searchField) {
                searchField.text = "";
            }
        }

        contentItem: ColumnLayout {
            spacing: 4

            // Search Bar Container
            Item {
                id: searchContainer
                visible: control.searchable
                Layout.fillWidth: true
                Layout.preferredHeight: control.searchable ? 34 : 0
                Layout.margins: 4

                TextField {
                    id: searchField
                    anchors.fill: parent
                    placeholderText: control.searchPlaceholder
                    placeholderTextColor: Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.4)
                    color: Theme.onPrimaryContainerColor
                    font.pixelSize: 13
                    leftPadding: 32
                    rightPadding: clearBtn.visible ? 28 : 10
                    topPadding: 6
                    bottomPadding: 6

                    onTextChanged: {
                        control.searchQuery = text;
                    }

                    Keys.onDownPressed: {
                        listView.forceActiveFocus();
                        if (listView.currentIndex < listView.count - 1) {
                            listView.currentIndex++;
                        }
                    }

                    Keys.onReturnPressed: {
                        if (control.filteredItems.length > 0) {
                            let item = control.filteredItems[Math.max(0, listView.currentIndex)];
                            if (item) {
                                control.currentIndex = item.originalIndex;
                                control.activated(item.originalIndex);
                                popupControl.close();
                            }
                        }
                    }

                    Keys.onEscapePressed: {
                        popupControl.close();
                    }

                    background: Item {
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.onPrimaryContainerColor
                            opacity: 0.15
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.primary
                            opacity: (parent.parent.activeFocus || parent.parent.hovered) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    Text {
                        text: "⚲"
                        font.pixelSize: 15
                        color: Theme.onPrimaryContainerColor
                        opacity: 0.5
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        rotation: -45
                    }

                    Text {
                        id: clearBtn
                        visible: searchField.text !== ""
                        text: "✕"
                        font.pixelSize: 11
                        color: Theme.onPrimaryContainerColor
                        opacity: clearMouseArea.containsMouse ? 0.9 : 0.4
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10

                        MouseArea {
                            id: clearMouseArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // Divider line if searchable
            Rectangle {
                visible: control.searchable
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                height: 1
                color: Theme.outlineVariant
                opacity: 0.4
            }

            // ListView Area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: control.filteredItems
                    ScrollBar.vertical: ScrollBar {
                        policy: (listView.contentHeight > listView.height) ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: itemDlgt
                        width: listView.width
                        height: 36

                        readonly property string itemText: modelData.text
                        readonly property int origIndex: modelData.originalIndex
                        readonly property bool isSelected: (origIndex === control.currentIndex) || (itemText === control.currentText)
                        readonly property bool isHovered: itemMouseArea.containsMouse

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: 8
                            color: Theme.onPrimaryContainerColor
                            opacity: itemDlgt.isSelected ? 0.85 : (itemDlgt.isHovered ? 0.15 : 0.0)
                            layer.enabled: true
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: itemDlgt.itemText
                                color: itemDlgt.isSelected ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                font.pixelSize: 13
                                font.weight: itemDlgt.isSelected ? Font.DemiBold : Font.Normal
                                font.family: (itemDlgt.itemText !== "System Default" && itemDlgt.itemText !== "Default (Global)") ? itemDlgt.itemText : ""
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: itemDlgt.isSelected
                                text: "✓"
                                color: Theme.inversePrimary
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: itemMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                control.currentIndex = itemDlgt.origIndex;
                                control.activated(itemDlgt.origIndex);
                                popupControl.close();
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: listView.count === 0
                    text: "No matching fonts"
                    color: Theme.onPrimaryContainerColor
                    opacity: 0.5
                    font.pixelSize: 12
                }
            }
        }

        background: Rectangle {
            color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.98)
            radius: 16
            border.width: 1
            border.color: Theme.outlineVariant
        }
    }
}
