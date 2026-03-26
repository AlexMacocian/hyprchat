import QtQuick
import QtQuick.Layouts

// Preferences panel — configure HyprChat settings.
Item {
    id: root

    property bool shown: false
    property var preferences: null

    // Local copies for editing (not applied until Save)
    property real editThreshold: 0.7
    property int editKeepRecent: 4
    property string editSystemPrompt: ""
    property bool editMemoryEnabled: true

    visible: shown

    onShownChanged: {
        if (shown && preferences) {
            // Load current values into edit fields
            editThreshold = preferences.summarizeThreshold;
            editKeepRecent = preferences.keepRecentMessages;
            editSystemPrompt = preferences.systemPrompt;
            editMemoryEnabled = preferences.memoryEnabled;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg0

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: Theme.bg1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: "Preferences"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    // Save button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: saveLabel.implicitWidth + 16
                        radius: 4
                        color: saveMouse.containsMouse ? Theme.accent2 : Theme.accent1

                        Text {
                            id: saveLabel
                            anchors.centerIn: parent
                            text: "Save"
                            color: Theme.bg0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }

                        MouseArea {
                            id: saveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.preferences.summarizeThreshold = root.editThreshold;
                                root.preferences.keepRecentMessages = root.editKeepRecent;
                                root.preferences.systemPrompt = root.editSystemPrompt;
                                root.preferences.memoryEnabled = root.editMemoryEnabled;
                                root.preferences.save();
                                root.shown = false;
                            }
                        }
                    }

                    // Close button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: closeLabel.implicitWidth + 12
                        radius: 4
                        color: closeMouse.containsMouse ? Theme.bg3 : "transparent"

                        Text {
                            id: closeLabel
                            anchors.centerIn: parent
                            text: "Close"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.shown = false
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // Settings
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    id: settingsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 16

                    Item { Layout.preferredHeight: 8 }

                    // --- System Prompt ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 4

                        Text {
                            text: "System Prompt"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }

                        Text {
                            text: "Instructions sent to the model at the start of every conversation."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(promptEdit.implicitHeight + 16, 80)
                            radius: 6
                            color: Theme.bg2
                            border.color: promptEdit.activeFocus ? Theme.accent1 : Theme.border
                            border.width: 1

                            TextEdit {
                                id: promptEdit
                                anchors.fill: parent
                                anchors.margins: 8
                                text: root.editSystemPrompt
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                onTextChanged: root.editSystemPrompt = text
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Memory Toggle ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Memory"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: "Enable persistent memory. The model will save and recall information across conversations."
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                        }

                        // Toggle
                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 24
                            radius: 12
                            color: root.editMemoryEnabled ? Theme.accent1 : Theme.bg3

                            Rectangle {
                                x: root.editMemoryEnabled ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                radius: 9
                                color: Theme.text

                                Behavior on x {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editMemoryEnabled = !root.editMemoryEnabled
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Summarize Threshold ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 4

                        Text {
                            text: "Summarize Threshold"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }

                        Text {
                            text: "Trigger conversation summarization when context usage exceeds this percentage."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            // Custom slider — Slider widget doesn't work in QuickShell
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24

                                Rectangle {
                                    id: thresholdTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 4
                                    radius: 2
                                    color: Theme.bg2

                                    Rectangle {
                                        width: parent.width * ((root.editThreshold - 0.1) / 0.9)
                                        height: parent.height
                                        radius: 2
                                        color: Theme.accent1
                                    }
                                }

                                Rectangle {
                                    id: thresholdHandle
                                    x: thresholdTrack.width * ((root.editThreshold - 0.1) / 0.9) - width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: thresholdDrag.pressed ? Theme.accent2 : Theme.accent1
                                }

                                MouseArea {
                                    id: thresholdDrag
                                    anchors.fill: parent
                                    onPressed: updateThreshold(mouse)
                                    onPositionChanged: updateThreshold(mouse)

                                    function updateThreshold(mouse) {
                                        let ratio = Math.max(0, Math.min(1, mouse.x / width));
                                        root.editThreshold = Math.round((0.1 + ratio * 0.9) * 20) / 20; // snap to 0.05
                                    }
                                }
                            }

                            Text {
                                text: Math.round(root.editThreshold * 100) + "%"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.preferredWidth: 40
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Keep Recent Messages ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 4

                        Text {
                            text: "Keep Recent Messages"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }

                        Text {
                            text: "Number of recent messages to preserve after summarization."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24

                                Rectangle {
                                    id: keepTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 4
                                    radius: 2
                                    color: Theme.bg2

                                    Rectangle {
                                        width: parent.width * (root.editKeepRecent / 20)
                                        height: parent.height
                                        radius: 2
                                        color: Theme.accent1
                                    }
                                }

                                Rectangle {
                                    x: keepTrack.width * (root.editKeepRecent / 20) - width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: keepDrag.pressed ? Theme.accent2 : Theme.accent1
                                }

                                MouseArea {
                                    id: keepDrag
                                    anchors.fill: parent
                                    onPressed: updateKeep(mouse)
                                    onPositionChanged: updateKeep(mouse)

                                    function updateKeep(mouse) {
                                        let ratio = Math.max(0, Math.min(1, mouse.x / width));
                                        root.editKeepRecent = Math.round(ratio * 20);
                                    }
                                }
                            }

                            Text {
                                text: root.editKeepRecent
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.preferredWidth: 30
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 16 }
                }
            }
        }
    }
}
