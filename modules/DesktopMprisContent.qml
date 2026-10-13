import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import "../services"

Item {
    id: root

    property bool interactive: true
    property bool transparentBg: false
    property string customFont: ""

    readonly property real defaultWidth: 400
    readonly property real defaultHeight: 170
    readonly property real scaleFactor: Math.max(0.55, Math.min(width / defaultWidth, height / defaultHeight))

    // ── Album-art palette ─────────────────────────────────────────────
    property color accentColor: Theme.primary
    property color waveBackColor: Theme.primary
    property color waveMidColor: Theme.primary
    property color waveFrontColor: Theme.primary

    Behavior on accentColor    { ColorAnimation { duration: 500 } }
    Behavior on waveBackColor  { ColorAnimation { duration: 500 } }
    Behavior on waveMidColor   { ColorAnimation { duration: 500 } }
    Behavior on waveFrontColor { ColorAnimation { duration: 500 } }

    onAccentColorChanged: progressCanvas.requestPaint()
    onWaveBackColorChanged: progressCanvas.requestPaint()
    onWaveMidColorChanged: progressCanvas.requestPaint()
    onWaveFrontColorChanged: progressCanvas.requestPaint()

    // h / h2 are hues in 0..1, s / s2 saturations in 0..1
    function setPalette(h, s, h2, s2) {
        accentColor    = Qt.hsla(h,  s,        0.62, 1)
        waveBackColor  = Qt.hsla(h2, s2 * 0.9, 0.50, 1)
        waveMidColor   = Qt.hsla(h,  s,        0.66, 1)
        waveFrontColor = Qt.hsla(h,  s * 0.45, 0.90, 1)
    }

    // True while the palette comes from matugen (no art, or art without usable colour)
    property bool usingThemePalette: true

    // Matugen palette — same roles the rest of the widget uses
    function applyFallbackPalette() {
        usingThemePalette = true
        accentColor    = Theme.primary
        waveBackColor  = Theme.secondary
        waveMidColor   = Theme.primary
        waveFrontColor = Theme.onPrimaryContainerColor
    }

    // Keep the fallback live when matugen regenerates colors.json
    Connections {
        target: Theme
        function onPrimaryChanged()                 { if (root.usingThemePalette) root.applyFallbackPalette() }
        function onSecondaryChanged()               { if (root.usingThemePalette) root.applyFallbackPalette() }
        function onOnPrimaryContainerColorChanged() { if (root.usingThemePalette) root.applyFallbackPalette() }
    }

    function rgbToHsl(r, g, b) {
        r /= 255; g /= 255; b /= 255
        let max = Math.max(r, g, b), min = Math.min(r, g, b)
        let l = (max + min) / 2
        if (max === min) return [0, 0, l]
        let d = max - min
        let s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
        let h
        if (max === r)      h = (g - b) / d + (g < b ? 6 : 0)
        else if (max === g) h = (b - r) / d + 2
        else                h = (r - g) / d + 4
        return [h / 6, s, l]
    }

    // Reads the cover through a tiny hidden canvas and picks a dominant + secondary hue
    Canvas {
        id: paletteSampler
        width: 32
        height: 32
        z: -1
        opacity: 0.01   // must stay > 0 or Qt skips painting the canvas

        property string src: MprisService.mprisData.artUrl || ""
        property string prevSrc: ""

        onSrcChanged: refresh()
        Component.onCompleted: refresh()

        function refresh() {
            if (prevSrc !== "" && prevSrc !== src && isImageLoaded(prevSrc))
                unloadImage(prevSrc)
            prevSrc = src

            if (src === "") { root.applyFallbackPalette(); return }
            if (isImageLoaded(src)) requestPaint()
            else loadImage(src)
        }

        onImageLoaded: requestPaint()

        onPaint: {
            if (src === "" || !isImageLoaded(src)) return
            let ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(src, 0, 0, width, height)
            let d = ctx.getImageData(0, 0, width, height).data

            // 12 hue buckets + 1 neutral bucket (greys / near-black / near-white)
            let buckets = []
            for (let i = 0; i < 13; i++) buckets.push({ w: 0, r: 0, g: 0, b: 0, n: 0 })

            for (let i = 0; i < d.length; i += 4) {
                if (d[i + 3] < 128) continue
                let hsl = root.rgbToHsl(d[i], d[i + 1], d[i + 2])
                let idx, wt
                if (hsl[1] < 0.18 || hsl[2] < 0.10 || hsl[2] > 0.93) {
                    idx = 12; wt = 0.02
                } else {
                    idx = Math.min(11, Math.floor(hsl[0] * 12))
                    wt = hsl[1] * (1 - Math.abs(2 * hsl[2] - 1)) + 0.02
                }
                let bk = buckets[idx]
                bk.w += wt; bk.r += d[i]; bk.g += d[i + 1]; bk.b += d[i + 2]; bk.n++
            }

            let order = []
            for (let i = 0; i < 12; i++) if (buckets[i].n > 0) order.push(buckets[i])
            order.sort((a, b) => b.w - a.w)

            // Greyscale / colourless cover → use the matugen palette
            if (order.length === 0 || order[0].w <= buckets[12].w) {
                root.applyFallbackPalette()
                return
            }

            function bucketHsl(bk) {
                return root.rgbToHsl(bk.r / bk.n, bk.g / bk.n, bk.b / bk.n)
            }

            let c1 = bucketHsl(order[0])
            let h = c1[0]
            let s = Math.max(0.45, Math.min(0.95, c1[1]))
            let h2 = (h + 0.06) % 1.0
            let s2 = s
            if (order.length > 1 && order[1].w >= order[0].w * 0.35) {
                let c2 = bucketHsl(order[1])
                h2 = c2[0]
                s2 = Math.max(0.40, Math.min(0.95, c2[1]))
            }
            root.usingThemePalette = false
            root.setPalette(h, s, h2, s2)
        }
    }

    DesktopWidgetBackground {
        transparentBg: root.transparentBg
    }

    Item {
        id: container
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Math.round(16 * root.scaleFactor)

        // Album Art: anchored to top, bottom, and left
        Rectangle {
            id: artContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Math.min(height, Math.round(parent.width * 0.42))
            radius: Theme.radiusSmall
            color: "transparent"
            clip: true

            function getFallbackSvg() {
                let c = Theme.background;
                let bg = Theme.primary;
                let raw = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                    <path fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="miter" stroke-linecap="butt" d="M 16.50 8.85 L 19.78 6.55 A 9.5 9.5 0 1 1 17.45 4.22" />
                    <circle cx="12" cy="12" r="4.5" fill="${c}" />
                    <circle cx="12" cy="12" r="1.5" fill="${bg}" />
                </svg>`;
                return "data:image/svg+xml," + encodeURIComponent(raw);
            }

            Rectangle {
                id: backgroundRect
                anchors.fill: parent
                color: MprisService.mprisData.artUrl ? "transparent" : Theme.primary
                radius: Math.max(4, Math.round(10 * root.scaleFactor))
                clip: true

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: MprisService.mprisData.artUrl || artContainer.getFallbackSvg()
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    layer.enabled: true
                    sourceSize.width: Math.max(32, parent.width)
                    sourceSize.height: Math.max(32, parent.height)
                    anchors.margins: MprisService.mprisData.artUrl ? 0 : Math.round(4 * root.scaleFactor)
                }

                Rectangle {
                    id: maskRect
                    anchors.fill: parent
                    radius: Math.max(4, Math.round(10 * root.scaleFactor))
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    source: artImage
                    anchors.fill: parent
                    maskEnabled: true
                    maskSource: maskRect
                }
            }
        }

        // Media Info & Controls: anchored to top, bottom, left (artContainer.right), and right
        Item {
            id: rightContent
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: artContainer.right
            anchors.right: parent.right
            anchors.leftMargin: Math.round(14 * root.scaleFactor)

            // Track Info
            ColumnLayout {
                id: trackInfo
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Math.round(3 * root.scaleFactor)

                Text {
                    Layout.fillWidth: true
                    text: MprisService.mprisData.title ? MprisService.mprisData.title : "No Media"
                    color: Theme.onPrimaryContainerColor
                    font.family: Theme.widgetFont(root.customFont)
                    font.bold: true
                    font.pixelSize: Math.max(11, Math.round(16 * root.scaleFactor))
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: MprisService.mprisData.artist ? MprisService.mprisData.artist : ""
                    color: Theme.onPrimaryContainerColor
                    font.family: Theme.widgetFont(root.customFont)
                    font.pixelSize: Math.max(9, Math.round(14 * root.scaleFactor))
                    elide: Text.ElideRight
                }
            }

            // Controls row
            RowLayout {
                id: controlsRow
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.max(28, Math.round(36 * root.scaleFactor))
                spacing: Math.round(18 * root.scaleFactor)

                Item { Layout.fillWidth: true }

                // Previous
                Text {
                    text: "󰒮"
                    font.family: "CaskaydiaCove Nerd Font Mono"
                    font.pixelSize: Math.max(16, Math.round(24 * root.scaleFactor))
                    color: Theme.onPrimaryContainerColor
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisService.runPlayerCtl("previous")
                    }
                }

                // Play/Pause
                Text {
                    text: MprisService.isPlaying ? "󰏤" : "󰐊"
                    font.family: "CaskaydiaCove Nerd Font Mono"
                    font.pixelSize: Math.max(20, Math.round(32 * root.scaleFactor))
                    color: Theme.onPrimaryContainerColor
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisService.runPlayerCtl("play-pause")
                    }
                }

                // Next
                Text {
                    text: "󰒭"
                    font.family: "CaskaydiaCove Nerd Font Mono"
                    font.pixelSize: Math.max(16, Math.round(24 * root.scaleFactor))
                    color: Theme.onPrimaryContainerColor
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisService.runPlayerCtl("next")
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // ── Seek bar with album-art coloured equalizer waves ──────────
            Canvas {
                id: progressCanvas
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: controlsRow.top
                anchors.bottomMargin: Math.max(2, Math.round(4 * root.scaleFactor))
                height: Math.max(34, Math.round(46 * root.scaleFactor))

                property real progress: MprisService.trackLength > 0 ? Math.min(MprisService.trackPosition / MprisService.trackLength, 1.0) : 0
                property real waveTime: 0        // seconds, ever-increasing
                property real waveSpeed: 1.0     // 1.0 = default; raise for faster waves
                property real waveHeight: 0.5    // tallest peak as a fraction of the space above the bar
                property real heightFraction: MprisService.isPlaying ? 1.0 : 0.0

                Behavior on heightFraction {
                    NumberAnimation { duration: MprisService.isPlaying ? 700 : 500; easing.type: Easing.OutCubic }
                }

                // Vsync-aligned clock (runs while playing, and while the waves settle after pausing)
                FrameAnimation {
                    running: MprisService.isPlaying || progressCanvas.heightFraction > 0.001
                    onTriggered: progressCanvas.waveTime += frameTime * progressCanvas.waveSpeed
                }

                onProgressChanged: requestPaint()
                onWaveTimeChanged: requestPaint()
                onHeightFractionChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    let ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    let sf = root.scaleFactor
                    let barThickness = Math.max(3, Math.round(4 * sf))
                    let thumbR = Math.max(5, Math.round(7 * sf))
                    let ringW = Math.max(1.5, 2 * sf)
                    let padX = thumbR
                    let barY = height - thumbR - 1

                    let trackW = Math.max(1, width - 2 * padX)
                    let progressX = padX + trackW * progress
                    let playedW = progressX - padX

                    let accent = root.accentColor
                    let onBg = Theme.onPrimaryContainerColor

                    function mix(c1, c2, t) {
                        return Qt.rgba(c1.r + (c2.r - c1.r) * t,
                                       c1.g + (c2.g - c1.g) * t,
                                       c1.b + (c2.b - c1.b) * t, 1)
                    }

                    // ── Equalizer waves (behind the bar, only over the played part) ──
                    // Carrier waves travel left → right; a hump envelope over the played region keeps
                    // the tallest peaks in the middle and tapers both ends (left edge → seeker).
                    if (heightFraction > 0.001 && playedW > 2) {
                        let t = waveTime
                        let maxAmp = (barY - 2) * waveHeight * heightFraction
                        let back = root.waveBackColor, mid = root.waveMidColor, front = root.waveFrontColor

                        // back (tall, dark) → front (short, light).
                        // l = wavelength (px @1x), v = speed (px/s @1x). Long wavelengths = rounded hills.
                        let layers = [
                            { color: back,                   alpha: 0.50, amp: 1.00, l1: 170, v1: 55, o1: 0.0, l2: 260, v2: 30, o2: 1.3 },
                            { color: mix(back, mid, 0.5),    alpha: 0.55, amp: 0.85, l1: 130, v1: 70, o1: 2.1, l2: 210, v2: 40, o2: 0.4 },
                            { color: mid,                    alpha: 0.62, amp: 0.72, l1: 105, v1: 85, o1: 4.0, l2: 180, v2: 25, o2: 2.6 },
                            { color: mix(mid, front, 0.5),   alpha: 0.72, amp: 0.58, l1: 145, v1: 65, o1: 5.2, l2: 230, v2: 45, o2: 0.9 },
                            { color: front,                  alpha: 0.88, amp: 0.45, l1: 120, v1: 95, o1: 3.3, l2: 200, v2: 35, o2: 4.4 }
                        ]

                        for (let li = 0; li < layers.length; li++) {
                            let L = layers[li]

                            let waveH = function(x) {
                                let px = (x - padX) / sf                 // position in 1x pixels
                                // Bounded sum of two rightward-travelling sines (no product → no sudden tall spikes)
                                let w1 = Math.sin(Math.PI * 2 * (px - L.v1 * t) / L.l1 + L.o1)
                                let w2 = Math.sin(Math.PI * 2 * (px - L.v2 * t) / L.l2 + L.o2)
                                let a = 0.5 + 0.5 * (0.7 * w1 + 0.3 * w2)      // always within 0..1
                                // Hump envelope: zero slope at both ends, tallest in the middle
                                let env = Math.pow(Math.max(0, Math.sin(Math.PI * (x - padX) / playedW)), 1.4)
                                return maxAmp * L.amp * a * env
                            }

                            ctx.beginPath()
                            ctx.moveTo(padX, barY)
                            for (let x = padX; x < progressX; x += 2)
                                ctx.lineTo(x, barY - waveH(x))
                            ctx.lineTo(progressX, barY)
                            ctx.closePath()

                            let g = ctx.createLinearGradient(0, barY - maxAmp, 0, barY)
                            g.addColorStop(0, Qt.rgba(L.color.r, L.color.g, L.color.b, L.alpha * 0.45))
                            g.addColorStop(1, Qt.rgba(L.color.r, L.color.g, L.color.b, L.alpha))
                            ctx.fillStyle = g
                            ctx.fill()
                        }
                    }

                    ctx.lineCap = "round"
                    ctx.lineWidth = barThickness

                    // ── Unplayed track ──
                    let unplayedStart = progressX + thumbR + Math.max(2, 3 * sf)
                    let unplayedEnd = width - padX
                    if (unplayedStart < unplayedEnd) {
                        ctx.beginPath()
                        ctx.moveTo(unplayedStart, barY)
                        ctx.lineTo(unplayedEnd, barY)
                        ctx.strokeStyle = Qt.rgba(onBg.r, onBg.g, onBg.b, 0.2)
                        ctx.stroke()
                    }

                    // ── Played track ──
                    ctx.beginPath()
                    ctx.moveTo(padX, barY)
                    ctx.lineTo(progressX, barY)
                    ctx.strokeStyle = accent
                    ctx.stroke()

                    // ── Thumb ──
                    ctx.beginPath()
                    ctx.arc(progressX, barY, thumbR - ringW / 2, 0, Math.PI * 2)
                    ctx.fillStyle = accent
                    ctx.fill()
                    ctx.lineWidth = ringW
                    ctx.strokeStyle = onBg
                    ctx.stroke()
                }
            }
        }
    }
}
