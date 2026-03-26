import QtQuick
import Quickshell.Io

// Manages secrets in the system keyring via secret-tool (libsecret).
// All entries use: service=hyprchat, account=<backend name>
Item {
    id: root

    signal keyRetrieved(string account, string key)
    signal keyMissing(string account)
    signal keyError(string account, string error)
    signal keyStored(string account)
    signal keyDeleted(string account)

    property string _pendingAccount: ""
    property string _pendingAction: "" // "lookup", "store", "delete"

    function lookup(account) {
        if (lookupProcess.running) {
            console.warn("KeyringService: lookup already in progress");
            return;
        }
        _pendingAccount = account;
        _pendingAction = "lookup";
        lookupProcess.command = ["secret-tool", "lookup", "service", "hyprchat", "account", account];
        lookupProcess.running = true;
    }

    function store(account, key) {
        if (storeProcess.running) {
            console.warn("KeyringService: store already in progress");
            return;
        }
        _pendingAccount = account;
        _pendingAction = "store";
        storeProcess.command = [
            "bash", "-c",
            "echo -n " + Qt.btoa(key) + " | base64 -d | secret-tool store --label='HyprChat " + account + "' service hyprchat account " + account
        ];
        storeProcess.running = true;
    }

    function remove(account) {
        if (deleteProcess.running) {
            console.warn("KeyringService: delete already in progress");
            return;
        }
        _pendingAccount = account;
        _pendingAction = "delete";
        deleteProcess.command = ["secret-tool", "clear", "service", "hyprchat", "account", account];
        deleteProcess.running = true;
    }

    Process {
        id: lookupProcess
        running: false

        stdout: StdioCollector {
            id: lookupStdout
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: lookupStderr
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            let account = root._pendingAccount;
            if (exitCode === 0) {
                let key = lookupStdout.text.trim();
                if (key.length > 0) {
                    root.keyRetrieved(account, key);
                } else {
                    root.keyMissing(account);
                }
            } else {
                // secret-tool returns non-zero when no match — treat as missing
                root.keyMissing(account);
            }
        }
    }

    Process {
        id: storeProcess
        running: false

        stderr: StdioCollector {
            id: storeStderr
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            let account = root._pendingAccount;
            if (exitCode === 0) {
                root.keyStored(account);
            } else {
                root.keyError(account, "Failed to store key: " + storeStderr.text.trim());
            }
        }
    }

    Process {
        id: deleteProcess
        running: false

        stderr: StdioCollector {
            id: deleteStderr
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            let account = root._pendingAccount;
            if (exitCode === 0) {
                root.keyDeleted(account);
            } else {
                root.keyError(account, "Failed to delete key: " + deleteStderr.text.trim());
            }
        }
    }
}
