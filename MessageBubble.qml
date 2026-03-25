import QtQuick

Item {
    id: root

    required property bool isUser
    required property string content

    property bool collapsed: false
    readonly property real collapsedHeight: Theme.fontSize * 3.5  // ~2 lines
    readonly property bool canCollapse: msgText.implicitHeight > collapsedHeight + 20

    implicitHeight: bubble.height + 8
    height: implicitHeight

    Rectangle {
        id: bubble

        anchors.right: root.isUser ? parent.right : undefined
        anchors.left: root.isUser ? undefined : parent.left
        anchors.margins: 12

        width: Math.min(msgText.implicitWidth + 24, root.width - 24)
        height: (root.collapsed ? Math.min(msgText.implicitHeight, root.collapsedHeight) : msgText.implicitHeight) + 16 + (root.canCollapse ? collapseBtn.height + 4 : 0)
        radius: 8
        color: root.isUser ? Theme.accent1 : Theme.bg2
        clip: true

        TextEdit {
            id: msgText
            width: parent.width - 24
            x: 12
            y: 8
            height: root.collapsed ? Math.min(implicitHeight, root.collapsedHeight) : implicitHeight
            clip: root.collapsed
            text: root.content
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

        // Collapse/expand button
        Text {
            id: collapseBtn
            visible: root.canCollapse
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 8
            text: root.collapsed ? "▼ expand" : "▲ collapse"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.collapsed = !root.collapsed
            }
        }
    }
}
