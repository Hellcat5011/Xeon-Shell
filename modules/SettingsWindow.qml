import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../services"

OverlayWindow {
    id: root
    panelWidth: 860
    panelHeight: 620
    hasBorder: true

    property bool editModeActive: false
    signal requestEditMode()

    // ── Screenshot settings ──
    // These are stored by scripts/screenshot-config.sh (not in Config), so the
    // tab keeps its own saved/draft copies and joins the normal Save / unsaved-
    // changes flow.
    property string ssDir: ""
    property string recDir: ""
    property string draftSsDir: ""
    property string draftRecDir: ""
    readonly property bool screenshotDirty: draftSsDir !== ssDir || draftRecDir !== recDir
    readonly property bool hasUnsavedChanges: Config.isDirty || screenshotDirty

    function show() {
        if (editModeActive) return;
        root.shown = true;
    }

    function toggle() {
        if (editModeActive) return;
        root.shown = !root.shown;
    }

    // Open the window (if needed) and jump straight to a tab.
    function openTab(index) {
        if (editModeActive) return;
        if (!root.shown) root.shown = true;   // onShownChanged resets state first
        tabList.currentIndex = index;
    }

    function showScreenshotTab() { openTab(5) }

    function loadScreenshotConfig() { screenshotConfigReader.running = true }

    function discardScreenshotDraft() {
        draftSsDir = ssDir;
        draftRecDir = recDir;
    }

    function saveScreenshotConfig() {
        if (!screenshotDirty) return;
        // Mark as saved immediately so the dirty check (and the popup Save flow) settles at once
        ssDir = draftSsDir;
        recDir = draftRecDir;
        screenshotConfigWriter.command = [
            "sh", "-c",
            'sh "$1" write screenshotDir "$2" && sh "$1" write recordingDir "$3"',
            "_", Quickshell.shellDir + "/scripts/screenshot-config.sh", ssDir, recDir
        ];
        screenshotConfigWriter.running = true;
    }

    Process {
        id: screenshotConfigReader
        command: ["sh", Quickshell.shellDir + "/scripts/screenshot-config.sh", "read"]
        property string jsonContent: ""

        onRunningChanged: {
            if (running) {
                jsonContent = "";
            } else if (jsonContent.trim().length > 0) {
                try {
                    let c = JSON.parse(jsonContent);
                    root.ssDir = c.screenshotDir || "";
                    root.recDir = c.recordingDir || "";
                    root.draftSsDir = root.ssDir;
                    root.draftRecDir = root.recDir;
                } catch (e) {
                    console.warn("SettingsWindow: could not parse screenshot config -", e);
                }
            }
        }
        stdout: SplitParser { onRead: data => { screenshotConfigReader.jsonContent += data + "\n" } }
    }

    Process {
        id: screenshotConfigWriter
        onExited: (code) => {
            if (code !== 0) {
                applyProc.success = false;
                applyProc.resultMessage = "Could not save screenshot settings.";
                messageTimer.restart();
            }
        }
    }

    Process {
        id: ssPickerProcess
        property string selectedPath: ""
        onRunningChanged: { if (running) selectedPath = "" }
        onExited: (exitCode) => {
            if (exitCode === 0 && selectedPath.trim().length > 0)
                root.draftSsDir = selectedPath.trim();
        }
        stdout: SplitParser { onRead: data => { ssPickerProcess.selectedPath += data } }
    }

    Process {
        id: recPickerProcess
        property string selectedPath: ""
        onRunningChanged: { if (running) selectedPath = "" }
        onExited: (exitCode) => {
            if (exitCode === 0 && selectedPath.trim().length > 0)
                root.draftRecDir = selectedPath.trim();
        }
        stdout: SplitParser { onRead: data => { recPickerProcess.selectedPath += data } }
    }

    function fuzzyMatch(pattern, str) {
        pattern = pattern.toLowerCase().trim();
        str = str.toLowerCase();
        if (pattern === "") return true;
        
        let words = pattern.split(/\s+/);
        for (let i = 0; i < words.length; i++) {
            if (str.indexOf(words[i]) === -1) {
                return false;
            }
        }
        return true;
    }

    property var searchIndex: [
        "Wallpaper Wallpaper Directory The absolute path to the directory containing your wallpaper images. Wallpaper Daemon The backend service used to set and render your desktop wallpapers. Wallpaper Depth Makes desktop widgets pass behind wallpaper foregrounds. Status Active Device Install Install GPU support Compute device Generate automatically Pre-generate Foreground threshold Edge feather Generate now Clear cache",
        "Lock Screen Lockscreen Power Menu Allow session control actions (Suspend, Reboot, Shutdown) directly from the lockscreen. Lockscreen Alignment Position the lockscreen elements aligned to the left or right edge of the screen.",
        "Greeter Remember Last User Save the last logged-in user and session to automatically pre-select them on the next boot.",
        "Display Global font Select a global font for the shell and desktop widgets. Manage idle behavior Automatically lock the screen when the system is idle. Lock timeout Time in minutes before the screen is locked. Blue Light Filter Toggle the blue light filter (night light). Turn on now Manually force the blue light filter on. Mode Fixed Time, Sunset/Sunrise Night Schedule Night starts Night ends The filter is active between these times Coordinates Use realtime location based on IP Transition Duration Time in minutes for the color temperature to transition. Day Temperature Color temperature during the day (K). Night Temperature Color temperature at night (K).",
        "Desktop Desktop Edit Mode Reposition, resize, remove and re-add desktop widgets. Window Rounding Corner radius Manual rounding Set manual pixel number Set the rounding value for the UI",
        "Screenshot Screenshot Directory The folder where screenshots are saved. Recording Directory The folder where screen recordings are saved."
    ]

    function commitChanges(isFromPopup) {
        let needsGreeterSync = (Config.draftLockscreenAlignment !== Config.lockscreenAlignment) || (Config.draftRememberLastUser !== Config.rememberLastUser);
        Config.save();
        root.saveScreenshotConfig();
        
        if (needsGreeterSync) {
            applyProc.isPopup = isFromPopup;
            applyProc.command = ["python3", Quickshell.shellDir + "/scripts/write-greeter-snapshot.py", "--alignment", Config.lockscreenAlignment, "--remember", (Config.rememberLastUser ? "true" : "false")]
            applyProc.running = true;
        } else {
            if (isFromPopup) {
                unsavedPopup.visible = false;
                root.hide();
            } else {
                applyProc.success = true;
                applyProc.resultMessage = "Settings saved.";
                messageTimer.start();
            }
        }
    }

    function requestClose() {
        if (root.hasUnsavedChanges) {
            unsavedPopup.visible = true
        } else {
            root.hide()
        }
    }

    onVisibleChanged: {
        if (!visible && root.hasUnsavedChanges) {
            visible = true
            requestClose()
        }
    }

    onShownChanged: {
        if (shown) {
            if (editModeActive) {
                shown = false
                return
            }
            Config.discard()
            root.discardScreenshotDraft()
            root.loadScreenshotConfig()
            keyHandler.forceActiveFocus()
            if (searchField) searchField.text = ""
        }
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (unsavedPopup.visible) {
                    event.accepted = true
                } else {
                    keyHandler.forceActiveFocus()
                    root.requestClose()
                    event.accepted = true
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // ── LEFT SIDEBAR (Tabs) ──
            ColumnLayout {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                spacing: 16

                // Search Bar
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search"
                    color: Theme.onPrimaryContainerColor
                    font.pixelSize: 14
                    leftPadding: 32
                    rightPadding: 16
                    topPadding: 8
                    bottomPadding: 8
                    
                    onTextChanged: {
                        if (text.trim() !== "") {
                            for (let i = 0; i < root.searchIndex.length; i++) {
                                if (root.fuzzyMatch(text, root.searchIndex[i])) {
                                    tabList.currentIndex = i;
                                    break;
                                }
                            }
                        }
                    }
                    
                    background: Item {
                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.onPrimaryContainerColor
                            opacity: 0.15
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.primary
                            opacity: (parent.parent.activeFocus || parent.parent.hovered) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }
                    
                    Text {
                        text: "⚲"
                        font.pixelSize: 16
                        color: Theme.onPrimaryContainerColor
                        opacity: 0.5
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        rotation: -45
                    }
                }

                // Tabs List
                ListView {
                    id: tabList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: ["Wallpaper", "Lock Screen", "Greeter", "Display", "Desktop", "Screenshot"]
                    currentIndex: 0
                    
                    delegate: Item {
                        property bool isMatch: root.fuzzyMatch(searchField.text, root.searchIndex[index])
                        visible: isMatch
                        width: ListView.view.width
                        height: isMatch ? 38 : 0
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            radius: 8
                            color: Theme.onPrimaryContainerColor
                            opacity: tabList.currentIndex === index ? 0.85 : (mArea.containsMouse ? 0.15 : 0.0)
                            layer.enabled: true
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: modelData
                            color: tabList.currentIndex === index ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                            font.pixelSize: 14
                            font.weight: tabList.currentIndex === index ? Font.DemiBold : Font.Normal
                        }
                        
                        MouseArea {
                            id: mArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: parent.ListView.view.currentIndex = index
                        }
                    }
                }
            }

            // ── RIGHT CONTENT PANE ──
            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 600
                Layout.fillHeight: true
                
                // Background Card
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusLarge
                    color: "black"
                    opacity: 0.25
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusLarge
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.45)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 24

                    // ── Header ──
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Text {
                            text: "⚙  " + ["Wallpaper Settings", "Lock Screen Settings", "Greeter Settings", "Display Settings", "Desktop Settings", "Screenshot Settings"][tabList.currentIndex]
                            color: Theme.onPrimaryContainerColor
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Close button
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: closeMouse.containsMouse ? Theme.error : "transparent"
                            opacity: closeMouse.containsMouse ? 0.8 : 1.0
                            border.width: 1
                            border.color: closeMouse.containsMouse ? "transparent" : Theme.outlineVariant
                            layer.enabled: true
                            
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: closeMouse.containsMouse ? "white" : Theme.onPrimaryContainerColor
                                font.pixelSize: 14
                            }
                            
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.requestClose()
                            }
                        }
                    }

                    // ── Thin Separator ──
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.outlineVariant
                        opacity: 0.3
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            // ── PAGE 0: Wallpaper ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 24
                                visible: tabList.currentIndex === 0
                        
                        // Setting: Wallpaper Directory
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Wallpaper Directory The absolute path to the directory containing your wallpaper images.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Wallpaper Directory"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "The absolute path to the directory containing your wallpaper images."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            TextField {
                                Layout.preferredWidth: 150
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                text: Config.draftWallpaperDir
                                color: Theme.onPrimaryContainerColor
                                font.pixelSize: 14
                                leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                background: Rectangle {
                                    color: Theme.primary; opacity: 0.1; radius: 20
                                    border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                }
                                onTextEdited: Config.draftWallpaperDir = text
                                onEditingFinished: Config.draftWallpaperDir = text
                            }
                        }

                        // Setting: Wallpaper Daemon
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Wallpaper Daemon The backend service used to set and render your desktop wallpapers.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Wallpaper Daemon"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "The backend service used to set and render your desktop wallpapers."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            StyledComboBox {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                model: ["awww", "swww", "hyprpaper"]
                                currentIndex: model.indexOf(Config.draftWallpaperDaemon)
                                onActivated: Config.draftWallpaperDaemon = model[currentIndex]
                            }
                        }

                        // Setting: Wallpaper Depth (Master Toggle)
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Wallpaper Depth Makes desktop widgets pass behind wallpaper foregrounds.")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Wallpaper Depth"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Makes desktop widgets pass behind wallpaper foregrounds."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftDepthEffectEnabled
                                onToggled: (value) => Config.draftDepthEffectEnabled = value
                            }
                        }

                        // Child Setting 1: Status & Active Device
                        RowLayout {
                            visible: Config.draftDepthEffectEnabled && root.fuzzyMatch(searchField.text, "Status Active Device")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Status & Device"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text {
                                    text: "Status: " + (DepthService.installed ? DepthService.statusText : "Not installed") + " • Device: " + DepthService.activeDevice + " • Cache: " + DepthService.cacheSizeFormatted
                                    color: Theme.onPrimaryContainerColor
                                    opacity: 0.7
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            Row {
                                spacing: 8
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

                                Button {
                                    text: DepthService.installed ? "Reinstall CPU (~120 MB)" : "Install (~120 MB)"
                                    enabled: !DepthService.busy
                                    onClicked: DepthService.install(false)
                                    contentItem: Text {
                                        text: parent.text; color: Theme.onPrimaryContainerColor; font.pixelSize: 12; font.weight: Font.Medium
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 30; implicitWidth: 140
                                        color: parent.down ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) :
                                               (parent.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12))
                                        radius: 15; border.width: 1; border.color: Theme.primary
                                    }
                                }

                                Button {
                                    visible: DepthService.hasNvidiaGpu
                                    text: "Install GPU support (~1.5 GB)"
                                    enabled: !DepthService.busy
                                    onClicked: DepthService.install(true)
                                    contentItem: Text {
                                        text: parent.text; color: Theme.onPrimaryContainerColor; font.pixelSize: 12; font.weight: Font.Medium
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 30; implicitWidth: 175
                                        color: parent.down ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) :
                                               (parent.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12))
                                        radius: 15; border.width: 1; border.color: Theme.primary
                                    }
                                }
                            }
                        }

                        // Child Setting 2: Compute Device
                        RowLayout {
                            visible: Config.draftDepthEffectEnabled && root.fuzzyMatch(searchField.text, "Compute device")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Compute Device"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Select execution provider for neural depth estimation."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            StyledComboBox {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                model: DepthService.gpuInstalled ? ["cpu", "auto", "gpu"] : ["cpu"]
                                currentIndex: Math.max(0, model.indexOf(Config.draftDepthDevice))
                                onActivated: Config.draftDepthDevice = model[currentIndex]
                            }
                        }

                        // Child Setting 3: Generate automatically
                        RowLayout {
                            visible: Config.draftDepthEffectEnabled && root.fuzzyMatch(searchField.text, "Generate automatically")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Generate automatically"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Automatically generate mask when wallpaper or parameters change."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftDepthAutoGenerate
                                onToggled: (value) => Config.draftDepthAutoGenerate = value
                            }
                        }

                        // Child Setting 4: Pre-generate for all wallpapers
                        RowLayout {
                            visible: Config.draftDepthEffectEnabled && root.fuzzyMatch(searchField.text, "Pre-generate")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Pre-generate wallpapers"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text {
                                    text: DepthService.queueProgress !== ""
                                        ? DepthService.queueProgress
                                        : "Pre-generate masks in the background so wallpaper switches are instant."
                                    color: DepthService.queueProgress !== "" ? Theme.primary : Theme.onPrimaryContainerColor
                                    opacity: DepthService.queueProgress !== "" ? 1.0 : 0.6
                                    font.pixelSize: 12
                                    font.weight: DepthService.queueProgress !== "" ? Font.Medium : Font.Normal
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftDepthPregenerate
                                onToggled: (value) => Config.draftDepthPregenerate = value
                            }
                        }

                        // Child Setting 5: Foreground threshold
                        RowLayout {
                            visible: Config.draftDepthEffectEnabled && root.fuzzyMatch(searchField.text, "Foreground threshold")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Foreground Threshold (" + Config.draftDepthThreshold + "%)"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Lower threshold = more of the scene in front of widgets."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            Slider {
                                Layout.preferredWidth: 150
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                from: 0
                                to: 100
                                stepSize: 1
                                value: Config.draftDepthThreshold
                                onValueChanged: Config.draftDepthThreshold = Math.round(value)
                            }
                        }

                        // Child Setting 6: Edge feather
                        RowLayout {
                            visible: Config.draftDepthEffectEnabled && root.fuzzyMatch(searchField.text, "Edge feather")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Edge Feather (" + Config.draftDepthFeather + ")"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Transition smoothness between foreground and background (0-50)."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            Slider {
                                Layout.preferredWidth: 150
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                from: 0
                                to: 50
                                stepSize: 1
                                value: Config.draftDepthFeather
                                onValueChanged: Config.draftDepthFeather = Math.round(value)
                            }
                        }

                        // Child Setting 7: Actions: Generate now & Clear cache
                        RowLayout {
                            visible: Config.draftDepthEffectEnabled && root.fuzzyMatch(searchField.text, "Generate now Clear cache")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Depth Actions"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Manually generate mask for current wallpaper or clear cached files."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            Row {
                                spacing: 8
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

                                Button {
                                    text: "Generate now"
                                    enabled: DepthService.installed && !DepthService.busy
                                    onClicked: DepthService.generateForCurrentWallpaper(true)
                                    contentItem: Text {
                                        text: parent.text; color: Theme.onPrimaryContainerColor; font.pixelSize: 12; font.weight: Font.Medium
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 30; implicitWidth: 105
                                        color: parent.down ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) :
                                               (parent.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12))
                                        radius: 15; border.width: 1; border.color: Theme.primary
                                    }
                                }

                                Button {
                                    text: "Clear cache"
                                    enabled: !DepthService.busy
                                    onClicked: DepthService.clearCache()
                                    contentItem: Text {
                                        text: parent.text; color: Theme.onPrimaryContainerColor; font.pixelSize: 12; font.weight: Font.Medium
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        implicitHeight: 30; implicitWidth: 95
                                        color: parent.down ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.35) :
                                               (parent.hovered ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.2) : "transparent")
                                        radius: 15; border.width: 1; border.color: Theme.outlineVariant
                                    }
                                }
                            }
                        }
                        
                            }

                            // ── PAGE 1: Lock Screen ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 24
                                visible: tabList.currentIndex === 1
                        
                        // Setting: Lockscreen Power Menu
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Lockscreen Power Menu Allow session control actions (Suspend, Reboot, Shutdown) directly from the lockscreen.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Lockscreen Power Menu"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Allow session control actions (Suspend, Reboot, Shutdown) directly from the lockscreen."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftShowLockscreenSessionControls
                                onToggled: (value) => Config.draftShowLockscreenSessionControls = value
                            }
                        }

                        // Setting: Lockscreen Alignment
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Lockscreen Alignment Position the lockscreen elements aligned to the left or right edge of the screen.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Lockscreen Alignment"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Position the lockscreen elements aligned to the left or right edge of the screen."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            StyledComboBox {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                model: ["left", "right"]
                                currentIndex: model.indexOf(Config.draftLockscreenAlignment)
                                onActivated: Config.draftLockscreenAlignment = model[currentIndex]
                                font.capitalization: Font.Capitalize
                            }
                        }

                            }

                            // ── PAGE 2: Greeter ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 24
                                visible: tabList.currentIndex === 2
                        
                        // Setting: Remember Last User
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Remember Last User Save the last logged-in user and session to automatically pre-select them on the next boot.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Remember Last User"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Save the last logged-in user and session to automatically pre-select them on the next boot. (Note: changes apply after next greeter sync)"; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftRememberLastUser
                                onToggled: (value) => Config.draftRememberLastUser = value
                            }
                        }
                        
                            }

                            // ── PAGE 3: Display ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 24
                                visible: tabList.currentIndex === 3

                        // Setting: Global font
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Global font Select a global font for the shell and desktop widgets.")
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Global font"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Select a global font for the shell and desktop widgets."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }

                            StyledComboBox {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                Layout.preferredWidth: 220
                                searchable: true
                                searchPlaceholder: "Search fonts..."
                                model: Theme.availableFonts
                                currentIndex: {
                                    let cur = Config.draftGlobalFont || Config.globalFont || "System Default";
                                    let idx = Theme.availableFonts.indexOf(cur);
                                    return idx >= 0 ? idx : 0;
                                }
                                onActivated: {
                                    Config.draftGlobalFont = model[currentIndex];
                                }
                            }
                        }

                        // Setting: Manage idle behavior
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Manage idle behavior Automatically lock the screen when the system is idle.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Manage idle behavior"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Automatically lock the screen when the system is idle."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftManageIdle
                                onToggled: (value) => Config.draftManageIdle = value
                            }
                        }

                        // Setting: Lock timeout
                        RowLayout {
                            visible: Config.draftManageIdle && root.fuzzyMatch(searchField.text, "Lock timeout Time in minutes before the screen is locked.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Lock timeout (minutes)"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Time in minutes before the screen is locked. (will restart shell)"; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            TextField {
                                id: idleTimeoutField
                                Layout.preferredWidth: 60
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                text: Config.draftIdleTimeout.toString()
                                validator: IntValidator { bottom: 1; top: 120 }
                                color: Theme.onPrimaryContainerColor
                                font.pixelSize: 14
                                leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                background: Rectangle {
                                    color: Theme.primary; opacity: 0.1; radius: 20
                                    border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                }
                                onTextEdited: {
                                    let val = parseInt(text);
                                    if (!isNaN(val) && val >= 1) Config.draftIdleTimeout = val;
                                }
                                onEditingFinished: {
                                    let val = parseInt(text);
                                    if (!isNaN(val) && val >= 1) {
                                        Config.draftIdleTimeout = val;
                                    }
                                }
                                
                                Connections {
                                    target: root
                                    function onVisibleChanged() {
                                        if (root.visible) {
                                            idleTimeoutField.text = Qt.binding(function() { return Config.draftIdleTimeout.toString() });
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Setting: Blue Light Filter
                        RowLayout {
                            visible: root.fuzzyMatch(searchField.text, "Blue Light Filter Toggle the blue light filter (night light).")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Blue Light Filter"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Adjust display color temperature based on time or location."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftBlueLightEnabled
                                onToggled: (value) => Config.draftBlueLightEnabled = value
                            }
                        }

                        // Setting: Turn on now
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && root.fuzzyMatch(searchField.text, "Turn on now Manually force the blue light filter on.")
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Turn on now"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Manually force the blue light filter on."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            PillSwitch {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                checked: Config.draftBlueLightManualOn
                                onToggled: (value) => Config.draftBlueLightManualOn = value
                            }
                        }

                        // Setting: Mode
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && root.fuzzyMatch(searchField.text, "Mode Fixed Time, Sunset/Sunrise.")
                            enabled: !Config.draftBlueLightManualOn
                            opacity: enabled ? 1.0 : 0.4
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Mode"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "How to determine day and night cycles."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            StyledComboBox {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                model: ["Fixed Time", "Sunset/Sunrise"]
                                currentIndex: (Config.draftBlueLightMode === "fixed_time" || Config.draftBlueLightMode === "time") ? 0 : 1
                                onActivated: {
                                    if (currentIndex === 0) Config.draftBlueLightMode = "fixed_time";
                                    else Config.draftBlueLightMode = "sunset_sunrise";
                                }
                            }
                        }

                        // Setting: Night Schedule (Night Start / Night End for Fixed Time mode)
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && (Config.draftBlueLightMode === "fixed_time" || Config.draftBlueLightMode === "time") && root.fuzzyMatch(searchField.text, "Night Schedule Night starts Night ends The filter is active between these times")
                            enabled: !Config.draftBlueLightManualOn
                            opacity: enabled ? 1.0 : 0.4
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Night Schedule"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "The filter is active between these times (HH:MM). Overnight windows like 22:00 → 06:00 are supported."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                spacing: 8
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "Night starts"; color: Theme.onPrimaryContainerColor; opacity: 0.5; font.pixelSize: 11 }
                                    TextField {
                                        id: blueLightNightStartField
                                        Layout.preferredWidth: 80
                                        text: Config.draftBlueLightNightStart
                                        placeholderText: "22:00"
                                        color: {
                                            let t = text.trim();
                                            if (t === "") return Theme.onPrimaryContainerColor;
                                            let re = /^\d{1,2}:\d{2}$/;
                                            if (!re.test(t)) return Theme.error;
                                            let p = t.split(":");
                                            let h = parseInt(p[0],10), m = parseInt(p[1],10);
                                            if (isNaN(h)||isNaN(m)||h<0||h>23||m<0||m>59) return Theme.error;
                                            return Theme.onPrimaryContainerColor;
                                        }
                                        font.pixelSize: 14
                                        leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                        background: Rectangle {
                                            color: Theme.primary; opacity: 0.1; radius: 20
                                            border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                        }
                                        onTextEdited: {
                                            let t = text.trim();
                                            let re = /^\d{1,2}:\d{2}$/;
                                            if (re.test(t)) {
                                                let p = t.split(":");
                                                let h = parseInt(p[0],10), m = parseInt(p[1],10);
                                                if (!isNaN(h) && !isNaN(m) && h>=0 && h<=23 && m>=0 && m<=59) {
                                                    Config.draftBlueLightNightStart = t;
                                                }
                                            }
                                        }
                                        onEditingFinished: {
                                            let t = text.trim();
                                            let re = /^\d{1,2}:\d{2}$/;
                                            if (re.test(t)) {
                                                let p = t.split(":");
                                                let h = parseInt(p[0],10), m = parseInt(p[1],10);
                                                if (!isNaN(h) && !isNaN(m) && h>=0 && h<=23 && m>=0 && m<=59) {
                                                    Config.draftBlueLightNightStart = t;
                                                } else {
                                                    text = Config.draftBlueLightNightStart;
                                                }
                                            } else {
                                                text = Config.draftBlueLightNightStart;
                                            }
                                        }
                                        Connections {
                                            target: root
                                            function onVisibleChanged() {
                                                if (root.visible) {
                                                    blueLightNightStartField.text = Qt.binding(function() { return Config.draftBlueLightNightStart; });
                                                }
                                            }
                                        }
                                    }
                                }
                                Text { text: "→"; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 13; Layout.alignment: Qt.AlignVCenter }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "Night ends"; color: Theme.onPrimaryContainerColor; opacity: 0.5; font.pixelSize: 11 }
                                    TextField {
                                        id: blueLightNightEndField
                                        Layout.preferredWidth: 80
                                        text: Config.draftBlueLightNightEnd
                                        placeholderText: "06:00"
                                        color: {
                                            let t = text.trim();
                                            if (t === "") return Theme.onPrimaryContainerColor;
                                            let re = /^\d{1,2}:\d{2}$/;
                                            if (!re.test(t)) return Theme.error;
                                            let p = t.split(":");
                                            let h = parseInt(p[0],10), m = parseInt(p[1],10);
                                            if (isNaN(h)||isNaN(m)||h<0||h>23||m<0||m>59) return Theme.error;
                                            return Theme.onPrimaryContainerColor;
                                        }
                                        font.pixelSize: 14
                                        leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                        background: Rectangle {
                                            color: Theme.primary; opacity: 0.1; radius: 20
                                            border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                        }
                                        onTextEdited: {
                                            let t = text.trim();
                                            let re = /^\d{1,2}:\d{2}$/;
                                            if (re.test(t)) {
                                                let p = t.split(":");
                                                let h = parseInt(p[0],10), m = parseInt(p[1],10);
                                                if (!isNaN(h) && !isNaN(m) && h>=0 && h<=23 && m>=0 && m<=59) {
                                                    Config.draftBlueLightNightEnd = t;
                                                }
                                            }
                                        }
                                        onEditingFinished: {
                                            let t = text.trim();
                                            let re = /^\d{1,2}:\d{2}$/;
                                            if (re.test(t)) {
                                                let p = t.split(":");
                                                let h = parseInt(p[0],10), m = parseInt(p[1],10);
                                                if (!isNaN(h) && !isNaN(m) && h>=0 && h<=23 && m>=0 && m<=59) {
                                                    Config.draftBlueLightNightEnd = t;
                                                } else {
                                                    text = Config.draftBlueLightNightEnd;
                                                }
                                            } else {
                                                text = Config.draftBlueLightNightEnd;
                                            }
                                        }
                                        Connections {
                                            target: root
                                            function onVisibleChanged() {
                                                if (root.visible) {
                                                    blueLightNightEndField.text = Qt.binding(function() { return Config.draftBlueLightNightEnd; });
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Setting: Coordinates (Sunset/Sunrise mode)
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && (Config.draftBlueLightMode === "sunset_sunrise" || Config.draftBlueLightMode === "realtime" || Config.draftBlueLightMode === "manual_location") && root.fuzzyMatch(searchField.text, "Coordinates Latitude and Longitude for calculating sunrise and sunset.")
                            enabled: !Config.draftBlueLightManualOn && !Config.draftBlueLightUseIpLocation
                            opacity: enabled ? 1.0 : 0.4
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Coordinates"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Latitude and Longitude for calculating sunrise and sunset."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                spacing: 8
                                TextField {
                                    id: blueLightLatField
                                    Layout.preferredWidth: 100
                                    text: Config.draftBlueLightLatitude
                                    placeholderText: "Latitude"
                                    color: Theme.onPrimaryContainerColor
                                    font.pixelSize: 14
                                    leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                    background: Rectangle {
                                        color: Theme.primary; opacity: 0.1; radius: 20
                                        border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                    }
                                    onTextEdited: Config.draftBlueLightLatitude = text
                                    onEditingFinished: Config.draftBlueLightLatitude = text
                                    Connections {
                                        target: root
                                        function onVisibleChanged() {
                                            if (root.visible) {
                                                blueLightLatField.text = Qt.binding(function() { return Config.draftBlueLightLatitude; });
                                            }
                                        }
                                    }
                                }
                                TextField {
                                    id: blueLightLonField
                                    Layout.preferredWidth: 100
                                    text: Config.draftBlueLightLongitude
                                    placeholderText: "Longitude"
                                    color: Theme.onPrimaryContainerColor
                                    font.pixelSize: 14
                                    leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                    background: Rectangle {
                                        color: Theme.primary; opacity: 0.1; radius: 20
                                        border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                    }
                                    onTextEdited: Config.draftBlueLightLongitude = text
                                    onEditingFinished: Config.draftBlueLightLongitude = text
                                    Connections {
                                        target: root
                                        function onVisibleChanged() {
                                            if (root.visible) {
                                                blueLightLonField.text = Qt.binding(function() { return Config.draftBlueLightLongitude; });
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Setting: Use realtime location based on IP checkbox (Sunset/Sunrise mode)
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && (Config.draftBlueLightMode === "sunset_sunrise" || Config.draftBlueLightMode === "realtime" || Config.draftBlueLightMode === "manual_location") && root.fuzzyMatch(searchField.text, "Use realtime location based on IP Fetch location automatically")
                            enabled: !Config.draftBlueLightManualOn
                            opacity: enabled ? 1.0 : 0.4
                            Layout.fillWidth: true
                            
                            CheckBox {
                                id: ipLocationCheckBox
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                                checked: Config.draftBlueLightUseIpLocation
                                text: "Use realtime location based on IP"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                indicator: Rectangle {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    radius: 6
                                    color: ipLocationCheckBox.checked ? Theme.primary : Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.2)
                                    border.color: ipLocationCheckBox.checked ? Theme.primary : Theme.outlineVariant
                                    border.width: 1

                                    Text {
                                        visible: ipLocationCheckBox.checked
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: Theme.primaryText
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                }
                                contentItem: Text {
                                    text: ipLocationCheckBox.text
                                    font: ipLocationCheckBox.font
                                    color: Theme.onPrimaryContainerColor
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: ipLocationCheckBox.indicator.width + 10
                                }
                                onToggled: Config.draftBlueLightUseIpLocation = checked
                            }
                        }
                        
                        // Setting: Transition Duration
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && root.fuzzyMatch(searchField.text, "Transition Duration Time in minutes for the color temperature to transition.")
                            enabled: !Config.draftBlueLightManualOn
                            opacity: enabled ? 1.0 : 0.4
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Transition Duration (minutes)"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "The transition completes by the scheduled time (ramp ends at the boundary, not starts)."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            TextField {
                                id: blueLightTransitionField
                                Layout.preferredWidth: 60
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                text: Config.draftBlueLightTransitionMinutes.toString()
                                validator: IntValidator { bottom: 0; top: 1440 }
                                color: Theme.onPrimaryContainerColor
                                font.pixelSize: 14
                                leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                background: Rectangle {
                                    color: Theme.primary; opacity: 0.1; radius: 20
                                    border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                }
                                onTextEdited: {
                                    let val = parseInt(text);
                                    if (!isNaN(val) && val >= 0) Config.draftBlueLightTransitionMinutes = val;
                                }
                                onEditingFinished: {
                                    let val = parseInt(text);
                                    if (!isNaN(val) && val >= 0) {
                                        Config.draftBlueLightTransitionMinutes = val;
                                    }
                                }
                                Connections {
                                    target: root
                                    function onVisibleChanged() {
                                        if (root.visible) {
                                            blueLightTransitionField.text = Qt.binding(function() { return Config.draftBlueLightTransitionMinutes.toString() });
                                        }
                                    }
                                }
                            }
                        }

                        // Setting: Day Temperature
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && root.fuzzyMatch(searchField.text, "Day Temperature Color temperature during the day (K).")
                            enabled: !Config.draftBlueLightManualOn
                            opacity: enabled ? 1.0 : 0.4
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Day Temperature (" + Config.draftBlueLightDayTemp + "K)"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Color temperature during the day (K)."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            Slider {
                                Layout.preferredWidth: 150
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                from: 1000
                                to: 10000
                                stepSize: 100
                                value: Config.draftBlueLightDayTemp
                                onValueChanged: Config.draftBlueLightDayTemp = value
                            }
                        }
                        
                        // Setting: Night Temperature
                        RowLayout {
                            visible: Config.draftBlueLightEnabled && root.fuzzyMatch(searchField.text, "Night Temperature Color temperature at night (K).")
                            enabled: !Config.draftBlueLightManualOn
                            opacity: enabled ? 1.0 : 0.4
                            Layout.fillWidth: true
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Night Temperature (" + Config.draftBlueLightNightTemp + "K)"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                Text { text: "Color temperature at night (K)."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            
                            Slider {
                                Layout.preferredWidth: 150
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                from: 1000
                                to: 10000
                                stepSize: 100
                                value: Config.draftBlueLightNightTemp
                                onValueChanged: Config.draftBlueLightNightTemp = value
                            }
                        }
                        
                            }

                            // ── PAGE 4: Desktop ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 24
                                visible: tabList.currentIndex === 4

                                RowLayout {
                                    visible: root.fuzzyMatch(searchField.text, "Desktop Edit Mode Reposition, resize, remove, and re-add desktop widgets.")
                                    Layout.fillWidth: true
                                    spacing: 16

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            text: "Desktop Edit Mode"
                                            color: Theme.onPrimaryContainerColor
                                            font.pixelSize: 15
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            text: "Reposition, resize, remove, and re-add desktop widgets."
                                            color: Theme.onPrimaryContainerColor
                                            opacity: 0.6
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Button {
                                        id: enterEditModeBtn
                                        text: "Enter desktop edit mode"
                                        onClicked: {
                                            root.hide();
                                            root.requestEditMode();
                                        }

                                        contentItem: Text {
                                            text: parent.text
                                            color: Theme.onPrimaryContainerColor
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        background: Rectangle {
                                            implicitHeight: 36
                                            implicitWidth: 190
                                            color: Theme.primary
                                            opacity: enterEditModeBtn.down ? 0.3 : (enterEditModeBtn.hovered ? 0.4 : 0.2)
                                            radius: 18
                                            border.width: 1
                                            border.color: Theme.primary
                                            layer.enabled: true
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }
                                    }
                                }

                                // Setting: Window Rounding Slider
                                RowLayout {
                                    visible: root.fuzzyMatch(searchField.text, "Window Rounding Corner radius")
                                    Layout.fillWidth: true
                                    enabled: !Config.draftWindowRadiusManual
                                    opacity: enabled ? 1.0 : 0.4
                                    spacing: 16

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            text: "Window Rounding (" + Config.draftWindowRadius + " px)"
                                            color: Theme.onPrimaryContainerColor
                                            font.pixelSize: 15
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            text: "Adjust corner rounding for all windows and overlay cards (0–24 px)."
                                            color: Theme.onPrimaryContainerColor
                                            opacity: 0.6
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Slider {
                                        id: windowRadiusSlider
                                        Layout.preferredWidth: 160
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                        from: 0
                                        to: 24
                                        stepSize: 1
                                        value: Math.min(Math.max(Config.draftWindowRadius, 0), 24)
                                        onValueChanged: {
                                            if (!Config.draftWindowRadiusManual) {
                                                Config.draftWindowRadius = Math.round(value)
                                            }
                                        }
                                    }
                                }

                                // Setting: Window Rounding (Manual Checkbox)
                                RowLayout {
                                    visible: root.fuzzyMatch(searchField.text, "Window Rounding Manual rounding Set manual pixel number")
                                    Layout.fillWidth: true

                                    CheckBox {
                                        id: manualRadiusCheckBox
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                                        checked: Config.draftWindowRadiusManual
                                        text: "Set manual pixel number"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        indicator: Rectangle {
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            radius: 6
                                            color: manualRadiusCheckBox.checked ? Theme.primary : Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.2)
                                            border.color: manualRadiusCheckBox.checked ? Theme.primary : Theme.outlineVariant
                                            border.width: 1

                                            Text {
                                                visible: manualRadiusCheckBox.checked
                                                anchors.centerIn: parent
                                                text: "✓"
                                                color: Theme.primaryText
                                                font.pixelSize: 13
                                                font.bold: true
                                            }
                                        }
                                        contentItem: Text {
                                            text: manualRadiusCheckBox.text
                                            font: manualRadiusCheckBox.font
                                            color: Theme.onPrimaryContainerColor
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: manualRadiusCheckBox.indicator.width + 10
                                        }
                                        onToggled: {
                                            Config.draftWindowRadiusManual = checked
                                            if (!checked && Config.draftWindowRadius > 24) {
                                                Config.draftWindowRadius = 24
                                            }
                                        }
                                    }
                                }

                                // Setting: Window Rounding (Manual Textbox Option)
                                RowLayout {
                                    visible: Config.draftWindowRadiusManual && root.fuzzyMatch(searchField.text, "Window Rounding Manual rounding Set the rounding value for the UI")
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 32
                                    spacing: 16

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            text: "Set the rounding value for the UI (px)"
                                            color: Theme.onPrimaryContainerColor
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            text: "Enter a custom pixel value for window rounding."
                                            color: Theme.onPrimaryContainerColor
                                            opacity: 0.6
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    TextField {
                                        id: manualRadiusField
                                        Layout.preferredWidth: 80
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                        text: Config.draftWindowRadius.toString()
                                        validator: IntValidator { bottom: 0; top: 200 }
                                        color: Theme.onPrimaryContainerColor
                                        font.pixelSize: 14
                                        horizontalAlignment: Text.AlignHCenter
                                        leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                        background: Rectangle {
                                            color: Theme.primary; opacity: 0.1; radius: 20
                                            border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                        }
                                        onTextEdited: {
                                            let val = parseInt(text);
                                            if (!isNaN(val) && val >= 0) {
                                                Config.draftWindowRadius = val;
                                            }
                                        }
                                        onEditingFinished: {
                                            let val = parseInt(text);
                                            if (!isNaN(val) && val >= 0) {
                                                Config.draftWindowRadius = val;
                                            } else {
                                                text = Config.draftWindowRadius.toString();
                                            }
                                        }
                                        Connections {
                                            target: root
                                            function onVisibleChanged() {
                                                if (root.visible) {
                                                    manualRadiusField.text = Config.draftWindowRadius.toString();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── PAGE 5: Screenshot ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 24
                                visible: tabList.currentIndex === 5

                                // Setting: Screenshot Directory
                                RowLayout {
                                    visible: root.fuzzyMatch(searchField.text, "Screenshot Directory The folder where screenshots are saved.")
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Text { text: "Screenshot Directory"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                        Text { text: "The folder where screenshots are saved."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }

                                    TextField {
                                        id: ssDirField
                                        Layout.preferredWidth: 220
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                        text: root.draftSsDir
                                        color: Theme.onPrimaryContainerColor
                                        font.pixelSize: 14
                                        leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                        selectByMouse: true
                                        background: Rectangle {
                                            color: Theme.primary; opacity: 0.1; radius: 20
                                            border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                        }
                                        onTextEdited: root.draftSsDir = text
                                        onEditingFinished: root.draftSsDir = text
                                    }

                                    Button {
                                        id: ssDirFieldBrowse
                                        enabled: !ssPickerProcess.running
                                        Layout.alignment: Qt.AlignVCenter
                                        onClicked: {
                                            ssPickerProcess.command = ["zenity", "--file-selection", "--directory", "--title=Select Screenshot Folder", "--filename=" + root.draftSsDir + "/"];
                                            ssPickerProcess.running = true;
                                        }
                                        contentItem: Text {
                                            text: "📁"
                                            font.pixelSize: 16
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitWidth: 36
                                            implicitHeight: 36
                                            radius: 18
                                            color: Theme.primary
                                            opacity: ssDirFieldBrowse.down ? 0.3 : (ssDirFieldBrowse.hovered ? 0.4 : 0.2)
                                            border.width: 1
                                            border.color: Theme.primary
                                            layer.enabled: true
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }
                                    }
                                }

                                // Setting: Recording Directory
                                RowLayout {
                                    visible: root.fuzzyMatch(searchField.text, "Recording Directory The folder where screen recordings are saved.")
                                    Layout.fillWidth: true
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Text { text: "Recording Directory"; color: Theme.onPrimaryContainerColor; font.pixelSize: 15; font.weight: Font.Medium }
                                        Text { text: "The folder where screen recordings are saved."; color: Theme.onPrimaryContainerColor; opacity: 0.6; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }

                                    TextField {
                                        id: recDirField
                                        Layout.preferredWidth: 220
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                        text: root.draftRecDir
                                        color: Theme.onPrimaryContainerColor
                                        font.pixelSize: 14
                                        leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                        selectByMouse: true
                                        background: Rectangle {
                                            color: Theme.primary; opacity: 0.1; radius: 20
                                            border.width: 1; border.color: parent.activeFocus ? Theme.primary : Theme.outlineVariant
                                        }
                                        onTextEdited: root.draftRecDir = text
                                        onEditingFinished: root.draftRecDir = text
                                    }

                                    Button {
                                        id: recDirFieldBrowse
                                        enabled: !recPickerProcess.running
                                        Layout.alignment: Qt.AlignVCenter
                                        onClicked: {
                                            recPickerProcess.command = ["zenity", "--file-selection", "--directory", "--title=Select Recording Folder", "--filename=" + root.draftRecDir + "/"];
                                            recPickerProcess.running = true;
                                        }
                                        contentItem: Text {
                                            text: "📁"
                                            font.pixelSize: 16
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            implicitWidth: 36
                                            implicitHeight: 36
                                            radius: 18
                                            color: Theme.primary
                                            opacity: recDirFieldBrowse.down ? 0.3 : (recDirFieldBrowse.hovered ? 0.4 : 0.2)
                                            border.width: 1
                                            border.color: Theme.primary
                                            layer.enabled: true
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // ── Footer Separator ──
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.outlineVariant
                        opacity: 0.3
                    }

                    // ── Persistent Footer ──
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Text {
                            text: applyProc.resultMessage
                            color: applyProc.success ? Theme.onPrimaryContainerColor : Theme.error
                            font.pixelSize: 13
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Button {
                            id: applyBtn
                            text: applyProc.running ? "Saving..." : "Save"
                            onClicked: {
                                root.commitChanges(false);
                            }

                            contentItem: Text {
                                text: parent.text
                                color: Theme.onPrimaryContainerColor
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                implicitHeight: 36
                                implicitWidth: 150
                                color: Theme.primary
                                opacity: applyBtn.down ? 0.3 : (applyBtn.hovered ? 0.4 : 0.2)
                                radius: 18
                                border.width: 1
                                border.color: Theme.primary
                                layer.enabled: true
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }
                        
                        Timer {
                            id: messageTimer
                            interval: 5000
                            onTriggered: applyProc.resultMessage = ""
                        }
                    }
                    
                    Process {
                        id: applyProc
                        property string resultMessage: ""
                        property bool success: false
                        property bool isPopup: false
                        
                        stdout: SplitParser {
                            onRead: data => console.log(data)
                        }
                        stderr: SplitParser {
                            onRead: data => { applyProc.resultMessage = data; }
                        }
                        
                        onStarted: {
                            resultMessage = "";
                            success = false;
                            messageTimer.stop()
                        }
                        
                        onExited: (code) => {
                            if (code === 0) {
                                if (isPopup) {
                                    unsavedPopup.visible = false;
                                    root.hide();
                                } else {
                                    success = true;
                                    resultMessage = "Settings saved.";
                                    messageTimer.restart();
                                }
                            } else {
                                if (isPopup) {
                                    if (resultMessage.indexOf("greeter-sync group") !== -1) {
                                        resultMessage = "Permission denied. Ensure you are in 'greeter-sync' group and have logged out and back in.";
                                    }
                                } else {
                                    success = false;
                                    if (resultMessage.indexOf("greeter-sync group") !== -1) {
                                        resultMessage = "Settings saved; greeter sync failed: Permission denied (greeter-sync group).";
                                    } else {
                                        resultMessage = "Settings saved; greeter sync failed: " + resultMessage;
                                    }
                                    messageTimer.restart();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // ── Unsaved Changes Popup ──
    Item {
        id: unsavedPopup
        anchors.fill: parent
        z: 100
        visible: false

        // Scrim
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5)
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        // Card
        Item {
            width: 400
            height: 180
            anchors.centerIn: parent

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusLarge
                color: "black"
                opacity: 0.25
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusLarge
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.45)
            }
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16
                
                Text {
                    text: "You have unsaved changes."
                    color: Theme.onPrimaryContainerColor
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Item { Layout.fillHeight: true }
                
                Text {
                    text: applyProc.resultMessage
                    color: Theme.error
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    visible: applyProc.isPopup && applyProc.resultMessage !== ""
                }
                
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 16
                    
                    Button {
                        id: saveBtn
                        text: (applyProc.isPopup && applyProc.running) ? "Saving..." : "Save"
                        onClicked: {
                            root.commitChanges(true);
                        }
                        contentItem: Text {
                            text: parent.text
                            color: Theme.onPrimaryContainerColor
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 36
                            implicitWidth: 100
                            color: Theme.primary
                            opacity: parent.down ? 0.3 : (parent.hovered ? 0.4 : 0.2)
                            radius: 18
                            border.width: 1
                            border.color: Theme.primary
                            layer.enabled: true
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    Button {
                        id: discardBtn
                        text: "Discard"
                        onClicked: {
                            Config.discard()
                            root.discardScreenshotDraft()
                            unsavedPopup.visible = false
                            root.hide()
                        }
                        contentItem: Text {
                            text: parent.text
                            color: Theme.onPrimaryContainerColor
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            implicitHeight: 36
                            implicitWidth: 100
                            color: discardBtn.down ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.2) : (discardBtn.hovered ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.1) : "transparent")
                            radius: 18
                            border.width: 1
                            border.color: Theme.outlineVariant
                            layer.enabled: true
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }
            }
        }
    }
}
