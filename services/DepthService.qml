pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import QtCore

Item {
    id: root

    // Master enable flag (follows Config.depthEffectEnabled)
    readonly property bool enabled: Config.depthEffectEnabled

    // State properties
    property bool installed: false
    property bool gpuInstalled: false
    property bool hasNvidiaGpu: false
    property bool busy: false
    property string statusText: "Ready"
    property string activeDevice: "CPU"
    property string queueProgress: ""
    property string currentWallpaper: ""
    property string currentMaskPath: ""
    property url maskUrl: ""
    property bool maskVisible: false
    property real maskFade: 0.0

    Behavior on maskFade {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }

    property string cacheSizeFormatted: "0 B"
    property int cacheSizeBytes: 0

    // Daemon transition duration:
    // set-wallpaper.sh uses --transition-duration 1 (1000 ms) for awww and swww;
    // hyprpaper has no transition (0 ms).
    readonly property int daemonTransitionDuration: Config.wallpaperDaemon === "hyprpaper" ? 0 : 1000

    property double applyStartTime: 0
    property string pendingMaskPath: ""
    property string targetWallpaperPath: ""

    // ── Processes ──

    // 1. Status checker process
    Process {
        id: statusProcess
        command: ["python3", Quickshell.shellDir + "/scripts/wallpaper-depth.py", "status"]
        property string outBuf: ""

        onRunningChanged: {
            if (running) {
                outBuf = "";
            } else if (outBuf.trim().length > 0) {
                try {
                    let lines = outBuf.trim().split("\n");
                    for (let i = 0; i < lines.length; i++) {
                        let l = lines[i].trim();
                        if (l.startsWith("{")) {
                            let data = JSON.parse(l);
                            if (data.status === "status") {
                                root.installed = data.installed === true;
                                root.gpuInstalled = data.gpuInstalled === true;
                                root.hasNvidiaGpu = data.hasNvidiaGpu === true;
                                root.cacheSizeBytes = data.cacheSizeBytes || 0;
                                root.cacheSizeFormatted = data.cacheSizeFormatted || "0 B";
                                if (data.installed) {
                                    root.activeDevice = (Config.depthDevice === "gpu" && root.gpuInstalled) ? "NVIDIA GPU (CUDA)" :
                                                        (Config.depthDevice === "auto" && root.gpuInstalled ? "NVIDIA GPU (CUDA)" : "CPU");
                                    if (root.enabled && root.currentWallpaper && root.currentMaskPath === "") {
                                        root.generateForCurrentWallpaper();
                                    }
                                    if (root.enabled && !watchProcess.running) {
                                        root.startWatcher();
                                    }
                                } else {
                                    root.activeDevice = "Not installed";
                                }
                            }
                        }
                    }
                } catch (e) {
                    console.warn("DepthService: error parsing status:", e);
                }
            }
        }

        stdout: SplitParser {
            onRead: data => { statusProcess.outBuf += data + "\n"; }
        }
    }

    // 2. Installer process
    Process {
        id: installProcess
        property string outBuf: ""

        onRunningChanged: {
            if (running) {
                root.busy = true;
                root.statusText = "Installing...";
                outBuf = "";
            } else {
                root.busy = false;
                root.refreshStatus();
            }
        }

        stdout: SplitParser {
            onRead: data => {
                let lines = data.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line.startsWith("{")) continue;
                    try {
                        let obj = JSON.parse(line);
                        if (obj.status === "installing") {
                            root.statusText = obj.step || "Installing...";
                        } else if (obj.status === "ready") {
                            root.statusText = "Ready";
                            root.installed = true;
                            if (obj.gpuInstalled !== undefined) root.gpuInstalled = obj.gpuInstalled;
                        } else if (obj.status === "error") {
                            root.statusText = "Error: " + obj.message;
                        }
                    } catch (e) {}
                }
            }
        }
    }

    // 3. Foreground generate process (high priority in queue)
    Process {
        id: generateProcess
        property string generatingPath: ""
        property string outBuf: ""

        onRunningChanged: {
            if (running) {
                root.busy = true;
                outBuf = "";
            } else {
                root.busy = false;
                if (Config.depthPregenerate && root.enabled && root.installed && !pregenProcess.running) {
                    root.startPregeneration();
                }
            }
        }

        stdout: SplitParser {
            onRead: data => {
                let lines = data.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line.startsWith("{")) continue;
                    try {
                        let obj = JSON.parse(line);
                        if (obj.status === "ready") {
                            if (obj.wallpaper === root.targetWallpaperPath) {
                                root.handleGenerationResult(obj.mask, obj.activeProvider);
                            }
                        } else if (obj.status === "error") {
                            root.statusText = "Error: " + obj.message;
                        }
                    } catch (e) {}
                }
            }
        }
    }

    // 4. Background pregeneration process (lowest priority)
    Process {
        id: pregenProcess

        onRunningChanged: {
            if (!running) {
                root.queueProgress = "";
            }
        }

        stdout: SplitParser {
            onRead: data => {
                let lines = data.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line.startsWith("{")) continue;
                    try {
                        let obj = JSON.parse(line);
                        if (obj.status === "progress") {
                            root.queueProgress = "Preparing wallpapers " + obj.current + " / " + obj.total;
                        } else if (obj.status === "pregenerate_done") {
                            root.queueProgress = "";
                            root.refreshStatus();
                        }
                    } catch (e) {}
                }
            }
        }
    }

    // 5. Cache clearing process
    Process {
        id: clearProcess
        command: ["python3", Quickshell.shellDir + "/scripts/wallpaper-depth.py", "clear-cache"]
        onExited: (code) => {
            root.refreshStatus();
            if (root.enabled) {
                root.generateForCurrentWallpaper();
            }
        }
    }

    // 6. Background inotify folder watcher process
    Process {
        id: watchProcess
        property string outBuf: ""

        onRunningChanged: {
            if (!running && root.enabled && root.installed) {
                restartWatchTimer.start();
            }
        }

        stdout: SplitParser {
            onRead: data => {
                let lines = data.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line.startsWith("{")) continue;
                    try {
                        let obj = JSON.parse(line);
                        if (obj.status === "watched_generate") {
                            root.refreshStatus();
                            if (obj.wallpaper === root.currentWallpaper && root.enabled) {
                                root.generateForCurrentWallpaper();
                            }
                        }
                    } catch (e) {}
                }
            }
        }
    }

    Timer {
        id: restartWatchTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.enabled && root.installed && !watchProcess.running) {
                root.startWatcher();
            }
        }
    }

    // Transition delay timer:
    // Ensures a cache-hit mask does not appear until the daemon's transition completes
    Timer {
        id: transitionTimer
        repeat: false
        onTriggered: {
            root.applyMask(root.pendingMaskPath);
        }
    }

    // ── Public API ──

    function refreshStatus() {
        if (!statusProcess.running) {
            statusProcess.running = true;
        }
    }

    function install(gpu) {
        if (root.busy) return;
        let args = ["python3", Quickshell.shellDir + "/scripts/wallpaper-depth.py", "install"];
        if (gpu) args.push("--gpu");
        installProcess.command = args;
        installProcess.running = true;
    }

    function clearCache() {
        if (!clearProcess.running) {
            clearProcess.running = true;
        }
    }

    function cancelPregenerate() {
        if (pregenProcess.running) {
            pregenProcess.running = false;
        }
        root.queueProgress = "";
    }

    function wallpaperApplying(path, force) {
        // Called by WallpaperSelector.applyWallpaper BEFORE set-wallpaper.sh is launched
        root.applyStartTime = Date.now();
        root.targetWallpaperPath = path;
        root.currentWallpaper = path;

        // Immediately fade out the old mask as it belongs to the previous wallpaper
        root.maskFade = 0.0;
        root.maskVisible = false;
        transitionTimer.stop();

        if ((!root.enabled && !force) || !root.installed) {
            root.currentMaskPath = "";
            root.maskUrl = "";
            return;
        }

        // Cancel background pregeneration so this current wallpaper takes priority
        if (pregenProcess.running) {
            pregenProcess.running = false;
            root.queueProgress = "";
        }

        // Abort previous generateProcess if still active
        if (generateProcess.running) {
            generateProcess.running = false;
        }

        root.statusText = "Generating...";
        let wpDir = Config.wallpaperDir.startsWith("~") ? (Quickshell.env("HOME") + Config.wallpaperDir.slice(1)) : Config.wallpaperDir;

        generateProcess.command = [
            "nice", "-n", "19",
            "ionice", "-c3",
            "python3", Quickshell.shellDir + "/scripts/wallpaper-depth.py",
            "generate", path,
            "--threshold", Config.depthThreshold.toString(),
            "--feather", Config.depthFeather.toString(),
            "--device", Config.depthDevice,
            "--wallpaper-dir", wpDir
        ];
        generateProcess.running = true;
    }

    function handleGenerationResult(maskPath, provider) {
        root.statusText = "Ready";
        if (provider) {
            root.activeDevice = (provider.indexOf("CUDA") !== -1) ? "NVIDIA GPU (CUDA)" : "CPU";
        }
        root.pendingMaskPath = maskPath;

        let elapsed = Date.now() - root.applyStartTime;
        let isCurrent = (root.applyStartTime === 0 || root.targetWallpaperPath === root.currentWallpaper);
        let delay = isCurrent ? 0 : Math.max(0, root.daemonTransitionDuration - elapsed + 50);

        if (delay > 0) {
            transitionTimer.interval = delay;
            transitionTimer.start();
        } else {
            root.applyMask(maskPath);
        }

        // If pre-generation is enabled and idle, trigger pre-generation of folder
        if (Config.depthPregenerate && !pregenProcess.running) {
            root.startPregeneration();
        }
    }

    function applyMask(maskPath) {
        if (!maskPath || maskPath.length === 0) return;
        root.currentMaskPath = maskPath;
        root.maskUrl = "file://" + maskPath;
        root.maskVisible = true;
        root.maskFade = 1.0;
        root.refreshStatus();
    }

    Process {
        id: detectTxtProcess
        command: ["cat", Quickshell.shellDir + "/data/current-wallpaper.txt"]
        property string result: ""
        stdout: SplitParser { onRead: data => { detectTxtProcess.result += data.trim(); } }
        onRunningChanged: {
            if (running) {
                result = "";
            } else if (result.length > 0 && !result.endsWith(".wa.jpg")) {
                let changed = (result !== root.currentWallpaper);
                root.currentWallpaper = result;
                if (root.enabled && root.installed && (changed || root.currentMaskPath === "")) {
                    root.wallpaperApplying(root.currentWallpaper);
                }
            } else {
                detectFallbackProcess.running = true;
            }
        }
    }

    Process {
        id: detectFallbackProcess
        command: ["bash", Quickshell.shellDir + "/scripts/get-current-wallpaper.sh", Config.wallpaperDaemon]
        property string result: ""
        stdout: SplitParser { onRead: data => { detectFallbackProcess.result += data.trim(); } }
        onRunningChanged: {
            if (running) {
                result = "";
            } else if (result.length > 0 && !result.endsWith(".wa.jpg")) {
                let changed = (result !== root.currentWallpaper);
                root.currentWallpaper = result;
                if (root.enabled && root.installed && (changed || root.currentMaskPath === "")) {
                    root.wallpaperApplying(root.currentWallpaper);
                }
            }
        }
    }

    function detectCurrentWallpaper() {
        if (!detectTxtProcess.running) {
            detectTxtProcess.running = true;
        }
    }

    function generateForCurrentWallpaper(force) {
        if (!root.installed) return;
        if (!root.enabled && !force) return;
        if (!root.currentWallpaper || root.currentWallpaper.length === 0) {
            detectCurrentWallpaper();
        } else {
            root.wallpaperApplying(root.currentWallpaper, force);
        }
    }

    function startPregeneration() {
        if (!root.enabled || !root.installed || !Config.depthPregenerate) return;
        if (pregenProcess.running || generateProcess.running || root.busy) return;

        let wpDir = Config.wallpaperDir.startsWith("~") ? (Quickshell.env("HOME") + Config.wallpaperDir.slice(1)) : Config.wallpaperDir;

        pregenProcess.command = [
            "nice", "-n", "19",
            "ionice", "-c3",
            "python3", Quickshell.shellDir + "/scripts/wallpaper-depth.py",
            "pregenerate", wpDir,
            "--threshold", Config.depthThreshold.toString(),
            "--feather", Config.depthFeather.toString(),
            "--device", Config.depthDevice
        ];
        pregenProcess.running = true;
    }

    function startWatcher() {
        if (!root.enabled || !root.installed) return;
        if (watchProcess.running) {
            watchProcess.running = false;
        }

        let wpDir = Config.wallpaperDir.startsWith("~") ? (Quickshell.env("HOME") + Config.wallpaperDir.slice(1)) : Config.wallpaperDir;

        watchProcess.command = [
            "nice", "-n", "19",
            "ionice", "-c3",
            "python3", Quickshell.shellDir + "/scripts/wallpaper-depth.py",
            "watch", wpDir,
            "--threshold", Config.depthThreshold.toString(),
            "--feather", Config.depthFeather.toString(),
            "--device", Config.depthDevice
        ];
        watchProcess.running = true;
    }

    function stopWatcher() {
        restartWatchTimer.stop();
        if (watchProcess.running) {
            watchProcess.running = false;
        }
    }

    // ── Watchers & Triggers ──

    onEnabledChanged: {
        if (root.enabled) {
            root.refreshStatus();
            if (root.installed) {
                root.generateForCurrentWallpaper();
                root.startWatcher();
                if (Config.depthPregenerate && !pregenProcess.running && !generateProcess.running) {
                    root.startPregeneration();
                }
            }
        } else {
            // Feature disabled: zero overhead, no processes, no masks
            root.stopWatcher();
            if (pregenProcess.running) pregenProcess.running = false;
            if (generateProcess.running) generateProcess.running = false;
            transitionTimer.stop();
            root.maskFade = 0.0;
            root.maskVisible = false;
            root.currentMaskPath = "";
            root.maskUrl = "";
            root.queueProgress = "";
        }
    }

    onInstalledChanged: {
        if (root.installed && root.enabled) {
            if (root.currentWallpaper && root.currentMaskPath === "") {
                root.generateForCurrentWallpaper();
            }
            root.startWatcher();
            if (Config.depthPregenerate && !pregenProcess.running && !generateProcess.running) {
                root.startPregeneration();
            }
        }
    }

    onCurrentWallpaperChanged: {
        if (root.installed && root.enabled && root.currentWallpaper && root.currentMaskPath === "") {
            root.generateForCurrentWallpaper();
        }
    }

    // When parameters change and autoGenerate is on:
    Connections {
        target: Config
        function onWallpaperDirChanged() {
            if (root.enabled && root.installed) {
                root.startWatcher();
            }
        }
        function onDepthThresholdChanged() {
            if (root.enabled && root.installed && Config.depthAutoGenerate && root.currentWallpaper) {
                root.wallpaperApplying(root.currentWallpaper);
            }
            if (root.enabled && root.installed) {
                root.startWatcher();
            }
        }
        function onDepthFeatherChanged() {
            if (root.enabled && root.installed && Config.depthAutoGenerate && root.currentWallpaper) {
                root.wallpaperApplying(root.currentWallpaper);
            }
            if (root.enabled && root.installed) {
                root.startWatcher();
            }
        }
        function onDepthDeviceChanged() {
            if (root.installed) {
                root.activeDevice = (Config.depthDevice === "gpu" && root.gpuInstalled) ? "NVIDIA GPU (CUDA)" :
                                    (Config.depthDevice === "auto" && root.gpuInstalled ? "NVIDIA GPU (CUDA)" : "CPU");
            }
            if (root.enabled && root.installed) {
                root.startWatcher();
            }
        }
        function onDepthPregenerateChanged() {
            if (Config.depthPregenerate) {
                root.startPregeneration();
            } else {
                root.cancelPregenerate();
            }
        }
    }

    Component.onCompleted: {
        root.refreshStatus();
        root.detectCurrentWallpaper();
    }
}
