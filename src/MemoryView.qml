import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Memory viewer panel — browse, read, edit, delete memory topics.
Item {
    id: root

    property bool shown: false
    property var memoryService: null
    property string selectedTopic: ""
    property bool editing: false

    visible: shown

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
                        text: root.selectedTopic.length > 0 ? ("Memory: " + root.selectedTopic) : "Memory"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    // Back button (when viewing a topic)
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: backLabel.implicitWidth + 12
                        radius: 4
                        color: backMouse.containsMouse ? Theme.bg3 : "transparent"
                        visible: root.selectedTopic.length > 0

                        Text {
                            id: backLabel
                            anchors.centerIn: parent
                            text: "Back"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: backMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.selectedTopic = "";
                                root.editing = false;
                            }
                        }
                    }

                    // Edit/Save button (when viewing a topic)
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: editLabel.implicitWidth + 12
                        radius: 4
                        color: editMouse.containsMouse ? Theme.bg3 : "transparent"
                        visible: root.selectedTopic.length > 0

                        Text {
                            id: editLabel
                            anchors.centerIn: parent
                            text: root.editing ? "Save" : "Edit"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: editMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (root.editing) {
                                    // Save
                                    root.memoryService.editTopic(root.selectedTopic, contentEditor.text);
                                    root.editing = false;
                                } else {
                                    root.editing = true;
                                }
                            }
                        }
                    }

                    // Delete button (when viewing a topic)
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: deleteLabel.implicitWidth + 12
                        radius: 4
                        color: deleteMouse.containsMouse ? "#802020" : "transparent"
                        visible: root.selectedTopic.length > 0

                        Text {
                            id: deleteLabel
                            anchors.centerIn: parent
                            text: "Delete"
                            color: deleteMouse.containsMouse ? "#FF6060" : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.memoryService.deleteTopic(root.selectedTopic);
                                root.selectedTopic = "";
                                root.editing = false;
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
                            onClicked: {
                                root.shown = false;
                                root.selectedTopic = "";
                                root.editing = false;
                            }
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

            // Content area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Topic list (shown when no topic selected)
                ListView {
                    id: topicList
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: root.selectedTopic.length === 0 && root.memoryService !== null
                    clip: true
                    spacing: 2

                    model: {
                        if (!root.memoryService) return [];
                        let v = root.memoryService._cacheVersion;
                        return root.memoryService.topicNames;
                    }

                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: topicList.width
                        height: 40
                        radius: 6
                        color: topicMouse.containsMouse ? Theme.bg2 : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            Text {
                                text: modelData
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.fillWidth: true
                            }

                            Text {
                                text: {
                                    let content = root.memoryService.readTopic(modelData);
                                    let lines = content.split("\n").length;
                                    return lines + " lines";
                                }
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }

                            Text {
                                text: "›"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 2
                            }
                        }

                        MouseArea {
                            id: topicMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.selectedTopic = modelData;
                                root.editing = false;
                            }
                        }
                    }

                    // Empty state
                    Text {
                        anchors.centerIn: parent
                        visible: topicList.count === 0
                        text: "No memories yet.\nMemories will appear here as the model saves them."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Theme.bg3
                        }
                    }
                }

                // Topic content view (shown when a topic is selected)
                Flickable {
                    id: contentFlickable
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: root.selectedTopic.length > 0
                    contentHeight: root.editing ? contentEditor.implicitHeight : contentView.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // Read-only view
                    TextEdit {
                        id: contentView
                        visible: !root.editing
                        width: contentFlickable.width
                        text: {
                            if (!root.memoryService || root.selectedTopic.length === 0) return "";
                            let v = root.memoryService._cacheVersion;
                            return root.memoryService.readTopic(root.selectedTopic);
                        }
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.MarkdownText
                        readOnly: true
                        selectByMouse: true
                        selectedTextColor: Theme.bg0
                        selectionColor: Theme.accent2
                    }

                    // Editable view
                    TextEdit {
                        id: contentEditor
                        visible: root.editing
                        width: contentFlickable.width
                        text: {
                            if (!root.memoryService || root.selectedTopic.length === 0) return "";
                            let v = root.memoryService._cacheVersion;
                            return root.memoryService.readTopic(root.selectedTopic);
                        }
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        readOnly: false
                        selectByMouse: true
                        selectedTextColor: Theme.bg0
                        selectionColor: Theme.accent2
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Theme.bg3
                        }
                    }
                }
            }
        }
    }
}
