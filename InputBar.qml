import QtQuick
import QtQuick.Layouts

Item {
    id: root

    signal messageSent(string text)

    implicitHeight: inputLayout.implicitHeight

    RowLayout {
        id: inputLayout
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(inputArea.implicitHeight + 16, 150)
            radius: 8
            color: Theme.bg2
            border.color: inputArea.activeFocus ? Theme.accent1 : Theme.border
            border.width: 1

            TextEdit {
                id: inputArea
                anchors.fill: parent
                anchors.margins: 8
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                wrapMode: TextEdit.Wrap
                focus: true

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                        event.accepted = true;
                        let msg = inputArea.text.trim();
                        if (msg.length > 0) {
                            root.messageSent(msg);
                            inputArea.text = "";
                        }
                    }
                }
            }
        }
    }

    function focusInput() {
        inputArea.forceActiveFocus();
    }
}
