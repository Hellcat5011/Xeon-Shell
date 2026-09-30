import QtQuick
import QtQuick.Effects
import "../services"

Item {
    id: root

    property bool enabled: true
    property real screenX: 0
    property real screenY: 0
    property real screenWidth: 1920
    property real screenHeight: 1080

    // Only active when enabled, DepthService is enabled, mask URL is non-empty, and mask is marked visible
    readonly property bool isMaskActive: root.enabled && DepthService.enabled && DepthService.maskUrl !== "" && DepthService.maskVisible

    default property alias content: contentWrapper.data

    // 1. Content container
    Item {
        id: contentWrapper
        anchors.fill: parent
        visible: !root.isMaskActive
        layer.enabled: root.isMaskActive
    }

    // 2. Offscreen mask source item
    Item {
        id: maskSourceItem
        anchors.fill: parent
        visible: false
        layer.enabled: root.isMaskActive

        Image {
            x: -root.screenX
            y: -root.screenY
            width: root.screenWidth
            height: root.screenHeight
            fillMode: Image.PreserveAspectCrop
            source: DepthService.maskUrl
            sourceSize.width: root.screenWidth
            sourceSize.height: root.screenHeight
            asynchronous: true
            cache: true
        }
    }

    // 3. Standalone MultiEffect
    MultiEffect {
        id: effect
        anchors.fill: parent
        visible: root.isMaskActive
        source: contentWrapper
        maskEnabled: true
        maskSource: maskSourceItem
        maskInverted: true
        opacity: DepthService.maskFade
    }
}
