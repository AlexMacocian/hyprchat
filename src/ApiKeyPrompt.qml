import QtQuick
import QtQuick.Layouts

// Inline prompt shown when a backend is missing its API key.
Item {
    id: root

    property string backendName: ""
    property bool shown: false

    signal keySubmitted(string key)
    signal cancelled()

    visible: shown
    implicitHeight: shown ? content.implicitHeight + 24 : 0
    clip: true

    Rectangle {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        visible: root.shown
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
                text: "API key required for **" + root.backendName + "**"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                textFormat: Text.MarkdownText
                Layout.fillWidth: true
            }

            Text {
                text: "The key will be stored in your system keyring."
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 4
                    color: Theme.bg2
                    border.color: keyInput.activeFocus ? Theme.accent1 : Theme.border
                    border.width: 1

                    TextEdit {
                        id: keyInput
                        anchors.fill: parent
                        anchors.margins: 6
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        verticalAlignment: TextEdit.AlignVCenter

                        Keys.onReturnPressed: {
                            submitKey();
                        }
                        Keys.onEscapePressed: {
                            root.cancelled();
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 32
                    radius: 4
                    color: submitMouse.containsMouse ? Theme.accent2 : Theme.accent1

                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        color: Theme.bg0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    MouseArea {
                        id: submitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: submitKey()
                    }
                }
            }
        }
    }

    function submitKey() {
        let key = keyInput.text.trim();
        if (key.length > 0) {
            root.keySubmitted(key);
            keyInput.text = "";
        }
    }

    function focusInput() {
        keyInput.forceActiveFocus();
    }
}
