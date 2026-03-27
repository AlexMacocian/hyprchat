import QtQuick
import QtQuick.Controls

Item {
    id: root

    property alias model: messageList.model
    property var collapsedIndices: ({})
    property int _collapseVersion: 0

    function scrollToBottom() {
        messageList.positionViewAtEnd();
    }

    function isCollapsed(idx) {
        // Reference _collapseVersion to trigger re-evaluation
        let v = _collapseVersion;
        return collapsedIndices[idx] === true;
    }

    function toggleCollapsed(idx) {
        if (collapsedIndices[idx]) {
            delete collapsedIndices[idx];
        } else {
            collapsedIndices[idx] = true;
        }
        _collapseVersion++;
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
            required property int index
            required property bool sent
            width: messageList.width
            isUser: role === "user"
            isSystem: role === "system"
            content: text
            sent: sent
            collapsed: { let v = root._collapseVersion; return root.isCollapsed(index); }
            messageIndex: index

            onToggleCollapse: (idx) => {
                root.toggleCollapsed(idx);
            }
        }

        onCountChanged: {
            Qt.callLater(scrollToBottom);
        }
    }
}
