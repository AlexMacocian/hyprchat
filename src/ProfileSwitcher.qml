import QtQuick
import QtQuick.Layouts

// Dropdown listing all profiles. Click one to switch.
Item {
    id: root

    property bool shown: false
    property var profiles: []
    property string activeProfileName: ""

    signal profileSelected(string name)

    visible: shown
    implicitHeight: shown ? (root.profiles.length * 42 + 24) : 0
    clip: true

    Rectangle {
        id: popup
        width: parent.width - 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        height: root.profiles.length * 42 + 20
        radius: 8
        color: Theme.bg1
        border.color: Theme.border
        border.width: 1

        Column {
            id: profileCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 2

            Repeater {
                model: root.profiles

                Rectangle {
                    width: parent ? parent.width : 0
                    height: 40
                    radius: 6
                    color: modelData.name === root.activeProfileName ? Theme.accent1 : (itemMouse.containsMouse ? Theme.bg3 : "transparent")

                    // Icon
                    Text {
                        id: profDropIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.icon || "🤖"
                        font.pixelSize: Theme.fontSize + 2
                        width: 24
                    }

                    // Name + subtitle
                    Column {
                        anchors.left: profDropIcon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            text: modelData.name
                            color: modelData.name === root.activeProfileName ? Theme.bg0 : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: modelData.name === root.activeProfileName
                        }

                        Text {
                            text: modelData.backend + " · " + modelData.model
                            color: modelData.name === root.activeProfileName ? Theme.bg1 : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.profileSelected(modelData.name);
                            root.shown = false;
                        }
                    }
                }
            }
        }
    }
}
