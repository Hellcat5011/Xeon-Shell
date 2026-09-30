import QtQuick
import QtQuick.Effects
import "../services"

Item {
    id: root

    property real screenX: 0
    property real screenY: 0
    property real screenWidth: 1920
    property real screenHeight: 1080

    // Only active when DepthService is enabled, mask URL is non-empty, and mask is marked visible
    readonly property bool isMaskActive: DepthService.enabled && DepthService.maskUrl !== "" && DepthService.maskVisible

    default property alias content: contentWrapper.data

    // 1. Content container
    Item {
        id: contentWrapper
        anchors.fill: parent
        layer.enabled: root.isMaskActive
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskThresholdMin: 0.0
            maskSpreadAtMin: 1.0
            opacity: DepthService.maskFade
            maskSource: maskSourceItem
        }
    }

    // 2. Offscreen mask source item
    Item {
        id: maskSourceItem
        anchors.fill: parent
        visible: false
        layer.enabled: root.isMaskActive

        Loader {
            anchors.fill: parent
            active: root.isMaskActive
            sourceComponent: Image {
                fillMode: Image.PreserveAspectCrop
                width: root.screenWidth
                height: root.screenHeight
                x: -root.screenX
                y: -root.screenY
                source: DepthService.maskUrl
                sourceSize.width: root.screenWidth
                sourceSize.height: root.screenHeight
                asynchronous: true
                cache: true
            }
        }
    }
}
