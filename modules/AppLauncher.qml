// ─────────────────────────────────────────────────────────────────────────
// AppLauncher.qml — vertical list launcher
//
// Layout: search field → scrollable list of icon + name rows.
// Selection is highlighted with a rounded rect in Theme.primaryContainer.
// Keyboard: Up/Down to move, Enter to launch, Escape to close, type to
// filter. Mouse: hover to select, click to launch.
//
// Data source: Quickshell's built-in DesktopEntries singleton — reads
// every .desktop file on the system, no external binary needed.
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import "../services"

OverlayWindow {
    id: launcher
    panelWidth:  960
    panelHeight: 620
    cardRadius:  0 // Remove all rounding for the launcher

    property string currentWallpaperPath: "file://" + Quickshell.env("HOME") + "/.wa-thumb.jpg"

    // When false, mouse input is ignored (cursor hidden, hover-selection disabled).
    // Becomes true on first real mouse movement or click after the launcher opens.
    property bool mouseActivated: false

    // Ignores the initial burst of pointer events that Wayland delivers
    // when a surface appears under the cursor.  While running, all
    // onPositionChanged handlers are suppressed.
    Timer { id: mouseReadyTimer; interval: 150 }

    // Re-focus search and refresh the app list every time the panel opens.
    onShownChanged: {
        if (shown) {
            queryField.text = ""
            // Append timestamp to bypass image cache when wallpaper changes
            launcher.currentWallpaperPath = "file://" + Quickshell.env("HOME") + "/.wa-thumb.jpg?t=" + Date.now()
            refreshApps()
            // Make sure the launcher always starts at the top of the list when opened
            launcher.selectedIndex = 0
            list.positionViewAtBeginning()
            queryField.forceActiveFocus()
            // Suppress mouse input until the user actually moves or clicks
            launcher.mouseActivated = false
            mouseReadyTimer.restart()
        }
    }

    Component.onCompleted: {
        // Trigger Quickshell's lazy-loading of .desktop files immediately on startup 
        // so they are ready by the time the user first opens the launcher.
        refreshApps()
    }

    property var allApps: []
    property var results:  []
    property int selectedIndex: 0

    function refreshApps() {
        const apps = []
        for (const entry of DesktopEntries.applications.values) {
            if (!entry.noDisplay) apps.push(entry)
        }
        apps.sort((a, b) => a.name.localeCompare(b.name))
        allApps = apps
        applyFilter()
    }

    function fuzzyScore(query, text) {
        if (!text) return -1;
        query = query.toLowerCase();
        text = text.toLowerCase();
        if (query.length === 0) return 0;
        
        let qIdx = 0;
        let tIdx = 0;
        let score = 0;
        let lastMatchIdx = -2;
        
        while (qIdx < query.length && tIdx < text.length) {
            if (query[qIdx] === text[tIdx]) {
                if (lastMatchIdx === tIdx - 1) {
                    score += 5; // contiguous match
                } else {
                    score += 1;
                }
                if (tIdx === 0 || text[tIdx - 1] === ' ' || text[tIdx - 1] === '-') {
                    score += 10; // word boundary
                }
                lastMatchIdx = tIdx;
                qIdx++;
            }
            tIdx++;
        }
        
        if (qIdx === query.length) {
            score -= text.length * 0.1; // penalize longer strings
            if (text.startsWith(query)) score += 20;
            return score;
        }
        return -1;
    }

    function applyFilter() {
        const q = queryField.text.trim();
        if (q.length === 0) {
            results = allApps;
        } else {
            const scoredApps = [];
            for (let i = 0; i < allApps.length; i++) {
                const app = allApps[i];
                let maxScore = -1;
                
                const nameScore = fuzzyScore(q, app.name);
                if (nameScore > maxScore) maxScore = nameScore;
                
                if (app.genericName) {
                    const gScore = fuzzyScore(q, app.genericName);
                    if (gScore !== -1 && (gScore * 0.8) > maxScore) {
                        maxScore = gScore * 0.8;
                    }
                }
                
                if (app.keywords) {
                    for (let k = 0; k < app.keywords.length; k++) {
                        const kScore = fuzzyScore(q, app.keywords[k]);
                        if (kScore !== -1 && (kScore * 0.5) > maxScore) {
                            maxScore = kScore * 0.5;
                        }
                    }
                }
                
                if (maxScore !== -1) {
                    scoredApps.push({ app: app, score: maxScore });
                }
            }
            scoredApps.sort((a, b) => b.score - a.score);
            results = scoredApps.map(e => e.app);
        }
        selectedIndex = 0;
    }

    function moveSelection(delta) {
        if (results.length === 0) return
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta))
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function launch(entry) {
        if (!entry) return
        entry.execute()
        launcher.hide()
    }

    // ── Cursor-blanking overlay ─────────────────────────────────────────
    // Loader recreates a BlankCursor MouseArea each open so Qt re-delivers
    // pointer-enter (needed when the Wayland surface stayed mapped during
    // the close animation).  Destroyed once mouseActivated flips.
    Loader {
        anchors.fill: parent
        z: 100
        active: !launcher.mouseActivated
        sourceComponent: MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.BlankCursor
            onPositionChanged: {
                if (!mouseReadyTimer.running) launcher.mouseActivated = true
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left Side: Current Wallpaper ─────────────────────────────────
        Image {
            id: currentWall
            Layout.preferredWidth: 576
            Layout.fillHeight: true
            source: launcher.currentWallpaperPath
            sourceSize.width: 1080
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        // ── Right Side: App List ────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 384
            Layout.fillHeight: true
            Layout.margins: 20
            spacing: 12

            // ── Search field ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: Theme.radiusSmall
                color:  Theme.surfaceVariant

                border.width: queryField.activeFocus ? 2 : 0
                border.color: Theme.primary
                Behavior on border.width { NumberAnimation { duration: Theme.animFast } }

                RowLayout {
                    anchors.fill:    parent
                    anchors.margins: 12
                    spacing: 8

                    // Magnifier glyph (GPU-rendered Shape)
                    Shape {
                        width: 18; height: 18
                        Layout.alignment: Qt.AlignVCenter
                        layer.enabled: true; layer.samples: 4
                        ShapePath {
                            strokeWidth: 2; strokeColor: Theme.surfaceVariantText; fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathSvg { path: "M 7 7 m -5 0 a 5 5 0 1 0 10 0 a 5 5 0 1 0 -10 0 M 11 11 L 16 16" }
                        }
                    }

                    TextInput {
                        id: queryField
                        Layout.fillWidth:    true
                        Layout.fillHeight:   true
                        verticalAlignment:   TextInput.AlignVCenter
                        font.pixelSize:      17
                        color:               Theme.surfaceText
                        clip:                true

                        onTextChanged: launcher.applyFilter()

                        Keys.onEscapePressed: launcher.hide()
                        Keys.onReturnPressed: launcher.launch(launcher.results[launcher.selectedIndex])
                        Keys.onEnterPressed:  launcher.launch(launcher.results[launcher.selectedIndex])
                        Keys.onDownPressed:   launcher.moveSelection(1)
                        Keys.onUpPressed:     launcher.moveSelection(-1)

                        Text {
                            visible:              queryField.text.length === 0
                            text:                 "Search apps…"
                            color:                Theme.surfaceVariantText
                            font:                 queryField.font
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // ── Result count hint ───────────────
            Text {
                visible:         queryField.text.length > 0
                text:            launcher.results.length + " result" + (launcher.results.length === 1 ? "" : "s")
                color:           Theme.surfaceVariantText
                font.pixelSize:  12
                Layout.leftMargin: 4
            }

            // ── App list ────────────────────────────────────────────────────
            ListView {
                id:               list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip:             true
                model:            launcher.results
                spacing:          4
                layer.enabled:    true

                delegate: Item {
                    width:  list.width
                    height: 54

                    Rectangle {
                        id: pill
                        anchors.fill:    parent
                        anchors.margins: 2
                        radius:          Theme.radiusSmall
                        color: (index === launcher.selectedIndex || (launcher.mouseActivated && hoverArea.containsMouse))
                               ? Qt.rgba(Theme.onPrimaryContainerColor.r, Theme.onPrimaryContainerColor.g, Theme.onPrimaryContainerColor.b, 0.85)
                               : "transparent"

                        RowLayout {
                            anchors.fill:    parent
                            anchors.leftMargin:  12
                            anchors.rightMargin: 12
                            spacing: 12

                            IconImage {
                                width:  32
                                height: 32
                                source: Quickshell.iconPath(modelData.icon)
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                Layout.fillWidth:    true
                                text:                modelData.name
                                color: (index === launcher.selectedIndex || (launcher.mouseActivated && hoverArea.containsMouse)) ? Theme.inversePrimary : Theme.onPrimaryContainerColor
                                font.pixelSize:      15
                                elide:               Text.ElideRight
                                Layout.alignment:    Qt.AlignVCenter
                            }

                            Text {
                                visible:          modelData.genericName && modelData.genericName.length > 0
                                text:             modelData.genericName ?? ""
                                color: (index === launcher.selectedIndex || (launcher.mouseActivated && hoverArea.containsMouse)) ? Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.7) : Theme.surfaceVariantText
                                font.pixelSize:   12
                                elide:            Text.ElideRight
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    MouseArea {
                        id:           hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: {
                            if (!mouseReadyTimer.running && !launcher.mouseActivated)
                                launcher.mouseActivated = true
                            if (launcher.mouseActivated)
                                launcher.selectedIndex = index
                        }
                        onClicked: {
                            launcher.mouseActivated = true
                            launcher.launch(modelData)
                        }
                    }
                }
            }
        }
    }
}

