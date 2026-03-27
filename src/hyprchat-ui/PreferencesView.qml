import QtQuick
import QtQuick.Layouts

// Preferences panel — configure HyprChat settings.
Item {
    id: root

    property bool shown: false
    property var preferences: null
    property var modelFetcher: null  // deprecated, unused
    property var backendProcess: null  // set from ChatWindow

    // Local copies for editing (not applied until Save)
    property real editThreshold: 0.7
    property int editKeepRecent: 4
    property string editSystemPrompt: ""
    property bool editMemoryEnabled: true
    property bool editWebSearchEnabled: true
    property bool editShellEnabled: false
    property bool editFileAccessEnabled: true
    property string editFileAccessRoot: "/"
    property bool editDateEnabled: true

    // Profile editor state
    property bool editingProfile: false
    property bool creatingProfile: false
    property string editProfileOrigName: ""
    property string editProfileName: ""
    property string editProfileIcon: "🤖"
    property string editProfileBackend: "copilot"
    property string editProfileModel: "gpt-4o"
    property string editProfilePrompt: ""
    property var editProfileModels: []  // fetched models for current backend
    property bool editProfileModelLoading: false

    visible: shown

    onShownChanged: {
        if (shown && preferences) {
            // Load current values into edit fields
            editThreshold = preferences.summarizeThreshold;
            editKeepRecent = preferences.keepRecentMessages;
            editMemoryEnabled = preferences.memoryEnabled;
            editWebSearchEnabled = preferences.webSearchEnabled;
            editShellEnabled = preferences.shellEnabled;
            editFileAccessEnabled = preferences.fileAccessEnabled;
            editFileAccessRoot = preferences.fileAccessRoot;
            editDateEnabled = preferences.dateEnabled;
        }
    }

    onEditProfileBackendChanged: {
        if (editingProfile && backendProcess) {
            _fetchModelsForBackend(editProfileBackend);
        }
        _autoSaveProfile();
    }

    onEditProfileModelChanged: _autoSaveProfile()
    onEditProfileNameChanged: _autoSaveProfile()
    onEditProfileIconChanged: _autoSaveProfile()
    onEditProfilePromptChanged: _autoSaveProfile()

    // Auto-save profile changes (debounced)
    property bool _autoSaveQueued: false

    function _autoSaveProfile() {
        if (!editingProfile || creatingProfile || !preferences) return;
        if (editProfileOrigName.length === 0) return;
        if (!_autoSaveQueued) {
            _autoSaveQueued = true;
            autoSaveTimer.running = true;
        }
    }

    Timer {
        id: autoSaveTimer
        interval: 500  // debounce 500ms
        running: false
        repeat: false
        onTriggered: {
            root._autoSaveQueued = false;
            if (!root.editingProfile || root.creatingProfile) return;
            let prof = {
                name: root.editProfileName,
                icon: root.editProfileIcon,
                backend: root.editProfileBackend,
                model: root.editProfileModel,
                systemPrompt: root.editProfilePrompt
            };
            root.preferences.updateProfile(root.editProfileOrigName, prof);
            // Update origName in case name changed
            root.editProfileOrigName = root.editProfileName;
            console.log("PreferencesView: auto-saved profile", prof.name);
        }
    }

    function _fetchModelsForBackend(backend) {
        if (!backendProcess) { console.log("PreferencesView: no backendProcess"); return; }
        // Use cached models if available for this backend
        if (backendProcess.cachedModelsBackend === backend && backendProcess.cachedModels.length > 0) {
            console.log("PreferencesView: using cached models for", backend, "count:", backendProcess.cachedModels.length);
            editProfileModels = backendProcess.cachedModels;
            editProfileModelLoading = false;
            return;
        }
        console.log("PreferencesView: fetching models for", backend);
        editProfileModelLoading = true;
        editProfileModels = [];
        backendProcess.fetchModels(backend, backendProcess.apiKey, "");
    }

    // Listen for model fetcher completion
    Connections {
        target: root.backendProcess
        function onModelsFetched(models) {
            console.log("PreferencesView: got", models.length, "models, editing:", root.editingProfile);
            if (root.editingProfile) {
                root.editProfileModels = models;
                root.editProfileModelLoading = false;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg0

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: Theme.bg1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: "Preferences"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    // Save button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: saveLabel.implicitWidth + 16
                        radius: 4
                        color: saveMouse.containsMouse ? Theme.accent2 : Theme.accent1

                        Text {
                            id: saveLabel
                            anchors.centerIn: parent
                            text: "Save"
                            color: Theme.bg0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }

                        MouseArea {
                            id: saveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.preferences.summarizeThreshold = root.editThreshold;
                                root.preferences.keepRecentMessages = root.editKeepRecent;
                                root.preferences.memoryEnabled = root.editMemoryEnabled;
                                root.preferences.webSearchEnabled = root.editWebSearchEnabled;
                                root.preferences.shellEnabled = root.editShellEnabled;
                                root.preferences.fileAccessEnabled = root.editFileAccessEnabled;
                                root.preferences.fileAccessRoot = root.editFileAccessRoot;
                                root.preferences.dateEnabled = root.editDateEnabled;
                                root.preferences.save();
                                root.shown = false;
                            }
                        }
                    }

                    // Close button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: closeLabel.implicitWidth + 12
                        radius: 4
                        color: closeMouse.containsMouse ? Theme.bg3 : "transparent"

                        Text {
                            id: closeLabel
                            anchors.centerIn: parent
                            text: "Close"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.shown = false
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // Settings
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Flickable {
                    id: settingsFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: settingsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: settingsCol
                    width: settingsFlick.width
                    spacing: 16

                    Item { Layout.preferredHeight: 8 }

                    // --- Profiles ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "Profiles"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            // New profile button
                            Rectangle {
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: newProfLabel.implicitWidth + 12
                                radius: 4
                                color: newProfMouse.containsMouse ? Theme.accent2 : Theme.accent1

                                Text {
                                    id: newProfLabel
                                    anchors.centerIn: parent
                                    text: "+ New"
                                    color: Theme.bg0
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                }

                                MouseArea {
                                    id: newProfMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.creatingProfile = true;
                                        root.editingProfile = true;
                                        root.editProfileOrigName = "";
                                        root.editProfileName = "";
                                        root.editProfileIcon = "🤖";
                                        root.editProfileBackend = "copilot";
                                        root.editProfileModel = "gpt-4o";
                                        root.editProfilePrompt = "You are a helpful assistant.";
                                        root._fetchModelsForBackend("copilot");
                                    }
                                }
                            }
                        }

                        // Profile list
                        Column {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: !root.editingProfile

                            Repeater {
                                model: root.preferences ? root.preferences.profiles : []

                                Rectangle {
                                    width: parent ? parent.width : 0
                                    height: 44
                                    radius: 6
                                    color: "transparent"

                                    Text {
                                        id: profIcon
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.icon || "🤖"
                                        font.pixelSize: Theme.fontSize + 4
                                        width: 28
                                    }

                                    Column {
                                        anchors.left: profIcon.right
                                        anchors.leftMargin: 8
                                        anchors.right: profBtns.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0

                                        Text {
                                            text: modelData.name
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.bold: modelData.name === root.preferences.activeProfileName
                                        }

                                        Text {
                                            text: modelData.backend + " · " + modelData.model
                                            color: Theme.textDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                    }

                                    Row {
                                        id: profBtns
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        Rectangle {
                                            width: 40; height: 22; radius: 4
                                            color: editBtnMouse.containsMouse ? Theme.bg3 : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Edit"
                                                color: Theme.textDim
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize - 2
                                            }

                                            MouseArea {
                                                id: editBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    root.creatingProfile = false;
                                                    root.editingProfile = true;
                                                    root.editProfileOrigName = modelData.name;
                                                    root.editProfileName = modelData.name;
                                                    root.editProfileIcon = modelData.icon || "🤖";
                                                    root.editProfileBackend = modelData.backend;
                                                    root.editProfileModel = modelData.model;
                                                    root.editProfilePrompt = modelData.systemPrompt;
                                                    root._fetchModelsForBackend(modelData.backend);
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: 22; height: 22; radius: 4
                                            color: delBtnMouse.containsMouse ? Theme.dangerBg : "transparent"
                                            visible: modelData.name !== "Assistant"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "×"
                                                color: delBtnMouse.containsMouse ? Theme.danger : Theme.textDim
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize
                                            }

                                            MouseArea {
                                                id: delBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: root.preferences.deleteProfile(modelData.name)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Profile editor form
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.editingProfile

                            // Name + Icon row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 40
                                    Layout.preferredHeight: 32
                                    radius: 4
                                    color: Theme.bg2

                                    TextEdit {
                                        anchors.centerIn: parent
                                        text: root.editProfileIcon
                                        font.pixelSize: Theme.fontSize + 4
                                        onTextChanged: root.editProfileIcon = text
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 4
                                    color: Theme.bg2
                                    border.color: Theme.border
                                    border.width: 1

                                    TextEdit {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        text: root.editProfileName
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        onTextChanged: root.editProfileName = text
                                    }
                                }
                            }

                            // Backend selector
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "Backend"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }

                                Row {
                                    spacing: 4

                                    Repeater {
                                        model: ["copilot", "openai", "claude", "ollama"]

                                        Rectangle {
                                            width: bkLabel.implicitWidth + 12
                                            height: 28
                                            radius: 4
                                            color: modelData === root.editProfileBackend ? Theme.accent1 : (bkMouse.containsMouse ? Theme.bg3 : Theme.bg2)

                                            Text {
                                                id: bkLabel
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: modelData === root.editProfileBackend ? Theme.bg0 : Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize - 1
                                                font.bold: modelData === root.editProfileBackend
                                            }

                                            MouseArea {
                                                id: bkMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: root.editProfileBackend = modelData
                                            }
                                        }
                                    }
                                }
                            }

                            // Model selector
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: root.editProfileModelLoading ? "Model (loading...)" : "Model"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }

                                // Current selection
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 4
                                    color: Theme.bg3

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        text: root.editProfileModel || "(select a model)"
                                        color: root.editProfileModel ? Theme.text : Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                    }
                                }

                                // Model list
                                ListView {
                                    id: modelListView
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.min(count * 27, 150)
                                    visible: count > 0
                                    clip: true
                                    interactive: false
                                    spacing: 1
                                    model: root.editProfileModels
                                    boundsBehavior: Flickable.StopAtBounds

                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: modelListView.width
                                        height: 26
                                        radius: 3
                                        color: modelData.id === root.editProfileModel ? Theme.accent1 : (mdlMouse.containsMouse ? Theme.bg3 : "transparent")

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            text: modelData.name || modelData.id
                                            color: modelData.id === root.editProfileModel ? Theme.bg0 : Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                            font.bold: modelData.id === root.editProfileModel
                                        }

                                        MouseArea {
                                            id: mdlMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                root.editProfileModel = modelData.id;
                                            }
                                        }
                                    }
                                }
                            }

                            // System prompt
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "System Prompt"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 60
                                    radius: 4
                                    color: Theme.bg2
                                    border.color: Theme.border
                                    border.width: 1

                                    TextEdit {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        text: root.editProfilePrompt
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                        wrapMode: TextEdit.Wrap
                                        onTextChanged: root.editProfilePrompt = text
                                    }
                                }
                            }

                            // Done button
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    Layout.preferredWidth: 60
                                    Layout.preferredHeight: 26
                                    radius: 4
                                    color: doneProfMouse.containsMouse ? Theme.accent2 : Theme.accent1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Done"
                                        color: Theme.bg0
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: doneProfMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (root.creatingProfile && root.editProfileName.length > 0) {
                                                let prof = {
                                                    name: root.editProfileName,
                                                    icon: root.editProfileIcon,
                                                    backend: root.editProfileBackend,
                                                    model: root.editProfileModel,
                                                    systemPrompt: root.editProfilePrompt
                                                };
                                                root.preferences.addProfile(prof);
                                            }
                                            root.editingProfile = false;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Memory Toggle ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Memory"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: "Enable persistent memory. The model will save and recall information across conversations."
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                        }

                        // Toggle
                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 24
                            radius: 12
                            color: root.editMemoryEnabled ? Theme.accent1 : Theme.bg3

                            Rectangle {
                                x: root.editMemoryEnabled ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                radius: 9
                                color: Theme.text

                                Behavior on x {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editMemoryEnabled = !root.editMemoryEnabled
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Web Search Toggle ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Web Search"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: "Allow the model to search the web via DuckDuckGo and read pages."
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 24
                            radius: 12
                            color: root.editWebSearchEnabled ? Theme.accent1 : Theme.bg3

                            Rectangle {
                                x: root.editWebSearchEnabled ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; radius: 9
                                color: Theme.text
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editWebSearchEnabled = !root.editWebSearchEnabled
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Shell Toggle ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Shell Commands"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: "Allow the model to execute shell commands. Runs as your user — use with caution."
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 24
                            radius: 12
                            color: root.editShellEnabled ? Theme.accent1 : Theme.bg3

                            Rectangle {
                                x: root.editShellEnabled ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; radius: 9
                                color: Theme.text
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editShellEnabled = !root.editShellEnabled
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- File Access Toggle + Root ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "File Access"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: "Allow the model to read and write files."
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 24
                            radius: 12
                            color: root.editFileAccessEnabled ? Theme.accent1 : Theme.bg3

                            Rectangle {
                                x: root.editFileAccessEnabled ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; radius: 9
                                color: Theme.text
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editFileAccessEnabled = !root.editFileAccessEnabled
                            }
                        }
                    }

                    // File root path
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 2
                        visible: root.editFileAccessEnabled

                        Text {
                            text: "Allowed Root Path"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 4
                            color: Theme.bg2
                            border.color: Theme.border
                            border.width: 1

                            TextEdit {
                                anchors.fill: parent
                                anchors.margins: 6
                                text: root.editFileAccessRoot
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                onTextChanged: root.editFileAccessRoot = text
                            }
                        }

                        Text {
                            text: "Files outside this path will be blocked. Use \"/\" for unrestricted access."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Date & Time Toggle ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Date & Time"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: "Give the model access to current date/time, day-of-week lookups, and date arithmetic."
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 24
                            radius: 12
                            color: root.editDateEnabled ? Theme.accent1 : Theme.bg3

                            Rectangle {
                                x: root.editDateEnabled ? parent.width - width - 3 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18; radius: 9
                                color: Theme.text
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editDateEnabled = !root.editDateEnabled
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Summarize Threshold ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 4

                        Text {
                            text: "Summarize Threshold"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }

                        Text {
                            text: "Trigger conversation summarization when context usage exceeds this percentage."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            // Custom slider — Slider widget doesn't work in QuickShell
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24

                                Rectangle {
                                    id: thresholdTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 4
                                    radius: 2
                                    color: Theme.bg2

                                    Rectangle {
                                        width: parent.width * ((root.editThreshold - 0.1) / 0.9)
                                        height: parent.height
                                        radius: 2
                                        color: Theme.accent1
                                    }
                                }

                                Rectangle {
                                    id: thresholdHandle
                                    x: thresholdTrack.width * ((root.editThreshold - 0.1) / 0.9) - width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: thresholdDrag.pressed ? Theme.accent2 : Theme.accent1
                                }

                                MouseArea {
                                    id: thresholdDrag
                                    anchors.fill: parent
                                    onPressed: updateThreshold(mouse)
                                    onPositionChanged: updateThreshold(mouse)

                                    function updateThreshold(mouse) {
                                        let ratio = Math.max(0, Math.min(1, mouse.x / width));
                                        root.editThreshold = Math.round((0.1 + ratio * 0.9) * 20) / 20; // snap to 0.05
                                    }
                                }
                            }

                            Text {
                                text: Math.round(root.editThreshold * 100) + "%"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.preferredWidth: 40
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: Theme.border
                    }

                    // --- Keep Recent Messages ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 4

                        Text {
                            text: "Keep Recent Messages"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }

                        Text {
                            text: "Number of recent messages to preserve after summarization."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24

                                Rectangle {
                                    id: keepTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 4
                                    radius: 2
                                    color: Theme.bg2

                                    Rectangle {
                                        width: parent.width * (root.editKeepRecent / 20)
                                        height: parent.height
                                        radius: 2
                                        color: Theme.accent1
                                    }
                                }

                                Rectangle {
                                    x: keepTrack.width * (root.editKeepRecent / 20) - width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: keepDrag.pressed ? Theme.accent2 : Theme.accent1
                                }

                                MouseArea {
                                    id: keepDrag
                                    anchors.fill: parent
                                    onPressed: updateKeep(mouse)
                                    onPositionChanged: updateKeep(mouse)

                                    function updateKeep(mouse) {
                                        let ratio = Math.max(0, Math.min(1, mouse.x / width));
                                        root.editKeepRecent = Math.round(ratio * 20);
                                    }
                                }
                            }

                            Text {
                                text: root.editKeepRecent
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.preferredWidth: 30
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 16 }
                }
                }
            }
        }
    }
}
