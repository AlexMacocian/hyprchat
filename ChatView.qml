import QtQuick
import QtQuick.Controls

Item {
    id: root

    property alias model: messageList.model

    function scrollToBottom() {
        messageList.positionViewAtEnd();
    }

    ListView {
        id: messageList
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4
        clip: true
        verticalLayoutDirection: ListView.TopToBottom

        // Scrollbar
        ScrollBar.vertical: ScrollBar {
            id: scrollBar
            active: true
            policy: ScrollBar.AsNeeded

            contentItem: Rectangle {
                implicitWidth: 4
                radius: 2
                color: scrollBar.pressed ? Theme.accent1 : (scrollBar.hovered ? Theme.textDim : Theme.bg3)
                opacity: scrollBar.active ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }

            background: Rectangle {
                implicitWidth: 4
                color: "transparent"
            }
        }

        delegate: MessageBubble {
            required property string role
            required property string text
            width: messageList.width
            isUser: role === "user"
            content: text
        }

        onCountChanged: {
            Qt.callLater(scrollToBottom);
        }
    }
}
