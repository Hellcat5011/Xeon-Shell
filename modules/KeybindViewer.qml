// ─────────────────────────────────────────────────────────────────────────
// KeybindViewer.qml — read-only overlay that displays Hyprland keybinds
//
// Reads ~/.config/hypr/user/keybinds.lua and parses every active
// hl.bind() line into a grid of  Key → Action  rows, grouped by the
// comment-section headers found in the file.
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"

OverlayWindow {
    id: keybindViewer
    WlrLayershell.namespace: "keybinds"

    panelWidth:  width > 0 ? Math.min(width * 0.82, 1400) : 1200
    panelHeight: height > 0 ? height * 0.78 : 700

    // ── File reader ──────────────────────────────────────────────────────
    property string rawContent: ""

    Process {
        id: reader
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/user/keybinds.lua"]
        property string buf: ""
        onRunningChanged: {
            if (running) buf = ""
            else {
                keybindViewer.rawContent = buf
                keybindViewer._parse()
            }
        }
        stdout: SplitParser { onRead: data => reader.buf += data + "\n" }
    }

    onShownChanged: {
        if (shown) {
            reader.running = true
            keyHandler.forceActiveFocus()
        }
    }

    // ── Parsed model ─────────────────────────────────────────────────────
    // Each element: { section: "...", key: "...", action: "..." }
    // Section headers become dividers in the grid.
    property var binds: []
    property var leftBinds: []
    property var rightBinds: []

    function _parse() {
        let lines = rawContent.split("\n")
        let result = []
        let section = "General"
        let inForLoop = false

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim()

            // Skip empty / commented-out binds
            if (line === "" || line.startsWith("--")) {
                // But capture section headers from comments
                let headerMatch = line.match(/^--\s+(.+)/)
                if (headerMatch) {
                    let h = headerMatch[1].trim()
                    // Only use lines that look like headers (all-caps or title-case,
                    // and not things like "closeWindowBind:set_enabled(false)")
                    if (h.length > 2 && !h.includes("hl.") && !h.includes("=")) {
                        section = h.replace(/^-+\s*/, "").replace(/\s*-+$/, "").trim()
                    }
                }
                continue
            }

            // Detect for-loop workspace binds and synthesize them
            if (line.startsWith("for ") && line.includes("1, 10")) {
                inForLoop = true
                continue
            }
            if (inForLoop) {
                if (line === "end") {
                    inForLoop = false
                    continue
                }
                // Synthesize workspace 1-10 binds from the loop body
                if (line.includes("hl.bind(") && !line.startsWith("--")) {
                    for (let ws = 1; ws <= 10; ws++) {
                        let displayKey = ws % 10  // 10 → 0
                        if (line.includes("focus")) {
                            result.push({ section: section, key: "SUPER + " + displayKey, action: "Go to Workspace " + ws })
                        } else if (line.includes("window.move")) {
                            result.push({ section: section, key: "SUPER + SHIFT + " + displayKey, action: "Move to Workspace " + ws })
                        }
                    }
                }
                continue
            }

            // Skip non-bind lines (local declarations, etc.)
            if (!line.includes("hl.bind(")) continue

            // Strip "local ... = " prefix if present (e.g. "local closeWindowBind = hl.bind(...)")
            let bindPart = line.replace(/^.*?hl\.bind\(/, "hl.bind(")

            // Extract the key string and action from hl.bind(...)
            // Pattern 1: mainMod .. " + KEY", action  [, {opts}])
            // Pattern 2: "STANDALONE_KEY", action  [, {opts}])
            let keyCombo = ""
            let rawAction = ""

            let mainModMatch = bindPart.match(/^hl\.bind\(\s*mainMod\s*\.\.\s*"\s*\+\s*([^"]+)"\s*,\s*(.+)$/)
            if (mainModMatch) {
                keyCombo = "SUPER + " + mainModMatch[1].trim()
                rawAction = mainModMatch[2]
            } else {
                let plainMatch = bindPart.match(/^hl\.bind\(\s*"([^"]+)"\s*,\s*(.+)$/)
                if (plainMatch) {
                    keyCombo = plainMatch[1].trim()
                    rawAction = plainMatch[2]
                }
            }

            if (!keyCombo || !rawAction) continue

            // Strip trailing options table and closing paren:
            //   hl.dsp.exec_cmd("foo"), { locked = true, repeating = true })
            //   hl.dsp.exec_cmd("foo"))
            // We need to remove the outermost closing ) and any trailing , { ... }
            rawAction = rawAction.replace(/,\s*\{[^}]*\}\s*\)\s*$/, ")")  // strip opts + final )
            rawAction = rawAction.replace(/\)\s*$/, "")                    // strip final trailing )

            let action = _humanise(rawAction.trim())
            result.push({ section: section, key: keyCombo, action: action })
        }

        binds = result
        _splitColumns()
    }

    function _splitColumns() {
        // Split binds into two columns, trying to break at a section boundary
        // near the midpoint so sections don't get split across columns.
        let mid = Math.ceil(binds.length / 2)

        // Search for a section boundary near mid (prefer keeping sections intact)
        let bestSplit = mid
        for (let offset = 0; offset < Math.min(8, mid); offset++) {
            let idx = mid + offset
            if (idx < binds.length && idx > 0 && binds[idx].section !== binds[idx - 1].section) {
                bestSplit = idx
                break
            }
            idx = mid - offset
            if (idx > 0 && idx < binds.length && binds[idx].section !== binds[idx - 1].section) {
                bestSplit = idx
                break
            }
        }

        leftBinds  = binds.slice(0, bestSplit)
        rightBinds = binds.slice(bestSplit)
    }

    function _humanise(raw) {
        // hl.dsp.exec_cmd(qs_launch .. "notif toggle") → friendly name
        // Handles variable concatenation patterns like: qs_launch .. "command arg"
        let qsMatch = raw.match(/hl\.dsp\.exec_cmd\(\s*qs_launch\s*\.\.\s*"([^"]+)"\s*\)/)
        if (qsMatch) {
            let qsCmd = qsMatch[1].trim()
            return _qsLaunchName(qsCmd)
        }

        // hl.dsp.exec_cmd("some command") → "some command"
        let execMatch = raw.match(/hl\.dsp\.exec_cmd\(\s*"([^"]+)"\s*\)/)
        if (execMatch) {
            let cmd = execMatch[1]
            // Simplify well-known commands
            if (cmd.includes("ipc call")) {
                let parts = cmd.match(/ipc call (\w+) (\w+)/)
                if (parts) return parts[1].charAt(0).toUpperCase() + parts[1].slice(1) + " → " + parts[2]
            }
            if (cmd.includes("volume.sh"))      return "Volume " + (cmd.includes("+") ? "Up" : cmd.includes("-") ? "Down" : "Mute")
            if (cmd.includes("brightness.sh"))   return "Brightness " + (cmd.includes("+") ? "Up" : "Down")
            if (cmd.includes("playerctl"))       return "Media " + cmd.split("playerctl ")[1]
            if (cmd.includes("brightnessctl"))   return "Brightness " + (cmd.includes("set 5%+") ? "Up" : "Down")
            if (cmd.includes("hyprpicker"))      return "Color Picker"
            if (cmd.includes("hyprlock"))        return "Lock Screen"
            if (cmd.includes("blueman"))         return "Bluetooth Manager"
            if (cmd.includes("pavucontrol"))     return "Audio Settings"
            return cmd
        }

        // hl.dsp.focus({direction="left"}) → Focus Left
        let focusMatch = raw.match(/hl\.dsp\.focus\(\{.*direction\s*=\s*"(\w+)"/)
        if (focusMatch) return "Focus " + focusMatch[1].charAt(0).toUpperCase() + focusMatch[1].slice(1)

        // hl.dsp.focus({workspace = N}) → Go to Workspace N
        let wsFocus = raw.match(/hl\.dsp\.focus\(\{.*workspace\s*=\s*(\S+)/)
        if (wsFocus) return "Go to Workspace " + wsFocus[1].replace(/[}"]/g, "")

        // hl.dsp.window.move({workspace = N}) → Move to Workspace N
        let wsMove = raw.match(/hl\.dsp\.window\.move\(\{.*workspace\s*=\s*(\S+)/)
        if (wsMove) {
            let ws = wsMove[1].replace(/[}"]/g, "")
            return ws.includes("special") ? "Move to Scratchpad" : "Move to Workspace " + ws
        }

        // hl.dsp.window.swap({direction="left"}) → Swap Left
        let swapMatch = raw.match(/hl\.dsp\.window\.swap\(\{.*direction\s*=\s*"(\w+)"/)
        if (swapMatch) return "Swap " + swapMatch[1].charAt(0).toUpperCase() + swapMatch[1].slice(1)

        // hl.dsp.window.close() → Close Window
        if (raw.includes("window.close"))      return "Close Window"
        if (raw.includes("window.float"))      return "Toggle Floating"
        if (raw.includes("window.fullscreen")) {
            if (raw.includes("maximized"))     return "Toggle Maximized"
            return "Toggle Fullscreen"
        }
        if (raw.includes("window.pseudo"))     return "Toggle Pseudo-tile"
        if (raw.includes("window.drag"))       return "Drag Window"
        if (raw.includes("window.resize"))     return "Resize Window"

        if (raw.includes("workspace.toggle_special")) return "Toggle Scratchpad"
        if (raw.includes("layout("))           return "Toggle Layout"
        if (raw.includes("dsp.exit"))          return "Exit Hyprland"
        if (raw.includes("exec_cmd(terminal)"))  return "Open Terminal"
        if (raw.includes("exec_cmd(fileManager)")) return "Open File Manager"
        if (raw.includes("exec_cmd(browser)")) return "Open Browser"
        if (raw.includes("exec_cmd(menu)"))    return "Open App Menu"

        // Fallback: strip hl.dsp. prefix
        return raw.replace(/hl\.dsp\./, "").replace(/[(){}]/g, " ").trim()
    }

    // Map qs_launch IPC commands to friendly display names
    function _qsLaunchName(cmd) {
        let map = {
            "notif toggle":       "Notification Center",
            "wallpaper toggle":   "Wallpaper Picker",
            "launcher toggle":    "App Launcher",
            "power toggle":       "Power Menu",
            "clipboard toggle":   "Clipboard History",
            "screenshot region":  "Screenshot Region",
            "screenshot window":  "Screenshot Window",
            "screenshot output":  "Screenshot Output",
            "keybinds toggle":    "Keybind Viewer",
        }
        if (map[cmd]) return map[cmd]

        // Fallback: capitalize the command
        return cmd.split(" ").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
    }

    // ── Visual ───────────────────────────────────────────────────────────
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                keybindViewer.hide()
                event.accepted = true
            }
        }

        // Header
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 0

            // ── Title row ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 16

                Text {
                    text: "⌨  Keybindings"
                    color: Theme.onPrimaryContainerColor
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "ESC to close"
                    color: Qt.rgba(Theme.onPrimaryContainerColor.r,
                                   Theme.onPrimaryContainerColor.g,
                                   Theme.onPrimaryContainerColor.b, 0.45)
                    font.pixelSize: 13
                }
            }

            // Thin separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.5)
                Layout.bottomMargin: 12
            }

            // ── Scrollable two-column grid ─────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Subtle background behind the list area
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    color: Qt.rgba(Theme.surfaceVariant.r,
                                   Theme.surfaceVariant.g,
                                   Theme.surfaceVariant.b, 0.15)
                }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.rightMargin: 10   // leave room for scrollbar
                    contentHeight: twoColRow.implicitHeight + 24
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    // ── Two columns side by side ─────────────────────
                    Row {
                        id: twoColRow
                        width: flick.width
                        spacing: 0
                        y: 12  // top padding

                        // ── Left column ──────────────────────────────
                        ColumnLayout {
                            width: (twoColRow.width - divider.width - 24) / 2
                            spacing: 4

                            Repeater {
                                model: keybindViewer.leftBinds.length

                                delegate: ColumnLayout {
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        visible: index === 0 || keybindViewer.leftBinds[index].section !== keybindViewer.leftBinds[index - 1].section
                                        Layout.fillWidth: true
                                        Layout.topMargin: index > 0 ? 16 : 4
                                        Layout.bottomMargin: 6
                                        Layout.leftMargin: 8
                                        text: keybindViewer.leftBinds[index] ? keybindViewer.leftBinds[index].section : ""
                                        color: Theme.primary
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.8
                                    }

                                    KeybindRow {
                                        bindSource: keybindViewer.leftBinds
                                        bindIndex: index
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }

                        // ── Vertical divider ─────────────────────────
                        Rectangle {
                            id: divider
                            width: 1
                            height: Math.max(
                                twoColRow.children[0].implicitHeight,
                                twoColRow.children[2] ? twoColRow.children[2].implicitHeight : 0
                            )
                            anchors.margins: 12
                            color: Qt.rgba(Theme.outlineVariant.r,
                                           Theme.outlineVariant.g,
                                           Theme.outlineVariant.b, 0.35)
                        }

                        // Spacer for divider margins
                        Item { width: 24; height: 1 }

                        // ── Right column ─────────────────────────────
                        ColumnLayout {
                            width: (twoColRow.width - divider.width - 24) / 2
                            spacing: 4

                            Repeater {
                                model: keybindViewer.rightBinds.length

                                delegate: ColumnLayout {
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        visible: index === 0 || keybindViewer.rightBinds[index].section !== keybindViewer.rightBinds[index - 1].section
                                        Layout.fillWidth: true
                                        Layout.topMargin: index > 0 ? 16 : 4
                                        Layout.bottomMargin: 6
                                        Layout.leftMargin: 8
                                        text: keybindViewer.rightBinds[index] ? keybindViewer.rightBinds[index].section : ""
                                        color: Theme.primary
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.8
                                    }

                                    KeybindRow {
                                        bindSource: keybindViewer.rightBinds
                                        bindIndex: index
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Scrollbar ────────────────────────────────────────
                Rectangle {
                    id: scrollTrack
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: 4
                    radius: 2
                    color: Qt.rgba(Theme.outlineVariant.r,
                                   Theme.outlineVariant.g,
                                   Theme.outlineVariant.b, 0.15)
                    visible: flick.contentHeight > flick.height

                    Rectangle {
                        id: scrollThumb
                        width: parent.width
                        radius: 2
                        color: Qt.rgba(Theme.primary.r,
                                       Theme.primary.g,
                                       Theme.primary.b,
                                       thumbMouse.containsMouse || thumbMouse.pressed ? 0.7 : 0.35)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        // Thumb size proportional to visible fraction
                        property real ratio: flick.height / flick.contentHeight
                        height: Math.max(30, scrollTrack.height * ratio)

                        // Thumb position tracks flick position
                        y: flick.contentHeight > flick.height
                           ? (flick.contentY / (flick.contentHeight - flick.height))
                             * (scrollTrack.height - height)
                           : 0

                        MouseArea {
                            id: thumbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            drag.target: parent
                            drag.axis: Drag.YAxis
                            drag.minimumY: 0
                            drag.maximumY: scrollTrack.height - scrollThumb.height

                            onPositionChanged: {
                                if (pressed) {
                                    let fraction = scrollThumb.y / (scrollTrack.height - scrollThumb.height)
                                    flick.contentY = fraction * (flick.contentHeight - flick.height)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Keybind row component ────────────────────────────────────────────
    component KeybindRow: Rectangle {
        property var bindSource: []
        property int bindIndex: 0

        implicitHeight: 38
        radius: Theme.radiusSmall
        color: rowMouse.containsMouse
               ? Qt.rgba(Theme.onPrimaryContainerColor.r,
                         Theme.onPrimaryContainerColor.g,
                         Theme.onPrimaryContainerColor.b, 0.08)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 16

            // Key badges
            Row {
                spacing: 6
                Layout.preferredWidth: parent.width * 0.42
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter

                Repeater {
                    model: bindSource[bindIndex]
                           ? bindSource[bindIndex].key.split(/\s*\+\s*/)
                           : []

                    delegate: Rectangle {
                        required property string modelData

                        width: keyLabel.implicitWidth + 18
                        height: 26
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 6
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)

                        Text {
                            id: keyLabel
                            anchors.centerIn: parent
                            text: _prettyKey(modelData)
                            color: Theme.onPrimaryContainerColor
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.family: "monospace"
                        }

                        function _prettyKey(k) {
                            k = k.trim()
                            if (k === "return") return "↵"
                            if (k === "RETURN") return "↵"
                            if (k === "PRINT")  return "PrtSc"
                            if (k === "Next")   return "PgDn"
                            if (k === "Prior")  return "PgUp"
                            if (k === "left")   return "←"
                            if (k === "right")  return "→"
                            if (k === "up")     return "↑"
                            if (k === "down")   return "↓"
                            if (k === "mouse:272") return "LMB"
                            if (k === "mouse:273") return "RMB"
                            if (k === "mouse_down") return "Scroll ↓"
                            if (k === "mouse_up")   return "Scroll ↑"
                            if (k === "bracketright") return "]"
                            if (k === "bracketleft")  return "["
                            if (k.startsWith("XF86Audio"))  return k.replace("XF86Audio", "🔊 ")
                            if (k.startsWith("XF86MonBrightness")) return k.replace("XF86MonBrightness", "🔆 ")
                            if (k === "SPACE" || k === "Space") return "␣"
                            if (k === "ESCAPE" || k === "escape") return "Esc"
                            return k
                        }
                    }
                }
            }

            // Action description
            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignVCenter
                text: bindSource[bindIndex]
                      ? bindSource[bindIndex].action
                      : ""
                color: Qt.rgba(Theme.onPrimaryContainerColor.r,
                               Theme.onPrimaryContainerColor.g,
                               Theme.onPrimaryContainerColor.b, 0.85)
                font.pixelSize: 14
                elide: Text.ElideRight
            }
        }
    }
}
