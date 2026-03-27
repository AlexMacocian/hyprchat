import QtQuick

Item {
    id: root

    required property bool isUser
    required property string content
    property int messageIndex: -1
    property bool collapsed: false
    property bool sent: true
    property bool isSystem: false

    signal toggleCollapse(int messageIndex)

    readonly property real collapsedHeight: Theme.fontSize * 3.5
    readonly property bool canCollapse: msgText.implicitHeight > collapsedHeight + 20

    implicitHeight: root.isSystem ? divider.height + 8 : bubble.height + 8
    height: implicitHeight
    opacity: root.sent ? 1.0 : 0.4

    // System divider (summary separator)
    Rectangle {
        id: divider
        visible: root.isSystem
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        height: visible ? dividerText.implicitHeight + 12 : 0
        color: "transparent"

        Text {
            id: dividerText
            anchors.centerIn: parent
            text: root.content
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.italic: true
        }
    }

    Rectangle {
        id: bubble
        visible: !root.isSystem

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

            onLinkActivated: (link) => {
                Qt.openUrlExternally(link);
            }

            // Show pointer cursor on links
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: msgText.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.IBeamCursor
            }
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
                onClicked: root.toggleCollapse(root.messageIndex)
            }
        }
    }
}
