pragma Singleton
import QtQuick
import QtCore
import Quickshell.Io

Item {
    id: root

    // Reference AppInfo so its singleton is constructed when Config.qml
    // is loaded. With the explicit Settings.location below, this is now
    // belt-and-braces rather than the load-bearing mechanism.
    readonly property var _appInfo: AppInfo

    Component.onCompleted: discard()

    Process {
        id: restartProcess
        command: [
            "bash",
            "-c",
            "notify-send 'Xeon Shell' 'Applying changes - restarting shell...' -t 2000 -h string:x-canonical-private-synchronous:xeon-restart; setsid bash -c 'sleep 1 && killall qs && sleep 0.3 && qs -c xeon-shell' >/dev/null 2>&1 & disown"
        ]
    }

    // Live values — the shell reads these at runtime, and they persist
    // to ~/.config/Xeon Shell/xeon-shell.conf via Settings{}.
    property alias wallpaperDir: settings.wallpaperDir
    property alias wallpaperDaemon: settings.wallpaperDaemon
    property alias showLockscreenSessionControls: settings.showLockscreenSessionControls
    property alias lockscreenAlignment: settings.lockscreenAlignment
    property alias rememberLastUser: settings.rememberLastUser
    property alias manageIdle: settings.manageIdle
    property alias idleTimeout: settings.idleTimeout
    property alias blueLightEnabled: settings.blueLightEnabled
    property alias blueLightManualOn: settings.blueLightManualOn
    property alias blueLightMode: settings.blueLightMode
    // Renamed from blueLightStartTime/EndTime → blueLightNightStart/NightEnd.
    // Old saved values under the old keys are ignored; new defaults apply.
    property alias blueLightNightStart: settings.blueLightNightStart
    property alias blueLightNightEnd: settings.blueLightNightEnd
    property alias blueLightUseIpLocation: settings.blueLightUseIpLocation
    property alias blueLightLatitude: settings.blueLightLatitude
    property alias blueLightLongitude: settings.blueLightLongitude
    property alias blueLightTransitionMinutes: settings.blueLightTransitionMinutes
    property alias blueLightDayTemp: settings.blueLightDayTemp
    property alias blueLightNightTemp: settings.blueLightNightTemp
    property alias desktopLayout: settings.desktopLayout

    // Draft values — the Settings UI edits these. They do not affect the
    // shell's live behavior until save() is called.
    property string draftWallpaperDir: ""
    property string draftWallpaperDaemon: ""
    property bool   draftShowLockscreenSessionControls: true
    property string draftLockscreenAlignment: "left"
    property bool   draftRememberLastUser: false
    property bool   draftManageIdle: true
    property int    draftIdleTimeout: 5
    property bool   draftBlueLightEnabled: false
    property bool   draftBlueLightManualOn: false
    property string draftBlueLightMode: "fixed_time"
    property string draftBlueLightNightStart: "22:00"
    property string draftBlueLightNightEnd: "06:00"
    property bool   draftBlueLightUseIpLocation: false
    property string draftBlueLightLatitude: ""
    property string draftBlueLightLongitude: ""
    property int    draftBlueLightTransitionMinutes: 30
    property int    draftBlueLightDayTemp: 6500
    property int    draftBlueLightNightTemp: 4500

    // True if any draft differs from its corresponding live value.
    readonly property bool isDirty:
        draftWallpaperDir !== wallpaperDir ||
        draftWallpaperDaemon !== wallpaperDaemon ||
        draftShowLockscreenSessionControls !== showLockscreenSessionControls ||
        draftLockscreenAlignment !== lockscreenAlignment ||
        draftRememberLastUser !== rememberLastUser ||
        draftManageIdle !== manageIdle ||
        draftIdleTimeout !== idleTimeout ||
        draftBlueLightEnabled !== blueLightEnabled ||
        draftBlueLightManualOn !== blueLightManualOn ||
        draftBlueLightMode !== blueLightMode ||
        draftBlueLightNightStart !== blueLightNightStart ||
        draftBlueLightNightEnd !== blueLightNightEnd ||
        draftBlueLightUseIpLocation !== blueLightUseIpLocation ||
        draftBlueLightLatitude !== blueLightLatitude ||
        draftBlueLightLongitude !== blueLightLongitude ||
        draftBlueLightTransitionMinutes !== blueLightTransitionMinutes ||
        draftBlueLightDayTemp !== blueLightDayTemp ||
        draftBlueLightNightTemp !== blueLightNightTemp

    function save() {
        let needsRestart = false;
        if (draftManageIdle !== manageIdle || draftIdleTimeout !== idleTimeout) {
            needsRestart = true;
        }

        wallpaperDir = draftWallpaperDir
        wallpaperDaemon = draftWallpaperDaemon
        showLockscreenSessionControls = draftShowLockscreenSessionControls
        lockscreenAlignment = draftLockscreenAlignment
        rememberLastUser = draftRememberLastUser
        manageIdle = draftManageIdle
        idleTimeout = draftIdleTimeout
        blueLightEnabled = draftBlueLightEnabled
        blueLightManualOn = draftBlueLightManualOn
        blueLightMode = draftBlueLightMode
        blueLightNightStart = draftBlueLightNightStart
        blueLightNightEnd = draftBlueLightNightEnd
        blueLightUseIpLocation = draftBlueLightUseIpLocation
        blueLightLatitude = draftBlueLightLatitude
        blueLightLongitude = draftBlueLightLongitude
        blueLightTransitionMinutes = draftBlueLightTransitionMinutes
        blueLightDayTemp = draftBlueLightDayTemp
        blueLightNightTemp = draftBlueLightNightTemp

        if (needsRestart) {
            restartProcess.running = true;
        }
    }

    function discard() {
        draftWallpaperDir = wallpaperDir
        draftWallpaperDaemon = wallpaperDaemon
        draftShowLockscreenSessionControls = showLockscreenSessionControls
        draftLockscreenAlignment = lockscreenAlignment
        draftRememberLastUser = rememberLastUser
        draftManageIdle = manageIdle
        draftIdleTimeout = idleTimeout
        draftBlueLightEnabled = blueLightEnabled
        draftBlueLightManualOn = blueLightManualOn
        draftBlueLightMode = blueLightMode
        draftBlueLightNightStart = blueLightNightStart
        draftBlueLightNightEnd = blueLightNightEnd
        draftBlueLightUseIpLocation = blueLightUseIpLocation
        draftBlueLightLatitude = blueLightLatitude
        draftBlueLightLongitude = blueLightLongitude
        draftBlueLightTransitionMinutes = blueLightTransitionMinutes
        draftBlueLightDayTemp = blueLightDayTemp
        draftBlueLightNightTemp = blueLightNightTemp
    }

    Settings {
        id: settings

        // The explicit path. This is what makes the fix robust: the
        // QSettings backend uses this directly and never consults
        // Qt.application.organization or Qt.application.name, so the
        // path is correct regardless of which property bindings have
        // fired or which Component.onCompleted handlers have run.
        location: AppInfo.settingsLocation

        category: "General"
        property string wallpaperDir: "~/Pictures/Wallpapers"
        property string wallpaperDaemon: "awww" // 'awww', 'swww', 'hyprpaper'
        property bool showLockscreenSessionControls: true
        property string lockscreenAlignment: "left" // 'left', 'right'
        property bool rememberLastUser: false
        property bool manageIdle: true
        property int idleTimeout: 5
        property bool blueLightEnabled: false
        property bool blueLightManualOn: false
        property string blueLightMode: "fixed_time"
        // Night-hours semantics: these define when the filter is ACTIVE.
        // Renamed from blueLightStartTime/EndTime to avoid silently
        // inverting the schedule for existing configs that stored day hours.
        property string blueLightNightStart: "22:00"
        property string blueLightNightEnd: "06:00"
        property bool blueLightUseIpLocation: false
        property string blueLightLatitude: ""
        property string blueLightLongitude: ""
        property int blueLightTransitionMinutes: 30
        property int blueLightDayTemp: 6500
        property int blueLightNightTemp: 4500
        property string desktopLayout: ""
    }
}
