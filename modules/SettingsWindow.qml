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
    cardRadius: Theme.radiusLarge
    hasBorder: true

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
        "Wallpaper Wallpaper Directory The absolute path to the directory containing your wallpaper images. Wallpaper Daemon The backend service used to set and render your desktop wallpapers.",
        "Lock Screen Lockscreen Power Menu Allow session control actions (Suspend, Reboot, Shutdown) directly from the lockscreen. Lockscreen Alignment Position the lockscreen elements aligned to the left or right edge of the screen.",
        "Greeter Remember Last User Save the last logged-in user and session to automatically pre-select them on the next boot.",
        "Display Manage idle behavior Automatically lock the screen when the system is idle. Lock timeout Time in minutes before the screen is locked. Blue Light Filter Toggle the blue light filter (night light). Turn on now Manually force the blue light filter on. Mode Fixed Time, Sunset/Sunrise Night Schedule Night starts Night ends The filter is active between these times Coordinates Use realtime location based on IP Transition Duration Time in minutes for the color temperature to transition. Day Temperature Color temperature during the day (K). Night Temperature Color temperature at night (K)."
    ]

    function commitChanges(isFromPopup) {
        let needsGreeterSync = (Config.draftLockscreenAlignment !== Config.lockscreenAlignment) || (Config.draftRememberLastUser !== Config.rememberLastUser);
        Config.save();
        
        if (needsGreeterSync) {
            applyProc.isPopup = isFromPopup;
            applyProc.command = ["bash", "-c", "python3 ~/.config/quickshell/xeon-shell/scripts/write-greeter-snapshot.py --alignment " + Config.lockscreenAlignment + " --remember " + (Config.rememberLastUser ? "true" : "false")]
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
        if (Config.isDirty) {
            unsavedPopup.visible = true
        } else {
            root.hide()
        }
    }

    onVisibleChanged: {
        if (!visible && Config.isDirty) {
            visible = true
            requestClose()
        }
    }

    onShownChanged: {
        if (shown) {
            Config.discard()
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
                    model: ["Wallpaper", "Lock Screen", "Greeter", "Display"]
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
                            text: tabList.currentIndex === 0 ? "⚙  Wallpaper Settings" : (tabList.currentIndex === 1 ? "⚙  Lock Screen Settings" : (tabList.currentIndex === 2 ? "⚙  Greeter Settings" : "⚙  Display Settings"))
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
