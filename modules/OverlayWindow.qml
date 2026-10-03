// ─────────────────────────────────────────────────────────────────────────
// OverlayWindow.qml — shared base for any "popup card" window
//
// New in this version:
//   • cardTransparent: bool — when true the card has no background so
//     content (e.g. WallpaperSelector's floating images) appears directly
//     against the wallpaper with no card box behind it.
//   • The gradient now goes diagonally (top-left primaryContainer →
//     bottom-right secondary) at true 45° using a Canvas, since QML's
//     built-in Gradient only supports vertical/horizontal directions.
//   • Both gradient colours carry 80 % alpha so the launcher
//     reads as translucent on top of the wallpaper without relying on
//     Hyprland's layer-rule opacity (which only works for windows).
// ─────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../services"

PanelWindow {
    id: root

    // ---- Public API ------------------------------------------------------
    property bool shown:       false
    property int  panelWidth:  640
    property int  panelHeight: 420
    property int  cardRadius:  Config.windowRadius
    property string anchorPos: "center"
    property color cardColor: Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, Config.backgroundOpacity)
    property bool hasBorder: false
    property string enterAnimation: "scale"

    // Set true in WallpaperSelector: hides the card background entirely so
    // only the delegate images are visible (floating-card look).
    property bool cardTransparent: false

    // Any child items written inside `OverlayWindow { … }` land here.
    default property alias content: card.data

    function show()    { root.shown = true  }
    function hide()    { root.shown = false }
    function hideNow() {
        root.shown = false;
        closingTimer.stop();
    }
    function toggle()  { root.shown = !root.shown }

    // ---- Wayland layer-shell plumbing ------------------------------------
    WlrLayershell.layer: WlrLayer.Overlay
    color:     "transparent"
    focusable: root.shown
    anchors { top: true; bottom: true; left: true; right: true }

    // Keep the surface alive long enough for the closing animation to play.
    visible: shown || closingTimer.running
    Timer {
        id: closingTimer
        interval: Theme.animMed + 100
    }
    onShownChanged: if (!shown) closingTimer.start()

    // Click anywhere on the full-screen backdrop to dismiss.
    MouseArea {
        anchors.fill: parent
        onClicked: root.hide()
    }

    // ---- Card -----------------------------------------------------------
    Rectangle {
        id: card
        anchors.centerIn: root.anchorPos === "center" ? parent : undefined
        anchors.left: root.anchorPos === "left" || root.anchorPos === "topleft" ? parent.left : undefined
        anchors.right: root.anchorPos === "right" ? parent.right : undefined
        anchors.top: root.anchorPos === "topleft" || root.anchorPos === "top" ? parent.top : undefined
        anchors.bottom: root.anchorPos === "bottom" ? parent.bottom : undefined
        anchors.verticalCenter: (root.anchorPos === "left" || root.anchorPos === "right") ? parent.verticalCenter : undefined
        anchors.margins: 20
        width:  root.panelWidth
        height: root.panelHeight
        radius: root.cardRadius
        // The actual card color
        color: root.cardTransparent ? "transparent" : root.cardColor
        border.width: root.hasBorder && !root.cardTransparent ? 1 : 0
        border.color: Theme.outlineVariant
        clip: true
        layer.enabled: true

        // Fade + gentle scale animation on open/close.
        opacity: (root.enterAnimation === "scale") ? (root.shown ? 1 : 0) : 1
        scale:   root.enterAnimation === "scale" ? (root.shown ? 1 : 0.92) : 1
        
        transform: Translate {
            x: {
                if (!root.shown) {
                    if (root.enterAnimation === "slideLeft") return -card.width - 100;
                    if (root.enterAnimation === "slideRight") return card.width + 100;
                }
                return 0;
            }
            y: {
                if (!root.shown) {
                    if (root.enterAnimation === "slideTop") return -card.height - 100;
                    if (root.enterAnimation === "slideBottom") return card.height + 100;
                }
                return 0;
            }
            Behavior on x { 
                NumberAnimation { 
                    duration: Theme.animMed + 50
                    easing.type: Easing.OutBack
                    easing.overshoot: 2.0
                } 
            }
            Behavior on y { 
                NumberAnimation { 
                    duration: Theme.animMed + 50
                    easing.type: Easing.OutBack
                    easing.overshoot: 2.0
                } 
            }
        }

        Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }
        Behavior on scale   { NumberAnimation { duration: Theme.animMed; easing.type: Theme.easeOut } }

        // Swallow clicks within the card bounds so they don't propagate
        // to the full-screen backdrop MouseArea (which would close us).
        MouseArea { anchors.fill: parent; onClicked: (mouse) => mouse.accepted = true }
    }
}
