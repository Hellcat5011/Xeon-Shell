// ─────────────────────────────────────────────────────────────────────────
// NotificationManager.qml — notification server + history + grouping
//
// Everything the UI consumes is a PLAIN JS snapshot (not a live QObject), so
// delegates can keep rendering a notification while it animates out even after
// the underlying Notification object has been destroyed.
//
// Public API (names kept compatible with the previous manager where known):
//   signals   incomingNotification(notif) / notificationUpdated(notif) /
//             notificationRemoved(nid)
//   props     silent, notifications, count, groupModel, groupsMap,
//             expandedGroup, clock
//   methods   clearAll(), clearGroup(key), dismiss(nid), invoke(nid, id),
//             toggleGroup(key), toggleSilent(), copyText(nid), timeLabel(ms)
//
// Snapshot fields:
//   nid key appName summary body(markup) bodyPlain iconName iconFileUrl
//   previewUrl urgency actions[{identifier,text}] resident stamp version
//   timeoutMs
// ─────────────────────────────────────────────────────────────────────────
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // ── Public state ────────────────────────────────────────────────────
    property bool silent: false                 // suppress popups (history still kept)
    property bool silentAllowsCritical: true    // critical popups bypass "silent"

    property var  notifications: []             // newest first
    readonly property int count: notifications.length
    property var  groupsMap: ({})               // key -> snapshot[] (newest first)
    property string expandedGroup: ""           // accordion: one open group at a time
    property real clock: Date.now()             // ticks so relative times refresh
    readonly property ListModel groupModel: _groupModel

    signal incomingNotification(var notif)
    signal notificationUpdated(var notif)
    signal notificationRemoved(int nid)

    // ── Internals ───────────────────────────────────────────────────────
    property bool _ready: false
    property bool _batching: false
    property var  _snaps: ({})
    property var  _sources: ({})
    property var  _touched: ({})
    property var  _sigs: ({})
    property var  _groupArrays: ({})
    property var  _entryCache: ({})

    ListModel { id: _groupModel }

    Timer {
        interval: 30000; running: true; repeat: true
        onTriggered: root.clock = Date.now()
    }

    Timer {
        id: rebuildTimer
        interval: 0
        onTriggered: root.rebuild()
    }

    // Coalesces summary+body+image changes of a replaced notification.
    Timer {
        id: touchTimer
        interval: 40
        onTriggered: root.rebuild()
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: false
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        imageSupported: true
        persistenceSupported: true

        onNotification: n => { n.tracked = true }
    }

    // One watcher per tracked notification: detects in-place replacements
    // (replaces_id) and keeps add/remove in sync with the server.
    Instantiator {
        model: server.trackedNotifications
        delegate: Connections {
            required property var modelData
            target: modelData
            function onSummaryChanged()  { root.touch(modelData.id) }
            function onBodyChanged()     { root.touch(modelData.id) }
            function onImageChanged()    { root.touch(modelData.id) }
            function onAppIconChanged()  { root.touch(modelData.id) }
            function onActionsChanged()  { root.touch(modelData.id) }
        }
        onObjectAdded: rebuildTimer.restart()
        onObjectRemoved: rebuildTimer.restart()
    }

    Component.onCompleted: {
        rebuild();       // restores notifications kept across a reload (no popups)
        _ready = true;
    }

    function touch(nid) {
        _touched[nid] = true;
        touchTimer.restart();
    }

    // ── Helpers ─────────────────────────────────────────────────────────
    function isFileLike(p) {
        return p.startsWith("/") || p.startsWith("file://") || p.startsWith("~/");
    }

    function toUrl(p) {
        if (!p) return "";
        if (p.startsWith("image://") || p.startsWith("file://")) return p;
        if (p.startsWith("~/")) p = Quickshell.env("HOME") + p.slice(1);
        if (p.startsWith("/")) return "file://" + p.split("/").map(encodeURIComponent).join("/");
        return "";
    }

    function stripMarkup(s) {
        return s.replace(/<br\s*\/?>/gi, " ")
                .replace(/<[^>]*>/g, "")
                .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
                .replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'")
                .replace(/&amp;/g, "&")
                .replace(/\s+/g, " ").trim();
    }

    // StyledText-safe body: no <img>, newlines become <br/>.
    function cleanBody(s) {
        return s.replace(/<img[^>]*>/gi, "").replace(/\r?\n/g, "<br/>");
    }

    function lookupEntry(desktopEntry, appName) {
        const name = desktopEntry || appName || "";
        if (name === "") return null;
        const k = name.toLowerCase();
        if (_entryCache[k] !== undefined) return _entryCache[k];
        let e = null;
        try { e = DesktopEntries.heuristicLookup(name) || null; } catch (err) { e = null; }
        _entryCache[k] = e;
        return e;
    }

    function makeSnap(n, stamp, version) {
        const appName = n.appName || "";
        const entry = lookupEntry(n.desktopEntry, appName);

        // Icon: themed name, or a file path / file:// URL
        const rawIcon = n.appIcon || "";
        let iconName = "";
        let iconFileUrl = "";
        if (rawIcon !== "") {
            if (isFileLike(rawIcon)) iconFileUrl = toUrl(rawIcon);
            else iconName = rawIcon;
        }
        if (iconName === "" && iconFileUrl === "" && entry && entry.icon) {
            if (isFileLike(entry.icon)) iconFileUrl = toUrl(entry.icon);
            else iconName = entry.icon;
        }
        if (iconName === "" && iconFileUrl === "") iconName = "dialog-information";

        // Preview image (image-data / image-path hints). Screenshots arrive here.
        const previewUrl = n.image ? (n.image.startsWith("image://") ? n.image : toUrl(n.image)) : "";

        // Actions supplied by the app. "default" has no label → show it as "Open".
        const actions = [];
        const acts = n.actions;
        for (let i = 0; i < acts.length; i++) {
            const a = acts[i];
            let text = a.text || "";
            if (a.identifier === "default" && (text === "" || text.toLowerCase() === "default")) text = "Open";
            if (text === "") continue;
            actions.push({ identifier: a.identifier, text: text });
        }
        // App supplied nothing → offer to open the app itself if we can resolve it.
        if (actions.length === 0 && entry)
            actions.push({ identifier: "__open__", text: "Open" });

        const body = n.body || "";
        let ms = n.expireTimeout > 0 ? n.expireTimeout : 0;
        if (ms > 0 && ms <= 100) ms = ms * 1000;          // tolerate seconds or ms
        ms = ms > 0 ? Math.min(Math.max(ms, 3000), 20000) : 5000;

        return {
            nid: n.id,
            key: (appName || "unknown").toLowerCase(),
            entryKey: (n.desktopEntry || appName || "").toLowerCase(),
            appName: appName,
            summary: n.summary || "",
            body: cleanBody(body),
            bodyPlain: stripMarkup(body),
            iconName: iconName,
            iconFileUrl: iconFileUrl,
            previewUrl: previewUrl,
            urgency: n.urgency,
            actions: actions,
            resident: n.resident === true,
            stamp: stamp,
            version: version,
            timeoutMs: ms
        };
    }

    function shouldPopup(s) {
        if (!silent) return true;
        return silentAllowsCritical && s.urgency === NotificationUrgency.Critical;
    }

    // ── Core: rebuild snapshots / groups from the server's tracked list ──
    function rebuild() {
        if (_batching) return;

        const live = Array.from(server.trackedNotifications.values);
        const oldSnaps = _snaps;
        const newSnaps = {};
        const sources = {};
        const list = [];
        const incoming = [];
        const updated = [];
        const now = Date.now();

        for (let i = 0; i < live.length; i++) {
            const n = live[i];
            const nid = n.id;
            sources[nid] = n;
            const prev = oldSnaps[nid];
            const touched = _touched[nid] === true;

            let snap;
            if (prev && !touched) {
                snap = prev;
            } else {
                snap = makeSnap(n, (touched || !prev) ? now : prev.stamp, prev ? prev.version + (touched ? 1 : 0) : 0);
                if (!prev) { if (_ready) incoming.push(snap); }
                else updated.push(snap);
            }
            newSnaps[nid] = snap;
            list.push(snap);
        }

        const removed = [];
        for (const k of Object.keys(oldSnaps))
            if (newSnaps[k] === undefined) removed.push(parseInt(k));

        list.sort((a, b) => (b.stamp - a.stamp) || (b.nid - a.nid));

        // Group by app, preserving array identity when nothing changed so
        // delegates are not needlessly rebuilt.
        const gmap = {};
        const order = [];
        for (const s of list) {
            if (!gmap[s.key]) { gmap[s.key] = []; order.push(s.key); }
            gmap[s.key].push(s);
        }
        const nextSigs = {};
        const nextArrays = {};
        for (const key of order) {
            const sig = gmap[key].map(s => s.nid + "." + s.version).join(",");
            nextSigs[key] = sig;
            if (_sigs[key] === sig && _groupArrays[key]) gmap[key] = _groupArrays[key];
            nextArrays[key] = gmap[key];
        }
        _sigs = nextSigs;
        _groupArrays = nextArrays;

        _snaps = newSnaps;
        _sources = sources;
        _touched = ({});
        notifications = list;
        groupsMap = gmap;
        syncGroupModel(order);
        if (expandedGroup !== "" && gmap[expandedGroup] === undefined) expandedGroup = "";

        for (const s of incoming) if (shouldPopup(s)) incomingNotification(s);
        for (const s of updated)  if (shouldPopup(s)) notificationUpdated(s);
        for (const id of removed) notificationRemoved(id);
    }

    function syncGroupModel(order) {
        for (let i = _groupModel.count - 1; i >= 0; i--)
            if (order.indexOf(_groupModel.get(i).key) === -1) _groupModel.remove(i);

        for (let i = 0; i < order.length; i++) {
            const key = order[i];
            if (i < _groupModel.count && _groupModel.get(i).key === key) continue;
            let found = -1;
            for (let j = i + 1; j < _groupModel.count; j++)
                if (_groupModel.get(j).key === key) { found = j; break; }
            if (found >= 0) _groupModel.move(found, i, 1);
            else _groupModel.insert(i, { key: key });
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────
    function dismiss(nid) {
        const n = _sources[nid];
        if (!n) return;
        try { n.dismiss(); } catch (e) {}
    }

    function invoke(nid, identifier) {
        if (identifier === "__open__") {
            const s = _snaps[nid];
            const e = s ? _entryCache[s.entryKey] : null;
            if (e) e.execute();
            dismiss(nid);
            return;
        }
        const n = _sources[nid];
        if (!n) return;
        let resident = false;
        try {
            resident = n.resident === true;
            const acts = n.actions;
            for (let i = 0; i < acts.length; i++) {
                if (acts[i].identifier === identifier) { acts[i].invoke(); break; }
            }
        } catch (e) {}
        if (!resident) dismiss(nid);
    }

    function clearAll() {
        _batching = true;
        const live = Array.from(server.trackedNotifications.values);
        for (const n of live) { try { n.dismiss(); } catch (e) {} }
        _batching = false;
        rebuild();
    }

    function clearGroup(key) {
        const items = groupsMap[key];
        if (!items) return;
        _batching = true;
        for (const s of items) dismiss(s.nid);
        _batching = false;
        rebuild();
    }

    function toggleGroup(key) { expandedGroup = expandedGroup === key ? "" : key; }
    function toggleSilent()   { silent = !silent; }

    function copyText(nid) {
        const s = _snaps[nid];
        if (!s) return;
        Quickshell.execDetached(["wl-copy", s.bodyPlain !== "" ? s.bodyPlain : s.summary]);
    }

    // `tick` is unused; passing NotificationManager.clock re-evaluates callers' bindings.
    function timeLabel(stamp, tick) {
        if (!stamp) return "";
        const now = new Date();
        const d = new Date(stamp);
        const diff = (now.getTime() - stamp) / 1000;
        if (diff < 60) return "Now";
        if (diff < 3600) return Math.floor(diff / 60) + "m";
        if (d.toDateString() === now.toDateString()) return Math.floor(diff / 3600) + "h";
        const y = new Date(now); y.setDate(now.getDate() - 1);
        if (d.toDateString() === y.toDateString()) return "Yesterday";
        if (diff < 7 * 86400) return Qt.formatDateTime(d, "ddd");
        return Qt.formatDateTime(d, "d MMM");
    }
}
