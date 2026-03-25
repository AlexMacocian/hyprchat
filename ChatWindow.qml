import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

FloatingWindow {
    id: window

    visible: false
    implicitWidth: 700
    implicitHeight: 500
    title: "HyprChat"

    // Toggle visibility via Hyprland global shortcut
    GlobalShortcut {
        appid: "hyprchat"
        name: "toggle"
        description: "Toggle HyprChat window"

        onPressed: {
            window.visible = !window.visible;
            if (window.visible) {
                inputBar.focusInput();
            }
        }
    }

    // Grab focus when the window is shown so clicks outside dismiss it
    // TODO: re-enable once toggle keybind is set up
    // HyprlandFocusGrab {
    //     id: focusGrab
    //     active: window.visible
    //     windows: [window]
    //     onCleared: window.visible = false
    // }

    // Message model
    ListModel {
        id: messageModel
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg0

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Top bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: Theme.bg1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: "HyprChat"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "copilot · gpt-4o"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // Chat messages
            ChatView {
                id: chatView
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: messageModel
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // Input bar
            InputBar {
                id: inputBar
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight

                onMessageSent: (text) => {
                    messageModel.append({ role: "user", text: text });
                    // TODO: send to backend, receive streaming response
                    messageModel.append({ role: "assistant", text: "_Thinking..._" });
                }
            }
        }
    }

    // Escape to hide
    Shortcut {
        sequence: "Escape"
        onActivated: window.visible = false
    }

    // Ctrl+N for new chat
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: messageModel.clear()
    }
}
