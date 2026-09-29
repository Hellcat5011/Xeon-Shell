pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // --- Bluetooth State ---
    property bool btConnected: false
    property string btName: ""
    property string btBattery: ""
    property string btIcon: ""
    
    // --- Idle State ---
    property bool caffeinateEnabled: false

    Process {
        id: btProcess
        command: ["sh", Quickshell.shellDir + "/scripts/get-bluetooth.sh"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return;
                try {
                    let j = JSON.parse(data);
                    root.btConnected = j.connected === true;
                    if (root.btConnected) {
                        root.btName = j.name;
                        root.btBattery = j.battery;
                        root.btIcon = j.icon || "bluetooth";
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: btProcess.running = true
    }

    // --- Audio State ---
    property var audioSinks: []
    property string defaultSinkName: ""
    property int currentVolume: 0

    Process {
        id: audioProcess
        command: ["sh", Quickshell.shellDir + "/scripts/get-audio.sh"]
        
        property string fullData: ""
        onRunningChanged: {
            if (running) fullData = "";
            else if (fullData.trim().length > 0) {
                try {
                    let j = JSON.parse(fullData);
                    let sinks = j.sinks;
                    root.defaultSinkName = j.default;
                    
                    let newSinks = [];
                    for (let i = 0; i < sinks.length; i++) {
                        newSinks.push({
                            name: sinks[i].name,
                            description: sinks[i].description,
                            volume: sinks[i].volume["front-left"].value_percent.replace("%", "")
                        });
                        
                        if (sinks[i].name === root.defaultSinkName) {
                            root.currentVolume = parseInt(sinks[i].volume["front-left"].value_percent.replace("%", ""));
                        }
                    }
                    root.audioSinks = newSinks;
                } catch(e) { console.log("Audio parse error", e) }
            }
        }

        stdout: SplitParser {
            onRead: data => {
                audioProcess.fullData += data + "\n";
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: audioProcess.running = true
    }
    
    function refreshAudio() {
        audioProcess.running = true;
    }
}
