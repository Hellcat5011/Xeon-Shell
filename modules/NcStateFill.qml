// NcStateFill.qml — GPU-friendly state colour.
//
// ColorAnimation runs on the GUI thread and re-rasterises its item every frame.
// Instead we keep a solid rectangle and animate only its OPACITY with an
// OpacityAnimator, which runs on the render thread (a pure GPU blend).
// Stack one of these per state (hover, active, expanded …) on top of a static base.
import QtQuick
import "../services"

Rectangle {
    id: root

    property bool shown: false
    property real level: 1.0          // opacity when shown (acts as the colour's alpha)

    opacity: shown ? level : 0
    Behavior on opacity { OpacityAnimator { duration: Theme.animFast; easing.type: Easing.OutCubic } }
}
