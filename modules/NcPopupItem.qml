// NcPopupItem.qml — ONE popup, fully self-contained lifecycle.
//
//   entering ──► shown ──► leaving ──► finished(uid)
//
// Why this removes the old race / jank:
//   • Every popup animates independently. There is no shared "isListAnimating"
//     lock and no "only index 0 may leave" rule, so any number of popups can
//     time out at the same moment without waiting on each other.
//   • The exit is slide-out + fade, then the item's own height collapses to 0.
//     Anything below slides up continuously because layout follows the height
//     animation; nothing is removed from the model until the collapse is done.
//   • Slide (XAnimator) and fade (OpacityAnimator) run on the render thread, so
//     they stay smooth even if the QML thread is busy. Only the height collapse
//     (layout geometry) is a regular NumberAnimation.
//   • Leaving is requested through the model (`leaving` role) and is idempotent,
//     so timeout / close button / external dismissal / overflow can't double-fire.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import "../services"

Item {
    id: root

    // ── Model roles ─────────────────────────────────────────────────────
    required property int    uid
    required property int    nid
    required property string appName
    required property string summary
    required property string body
    required property string iconName
    required property string iconFileUrl
    required property string previewUrl
    required property int    urgency
    required property string actionsJson
    required property int    timeoutMs
    required property int    rev
    required property bool   leaving

    signal leaveRequested(int uid)
    signal finished(int uid)

    // ── State ───────────────────────────────────────────────────────────
    property string phase: "entering"          // entering | shown | leaving
    property real   reveal: 0

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property bool  critical: urgency === NotificationUrgency.Critical
    readonly property var   actions: {
        try { return JSON.parse(root.actionsJson).slice(0, 3); } catch (e) { return []; }
    }
    readonly property real fullHeight: card.height + 12     // card + gap

    height: Math.round(fullHeight * reveal)
    clip: true

    // ── Animations ──────────────────────────────────────────────────────
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "reveal"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        XAnimator       { target: card; to: 10; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        OpacityAnimator { target: card; to: 1;  duration: 200 }
        onFinished: if (root.phase === "entering") root.phase = "shown"
    }

    SequentialAnimation {
        id: leaveAnim
        ParallelAnimation {
            XAnimator       { target: card; to: -460; duration: 300; easing.type: Easing.InCubic }
            OpacityAnimator { target: card; to: 0;    duration: 260 }
            SequentialAnimation {
                PauseAnimation { duration: 160 }
                NumberAnimation { target: root; property: "reveal"; to: 0; duration: 260; easing.type: Easing.InOutCubic }
            }
        }
        ScriptAction { script: root.finished(root.uid) }
    }

    function startLeave() {
        if (phase === "leaving") return;     // idempotent
        phase = "leaving";
        dismissTimer.stop();
        enterAnim.stop();                    // safe if dismissed mid-entry
        leaveAnim.start();
    }

    onLeavingChanged: if (leaving) startLeave()
    Component.onCompleted: { if (leaving) startLeave(); else enterAnim.start(); }

    // ── Auto-dismiss (paused while hovered, restarted on in-place update) ─
    Timer {
        id: dismissTimer
        interval: root.timeoutMs
        onTriggered: root.leaveRequested(root.uid)
    }
    function armTimer() {
        dismissTimer.stop();
        if (phase !== "shown" || critical || hover.hovered) return;
        dismissTimer.start();
    }
    onPhaseChanged: if (phase === "shown") armTimer()
    onRevChanged: armTimer()

    // ── Card ────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        x: -460                      // parked off-screen; XAnimator slides it to 10
        y: 0
        width: 360
        height: content.implicitHeight + 24
        opacity: 0
        radius: Config.windowRadius
        color: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, Config.backgroundOpacity)
        border.width: root.critical ? 2 : 1
        border.color: root.critical ? Theme.error : Theme.outlineVariant

        HoverHandler {
            id: hover
            onHoveredChanged: hovered ? dismissTimer.stop() : root.armTimer()
        }

        // Click anywhere on the body: hide the popup (stays in the centre).
        MouseArea {
            anchors.fill: parent
            onClicked: root.leaveRequested(root.uid)
        }

        ColumnLayout {
            id: content
            x: 12; y: 12
            width: card.width - 24
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                NcNotifIcon {
                    Layout.alignment: Qt.AlignTop
                    iconName: root.iconName
                    iconFileUrl: root.iconFileUrl
                    previewUrl: root.previewUrl
                    size: 44
                    previewSize: 68
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: root.appName
                            color: Qt.alpha(root.fg, 0.65)
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: closeMouse.containsMouse ? root.fg : "transparent"
                            NcIcon {
                                anchors.centerIn: parent
                                name: "close"
                                size: 12
                                color: closeMouse.containsMouse ? Theme.inversePrimary : root.fg
                            }
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.leaveRequested(root.uid)
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.summary
                        color: root.fg
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.body !== ""
                        text: root.body
                        textFormat: Text.StyledText
                        color: Qt.alpha(root.fg, 0.9)
                        linkColor: Theme.primary
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }

            // App-provided actions (+ default action as "Open")
            RowLayout {
                Layout.fillWidth: true
                visible: root.actions.length > 0
                spacing: 8

                Repeater {
                    model: root.actions
                    delegate: NcButton {
                        required property var modelData
                        Layout.fillWidth: true
                        compact: true
                        text: modelData.text
                        onClicked: {
                            NotificationManager.invoke(root.nid, modelData.identifier);
                            root.leaveRequested(root.uid);
                        }
                    }
                }
            }
        }
    }
}
