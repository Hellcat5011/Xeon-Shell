// NcBluetoothPage.qml — power, Discoverable, refresh, and ordered device list:
//
//     Connected  →  Paired  →  Available   (+ unnamed devices, collapsed)
//
// Scanning runs for ~15 s when the tab opens and whenever the refresh button
// is pressed, then stops by itself (kinder to the radio and the battery).
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../services"

Item {
    id: root

    property bool active: false          // tab is showing
    property bool showUnnamed: false

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property var  adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter ? adapter.enabled === true : false
    readonly property bool discovering: adapter ? adapter.discovering === true : false
    readonly property var  devices: Array.from(Bluetooth.devices ? Bluetooth.devices.values : [])

    // BLE advertisers that never resolve a name show up as their MAC address.
    function isNamed(d) {
        return !/^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i.test(d.name || "");
    }

    readonly property int connectedCount: devices.filter(d => d.connected).length
    readonly property int pairedCount:    devices.filter(d => d.paired && !d.connected).length
    readonly property int availableCount: devices.filter(d => !d.paired && !d.connected && root.isNamed(d)).length
    readonly property int unnamedCount:   devices.filter(d => !d.paired && !d.connected && !root.isNamed(d)).length

    // ── Scanning ────────────────────────────────────────────────────────
    function startScan() {
        if (!adapter || !powered) return;
        adapter.discovering = true;
        scanTimer.restart();
    }
    function stopScan() {
        scanTimer.stop();
        if (adapter && adapter.discovering) adapter.discovering = false;
    }
    function rescan() {
        if (!adapter || !powered) return;
        if (adapter.discovering) {                 // restart so BlueZ re-announces devices
            adapter.discovering = false;
            restartTimer.restart();
        } else startScan();
    }

    Timer { id: scanTimer; interval: 15000; onTriggered: root.stopScan() }
    Timer { id: restartTimer; interval: 350; onTriggered: root.startScan() }

    onActiveChanged: { if (active) startScan(); else stopScan(); }
    onPoweredChanged: if (powered && active) startScan()

    component SectionLabel: Text {
        color: Qt.alpha(Theme.onPrimaryContainerColor, 0.6)
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 0.6
        topPadding: 6
        leftPadding: 4
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Power
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { text: "Bluetooth"; color: root.fg; font.pixelSize: 16; font.bold: true }
                Text {
                    text: !root.adapter ? "No adapter found" : root.powered ? "On" : "Turned off"
                    color: Qt.alpha(root.fg, 0.65)
                    font.pixelSize: 12
                }
            }
            NcSwitch {
                enabled: !!root.adapter
                checked: root.powered
                onToggled: root.adapter.enabled = !root.adapter.enabled
            }
        }

        // Discoverable
        Rectangle {
            Layout.fillWidth: true
            visible: root.powered
            implicitHeight: 52
            radius: Theme.radiusSmall
            color: Qt.alpha(root.fg, 0.1)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { text: "Discoverable"; color: root.fg; font.pixelSize: 14 }
                    Text {
                        Layout.fillWidth: true
                        text: root.adapter && root.adapter.discoverable
                              ? "Visible as “" + root.adapter.name + "”"
                              : "Hidden from other devices"
                        color: Qt.alpha(root.fg, 0.65)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                NcSwitch {
                    checked: root.adapter ? root.adapter.discoverable === true : false
                    onToggled: root.adapter.discoverable = !root.adapter.discoverable
                }
            }
        }

        // List header + manual rescan
        RowLayout {
            Layout.fillWidth: true
            visible: root.powered
            Text {
                Layout.fillWidth: true
                text: root.discovering ? "Devices  ·  searching…" : "Devices"
                color: Qt.alpha(root.fg, 0.8)
                font.pixelSize: 13
                font.bold: true
            }
            NcRefreshButton {
                spinning: root.discovering
                onClicked: root.rescan()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                anchors.fill: parent
                visible: root.powered
                clip: true
                contentWidth: width
                contentHeight: devCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: devCol
                    width: parent.width
                    spacing: 4

                    // 1 ─ Connected
                    SectionLabel { text: "CONNECTED"; visible: root.connectedCount > 0 }
                    Repeater {
                        model: Bluetooth.devices
                        delegate: NcBluetoothRow {
                            required property var modelData
                            width: devCol.width
                            device: modelData
                            shown: modelData.connected === true
                        }
                    }

                    // 2 ─ Paired (known)
                    SectionLabel { text: "PAIRED"; visible: root.pairedCount > 0 }
                    Repeater {
                        model: Bluetooth.devices
                        delegate: NcBluetoothRow {
                            required property var modelData
                            width: devCol.width
                            device: modelData
                            shown: modelData.paired === true && modelData.connected !== true
                        }
                    }

                    // 3 ─ Available (named)
                    SectionLabel { text: "AVAILABLE"; visible: root.availableCount > 0 }
                    Repeater {
                        model: Bluetooth.devices
                        delegate: NcBluetoothRow {
                            required property var modelData
                            width: devCol.width
                            device: modelData
                            shown: modelData.paired !== true && modelData.connected !== true && root.isNamed(modelData)
                        }
                    }

                    // 4 ─ Unnamed (address-only) devices, collapsed by default
                    Item {
                        width: devCol.width
                        height: root.unnamedCount > 0 ? 40 : 0
                        visible: height > 0
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            Text {
                                Layout.fillWidth: true
                                text: root.unnamedCount + (root.unnamedCount === 1 ? " unnamed device" : " unnamed devices")
                                color: Qt.alpha(root.fg, 0.6)
                                font.pixelSize: 12
                            }
                            NcButton {
                                compact: true
                                text: root.showUnnamed ? "Hide" : "Show"
                                onClicked: root.showUnnamed = !root.showUnnamed
                            }
                        }
                    }
                    Repeater {
                        model: Bluetooth.devices
                        delegate: NcBluetoothRow {
                            required property var modelData
                            width: devCol.width
                            device: modelData
                            shown: root.showUnnamed && modelData.paired !== true && modelData.connected !== true && !root.isNamed(modelData)
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                opacity: 0.6
                visible: !root.powered || (root.connectedCount + root.pairedCount + root.availableCount + root.unnamedCount === 0)

                NcIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "bluetooth"
                    size: 34
                    color: root.fg
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !root.powered ? "Bluetooth is turned off"
                        : root.discovering ? "Searching for devices…" : "No devices found"
                    color: root.fg
                    font.pixelSize: 14
                }
            }
        }
    }
}
