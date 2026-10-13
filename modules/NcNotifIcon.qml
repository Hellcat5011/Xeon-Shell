// NcNotifIcon.qml — avatar slot for a notification.
//
//  • image hint / screenshot  → rounded, cropped PREVIEW shown in place of the icon
//  • app_icon given as a path → shown from file (treated as a preview when it is
//                               clearly a photo/screenshot rather than a small icon)
//  • otherwise                → themed icon on a soft disc
//
// File images are loaded with cache:false (screenshot tools often overwrite the
// same filename) and retried a few times, because some tools fire the
// notification a moment before the file has finished writing.
import QtQuick
import Quickshell
import Quickshell.Widgets
import "../services"

Item {
    id: root

    property string iconName: ""
    property string iconFileUrl: ""
    property string previewUrl: ""
    property int size: 44
    property int previewSize: 64

    readonly property color fg: Theme.onPrimaryContainerColor
    readonly property string fileUrl: previewUrl !== "" ? previewUrl : iconFileUrl

    property int  retries: 0
    property bool fileIsPreviewish: false
    readonly property bool fileFailed: img.status === Image.Error && retries >= 3
    readonly property bool useFile: fileUrl !== "" && !fileFailed
    readonly property bool asPreview: useFile && (previewUrl !== "" || fileIsPreviewish)

    implicitWidth: asPreview ? previewSize : size
    implicitHeight: implicitWidth
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.alpha(root.fg, 0.14)
        visible: !root.asPreview
    }

    IconImage {
        anchors.centerIn: parent
        width: root.size * 0.58
        height: width
        visible: !root.useFile
        source: Quickshell.iconPath(root.iconName !== "" ? root.iconName : "dialog-information")
    }

    ClippingRectangle {
        anchors.fill: parent
        visible: root.useFile
        color: "transparent"
        radius: root.asPreview ? 14 : width / 2

        Image {
            id: img
            anchors.fill: parent
            anchors.margins: root.asPreview ? 0 : root.size * 0.2
            source: root.fileUrl
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            fillMode: root.asPreview ? Image.PreserveAspectCrop : Image.PreserveAspectFit
            // Down-scales big screenshots (aspect preserved), never up-scales icons.
            sourceSize: Qt.size(384, 384)

            onStatusChanged: {
                if (status === Image.Ready) {
                    const r = implicitWidth / Math.max(1, implicitHeight);
                    root.fileIsPreviewish = Math.abs(r - 1) > 0.12
                        || /screenshot|screen[-_ ]?shot|capture|pictures/i.test(root.fileUrl);
                } else if (status === Image.Error && root.retries < 3) {
                    retryTimer.restart();
                }
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 400
        onTriggered: {
            root.retries++;
            img.source = "";
            img.source = Qt.binding(() => root.fileUrl);
        }
    }
}
