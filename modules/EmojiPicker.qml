// ─────────────────────────────────────────────────────────────────────────────
// EmojiPicker.qml — Android-style Wayland emoji picker overlay
//
// Features:
//   • Full-height vertical category rail on the left (Recents, All, Categories).
//   • Top fuzzy search bar with multi-token matching, field weights, and debounce.
//   • 2D GridView with keyboard arrow navigation and viewport-level hover de-confliction.
//   • Single atomic LRU recents persistence via FileView with string-glyph migration.
//   • Target-window-aware clipboard copying and simulated Wayland paste.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import "../services"

OverlayWindow {
    id: picker
    panelWidth:  740
    panelHeight: 520
    hasBorder:   true

    // ─────────────────────────────────────────────────────────────────────────
    // State & Public Properties
    // ─────────────────────────────────────────────────────────────────────────
    property var allEmojis: []
    property var categorizedEmojis: ({})
    property var emojiByGlyph: ({})
    property var rawRecentGlyphs: []
    property var recentEmojis: []
    property var currentDisplayList: []
    property int selectedIndex: 0
    property int activeTab: 1
    property bool loaded: false

    property string targetWindowAddr: ""
    property string targetWindowClass: ""
    property bool openingPending: false

    property real lastMouseX: -1
    property real lastMouseY: -1

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell-emoji"
    readonly property string recentsPath: stateDir + "/recents.json"

    readonly property var categories: [
        { id: "recent", name: "Recent", icon: "🕒" },
        { id: "all", name: "All", icon: "🌐" },
        { id: "Smileys & Emotion", name: "Smileys", icon: "😀" },
        { id: "People & Body", name: "People", icon: "👋" },
        { id: "Animals & Nature", name: "Nature", icon: "🐶" },
        { id: "Food & Drink", name: "Food", icon: "🍔" },
        { id: "Travel & Places", name: "Travel", icon: "✈️" },
        { id: "Activities", name: "Activities", icon: "⚽" },
        { id: "Objects", name: "Objects", icon: "💡" },
        { id: "Symbols", name: "Symbols", icon: "🔣" },
        { id: "Flags", name: "Flags", icon: "🏁" }
    ]

    function show() {
        if (picker.shown) return;
        picker.openingPending = true;
        picker.targetWindowAddr = "";
        picker.targetWindowClass = "";
        captureTimeoutTimer.restart();
        captureActiveWindow();
    }

    function toggle() {
        if (picker.shown) {
            captureTimeoutTimer.stop();
            picker.openingPending = false;
            picker.hide();
        } else if (picker.openingPending) {
            captureTimeoutTimer.stop();
            picker.openingPending = false;
        } else {
            picker.openingPending = true;
            picker.targetWindowAddr = "";
            picker.targetWindowClass = "";
            captureTimeoutTimer.restart();
            captureActiveWindow();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle & Focus Management
    // ─────────────────────────────────────────────────────────────────────────
    onShownChanged: {
        if (shown) {
            captureTimeoutTimer.stop();
            searchField.text = "";
            picker.activeTab = (picker.recentEmojis.length > 0) ? 0 : 1;
            refreshView();
            picker.selectedIndex = 0;
            if (grid.count > 0) grid.positionViewAtBeginning();
            searchField.forceActiveFocus();
            picker.lastMouseX = -1;
            picker.lastMouseY = -1;
        } else {
            captureTimeoutTimer.stop();
            picker.openingPending = false;
        }
    }

    Timer {
        id: captureTimeoutTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (picker.openingPending) {
                console.warn("EmojiPicker: Active window capture timed out after 300ms; opening with empty target");
                picker.openingPending = false;
                picker.targetWindowAddr = "";
                picker.targetWindowClass = "";
                picker.screen = HyprlandService.getFocusedScreen();
                picker.shown = true;
            }
        }
    }

    Component.onCompleted: {
        mkdirProcess.running = true;
    }

    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", picker.stateDir]
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Active Window Capture & Paste
    // ─────────────────────────────────────────────────────────────────────────
    function captureActiveWindow() {
        captureProcess.running = true;
    }

    Process {
        id: captureProcess
        command: ["sh", "-c", "hyprctl activewindow -j 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            id: captureCollector
            onStreamFinished: {
                if (picker.openingPending) {
                    captureTimeoutTimer.stop();
                    picker.openingPending = false;
                    try {
                        const win = JSON.parse(captureCollector.text);
                        picker.targetWindowAddr = win.address ? win.address : "none";
                        picker.targetWindowClass = win.class || "none";
                    } catch (e) {
                        console.warn("EmojiPicker: Could not parse activewindow JSON —", e);
                        picker.targetWindowAddr = "";
                        picker.targetWindowClass = "";
                    }
                    picker.screen = HyprlandService.getFocusedScreen();
                    picker.shown = true;
                } else {
                    console.warn("EmojiPicker: Capture stream finished after timeout or cancellation; ignoring late result");
                }
            }
        }
        onExited: (code) => {
            // Failsafe in case stream was empty or failed
            if (picker.openingPending) {
                captureTimeoutTimer.stop();
                picker.openingPending = false;
                picker.targetWindowAddr = "";
                picker.targetWindowClass = "";
                picker.screen = HyprlandService.getFocusedScreen();
                picker.shown = true;
            }
        }
    }

    function debugSelect(glyph, mode) {
        if (Quickshell.env("XEON_EMOJI_DEBUG") !== "1") return;
        const clean = glyph ? glyph.replace(/\uFE0F/g, "") : "";
        const item = picker.emojiByGlyph[clean] || picker.emojiByGlyph[glyph] || { emoji: glyph, cleanGlyph: clean, name: "Debug" };
        picker.selectEmoji(item, mode || "paste");
    }


    function selectCurrent(mode) {
        if (currentDisplayList.length === 0) return;
        const idx = Math.max(0, Math.min(currentDisplayList.length - 1, selectedIndex));
        selectEmoji(currentDisplayList[idx], mode);
    }

    function selectEmoji(item, mode) {
        if (!item) return;
        recordRecent(item);

        const pasteMode = mode || "paste";
        const targetAddr = picker.targetWindowAddr;
        const targetClass = picker.targetWindowClass;

        // Dismiss immediately without animation to yield Wayland keyboard focus
        picker.hideNow();

        Quickshell.execDetached([
            "bash",
            Quickshell.shellDir + "/scripts/paste-emoji.sh",
            item.emoji,
            targetAddr,
            targetClass,
            pasteMode
        ]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Recents Persistence (Single Atomic FileView with Array of Strings)
    // ─────────────────────────────────────────────────────────────────────────
    FileView {
        id: recentsFile
        path: picker.recentsPath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const content = (typeof text === "function") ? text() : text;
            picker.loadRecents(content);
        }
    }

    function loadRecents(content) {
        if (!content || content.trim().length === 0) {
            picker.rawRecentGlyphs = [];
            picker.resolveRecents();
            return;
        }
        try {
            const parsed = JSON.parse(content);
            if (Array.isArray(parsed)) {
                let migrated = false;
                const glyphs = [];
                for (let i = 0; i < parsed.length; i++) {
                    const item = parsed[i];
                    let rawG = "";
                    if (typeof item === "string") {
                        rawG = item;
                    } else if (item && typeof item === "object" && item.emoji) {
                        // Migrate legacy object format gracefully
                        rawG = item.emoji;
                        migrated = true;
                    }
                    if (rawG) {
                        // Store the canonical FE0F-stripped glyph to resolve FE0F and non-FE0F uniformly
                        const cleanG = rawG.replace(/\uFE0F/g, "");
                        if (!glyphs.includes(cleanG)) {
                            glyphs.push(cleanG);
                        }
                    }
                }
                picker.rawRecentGlyphs = glyphs;
                picker.resolveRecents();
                if (migrated) {
                    try {
                        recentsFile.setText(JSON.stringify(glyphs));
                    } catch (e) {}
                }
            }
        } catch (e) {
            console.warn("EmojiPicker: Could not parse recents.json —", e);
            picker.rawRecentGlyphs = [];
            picker.resolveRecents();
        }
    }

    function resolveRecents() {
        if (!picker.loaded) {
            return;
        }
        const resolved = [];
        const seen = {};
        for (let i = 0; i < picker.rawRecentGlyphs.length; i++) {
            const rawG = picker.rawRecentGlyphs[i];
            const cleanG = rawG ? rawG.replace(/\uFE0F/g, "") : "";
            const item = picker.emojiByGlyph[cleanG] || picker.emojiByGlyph[rawG];
            if (item && !seen[item.emoji]) {
                seen[item.emoji] = true;
                resolved.push(item);
                if (resolved.length >= 48) break;
            }
        }
        picker.recentEmojis = resolved;
        if (picker.activeTab === 0 && searchField.text.trim().length === 0) {
            picker.refreshView();
        }
    }

    function recordRecent(emojiObj) {
        if (!emojiObj || !emojiObj.emoji) return;
        const cleanG = emojiObj.cleanGlyph || emojiObj.emoji.replace(/\uFE0F/g, "");

        // Dedup and move to front using FE0F-stripped comparison
        const filtered = picker.rawRecentGlyphs.filter(g => g !== cleanG && g.replace(/\uFE0F/g, "") !== cleanG);
        filtered.unshift(cleanG);
        const capped = filtered.slice(0, 48);
        picker.rawRecentGlyphs = capped;
        picker.resolveRecents();

        try {
            recentsFile.setText(JSON.stringify(capped));
        } catch (e) {
            console.warn("EmojiPicker: Could not save recents.json —", e);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dataset Loader (FileView parsed once at startup)
    // ─────────────────────────────────────────────────────────────────────────
    FileView {
        id: emojiDataFile
        path: Quickshell.shellDir + "/data/emojis.json"
        onLoaded: {
            try {
                const content = (typeof text === "function") ? text() : text;
                const list = JSON.parse(content);
                picker.allEmojis = list;
                const map = {};
                const glyphMap = {};
                for (let i = 0; i < list.length; i++) {
                    const item = list[i];
                    item.cleanGlyph = item.emoji ? item.emoji.replace(/\uFE0F/g, "") : "";
                    const cat = item.category;
                    if (!map[cat]) map[cat] = [];
                    map[cat].push(item);
                    glyphMap[item.emoji] = item;
                    glyphMap[item.cleanGlyph] = item;
                }
                picker.categorizedEmojis = map;
                picker.emojiByGlyph = glyphMap;
                picker.loaded = true;
                picker.resolveRecents();
                picker.refreshView();
            } catch (e) {
                console.warn("EmojiPicker: Could not parse emojis.json —", e);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Filtering & Debounce
    // ─────────────────────────────────────────────────────────────────────────
    Timer {
        id: searchDebounceTimer
        interval: 50
        repeat: false
        onTriggered: {
            picker.refreshView();
            if (grid.count > 0) grid.positionViewAtBeginning();
        }
    }

    function flushSearch() {
        if (searchDebounceTimer.running) {
            searchDebounceTimer.stop();
            picker.refreshView();
            if (grid.count > 0) grid.positionViewAtBeginning();
        }
    }

    function refreshView() {
        const q = searchField.text.trim();
        if (q.length > 0) {
            // Global search overrides active tab using hoisted prepared query
            const pq = Fuzzy.prepareQuery(q);
            const scored = [];
            for (let i = 0; i < allEmojis.length; i++) {
                const s = Fuzzy.scoreEmoji(pq, allEmojis[i]);
                if (s > 0) {
                    scored.push({ item: allEmojis[i], score: s });
                }
            }
            scored.sort((a, b) => b.score - a.score);
            currentDisplayList = scored.map(x => x.item);
        } else {
            // Tab-specific filtered list
            if (activeTab === 0) {
                currentDisplayList = recentEmojis;
            } else if (activeTab === 1) {
                currentDisplayList = allEmojis;
            } else {
                const catName = categories[activeTab].id;
                currentDisplayList = categorizedEmojis[catName] || [];
            }
        }
        selectedIndex = Math.min(selectedIndex, Math.max(0, currentDisplayList.length - 1));
        if (currentDisplayList.length > 0 && selectedIndex < 0) {
            selectedIndex = 0;
        }
    }

    function moveSelection(delta) {
        if (currentDisplayList.length === 0) return;
        selectedIndex = Math.max(0, Math.min(currentDisplayList.length - 1, selectedIndex + delta));
        grid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    function switchTab(newTab) {
        if (newTab < 0 || newTab >= categories.length) return;
        searchField.text = "";
        activeTab = newTab;
        refreshView();
        selectedIndex = 0;
        if (grid.count > 0) grid.positionViewAtBeginning();
    }

    function handleKey(key, modifiers) {
        const cols = gridArea.cols;

        if (key === Qt.Key_Left) {
            picker.moveSelection(-1);
            return true;
        } else if (key === Qt.Key_Right) {
            picker.moveSelection(1);
            return true;
        } else if (key === Qt.Key_Up) {
            picker.moveSelection(-cols);
            return true;
        } else if (key === Qt.Key_Down) {
            picker.moveSelection(cols);
            return true;
        } else if (key === Qt.Key_PageUp) {
            picker.moveSelection(-cols * 4);
            return true;
        } else if (key === Qt.Key_PageDown) {
            picker.moveSelection(cols * 4);
            return true;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            if (modifiers & Qt.ControlModifier) {
                // Explicitly ignore Ctrl+Enter to align with hint strip
                return true;
            }
            picker.flushSearch();
            if (modifiers & Qt.ShiftModifier) {
                picker.selectCurrent("copy-only");
            } else {
                picker.selectCurrent("paste");
            }
            return true;
        } else if (key === Qt.Key_Escape) {
            if (searchField.text.length > 0) {
                searchField.text = "";
            } else {
                picker.hide();
            }
            return true;
        } else if ((key === Qt.Key_Backtab && (modifiers & Qt.ControlModifier)) ||
                   (key === Qt.Key_Tab && (modifiers & Qt.ControlModifier) && (modifiers & Qt.ShiftModifier))) {
            picker.switchTab((picker.activeTab - 1 + picker.categories.length) % picker.categories.length);
            return true;
        } else if (key === Qt.Key_Tab && (modifiers & Qt.ControlModifier)) {
            picker.switchTab((picker.activeTab + 1) % picker.categories.length);
            return true;
        } else if (modifiers & Qt.AltModifier && key >= Qt.Key_1 && key <= Qt.Key_9) {
            picker.switchTab(key - Qt.Key_1);
            return true;
        }
        return false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Main UI Layout
    // ─────────────────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── 1. Android-Style Left Category Rail (Full Window Height) ──────────
        Rectangle {
            id: categoryRail
            z: 10
            Layout.preferredWidth: 56
            Layout.fillHeight: true
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.45)
            border.width: 1
            border.color: Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.3)

            property int hoveredTab: -1
            property real hoveredTabY: 0
            property string hoveredTabName: ""

            ListView {
                id: tabList
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                clip: true
                spacing: 4 // 11 tabs * 40px + 10 gaps * 4px + 24px margins = 504px (fits comfortably in 520px panel)
                interactive: false
                model: picker.categories

                delegate: Rectangle {
                    id: tabBtn
                    width: 44
                    height: 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: Theme.radiusSmall

                    property bool isActive: (index === picker.activeTab)
                    property bool isSearching: (searchField.text.trim().length > 0)

                    color: isActive
                        ? (isSearching
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                            : Theme.primary)
                        : (tabMouse.containsMouse
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                            : "transparent")

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 18
                        opacity: tabBtn.isActive ? (tabBtn.isSearching ? 0.6 : 1.0) : 0.85
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            categoryRail.hoveredTab = index;
                            categoryRail.hoveredTabName = modelData.name;
                            categoryRail.hoveredTabY = tabBtn.mapToItem(categoryRail, 0, tabBtn.height / 2).y;
                        }
                        onExited: {
                            if (categoryRail.hoveredTab === index) {
                                categoryRail.hoveredTab = -1;
                            }
                        }
                        onClicked: picker.switchTab(index)
                    }
                }
            }

            // Hover Tooltip — positioned outside ListView so it is never clipped
            Rectangle {
                id: railTooltip
                visible: categoryRail.hoveredTab >= 0
                x: categoryRail.width + 8
                y: Math.max(8, Math.min(categoryRail.height - height - 8, categoryRail.hoveredTabY - (height / 2)))
                width: tooltipText.width + 16
                height: tooltipText.height + 8
                color: Theme.surface
                border.color: Theme.outlineVariant
                border.width: 1
                radius: 6
                z: 999

                Text {
                    id: tooltipText
                    anchors.centerIn: parent
                    text: categoryRail.hoveredTabName
                    color: Theme.surfaceText
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }

        // ── 2. Right Pane: Search Bar + Grid + Bottom Status Strip ────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            spacing: 10

            // Search Field
            Rectangle {
                Layout.fillWidth: true
                height: 46
                color: Theme.surfaceVariant
                radius: Theme.radiusSmall
                border.width: searchField.activeFocus ? 2 : 1
                border.color: searchField.activeFocus ? Theme.primary : Theme.outlineVariant

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        text: "🔍"
                        font.pixelSize: 14
                        color: Theme.surfaceVariantText
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            text: "Search emojis..."
                            color: Theme.surfaceVariantText
                            font.pixelSize: 15
                            visible: searchField.text.length === 0
                        }

                        TextInput {
                            id: searchField
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.surfaceText
                            font.pixelSize: 15
                            clip: true

                            onTextChanged: {
                                picker.selectedIndex = 0;
                                if (text.length === 0) {
                                    searchDebounceTimer.stop();
                                    picker.refreshView();
                                    if (grid.count > 0) grid.positionViewAtBeginning();
                                } else {
                                    searchDebounceTimer.restart();
                                }
                            }

                            Keys.onPressed: (event) => {
                                if (picker.handleKey(event.key, event.modifiers)) {
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    // Clear button
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: clearMouse.containsMouse ? Theme.surface : "transparent"
                        visible: searchField.text.length > 0

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: Theme.surfaceVariantText
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // Grid Container & Empty States
            Item {
                id: gridArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Fixed gutter width (10px) always reserved on the right
                readonly property real gutterWidth: 10
                readonly property real availableWidth: Math.max(100, width - gutterWidth)
                readonly property int targetCellSize: 48
                readonly property int cols: Math.max(1, Math.floor(availableWidth / targetCellSize))
                readonly property real calculatedCellWidth: Math.floor(availableWidth / cols)
                readonly property real calculatedCellHeight: 46

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.rightMargin: gridArea.gutterWidth
                    cellWidth: gridArea.calculatedCellWidth
                    cellHeight: gridArea.calculatedCellHeight
                    clip: true
                    reuseItems: true
                    model: picker.currentDisplayList
                    currentIndex: picker.selectedIndex
                    visible: picker.currentDisplayList.length > 0

                    delegate: Item {
                        id: delegateRoot
                        width: grid.cellWidth
                        height: grid.cellHeight

                        property bool isCurrent: (index === picker.selectedIndex)

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 4
                            height: parent.height - 4
                            radius: Theme.radiusSmall
                            color: delegateRoot.isCurrent
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                                : "transparent"

                            border.width: delegateRoot.isCurrent ? 1 : 0
                            border.color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: modelData.emoji
                                font.family: "Noto Color Emoji"
                                font.pixelSize: 24
                            }
                        }
                    }

                    ScrollBar.vertical: gridScrollBar
                }

                ScrollBar {
                    id: gridScrollBar
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: gridArea.gutterWidth
                    policy: ScrollBar.AsNeeded
                    z: 10
                }

                // Single MouseArea over viewport for hover de-confliction & selection
                MouseArea {
                    id: gridMouseArea
                    anchors.fill: parent
                    anchors.rightMargin: gridArea.gutterWidth
                    hoverEnabled: true
                    z: 1

                    cursorShape: {
                        const idx = grid.indexAt(mouseX + grid.contentX, mouseY + grid.contentY);
                        return (idx >= 0 && idx < picker.currentDisplayList.length) ? Qt.PointingHandCursor : Qt.ArrowCursor;
                    }

                    onPositionChanged: (mouse) => {
                        const dx = Math.abs(mouse.x - picker.lastMouseX);
                        const dy = Math.abs(mouse.y - picker.lastMouseY);
                        // Require real pointer movement in non-scrolling viewport space
                        if (dx >= 3 || dy >= 3) {
                            picker.lastMouseX = mouse.x;
                            picker.lastMouseY = mouse.y;
                            const idx = grid.indexAt(mouse.x + grid.contentX, mouse.y + grid.contentY);
                            if (idx >= 0 && idx < picker.currentDisplayList.length) {
                                picker.selectedIndex = idx;
                            }
                        }
                    }

                    onClicked: (mouse) => {
                        const idx = grid.indexAt(mouse.x + grid.contentX, mouse.y + grid.contentY);
                        if (idx >= 0 && idx < picker.currentDisplayList.length) {
                            picker.selectedIndex = idx;
                            const item = picker.currentDisplayList[idx];
                            if (mouse.modifiers & Qt.ShiftModifier) {
                                picker.selectEmoji(item, "copy-only");
                            } else {
                                picker.selectEmoji(item, "paste");
                            }
                        }
                    }

                    onWheel: (wheel) => {
                        // Pass wheel events through to GridView
                        wheel.accepted = false;
                    }
                }

                // Empty State: No Recents
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: picker.currentDisplayList.length === 0 && searchField.text.trim().length === 0 && picker.activeTab === 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "🕒"
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 36
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No recent emojis yet"
                        color: Theme.surfaceVariantText
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Selected emojis will appear here for quick access."
                        color: Theme.surfaceVariantText
                        font.pixelSize: 13
                        opacity: 0.8
                    }
                }

                // Empty State: No Search Matches
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: picker.currentDisplayList.length === 0 && searchField.text.trim().length > 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "🔍"
                        font.pixelSize: 32
                        color: Theme.surfaceVariantText
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No emojis found"
                        color: Theme.surfaceVariantText
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Try searching with broader terms or synonyms."
                        color: Theme.surfaceVariantText
                        font.pixelSize: 13
                        opacity: 0.8
                    }
                }
            }

            // ── 3. Bottom Detail / Status Strip ──────────────────────────────
            Rectangle {
                id: detailStrip
                Layout.fillWidth: true
                height: 48
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5)
                radius: Theme.radiusSmall
                border.width: 1
                border.color: Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.3)

                readonly property var currentItem: (picker.currentDisplayList.length > 0 && picker.selectedIndex >= 0 && picker.selectedIndex < picker.currentDisplayList.length)
                    ? picker.currentDisplayList[picker.selectedIndex]
                    : null

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    // Large Glyph Preview
                    Text {
                        text: detailStrip.currentItem ? detailStrip.currentItem.emoji : ""
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 28
                        visible: detailStrip.currentItem !== null
                    }

                    // Title & Category
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: detailStrip.currentItem !== null

                        Text {
                            text: detailStrip.currentItem ? detailStrip.currentItem.name : ""
                            color: Theme.surfaceText
                            font.pixelSize: 13
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            text: detailStrip.currentItem ? detailStrip.currentItem.category : ""
                            color: Theme.primary
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    // Shortcut Hints
                    RowLayout {
                        spacing: 8
                        opacity: 0.7

                        Rectangle {
                            height: 18
                            width: hint1.width + 10
                            radius: 4
                            color: Theme.surfaceVariant
                            Text {
                                id: hint1
                                anchors.centerIn: parent
                                text: "Enter ↵ paste"
                                color: Theme.surfaceVariantText
                                font.pixelSize: 10
                            }
                        }

                        Rectangle {
                            height: 18
                            width: hint2.width + 10
                            radius: 4
                            color: Theme.surfaceVariant
                            Text {
                                id: hint2
                                anchors.centerIn: parent
                                text: "Shift+Enter copy"
                                color: Theme.surfaceVariantText
                                font.pixelSize: 10
                            }
                        }

                        Rectangle {
                            height: 18
                            width: hint3.width + 10
                            radius: 4
                            color: Theme.surfaceVariant
                            Text {
                                id: hint3
                                anchors.centerIn: parent
                                text: "Esc close"
                                color: Theme.surfaceVariantText
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }
}
