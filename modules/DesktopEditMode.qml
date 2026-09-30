import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"

Scope {
    id: root

    property bool active: false
    property string currentWallpaperPath: ""
    property var workingLayout: ({})
    property int layoutRevision: 0
    property string openPopoverWidgetId: ""

    signal closed(bool saved)

    function startEditMode() {
        root.openPopoverWidgetId = "";
        initWorkingLayout();
        refreshWallpaper();
        root.active = true;
    }

    function show() {
        startEditMode();
    }

    function hide() {
        discardAndClose();
    }

    function toggle() {
        if (root.active) discardAndClose();
        else startEditMode();
    }

    function refreshWallpaper() {
        wallpaperProcess.running = true;
    }

    Process {
        id: wallpaperProcess
        command: ["bash", Quickshell.shellDir + "/scripts/get-current-wallpaper.sh", Config.wallpaperDaemon]
        property string outBuf: ""
        onRunningChanged: {
            if (running) {
                outBuf = "";
            } else if (outBuf.trim().length > 0) {
                root.currentWallpaperPath = "file://" + outBuf.trim();
            }
        }
        stdout: SplitParser {
            onRead: data => {
                wallpaperProcess.outBuf += data;
            }
        }
    }

    function initWorkingLayout() {
        let sw = (Quickshell.screens.length > 0 && Quickshell.screens[0].width > 0) ? Quickshell.screens[0].width : 1920;
        let sh = (Quickshell.screens.length > 0 && Quickshell.screens[0].height > 0) ? Quickshell.screens[0].height : 1080;
        let def = DesktopLayout.getDefaultWorkingLayout(sw, sh);
        let cur = DesktopLayout.currentLayout || {};
        let wl = {};
        let ids = ["mpris", "tray", "clock", "calendar"];

        for (let i = 0; i < ids.length; i++) {
            let id = ids[i];
            if (DesktopLayout.hasStored(id)) {
                wl[id] = {
                    x: cur[id].x,
                    y: cur[id].y,
                    w: cur[id].w,
                    h: cur[id].h,
                    visible: cur[id].visible !== false,
                    transparentBg: cur[id].transparentBg === true,
                    sendToBackground: cur[id].sendToBackground === true
                };
            } else {
                wl[id] = {
                    x: def[id].x,
                    y: def[id].y,
                    w: def[id].w,
                    h: def[id].h,
                    visible: true,
                    transparentBg: false,
                    sendToBackground: false
                };
            }
        }
        root.workingLayout = wl;
        root.layoutRevision++;
    }

    function updateWidgetGeometry(id, xFrac, yFrac, wFrac, hFrac) {
        if (!root.workingLayout[id]) return;
        root.workingLayout[id].x = xFrac;
        root.workingLayout[id].y = yFrac;
        root.workingLayout[id].w = wFrac;
        root.workingLayout[id].h = hFrac;
        root.layoutRevision++;
    }

    function updateWidgetTransparentBg(id, val) {
        if (!root.workingLayout[id]) return;
        root.workingLayout[id].transparentBg = val;
        root.layoutRevision++;
    }

    function updateWidgetSendToBackground(id, val) {
        if (!root.workingLayout[id]) return;
        root.workingLayout[id].sendToBackground = val;
        root.layoutRevision++;
    }

    function removeWidget(id) {
        if (!root.workingLayout[id]) return;
        root.workingLayout[id].visible = false;
        root.layoutRevision++;
    }

    function restoreWidget(id) {
        if (!root.workingLayout[id]) return;
        root.workingLayout[id].visible = true;
        root.layoutRevision++;
    }

    function saveAndClose() {
        root.openPopoverWidgetId = "";
        DesktopLayout.saveLayout(root.workingLayout);
        root.active = false;
        root.closed(true);
    }

    function discardAndClose() {
        root.openPopoverWidgetId = "";
        root.active = false;
        root.closed(false);
    }

    function getRemovedWidgets() {
        // dummy read to create binding dependency
        let rev = root.layoutRevision;
        let list = [];
        let map = {
            "mpris": "Media Player",
            "clock": "Clock",
            "calendar": "Calendar",
            "tray": "Tray"
        };
        let ids = ["mpris", "clock", "calendar", "tray"];
        for (let i = 0; i < ids.length; i++) {
            let id = ids[i];
            if (root.workingLayout[id] && root.workingLayout[id].visible === false) {
                list.push({ id: id, name: map[id] });
            }
        }
        return list;
    }

    // Fullscreen overlay on every screen
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: overlayWindow
            property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "desktop-edit-mode"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"
            visible: root.active

            readonly property bool isPrimary: (screen === Quickshell.screens[0])
            readonly property real screenW: screen ? screen.width : 1920
            readonly property real screenH: screen ? screen.height : 1080

            // Esc shortcut
            Shortcut {
                sequence: "Escape"
                enabled: root.active
                onActivated: {
                    if (root.openPopoverWidgetId !== "") {
                        root.openPopoverWidgetId = "";
                    } else {
                        root.discardAndClose();
                    }
                }
            }

            Item {
                id: focusScope
                anchors.fill: parent
                focus: root.active
                Keys.onEscapePressed: {
                    if (root.openPopoverWidgetId !== "") {
                        root.openPopoverWidgetId = "";
                    } else {
                        root.discardAndClose();
                    }
                }

                // ── 1. Wallpaper background ──
                Rectangle {
                    anchors.fill: parent
                    color: Theme.background
                }

                Image {
                    anchors.fill: parent
                    source: root.currentWallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: overlayWindow.screenW
                    sourceSize.height: overlayWindow.screenH
                    cache: false
                    visible: status === Image.Ready
                }

                // ── 2. Widgets Container (Primary screen only) ──
                Item {
                    id: widgetsContainer
                    anchors.fill: parent
                    visible: overlayWindow.isPrimary

                    // Outside click handler to close open popover (z: 150 sits above normal widgets, below active widget at z: 200)
                    MouseArea {
                        anchors.fill: parent
                        z: 150
                        enabled: root.openPopoverWidgetId !== ""
                        onPressed: (mouse) => {
                            root.openPopoverWidgetId = "";
                            mouse.accepted = true;
                        }
                    }

                    // Repeater for the 4 editable widgets
                    Repeater {
                        model: ["mpris", "tray", "clock", "calendar"]

                        delegate: Item {
                            id: widgetWrapper
                            property string widgetId: modelData
                            z: (root.openPopoverWidgetId === widgetId) ? 200 : 1
                            // binding dependency on layoutRevision
                            property int rev: root.layoutRevision

                            property var widgetData: {
                                // Re-evaluate whenever the working layout is committed (drag/resize release, remove, restore)
                                let dep = widgetWrapper.rev;
                                let d = root.workingLayout[widgetId] || ({ x: 0, y: 0, w: 0.2, h: 0.15, visible: true, transparentBg: false, sendToBackground: false });
                                // Return a NEW object each time. A var property only emits a change
                                // signal when it gets a different object, and workingLayout[id] is
                                // mutated in place, so returning it directly never notifies.
                                return ({ x: d.x, y: d.y, w: d.w, h: d.h, visible: d.visible, transparentBg: d.transparentBg === true, sendToBackground: d.sendToBackground === true });
                            }
                            visible: widgetData.visible !== false

                            property var minSize: DesktopLayout.getMinSize(widgetId)
                            property real minW: minSize.width
                            property real minH: minSize.height

                            // Transient offsets used ONLY while the mouse is held down.
                            // The working layout is not touched until release.
                            property real dragDX: 0
                            property real dragDY: 0
                            property real resizeDW: 0
                            property real resizeDH: 0

                            // Committed geometry (pixels) derived from the working layout
                            property real baseW: Math.max(minW, Math.min(overlayWindow.screenW, Math.round((widgetData.w || 0.2) * overlayWindow.screenW)))
                            property real baseH: Math.max(minH, Math.min(overlayWindow.screenH, Math.round((widgetData.h || 0.15) * overlayWindow.screenH)))
                            property real baseX: Math.max(0, Math.min(overlayWindow.screenW - baseW, Math.round((widgetData.x || 0) * overlayWindow.screenW)))
                            property real baseY: Math.max(0, Math.min(overlayWindow.screenH - baseH, Math.round((widgetData.y || 0) * overlayWindow.screenH)))

                            width: baseW + resizeDW
                            height: baseH + resizeDH
                            x: baseX + dragDX
                            y: baseY + dragDY

                            // Write the final geometry to the working layout ONCE, on release
                            function commitGeometry() {
                                if (dragDX === 0 && dragDY === 0 && resizeDW === 0 && resizeDH === 0) return;
                                let sw = overlayWindow.screenW;
                                let sh = overlayWindow.screenH;
                                let fx = x / sw, fy = y / sh, fw = width / sw, fh = height / sh;
                                root.updateWidgetGeometry(widgetId, fx, fy, fw, fh);
                                dragDX = 0; dragDY = 0; resizeDW = 0; resizeDH = 0;
                            }

                            // Abort an in-flight drag/resize without saving anything
                            function cancelGeometry() {
                                dragDX = 0; dragDY = 0; resizeDW = 0; resizeDH = 0;
                            }

                            // Visual editable cue: subtle border
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                radius: 10
                                border.width: 1.5
                                border.color: widgetWrapper.widgetData.transparentBg
                                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.95)
                                    : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.75)
                                z: 4
                            }

                            // Real Widget Content (wrapped in DepthMask for live depth preview in edit mode)
                            DepthMask {
                                anchors.fill: parent
                                enabled: widgetWrapper.widgetData.sendToBackground === true
                                screenX: widgetWrapper.x
                                screenY: widgetWrapper.y
                                screenWidth: overlayWindow.screenW
                                screenHeight: overlayWindow.screenH

                                Loader {
                                    anchors.fill: parent
                                    sourceComponent: {
                                        switch (widgetId) {
                                            case "mpris": return mprisComp;
                                            case "tray": return trayComp;
                                            case "clock": return clockComp;
                                            case "calendar": return calendarComp;
                                            default: return null;
                                        }
                                    }
                                }
                            }

                            Component {
                                id: mprisComp
                                DesktopMprisContent { interactive: false; transparentBg: widgetWrapper.widgetData.transparentBg }
                            }

                            Component {
                                id: trayComp
                                DesktopTrayContent { interactive: false; editMode: true; transparentBg: widgetWrapper.widgetData.transparentBg }
                            }

                            Component {
                                id: clockComp
                                DesktopClockContent { interactive: false; transparentBg: widgetWrapper.widgetData.transparentBg }
                            }

                            Component {
                                id: calendarComp
                                DesktopCalendarContent { interactive: false; transparentBg: widgetWrapper.widgetData.transparentBg }
                            }

                            // Drag MouseArea covering the widget
                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                z: 10

                                // Pointer position in the (stationary) widgets container's
                                // coordinates. mouse.x/y are relative to this MouseArea, which
                                // moves with the widget, so using them directly feeds back on itself.
                                property real pressSceneX: 0
                                property real pressSceneY: 0

                                onPressed: (mouse) => {
                                    let p = mapToItem(widgetsContainer, mouse.x, mouse.y);
                                    pressSceneX = p.x;
                                    pressSceneY = p.y;
                                }

                                onPositionChanged: (mouse) => {
                                    if (!pressed) return;
                                    let p = mapToItem(widgetsContainer, mouse.x, mouse.y);
                                    let minDX = -widgetWrapper.baseX;
                                    let maxDX = overlayWindow.screenW - widgetWrapper.width - widgetWrapper.baseX;
                                    let minDY = -widgetWrapper.baseY;
                                    let maxDY = overlayWindow.screenH - widgetWrapper.height - widgetWrapper.baseY;
                                    widgetWrapper.dragDX = Math.round(Math.max(minDX, Math.min(maxDX, p.x - pressSceneX)));
                                    widgetWrapper.dragDY = Math.round(Math.max(minDY, Math.min(maxDY, p.y - pressSceneY)));
                                }

                                onReleased: widgetWrapper.commitGeometry()
                                onCanceled: widgetWrapper.cancelGeometry()
                            }

                            // Gear Settings Button (Top-Left)
                            Rectangle {
                                id: gearBtn
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                width: 24
                                height: 24
                                radius: 12
                                z: 20
                                color: (gearMouse.containsMouse || root.openPopoverWidgetId === widgetId) ? Theme.primary : Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.85)
                                border.width: 1
                                border.color: (gearMouse.containsMouse || root.openPopoverWidgetId === widgetId) ? Theme.primary : Theme.outlineVariant

                                Text {
                                    anchors.centerIn: parent
                                    text: "⚙"
                                    color: (gearMouse.containsMouse || root.openPopoverWidgetId === widgetId) ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: gearMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (mouse) => { mouse.accepted = true; }
                                    onClicked: (mouse) => {
                                        mouse.accepted = true;
                                        if (root.openPopoverWidgetId === widgetId) {
                                            root.openPopoverWidgetId = "";
                                        } else {
                                            root.openPopoverWidgetId = widgetId;
                                        }
                                    }
                                }
                            }

                            // Popover Anchored to Gear Button
                            Rectangle {
                                id: gearPopover
                                visible: root.openPopoverWidgetId === widgetId
                                z: 200
                                width: 240
                                height: 124
                                radius: Theme.radiusSmall
                                color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.98)
                                border.width: 1
                                border.color: Theme.outlineVariant

                                // Stays fully on screen: flip horizontally / vertically near screen edges
                                x: (widgetWrapper.x + 6 + width > overlayWindow.screenW) ? Math.max(-widgetWrapper.x, widgetWrapper.width - width - 6) : 6
                                y: (widgetWrapper.y + 36 + height > overlayWindow.screenH) ? Math.max(-widgetWrapper.y, -height - 6) : 36

                                MouseArea {
                                    anchors.fill: parent
                                    preventStealing: true
                                    onPressed: (mouse) => { mouse.accepted = true; }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    // 1. Transparent background
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: "Transparent background"
                                                color: Theme.onPrimaryContainerColor
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }

                                            Text {
                                                text: "Hide widget container fill"
                                                color: Theme.onPrimaryContainerColor
                                                opacity: 0.6
                                                font.pixelSize: 10
                                            }
                                        }

                                        PillSwitch {
                                            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                            checked: widgetWrapper.widgetData.transparentBg
                                            onToggled: (val) => root.updateWidgetTransparentBg(widgetId, val)
                                        }
                                    }

                                    // 2. Send to background (Wallpaper depth)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: "Send to background"
                                                color: Theme.onPrimaryContainerColor
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }

                                            Text {
                                                text: "Pass behind wallpaper scenery"
                                                color: Theme.onPrimaryContainerColor
                                                opacity: 0.6
                                                font.pixelSize: 10
                                            }
                                        }

                                        PillSwitch {
                                            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                            checked: widgetWrapper.widgetData.sendToBackground
                                            onToggled: (val) => root.updateWidgetSendToBackground(widgetId, val)
                                        }
                                    }
                                }
                            }

                            // 'x' Remove Button (Top-Right)
                            Rectangle {
                                id: removeBtn
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                width: 24
                                height: 24
                                radius: 12
                                z: 20
                                color: xMouse.containsMouse ? Theme.error : Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.85)
                                border.width: 1
                                border.color: xMouse.containsMouse ? Theme.error : Theme.outlineVariant

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: xMouse.containsMouse ? "white" : Theme.onPrimaryContainerColor
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                MouseArea {
                                    id: xMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeWidget(widgetId)
                                }
                            }

                            // Resize Grip (Bottom-Right)
                            Item {
                                id: resizeGrip
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: -4
                                anchors.bottomMargin: -4
                                width: 28
                                height: 28
                                z: 20

                                Rectangle {
                                    width: 16
                                    height: 16
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    color: gripMouse.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                                    radius: 3
                                    clip: true

                                    Canvas {
                                        anchors.fill: parent
                                        onPaint: {
                                            let ctx = getContext("2d");
                                            ctx.strokeStyle = Theme.inversePrimary;
                                            ctx.lineWidth = 1.5;
                                            ctx.beginPath();
                                            ctx.moveTo(3, 16); ctx.lineTo(16, 3);
                                            ctx.moveTo(8, 16); ctx.lineTo(16, 8);
                                            ctx.moveTo(13, 16); ctx.lineTo(16, 13);
                                            ctx.stroke();
                                        }
                                    }
                                }

                                MouseArea {
                                    id: gripMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.SizeFDiagCursor

                                    // Same reasoning as the drag area: track the pointer in the
                                    // stationary container's coordinates (this grip moves as the
                                    // widget resizes).
                                    property real pressSceneX: 0
                                    property real pressSceneY: 0

                                    onPressed: (mouse) => {
                                        let p = mapToItem(widgetsContainer, mouse.x, mouse.y);
                                        pressSceneX = p.x;
                                        pressSceneY = p.y;
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (!pressed) return;
                                        let p = mapToItem(widgetsContainer, mouse.x, mouse.y);
                                        let maxW = overlayWindow.screenW - widgetWrapper.baseX;
                                        let maxH = overlayWindow.screenH - widgetWrapper.baseY;
                                        let newW = Math.max(widgetWrapper.minW, Math.min(maxW, Math.round(widgetWrapper.baseW + (p.x - pressSceneX))));
                                        let newH = Math.max(widgetWrapper.minH, Math.min(maxH, Math.round(widgetWrapper.baseH + (p.y - pressSceneY))));
                                        widgetWrapper.resizeDW = newW - widgetWrapper.baseW;
                                        widgetWrapper.resizeDH = newH - widgetWrapper.baseH;
                                    }

                                    onReleased: widgetWrapper.commitGeometry()
                                    onCanceled: widgetWrapper.cancelGeometry()
                                }
                            }
                        }
                    }
                }

                // ── 3. Controls Window (Top-Right of primary screen) ──
                Rectangle {
                    id: controlsPanel
                    visible: overlayWindow.isPrimary
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 20
                    z: 100

                    implicitHeight: 46
                    width: controlsRow.implicitWidth + 28
                    radius: Theme.radiusSmall
                    color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.90)
                    border.width: 1
                    border.color: Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.5)

                    property bool addDropdownOpen: false

                    RowLayout {
                        id: controlsRow
                        anchors.centerIn: parent
                        spacing: 12

                        // Label
                        Text {
                            text: "Desktop Edit Mode"
                            color: Theme.onPrimaryContainerColor
                            font.family: "CaskaydiaCove Nerd Font Mono"
                            font.bold: true
                            font.pixelSize: 13
                        }

                        Rectangle {
                            width: 1
                            height: 20
                            color: Theme.outlineVariant
                            opacity: 0.5
                        }

                        // '+' Add widget button
                        Rectangle {
                            id: addBtn
                            width: 30
                            height: 30
                            radius: 15
                            readonly property var removedList: root.getRemovedWidgets()
                            readonly property bool canAdd: removedList.length > 0
                            opacity: canAdd ? 1.0 : 0.4
                            color: addMouse.containsMouse && canAdd ? Theme.primary : Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.15)
                            border.width: 1
                            border.color: Theme.onPrimaryContainerColor

                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                color: (addMouse.containsMouse && addBtn.canAdd) ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                font.pixelSize: 16
                                font.bold: true
                            }

                            MouseArea {
                                id: addMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: addBtn.canAdd
                                cursorShape: addBtn.canAdd ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: controlsPanel.addDropdownOpen = !controlsPanel.addDropdownOpen
                            }
                        }

                        // Discard Button
                        Button {
                            id: discardBtn
                            text: "Discard"
                            onClicked: root.discardAndClose()

                            contentItem: Text {
                                text: parent.text
                                color: Theme.onPrimaryContainerColor
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                implicitHeight: 30
                                implicitWidth: 70
                                color: discardBtn.down ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.25) : 
                                       (discardBtn.hovered ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.15) : "transparent")
                                radius: 15
                                border.width: 1
                                border.color: Theme.onPrimaryContainerColor
                            }
                        }

                        // Save Button
                        Button {
                            id: saveBtn
                            text: "Save"
                            onClicked: root.saveAndClose()

                            contentItem: Text {
                                text: parent.text
                                color: Theme.inversePrimary
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                implicitHeight: 30
                                implicitWidth: 64
                                color: Theme.primary
                                opacity: saveBtn.down ? 0.7 : (saveBtn.hovered ? 0.85 : 1.0)
                                radius: 15
                            }
                        }
                    }

                    // Add Widget Dropdown
                    Rectangle {
                        id: addDropdown
                        anchors.top: parent.bottom
                        anchors.right: parent.right
                        anchors.topMargin: 8
                        width: 170
                        visible: controlsPanel.addDropdownOpen && (root.getRemovedWidgets().length > 0)
                        radius: Theme.radiusSmall
                        color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.95)
                        border.width: 1
                        border.color: Theme.outlineVariant
                        implicitHeight: dropdownColumn.implicitHeight + 12

                        ColumnLayout {
                            id: dropdownColumn
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 4

                            Repeater {
                                model: root.getRemovedWidgets()

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: 28
                                    radius: 4
                                    color: dropItemMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Text {
                                            text: "+"
                                            color: Theme.primary
                                            font.bold: true
                                            font.pixelSize: 13
                                        }

                                        Text {
                                            text: modelData.name
                                            color: Theme.onPrimaryContainerColor
                                            font.pixelSize: 13
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: dropItemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.restoreWidget(modelData.id);
                                            if (root.getRemovedWidgets().length === 0) {
                                                controlsPanel.addDropdownOpen = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
