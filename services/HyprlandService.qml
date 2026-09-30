pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: root

    property bool isLua: false
    property int stateRevision: 0
    property bool overviewOpen: false
    property bool switcherOpen: false

    Process {
        id: luaDetector
        command: ["sh", "-c", "test -f \"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua\""]
        running: true
        onExited: (code) => {
            root.isLua = (code === 0);
        }
    }

    Component.onCompleted: {
        refreshAll();
    }

    function refreshAll() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        root.stateRevision++;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            let name = event.name;
            if (name === "workspace" || name === "focusedmon" || name === "activeworkspace" ||
                name === "createworkspace" || name === "destroyworkspace" || name === "moveworkspace" ||
                name === "urgent") {
                Hyprland.refreshWorkspaces();
                root.stateRevision++;
            }
            if (name === "openwindow" || name === "closewindow" || name === "movewindow" ||
                name === "movewindowv2" || name === "activewindow" || name === "activewindowv2" ||
                name === "changefloatingmode" || name === "urgent") {
                Hyprland.refreshToplevels();
                root.stateRevision++;
            }
        }
    }

    Timer {
        id: livePollTimer
        interval: 600
        repeat: true
        running: root.overviewOpen || root.switcherOpen
        onTriggered: {
            Hyprland.refreshWorkspaces();
            Hyprland.refreshToplevels();
            root.stateRevision++;
        }
    }

    function switchWorkspace(wsId: int) {
        if (root.isLua) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsId + " })");
        } else {
            Hyprland.dispatch("workspace " + wsId);
        }
    }

    function focusWindow(address: string, wsId: int) {
        if (!address) return;
        let addr = address.startsWith("0x") ? address : ("0x" + address);
        if (root.isLua) {
            if (wsId > 0) {
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsId + " })");
            }
            Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + addr + "' })");
        } else {
            if (wsId > 0) {
                Hyprland.dispatch("workspace " + wsId);
            }
            Hyprland.dispatch("focuswindow address:" + addr);
        }
    }

    function moveWindowSilent(wsId: int, address: string) {
        if (!address) return;
        let addr = address.startsWith("0x") ? address : ("0x" + address);
        if (root.isLua) {
            Hyprland.dispatch("hl.dsp.window.move({ workspace = " + wsId + ", window = 'address:" + addr + "', follow = false })");
        } else {
            Hyprland.dispatch("movetoworkspacesilent " + wsId + ",address:" + addr);
        }
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        root.stateRevision++;
    }

    function getFocusedScreen(): var {
        let focusedName = "";
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name) {
            focusedName = Hyprland.focusedMonitor.name;
        } else {
            for (let m of Hyprland.monitors.values) {
                if (m.focused && m.name) {
                    focusedName = m.name;
                    break;
                }
            }
        }
        if (focusedName && Quickshell.screens) {
            for (let s of Quickshell.screens) {
                if (s && s.name === focusedName) return s;
            }
        }
        return (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null;
    }

    function getMonitorForWorkspace(wsId: int): var {
        for (let ws of Hyprland.workspaces.values) {
            let id = ws.id;
            if (id === -1 && ws.name) id = parseInt(ws.name);
            if (id === wsId && ws.monitor) return ws.monitor;
        }
        for (let tl of Hyprland.toplevels.values) {
            let ipc = tl.lastIpcObject;
            if (ipc && ipc.workspace && (ipc.workspace.id === wsId || ipc.workspace.name === ("" + wsId))) {
                if (tl.monitor) return tl.monitor;
            }
        }
        if (Hyprland.focusedMonitor) return Hyprland.focusedMonitor;
        return (Hyprland.monitors.values.length > 0) ? Hyprland.monitors.values[0] : null;
    }
}
