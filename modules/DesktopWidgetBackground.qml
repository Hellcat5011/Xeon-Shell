import QtQuick
import "../services"

Rectangle {
    id: root
    anchors.fill: parent
    
    property bool transparentBg: false

    // Eww config: border-radius: 10px
    radius: 10
    
    // Solid background using 60% opacity inverse primary (transparent if transparentBg is true)
    color: transparentBg ? "transparent" : Qt.rgba(Theme.inversePrimary.r, Theme.inversePrimary.g, Theme.inversePrimary.b, 0.60)
    layer.enabled: !transparentBg
}
