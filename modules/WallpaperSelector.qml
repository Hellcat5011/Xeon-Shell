// ─────────────────────────────────────────────────────────────────────────
// WallpaperSelector.qml — floating 3-image depth carousel
//
// Visual: three rounded wallpaper thumbnails with no card background.
// The centre image sits in front (z=2), flanking images peek from behind
// (z=0), matching the reference image layout.
//
// Fixes in this version:
//   • cardTransparent: true  — no card box, only the images float
//   • forceActiveFocus on open + Keys.on*Pressed — arrow keys now work
//   • Theme.file.reload() called after wallpaper script exits — forces an
//     immediate colour re-read because matugen uses atomic renames which
//     inotify's IN_MODIFY never catches
//   • Flanking images positioned at 22 %/78 % so they overlap behind the
//     centre image, replicating the carousel depth look from the reference
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Effects
import "../services"

OverlayWindow {
    id: picker
    WlrLayershell.namespace: "wallpaper"
    panelWidth:      picker.width
    panelHeight:     618
    cardRadius:      Theme.radiusLarge
    cardTransparent: true

    property string wallpaperDir: Config.wallpaperDir.startsWith("~") ? (Quickshell.env("HOME") + Config.wallpaperDir.slice(1)) : Config.wallpaperDir
    property var    _originalWallpapers: []
    property var    wallpapers:   []
    property bool   applying:     false
    property int    currentIndex: 0

    Component.onCompleted: {
        scanProcess.running = true
    }

    onShownChanged: {
        if (shown) {
            shuffleAndDisplay()
            if (!scanProcess.running)
                scanProcess.running = true
        }
    }

    onWallpaperDirChanged: {
        picker._originalWallpapers = []
        picker.wallpapers = []
        if (!scanProcess.running)
            scanProcess.running = true
    }

    function shuffleAndDisplay() {
        var arr = picker._originalWallpapers.slice()
        for (var i = arr.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1))
            var temp = arr[i]
            arr[i] = arr[j]
            arr[j] = temp
        }
        var duplicatedArr = []
        while (duplicatedArr.length < 9 && arr.length > 0) {
            duplicatedArr = duplicatedArr.concat(arr)
        }
        picker.wallpapers = duplicatedArr
        picker.currentIndex = 0
        if (picker.shown) carousel.forceActiveFocus()
    }

    Process {
        id: scanProcess
        command: ["bash", Quickshell.shellDir + "/scripts/gen-wallpaper-thumbs.sh", picker.wallpaperDir]
        property var _buffer: []

        onRunningChanged: {
            if (running) {
                _buffer = []
            } else {
                picker._originalWallpapers = _buffer
                if (picker.shown && picker.wallpapers.length === 0)
                    picker.shuffleAndDisplay()
            }
        }

        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split("|")
                if (parts.length >= 2)
                    scanProcess._buffer.push({original: parts[0], thumb: parts[1]})
                else if (parts[0] && parts[0].length > 0)
                    scanProcess._buffer.push({original: parts[0], thumb: parts[0]})
            }
        }
    }

    Process {
        id: applyProcess
        onExited: (exitCode) => {
            picker.applying = false
            if (exitCode === 0) {
                Theme.forceReload()
                picker.hide()
            }
        }
    }

    function applyWallpaper(path) {
        picker.applying = true
        applyProcess.command = ["sh", Quickshell.shellDir + "/scripts/set-wallpaper.sh", path, Config.wallpaperDaemon]
        applyProcess.running  = true
    }

    // ── Carousel (Dynamic PathView for flawless fluid animation) ───────
    PathView {
        id: carousel
        anchors.fill: parent

        focus: true
        Keys.onLeftPressed:   decrementCurrentIndex()
        Keys.onRightPressed:  incrementCurrentIndex()
        Keys.onEscapePressed: picker.hide()
        Keys.onReturnPressed: {
            if (!picker.applying && picker.wallpapers.length > 0)
                picker.applyWallpaper(picker.wallpapers[picker.currentIndex].original)
        }
        Keys.onEnterPressed: {
            if (!picker.applying && picker.wallpapers.length > 0)
                picker.applyWallpaper(picker.wallpapers[picker.currentIndex].original)
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                var forward = event.angleDelta.y < 0 || event.angleDelta.x < 0
                if (forward) carousel.incrementCurrentIndex()
                else         carousel.decrementCurrentIndex()
                event.accepted = true
            }
        }

        model: picker.wallpapers
        currentIndex: picker.currentIndex
        onCurrentIndexChanged: picker.currentIndex = currentIndex

        pathItemCount: picker.wallpapers.length
        preferredHighlightBegin: 0.5
        preferredHighlightEnd:   0.5
        highlightRangeMode:      PathView.StrictlyEnforceRange
        snapMode:                PathView.SnapToItem
        highlightMoveDuration:   250

        // ── Dynamic Scalable Path ─────────────────────────────────────────
        path: Path {
            id: dynamicPath
            property real n: Math.max(9, carousel.count)
            startX: carousel.width * (0.4 - 0.0625 * dynamicPath.n)
            startY: carousel.height / 2

            PathAttribute { name: "itemWidthScale"; value: 0.12 }
            PathAttribute { name: "zOrder"; value: 0 }

            PathLine { x: carousel.width * 0.275; y: carousel.height / 2 }
            PathPercent { value: 0.5 - 1.0 / dynamicPath.n }
            PathAttribute { name: "itemWidthScale"; value: 0.12 }
            PathAttribute { name: "zOrder"; value: 1 }

            PathLine { x: carousel.width * 0.500; y: carousel.height / 2 }
            PathPercent { value: 0.50000 }
            PathAttribute { name: "itemWidthScale"; value: 0.32 }
            PathAttribute { name: "zOrder"; value: 10 }

            PathLine { x: carousel.width * 0.725; y: carousel.height / 2 }
            PathPercent { value: 0.5 + 1.0 / dynamicPath.n }
            PathAttribute { name: "itemWidthScale"; value: 0.12 }
            PathAttribute { name: "zOrder"; value: 1 }

            PathLine { x: carousel.width * (0.6 + 0.0625 * dynamicPath.n); y: carousel.height / 2 }
            PathPercent { value: 1.00000 }
            PathAttribute { name: "itemWidthScale"; value: 0.12 }
            PathAttribute { name: "zOrder"; value: 0 }
        }

        // ── Delegate ──────────────────────────────────────────────────────
        delegate: Item {
            id: delegateRoot
            readonly property bool isCurrent: PathView.isCurrentItem
            property real skewVal: -0.25

            z: PathView.zOrder ?? 0

            width:  carousel.width * (PathView.itemWidthScale ?? 0.12)
            height: carousel.height * 0.80

            // ── Skewed Container ──────────────────────────────────────────
            Item {
                id: clipItem
                width: parent.width
                height: parent.height
                x: Math.abs(parent.height * skewVal / 2) // Shift right to counteract visual tilt
                y: 0
                clip: true
                antialiasing: true

                transform: Matrix4x4 {
                    matrix: Qt.matrix4x4(
                        1, skewVal, 0, 0,
                        0, 1,       0, 0,
                        0, 0,       1, 0,
                        0, 0,       0, 1
                    )
                }

                Image {
                    id: img
                    // Enlarge and shift right to perfectly balance the visual tilt illusion,
                    // without cropping out of the clipped corners.
                    width: parent.width + Math.abs(parent.height * skewVal * 2)
                    height: parent.height
                    x: skewVal < 0 ? parent.height * skewVal * 1.4 : -parent.height * skewVal * 1.4
                    y: 0
                    antialiasing: true

                    source: "file://" + modelData.thumb
                    sourceSize.width: carousel.width * 0.35
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    
                    opacity: img.status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

                    transform: Matrix4x4 {
                        matrix: Qt.matrix4x4(
                            1, -skewVal, 0, 0,
                            0, 1,        0, 0,
                            0, 0,        1, 0,
                            0, 0,        0, 1
                        )
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    // Bind border width directly to the width scale for perfectly continuous zooming
                    border.width: Math.max(0, ((PathView.itemWidthScale ?? 0.12) - 0.12) / 0.20 * 3)
                    border.color: Theme.primary
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.55)
                    visible: picker.applying && isCurrent
                    Text {
                        anchors.centerIn: parent
                        text: "Applying…"
                        color: "white"
                        font.pixelSize: 20
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !picker.applying
                    onClicked: {
                        if (isCurrent) {
                            picker.applyWallpaper(modelData.original)
                        } else {
                            carousel.currentIndex = index
                        }
                    }
                }
            }
        }
    }
}
