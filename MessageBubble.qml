import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property bool isUser
    required property string content

    Layout.fillWidth: true
    Layout.preferredHeight: bubble.height + 8

    Rectangle {
        id: bubble

        anchors {
            right: root.isUser ? parent.right : undefined
            left: root.isUser ? undefined : parent.left
            margins: 12
        }

        width: Math.min(msgText.implicitWidth + 24, root.width * 0.8)
        height: msgText.implicitHeight + 16
        radius: 8
        color: root.isUser ? Theme.accent1 : Theme.bg2

        Text {
            id: msgText
            anchors.fill: parent
            anchors.margins: 12
            text: root.content
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
        }
    }
}
