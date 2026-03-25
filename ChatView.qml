import QtQuick
import QtQuick.Layouts

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

        delegate: MessageBubble {
            width: messageList.width
            isUser: model.role === "user"
            content: model.text
        }

        onCountChanged: {
            Qt.callLater(scrollToBottom);
        }
    }
}
