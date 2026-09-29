pragma Singleton
import QtQuick

QtObject {
    id: root

    // Hardcoded colors from colors.json to prevent the greeter from breaking
    // if the user's files are unreadable.
    property color onPrimaryContainerColor: "#d4e6e7"
    property color primary: "#85d2e8"
    property color error: "#ffb4ab"
    property color outlineVariant: "#464747"

    // Hardcoded layout values from Config.qml
    property bool showLockscreenSessionControls: true
}
