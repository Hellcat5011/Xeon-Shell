pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var mprisData: ({})
    property bool isPlaying: mprisData.status === "Playing"

    // Track position for smooth progress bar interpolation
    property real trackPosition: 0
    property real trackLength: 0

    onMprisDataChanged: {
        trackPosition = root.mprisData.position || 0
        trackLength = root.mprisData.length || 0
    }

    // Smooth local interpolation — advances position between 1-second script updates
    Timer {
        interval: 100
        running: root.isPlaying && root.trackLength > 0
        repeat: true
        onTriggered: {
            if (root.trackPosition < root.trackLength)
                root.trackPosition += 0.1
        }
    }

    // Static process for playerctl commands to avoid Qt.createQmlObject memory leaks
    Process { id: playerCtlProcess }

    function runPlayerCtl(cmd) {
        if (!root.mprisData.player) return;
        playerCtlProcess.command = ["playerctl", "-p", root.mprisData.player, cmd];
        playerCtlProcess.running = true;
    }

    // Exactly one get-mpris.sh process lives in this singleton service
    Process {
        id: mprisProcess
        command: ["bash", Quickshell.shellDir + "/scripts/get-mpris.sh"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.mprisData = JSON.parse(data)
                } catch(e) {}
            }
        }
    }
}
