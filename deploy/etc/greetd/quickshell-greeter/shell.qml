import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls

PanelWindow {
    id: win

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: -1
    color: "#000000"
    focusable: true
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // ── shared state (mapped to GreeterState) ──
    property string currentText: ""
    property bool isPasswordMode: false

    // ── Background: fallback color ──
    Rectangle {
        anchors.fill: parent
        color: "#121414" // Solid dark color
        visible: wallpaperImage.status !== Image.Ready
    }

    // ── Background: static wallpaper ──
    Image {
        id: wallpaperImage
        anchors.fill: parent
        source: "file:///var/lib/greetd/quickshell-greeter/wallpaper.jpg"
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
        cache: false
        onStatusChanged: {
            if (status === Image.Error) console.warn("Failed to load wallpaper:", source)
        }
    }

    // ── Background overlays (fading) ──
    Item {
        id: overlayContainer
        anchors.fill: parent

        // Dark overlay for contrast
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.15)
            visible: wallpaperImage.status === Image.Ready
        }
        
        // Edge Gradient for readability
        Rectangle {
            anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
            anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.6
            
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: GreeterState.lockscreenAlignment === "left" ? "black" : "transparent" }
                GradientStop { position: 1.0; color: GreeterState.lockscreenAlignment === "left" ? "transparent" : "black" }
            }
        }
    }

    // ── Global Input Handlers ──
    Item {
        id: globalInputHandler
        anchors.fill: parent
        focus: !win.isPasswordMode && !userFieldContainer.isUsernameMode
        Keys.onPressed: (event) => {
            if (!win.isPasswordMode && !userFieldContainer.isUsernameMode) {
                if (GreeterState.username === GreeterState.newUserSentinel && event.text.length > 0) {
                    userFieldContainer.isUsernameMode = true
                    userInlineInput.text = event.text
                    userInlineInput.cursorPosition = userInlineInput.text.length
                } else {
                    win.isPasswordMode = true
                    passwordInput.forceActiveFocus()
                }
                event.accepted = true
            }
        }
    }

    Timer {
        id: inactivityTimer
        interval: 15000
        running: win.isPasswordMode || userFieldContainer.isUsernameMode
        repeat: false
        onTriggered: {
            passwordInput.text = ""
            win.isPasswordMode = false
            if (userFieldContainer.isUsernameMode) {
                userInlineInput.text = ""
                userFieldContainer.isUsernameMode = false
            }
            globalInputHandler.forceActiveFocus()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!win.isPasswordMode && !userFieldContainer.isUsernameMode) {
                win.isPasswordMode = true
                passwordInput.forceActiveFocus()
            }
        }
    }

    // ── Main content layout ──
    Item {
        id: content
        anchors.fill: parent

        readonly property real designHeight: 1440
        readonly property real s: Math.max(0.1, height / designHeight)
        function px(v) { return Math.round(v * s) }

        Process { id: powerProcess }

        // ── SIDE CONTENT WRAPPER ──
        Item {
            anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
            anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: GreeterState.lockscreenAlignment === "left" ? content.px(120) : 0
            anchors.rightMargin: GreeterState.lockscreenAlignment === "right" ? content.px(120) : 0
            width: content.px(600)
            
            // ── TOP: Clock & Day ──
            Column {
                anchors.top: parent.top
                anchors.topMargin: content.px(120)
                anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                spacing: content.px(15)

                property var currentDate: new Date()
                Timer {
                    interval: 1000; running: true; repeat: true
                    onTriggered: parent.currentDate = new Date()
                }

                Text {
                    anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                    horizontalAlignment: GreeterState.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                    text: {
                        let d = parent.currentDate
                        let rawH = d.getHours()
                        let h = (rawH % 12 || 12).toString().padStart(2, '0')
                        let m = d.getMinutes().toString().padStart(2, '0')
                        return h + ":" + m
                    }
                    color: GreeterTheme.onPrimaryContainerColor
                    font.family: "Inter"
                    font.weight: Font.Black
                    font.pixelSize: content.px(160)
                }

                Text {
                    anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                    horizontalAlignment: GreeterState.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                    text: Qt.formatDate(parent.currentDate, "dddd / MMMM d").toUpperCase()
                    color: GreeterTheme.onPrimaryContainerColor
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
                anchors.verticalCenterOffset: content.px(80)
                anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                width: content.px(400)
                spacing: content.px(5)

                Text {
                    anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                    horizontalAlignment: GreeterState.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                    text: "CURRENT OPERATIVE"
                    color: GreeterTheme.onPrimaryContainerColor
                    font.family: "Inter"
                    font.weight: Font.Bold
                    font.letterSpacing: content.px(4)
                    font.pixelSize: content.px(12)
                    opacity: 0.6
                }

                Item {
                    id: userFieldContainer
                    anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                    width: content.px(400)
                    height: content.px(63) // 48 + 15 padding

                    property bool isUsernameMode: false
                    property string nextUsername: GreeterState.username

                    onNextUsernameChanged: {
                        if (!isUsernameMode) userChangeAnim.restart()
                    }

                    SequentialAnimation {
                        id: userChangeAnim
                        ParallelAnimation {
                            NumberAnimation { target: userDisplay; property: "opacity"; to: 0; duration: 75; easing.type: Easing.OutCubic }
                            NumberAnimation { target: userDisplay; property: "y"; to: content.px(-10); duration: 75; easing.type: Easing.OutCubic }
                        }
                        ScriptAction { 
                            script: {
                                userDisplay.text = userFieldContainer.nextUsername.toUpperCase()
                                userDisplay.color = (userFieldContainer.nextUsername === GreeterState.newUserSentinel) ? Qt.rgba(GreeterTheme.onPrimaryContainerColor.r, GreeterTheme.onPrimaryContainerColor.g, GreeterTheme.onPrimaryContainerColor.b, 0.4) : GreeterTheme.onPrimaryContainerColor 
                            }
                        }
                        PropertyAction { target: userDisplay; property: "y"; value: content.px(10) }
                        ParallelAnimation {
                            NumberAnimation { target: userDisplay; property: "opacity"; to: 1; duration: 75; easing.type: Easing.OutCubic }
                            NumberAnimation { target: userDisplay; property: "y"; to: 0; duration: 75; easing.type: Easing.OutCubic }
                        }

                    }

                    Text {
                        id: userDisplay
                        anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                        anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                        horizontalAlignment: GreeterState.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                        y: 0
                        text: GreeterState.username.toUpperCase()
                        color: userMArea.containsMouse ? GreeterTheme.primary : (GreeterState.username === GreeterState.newUserSentinel ? Qt.rgba(GreeterTheme.onPrimaryContainerColor.r, GreeterTheme.onPrimaryContainerColor.g, GreeterTheme.onPrimaryContainerColor.b, 0.4) : GreeterTheme.onPrimaryContainerColor)
                        font.family: "Inter"
                        font.weight: Font.Black
                        font.pixelSize: content.px(48)
                        font.underline: userMArea.containsMouse
                        bottomPadding: content.px(15)
                        visible: !userFieldContainer.isUsernameMode
                        scale: userMArea.containsMouse ? 1.04 : 1.0
                        transformOrigin: GreeterState.lockscreenAlignment === "left" ? Item.Left : Item.Right
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MouseArea {
                            id: userMArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (userFieldContainer.isUsernameMode) return
                                GreeterState.cycleUser()
                            }
                        }
                    }

                    TextInput {
                        id: userInlineInput
                        anchors.fill: userDisplay
                        horizontalAlignment: userDisplay.horizontalAlignment
                        color: GreeterTheme.onPrimaryContainerColor
                        font.family: "Inter"
                        font.weight: Font.Black
                        font.pixelSize: content.px(48)
                        bottomPadding: content.px(15)
                        visible: userFieldContainer.isUsernameMode
                        activeFocusOnTab: true
                        
                        onVisibleChanged: {
                            if (visible) {
                                forceActiveFocus()
                            }
                        }
                        
                        Keys.onEscapePressed: {
                            text = ""
                            userFieldContainer.isUsernameMode = false
                            globalInputHandler.forceActiveFocus()
                        }
                        Keys.onPressed: (event) => {
                            inactivityTimer.restart()
                            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                if (text.trim().length > 0) {
                                    GreeterState.commitNewUser(text)
                                    userFieldContainer.isUsernameMode = false
                                    userChangeAnim.restart()
                                    win.isPasswordMode = true
                                    passwordInput.forceActiveFocus()
                                }
                                event.accepted = true
                            }
                        }
                    }
                }

                // ── PASSWORD & LOCK MORPH CONTAINER ──
                Rectangle {
                    id: passwordContainer
                    anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                    
                    width: win.isPasswordMode ? parent.width : content.px(55)
                    height: content.px(55)
                    radius: win.isPasswordMode ? content.px(8) : height / 2
                    color: "transparent"
                    border.width: win.isPasswordMode ? 1 : 1
                    border.color: GreeterState.showFailure ? GreeterTheme.error : (passwordInput.activeFocus ? GreeterTheme.primary : Qt.rgba(GreeterTheme.outlineVariant.r, GreeterTheme.outlineVariant.g, GreeterTheme.outlineVariant.b, 0.4))
                    
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
                        onFinished: {
                            passwordInput.text = ""
                            win.currentText = ""
                        }
                    }
                    
                    // ── LOCK ICON ──
                    Item {
                        anchors.centerIn: parent
                        width: content.px(32)
                        height: content.px(32)
                        opacity: win.isPasswordMode ? 0 : 0.7
                        scale: win.isPasswordMode ? 0.5 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                        Image {
                            anchors.fill: parent
                            sourceSize.width: content.px(32)
                            sourceSize.height: content.px(32)
                            source: "data:image/svg+xml;utf8," + encodeURIComponent(
                                "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + GreeterTheme.onPrimaryContainerColor + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='4' y='10' width='16' height='12' rx='3' ry='3'></rect><path d='M7 10V6a5 5 0 0 1 10 0v4'></path></svg>"
                            )
                        }
                    }

                    // ── PASSWORD ELEMENTS WRAPPER ──
                    Item {
                        anchors.fill: parent
                        opacity: win.isPasswordMode ? 1 : 0
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
                            enabled: !GreeterState.unlockInProgress && !GreeterState.sessionStarting

                            onTextChanged: win.currentText = text
                            onAccepted: {
                                if (text.length > 0) GreeterState.authenticate(text)
                            }
                            Keys.onEscapePressed: {
                                text = ""
                                win.isPasswordMode = false
                                globalInputHandler.forceActiveFocus()
                            }
                            Keys.onPressed: (event) => {
                                inactivityTimer.restart()
                                event.accepted = false
                            }

                            Connections {
                                target: win
                                function onCurrentTextChanged() { 
                                    if (passwordInput.text !== win.currentText) {
                                        passwordInput.text = win.currentText 
                                    }
                                }
                            }
                            Connections {
                                target: GreeterState
                                function onFailed() { shakeAnim.start() }
                            }
                        }

                        // Placeholder
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: content.px(20)
                            visible: win.currentText.length === 0 && !passwordInput.activeFocus
                            text: "Password..."
                            color: Qt.rgba(GreeterTheme.onPrimaryContainerColor.r, GreeterTheme.onPrimaryContainerColor.g, GreeterTheme.onPrimaryContainerColor.b, 0.4)
                            font.pixelSize: content.px(16)
                            font.family: "Inter"
                        }

                        // Mask Area
                        Item {
                            id: maskArea
                            anchors.fill: parent
                            anchors.leftMargin: content.px(20); anchors.rightMargin: content.px(60)
                            clip: true
                            Row {
                                id: maskRow
                                height: parent.height
                                spacing: content.px(10)
                                x: 0
                                
                                readonly property string symbolFont: "CaskaydiaCove Nerd Font"
                                readonly property var symbolSet: [
                                    String.fromCodePoint(0xf0d7),
                                    String.fromCodePoint(0xf0d8),
                                    String.fromCodePoint(0xf0d9),
                                    String.fromCodePoint(0xf0da)
                                ]
                                property var maskSymbols: []

                                Connections {
                                    target: win
                                    function onCurrentTextChanged() {
                                        let arr = maskRow.maskSymbols.slice()
                                        while (arr.length > win.currentText.length) arr.pop()
                                        while (arr.length < win.currentText.length) {
                                            let prev = arr.length ? arr[arr.length - 1] : -1
                                            let i
                                            do { i = Math.floor(Math.random() * maskRow.symbolSet.length) }
                                            while (i === prev && maskRow.symbolSet.length > 1)
                                            arr.push(i)
                                        }
                                        maskRow.maskSymbols = arr
                                    }
                                }

                                Repeater {
                                    model: maskRow.maskSymbols.length
                                    Text {
                                        id: symbolText
                                        height: maskRow.height
                                        verticalAlignment: Text.AlignVCenter
                                        text: maskRow.symbolSet[maskRow.maskSymbols[index]]
                                        font.family: maskRow.symbolFont
                                        font.pixelSize: content.px(32)
                                        color: GreeterTheme.onPrimaryContainerColor

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
                            color: GreeterTheme.onPrimaryContainerColor
                            font.family: "Inter"
                            font.weight: Font.Bold
                            font.pixelSize: content.px(14)
                            font.letterSpacing: content.px(2)
                            opacity: win.currentText.length > 0 ? 1.0 : 0.4
                            
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: content.px(-10)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (win.currentText.length > 0) {
                                        GreeterState.authenticate(win.currentText)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── STATUS MESSAGE ──
                Text {
                    anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                    anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                    horizontalAlignment: GreeterState.lockscreenAlignment === "left" ? Text.AlignLeft : Text.AlignRight
                    text: GreeterState.sessionStarting ? "Starting session..." : GreeterState.statusMessage
                    color: GreeterState.showFailure ? GreeterTheme.error : Qt.rgba(GreeterTheme.onPrimaryContainerColor.r, GreeterTheme.onPrimaryContainerColor.g, GreeterTheme.onPrimaryContainerColor.b, 0.7)
                    font.pixelSize: content.px(14)
                    font.family: "Inter"
                    visible: text.length > 0
                }
            }

            // ── BOTTOM: Session Controls ──
            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: content.px(120)
                anchors.left: GreeterState.lockscreenAlignment === "left" ? parent.left : undefined
                anchors.right: GreeterState.lockscreenAlignment === "right" ? parent.right : undefined
                layoutDirection: GreeterState.lockscreenAlignment === "left" ? Qt.LeftToRight : Qt.RightToLeft
                spacing: content.px(40)
                visible: GreeterTheme.showLockscreenSessionControls

                component LockTextButton: Item {
                    property string text
                    property string command
                    property color textColor: mArea.containsMouse ? GreeterTheme.primary : GreeterTheme.onPrimaryContainerColor
                    
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

                // Current session indicator / cycler
                Item {
                    id: sessionItem
                    width: sessionRow.implicitWidth
                    height: sessionRow.implicitHeight
                    property string nextSessionName: GreeterState.sessionName
                    
                    onNextSessionNameChanged: sessionChangeAnim.restart()
                    
                    SequentialAnimation {
                        id: sessionChangeAnim
                        ParallelAnimation {
                            NumberAnimation { target: sessionLabel; property: "opacity"; to: 0; duration: 75; easing.type: Easing.OutCubic }
                            NumberAnimation { target: sessionLabel; property: "y"; to: content.px(-5); duration: 75; easing.type: Easing.OutCubic }
                        }
                        ScriptAction { 
                            script: {
                                sessionLabel.text = sessionItem.nextSessionName.toUpperCase()
                            }
                        }
                        PropertyAction { target: sessionLabel; property: "y"; value: content.px(5) }
                        ParallelAnimation {
                            NumberAnimation { target: sessionLabel; property: "opacity"; to: 1; duration: 75; easing.type: Easing.OutCubic }
                            NumberAnimation { target: sessionLabel; property: "y"; to: 0; duration: 75; easing.type: Easing.OutCubic }
                        }
                    }

                    Row {
                        id: sessionRow
                        spacing: content.px(15)
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Rectangle {
                            width: content.px(6)
                            height: width
                            radius: width / 2
                            color: sessionMArea.containsMouse ? GreeterTheme.primary : GreeterTheme.onPrimaryContainerColor
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: 0.5
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        
                        Text {
                            id: sessionLabel
                            text: GreeterState.sessionName.toUpperCase()
                            color: sessionMArea.containsMouse ? GreeterTheme.primary : GreeterTheme.onPrimaryContainerColor
                            font.family: "Inter"
                            font.weight: Font.Bold
                            font.pixelSize: content.px(14)
                            font.letterSpacing: content.px(2)
                            opacity: sessionMArea.containsMouse ? 1.0 : 0.6
                            font.underline: sessionMArea.containsMouse
                            scale: sessionMArea.containsMouse ? 1.08 : 1.0
                            transformOrigin: GreeterState.lockscreenAlignment === "left" ? Item.Left : Item.Right
                            y: 0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }
                    MouseArea {
                        id: sessionMArea
                        anchors.fill: parent
                        anchors.margins: content.px(-10)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GreeterState.cycleSession()
                    }
                }
            }
        }
    }
}
