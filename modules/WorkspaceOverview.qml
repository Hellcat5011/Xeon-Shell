// ─────────────────────────────────────────────────────────────────────────
// WorkspaceOverview.qml — Hyprland workspace overview
//
// Fullscreen overlay displaying workspaces 1..N in a 2 x ceil(N/2) grid.
// Shows live window thumbnails (via ScreencopyView) and fallback cards.
// Supports clicking to switch/focus and dragging windows between workspaces.
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
    property bool shown: false
    property bool blocked: false

    function show() {
        if (blocked) return;
        targetScreen = HyprlandService.getFocusedScreen();
        HyprlandService.overviewOpen = true;
        HyprlandService.refreshAll();
        root.shown = true;
    }

    function hide() {
        root.shown = false;
        HyprlandService.overviewOpen = false;
    }

    function toggle() {
        if (shown) hide();
        else show();
    }

    // ---- Wayland layer-shell configuration -------------------------------
    screen: targetScreen
    property var targetScreen: (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "workspace-overview"

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: shown || closingTimer.running

    Timer {
        id: closingTimer
        interval: Theme.animMed + 60
    }

    onShownChanged: {
        if (shown) {
            overlayRoot.forceActiveFocus();
        } else {
            closingTimer.restart();
            overlayRoot.cancelDrag();
        }
    }

    onBlockedChanged: {
        if (blocked && shown) {
            hide();
        }
    }

    // ---- Overlay Root (Stationary coordinate reference for dragging) ----
    Item {
        id: overlayRoot
        anchors.fill: parent
        focus: root.shown

        // Escape closes overview
        Shortcut {
            sequence: "Escape"
            enabled: root.shown
            onActivated: root.hide()
        }
        Keys.onEscapePressed: root.hide()

        // ── 1. Scrim Backdrop ──
        Rectangle {
            id: scrim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.65)
            opacity: root.shown ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut }
            }

            // Clicking outside workspace grid closes overview
            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }
        }

        // ── 2. Grid Geometry Math ──
        readonly property int totalWorkspaces: Math.max(1, Math.min(20, Config.overviewWorkspaceCount || 8))
        readonly property int gridRows: 2
        readonly property int gridCols: Math.ceil(totalWorkspaces / gridRows)
        readonly property real gridSpacing: 16

        // Aspect ratio of the monitor
        readonly property real monAspect: (root.screen && root.screen.height > 0)
            ? (root.screen.width / root.screen.height)
            : (16 / 9)

        readonly property real availWidth: overlayRoot.width * 0.90
        readonly property real availHeight: overlayRoot.height * 0.84
        readonly property real headerHeight: 34

        // Sizing calculation that respects monitor aspect ratio
        readonly property real rawCellW: (availWidth - (gridCols - 1) * gridSpacing) / gridCols
        readonly property real rawContentH: rawCellW / monAspect
        readonly property real rawCellH: rawContentH + headerHeight

        readonly property bool heightIsConstraint: (rawCellH * gridRows + (gridRows - 1) * gridSpacing) > availHeight

        readonly property real cellHeight: heightIsConstraint
            ? ((availHeight - (gridRows - 1) * gridSpacing) / gridRows)
            : rawCellH
        readonly property real cellContentHeight: cellHeight - headerHeight
        readonly property real cellWidth: heightIsConstraint
            ? (cellContentHeight * monAspect)
            : rawCellW

        readonly property real gridTotalW: cellWidth * gridCols + (gridCols - 1) * gridSpacing
        readonly property real gridTotalH: cellHeight * gridRows + (gridRows - 1) * gridSpacing

        // ── 3. Drag and Drop Tracking State ──
        property bool isDragging: false
        property var activeDragItem: null
        property string draggedAddress: ""
        property string draggedTitle: ""
        property string draggedAppIcon: ""
        property int draggedSourceWs: -1
        property real dragProxyX: 0
        property real dragProxyY: 0
        property real dragProxyW: 0
        property real dragProxyH: 0
        property real dragOriginX: 0
        property real dragOriginY: 0
        property real grabOffsetX: 0
        property real grabOffsetY: 0
        property int hoveredDropWsId: -1

        function prepareDrag(winData, mapItem, mouse) {
            let p = mapItem.mapToItem(overlayRoot, mouse.x, mouse.y);
            let origin = mapItem.mapToItem(overlayRoot, 0, 0);
            dragOriginX = origin.x;
            dragOriginY = origin.y;
            grabOffsetX = p.x - origin.x;
            grabOffsetY = p.y - origin.y;
            dragProxyW = mapItem.width;
            dragProxyH = mapItem.height;
            dragProxyX = origin.x;
            dragProxyY = origin.y;
            draggedAddress = winData.address;
            draggedTitle = winData.title;
            draggedAppIcon = winData.appIcon;
            draggedSourceWs = winData.workspaceId;
            isDragging = false;
            hoveredDropWsId = -1;
        }

        function startDragging(winData) {
            isDragging = true;
            snapBackAnim.stop();
        }

        function updateDragPosition(px, py) {
            dragProxyX = px - grabOffsetX;
            dragProxyY = py - grabOffsetY;
            hoveredDropWsId = getWorkspaceAt(px, py);
        }

        function commitDrag() {
            if (!isDragging) return;
            let targetWs = hoveredDropWsId;
            let addr = draggedAddress;
            let srcWs = draggedSourceWs;

            if (targetWs > 0 && targetWs !== srcWs) {
                HyprlandService.moveWindowSilent(targetWs, addr);
                cancelDrag();
            } else {
                // Snap back animation
                snapBackAnim.restart();
            }
        }

        function cancelDrag() {
            isDragging = false;
            draggedAddress = "";
            hoveredDropWsId = -1;
        }

        function getWorkspaceAt(px, py) {
            for (let i = 0; i < gridRepeater.count; i++) {
                let cellItem = gridRepeater.itemAt(i);
                if (!cellItem) continue;
                let cellPos = cellItem.mapToItem(overlayRoot, 0, 0);
                if (px >= cellPos.x && px <= cellPos.x + cellItem.width &&
                    py >= cellPos.y && py <= cellPos.y + cellItem.height) {
                    return i + 1;
                }
            }
            return -1;
        }

        ParallelAnimation {
            id: snapBackAnim
            NumberAnimation {
                target: overlayRoot
                property: "dragProxyX"
                to: overlayRoot.dragOriginX
                duration: 160
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: overlayRoot
                property: "dragProxyY"
                to: overlayRoot.dragOriginY
                duration: 160
                easing.type: Easing.OutCubic
            }
            onFinished: overlayRoot.cancelDrag()
        }

        // ── 4. Centered Workspace Grid Container ──
        Item {
            id: gridContainer
            anchors.centerIn: parent
            width: overlayRoot.gridTotalW
            height: overlayRoot.gridTotalH

            // Swallow clicks in the grid padding area so they don't dismiss the scrim
            MouseArea {
                anchors.fill: parent
                onClicked: (mouse) => mouse.accepted = true
            }

            Grid {
                id: grid
                anchors.fill: parent
                columns: overlayRoot.gridCols
                rows: overlayRoot.gridRows
                spacing: overlayRoot.gridSpacing

                Repeater {
                    id: gridRepeater
                    model: overlayRoot.totalWorkspaces

                    delegate: Rectangle {
                        id: cell
                        property int wsId: index + 1

                        width: overlayRoot.cellWidth
                        height: overlayRoot.cellHeight
                        radius: Theme.radiusSmall
                        clip: true

                        // Real Hyprland workspace state
                        readonly property bool isCurrentWs: {
                            let rev = HyprlandService.stateRevision;
                            let fw = Hyprland.focusedWorkspace;
                            if (fw) {
                                let fid = fw.id === -1 ? parseInt(fw.name) : fw.id;
                                if (fid === wsId || fw.name === ("" + wsId)) return true;
                            }
                            for (let ws of Hyprland.workspaces.values) {
                                let id = ws.id === -1 ? parseInt(ws.name) : ws.id;
                                if (id === wsId && (ws.active || ws.focused)) return true;
                            }
                            return false;
                        }

                        readonly property bool isUrgentWs: {
                            let rev = HyprlandService.stateRevision;
                            for (let ws of Hyprland.workspaces.values) {
                                let id = ws.id === -1 ? parseInt(ws.name) : ws.id;
                                if (id === wsId && ws.urgent) return true;
                            }
                            return false;
                        }

                        readonly property bool isDropTarget: (overlayRoot.isDragging && overlayRoot.hoveredDropWsId === wsId)

                        // Styling
                        color: isDropTarget
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                            : (isCurrentWs
                                ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                                : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.70))

                        border.width: isDropTarget ? 3 : ((isCurrentWs || isUrgentWs) ? 2 : 1)
                        border.color: isDropTarget
                            ? Theme.primary
                            : (isUrgentWs ? Theme.error : (isCurrentWs ? Theme.primary : Theme.outlineVariant))

                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        // Click empty area to switch to this workspace
                        MouseArea {
                            anchors.fill: parent
                            z: 0
                            onClicked: {
                                HyprlandService.switchWorkspace(cell.wsId);
                                root.hide();
                            }
                        }

                        // ── Workspace Cell Header ──
                        Item {
                            id: cellHeader
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: overlayRoot.headerHeight
                            z: 5

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Text {
                                    text: "Workspace " + cell.wsId
                                    color: cell.isCurrentWs ? Theme.primary : Theme.surfaceText
                                    font.pixelSize: 13
                                    font.bold: cell.isCurrentWs
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Active pill badge
                                Rectangle {
                                    visible: cell.isCurrentWs
                                    implicitHeight: 18
                                    implicitWidth: activeLabel.implicitWidth + 10
                                    radius: 9
                                    color: Theme.primary
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        id: activeLabel
                                        anchors.centerIn: parent
                                        text: "Active"
                                        color: Theme.inversePrimary
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }

                                // Urgent pill badge
                                Rectangle {
                                    visible: cell.isUrgentWs
                                    implicitHeight: 18
                                    implicitWidth: urgentLabel.implicitWidth + 10
                                    radius: 9
                                    color: Theme.error
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        id: urgentLabel
                                        anchors.centerIn: parent
                                        text: "Urgent"
                                        color: Theme.inversePrimary
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Window count indicator
                                Text {
                                    text: cellWindowArea.cellWindows.length > 0 ? (cellWindowArea.cellWindows.length + " win") : "empty"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            // Subtle divider line
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: Theme.outlineVariant
                                opacity: 0.5
                            }
                        }

                        // ── Workspace Window Thumbnails Area ──
                        Item {
                            id: cellWindowArea
                            anchors.top: cellHeader.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 4
                            clip: true
                            z: 2

                            // Collect windows belonging to this workspace (excluding negative/special IDs)
                            readonly property var cellWindows: {
                                let rev = HyprlandService.stateRevision;
                                let list = [];
                                for (let tl of Hyprland.toplevels.values) {
                                    let ipc = tl.lastIpcObject;
                                    if (!ipc || ipc.mapped === false || ipc.hidden === true) continue;
                                    let wId = ipc.workspace ? ipc.workspace.id : 0;
                                    let wName = ipc.workspace ? ipc.workspace.name : "";
                                    if (wId < 0 || wName.startsWith("special:")) continue;

                                    let matches = (wId === cell.wsId) || (wName === ("" + cell.wsId));
                                    if (!matches && tl.workspace) {
                                        let tid = tl.workspace.id === -1 ? parseInt(tl.workspace.name) : tl.workspace.id;
                                        matches = (tid === cell.wsId) || (tl.workspace.name === ("" + cell.wsId));
                                    }

                                    if (matches) {
                                        list.push(tl);
                                    }
                                }
                                // Sort: tiled first, floating above tiled
                                list.sort((a, b) => {
                                    let aFloat = (a.lastIpcObject && a.lastIpcObject.floating) ? 1 : 0;
                                    let bFloat = (b.lastIpcObject && b.lastIpcObject.floating) ? 1 : 0;
                                    return aFloat - bFloat;
                                });
                                return list;
                            }

                            // Monitor geometry for scaling
                            readonly property var targetMon: HyprlandService.getMonitorForWorkspace(cell.wsId)
                            readonly property real monW: (targetMon && targetMon.width > 0) ? targetMon.width : (root.screen ? root.screen.width : 2560)
                            readonly property real monH: (targetMon && targetMon.height > 0) ? targetMon.height : (root.screen ? root.screen.height : 1440)
                            readonly property real monX: targetMon ? targetMon.x : 0
                            readonly property real monY: targetMon ? targetMon.y : 0

                            Repeater {
                                model: cellWindowArea.cellWindows

                                delegate: Item {
                                    id: winItem
                                    property var tl: modelData
                                    property var ipc: tl.lastIpcObject || ({})

                                    readonly property real geomX: (ipc.at && ipc.at.length > 0) ? ipc.at[0] : 0
                                    readonly property real geomY: (ipc.at && ipc.at.length > 1) ? ipc.at[1] : 0
                                    readonly property real geomW: (ipc.size && ipc.size.length > 0) ? ipc.size[0] : 100
                                    readonly property real geomH: (ipc.size && ipc.size.length > 1) ? ipc.size[1] : 100

                                    // Offset relative to that workspace's monitor and scale to cell
                                    readonly property real relX: Math.max(0, Math.min(1, (geomX - cellWindowArea.monX) / cellWindowArea.monW))
                                    readonly property real relY: Math.max(0, Math.min(1, (geomY - cellWindowArea.monY) / cellWindowArea.monH))
                                    readonly property real relW: Math.max(0.05, Math.min(1, geomW / cellWindowArea.monW))
                                    readonly property real relH: Math.max(0.05, Math.min(1, geomH / cellWindowArea.monH))

                                    x: Math.round(relX * cellWindowArea.width)
                                    y: Math.round(relY * cellWindowArea.height)
                                    width: Math.max(28, Math.round(relW * cellWindowArea.width))
                                    height: Math.max(24, Math.round(relH * cellWindowArea.height))

                                    // Floating windows above tiled
                                    z: (ipc.floating ? 2 : 1)

                                    // Dim if currently being dragged
                                    opacity: (overlayRoot.isDragging && overlayRoot.draggedAddress === tl.address) ? 0.25 : 1.0

                                    readonly property var winData: ({
                                        address: tl.address,
                                        title: tl.title || ipc.title || "Window",
                                        winClass: ipc.class || "",
                                        appIcon: AppInfo.getAppIcon(ipc.class || ""),
                                        workspaceId: cell.wsId
                                    })

                                    // Card frame
                                    Rectangle {
                                        id: cardBackground
                                        anchors.fill: parent
                                        radius: 6
                                        clip: true
                                        color: Theme.surface
                                        border.width: winHover.containsMouse ? 2 : 1
                                        border.color: winHover.containsMouse ? Theme.primary : Theme.outlineVariant

                                        // ── Fallback Card (ALWAYS underneath ScreencopyView) ──
                                        Rectangle {
                                            anchors.fill: parent
                                            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.90)

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                anchors.margins: 4
                                                spacing: 2
                                                width: Math.min(parent.width - 6, implicitWidth)

                                                IconImage {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    width: Math.min(28, Math.max(16, winItem.height / 3))
                                                    height: width
                                                    source: Quickshell.iconPath(winItem.winData.appIcon)
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: winItem.winData.title
                                                    font.pixelSize: 10
                                                    color: Theme.surfaceText
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideRight
                                                    visible: winItem.height >= 44 && winItem.width >= 50
                                                }
                                            }
                                        }

                                        // ── Live ScreencopyView (Created ONLY while overview is shown) ──
                                        Loader {
                                            anchors.fill: parent
                                            active: root.shown && tl.wayland != null
                                            sourceComponent: ScreencopyView {
                                                id: scView
                                                anchors.fill: parent
                                                captureSource: winItem.tl.wayland
                                                live: true
                                                // Only show when valid content is reported
                                                visible: hasContent
                                            }
                                        }

                                        // Subtle window border overlay
                                        Rectangle {
                                            anchors.fill: parent
                                            color: "transparent"
                                            radius: 6
                                            border.width: winHover.containsMouse ? 2 : 1
                                            border.color: winHover.containsMouse ? Theme.primary : Qt.rgba(0, 0, 0, 0.25)
                                        }
                                    }

                                    // ── Interaction: Click to focus / Drag to move ──
                                    MouseArea {
                                        id: winHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: overlayRoot.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                                        property real pressSceneX: 0
                                        property real pressSceneY: 0
                                        property bool movedBeyondThreshold: false

                                        onPressed: (mouse) => {
                                            movedBeyondThreshold = false;
                                            let p = mapToItem(overlayRoot, mouse.x, mouse.y);
                                            pressSceneX = p.x;
                                            pressSceneY = p.y;
                                            overlayRoot.prepareDrag(winItem.winData, winItem, mouse);
                                        }

                                        onPositionChanged: (mouse) => {
                                            if (!pressed) return;
                                            let p = mapToItem(overlayRoot, mouse.x, mouse.y);
                                            if (!movedBeyondThreshold) {
                                                if (Math.hypot(p.x - pressSceneX, p.y - pressSceneY) > 6) {
                                                    movedBeyondThreshold = true;
                                                    overlayRoot.startDragging(winItem.winData);
                                                }
                                            }
                                            if (movedBeyondThreshold) {
                                                overlayRoot.updateDragPosition(p.x, p.y);
                                            }
                                        }

                                        onReleased: (mouse) => {
                                            if (!movedBeyondThreshold) {
                                                // Pure click: focus window and close overview
                                                HyprlandService.focusWindow(winItem.winData.address, winItem.winData.workspaceId);
                                                root.hide();
                                                overlayRoot.cancelDrag();
                                            } else {
                                                overlayRoot.commitDrag();
                                            }
                                        }

                                        onCanceled: {
                                            overlayRoot.cancelDrag();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 5. Drag Proxy (Raised to the very top of overlay, unclipped) ──
        Rectangle {
            id: dragProxy
            visible: overlayRoot.isDragging || snapBackAnim.running
            x: overlayRoot.dragProxyX
            y: overlayRoot.dragProxyY
            width: overlayRoot.dragProxyW
            height: overlayRoot.dragProxyH
            radius: 6
            color: Theme.surface
            border.width: 2
            border.color: Theme.primary
            z: 99999

            layer.enabled: true

            RowLayout {
                anchors.centerIn: parent
                anchors.margins: 4
                spacing: 6
                width: Math.min(parent.width - 8, implicitWidth)

                IconImage {
                    width: Math.min(28, Math.max(16, parent.height - 8))
                    height: width
                    source: Quickshell.iconPath(overlayRoot.draggedAppIcon || "application-x-executable")
                }

                Text {
                    Layout.fillWidth: true
                    text: overlayRoot.draggedTitle || ""
                    color: Theme.surfaceText
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: parent.width > 50
                }
            }
        }
    }
}
