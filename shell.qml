//@ pragma UseQApplication
// ─────────────────────────────────────────────────────────────────────────
// shell.qml — Quickshell entry point
//
// Run this with (from anywhere):
//   qs -c xeon-shell
// assuming this whole folder is placed at
//   ~/.config/quickshell/xeon-shell
//
// or point at it directly without installing it anywhere in particular:
//   qs -p /path/to/this/folder/shell.qml
//
// ShellRoot is just a container — it doesn't draw anything itself, it
// just holds the windows/singletons that make up your shell. Quickshell
// keeps this process running in the background (e.g. via `exec-once` in
// hyprland.conf) and both windows below stay hidden until toggled.
// ─────────────────────────────────────────────────────────────────────────
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQml
import "modules" as Modules
import "services"

ShellRoot {
    Component.onCompleted: {
        Quickshell.iconTheme = "Slot-Gray-Dark-Icons"
        dimProcess.command = ["bash", "-c", Quickshell.shellDir + "/scripts/idle-dim-manager.sh startup-restore && " + Quickshell.shellDir + "/scripts/idle-dim-manager.sh cache-displays"]
        dimProcess.running = true
    }

    // Launch custom clipboard watchers
    Process {
        command: ["sh", Quickshell.shellDir + "/scripts/clipboard-daemon.sh"]
        running: true
    }

    Modules.AppLauncher {
        id: appLauncher
    }

    Modules.WallpaperSelector {
        id: wallpaperSelector
    }

    Modules.NotificationCenter {
        id: notificationCenter
        onOpenSettings: settingsWindow.show()
    }

    Modules.NotificationPopup {
        id: notificationPopup
    }

    Modules.Osd {
        id: osd
    }

    Modules.ClipboardManager {
        id: clipboardManager
    }

    Modules.PowerMenu {
        id: powerMenu
    }

    Modules.ScreenCapture {
        id: screenCapture
        onOpenSettingsRequested: settingsWindow.showScreenshotTab()
    }

    Modules.DesktopMpris {
        id: desktopMpris
    }

    Modules.DesktopTray {
        id: desktopTray
    }

    Modules.SettingsWindow {
        id: settingsWindow
        editModeActive: desktopEditMode.active
        onRequestEditMode: desktopEditMode.startEditMode()
    }

    Modules.DesktopEditMode {
        id: desktopEditMode
        onClosed: (saved) => {
            settingsWindow.show()
        }
    }

    Modules.DesktopClock {
        id: desktopClock
    }

    Modules.DesktopCalendar {
        id: desktopCalendar
    }

    Modules.KeybindViewer {
        id: keybindViewer
    }

    Modules.WorkspaceOverview {
        id: workspaceOverview
        blocked: desktopEditMode.active || (lockscreen.fade > 0)
        onShownChanged: {
            if (shown && (tabSwitcher.active || tabSwitcher.shown)) {
                tabSwitcher.cancel();
            }
        }
    }

    Modules.TabSwitcher {
        id: tabSwitcher
        blocked: desktopEditMode.active || (lockscreen.fade > 0)
        onActiveChanged: {
            if (active && workspaceOverview.shown) {
                workspaceOverview.hide();
            }
        }
    }

    Modules.Lockscreen {
        id: lockscreen
    }

    Process {
        id: dimProcess
    }

    Process {
        id: restoreProcess
    }

    BlueLightFilter {
        id: blueLightFilter
    }



    // Note: Quickshell's QML hot-reload (on file save) does not automatically 
    // re-register top-level Wayland protocols like ext-idle-notify-v1. If you 
    // change IdleMonitor or IdleInhibitor properties, you MUST perform a full 
    // shell restart (killall qs && qs -c xeon-shell) for the changes to apply.
    IdleMonitor {
        id: idleMonitor
        enabled: Config.manageIdle
        timeout: Config.idleTimeout * 60
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) {
                lockscreen.lock()
            }
        }
    }

    IdleMonitor {
        id: dimIdleMonitor
        enabled: Config.manageIdle
        timeout: Math.max(Config.idleTimeout * 60 - 30, 1)
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) {
                dimProcess.command = ["bash", Quickshell.shellDir + "/scripts/idle-dim-manager.sh", "dim"]
                dimProcess.running = true
            } else {
                restoreProcess.command = ["bash", Quickshell.shellDir + "/scripts/idle-dim-manager.sh", "restore"]
                restoreProcess.running = true
            }
        }
    }

    property bool _manageIdleTracker: Config.manageIdle
    on_ManageIdleTrackerChanged: {
        if (!_manageIdleTracker) {
            restoreProcess.command = ["bash", Quickshell.shellDir + "/scripts/idle-dim-manager.sh", "restore"]
            restoreProcess.running = true
        }
    }

    PanelWindow {
        id: idleInhibitWindow
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "idle-inhibitor"
        exclusiveZone: -1
        color: "transparent"
        visible: true
        implicitWidth: 1
        implicitHeight: 1
        mask: Region {}
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: SystemMonitor.caffeinateEnabled
        window: idleInhibitWindow
    }

    // IPC handlers: these let you (or a Hyprland keybind) control the
    // windows above from a terminal, e.g.:
    //   qs -c xeon-shell ipc call launcher toggle
    //   qs -c xeon-shell ipc call wallpaper toggle
    // See hypr/launcher-binds.conf for ready-made Hyprland keybinds.
    IpcHandler {
        target: "launcher"
        function toggle(): void { appLauncher.toggle() }
        function open(): void { appLauncher.show() }
        function close(): void { appLauncher.hide() }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { wallpaperSelector.toggle() }
        function open(): void { wallpaperSelector.show() }
        function close(): void { wallpaperSelector.hide() }
    }

    IpcHandler {
        target: "theme"
        function reload(): void {
            Theme.forceReload()
        }
    }

    IpcHandler {
        target: "notif"
        function toggle(): void { notificationCenter.toggle() }
        function open(): void { notificationCenter.show() }
        function close(): void { notificationCenter.hide() }
    }

    IpcHandler {
        target: "osd"
        function volume(val: string): void { osd.showOsd("volume", val) }
        function brightness(val: string): void { osd.showOsd("brightness", val) }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { clipboardManager.toggle() }
        function open(): void { clipboardManager.show() }
        function close(): void { clipboardManager.hide() }
    }

    IpcHandler {
        target: "power"
        function toggle(): void { powerMenu.toggle() }
        function open(): void { powerMenu.show() }
        function close(): void { powerMenu.hide() }
    }

    IpcHandler {
        target: "screenshot"
        function toggle(): void { screenCapture.toggle() }
        function open(): void { screenCapture.show() }
        function close(): void { screenCapture.hide() }
        function region(): void { screenCapture.captureRegion() }
        function window(): void { screenCapture.captureWindow() }
        function output(): void { screenCapture.captureOutput() }
        function settings(): void { settingsWindow.showScreenshotTab() }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { settingsWindow.toggle() }
        function open(): void { settingsWindow.show() }
        function close(): void { settingsWindow.hide() }
    }

    IpcHandler {
        target: "desktopedit"
        function toggle(): void { desktopEditMode.toggle() }
        function open(): void { desktopEditMode.show() }
        function close(): void { desktopEditMode.hide() }
        function save(): void { desktopEditMode.saveAndClose() }
        function discard(): void { desktopEditMode.discardAndClose() }
        function status(): string {
            return JSON.stringify({
                active: desktopEditMode.active,
                workingLayout: desktopEditMode.workingLayout,
                storedLayout: Config.desktopLayout
            })
        }
        function reset(): void { Config.desktopLayout = "" }
    }

    IpcHandler {
        target: "keybinds"
        function toggle(): void { keybindViewer.toggle() }
        function open(): void { keybindViewer.show() }
        function close(): void { keybindViewer.hide() }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "overviewToggle"
        description: "Toggle workspace overview"
        onPressed: workspaceOverview.toggle()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "switcherNext"
        description: "Alt+Tab switcher next window"
        onPressed: tabSwitcher.next()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "switcherPrev"
        description: "Alt+Tab switcher previous window"
        onPressed: tabSwitcher.prev()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "switcherCommit"
        description: "Alt+Tab switcher commit selection"
        onPressed: tabSwitcher.commit()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "switcherCancel"
        description: "Alt+Tab switcher cancel"
        onPressed: tabSwitcher.cancel()
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { workspaceOverview.toggle() }
        function open(): void { workspaceOverview.show() }
        function close(): void { workspaceOverview.hide() }
    }

    IpcHandler {
        target: "switcher"
        function next(): void { tabSwitcher.next() }
        function prev(): void { tabSwitcher.prev() }
        function commit(): void { tabSwitcher.commit() }
        function cancel(): void { tabSwitcher.cancel() }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { lockscreen.lock() }
        function unlock(): void { lockscreen.unlock() }
    }

    IpcHandler {
        target: "config"
        function setManageIdle(val: string): void {
            if (val.toLowerCase() === "true") Config.manageIdle = true;
            else if (val.toLowerCase() === "false") Config.manageIdle = false;
        }
    }

    IpcHandler {
        target: "config_test"
        function testSave1Min(): void {
            Config.draftIdleTimeout = 1;
            Config.save();
        }
    }

    IpcHandler {
        target: "bluelight"
        function toggle(): void {
            Config.draftBlueLightEnabled = !Config.blueLightEnabled;
            Config.save();
        }
        function manual_toggle(): void {
            Config.draftBlueLightManualOn = !Config.blueLightManualOn;
            Config.save();
        }
        function set_fixed_time(start: string, end: string): void {
            Config.draftBlueLightMode = "fixed_time";
            Config.draftBlueLightNightStart = start;
            Config.draftBlueLightNightEnd = end;
            Config.save();
        }
        function set_sunset_sunrise_manual(lat: string, lon: string): void {
            Config.draftBlueLightMode = "sunset_sunrise";
            Config.draftBlueLightUseIpLocation = false;
            Config.draftBlueLightLatitude = lat;
            Config.draftBlueLightLongitude = lon;
            Config.save();
        }
        function set_sunset_sunrise_ip(): void {
            Config.draftBlueLightMode = "sunset_sunrise";
            Config.draftBlueLightUseIpLocation = true;
            Config.save();
        }
        function force_eval(): void {
            Config.draftBlueLightTransitionMinutes = 1;
            Config.save();
        }
        function set_transition_minutes(m: int): void {
            Config.draftBlueLightTransitionMinutes = m;
            Config.save();
        }
        function dump(): string {
            return JSON.stringify({
                enabled: Config.blueLightEnabled,
                manualOn: Config.blueLightManualOn,
                mode: Config.blueLightMode,
                nightStart: Config.blueLightNightStart,
                nightEnd: Config.blueLightNightEnd,
                dayTemp: Config.blueLightDayTemp,
                nightTemp: Config.blueLightNightTemp,
                draftManualOn: Config.draftBlueLightManualOn,
                draftEnabled: Config.draftBlueLightEnabled,
                draftNightTemp: Config.draftBlueLightNightTemp
            });
        }
    }

    IpcHandler {
        target: "depth"
        function status(): string {
            return JSON.stringify({
                installed: DepthService.installed,
                gpuInstalled: DepthService.gpuInstalled,
                hasNvidiaGpu: DepthService.hasNvidiaGpu,
                busy: DepthService.busy,
                statusText: DepthService.statusText,
                activeDevice: DepthService.activeDevice,
                queueProgress: DepthService.queueProgress,
                currentWallpaper: DepthService.currentWallpaper,
                maskUrl: DepthService.maskUrl.toString(),
                maskVisible: DepthService.maskVisible,
                maskFade: DepthService.maskFade,
                cacheSize: DepthService.cacheSizeFormatted
            });
        }
        function generate(): void {
            DepthService.generateForCurrentWallpaper(true);
        }
        function clear(): void {
            DepthService.clearCache();
        }
    }

    IpcHandler {
        target: "help"
        function display(): string {
            return `
Xeon Shell IPC Commands:

Usage: qs -c xeon-shell ipc call <target> <method> [args...]

Available Targets and Methods:

  launcher
    toggle()  - Toggle the application launcher
    open()    - Open the application launcher
    close()   - Close the application launcher

  wallpaper
    toggle()  - Toggle the wallpaper selector
    open()    - Open the wallpaper selector
    close()   - Close the wallpaper selector

  theme
    reload()  - Force reload the current theme

  notif
    toggle()  - Toggle the notification center
    open()    - Open the notification center
    close()   - Close the notification center

  osd
    volume(val: string)      - Show volume OSD
    brightness(val: string)  - Show brightness OSD

  config
    setManageIdle(val: string) - Enable or disable idle management (true/false)

  clipboard
    toggle()  - Toggle the clipboard manager
    open()    - Open the clipboard manager
    close()   - Close the clipboard manager

  power
    toggle()  - Toggle the power menu
    open()    - Open the power menu
    close()   - Close the power menu

  screenshot
    toggle()    - Toggle the screen capture overlay
    open()      - Open the screen capture overlay
    close()     - Close the screen capture overlay
    region()    - Capture a screen region
    window()    - Capture a specific window
    output()    - Capture a specific output/screen
    settings()  - Open Settings on the Screenshot tab

  settings
    toggle()  - Toggle the settings window
    open()    - Open the settings window
    close()   - Close the settings window

  desktopedit
    toggle()  - Toggle desktop edit mode
    open()    - Open desktop edit mode
    close()   - Close desktop edit mode

  keybinds
    toggle()  - Toggle the keybind viewer
    open()    - Open the keybind viewer
    close()   - Close the keybind viewer

  overview
    toggle()  - Toggle the workspace overview
    open()    - Open the workspace overview
    close()   - Close the workspace overview

  switcher
    next()    - Select next window in Alt+Tab switcher
    prev()    - Select previous window in Alt+Tab switcher
    commit()  - Commit selection and focus window
    cancel()  - Cancel switcher without changing focus

  lock
    lock()    - Lock the session
    unlock()  - Force unlock (testing/recovery only)

  bluelight
    toggle()  - Toggle the blue light filter

  depth
    status()   - Show current depth service status and cache info
    generate() - Generate depth mask for current wallpaper
    clear()    - Clear depth maps and mask cache

  help
    display()    - Show this help message
`
        }
    }
}
