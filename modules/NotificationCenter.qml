// ─────────────────────────────────────────────────────────────────────────
// NotificationCenter.qml — control centre
//
//   header        Control Centre · settings
//   tiles         [Network] [Bluetooth] [Notifications] [Caffeinate]
//                 The first three ARE the tabs: the open one widens and shows
//                 its details (network info / device / count), the rest shrink
//                 to icons. Caffeinate is a plain toggle.
//   page          Network · Bluetooth · Notifications
//   footer        volume + brightness — fixed, identical on every tab
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import "../services"

OverlayWindow {
    id: nc
    panelWidth: 400
    panelHeight: 1000
    anchorPos: "left"
    enterAnimation: "slideLeft"
    cardColor: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, Config.backgroundOpacity)
    hasBorder: true

    signal openSettings()

    margins.top: 10
    margins.bottom: 10
    margins.left: 0

    // 0 = notifications, 1 = network, 2 = bluetooth
    property int tab: 0

    readonly property color fg: Theme.onPrimaryContainerColor

    // Bluetooth summary for the quick tile
    readonly property var  btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter ? btAdapter.enabled === true : false
    readonly property var  btDevice: {
        const list = Array.from(Bluetooth.devices ? Bluetooth.devices.values : []);
        for (const d of list) if (d.connected) return d;
        return null;
    }

    Component.onCompleted: {
        nc.panelHeight = Qt.binding(function() { return nc.height - 20 })
    }

    onShownChanged: {
        if (shown) {
            tab = 0;
            SystemMonitor.refreshAudio();
            NcNetwork.refresh();
        } else {
            footer.closeMenu();
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (footer.sinkMenuOpen) footer.closeMenu();
            else if (nc.tab === 1 && networkPage.collapseAny()) { /* closed password field */ }
            else nc.hide();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Control Centre"
                color: nc.fg
                font.pixelSize: 18
                font.bold: true
                Layout.fillWidth: true
            }

            NcBatteryIndicator {}

            Rectangle {
                id: gearBtn
                width: 32
                height: 32
                radius: 16
                border.width: 1
                border.color: nc.fg
                color: gearMouse.containsMouse ? nc.fg : "transparent"

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 18 / 24
                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        strokeColor: gearMouse.containsMouse ? Theme.inversePrimary : nc.fg
                        strokeWidth: 2
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        capStyle: ShapePath.RoundCap
                        PathSvg {
                            path: "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"
                        }
                    }
                    ShapePath {
                        strokeColor: gearMouse.containsMouse ? Theme.inversePrimary : nc.fg
                        strokeWidth: 2
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: "M 12 9 A 3 3 0 0 1 12 15 A 3 3 0 0 1 12 9" }
                    }
                }

                MouseArea {
                    id: gearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        nc.hide();
                        nc.openSettings();
                    }
                }
            }
        }

        // ── Tabs (tiles) ────────────────────────────────────────────────
        // The four tiles always span the full width: three are 44 px squares and
        // the open one takes everything that is left. Sizes are explicit (no
        // layout feedback) and sum to the row width at every point of the animation.
        Item {
            id: tiles
            Layout.fillWidth: true
            Layout.preferredHeight: 44

            readonly property real gap: 8
            readonly property real wide: Math.max(44, width - 3 * 44 - 3 * gap)

            Row {
                spacing: tiles.gap
                height: 44

                NcTile {
                    iconName: NcNetwork.ethernetConnected ? "ethernet" : "wifi"
                    title: NcNetwork.statusText
                    subtitle: NcNetwork.statusDetail
                    selected: nc.tab === 1
                    dimmed: !NcNetwork.ethernetConnected && (!NcNetwork.wifiPresent || !NcNetwork.wifiEnabled)
                    slashed: !NcNetwork.ethernetConnected && NcNetwork.wifiPresent && !NcNetwork.wifiEnabled
                    expandedWidth: tiles.wide
                    onClicked: nc.tab = 1
                }
                NcTile {
                    iconName: "bluetooth"
                    title: !nc.btAdapter ? "No adapter"
                         : !nc.btOn ? "Bluetooth"
                         : nc.btDevice ? nc.btDevice.name : "Bluetooth"
                    subtitle: !nc.btAdapter ? ""
                            : !nc.btOn ? "Off"
                            : nc.btDevice ? ("Connected" + ((nc.btDevice.batteryAvailable === true) ? "  ·  " + Math.round(nc.btDevice.battery * 100) + "%" : ""))
                            : "On"
                    selected: nc.tab === 2
                    dimmed: !nc.btOn
                    expandedWidth: tiles.wide
                    onClicked: nc.tab = 2
                }
                NcTile {
                    iconName: "bell"
                    title: "Notifications"
                    subtitle: NotificationManager.silent ? "Silent" : ""
                    countText: NotificationManager.count > 0 ? NotificationManager.count : ""
                    selected: nc.tab === 0
                    slashed: NotificationManager.silent
                    badge: NotificationManager.count
                    expandedWidth: tiles.wide
                    onClicked: nc.tab = 0
                }
                NcTile {
                    iconName: "coffee"
                    on: SystemMonitor.caffeinateEnabled
                    dimmed: !SystemMonitor.caffeinateEnabled
                    slashed: !SystemMonitor.caffeinateEnabled
                    expandedWidth: tiles.wide
                    onClicked: SystemMonitor.caffeinateEnabled = !SystemMonitor.caffeinateEnabled
                }
            }
        }

        // ── Pages ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Pages cross-fade with OpacityAnimator (render thread). They stay
            // visible while fading out, and become visible the instant they open.
            NcNotificationsPage {
                anchors.fill: parent
                opacity: nc.tab === 0 ? 1 : 0
                visible: nc.tab === 0 || opacity > 0
                Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }
            }
            NcNetworkPage {
                id: networkPage
                anchors.fill: parent
                active: nc.shown && nc.tab === 1
                opacity: nc.tab === 1 ? 1 : 0
                visible: nc.tab === 1 || opacity > 0
                Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }
            }
            NcBluetoothPage {
                anchors.fill: parent
                active: nc.shown && nc.tab === 2
                opacity: nc.tab === 2 ? 1 : 0
                visible: nc.tab === 2 || opacity > 0
                Behavior on opacity { OpacityAnimator { duration: Theme.animFast } }
            }
        }

        // ── Fixed footer (same on every tab) ────────────────────────────
        NcFooter {
            id: footer
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
        }
    }
}
