// ─────────────────────────────────────────────────────────────────────────
// ScreenCapture.qml — fully QuickShell-native screenshot & recording tool
//
// No grim, slurp, or wf-recorder — capture is done entirely via
// ScreencopyView + grabToImage.  Only wl-copy (clipboard) and ffmpeg
// (video encoding) are used as lightweight utilities.
//
// Architecture:
//   PanelWindow (WlrLayer.Overlay, full-screen, custom namespace)
//   └─ ScreencopyView (frozen backdrop)
//   └─ Dark overlay with cut-out region
//   └─ Region selection rubber-band
//   └─ Top bar: Screenshot / Recording toggle
//   └─ Bottom bar: Region / Window / Output + FPS + folder picker
//
// IPC targets: screenshot toggle | open | close | region | window | output
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"

PanelWindow {
    id: root

    // ---- Public API -------------------------------------------------------
    property bool shown: false

    // Emitted by the gear button; shell.qml opens Settings on the Screenshot tab
    signal openSettingsRequested()

    function show()   { root.shown = true }
    function hide()   {
        root.shown = false
        resetState()
    }
    function toggle() { if (shown) hide(); else show() }

    // Direct capture functions for IPC
    function captureRegion() {
        root.captureMode = "screenshot"
        root.selectionType = "region"
        root.show()
    }
    function captureWindow() {
        root.captureMode = "screenshot"
        root.selectionType = "window"
        root.show()
    }
    function captureOutput() {
        root.captureMode = "screenshot"
        root.selectionType = "output"
        root.show()
        // Auto-capture full output after a brief delay for the frame to load
        autoOutputTimer.start()
    }

    // ---- State ------------------------------------------------------------
    property string captureMode:   "screenshot"  // "screenshot" | "recording"
    property string selectionType: "region"       // "region" | "window" | "output"
    property int    recordingFps:  24             // 24 | 30

    // Config
    property string screenshotDir: ""
    property string recordingDir:  ""

    // Region selection state
    property bool   isSelecting:   false
    property bool   hasSelection:  false
    property real   selStartX:     0
    property real   selStartY:     0
    property real   selEndX:       0
    property real   selEndY:       0

    // Window selection state
    property var    windowList:    []
    property int    hoveredWindow: -1
    property var    hoveredGeom:   null

    // Recording state
    property bool   isRecording:   false
    property int    frameCount:    0
    property string framesDir:     ""
    property bool   captureInProgress: false

    // ---- Computed selection rect (Rounded to prevent subpixel smearing!) ---
    readonly property int selX: Math.round(Math.min(selStartX, selEndX))
    readonly property int selY: Math.round(Math.min(selStartY, selEndY))
    readonly property int selW: Math.round(Math.abs(selEndX - selStartX))
    readonly property int selH: Math.round(Math.abs(selEndY - selStartY))

    // ---- Wayland layer-shell plumbing -------------------------------------
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "screencapture"
    color: "transparent"
    focusable: root.shown
    anchors { top: true; bottom: true; left: true; right: true }

    visible: shown || isRecording
    
    // Allow input to pass through to the desktop when UI is hidden
    mask: root.shown ? null : emptyRegion
    Region { id: emptyRegion }

    onShownChanged: {
        if (shown) {
            loadConfig()
            // Capture a frozen frame of the screen
            screenView.captureFrame()
            keyHandler.forceActiveFocus()
            // Refresh window list for window mode
            if (selectionType === "window") {
                windowListProcess.running = true
            }
        }
    }

    function resetState() {
        isSelecting = false
        hasSelection = false
        selStartX = 0; selStartY = 0
        selEndX = 0; selEndY = 0
        hoveredWindow = -1
        hoveredGeom = null
        captureInProgress = false
    }

    Timer {
        id: autoOutputTimer
        interval: 200
        onTriggered: performCapture()
    }

    // ---- Config loading ---------------------------------------------------
    Process {
        id: configReader
        command: ["sh", Quickshell.shellDir + "/scripts/screenshot-config.sh", "read"]
        property string jsonContent: ""

        onRunningChanged: {
            if (running) {
                jsonContent = ""
            } else if (jsonContent.trim().length > 0) {
                try {
                    var c = JSON.parse(jsonContent)
                    root.screenshotDir = c.screenshotDir || ""
                    root.recordingDir  = c.recordingDir  || ""
                    if (c.recordingFps) root.recordingFps = parseInt(c.recordingFps) || 24
                } catch (e) {
                    console.warn("ScreenCapture: could not parse config —", e)
                }
            }
        }

        stdout: SplitParser {
            onRead: data => { configReader.jsonContent += data + "\n" }
        }
    }

    function loadConfig() {
        configReader.running = true
    }

    // Config writer
    Process {
        id: configWriter
    }

    function saveConfig(key, value) {
        configWriter.command = ["sh", Quickshell.shellDir + "/scripts/screenshot-config.sh", "write", key, String(value)]
        configWriter.running = true
    }

    // ---- Init config on startup -------------------------------------------
    Process {
        id: initProcess
        command: ["sh", Quickshell.shellDir + "/scripts/screenshot-config.sh", "init"]
        running: true
    }

    Component.onCompleted: {
        loadConfig()
    }

    // ---- Window list (for window selection mode) --------------------------
    Process {
        id: windowListProcess
        command: ["hyprctl", "-j", "clients"]
        property string fullOutput: ""

        onRunningChanged: {
            if (running) {
                fullOutput = ""
            } else {
                try {
                    if (fullOutput.trim() === "") return
                    var clients = JSON.parse(fullOutput)
                    var wins = []
                    for (var i = 0; i < clients.length; i++) {
                        var c = clients[i]
                        if (c.mapped && !c.hidden && c.workspace && c.workspace.id > 0) {
                            wins.push({
                                title: c.title || c.class || "Unknown",
                                class: c.class || "",
                                address: c.address || "",
                                x: c.at[0],
                                y: c.at[1],
                                w: c.size[0],
                                h: c.size[1]
                            })
                        }
                    }
                    root.windowList = wins
                } catch (e) {
                    console.warn("ScreenCapture: could not parse clients —", e)
                }
            }
        }

        stdout: SplitParser {
            onRead: data => { windowListProcess.fullOutput += data + "\n" }
        }
    }

    // ---- Screenshot capture processes -------------------------------------
    Process {
        id: clipboardProcess
    }

    Process {
        id: notifyProcess
    }

    // ---- ScreencopyView (frozen backdrop) ---------------------------------
    ScreencopyView {
        id: screenView
        anchors.fill: parent
        captureSource: root.screen
        live: false
        paintCursor: false

        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    // ---- Dark overlay with selection cut-out -------------------------------
    Item {
        id: overlayMask
        anchors.fill: parent
        visible: root.shown && screenView.hasContent && !root.captureInProgress
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        property real holeX: (root.hasSelection || root.isSelecting) ? root.selX : (root.selectionType === "window" && root.hoveredGeom ? root.hoveredGeom.x : 0)
        property real holeY: (root.hasSelection || root.isSelecting) ? root.selY : (root.selectionType === "window" && root.hoveredGeom ? root.hoveredGeom.y : 0)
        property real holeW: (root.hasSelection || root.isSelecting) ? root.selW : (root.selectionType === "window" && root.hoveredGeom ? root.hoveredGeom.w : root.width)
        property real holeH: (root.hasSelection || root.isSelecting) ? root.selH : (root.selectionType === "window" && root.hoveredGeom ? root.hoveredGeom.h : root.height)
        
        property color maskColor: Qt.rgba(0, 0, 0, 0.55)

        Rectangle { x: 0; y: 0; width: parent.width; height: parent.holeY; color: parent.maskColor }
        Rectangle { x: 0; y: parent.holeY + parent.holeH; width: parent.width; height: parent.height - (parent.holeY + parent.holeH); color: parent.maskColor }
        Rectangle { x: 0; y: parent.holeY; width: parent.holeX; height: parent.holeH; color: parent.maskColor }
        Rectangle { x: parent.holeX + parent.holeW; y: parent.holeY; width: parent.width - (parent.holeX + parent.holeW); height: parent.holeH; color: parent.maskColor }
    }

    // ---- Selection border & dimension label -------------------------------
    Rectangle {
        visible: (root.hasSelection || root.isSelecting) && root.selW > 2 && root.selH > 2 && !root.captureInProgress
        x: root.selX
        y: root.selY
        width: root.selW
        height: root.selH
        color: "transparent"
        border.width: 2
        border.color: Theme.primary

        // Dimension label
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 8
            width: dimText.width + 16
            height: dimText.height + 8
            radius: 4
            color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.85)

            Text {
                id: dimText
                anchors.centerIn: parent
                text: Math.round(root.selW) + " × " + Math.round(root.selH)
                color: Theme.onPrimaryContainerColor
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.family: "monospace"
            }
        }
    }

    // ---- Window highlight (window mode) -----------------------------------
    Rectangle {
        visible: root.selectionType === "window" && root.hoveredGeom !== null && !root.captureInProgress
        x: root.hoveredGeom ? root.hoveredGeom.x : 0
        y: root.hoveredGeom ? root.hoveredGeom.y : 0
        width: root.hoveredGeom ? root.hoveredGeom.w : 0
        height: root.hoveredGeom ? root.hoveredGeom.h : 0
        color: "transparent"
        border.width: 3
        border.color: Theme.primary

        // Window title label
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 8
            width: winTitle.width + 16
            height: winTitle.height + 8
            radius: 4
            color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.85)
            visible: root.hoveredGeom !== null

            Text {
                id: winTitle
                anchors.centerIn: parent
                text: {
                    if (root.hoveredWindow >= 0 && root.hoveredWindow < root.windowList.length)
                        return root.windowList[root.hoveredWindow].title
                    return ""
                }
                color: Theme.onPrimaryContainerColor
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    // ---- Mouse interaction area -------------------------------------------
    MouseArea {
        id: interactionArea
        anchors.fill: parent
        enabled: root.shown
        // Covers the whole screen (including the very top/bottom edges).
        // The top/bottom bars sit above this and swallow their own clicks.
        hoverEnabled: root.selectionType === "window"
        cursorShape: root.selectionType === "region" ? Qt.CrossCursor : Qt.ArrowCursor

        onPressed: (mouse) => {
            if (root.selectionType === "region") {
                root.isSelecting = true
                root.hasSelection = false
                root.selStartX = Math.max(0, Math.min(root.width, mouse.x))
                root.selStartY = Math.max(0, Math.min(root.height, mouse.y))
                root.selEndX = root.selStartX
                root.selEndY = root.selStartY
            }
        }

        onPositionChanged: (mouse) => {
            if (root.selectionType === "region" && root.isSelecting) {
                root.selEndX = Math.max(0, Math.min(root.width, mouse.x))
                root.selEndY = Math.max(0, Math.min(root.height, mouse.y))
            } else if (root.selectionType === "window") {
                // Find which window the cursor is over
                var mx = mouse.x
                var my = mouse.y
                root.hoveredWindow = -1
                root.hoveredGeom = null
                for (var i = 0; i < root.windowList.length; i++) {
                    var w = root.windowList[i]
                    if (mx >= w.x && mx <= w.x + w.w && my >= w.y && my <= w.y + w.h) {
                        root.hoveredWindow = i
                        root.hoveredGeom = { x: w.x, y: w.y, w: w.w, h: w.h }
                        break
                    }
                }
            }
        }

        onReleased: (mouse) => {
            if (root.selectionType === "region" && root.isSelecting) {
                root.isSelecting = false
                root.selEndX = Math.max(0, Math.min(root.width, mouse.x))
                root.selEndY = Math.max(0, Math.min(root.height, mouse.y))
                if (root.selW > 10 && root.selH > 10) {
                    root.hasSelection = true
                }
            }
        }

        onClicked: (mouse) => {
            if (root.selectionType === "window" && root.hoveredWindow >= 0) {
                var w = root.windowList[root.hoveredWindow]
                root.selStartX = w.x; root.selStartY = w.y
                root.selEndX = w.x + w.w; root.selEndY = w.y + w.h
                root.hasSelection = true
                performCapture()
            } else if (root.selectionType === "output") {
                performCapture()
            }
        }

        onDoubleClicked: {
            if (root.selectionType === "region" && root.hasSelection) {
                performCapture()
            }
        }
    }

    // ---- Keyboard handler -------------------------------------------------
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.hide()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (root.hasSelection || root.selectionType === "output") {
                    performCapture()
                }
                event.accepted = true
            } else if (event.key === Qt.Key_1) {
                root.selectionType = "region"
                root.resetState()
                event.accepted = true
            } else if (event.key === Qt.Key_2) {
                root.selectionType = "window"
                root.resetState()
                windowListProcess.running = true
                event.accepted = true
            } else if (event.key === Qt.Key_3) {
                root.selectionType = "output"
                root.resetState()
                event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
                root.captureMode = (root.captureMode === "screenshot") ? "recording" : "screenshot"
                event.accepted = true
            }
        }
    }

    // ---- Hidden crop container for region screenshots ---------------------
    // This Item clips the ScreencopyView to just the selection region.
    // grabToImage on this produces a cropped screenshot — pure QML, no tools.
    Item {
        id: cropContainer
        x: root.selX
        y: root.selY
        z: -1
        width: Math.max(1, root.selW)
        height: Math.max(1, root.selH)
        clip: true
        opacity: root.shown ? 1 : 0.001 // Hide from screen during recording

        ScreencopyView {
            id: cropView
            x: -root.selX
            y: -root.selY
            width: root.width
            height: root.height
            captureSource: root.screen
            live: false
            paintCursor: false
        }
    }

    // ---- Full-screen capture view (for output mode) -----------------------
    Item {
        id: fullContainer
        x: 0
        y: 0
        z: -1
        width: root.width
        height: root.height
        clip: true
        opacity: root.shown ? 1 : 0.001 // Hide from screen during recording

        ScreencopyView {
            id: fullView
            anchors.fill: parent
            captureSource: root.screen
            live: false
            paintCursor: false
        }
    }



    // ---- Recording live view (for screen recording) -----------------------
    Item {
        anchors.fill: parent
        opacity: 0.001 // 0.1% opacity keeps it rendering (not culled) but invisible to users

        Item {
            id: recordContainer
            x: root.selectionType === "output" ? 0 : root.selX
            y: root.selectionType === "output" ? 0 : root.selY
            z: -1
            width: Math.max(1, root.selectionType === "output" ? root.width : root.selW)
            height: Math.max(1, root.selectionType === "output" ? root.height : root.selH)
            clip: true

            ScreencopyView {
                id: recordView
                x: root.selectionType === "output" ? 0 : -root.selX
                y: root.selectionType === "output" ? 0 : -root.selY
                width: root.width
                height: root.height
                captureSource: root.screen
                live: root.isRecording
                paintCursor: true // Use compositor cursor since Droste is hidden by 0.001 opacity
            }
        }
    }

    // ---- Capture logic ----------------------------------------------------
    function generateFilename(ext) {
        var now = new Date()
        var pad = function(n) { return n < 10 ? "0" + n : "" + n }
        var ts = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate()) +
                 "_" + pad(now.getHours()) + "-" + pad(now.getMinutes()) + "-" + pad(now.getSeconds())
        if (ext === "png") return "Screenshot_" + ts + ".png"
        return "Recording_" + ts + ".mp4"
    }

    function performCapture() {
        if (root.captureMode === "screenshot") {
            takeScreenshot()
        } else {
            startRecording()
        }
    }

    function takeScreenshot() {
        root.captureInProgress = true
        
        // Turn on live view to flush any stale frames while UI is settling!
        if (root.selectionType === "output") {
            fullView.live = true
        } else {
            cropView.live = true
        }

        captureSettleTimer.pendingAction = function() {
            var filename = generateFilename("png")
            var dir = root.screenshotDir || Quickshell.env("HOME") + "/Pictures/Screenshots"
            var fullPath = dir + "/" + filename

            // Ensure directory exists
            mkdirProcess.command = ["mkdir", "-p", dir]
            mkdirProcess.running = true

            if (root.selectionType === "output") {
                // Full screen capture
                fullView.live = false
                fullCaptureHandler.fullPath = fullPath
                fullCaptureHandler.enabled = true
                if (fullView.hasContent) fullCaptureHandler.onHasContentChanged()
            } else {
                // Region or window capture (both use selX/Y/W/H)
                cropView.live = false
                cropCaptureHandler.fullPath = fullPath
                cropCaptureHandler.enabled = true
                if (cropView.hasContent) cropCaptureHandler.onHasContentChanged()
            }
        }
        captureSettleTimer.start()
    }

    Timer {
        id: captureSettleTimer
        interval: 150
        property var pendingAction: null
        onTriggered: {
            if (pendingAction) {
                var action = pendingAction
                pendingAction = null
                action()
            }
        }
    }

    Process { id: mkdirProcess }

    // Wait for crop view content then grab
    Connections {
        id: cropCaptureHandler
        target: cropView
        enabled: false
        property string fullPath: ""

        function onHasContentChanged() {
            if (cropView.hasContent && enabled) {
                enabled = false
                cropContainer.grabToImage(function(result) {
                    if (result) {
                        result.saveToFile(cropCaptureHandler.fullPath)
                        onScreenshotSaved(cropCaptureHandler.fullPath)
                    }
                })
            }
        }
    }

    // Wait for full view content then grab
    Connections {
        id: fullCaptureHandler
        target: fullView
        enabled: false
        property string fullPath: ""

        function onHasContentChanged() {
            if (fullView.hasContent && enabled) {
                enabled = false
                fullContainer.grabToImage(function(result) {
                    if (result) {
                        result.saveToFile(fullCaptureHandler.fullPath)
                        onScreenshotSaved(fullCaptureHandler.fullPath)
                    }
                })
            }
        }
    }

    function onScreenshotSaved(path) {
        root.captureInProgress = false
        // Copy to clipboard
        clipboardProcess.command = ["sh", "-c", "wl-copy -t image/png < '" + path + "'"]
        clipboardProcess.running = true

        // Send notification with preview
        notifyProcess.command = [
            "notify-send",
            "-a", "Screen Capture",
            "-i", path,
            "Screenshot Saved",
            path
        ]
        notifyProcess.running = true

        root.hide()
    }

    // ---- Recording logic --------------------------------------------------
    function startRecording() {
        var cacheDir = Quickshell.env("HOME") + "/.cache/quickshell-screenshot/frames"
        root.framesDir = cacheDir
        root.frameCount = 0

        // Clean old frames
        cleanFramesProcess.command = ["sh", Quickshell.shellDir + "/scripts/screenshot-config.sh", "clean-frames"]
        cleanFramesProcess.running = true

        // Start recording after cleanup
        startRecordTimer.start()
    }

    Process { id: cleanFramesProcess }

    Timer {
        id: startRecordTimer
        interval: 100
        onTriggered: {
            root.isRecording = true
            recordingIndicator.recording = true
            recordingIndicator.elapsedSeconds = 0
            recordingIndicator.fps = root.recordingFps
            root.shown = false
            // Frame capture starts via the frameTimer below
        }
    }

    // Frame capture timer
    Timer {
        id: frameTimer
        interval: 1000 / root.recordingFps
        repeat: true
        running: root.isRecording
        property bool grabPending: false

        onTriggered: {
            if (grabPending) return  // Skip if previous grab not done
            grabPending = true

            recordContainer.grabToImage(function(result) {
                if (result) {
                    var padded = String(root.frameCount).padStart(5, '0')
                    result.saveToFile(root.framesDir + "/frame_" + padded + ".jpg")
                    root.frameCount++
                }
                frameTimer.grabPending = false
            })
        }
    }

    function stopRecording() {
        root.isRecording = false
        recordingIndicator.recording = false

        var filename = generateFilename("mp4")
        var dir = root.recordingDir || Quickshell.env("HOME") + "/Videos/Recordings"
        var fullPath = dir + "/" + filename

        // Encode via ffmpeg
        encodeProcess.command = [
            "sh", Quickshell.shellDir + "/scripts/screenshot-config.sh",
            "encode", String(root.recordingFps), root.framesDir, fullPath
        ]
        encodeProcess.running = true

        encodingPath = fullPath
    }

    property string encodingPath: ""

    Process {
        id: encodeProcess
        onExited: (exitCode) => {
            if (exitCode === 0) {
                notifyProcess.command = [
                    "notify-send",
                    "-a", "Screen Capture",
                    "Recording Saved",
                    root.encodingPath
                ]
                notifyProcess.running = true
            } else {
                notifyProcess.command = [
                    "notify-send",
                    "-a", "Screen Capture",
                    "-u", "critical",
                    "Recording Failed",
                    "ffmpeg encoding failed with exit code " + exitCode
                ]
                notifyProcess.running = true
            }
        }
    }

    // ---- Recording Indicator (separate window, below tray) ----------------
    RecordingIndicator {
        id: recordingIndicator
        onStopRequested: root.stopRecording()
    }

    // ---- Top bar: Mode toggle ---------------------------------------------
    Rectangle {
        id: topBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16
        width: modeRow.width + 8
        height: 44
        radius: 22
        color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.75)
        border.width: 1
        border.color: Theme.outlineVariant
        layer.enabled: true

        visible: root.shown && !root.captureInProgress
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        // Slide-in animation
        transform: Translate {
            y: root.shown ? 0 : -80
            Behavior on y { NumberAnimation { duration: Theme.animMed + 50; easing.type: Easing.OutBack; easing.overshoot: 2.0 } }
        }

        // Swallow clicks/hover so they don't start a selection underneath the pill
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: (mouse) => mouse.accepted = true }

        RowLayout {
            id: modeRow
            anchors.centerIn: parent
            spacing: 4

            // Screenshot button
            Rectangle {
                width: ssLabel.width + 32
                height: 34
                radius: 17
                color: root.captureMode === "screenshot"
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                    : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: ssLabel
                    anchors.centerIn: parent
                    text: "📷  Screenshot"
                    color: root.captureMode === "screenshot" ? Theme.primaryText : Theme.onPrimaryContainerColor
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.captureMode = "screenshot"
                }
            }

            // Recording button
            Rectangle {
                width: recLabel.width + 32
                height: 34
                radius: 17
                color: root.captureMode === "recording"
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                    : "transparent"

                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    id: recLabel
                    anchors.centerIn: parent
                    text: "⏺  Recording"
                    color: root.captureMode === "recording" ? Theme.primaryText : Theme.onPrimaryContainerColor
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.captureMode = "recording"
                }
            }
        }
    }

    // ---- Bottom bar: Selection type + settings ----------------------------
    Rectangle {
        id: bottomBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        width: bottomCol.width + 24
        height: bottomCol.height + 20
        radius: Theme.radiusLarge
        color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.75)
        border.width: 1
        border.color: Theme.outlineVariant
        layer.enabled: true

        visible: root.shown && !root.captureInProgress
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        // Slide-in animation
        transform: Translate {
            y: root.shown ? 0 : 120
            Behavior on y { NumberAnimation { duration: Theme.animMed + 50; easing.type: Easing.OutBack; easing.overshoot: 2.0 } }
        }

        // Swallow clicks so they don't dismiss
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: (mouse) => mouse.accepted = true }

        ColumnLayout {
            id: bottomCol
            anchors.centerIn: parent
            spacing: 10

            // Selection type row
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                component SelectionButton: Rectangle {
                    property string label
                    property string type
                    property string shortcut

                    width: btnLabel.width + 36
                    height: 34
                    radius: 17
                    color: root.selectionType === type
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        id: btnLabel
                        anchors.centerIn: parent
                        text: label
                        color: root.selectionType === type ? Theme.primaryText : Theme.onPrimaryContainerColor
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    // Shortcut badge
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -4
                        anchors.topMargin: -4
                        width: 18; height: 18; radius: 9
                        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.8)
                        visible: root.selectionType !== type

                        Text {
                            anchors.centerIn: parent
                            text: shortcut
                            color: Theme.surfaceText
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectionType = type
                            root.resetState()
                            if (type === "window") windowListProcess.running = true
                        }
                    }
                }

                SelectionButton { label: "⬒  Region";  type: "region";  shortcut: "1" }
                SelectionButton { label: "☐  Window";  type: "window";  shortcut: "2" }
                SelectionButton { label: "🖵  Output";  type: "output";  shortcut: "3" }

                // Separator
                Rectangle { width: 1; height: 24; color: Theme.outlineVariant; Layout.alignment: Qt.AlignVCenter }

                // FPS selector (visible in recording mode)
                Rectangle {
                    visible: root.captureMode === "recording"
                    width: fpsRow.width + 16
                    height: 34
                    radius: 17
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)

                    RowLayout {
                        id: fpsRow
                        anchors.centerIn: parent
                        spacing: 2

                        Rectangle {
                            width: fps24.width + 14; height: 26; radius: 13
                            color: root.recordingFps === 24
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: fps24
                                anchors.centerIn: parent
                                text: "24"
                                color: root.recordingFps === 24 ? Theme.primaryText : Theme.onPrimaryContainerColor
                                font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.recordingFps = 24
                                    root.saveConfig("recordingFps", "24")
                                }
                            }
                        }

                        Rectangle {
                            width: fps30.width + 14; height: 26; radius: 13
                            color: root.recordingFps === 30
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: fps30
                                anchors.centerIn: parent
                                text: "30"
                                color: root.recordingFps === 30 ? Theme.primaryText : Theme.onPrimaryContainerColor
                                font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.recordingFps = 30
                                    root.saveConfig("recordingFps", "30")
                                }
                            }
                        }

                        Text {
                            text: "fps"
                            color: Theme.onPrimaryContainerColor
                            font.pixelSize: 11
                            opacity: 0.7
                        }
                    }
                }

                // Separator
                Rectangle { width: 1; height: 24; color: Theme.outlineVariant; Layout.alignment: Qt.AlignVCenter }

                // Confirm button
                Rectangle {
                    width: confirmLabel.width + 32
                    height: 34
                    radius: 17
                    color: confirmMouse.containsMouse
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                        : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
                    opacity: (root.hasSelection || root.selectionType === "output") ? 1.0 : 0.4

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: confirmLabel
                        anchors.centerIn: parent
                        text: root.captureMode === "screenshot" ? "📷  Capture" : "⏺  Record"
                        color: Theme.primaryText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.hasSelection || root.selectionType === "output"
                        onClicked: performCapture()
                    }
                }

                // Settings button
                Rectangle {
                    width: 34
                    height: 34
                    radius: 17
                    color: settingsMouse.containsMouse
                        ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: Theme.onPrimaryContainerColor
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.hide()
                            root.openSettingsRequested()
                        }
                    }
                }
            }


            // Hint text
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root.selectionType === "region") return "Click and drag to select a region  ·  Enter to confirm  ·  Esc to cancel"
                    if (root.selectionType === "window") return "Click a window to select it  ·  Esc to cancel"
                    return "Press Enter or click Capture for full screen  ·  Esc to cancel"
                }
                color: Theme.onPrimaryContainerColor
                opacity: 0.5
                font.pixelSize: 11
            }
        }
    }
    // ---- (Folder picker logic lives in the Screenshot tab of SettingsWindow.qml) ------------
}
