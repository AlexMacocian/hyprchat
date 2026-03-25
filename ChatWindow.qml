import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

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

    // Active backend
    property string activeBackendName: "openai"
    property string activeModel: "gpt-4o"

    // Keyring for API key retrieval
    KeyringService {
        id: keyring
        onKeyRetrieved: (account, key) => {
            backend.apiKey = key;
            apiKeyPrompt.shown = false;
        }
        onKeyMissing: (account) => {
            apiKeyPrompt.backendName = account;
            apiKeyPrompt.shown = true;
            apiKeyPrompt.focusInput();
        }
        onKeyError: (account, error) => {
            console.warn("Keyring error:", error);
            apiKeyPrompt.backendName = account;
            apiKeyPrompt.shown = true;
            apiKeyPrompt.focusInput();
        }
        onKeyStored: (account) => {
            // Key saved — now look it up to set it on the backend
            keyring.lookup(account);
        }
        onKeyDeleted: (account) => {
            backend.apiKey = "";
            apiKeyPrompt.backendName = account;
            apiKeyPrompt.shown = true;
            apiKeyPrompt.focusInput();
        }
    }

    // LLM backend
    OpenAIBackend {
        id: backend
        model: window.activeModel

        onTokenReceived: (token) => {
            // Update the last assistant message in-place
            let idx = messageModel.count - 1;
            if (idx >= 0 && messageModel.get(idx).role === "assistant") {
                let current = messageModel.get(idx).text;
                if (current === "...") {
                    messageModel.set(idx, { role: "assistant", text: token });
                } else {
                    messageModel.set(idx, { role: "assistant", text: current + token });
                }
            }
        }

        onResponseFinished: {
            // Done streaming
        }

        onResponseError: (error) => {
            let idx = messageModel.count - 1;
            if (idx >= 0 && messageModel.get(idx).role === "assistant") {
                messageModel.set(idx, { role: "assistant", text: "**Error:** " + error });
            }
        }
    }

    // Fetch API key on startup
    Component.onCompleted: {
        keyring.lookup(activeBackendName);
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
                        text: window.activeBackendName + " · " + window.activeModel
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

            // API key prompt (shown when key is missing)
            ApiKeyPrompt {
                id: apiKeyPrompt
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight

                onKeySubmitted: (key) => {
                    keyring.store(apiKeyPrompt.backendName, key);
                }
                onCancelled: {
                    apiKeyPrompt.shown = false;
                }
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
                    if (backend.apiKey.length === 0) {
                        apiKeyPrompt.backendName = window.activeBackendName;
                        apiKeyPrompt.shown = true;
                        apiKeyPrompt.focusInput();
                        return;
                    }
                    messageModel.append({ role: "user", text: text });
                    messageModel.append({ role: "assistant", text: "..." });
                    backend.send(messageModel);
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
