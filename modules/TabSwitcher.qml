// ─────────────────────────────────────────────────────────────────────────
// TabSwitcher.qml — Alt+Tab window switcher
//
// Cycles open windows across all workspaces in MRU order.
// Shows at most 3 cards at a time (previous / selected / next). The list is
// circular, so cycling past the end wraps around to the first window.
// Each card has a live window preview (ScreencopyView) with an icon fallback.
//
// Committing (releasing Alt):
//   1. Hyprland release bind  -> GlobalShortcut "switcherCommit" -> commit()
//   2. Qt key release (Alt)   -> handled here while the overlay has keyboard
//      focus, so it still works if the Hyprland release bind does not fire.
//   Enter also commits, Esc cancels, Tab/Shift+Tab/arrows also cycle.
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "../services"

PanelWindow {
    id: root

    // ---- Public API ------------------------------------------------------
    property bool active: false          // a switch is in progress (Alt held)
    property bool shown: false           // the UI is visible (after the quick-tap delay)
    property bool blocked: false
    property int selectedIndex: 0
    property var windowList: []

    // ---- Layout constants ------------------------------------------------
    readonly property int maxVisible: 3
    readonly property int padding: 14
    readonly property int cardSpacing: 12
    readonly property int previewH: 150
    readonly property int cardH: 204
    readonly property int cardW: Math.max(180, Math.min(300,
        Math.floor(((switcherScope.width > 0 ? switcherScope.width : 1920) * 0.9
                    - 2 * padding - (maxVisible - 1) * cardSpacing) / maxVisible)))
    readonly property bool carousel: windowList.length > maxVisible
    readonly property int visibleCount: Math.min(maxVisible, windowList.length)

    function focusTargetScreen() {
        targetScreen = HyprlandService.getFocusedScreen();
    }

    function next() {
        if (blocked) return;
        if (!active) {
            buildList();
            if (windowList.length <= 1) {
                // 0 windows: do nothing. 1 window: do nothing visible.
                selectedIndex = 0;
                active = false;
                HyprlandService.switcherOpen = false;
                return;
            }
            focusTargetScreen();
            selectedIndex = 1;
            active = true;               // maps the (still invisible) overlay and grabs keyboard focus
            HyprlandService.switcherOpen = true;
            showDelayTimer.restart();
        } else if (windowList.length > 0) {
            selectedIndex = (selectedIndex + 1) % windowList.length;
        }
    }

    function prev() {
        if (blocked) return;
        if (!active) {
            buildList();
            if (windowList.length <= 1) {
                selectedIndex = 0;
                active = false;
                HyprlandService.switcherOpen = false;
                return;
            }
            focusTargetScreen();
            selectedIndex = windowList.length - 1;
            active = true;
            HyprlandService.switcherOpen = true;
            showDelayTimer.restart();
        } else if (windowList.length > 0) {
            selectedIndex = (selectedIndex - 1 + windowList.length) % windowList.length;
        }
    }

    function commit() {
        if (!active) return; // Release bind fires on every Alt release, no-op when inactive
        showDelayTimer.stop();
        if (windowList.length > 0 && selectedIndex >= 0 && selectedIndex < windowList.length) {
            let win = windowList[selectedIndex];
            HyprlandService.focusWindow(win.address, win.workspaceId);
        }
        active = false;
        shown = false;
        HyprlandService.switcherOpen = false;
    }

    function cancel() {
        showDelayTimer.stop();
        active = false;
        shown = false;
        HyprlandService.switcherOpen = false;
    }

    function buildList() {
        Hyprland.refreshToplevels();
        let list = [];
        for (let tl of Hyprland.toplevels.values) {
            let ipc = tl.lastIpcObject;
            if (!ipc || ipc.mapped === false || ipc.hidden === true) continue;
            let wsId = ipc.workspace ? ipc.workspace.id : 0;
            let wsName = (ipc.workspace && ipc.workspace.name) ? ipc.workspace.name : "";
            // Exclude negative / special workspaces
            if (wsId < 0 || wsName.startsWith("special:")) continue;

            list.push({
                address: tl.address,
                toplevel: tl,
                title: tl.title || ipc.title || "Window",
                winClass: ipc.class || "",
                appIcon: AppInfo.getAppIcon(ipc.class || ""),
                workspaceId: wsId,
                workspaceName: wsName || ("" + wsId),
                winW: (ipc.size && ipc.size.length >= 2) ? ipc.size[0] : 0,
                winH: (ipc.size && ipc.size.length >= 2) ? ipc.size[1] : 0,
                focusHistoryID: (ipc.focusHistoryID !== undefined) ? ipc.focusHistoryID : 9999
            });
        }
        // MRU order: 0 = current, 1 = previous, etc.
        list.sort((a, b) => a.focusHistoryID - b.focusHistoryID);
        windowList = list;
    }

    // Quick-tap timer: wait 150ms before revealing the UI to avoid a flash
    Timer {
        id: showDelayTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (root.active && root.windowList.length > 1) {
                root.shown = true;
            }
        }
    }

    // ---- Wayland layer-shell configuration -------------------------------
    screen: targetScreen
    property var targetScreen: (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // The overlay is mapped (invisibly) the moment Alt+Tab is pressed, so it owns the
    // keyboard while Alt is still held. That lets us see the Alt release ourselves.
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "tab-switcher"

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: active || closingTimer.running

    Timer {
        id: closingTimer
        interval: Theme.animFast + 30
    }

    onShownChanged: {
        if (!shown) closingTimer.restart();
    }

    onVisibleChanged: {
        if (visible) focusTimer.restart();
    }

    // Make sure our key handler item really has focus once the surface is up
    Timer {
        id: focusTimer
        interval: 30
        onTriggered: switcherScope.forceActiveFocus()
    }

    onBlockedChanged: {
        if (blocked && (active || shown)) {
            cancel();
        }
    }

    // ---- Switcher UI -----------------------------------------------------
    Item {
        id: switcherScope
        anchors.fill: parent
        focus: true

        // Esc cancels, Enter commits (window-level shortcuts, independent of item focus)
        Shortcut {
            sequence: "Escape"
            enabled: root.active
            onActivated: root.cancel()
        }
        Shortcut {
            sequences: ["Return", "Enter"]
            enabled: root.active
            onActivated: root.commit()
        }

        Keys.onPressed: (event) => {
            if (!root.active) return;
            switch (event.key) {
            case Qt.Key_Escape:
                root.cancel();
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.commit();
                event.accepted = true;
                break;
            case Qt.Key_Tab:
            case Qt.Key_Right:
                root.next();
                event.accepted = true;
                break;
            case Qt.Key_Backtab:
            case Qt.Key_Left:
                root.prev();
                event.accepted = true;
                break;
            }
        }

        // Releasing Alt while the overlay has keyboard focus commits the selection.
        // (Fallback for when the Hyprland release bind does not fire.)
        Keys.onReleased: (event) => {
            if (event.isAutoRepeat) return;
            if (root.active && (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr)) {
                root.commit();
                event.accepted = true;
            }
        }

        // Dimmed backdrop
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.3)
            opacity: root.shown ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: Theme.animFast; easing.type: Theme.easeOut }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()
            }
        }

        // Centered pill-shaped container
        Rectangle {
            id: pillContainer
            anchors.centerIn: parent
            implicitWidth: root.visibleCount * root.cardW + Math.max(0, root.visibleCount - 1) * root.cardSpacing + 2 * root.padding
            implicitHeight: root.cardH + 2 * root.padding + (root.carousel ? 22 : 0)
            radius: Theme.radiusLarge
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
            border.width: 1
            border.color: Theme.outlineVariant

            opacity: root.shown ? 1.0 : 0.0
            scale: root.shown ? 1.0 : 0.95
            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easeOut } }
            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easeOut } }

            layer.enabled: true

            MouseArea {
                anchors.fill: parent
                onClicked: (mouse) => mouse.accepted = true
            }

            // Cards area: a circular carousel showing previous / selected / next
            Item {
                id: cardArea
                x: root.padding
                y: root.padding
                width: pillContainer.width - 2 * root.padding
                height: root.cardH

                Repeater {
                    model: root.windowList

                    delegate: Item {
                        id: card

                        readonly property var tl: modelData.toplevel
                        readonly property int n: root.windowList.length
                        readonly property bool isSelected: (index === root.selectedIndex)

                        // Signed circular distance from the selected card (wraps around the list)
                        readonly property int rel: n > 0 ? (((index - root.selectedIndex) % n) + n) % n : 0
                        readonly property int dist: rel > n / 2 ? rel - n : rel

                        // With <= 3 windows every card is shown in list order; with more, the
                        // selected card sits in the middle with its neighbours either side.
                        readonly property bool inView: root.carousel ? Math.abs(dist) <= 1 : true
                        readonly property int slot: root.carousel ? dist + 1 : index

                        x: slot * (root.cardW + root.cardSpacing)
                        y: 0
                        width: root.cardW
                        height: root.cardH

                        opacity: inView ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                        // Card background / selection highlight
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: card.isSelected
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                                : (cardMouse.containsMouse
                                    ? Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.40)
                                    : "transparent")
                            border.width: card.isSelected ? 2 : 1
                            border.color: card.isSelected ? Theme.primary : Theme.outlineVariant
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                        }

                        // ── Window preview ──
                        Rectangle {
                            id: previewArea
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 8
                            height: root.previewH
                            radius: 6
                            clip: true
                            color: Qt.rgba(0, 0, 0, 0.30)

                            // Fallback: big app icon, hidden once live content is available
                            IconImage {
                                anchors.centerIn: parent
                                width: 48
                                height: 48
                                source: Quickshell.iconPath(modelData.appIcon)
                                visible: !thumb.hasLive
                                opacity: 0.9
                            }

                            // Live thumbnail, letterboxed to the window's real aspect ratio
                            Item {
                                id: thumb
                                readonly property real aspect: (modelData.winW > 0 && modelData.winH > 0)
                                    ? modelData.winW / modelData.winH : 16 / 9
                                readonly property bool hasLive: thumbLoader.item ? thumbLoader.item.hasContent : false
                                width: Math.min(previewArea.width, previewArea.height * aspect)
                                height: width / aspect
                                anchors.centerIn: parent

                                // Created ONLY while the switcher is visible and the card is on screen
                                Loader {
                                    id: thumbLoader
                                    anchors.fill: parent
                                    active: root.shown && card.inView && card.tl && card.tl.wayland != null
                                    sourceComponent: ScreencopyView {
                                        anchors.fill: parent
                                        captureSource: card.tl.wayland
                                        live: true
                                        visible: hasContent
                                    }
                                }
                            }
                        }

                        // ── Title row: icon, title, workspace badge ──
                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.bottomMargin: 10
                            height: 26
                            spacing: 8

                            IconImage {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                source: Quickshell.iconPath(modelData.appIcon)
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.title
                                color: card.isSelected ? (Theme.primaryText || Theme.surfaceText) : Theme.surfaceText
                                font.pixelSize: 13
                                font.bold: card.isSelected
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitHeight: 18
                                implicitWidth: wsBadgeText.implicitWidth + 12
                                radius: 9
                                color: card.isSelected ? Theme.primary : Theme.surfaceVariant

                                Text {
                                    id: wsBadgeText
                                    anchors.centerIn: parent
                                    text: "WS " + modelData.workspaceName
                                    color: card.isSelected ? Theme.inversePrimary : Theme.surfaceVariantText
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            enabled: card.inView
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIndex = index;
                                root.commit();
                            }
                        }
                    }
                }
            }

            // Position indicator when there are more windows than visible cards
            Text {
                visible: root.carousel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: (root.selectedIndex + 1) + " / " + root.windowList.length
                color: Theme.surfaceText
                opacity: 0.6
                font.pixelSize: 11
            }
        }
    }
}
