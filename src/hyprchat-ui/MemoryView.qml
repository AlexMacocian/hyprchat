import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Memory viewer panel — browse, read, edit, delete memory topics.
Item {
    id: root

    property bool shown: false
    property var backendProcess: null
    property string selectedTopic: ""
    property bool editing: false
    property var _topics: []
    property string _topicContent: ""
    property int _refreshCount: 0

    visible: shown

    onShownChanged: {
        if (shown && backendProcess) {
            _refreshTopics();
        }
    }

    function _refreshTopics() {
        if (!backendProcess) return;
        backendProcess.memoryList(function(topics) {
            root._topics = topics;
            root._refreshCount++;
        });
    }

    function _loadTopicContent(topic) {
        if (!backendProcess) return;
        backendProcess.memoryRead(topic, function(content) {
            root._topicContent = content;
        });
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
                                    if (root.backendProcess) {
                                        root.backendProcess.memoryEdit(root.selectedTopic, contentEditor.text);
                                    }
                                    root.editing = false;
                                    root._loadTopicContent(root.selectedTopic);
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
                        color: deleteMouse.containsMouse ? Theme.dangerBg : "transparent"
                        visible: root.selectedTopic.length > 0

                        Text {
                            id: deleteLabel
                            anchors.centerIn: parent
                            text: "Delete"
                            color: deleteMouse.containsMouse ? Theme.danger : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (root.backendProcess) {
                                    root.backendProcess.memoryDelete(root.selectedTopic);
                                }
                                root.selectedTopic = "";
                                root.editing = false;
                                root._refreshTopics();
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
                    visible: root.selectedTopic.length === 0 && root.backendProcess !== null
                    clip: true
                    spacing: 2

                    model: {
                        let v = root._refreshCount;
                        return root._topics;
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
                                root._loadTopicContent(modelData);
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
                        text: root._topicContent
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
                        text: root._topicContent
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
