// ─────────────────────────────────────────────────────────────────────────
// NcNetwork.qml — Ethernet + Wi-Fi via NetworkManager (nmcli)
//
//   • Ethernet connected → an Ethernet section (General / IPv4 / IPv6 details)
//   • Wi-Fi adapter present → a Wi-Fi section below it (scan / connect …)
//   • No ethernet → only the Wi-Fi section.  No adapters → empty state.
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
    property string activeRate: ""
    property string activeSecurity: ""
    property string wifiDevice: ""
    property string ethernetDevice: ""
    property bool   ethernetConnected: false
    readonly property bool wifiPresent: wifiDevice !== ""
    property var    networks: []        // [{ssid, signal, secure, security, rate, active, known, group}]
    property bool   pollActive: false   // set by the Network tab while visible
    property bool   freezeList: false   // set while a row is expanded

    property var ethMap: ({})           // parsed `nmcli device show` for the wired link
    property var wifiMap: ({})          // … for the Wi-Fi link
    property int linkSpeed: 0           // Mb/s, ethernet

    readonly property string firstIp: {
        const m = ethernetConnected ? ethMap : wifiMap;
        const a = m.ip4;
        return (a && a.length) ? a[0].split("/")[0] : "";
    }

    function speedText(n) {
        return n >= 1000 ? (n / 1000) + " Gb/s" : n + " Mb/s";
    }

    // Tile title / subtitle
    readonly property string statusText: {
        if (ethernetConnected) return "Ethernet";
        if (!wifiPresent) return "No network";
        if (!wifiEnabled) return "Wi-Fi off";
        if (activeSsid !== "") return activeSsid;
        return "Not connected";
    }
    readonly property string statusDetail: {
        const parts = [];
        if (ethernetConnected) {
            if (firstIp !== "") parts.push(firstIp);
            if (linkSpeed > 0) parts.push(speedText(linkSpeed));
        } else if (wifiPresent && wifiEnabled && activeSsid !== "") {
            parts.push(activeSignal + "%");
            if (firstIp !== "") parts.push(firstIp);
        } else if (wifiPresent) {
            parts.push(wifiEnabled ? "Wi-Fi" : "Turned off");
        }
        return parts.join(" · ");
    }

    // Detail rows, grouped like a connection-details dialog:
    //   [{header:"General"}, {label, value}, … , {header:"IPv4"}, …]
    readonly property var ethRows: ethernetConnected ? sections(ethMap, [
        ["Interface", "Ethernet (" + ethernetDevice + ")"],
        ["Hardware Address", ethMap.mac],
        ["Driver", ethMap.driver],
        ["Speed", linkSpeed > 0 ? linkSpeed + " Mb/s" : ""],
        ["Security", "None"]
    ]) : []

    readonly property var wifiRows: activeSsid !== "" ? sections(wifiMap, [
        ["Network", activeSsid],
        ["Interface", "Wi-Fi (" + wifiDevice + ")"],
        ["Hardware Address", wifiMap.mac],
        ["Driver", wifiMap.driver],
        ["Signal", activeSignal + "%"],
        ["Speed", activeRate],
        ["Security", activeSecurity !== "" ? activeSecurity : "None"]
    ]) : []

    // ── Internals ───────────────────────────────────────────────────────
    property var    _raw: []
    property var    knownNames: []
    property string _listSig: ""
    property int    _connectCode: 0
    property bool   _connectNeedsCleanup: false

    onFreezeListChanged: if (!freezeList) rebuildNetworks()
    onEthernetDeviceChanged: detailsTimer.restart()
    onWifiDeviceChanged: detailsTimer.restart()
    onActiveSsidChanged: detailsTimer.restart()
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

    // "192.168.0.20/24" → { ip, mask: "255.255.255.0", bcast: "192.168.0.255" }
    function ipv4Info(cidr) {
        const parts = cidr.split("/");
        const ip = parts[0];
        const p = parseInt(parts[1]);
        const o = ip.split(".").map(Number);
        if (o.length !== 4 || o.some(isNaN) || isNaN(p) || p < 0 || p > 32) return { ip: ip, mask: "", bcast: "" };
        const ipn = ((o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3]) >>> 0;
        const maskn = p === 0 ? 0 : ((0xFFFFFFFF << (32 - p)) >>> 0);
        const bn = (ipn | (~maskn >>> 0)) >>> 0;
        const dot = n => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join(".");
        return { ip: ip, mask: dot(maskn), bcast: dot(bn) };
    }

    function sections(m, general) {
        const rows = [];
        const group = function(title, pairs) {
            const items = pairs.filter(p => p[1] !== undefined && p[1] !== null && String(p[1]) !== "");
            if (items.length === 0) return;
            rows.push({ header: title });
            for (const p of items) rows.push({ label: p[0], value: String(p[1]) });
        };
        group("General", general);
        const v4 = (m.ip4 && m.ip4.length) ? ipv4Info(m.ip4[0]) : null;
        group("IPv4", v4 ? [
            ["IP Address", v4.ip],
            ["Broadcast Address", v4.bcast],
            ["Subnet Mask", v4.mask],
            ["Default Route", m.gateway],
            ["Primary DNS", (m.dns || [])[0]],
            ["Secondary DNS", (m.dns || [])[1]]
        ] : []);
        group("IPv6", [
            ["IP Address", (m.ip6 && m.ip6.length) ? m.ip6[0] : ""],
            ["Default Route", m.gateway6],
            ["Primary DNS", (m.dns6 || [])[0]]
        ]);
        return rows;
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
        if (!wifiEnabled || scanning || !wifiPresent) return;
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
        running: root.pollActive && root.wifiEnabled && root.wifiPresent
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
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,RATE", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector { onStreamFinished: root.parseList(this.text) }
    }

    Process { id: rescanProc; command: ["nmcli", "device", "wifi", "rescan"] }

    Process {
        id: ethProc
        stdout: StdioCollector { onStreamFinished: root.ethMap = root.parseDetails(this.text) }
    }
    Process {
        id: wifiProc
        stdout: StdioCollector { onStreamFinished: root.wifiMap = root.parseDetails(this.text) }
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
        // Whole sections (GENERAL, IP4, IP6) are always valid nmcli field groups.
        const fields = "GENERAL,IP4,IP6";
        if (ethernetConnected && ethernetDevice !== "") {
            ethProc.command = ["nmcli", "-t", "-f", fields, "device", "show", ethernetDevice];
            ethProc.running = true;
            speedProc.command = ["cat", "/sys/class/net/" + ethernetDevice + "/speed"];
            speedProc.running = true;
        } else {
            ethMap = ({});
            linkSpeed = 0;
        }
        if (activeSsid !== "" && wifiDevice !== "") {
            wifiProc.command = ["nmcli", "-t", "-f", fields, "device", "show", wifiDevice];
            wifiProc.running = true;
        } else {
            wifiMap = ({});
        }
    }

    function parseDetails(text) {
        const m = { device: "", mac: "", connection: "", driver: "", gateway: "", gateway6: "",
                    ip4: [], ip6: [], dns: [], dns6: [] };
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
            case "GENERAL.DRIVER":     m.driver = val; break;
            case "IP4.ADDRESS":        m.ip4.push(val); break;
            case "IP4.GATEWAY":        m.gateway = val; break;
            case "IP4.DNS":            m.dns.push(val); break;
            case "IP6.ADDRESS":        m.ip6.push(val); break;
            case "IP6.GATEWAY":        m.gateway6 = val; break;
            case "IP6.DNS":            m.dns6.push(val); break;
            }
        }
        // Prefer a routable IPv6 over link-local (fe80::)
        m.ip6.sort((a, b) => (a.toLowerCase().startsWith("fe80") ? 1 : 0) - (b.toLowerCase().startsWith("fe80") ? 1 : 0));
        return m;
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
                security: (f[3] !== "--") ? f[3] : "",
                rate: f.length > 4 ? f[4] : "",
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
            if (!b) best[e.ssid] = { ssid: e.ssid, signal: e.signal, secure: e.secure, security: e.security, rate: e.rate, active: e.active };
            else {
                if (e.signal > b.signal) { b.signal = e.signal; b.rate = e.rate; }
                if (e.active) b.active = true;
            }
        }
        const rank = { connected: 0, saved: 1, available: 2 };
        const out = [];
        let act = null;
        for (const k of Object.keys(best)) {
            const b = best[k];
            b.known = knownNames.indexOf(b.ssid) !== -1;
            b.group = b.active ? "connected" : (b.known ? "saved" : "available");
            if (b.active) act = b;
            out.push(b);
        }
        // Connected first, saved second, available last; strongest first within each.
        out.sort((a, b) => (rank[a.group] - rank[b.group]) || (b.signal - a.signal));
        activeSsid = act ? act.ssid : "";
        activeSignal = act ? act.signal : 0;
        activeRate = act ? act.rate : "";
        activeSecurity = act ? act.security : "";

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
