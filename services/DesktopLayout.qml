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
            case "mpris":
                return {
                    x: sw - 430,
                    y: 30,
                    w: 400,
                    h: 170,
                    visible: true,
                    transparentBg: false,
                    isStored: false
                };
            case "tray": {
                let w = (dynamicW && dynamicW > 0) ? dynamicW : 50;
                return {
                    x: sw - 30 - w,
                    y: 210,
                    w: w,
                    h: 50,
                    visible: true,
                    transparentBg: false,
                    isStored: false
                };
            }
            case "clock": {
                let h = (dynamicH && dynamicH > 0) ? dynamicH : 180;
                return {
                    x: sw - 390,
                    y: sh - 380 - h,
                    w: 360,
                    h: h,
                    visible: true,
                    transparentBg: false,
                    isStored: false
                };
            }
            case "calendar":
                return {
                    x: sw - 390,
                    y: sh - 350,
                    w: 360,
                    h: 320,
                    visible: true,
                    transparentBg: false,
                    isStored: false
                };
            default:
                return { x: 0, y: 0, w: 100, h: 100, visible: true, transparentBg: false, isStored: false };
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
                isStored: true
            };
        }

        return getDefaultGeometry(widgetId, sw, sh, dynamicW, dynamicH);
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
                transparentBg: false
            },
            "tray": {
                x: (sw - 30 - trayW) / sw,
                y: 210 / sh,
                w: trayW / sw,
                h: 50 / sh,
                visible: true,
                transparentBg: false
            },
            "clock": {
                x: (sw - 390) / sw,
                y: (sh - 380 - clockH) / sh,
                w: 360 / sw,
                h: clockH / sh,
                visible: true,
                transparentBg: false
            },
            "calendar": {
                x: (sw - 390) / sw,
                y: (sh - 350) / sh,
                w: 360 / sw,
                h: 320 / sh,
                visible: true,
                transparentBg: false
            }
        };
    }

    function saveLayout(layoutObj) {
        Config.desktopLayout = JSON.stringify(layoutObj);
    }
}
