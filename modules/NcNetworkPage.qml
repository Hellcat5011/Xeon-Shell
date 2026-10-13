// NcNetworkPage.qml
//
//   ┌ Ethernet ─────────────────┐   only when a wired link is up:
//   │ General / IPv4 / IPv6 …   │   connection details (click the header to fold)
//   ├ Wi-Fi ────────────────────┤   only when a Wi-Fi adapter exists:
//   │ Connected / Saved / Avail │   power, rescan, networks
//   └───────────────────────────┘
//
// No ethernet → just the Wi-Fi section. Neither → an empty state.
import QtQuick
import QtQuick.Layouts
import "../services"

Item {
    id: root

    property bool active: false          // tab is showing
    property string expandedSsid: ""
    property bool ethOpen: true

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property bool wired: NcNetwork.ethernetConnected
    readonly property bool hasWifi: NcNetwork.wifiPresent

    // Lets the window's Escape handler close an open row first.
    function collapseAny() {
        if (expandedSsid === "") return false;
        expandedSsid = "";
        return true;
    }

    onActiveChanged: {
        NcNetwork.pollActive = active;
        if (active) { NcNetwork.refresh(); NcNetwork.scan(); }
        else expandedSsid = "";
    }
    onExpandedSsidChanged: NcNetwork.freezeList = expandedSsid !== ""

    // Flatten into [{kind:"header"|"net"}] so the sections live in one list.
    function buildRows(nets) {
        const groups = [["connected", "Connected"], ["saved", "Saved networks"], ["available", "Available networks"]];
        const out = [];
        for (const g of groups) {
            const items = nets.filter(n => n.group === g[0]);
            if (items.length === 0) continue;
            out.push({ kind: "header", label: g[1] });
            for (const n of items) out.push({ kind: "net", net: n });
        }
        return out;
    }
    readonly property var rows: buildRows(NcNetwork.networks)

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ── Ethernet section ────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.wired
            spacing: 8

            Item {
                Layout.fillWidth: true
                implicitHeight: 40

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ethOpen = !root.ethOpen
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 12

                    NcIcon { name: "ethernet"; size: 26; color: root.fg }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: "Ethernet"; color: root.fg; font.pixelSize: 16; font.bold: true }
                        Text {
                            Layout.fillWidth: true
                            text: (NcNetwork.ethMap.connection ? NcNetwork.ethMap.connection + "  ·  " : "")
                                  + NcNetwork.ethernetDevice
                            color: Qt.alpha(root.fg, 0.65)
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    NcIcon {
                        name: "chevron-down"
                        size: 16
                        color: root.fg
                        opacity: 0.7
                        rotation: root.ethOpen ? 180 : 0
                        Behavior on rotation { RotationAnimator { duration: Theme.animMed; easing.type: Easing.OutCubic } }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.ethOpen ? ethCard.implicitHeight : 0
                Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }
                clip: true

                Rectangle {
                    id: ethCard
                    width: parent.width
                    implicitHeight: Math.max(60, ethDetails.implicitHeight + 12)
                    radius: Theme.radiusSmall
                    color: Qt.alpha(root.fg, 0.1)

                    NcNetworkDetails {
                        id: ethDetails
                        y: 6
                        width: parent.width
                        rows: NcNetwork.ethRows
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: NcNetwork.ethRows.length === 0
                        text: "Reading connection details…"
                        color: Qt.alpha(root.fg, 0.6)
                        font.pixelSize: 12
                    }
                }
            }
        }

        // Divider between the two sections
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: root.wired && root.hasWifi
            color: Qt.alpha(root.fg, 0.15)
        }

        // ── Wi-Fi section ───────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.hasWifi
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                NcIcon { name: "wifi"; size: 24; color: root.fg; slashed: !NcNetwork.wifiEnabled }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { text: "Wi-Fi"; color: root.fg; font.pixelSize: 16; font.bold: true }
                    Text {
                        text: !NcNetwork.wifiEnabled ? "Turned off"
                            : NcNetwork.activeSsid !== "" ? "Connected to " + NcNetwork.activeSsid
                            : "Not connected"
                        color: Qt.alpha(root.fg, 0.65)
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.maximumWidth: 220
                    }
                }

                NcSwitch {
                    checked: NcNetwork.wifiEnabled
                    onToggled: NcNetwork.setWifiEnabled(!NcNetwork.wifiEnabled)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: NcNetwork.wifiEnabled
                Text {
                    Layout.fillWidth: true
                    text: "Networks"
                    color: Qt.alpha(root.fg, 0.8)
                    font.pixelSize: 13
                    font.bold: true
                }
                NcRefreshButton {
                    spinning: NcNetwork.scanning
                    onClicked: NcNetwork.scan()
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    visible: NcNetwork.wifiEnabled
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.rows

                    delegate: Item {
                        id: dlg
                        required property var modelData
                        width: ListView.view.width
                        height: loader.item ? loader.item.implicitHeight : 0

                        Loader {
                            id: loader
                            width: parent.width
                            sourceComponent: dlg.modelData.kind === "header" ? headerComp : rowComp
                        }

                        Component {
                            id: headerComp
                            Text {
                                text: dlg.modelData.label.toUpperCase()
                                color: Qt.alpha(root.fg, 0.6)
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.6
                                topPadding: 6
                                leftPadding: 4
                            }
                        }
                        Component {
                            id: rowComp
                            NcNetworkRow {
                                net: dlg.modelData.net
                                expanded: root.expandedSsid === dlg.modelData.net.ssid
                                onExpandRequested: root.expandedSsid = dlg.modelData.net.ssid
                                onCollapseRequested: root.expandedSsid = ""
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: 0.6
                    visible: !NcNetwork.wifiEnabled || (NcNetwork.networks.length === 0)

                    NcIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "wifi"
                        size: 34
                        slashed: !NcNetwork.wifiEnabled
                        color: root.fg
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !NcNetwork.wifiEnabled ? "Wi-Fi is turned off"
                            : NcNetwork.scanning ? "Searching for networks…" : "No networks found"
                        color: root.fg
                        font.pixelSize: 14
                    }
                }
            }
        }

        // ── Nothing to show ─────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.wired && !root.hasWifi

            Column {
                anchors.centerIn: parent
                spacing: 10
                opacity: 0.6
                NcIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "ethernet"
                    size: 34
                    color: root.fg
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No network connection"
                    color: root.fg
                    font.pixelSize: 14
                }
            }
        }

        // Pushes the Ethernet section to the top when Wi-Fi isn't present
        Item { Layout.fillHeight: true; visible: root.wired && !root.hasWifi }
    }
}
