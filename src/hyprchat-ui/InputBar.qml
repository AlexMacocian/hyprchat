import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property bool enabled: true
    property bool streaming: false
    signal messageSent(string text)
    signal stopRequested()

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
                font.pixelSize: Theme.fontSize + 2
                wrapMode: TextEdit.Wrap
                focus: true

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                        event.accepted = true;
                        if (!root.enabled) return;
                        let msg = inputArea.text.trim();
                        if (msg.length > 0) {
                            root.messageSent(msg);
                            inputArea.text = "";
                        }
                    }
                }
            }
        }

        // Send / Stop button
        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 16
            color: actionMouse.containsMouse ? Theme.accent2 : Theme.accent1

            // Up arrow (send) or Stop square
            Item {
                anchors.centerIn: parent
                width: 14
                height: 14

                // Send arrow (▲)
                Canvas {
                    id: sendIcon
                    anchors.fill: parent
                    visible: !root.streaming
                    onPaint: {
                        let ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.fillStyle = Theme.bg0;
                        ctx.beginPath();
                        ctx.moveTo(7, 0);
                        ctx.lineTo(14, 10);
                        ctx.lineTo(9, 10);
                        ctx.lineTo(9, 14);
                        ctx.lineTo(5, 14);
                        ctx.lineTo(5, 10);
                        ctx.lineTo(0, 10);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                // Stop square (■)
                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: 2
                    color: Theme.bg0
                    visible: root.streaming
                }
            }

            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.streaming) {
                        root.stopRequested();
                    } else if (root.enabled) {
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
