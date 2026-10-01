pragma Singleton
import QtQuick
import Quickshell

Item {
    id: root

    readonly property var primaryScreen: (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null
    readonly property real screenWidth: (primaryScreen && primaryScreen.width > 0) ? primaryScreen.width : 1920
    readonly property real screenHeight: (primaryScreen && primaryScreen.height > 0) ? primaryScreen.height : 1080

    // Reactive layout object parsed from Config.desktopLayout
    readonly property var currentLayout: parseLayout(Config.desktopLayout)

    function parseLayout(jsonStr) {
        if (!jsonStr || typeof jsonStr !== "string" || jsonStr.trim() === "") return {};
        try {
            let obj = JSON.parse(jsonStr);
            if (typeof obj === "object" && obj !== null) return obj;
        } catch(e) {
            console.warn("DesktopLayout: corrupted layout JSON, falling back to defaults:", e);
        }
        return {};
    }

    function hasStored(widgetId) {
        let l = currentLayout;
        return l && (widgetId in l) && l[widgetId] && 
               typeof l[widgetId].x === "number" && 
               typeof l[widgetId].y === "number" && 
               typeof l[widgetId].w === "number" && 
               typeof l[widgetId].h === "number";
    }

    function getMinSize(widgetId) {
        switch (widgetId) {
            case "mpris":
                return { width: 260, height: 120 };
            case "tray":
                return { width: 40, height: 40 };
            case "clock":
                return { width: 180, height: 90 };
            case "calendar":
                return { width: 240, height: 220 };
            default:
                return { width: 50, height: 50 };
        }
    }

    function getDefaultGeometry(widgetId, screenW, screenH, dynamicW, dynamicH) {
        let sw = (screenW && screenW > 0) ? screenW : root.screenWidth;
        let sh = (screenH && screenH > 0) ? screenH : root.screenHeight;

        switch (widgetId) {
            case "mpris": {
                let w = Math.min(sw, 400);
                let h = Math.min(sh, 170);
                return {
                    x: Math.max(0, Math.min(sw - w, sw - 430)),
                    y: Math.max(0, Math.min(sh - h, 30)),
                    w: w,
                    h: h,
                    visible: true,
                    transparentBg: false,
                    sendToBackground: false,
                    fontFamily: "",
                    isStored: false
                };
            }
            case "tray": {
                let w = Math.min(sw, (dynamicW && dynamicW > 0) ? dynamicW : 50);
                let h = Math.min(sh, 50);
                return {
                    x: Math.max(0, Math.min(sw - w, sw - 30 - w)),
                    y: Math.max(0, Math.min(sh - h, 210)),
                    w: w,
                    h: h,
                    visible: true,
                    transparentBg: false,
                    sendToBackground: false,
                    fontFamily: "",
                    isStored: false
                };
            }
            case "clock": {
                let w = Math.min(sw, 360);
                let h = Math.min(sh, (dynamicH && dynamicH > 0) ? dynamicH : 180);
                return {
                    x: Math.max(0, Math.min(sw - w, sw - 390)),
                    y: Math.max(0, Math.min(sh - h, sh - 380 - h)),
                    w: w,
                    h: h,
                    visible: true,
                    transparentBg: false,
                    sendToBackground: false,
                    hideDate: false,
                    fontFamily: "",
                    isStored: false
                };
            }
            case "calendar": {
                let w = Math.min(sw, 360);
                let h = Math.min(sh, 320);
                return {
                    x: Math.max(0, Math.min(sw - w, sw - 390)),
                    y: Math.max(0, Math.min(sh - h, sh - 350)),
                    w: w,
                    h: h,
                    visible: true,
                    transparentBg: false,
                    sendToBackground: false,
                    fontFamily: "",
                    isStored: false
                };
            }
            default:
                return { x: 0, y: 0, w: Math.min(sw, 100), h: Math.min(sh, 100), visible: true, transparentBg: false, sendToBackground: false, fontFamily: "", isStored: false };
        }
    }

    function getWidgetGeometry(widgetId, screenW, screenH, dynamicW, dynamicH) {
        let sw = (screenW && screenW > 0) ? screenW : root.screenWidth;
        let sh = (screenH && screenH > 0) ? screenH : root.screenHeight;

        if (hasStored(widgetId)) {
            let item = currentLayout[widgetId];
            let minSize = getMinSize(widgetId);
            let w = Math.round((item.w !== undefined ? item.w : 0.2) * sw);
            let h = Math.round((item.h !== undefined ? item.h : 0.15) * sh);
            w = Math.max(minSize.width, Math.min(sw, w));
            h = Math.max(minSize.height, Math.min(sh, h));
            let x = Math.round((item.x !== undefined ? item.x : 0) * sw);
            let y = Math.round((item.y !== undefined ? item.y : 0) * sh);
            x = Math.max(0, Math.min(sw - w, x));
            y = Math.max(0, Math.min(sh - h, y));

            return {
                x: x,
                y: y,
                w: w,
                h: h,
                visible: item.visible !== false,
                transparentBg: item.transparentBg === true,
                sendToBackground: item.sendToBackground === true,
                hideDate: item.hideDate === true,
                fontFamily: (typeof item.fontFamily === "string") ? item.fontFamily : "",
                isStored: true
            };
        }

        return getDefaultGeometry(widgetId, sw, sh, dynamicW, dynamicH);
    }

    // ─────────────────────────────────────────────────────────────
    // Tray sizing
    //
    // The tray's LENGTH is always derived from how many icons it holds.
    // The stored rectangle only supplies:
    //   - thickness (cross-axis size; the user's resize just changes this,
    //     and icons/spacing/padding all scale with it)
    //   - orientation
    //   - position, and which screen edge (if any) the tray is pinned to
    // ─────────────────────────────────────────────────────────────

    // A tray within this many px of a screen edge is treated as pinned to it
    readonly property real trayEdgeSnap: 12

    function trayIconSize(thickness) { return Math.max(16, Math.round(thickness * 0.48)); }
    function traySpacing(thickness)  { return Math.max(4,  Math.round(thickness * 0.24)); }
    function trayPadding(thickness)  { return Math.max(8,  Math.round(thickness * 0.30)); }

    function trayLength(count, thickness) {
        let n = Math.max(1, Math.round(count || 0));
        return n * trayIconSize(thickness) + (n - 1) * traySpacing(thickness) + 2 * trayPadding(thickness);
    }

    // Largest thickness (<= the requested one) whose length still fits maxLength
    function trayFitThickness(count, thickness, maxLength, minThickness) {
        let t = Math.round(thickness);
        while (t > minThickness && trayLength(count, t) > maxLength) t--;
        return t;
    }

    // item: stored tray entry (fractions of the screen: x, y, w, h, optional vertical) or null for defaults.
    // Returns pixel geometry { x, y, w, h, vertical, thickness } that is always fully on screen.
    function computeTrayRect(item, count, screenW, screenH) {
        let sw = (screenW && screenW > 0) ? screenW : root.screenWidth;
        let sh = (screenH && screenH > 0) ? screenH : root.screenHeight;
        let n = Math.max(1, Math.round(count || 0));
        let minT = getMinSize("tray").height;
        let snap = root.trayEdgeSnap;

        let vertical = false, thickness = 50;
        let px = 0, py = 0, pw = 0, ph = 0;
        if (item) {
            px = item.x * sw; py = item.y * sh; pw = item.w * sw; ph = item.h * sh;
            // Older saved layouts have no "vertical" flag: infer it from the saved shape
            vertical = (typeof item.vertical === "boolean") ? item.vertical : (ph > pw * 1.2);
            thickness = vertical ? pw : ph;
        }

        let S = vertical ? sh : sw;   // screen length along the tray's main axis
        let C = vertical ? sw : sh;   // screen length along the cross axis

        let t = Math.max(minT, Math.min(Math.round(thickness), C));
        t = trayFitThickness(n, t, S, 16);
        let len = trayLength(n, t);

        // Work out how the tray is anchored along its main axis
        let mode = "end", gapStart = 0, gapEnd = 30, center = 0, cross0 = 210;
        if (item) {
            let start0 = vertical ? py : px;
            let len0 = vertical ? ph : pw;
            cross0 = vertical ? px : py;
            if (start0 <= snap) {                       // touching the left/top edge
                mode = "start"; gapStart = start0;
            } else if (S - (start0 + len0) <= snap) {   // touching the right/bottom edge
                mode = "end"; gapEnd = S - (start0 + len0);
            } else {                                    // free floating: grow both ways
                mode = "center"; center = start0 + len0 / 2;
            }
        }

        let start;
        if (mode === "start")      start = gapStart;
        else if (mode === "end")   start = S - gapEnd - len;
        else                       start = center - len / 2;
        start = Math.round(Math.max(0, Math.min(S - len, start)));

        let cross = Math.round(Math.max(0, Math.min(C - t, cross0)));

        return {
            x: vertical ? cross : start,
            y: vertical ? start : cross,
            w: vertical ? t : len,
            h: vertical ? len : t,
            vertical: vertical,
            thickness: t
        };
    }

    function getTrayGeometry(count, screenW, screenH) {
        let sw = (screenW && screenW > 0) ? screenW : root.screenWidth;
        let sh = (screenH && screenH > 0) ? screenH : root.screenHeight;
        let item = hasStored("tray") ? currentLayout["tray"] : null;
        let r = computeTrayRect(item, count, sw, sh);
        return {
            x: r.x, y: r.y, w: r.w, h: r.h,
            vertical: r.vertical,
            visible: item ? item.visible !== false : true,
            transparentBg: item ? item.transparentBg === true : false,
            sendToBackground: item ? item.sendToBackground === true : false,
            fontFamily: (item && typeof item.fontFamily === "string") ? item.fontFamily : "",
            isStored: item !== null
        };
    }

    function getDefaultWorkingLayout(screenW, screenH, dynamicTrayW, dynamicClockH) {
        let sw = (screenW && screenW > 0) ? screenW : root.screenWidth;
        let sh = (screenH && screenH > 0) ? screenH : root.screenHeight;
        let trayW = (dynamicTrayW && dynamicTrayW > 0) ? dynamicTrayW : 120;
        let clockH = (dynamicClockH && dynamicClockH > 0) ? dynamicClockH : 180;

        return {
            "mpris": {
                x: (sw - 430) / sw,
                y: 30 / sh,
                w: 400 / sw,
                h: 170 / sh,
                visible: true,
                transparentBg: false,
                sendToBackground: false,
                fontFamily: ""
            },
            "tray": {
                x: (sw - 30 - trayW) / sw,
                y: 210 / sh,
                w: trayW / sw,
                h: 50 / sh,
                visible: true,
                transparentBg: false,
                sendToBackground: false,
                fontFamily: ""
            },
            "clock": {
                x: (sw - 390) / sw,
                y: (sh - 380 - clockH) / sh,
                w: 360 / sw,
                h: clockH / sh,
                visible: true,
                transparentBg: false,
                sendToBackground: false,
                hideDate: false,
                fontFamily: ""
            },
            "calendar": {
                x: (sw - 390) / sw,
                y: (sh - 350) / sh,
                w: 360 / sw,
                h: 320 / sh,
                visible: true,
                transparentBg: false,
                sendToBackground: false,
                fontFamily: ""
            }
        };
    }

    function saveLayout(layoutObj) {
        Config.desktopLayout = JSON.stringify(layoutObj);
    }
}
