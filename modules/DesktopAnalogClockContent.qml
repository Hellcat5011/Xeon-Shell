import QtQuick
import QtQuick.Shapes
import "../services"

// Analog clock: scalloped "cookie" face, two chunky rounded hands, and a small
// dot that orbits the face as the seconds ticker.
Item {
    id: root

    property bool interactive: true
    property bool editMode: false
    property bool transparentBg: false
    // Kept for parity with the other widget contents (the clock draws no text)
    property string customFont: ""
    // The container turns this off while the widget is hidden so the timer sleeps
    property bool running: true

    // ── Geometry ────────────────────────────────────────────────
    // The face is always a circle fitted into the widget box and centred in it
    readonly property real size: Math.max(1, Math.min(width, height))
    readonly property real faceRadius: size / 2
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    readonly property int scallops: 12
    readonly property real scallopDepth: 0.045   // fraction of the radius

    readonly property real handWidth: faceRadius * 0.135
    readonly property real minuteLength: faceRadius * 0.70
    readonly property real hourLength: faceRadius * 0.46
    readonly property real dotDiameter: size * 0.12
    readonly property real dotOrbit: faceRadius * 0.78

    // ── Colours ─────────────────────────────────────────────────
    readonly property color faceColor: root.transparentBg
        ? "transparent"
        : Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, Config.backgroundOpacity)
    readonly property color handColor: Theme.primary
    // Seconds dot: tertiary when the theme provides it, otherwise falls back to primary
    readonly property color dotColor: (Theme.tertiary !== undefined) ? Theme.tertiary : Theme.primary

    // ── Time state (degrees, clockwise from 12 o'clock) ─────────
    property real hourAngle: 0
    property real minuteAngle: 0
    // Accumulates (never wraps back to 0) so the dot always travels forward,
    // including across the 59 -> 0 boundary.
    property real secondAngle: 0
    property int lastSecond: -1
    // Behaviour is off for the very first paint and for large catch-up jumps
    property bool animateTick: false

    function syncTime() {
        let d = new Date();
        let s = d.getSeconds();
        let m = d.getMinutes();
        let h = d.getHours() % 12;

        root.minuteAngle = (m + s / 60) * 6;
        root.hourAngle = (h + m / 60) * 30;

        if (root.lastSecond < 0) {
            root.animateTick = false;
            root.secondAngle = s * 6;
        } else {
            let diff = (s - root.lastSecond + 60) % 60;
            if (diff > 2) {
                // Woke up after a long pause: snap instead of spinning through the gap
                root.animateTick = false;
                root.secondAngle += diff * 6;
            } else if (diff > 0) {
                root.animateTick = true;
                root.secondAngle += diff * 6;
            }
        }
        root.lastSecond = s;

        // Re-aim the next tick just after the second rolls over, so the dot
        // stays in step with the real clock without polling.
        tickTimer.interval = Math.max(50, 1000 - d.getMilliseconds() + 15);
    }

    Timer {
        id: tickTimer
        repeat: true
        running: root.running
        interval: 1000
        onTriggered: root.syncTime()
    }

    // Catch up immediately when the widget becomes visible again
    onRunningChanged: if (running) root.syncTime()
    Component.onCompleted: root.syncTime()

    // ── Scalloped face ──────────────────────────────────────────
    function facePoints(sz, n, depth) {
        let pts = [];
        let steps = 288;
        let R = sz / 2;
        for (let i = 0; i <= steps; i++) {
            let a = (i / steps) * Math.PI * 2;
            // r swings between R (lobe tips) and R * (1 - 2*depth) (valleys)
            let r = R * (1 - depth + depth * Math.cos(n * a));
            pts.push(Qt.point(R + r * Math.sin(a), R - r * Math.cos(a)));
        }
        return pts;
    }

    Shape {
        id: face
        anchors.centerIn: parent
        width: root.size
        height: root.size
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: -1
            fillColor: root.faceColor
            PathPolyline {
                path: root.facePoints(root.size, root.scallops, root.scallopDepth)
            }
        }
    }

    // ── Hour hand ───────────────────────────────────────────────
    Rectangle {
        width: root.handWidth
        height: root.hourLength
        radius: width / 2
        color: root.handColor
        x: root.cx - width / 2
        y: root.cy - height
        transformOrigin: Item.Bottom
        rotation: root.hourAngle
        antialiasing: true
    }

    // ── Minute hand ─────────────────────────────────────────────
    Rectangle {
        width: root.handWidth
        height: root.minuteLength
        radius: width / 2
        color: root.handColor
        x: root.cx - width / 2
        y: root.cy - height
        transformOrigin: Item.Bottom
        rotation: root.minuteAngle
        antialiasing: true
    }

    // ── Seconds dot ─────────────────────────────────────────────
    // A zero-size pivot at the centre rotates; the dot is offset up from it,
    // so it travels along a circle.
    Item {
        x: root.cx
        y: root.cy
        width: 0
        height: 0
        rotation: root.secondAngle

        Behavior on rotation {
            enabled: root.animateTick
            NumberAnimation {
                duration: Theme.animSlow
                easing.type: Theme.easeOut
            }
        }

        Rectangle {
            width: root.dotDiameter
            height: root.dotDiameter
            radius: width / 2
            color: root.dotColor
            x: -width / 2
            y: -root.dotOrbit - height / 2
            antialiasing: true
        }
    }
}
