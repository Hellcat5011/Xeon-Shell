pragma Singleton
// ─────────────────────────────────────────────────────────────────────────
// Theme.qml — a QML "singleton"
//
// `pragma Singleton` means: no matter how many files reference the name
// "Theme", they all get the *same* single instance.
//
// This file watches the JSON file matugen writes every time you change
// your wallpaper and copies each value into a plain `property color`. Any
// Rectangle, Text, etc. anywhere in this project that does
// `color: Theme.primary` will repaint the instant that file changes.
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Quickshell.shellDir resolves to the folder shell.qml lives in.
    readonly property string colorsPath: Quickshell.shellDir + "/data/colors.json"

    // Public handle so WallpaperSelector can call Theme.file.reload()
    // immediately after the wallpaper script exits (matugen uses atomic
    // renames, so inotify's IN_MODIFY never fires — explicit reload is
    // the reliable path for post-apply colour refresh).
    property Process colorReader: Process {
        id: colorReader
        command: ["cat", root.colorsPath]
        
        property string jsonContent: ""
        
        onRunningChanged: {
            if (running) {
                jsonContent = ""
            } else if (jsonContent.trim().length > 0) {
                try {
                    root._apply(JSON.parse(jsonContent))
                } catch (e) {
                    console.warn("Theme: could not parse colors.json —", e)
                }
            }
        }
        
        stdout: SplitParser {
            onRead: data => {
                colorReader.jsonContent += data + "\n"
            }
        }
    }

    // Force a re-read of colors.json. Used by the shell IPC handler when matugen finishes.
    function forceReload() {
        colorReader.running = true
    }

    Component.onCompleted: {
        forceReload()
    }

    function _apply(c) {
        background         = c.background          ?? background
        backgroundText     = c.on_background        ?? backgroundText
        surface            = c.surface              ?? surface
        surfaceVariant     = c.surface_variant      ?? surfaceVariant
        surfaceText        = c.on_surface           ?? surfaceText
        surfaceVariantText = c.on_surface_variant   ?? surfaceVariantText
        primary            = c.primary              ?? primary
        primaryText        = c.on_primary           ?? primaryText
        primaryContainer   = c.primary_container    ?? primaryContainer
        secondary          = c.secondary            ?? secondary
        secondaryContainer = c.secondary_container  ?? secondaryContainer
        outline            = c.outline              ?? outline
        outlineVariant     = c.outline_variant      ?? outlineVariant
        error              = c.error                ?? error
        shadow             = c.shadow               ?? shadow
        inversePrimary     = c.inverse_primary      ?? inversePrimary
        onPrimaryContainerColor = c.on_primary_container ?? onPrimaryContainerColor
    }

    // ---- Palette (Material You / matugen naming) -------------------------
    // Fallback values set to bright MAGENTA to identify if matugen failed.
    property color background:         "#ff00ff"
    property color backgroundText:     "#ff00ff"
    property color surface:            "#ff00ff"
    property color surfaceVariant:     "#ff00ff"
    property color surfaceText:        "#ff00ff"
    property color surfaceVariantText: "#ff00ff"
    property color primary:            "#ff00ff"
    property color primaryText:        "#ff00ff"
    property color primaryContainer:   "#ff00ff"
    property color secondary:          "#ff00ff"
    property color secondaryContainer: "#ff00ff"
    property color outline:            "#ff00ff"
    property color outlineVariant:     "#ff00ff"
    property color error:              "#ff00ff"
    property color shadow:             "#ff00ff"
    property color inversePrimary:     "#ff00ff"
    property color onPrimaryContainerColor: "#ff00ff"



    // ---- Shared motion / shape tokens -----------------------------------
    readonly property int animFast:   53
    readonly property int animMed:    98
    readonly property int animSlow:   169
    readonly property int easeOut:    Easing.OutCubic
    readonly property int radiusSmall: 12
    readonly property int radiusLarge: 24

    // ---- Font tokens & resolution ---------------------------------------
    readonly property var availableFonts: {
        let raw = Qt.fontFamilies();
        let list = ["System Default"];
        let seen = { "System Default": true };
        for (let i = 0; i < raw.length; i++) {
            let f = raw[i];
            if (!f || f.startsWith(".") || f.startsWith("@") || f.includes("Emoji") || f.includes("Math")) continue;
            if (!seen[f]) {
                seen[f] = true;
                list.push(f);
            }
        }
        return list;
    }

    readonly property var widgetFontOptions: {
        let list = ["Default (Global)"];
        return list.concat(availableFonts);
    }

    function resolveFont(fontName) {
        if (!fontName || fontName === "System Default" || fontName === "Default") {
            return "";
        }
        return fontName;
    }

    readonly property string globalFont: resolveFont(Config.globalFont)

    function widgetFont(customFont) {
        if (customFont && customFont !== "" && customFont !== "Default (Global)" && customFont !== "Inherit" && customFont !== "Default") {
            if (customFont === "System Default") return "";
            return customFont;
        }
        return globalFont;
    }
}
