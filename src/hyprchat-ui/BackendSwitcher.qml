import QtQuick
import QtQuick.Layouts

// Dropdown popup for selecting backend + model.
Item {
    id: root

    property bool shown: false
    property string currentBackend: ""
    property string currentModel: ""
    property var models: []
    property bool loadingModels: false

    // Available backends
    readonly property var backends: ["copilot", "openai", "claude", "ollama"]

    signal backendSelected(string backend)
    signal modelSelected(string backend, string model)

    visible: shown
    implicitHeight: shown ? popup.height : 0
    clip: true

    // Click-away area
    MouseArea {
        anchors.fill: parent
        visible: root.shown
        onClicked: root.shown = false
    }

    Rectangle {
        id: popup
        width: parent.width - 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        height: popupContent.implicitHeight + 16
        radius: 8
        color: Theme.bg1
        border.color: Theme.border
        border.width: 1

        ColumnLayout {
            id: popupContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            // Backend tabs
            Text {
                text: "Backend"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                Layout.fillWidth: true
                Layout.leftMargin: 4
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.backends

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 4
                        color: modelData === root.currentBackend ? Theme.accent1 : (tabMouse.containsMouse ? Theme.bg3 : Theme.bg2)

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: modelData === root.currentBackend ? Theme.bg0 : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: modelData === root.currentBackend
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.backendSelected(modelData)
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                color: Theme.border
            }

            // Model list
            Text {
                text: root.loadingModels ? "Loading models..." : "Model"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                font.bold: true
                Layout.fillWidth: true
                Layout.leftMargin: 4
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(modelCol.implicitHeight, 250)
                contentHeight: modelCol.implicitHeight
                clip: true
                visible: root.models.length > 0
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: modelCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.models

                        Rectangle {
                            width: modelCol.width
                            height: 28
                            radius: 4
                            color: modelData.id === root.currentModel ? Theme.accent1 : (modelMouse.containsMouse ? Theme.bg3 : "transparent")

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                text: modelData.name
                                color: modelData.id === root.currentModel ? Theme.bg0 : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: modelData.id === root.currentModel
                            }

                            MouseArea {
                                id: modelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.modelSelected(root.currentBackend, modelData.id);
                                    root.shown = false;
                                }
                            }
                    }
                }
                }
            }

            // Empty state
            Text {
                text: "No models available"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                Layout.fillWidth: true
                Layout.leftMargin: 8
                visible: root.models.length === 0 && !root.loadingModels
            }
        }
    }
}
