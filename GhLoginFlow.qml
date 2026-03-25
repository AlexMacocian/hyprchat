import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// GitHub Copilot OAuth device flow.
// 1. POST /login/device/code with Copilot client_id → get user_code + device_code
// 2. User enters code in browser
// 3. Poll /login/oauth/access_token until we get an access_token (ghu_...)
// 4. Emit the OAuth token — caller exchanges it for a Copilot session token
Item {
    id: root

    readonly property string copilotClientId: "Iv1.b507a08c87ecfe98"

    property bool shown: false
    property string deviceCode: ""
    property string userCode: ""
    property string statusText: "Starting GitHub Copilot login..."
    property bool inProgress: false
    property int pollInterval: 5000

    // The OAuth token (ghu_...) — NOT the session token
    signal authCompleted(string oauthToken)
    signal authFailed(string error)
    signal authCancelled()

    visible: shown
    implicitHeight: shown ? content.implicitHeight + 24 : 0
    clip: true

    function start() {
        userCode = "";
        deviceCode = "";
        statusText = "Starting GitHub Copilot login...";
        inProgress = true;
        shown = true;
        // Step 1: Request device code
        initiateProcess.command = [
            "curl", "-s", "-X", "POST",
            "https://github.com/login/device/code",
            "-H", "Accept: application/json",
            "-d", "client_id=" + copilotClientId + "&scope=read:user"
        ];
        initiateProcess.running = true;
    }

    function cancel() {
        pollTimer.running = false;
        initiateProcess.running = false;
        pollProcess.running = false;
        inProgress = false;
        shown = false;
        root.authCancelled();
    }

    // Step 1: Get device code
    Process {
        id: initiateProcess
        running: false

        stdout: StdioCollector {
            id: initiateStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.statusText = "Failed to start login.";
                root.inProgress = false;
                root.authFailed("Device code request failed");
                return;
            }

            try {
                let json = JSON.parse(initiateStdout.text);
                root.deviceCode = json.device_code || "";
                root.userCode = json.user_code || "";
                root.pollInterval = (json.interval || 5) * 1000;

                if (root.userCode && root.deviceCode) {
                    root.statusText = "Enter this code on GitHub:";
                    // Open browser
                    browserProcess.command = ["xdg-open", json.verification_uri || "https://github.com/login/device"];
                    browserProcess.running = true;
                    // Start polling for token
                    pollTimer.interval = root.pollInterval;
                    pollTimer.running = true;
                } else {
                    root.statusText = "Failed to get device code.";
                    root.authFailed("No device code in response");
                }
            } catch (e) {
                root.statusText = "Failed to parse response.";
                root.authFailed("Parse error: " + e);
            }
        }
    }

    // Open browser
    Process {
        id: browserProcess
        running: false
    }

    // Step 2: Poll for access token
    Timer {
        id: pollTimer
        interval: 5000
        repeat: true
        running: false

        onTriggered: {
            if (pollProcess.running) return;
            pollProcess.command = [
                "curl", "-s", "-X", "POST",
                "https://github.com/login/oauth/access_token",
                "-H", "Accept: application/json",
                "-d", "client_id=" + root.copilotClientId
                    + "&device_code=" + root.deviceCode
                    + "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            ];
            pollProcess.running = true;
        }
    }

    Process {
        id: pollProcess
        running: false

        stdout: StdioCollector {
            id: pollStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return;

            try {
                let json = JSON.parse(pollStdout.text);

                if (json.access_token) {
                    // Success — got the OAuth token
                    pollTimer.running = false;
                    root.inProgress = false;
                    root.statusText = "Authenticated!";
                    root.shown = false;
                    root.authCompleted(json.access_token);
                } else if (json.error === "authorization_pending") {
                    // User hasn't entered code yet — keep polling
                    root.statusText = "Waiting for authorization...";
                } else if (json.error === "slow_down") {
                    // Slow down polling
                    pollTimer.interval = pollTimer.interval + 5000;
                } else if (json.error === "expired_token") {
                    pollTimer.running = false;
                    root.inProgress = false;
                    root.statusText = "Code expired. Try again.";
                    root.authFailed("Device code expired");
                } else if (json.error) {
                    pollTimer.running = false;
                    root.inProgress = false;
                    root.statusText = "Error: " + (json.error_description || json.error);
                    root.authFailed(json.error_description || json.error);
                }
            } catch (e) {
                // Parse error — ignore, keep polling
            }
        }
    }

    Rectangle {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        color: Theme.bg1
        radius: 8
        border.color: Theme.accent2
        border.width: 1
        implicitHeight: col.implicitHeight + 24

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "GitHub Copilot Login"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                Layout.fillWidth: true
            }

            Text {
                text: root.statusText
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                Layout.fillWidth: true
            }

            // Device code display
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 8
                color: Theme.bg2
                border.color: Theme.accent1
                border.width: root.userCode.length > 0 ? 2 : 0
                visible: root.userCode.length > 0

                Text {
                    anchors.centerIn: parent
                    text: root.userCode
                    color: Theme.accent2
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                    font.letterSpacing: 4
                }
            }

            Text {
                text: "A browser window should open automatically.\nPaste the code above and authorize."
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                visible: root.userCode.length > 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 28
                    radius: 4
                    color: cancelMouse.containsMouse ? Theme.bg3 : Theme.bg2

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.cancel()
                    }
                }
            }
        }
    }
}
