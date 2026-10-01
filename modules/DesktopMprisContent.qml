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

            // Equalizer overlay
            Row {
                anchors.centerIn: parent
                spacing: Math.max(2, Math.round(3 * root.scaleFactor))
                visible: MprisService.isPlaying
                opacity: 0.7

                Repeater {
                    model: 5
                    Item {
                        width: Math.max(4, Math.round(7 * root.scaleFactor))
                        height: Math.round(artContainer.height * 0.45)
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: Math.max(6, Math.round((10 + Math.random() * 30) * root.scaleFactor))
                            radius: 2
                            color: Theme.primary

                            SequentialAnimation on height {
                                loops: Animation.Infinite
                                running: MprisService.isPlaying
                                NumberAnimation {
                                    to: Math.round((10 + Math.random() * 40) * root.scaleFactor)
                                    duration: 200 + Math.random() * 200
                                    easing.type: Easing.InOutQuad
                                }
                                NumberAnimation {
                                    to: Math.round((10 + Math.random() * 20) * root.scaleFactor)
                                    duration: 200 + Math.random() * 200
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }
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

            // ── Squiggly progress bar ──────────────────
            Canvas {
                id: progressCanvas
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: controlsRow.top
                anchors.bottomMargin: Math.max(2, Math.round(4 * root.scaleFactor))
                height: Math.max(16, Math.round(22 * root.scaleFactor))

                property real progress: MprisService.trackLength > 0 ? Math.min(MprisService.trackPosition / MprisService.trackLength, 1.0) : 0
                property real wavePhase: 0
                property real heightFraction: MprisService.isPlaying ? 1.0 : 0.0

                Behavior on heightFraction {
                    NumberAnimation { duration: MprisService.isPlaying ? 800 : 550; easing.type: Easing.OutCubic }
                }

                NumberAnimation on wavePhase {
                    from: 0
                    to: 1.0
                    duration: 800
                    loops: Animation.Infinite
                    running: MprisService.isPlaying
                }

                onProgressChanged: requestPaint()
                onWavePhaseChanged: requestPaint()
                onHeightFractionChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    let ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    let centerY = height / 2
                    let totalWidth = width
                    let progressX = totalWidth * progress

                    // Scale wave parameters
                    let waveLength = Math.max(16, 28 * root.scaleFactor)
                    let amplitude = Math.max(2.5, 4.5 * root.scaleFactor)
                    let halfWave = waveLength / 2
                    let phaseOffsetPx = wavePhase * waveLength

                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"

                    function computeAmp(x, sign) {
                        if (x >= progressX) return 0
                        return sign * heightFraction * amplitude
                    }

                    let waveStart = -phaseOffsetPx - halfWave
                    let waveEnd = totalWidth + waveLength

                    let wavePath = []
                    let currentX = waveStart
                    let waveSign = 1
                    let currentAmp = computeAmp(currentX, waveSign)
                    wavePath.push({x: currentX, y: centerY + currentAmp})

                    while (currentX < waveEnd) {
                        waveSign = -waveSign
                        let nextX = currentX + halfWave
                        let midX = currentX + halfWave / 2
                        let nextAmp = computeAmp(nextX, waveSign)

                        wavePath.push({
                            type: "cubic",
                            cp1x: midX, cp1y: centerY + currentAmp,
                            cp2x: midX, cp2y: centerY + nextAmp,
                            x: nextX,   y: centerY + nextAmp
                        })
                        currentAmp = nextAmp
                        currentX = nextX
                    }

                    function drawWave(c) {
                        c.beginPath()
                        c.moveTo(wavePath[0].x, wavePath[0].y)
                        for (let i = 1; i < wavePath.length; i++) {
                            let p = wavePath[i]
                            c.bezierCurveTo(p.cp1x, p.cp1y, p.cp2x, p.cp2y, p.x, p.y)
                        }
                    }

                    // --- Played portion ---
                    ctx.save()
                    ctx.beginPath()
                    ctx.rect(0, 0, progressX, height)
                    ctx.clip()
                    drawWave(ctx)
                    ctx.strokeStyle = Theme.onPrimaryContainerColor
                    ctx.lineWidth = Math.max(1.5, Math.round(3 * root.scaleFactor))
                    ctx.stroke()
                    ctx.restore()

                    // --- Unplayed portion ---
                    if (progressX < totalWidth) {
                        ctx.beginPath()
                        ctx.moveTo(progressX, centerY)
                        ctx.lineTo(totalWidth, centerY)
                        ctx.strokeStyle = Qt.rgba(
                            Theme.onPrimaryContainerColor.r,
                            Theme.onPrimaryContainerColor.g,
                            Theme.onPrimaryContainerColor.b, 0.2)
                        ctx.lineWidth = Math.max(1.5, Math.round(3 * root.scaleFactor))
                        ctx.stroke()
                    }

                    // --- Playback head dot ---
                    if (progress > 0 && progress < 1) {
                        ctx.beginPath()
                        ctx.arc(progressX, centerY, Math.max(3, Math.round(5 * root.scaleFactor)), 0, Math.PI * 2)
                        ctx.fillStyle = Theme.onPrimaryContainerColor
                        ctx.fill()
                    }
                }
            }
        }
    }
}
