// ─────────────────────────────────────────────────────────────────────────
// NetworkService.qml — Ethernet-first networking via NetworkManager (nmcli)
//
//   • Ethernet connected  → ethernetConnected = true; Wi-Fi is ignored (no
//                           scanning, no list). detailRows describes the link.
//   • otherwise           → Wi-Fi: scan / connect / forget / disconnect.
//
// `nmcli monitor` keeps state live. Wi-Fi is only re-scanned while the
// Network tab is open (pollActive).
// ─────────────────────────────────────────────────────────────────────────
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ── Public state ────────────────────────────────────────────────────
    property bool   wifiEnabled: false
    property bool   scanning: false
    property bool   connecting: false
    property string connectingSsid: ""
    property string lastError: ""
    property string errorSsid: ""
    property string activeSsid: ""
    property int    activeSignal: 0
    property string wifiDevice: ""
    property string ethernetDevice: ""
    property bool   ethernetConnected: false
    property var    networks: []        // [{ssid, signal, secure, active, known, group}]
    property bool   pollActive: false   // set by the Network tab while visible
    property bool   freezeList: false   // set while a row is expanded

    // Details of the active link (ethernet if connected, else the Wi-Fi link)
    property var detailMap: ({})
    property int linkSpeed: 0           // Mb/s, ethernet only

    readonly property string primaryDevice:
        ethernetConnected ? ethernetDevice : (activeSsid !== "" ? wifiDevice : "")

    readonly property string firstIp: {
        const a = detailMap.ip4;
        return (a && a.length) ? a[0].split("/")[0] : "";
    }

    function speedText(n) {
        return n >= 1000 ? (n / 1000) + " Gb/s" : n + " Mb/s";
    }

    // Tile title / subtitle
    readonly property string statusText: {
        if (ethernetConnected) return "Ethernet";
        if (!wifiEnabled) return "Wi-Fi off";
        if (activeSsid !== "") return activeSsid;
        return "Not connected";
    }
    readonly property string statusDetail: {
        const parts = [];
        if (ethernetConnected) {
            if (firstIp !== "") parts.push(firstIp);
            if (linkSpeed > 0) parts.push(speedText(linkSpeed));
        } else if (wifiEnabled && activeSsid !== "") {
            parts.push(activeSignal + "%");
            if (firstIp !== "") parts.push(firstIp);
        } else {
            parts.push(wifiEnabled ? "Wi-Fi" : "Turned off");
        }
        return parts.join(" · ");
    }

    // Rows for the details card: [{label, value}]
    readonly property var detailRows: {
        const d = detailMap;
        const rows = [];
        const add = function(l, v) {
            if (v !== undefined && v !== null && String(v) !== "") rows.push({ label: l, value: String(v) });
        };
        const first = function(a) { return (a && a.length) ? a[0] : ""; };
        if (ethernetConnected) {
            add("Status", "Connected");
            add("Connection", d.connection);
        } else if (activeSsid !== "") {
            add("Network", activeSsid);
            add("Signal", activeSignal + "%");
        }
        add("Interface", d.device);
        add("MAC address", d.mac);
        add("IPv4 address", first(d.ip4));
        add("Gateway", d.gateway);
        add("DNS", (d.dns || []).join(", "));
        add("IPv6 address", first(d.ip6));
        if (ethernetConnected && linkSpeed > 0) add("Link speed", speedText(linkSpeed));
        return rows;
    }

    // ── Internals ───────────────────────────────────────────────────────
    property var    _raw: []
    property var    knownNames: []
    property string _listSig: ""
    property int    _connectCode: 0
    property bool   _connectNeedsCleanup: false

    onFreezeListChanged: if (!freezeList) rebuildNetworks()
    onPrimaryDeviceChanged: detailsTimer.restart()
    Component.onCompleted: refresh()

    function splitTerse(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) { cur += line[i + 1]; i++; }
            else if (ch === ":") { out.push(cur); cur = ""; }
            else cur += ch;
        }
        out.push(cur);
        return out;
    }

    // ── Refresh ─────────────────────────────────────────────────────────
    function refresh() {
        radioProc.running = true;
        statusProc.running = true;
        knownProc.running = true;
        listProc.running = true;
        detailsTimer.restart();
    }
    function refreshSoon() { refreshTimer.restart(); }

    function scan() {
        if (!wifiEnabled || scanning || ethernetConnected) return;
        scanning = true;
        rescanProc.running = true;
        scanTimer.restart();
        listProc.running = true;
    }

    Timer { id: refreshTimer; interval: 400; onTriggered: root.refresh() }
    Timer { id: detailsTimer; interval: 200; onTriggered: root.refreshDetails() }
    Timer {
        id: scanTimer
        interval: 3000
        onTriggered: { root.scanning = false; listProc.running = true; }
    }
    Timer {
        interval: 8000; repeat: true
        running: root.pollActive && root.wifiEnabled && !root.ethernetConnected
        onTriggered: root.scan()
    }

    Process {
        id: monitorProc
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: data => root.refreshSoon() }
    }

    Process {
        id: radioProc
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiEnabled = this.text.trim() === "enabled"
        }
    }

    Process {
        id: statusProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
    }

    Process {
        id: knownProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector { onStreamFinished: root.parseKnown(this.text) }
    }

    Process {
        id: listProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector { onStreamFinished: root.parseList(this.text) }
    }

    Process { id: rescanProc; command: ["nmcli", "device", "wifi", "rescan"] }

    Process {
        id: detailsProc
        stdout: StdioCollector { onStreamFinished: root.parseDetails(this.text) }
    }

    Process {
        id: speedProc
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(this.text.trim());
                root.linkSpeed = (n > 0) ? n : 0;
            }
        }
    }

    function refreshDetails() {
        const dev = primaryDevice;
        if (dev === "") { detailMap = ({}); linkSpeed = 0; return; }
        detailsProc.command = ["nmcli", "-t", "-f",
            "GENERAL.DEVICE,GENERAL.HWADDR,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS",
            "device", "show", dev];
        detailsProc.running = true;
        if (ethernetConnected) {
            speedProc.command = ["cat", "/sys/class/net/" + dev + "/speed"];
            speedProc.running = true;
        } else {
            linkSpeed = 0;
        }
    }

    function parseDetails(text) {
        const m = { device: "", mac: "", connection: "", gateway: "", ip4: [], ip6: [], dns: [] };
        for (const line of text.split("\n")) {
            if (!line) continue;
            const f = splitTerse(line);
            if (f.length < 2) continue;
            const key = f[0].replace(/\[\d+\]$/, "");
            const val = f.slice(1).join(":");
            if (val === "" || val === "--") continue;
            switch (key) {
            case "GENERAL.DEVICE":     m.device = val; break;
            case "GENERAL.HWADDR":     m.mac = val; break;
            case "GENERAL.CONNECTION": m.connection = val; break;
            case "IP4.ADDRESS":        m.ip4.push(val); break;
            case "IP4.GATEWAY":        m.gateway = val; break;
            case "IP4.DNS":            m.dns.push(val); break;
            case "IP6.ADDRESS":        m.ip6.push(val); break;
            }
        }
        // Prefer a routable IPv6 over link-local (fe80::)
        m.ip6.sort((a, b) => (a.toLowerCase().startsWith("fe80") ? 1 : 0) - (b.toLowerCase().startsWith("fe80") ? 1 : 0));
        detailMap = m;
    }

    function parseStatus(text) {
        let eth = "";
        let wifi = "";
        for (const line of text.split("\n")) {
            if (!line) continue;
            const f = splitTerse(line);
            if (f.length < 3) continue;
            if (f[1] === "wifi" && wifi === "") wifi = f[0];
            if (f[1] === "ethernet" && f[2].startsWith("connected") && eth === "") eth = f[0];
        }
        wifiDevice = wifi;
        ethernetDevice = eth;
        ethernetConnected = eth !== "";
    }

    function parseKnown(text) {
        const names = [];
        for (const line of text.split("\n")) {
            if (!line) continue;
            const f = splitTerse(line);
            if (f.length >= 2 && (f[1].indexOf("wireless") !== -1 || f[1] === "wifi")) names.push(f[0]);
        }
        knownNames = names;
        rebuildNetworks();
    }

    function parseList(text) {
        const raw = [];
        for (const line of text.split("\n")) {
            if (!line) continue;
            const f = splitTerse(line);
            if (f.length < 4 || f[1] === "") continue;
            raw.push({
                ssid: f[1],
                signal: parseInt(f[2]) || 0,
                secure: f[3] !== "" && f[3] !== "--",
                active: f[0] === "*"
            });
        }
        _raw = raw;
        rebuildNetworks();
    }

    function rebuildNetworks() {
        const best = {};
        for (const e of _raw) {
            const b = best[e.ssid];
            if (!b) best[e.ssid] = { ssid: e.ssid, signal: e.signal, secure: e.secure, active: e.active };
            else {
                if (e.signal > b.signal) b.signal = e.signal;
                if (e.active) b.active = true;
            }
        }
        const rank = { connected: 0, saved: 1, available: 2 };
        const out = [];
        let act = "";
        let actSig = 0;
        for (const k of Object.keys(best)) {
            const b = best[k];
            b.known = knownNames.indexOf(b.ssid) !== -1;
            b.group = b.active ? "connected" : (b.known ? "saved" : "available");
            if (b.active) { act = b.ssid; actSig = b.signal; }
            out.push(b);
        }
        // Connected first, saved second, available last; strongest first within each.
        out.sort((a, b) => (rank[a.group] - rank[b.group]) || (b.signal - a.signal));
        activeSsid = act;
        activeSignal = actSig;

        if (freezeList) return;
        const sig = out.map(n => n.ssid + "|" + Math.round(n.signal / 25) + "|" + (n.secure ? 1 : 0) + n.group).join("\n");
        if (sig !== _listSig) { _listSig = sig; networks = out; }
    }

    // ── Actions ─────────────────────────────────────────────────────────
    function setWifiEnabled(on) {
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        wifiEnabled = on;
        refreshSoon();
    }

    function connectTo(ssid, password) {
        if (connecting) return;
        connecting = true;
        connectingSsid = ssid;
        lastError = "";
        errorSsid = "";
        const known = knownNames.indexOf(ssid) !== -1;
        _connectNeedsCleanup = !known;

        if (known)
            connectProc.command = ["nmcli", "-w", "25", "connection", "up", "id", ssid];
        else if (password && password !== "")
            connectProc.command = ["nmcli", "-w", "25", "device", "wifi", "connect", ssid, "password", password];
        else
            connectProc.command = ["nmcli", "-w", "25", "device", "wifi", "connect", ssid];
        connectProc.running = true;
    }

    function disconnectWifi() {
        if (wifiDevice === "") return;
        Quickshell.execDetached(["nmcli", "device", "disconnect", wifiDevice]);
        refreshSoon();
    }

    function forget(ssid) {
        Quickshell.execDetached(["nmcli", "connection", "delete", "id", ssid]);
        refreshSoon();
    }

    Process {
        id: connectProc
        stdout: StdioCollector { id: connOut }
        stderr: StdioCollector { id: connErr }
        onExited: (code, status) => { root._connectCode = code; connectDone.restart(); }
    }

    // Give the collectors a moment to flush before reading them.
    Timer { id: connectDone; interval: 200; onTriggered: root.finishConnect() }

    function finishConnect() {
        const ssid = connectingSsid;
        connecting = false;
        connectingSsid = "";

        if (_connectCode !== 0) {
            let msg = (connErr.text + "\n" + connOut.text).trim();
            if (/secrets were required|password|802-1x|authent/i.test(msg)) msg = "Wrong password or authentication failed";
            else if (/no network with ssid/i.test(msg)) msg = "Network not found";
            else if (/timeout|timed out/i.test(msg)) msg = "Connection timed out";
            else if (msg === "") msg = "Could not connect";
            lastError = msg;
            errorSsid = ssid;
            // nmcli saves a profile even when the password was wrong; drop it.
            if (_connectNeedsCleanup)
                Quickshell.execDetached(["nmcli", "connection", "delete", "id", ssid]);
        }
        refreshSoon();
    }
}
