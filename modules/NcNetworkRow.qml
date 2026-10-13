// NcNetworkRow.qml — one Wi-Fi network.
//   connected row  → click to expand its connection details (IP, MAC …)
//   saved / open   → click (or Connect) to join
//   secured + new  → expands an inline password field
import QtQuick
import QtQuick.Layouts
import "../services"

Item {
    id: root

    property var  net: ({ ssid: "", signal: 0, secure: false, active: false, known: false })
    property bool expanded: false
    signal expandRequested()
    signal collapseRequested()

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property bool isConnecting: NcNetwork.connecting && NcNetwork.connectingSsid === net.ssid
    readonly property bool hasError: NcNetwork.errorSsid === net.ssid && NcNetwork.lastError !== ""
    readonly property int  level: Math.round(net.signal / 25)     // 0..4

    function requestConnect() {
        if (NcNetwork.connecting) return;
        if (net.known || !net.secure) NcNetwork.connectTo(net.ssid, "");
        else root.expandRequested();
    }

    function submit() {
        if (pw.text.length === 0) return;
        NcNetwork.connectTo(net.ssid, pw.text);
        pw.text = "";
        root.collapseRequested();
    }

    onExpandedChanged: if (expanded && !net.active) Qt.callLater(function() { pw.forceActiveFocus() })

    implicitHeight: main.height + extra.height + 6
    clip: true

    HoverHandler { id: hover }

    NcStateFill {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: root.fg
        level: 0.1
        shown: hover.hovered && !root.net.active
    }
    NcStateFill {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: root.fg
        level: 0.16
        shown: root.net.active
    }

    Item {
        id: main
        width: parent.width
        height: 52

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.net.active) {
                    if (root.expanded) root.collapseRequested(); else root.expandRequested();
                } else root.requestConnect();
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 12

            NcIcon {
                name: "wifi"
                size: 22
                color: root.fg
                opacity: 0.35 + 0.65 * Math.min(1, root.level / 3)
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    spacing: 6
                    Text {
                        Layout.maximumWidth: 150
                        text: root.net.ssid
                        color: root.fg
                        font.pixelSize: 14
                        font.bold: root.net.active
                        elide: Text.ElideRight
                    }
                    NcIcon {
                        visible: root.net.secure
                        name: "lock"
                        size: 12
                        color: root.fg
                        opacity: 0.7
                    }
                }
                Text {
                    text: root.isConnecting ? "Connecting…"
                        : root.net.active ? "Connected  ·  " + root.net.signal + "%"
                        : root.net.known ? "Saved" : (root.net.secure ? "Secured" : "Open")
                    color: Qt.alpha(root.fg, 0.65)
                    font.pixelSize: 11
                }
            }

            NcIcon {
                visible: root.net.active
                name: "chevron-down"
                size: 14
                color: root.fg
                opacity: 0.7
                rotation: root.expanded ? 180 : 0
                Behavior on rotation { RotationAnimator { duration: Theme.animMed; easing.type: Easing.OutCubic } }
            }

            NcButton {
                visible: root.net.known && !root.net.active
                compact: true
                text: "Forget"
                onClicked: NcNetwork.forget(root.net.ssid)
            }
            NcButton {
                compact: true
                active: root.net.active
                text: root.net.active ? "Disconnect" : "Connect"
                enabled: !NcNetwork.connecting
                onClicked: root.net.active ? NcNetwork.disconnectWifi() : root.requestConnect()
            }
        }
    }

    Column {
        id: extra
        y: main.height
        width: parent.width
        clip: true
        height: (root.expanded ? (root.net.active ? detailsBox.height : pwBox.height) + 8 : 0)
                + (root.hasError ? errText.height : 0)
        Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }

        // Connection details (connected row)
        Item {
            id: detailsBox
            width: parent.width
            height: det.implicitHeight
            visible: root.expanded && root.net.active
            NcNetworkDetails {
                id: det
                width: parent.width
                rows: NcNetwork.wifiRows
            }
        }

        // Password entry (secured, not yet saved)
        Item {
            id: pwBox
            width: parent.width
            height: 44
            visible: root.expanded && !root.net.active

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                radius: Theme.radiusSmall
                color: Theme.surfaceVariant
                border.width: pw.activeFocus ? 2 : 0
                border.color: Theme.primary

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    TextInput {
                        id: pw
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        font.pixelSize: 14
                        color: Theme.surfaceText
                        clip: true
                        Keys.onReturnPressed: root.submit()
                        Keys.onEnterPressed: root.submit()
                        Keys.onEscapePressed: root.collapseRequested()

                        Text {
                            visible: pw.text.length === 0
                            text: "Password"
                            color: Theme.surfaceVariantText
                            font: pw.font
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    NcButton {
                        compact: true
                        text: "Join"
                        onClicked: root.submit()
                    }
                }
            }
        }

        Text {
            id: errText
            visible: root.hasError
            x: 12
            width: parent.width - 24
            topPadding: 6
            text: NcNetwork.lastError
            color: Theme.error
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
}
