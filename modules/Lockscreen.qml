// ─────────────────────────────────────────────────────────────────────────
// Lockscreen.qml — QuickShell session lock screen
//
// Uses the secure WlSessionLock protocol (ext-session-lock-v1) for
// proper Wayland session locking, with PAM authentication.
//
// Trigger via:
//   qs -c xeon-shell ipc call lock lock
//   loginctl lock-session
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../services"

Scope {
    id: root

    // ── shared state ──
    readonly property string username: Quickshell.env("USER") || ""
    readonly property string home: Quickshell.env("HOME") || ""
    property string currentText: ""
    property string statusMessage: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool isPasswordMode: false
    signal failed()

    // ── Fade animations ──
    property real fade: 0
    property bool unlocking: false

    NumberAnimation { id: fadeIn;  target: root; property: "fade"; to: 1; duration: 600; easing.type: Easing.OutCubic }
    NumberAnimation { id: fadeOut; target: root; property: "fade"; to: 0; duration: 350; easing.type: Easing.InOutCubic; onFinished: { sessionLock.locked = false; root.unlocking = false } }

    function beginUnlock() {
        if (unlocking || !sessionLock.locked) return
        unlocking = true
        fadeIn.stop()
        fadeOut.start()
    }

    Timer {
        interval: 1200
        running: root.unlocking
        onTriggered: sessionLock.locked = false
    }

    Timer {
        id: fadeInSafety
        interval: 800
        running: sessionLock.locked && !root.unlocking && root.fade < 1
        onTriggered: root.fade = 1
    }

    // ── Password mask state ──
    readonly property string symbolFont: "CaskaydiaCove Nerd Font"

    readonly property var symbolSet: [
        String.fromCodePoint(0xf0d7),
        String.fromCodePoint(0xf0d8),
        String.fromCodePoint(0xf0d9),
        String.fromCodePoint(0xf0da)
    ]
    property var maskSymbols: []

    onCurrentTextChanged: {
        let arr = maskSymbols.slice()
        while (arr.length > currentText.length) arr.pop()
        while (arr.length < currentText.length) {
            let prev = arr.length ? arr[arr.length - 1] : -1
            let i
            do { i = Math.floor(Math.random() * symbolSet.length) }
            while (i === prev && symbolSet.length > 1)
            arr.push(i)
        }
        maskSymbols = arr
    }

    function lock() {
        if (!sessionLock.locked) sessionLock.locked = true
    }

    function unlock() {
        sessionLock.locked = false
    }

    function tryUnlock() {
        if (currentText === "" || unlockInProgress) return
        showFailure = false
        statusMessage = ""
        unlockInProgress = true
        pam.start()
    }

    // ── Time keeping ──
    property var currentDate: new Date()
    Timer {
        interval: 1000
        running: sessionLock.locked
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentDate = new Date()
    }

    PamContext {
        id: pam
        config: "quickshell"
        onPamMessage: { 
            if (responseRequired) respond(root.currentText)
            else root.statusMessage = pam.message 
        }
        onCompleted: result => {
            root.unlockInProgress = false
            root.currentText = ""
            if (result === PamResult.Success) {
                root.beginUnlock()
            } else {
                root.showFailure = true
                root.failed()
            }
        }
        onError: err => {
            console.warn("Lockscreen PAM error:", err)
            root.unlockInProgress = false
            root.showFailure = true
            root.failed()
        }
    }

    WlSessionLock {
        id: sessionLock
        onLockStateChanged: { if (locked) { root.isPasswordMode = false; root.currentText = ""; root.statusMessage = ""; root.showFailure = false; root.unlocking = false; root.fade = 0; fadeIn.restart() } }

        WlSessionLockSurface {
            id: lockSurface
            color: "transparent"

            // ── Background: static wallpaper ──
            Image {
                id: wallpaperImage
                anchors.fill: parent
                source: "file://" + root.home + "/.wa.jpg"
                fillMode: Image.PreserveAspectCrop
                visible: true
                cache: false
                onStatusChanged: {
                    if (status === Image.Error) console.warn("Failed to load wallpaper:", source)
                }
            }

            // ── Background overlays (fading) ──
            Item {
                id: overlayContainer
                anchors.fill: parent
                opacity: root.fade

                // Dark overlay for contrast
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.15)
                    visible: wallpaperImage.status === Image.Ready
                }
                
                // Edge Gradient for readability
                Rectangle {
                    anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * 0.6
                    
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Config.lockscreenAlignment === "left" ? "black" : "transparent" }
                        GradientStop { position: 1.0; color: Config.lockscreenAlignment === "left" ? "transparent" : "black" }
                    }
                }
            }

            // ── Global Input Handlers ──
            Item {
                id: globalInputHandler
                anchors.fill: parent
                focus: !root.isPasswordMode
                Keys.onPressed: (event) => {
                    if (!root.isPasswordMode) {
                        root.isPasswordMode = true
                        passwordInput.forceActiveFocus()
                        event.accepted = true
                    }
                }
            }

            Timer {
                id: inactivityTimer
                interval: 15000
                running: root.isPasswordMode
                repeat: false
                onTriggered: {
                    passwordInput.text = ""
                    root.isPasswordMode = false
                    globalInputHandler.forceActiveFocus()
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (!root.isPasswordMode) {
                        root.isPasswordMode = true
                        passwordInput.forceActiveFocus()
                    }
                }
            }

            // ── Main content layout ──
            Item {
                id: content
                anchors.fill: parent
                opacity: Math.max(0, Math.min(1, (root.fade - 0.25) / 0.75))

                readonly property real designHeight: 1440
                readonly property real s: Math.max(0.1, height / designHeight)
                function px(v) { return Math.round(v * s) }

                // ── PROCESS FOR SESSION COMMANDS ──
                Process { id: powerProcess }

                // ── SIDE CONTENT WRAPPER ──
                Item {
                    anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Config.lockscreenAlignment === "left" ? content.px(120) : 0
                    anchors.rightMargin: Config.lockscreenAlignment === "right" ? content.px(120) : 0
                    width: content.px(600)
                    
                    // ── TOP: Clock & Day ──
                    Column {
                        anchors.top: parent.top
                        anchors.topMargin: content.px(120)
                        anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                        anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                        spacing: content.px(15)

                        Text {
                            anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                            anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                            horizontalAlignment: Config.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                            text: {
                                let rawH = root.currentDate.getHours()
                                let h = (rawH % 12 || 12).toString().padStart(2, '0')
                                let m = root.currentDate.getMinutes().toString().padStart(2, '0')
                                return h + ":" + m
                            }
                            color: Theme.onPrimaryContainerColor
                            font.family: "Inter"
                            font.weight: Font.Black
                            font.pixelSize: content.px(160)
                        }

                        Text {
                            anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                            anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                            horizontalAlignment: Config.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                            text: Qt.formatDate(root.currentDate, "dddd / MMMM d").toUpperCase()
                            color: Theme.onPrimaryContainerColor
                            font.family: "Inter"
                            font.weight: Font.Bold
                            font.letterSpacing: content.px(8)
                            font.pixelSize: content.px(16)
                            opacity: 0.8
                        }
                    }

                    // ── MIDDLE: Login ──
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: content.px(80) // Slightly below exact center
                        anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                        anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                        width: content.px(400)
                        spacing: content.px(5)

                        Text {
                            anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                            anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                            horizontalAlignment: Config.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                            text: "CURRENT OPERATIVE"
                            color: Theme.onPrimaryContainerColor
                            font.family: "Inter"
                            font.weight: Font.Bold
                            font.letterSpacing: content.px(4)
                            font.pixelSize: content.px(12)
                            opacity: 0.6
                        }

                        Text {
                            anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                            anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                            horizontalAlignment: Config.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                            text: root.username.toUpperCase()
                            color: Theme.onPrimaryContainerColor
                            font.family: "Inter"
                            font.weight: Font.Black
                            font.pixelSize: content.px(48)
                            bottomPadding: content.px(15)
                        }

                        // ── PASSWORD & LOCK MORPH CONTAINER ──
                        Rectangle {
                            id: passwordContainer
                            anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                            anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                            
                            // Width transitions from icon-size (55) to full width
                            width: root.isPasswordMode ? parent.width : content.px(55)
                            height: content.px(55)
                            radius: root.isPasswordMode ? content.px(8) : height / 2
                            color: "transparent"
                            border.width: root.isPasswordMode ? 1 : 1
                            border.color: root.showFailure ? Theme.error : (passwordInput.activeFocus ? Theme.primary : Qt.rgba(Theme.outlineVariant.r, Theme.outlineVariant.g, Theme.outlineVariant.b, 0.4))
                            
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 300 } }

                            // Shake animation on failed auth
                            transform: Translate { id: shakeTranslate; x: 0 }
                            SequentialAnimation {
                                id: shakeAnim
                                loops: 1
                                NumberAnimation { target: shakeTranslate; property: "x"; to: content.px(-20); duration: 50;  easing.type: Easing.OutQuad }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: content.px(20);  duration: 50;  easing.type: Easing.OutQuad }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: content.px(-15); duration: 50;  easing.type: Easing.OutQuad }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: content.px(15);  duration: 50;  easing.type: Easing.OutQuad }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: content.px(-5);  duration: 50;  easing.type: Easing.OutQuad }
                                NumberAnimation { target: shakeTranslate; property: "x"; to: 0;   duration: 50;  easing.type: Easing.OutQuad }
                            }
                            
                            // ── LOCK ICON ──
                            Item {
                                anchors.centerIn: parent
                                width: content.px(32)
                                height: content.px(32)
                                opacity: root.isPasswordMode ? 0 : 0.7
                                scale: root.isPasswordMode ? 0.5 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                Image {
                                    anchors.fill: parent
                                    sourceSize.width: content.px(32)
                                    sourceSize.height: content.px(32)
                                    source: "data:image/svg+xml;utf8," + encodeURIComponent(
                                        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + Theme.onPrimaryContainerColor + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='4' y='10' width='16' height='12' rx='3' ry='3'></rect><path d='M7 10V6a5 5 0 0 1 10 0v4'></path></svg>"
                                    )
                                }
                            }

                            // ── PASSWORD ELEMENTS WRAPPER ──
                            Item {
                                anchors.fill: parent
                                opacity: root.isPasswordMode ? 1 : 0
                                visible: opacity > 0
                                clip: true
                                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: passwordInput.forceActiveFocus()
                                }

                                TextInput {
                                    id: passwordInput
                                    anchors.fill: parent
                                    opacity: 0
                                    cursorVisible: false
                                    echoMode: TextInput.Password
                                    enabled: !root.unlockInProgress && !root.unlocking

                                    onTextChanged: root.currentText = text
                                    onAccepted: root.tryUnlock()
                                    Keys.onEscapePressed: {
                                        text = ""
                                        root.isPasswordMode = false
                                        globalInputHandler.forceActiveFocus()
                                    }
                                    Keys.onPressed: (event) => {
                                        inactivityTimer.restart()
                                        event.accepted = false
                                    }

                                    Connections {
                                        target: root
                                        function onCurrentTextChanged() { 
                                            if (passwordInput.text !== root.currentText) {
                                                passwordInput.text = root.currentText 
                                            }
                                        }
                                        function onFailed() { shakeAnim.start() }
                                    }
                                }

                                // Placeholder
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: content.px(20)
                                    visible: root.currentText.length === 0 && !passwordInput.activeFocus
                                    text: "Password..."
                                    color: Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.4)
                                    font.pixelSize: content.px(16)
                                    font.family: "Inter"
                                }

                                // Mask Area
                                Item {
                                    id: maskArea
                                    anchors.fill: parent
                                    anchors.leftMargin: content.px(20); anchors.rightMargin: content.px(60) // Leave space for GO button
                                    clip: true
                                    Row {
                                        id: maskRow
                                        height: parent.height
                                        spacing: content.px(10)
                                        x: 0
                                        Repeater {
                                            model: root.maskSymbols.length
                                            Text {
                                                id: symbolText
                                                height: maskRow.height
                                                verticalAlignment: Text.AlignVCenter
                                                text: root.symbolSet[root.maskSymbols[index]]
                                                font.family: root.symbolFont
                                                font.pixelSize: content.px(32)
                                                color: Theme.onPrimaryContainerColor

                                                scale: 0.7
                                                opacity: 0
                                                Component.onCompleted: popAnim.start()
                                                ParallelAnimation {
                                                    id: popAnim
                                                    NumberAnimation { target: symbolText; property: "opacity"; to: 1; duration: 120; easing.type: Easing.OutBack }
                                                    NumberAnimation { target: symbolText; property: "scale"; to: 1; duration: 120; easing.type: Easing.OutBack }
                                                }
                                            }
                                        }
                                    }
                                }

                                // GO Button
                                Text {
                                    text: "GO"
                                    anchors.right: parent.right
                                    anchors.rightMargin: content.px(20)
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.onPrimaryContainerColor
                                    font.family: "Inter"
                                    font.weight: Font.Bold
                                    font.pixelSize: content.px(14)
                                    font.letterSpacing: content.px(2)
                                    opacity: root.currentText.length > 0 ? 1.0 : 0.4
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: content.px(-10)
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.tryUnlock()
                                    }
                                }
                            }
                        }

                        // ── PAM STATUS MESSAGE ──
                        Text {
                            anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                            anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                            horizontalAlignment: Config.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                            text: root.statusMessage
                            color: pam.messageIsError ? Theme.error : Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.7)
                            font.pixelSize: content.px(14)
                            font.family: "Inter"
                            visible: text.length > 0
                        }
                    }

                    // ── BOTTOM: Session Controls ──
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: content.px(120)
                        anchors.left: Config.lockscreenAlignment === "left" ? parent.left : undefined
                        anchors.right: Config.lockscreenAlignment === "right" ? parent.right : undefined
                        layoutDirection: Config.lockscreenAlignment === "left" ? Qt.LeftToRight : Qt.RightToLeft
                        spacing: content.px(40)
                        visible: Config.showLockscreenSessionControls

                        component LockTextButton: Item {
                            property string text
                            property string command
                            property color textColor: mArea.containsMouse ? Theme.primary : Theme.onPrimaryContainerColor
                            
                            width: label.implicitWidth
                            height: label.implicitHeight
                            
                            Text {
                                id: label
                                text: parent.text
                                color: parent.textColor
                                font.family: "Inter"
                                font.weight: Font.Bold
                                font.pixelSize: content.px(14)
                                font.letterSpacing: content.px(2)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: mArea
                                anchors.fill: parent
                                anchors.margins: content.px(-10)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    powerProcess.command = ["sh", "-c", parent.command]
                                    powerProcess.running = true
                                }
                            }
                        }

                        LockTextButton {
                            text: "SHUTDOWN"
                            command: "systemctl poweroff"
                        }

                        LockTextButton {
                            text: "REBOOT"
                            command: "systemctl reboot"
                        }

                        // Current session indicator
                        Row {
                            spacing: content.px(15)
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Rectangle {
                                width: content.px(6)
                                height: width
                                radius: width / 2
                                color: Theme.onPrimaryContainerColor
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: 0.5
                            }
                            
                            Text {
                                text: Quickshell.env("XDG_SESSION_DESKTOP") ? Quickshell.env("XDG_SESSION_DESKTOP").toUpperCase() + " (WAYLAND)" : "WAYLAND SESSION"
                                color: Theme.onPrimaryContainerColor
                                font.family: "Inter"
                                font.weight: Font.Bold
                                font.pixelSize: content.px(14)
                                font.letterSpacing: content.px(2)
                                opacity: 0.5
                            }
                        }
                    }
                }
            }
        }
    }
}
