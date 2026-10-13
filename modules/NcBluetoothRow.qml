// NcBluetoothRow.qml — one device: connect / disconnect / pair / forget.
// Pair flow: stop scanning → pair() → (paired) → trust → connect. A watchdog
// reports failures instead of leaving the row stuck on "Pairing…".
//
// `shown` lets the page keep one delegate per device and just slide it in/out
// of whichever section it belongs to (height + opacity, no delegate churn).
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../services"

Item {
    id: root

    property var  device: null
    property bool shown: true

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property bool paired: device ? device.paired === true : false
    readonly property bool connected: device ? device.connected === true : false
    readonly property bool connecting: device ? device.state === BluetoothDeviceState.Connecting : false
    readonly property bool pairing: pairRequested || (device ? device.pairing === true : false)

    property bool pairRequested: false
    property bool failed: false
    property int  elapsed: 0

    function iconFor(d) {
        const i = ((d && d.icon) ? d.icon : "").toLowerCase();
        if (i.indexOf("headset") !== -1 || i.indexOf("headphone") !== -1) return "headset";
        if (i.indexOf("audio") !== -1) return "speaker";
        if (i.indexOf("keyboard") !== -1) return "keyboard";
        if (i.indexOf("phone") !== -1) return "phone";
        if (i.indexOf("computer") !== -1) return "monitor";
        return "bluetooth";
    }

    function statusText() {
        if (!device) return "";
        if (failed) return "Pairing failed";
        if (connecting) return "Connecting…";
        if (pairing) return "Pairing…";
        if (connected) {
            const b = (device.batteryAvailable === true) ? "  ·  " + Math.round(device.battery * 100) + "%" : "";
            return "Connected" + b;
        }
        return paired ? "Paired" : "Available";
    }

    function startPair() {
        if (!device) return;
        failed = false;
        elapsed = 0;
        pairRequested = true;
        // Pairing while scanning is slow and flaky on BlueZ.
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false;
        device.pair();
    }

    function cancelPair() {
        if (device) device.cancelPair();
        pairRequested = false;
    }

    Connections {
        target: root.device
        function onPairedChanged() {
            if (root.device && root.device.paired && root.pairRequested) {
                root.pairRequested = false;
                root.device.trusted = true;
                root.device.connect();
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.pairRequested
        onTriggered: {
            root.elapsed++;
            if (!root.device || root.device.paired) return;
            const stoppedEarly = root.elapsed >= 3 && root.device.pairing === false;
            if (stoppedEarly || root.elapsed >= 30) {
                if (!stoppedEarly) root.device.cancelPair();
                root.pairRequested = false;
                root.failed = true;
            }
        }
    }

    // Slide in/out of its section
    implicitHeight: shown ? 54 : 0
    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    opacity: shown ? 1 : 0
    Behavior on opacity { OpacityAnimator { duration: 160 } }
    visible: implicitHeight > 0.5
    clip: true

    HoverHandler { id: hover }

    NcStateFill {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: root.fg
        level: 0.1
        shown: hover.hovered && !root.connected
    }
    NcStateFill {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: root.fg
        level: 0.16
        shown: root.connected
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 12

        NcIcon {
            name: root.iconFor(root.device)
            size: 22
            color: root.fg
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.device ? root.device.name : ""
                color: root.fg
                font.pixelSize: 14
                font.bold: root.connected
                elide: Text.ElideRight
            }
            Text {
                text: root.statusText()
                color: root.failed ? Theme.error : Qt.alpha(root.fg, 0.65)
                font.pixelSize: 11
            }
        }

        NcButton {
            visible: root.paired && !root.connected && !root.connecting
            compact: true
            text: "Forget"
            onClicked: root.device.forget()
        }
        NcButton {
            compact: true
            active: root.connected
            enabled: !root.connecting
            text: root.connected ? "Disconnect"
                : root.pairing ? "Cancel"
                : root.paired ? "Connect" : "Pair"
            onClicked: {
                if (root.connected) root.device.disconnect();
                else if (root.pairing) root.cancelPair();
                else if (root.paired) root.device.connect();
                else root.startPair();
            }
        }
    }
}
