// NotificationPopup.qml — popup stack
//
// Window sizing: the layer-shell surface is resized ONCE per add/remove event
// (to the sum of the popups' final heights), never per animation frame. The
// old version bound the window height to an animating ListView, which forced a
// compositor resize every frame — the main source of the visible jank.
// Input is restricted to the stack with `mask`, so empty space never eats clicks.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "osd"
    exclusiveZone: -1
    color: "transparent"
    anchors { top: true; left: true }

    margins.top: 20
    margins.left: 0

    property int maxVisible: 4      // older popups are retired (animated) beyond this
    property int contentH: 0
    property int nextUid: 1

    implicitWidth: 420
    implicitHeight: Math.max(1, contentH)
    visible: popupModel.count > 0
    mask: Region { item: stack }

    ListModel { id: popupModel }

    // ── Wiring to the manager ───────────────────────────────────────────
    Connections {
        target: NotificationManager
        function onIncomingNotification(notif)  { root.showPopup(notif) }
        function onNotificationUpdated(notif)   { root.updatePopup(notif) }
        function onNotificationRemoved(nid)     { root.retireByNid(nid) }
    }

    // ── Model helpers (always by uid / nid, never by a stale index) ─────
    function rowFrom(s) {
        return {
            uid: nextUid++,
            nid: s.nid,
            appName: s.appName,
            summary: s.summary,
            body: s.body,
            iconName: s.iconName,
            iconFileUrl: s.iconFileUrl,
            previewUrl: s.previewUrl,
            urgency: s.urgency,
            actionsJson: JSON.stringify(s.actions),
            timeoutMs: s.timeoutMs,
            rev: 0,
            leaving: false
        };
    }

    function indexOfUid(uid) {
        for (let i = 0; i < popupModel.count; i++)
            if (popupModel.get(i).uid === uid) return i;
        return -1;
    }

    function activeIndexOfNid(nid) {
        for (let i = 0; i < popupModel.count; i++) {
            const r = popupModel.get(i);
            if (r.nid === nid && !r.leaving) return i;
        }
        return -1;
    }

    function showPopup(s) {
        const i = activeIndexOfNid(s.nid);
        if (i >= 0) { updatePopup(s); return; }
        popupModel.append(rowFrom(s));
        enforceCap();
    }

    function updatePopup(s) {
        const i = activeIndexOfNid(s.nid);
        if (i < 0) { popupModel.append(rowFrom(s)); enforceCap(); return; }
        const r = rowFrom(s);
        const keys = ["appName", "summary", "body", "iconName", "iconFileUrl",
                      "previewUrl", "urgency", "actionsJson", "timeoutMs"];
        for (const k of keys) popupModel.setProperty(i, k, r[k]);
        popupModel.setProperty(i, "rev", popupModel.get(i).rev + 1);   // re-arms its timer
    }

    function markLeaving(uid) {
        const i = indexOfUid(uid);
        if (i >= 0 && !popupModel.get(i).leaving) popupModel.setProperty(i, "leaving", true);
    }

    function retireByNid(nid) {
        for (let i = 0; i < popupModel.count; i++)
            if (popupModel.get(i).nid === nid && !popupModel.get(i).leaving)
                popupModel.setProperty(i, "leaving", true);
    }

    function removeByUid(uid) {
        const i = indexOfUid(uid);
        if (i >= 0) popupModel.remove(i);
    }

    // Too many on screen → gracefully retire the oldest (never hard-delete).
    function enforceCap() {
        let active = 0;
        for (let i = 0; i < popupModel.count; i++) if (!popupModel.get(i).leaving) active++;
        let drop = active - maxVisible;
        for (let i = 0; i < popupModel.count && drop > 0; i++) {
            if (!popupModel.get(i).leaving) { popupModel.setProperty(i, "leaving", true); drop--; }
        }
    }

    // ── Window height: discrete, coalesced ──────────────────────────────
    Timer { id: relayoutTimer; interval: 0; onTriggered: root.relayout() }
    function scheduleRelayout() { relayoutTimer.restart() }
    function relayout() {
        let h = 0;
        for (let i = 0; i < rep.count; i++) {
            const it = rep.itemAt(i);
            if (it) h += it.fullHeight;
        }
        contentH = Math.ceil(h);
    }

    Column {
        id: stack
        x: 0
        y: 0
        width: 420

        Repeater {
            id: rep
            model: popupModel
            onItemAdded: root.scheduleRelayout()
            onItemRemoved: root.scheduleRelayout()

            delegate: NcPopupItem {
                width: stack.width
                onLeaveRequested: uid => root.markLeaving(uid)
                onFinished: uid => Qt.callLater(root.removeByUid, uid)
                onFullHeightChanged: root.scheduleRelayout()
            }
        }
    }
}
