//
//  hs.ipc.js
//  Hammerspoon 2
//
//  Created on 2025-12-27.
//  JavaScript protocol handler for IPC module
//

// Message ID constants (must match IPCProtocol.swift)
const MSG_ID = {
    REGISTER: 100,
    UNREGISTER: 200,
    COMMAND: 500,
    QUERY: 501,
    ERROR: -1,
    OUTPUT: 1,
    RETURN: 2,
    CONSOLE: 3
};

// IPC state is stored in closure-scoped variables rather than on the
// hs.ipc JSExport proxy, because JSExport proxy objects lose dynamically
// assigned properties when the garbage collector reclaims their wrappers.
var __ipcRegisteredInstances = {};
var __ipcRemotePorts = {};
var __ipcDefaultPort = null;
var __ipcOriginalPrint = (typeof print !== 'undefined') ? print : console.log;

// Default message handler for IPC protocol
// DEFENSIVE: Wrapped in try-catch to ensure Hammerspoon never crashes from IPC errors
var __ipcDefaultHandler = function(port, msgID, data) {
    try {
        // Parse message based on type
        if (msgID === MSG_ID.REGISTER) {
            // REGISTER: instanceID\0{...json...}
            const nullIndex = data.indexOf('\0');
            if (nullIndex === -1) {
                return "error: invalid register message format";
            }

            const instanceID = data.substring(0, nullIndex);
            const argsJSON = data.substring(nullIndex + 1);

            // Parse JSON arguments
            let args;
            try {
                args = JSON.parse(argsJSON);
            } catch (e) {
                return "error: invalid JSON in register message";
            }

            const quiet = args.quiet || false;
            const consoleMirroring = args.console || false;
            const customArgs = args.customArgs || [];

            // Create remote port for this instance
            // Defensive: Handle port creation failure gracefully (can happen when hitting OS limits)
            const remote = hs.ipc.remotePort(instanceID);
            if (!remote) {
                console.error("IPC: Failed to create remote port for instance:", instanceID);
                return "error: failed to create remote port - resource limit reached";
            }

            // Store remote port to prevent garbage collection
            // This is CRITICAL - without this, the remote port object gets deallocated
            // and causes crashes when callbacks try to access it
            __ipcRemotePorts[instanceID] = remote;

            // Create instance object with isolated _cli and print
            __ipcRegisteredInstances[instanceID] = {
                _cli: {
                    remote: remote,
                    quietMode: quiet,
                    console: consoleMirroring,
                    args: customArgs
                },
                print: function(...args) {
                    const instance = __ipcRegisteredInstances[instanceID];
                    if (!instance) {
                        return;
                    }
                    if (instance._cli.quietMode) {
                        return;
                    }

                    const output = args.map(a => String(a)).join('\t') + '\n';
                    instance._cli.remote.sendMessage(output, MSG_ID.OUTPUT, 4.0, true);  // oneWay=true to avoid deadlock
                }
            };

            return "ok";

        } else if (msgID === MSG_ID.UNREGISTER) {
            // UNREGISTER: instanceID
            const instanceID = data;

            // Defensive: Safe cleanup even if instance doesn't exist
            try {
                if (__ipcRegisteredInstances[instanceID]) {
                    const instance = __ipcRegisteredInstances[instanceID];
                    if (instance && instance._cli && instance._cli.remote) {
                        try {
                            instance._cli.remote.delete();
                        } catch (e) {
                            console.error("IPC: Error deleting remote port:", e);
                        }
                    }
                    delete __ipcRegisteredInstances[instanceID];
                }

                // Clean up remote port storage to prevent resource leak
                if (__ipcRemotePorts[instanceID]) {
                    delete __ipcRemotePorts[instanceID];
                }
            } catch (e) {
                console.error("IPC: Error during UNREGISTER cleanup:", e);
            }

            // No response needed for unregister
            return undefined;

        } else if (msgID === MSG_ID.COMMAND || msgID === MSG_ID.QUERY) {
            // COMMAND/QUERY: instanceID\0code
            const nullIndex = data.indexOf('\0');
            if (nullIndex === -1) {
                return "error: invalid command message format";
            }

            const instanceID = data.substring(0, nullIndex);
            const code = data.substring(nullIndex + 1);

            const instance = __ipcRegisteredInstances[instanceID];
            if (!instance) {
                return "error: instance not registered - client must reconnect";
            }

            // Execute code with instance-specific _cli and print as parameters
            let result;
            let evalError = null;

            const trimmedCode = code.trim();

            // Always try implicit return first, fall back to bare code on SyntaxError
            try {
                const fn = new Function('_cli', 'print', 'return ' + trimmedCode);
                result = fn(instance._cli, instance.print);
            } catch (e1) {
                if (e1 instanceof SyntaxError) {
                    // Implicit return failed with SyntaxError - try as statements
                    try {
                        const fn = new Function('_cli', 'print', trimmedCode);
                        result = fn(instance._cli, instance.print);
                    } catch (e2) {
                        evalError = e2;
                    }
                } else {
                    evalError = e1;
                }
            }

            // Handle errors
            if (evalError) {
                try {
                    const errorMsg = String(evalError) + '\n';
                    instance._cli.remote.sendMessage(errorMsg, MSG_ID.ERROR, 4.0, true);  // oneWay=true
                } catch (e) {
                    console.error("IPC: Failed to send error message to client:", e);
                }
                // Return "ok" to indicate IPC protocol succeeded even though JavaScript evaluation failed.
                return "ok";
            }

            // Format and send result
            if (msgID === MSG_ID.COMMAND) {
                // For COMMAND, send result as RETURN message
                try {
                    if (result !== undefined && result !== null) {
                        const resultStr = String(result) + '\n';
                        instance._cli.remote.sendMessage(resultStr, MSG_ID.RETURN, 4.0, true);  // oneWay=true
                    }
                } catch (e) {
                    console.error("IPC: Failed to send result to client:", e);
                    return "error: send failed";
                }
                return "ok";
            } else {
                // For QUERY, return result directly
                try {
                    return (result !== undefined && result !== null) ? String(result) : "";
                } catch (e) {
                    console.error("IPC: Failed to convert result to string:", e);
                    return "error: conversion failed";
                }
            }

        } else {
            return "error: unknown message ID";
        }
    } catch (e) {
        console.error("IPC handler error:", e);
        return "error: " + String(e);
    }
};

// NOTE: __ipcPrint is not yet functional.
// The JS engine has no global 'print' function, so it cannot be replaced.
// This function is retained for future use when console mirroring is implemented.
// See docs/IPC.md "Console Mirroring" for details.
var __ipcPrint = function(...args) {
    // Call original print
    __ipcOriginalPrint(...args);

    // Mirror to all CLI instances with console mirroring enabled
    const output = args.map(a => String(a)).join('\t') + '\n';

    for (const instanceID in __ipcRegisteredInstances) {
        const instance = __ipcRegisteredInstances[instanceID];
        if (instance._cli.console && instance._cli.remote) {
            try {
                instance._cli.remote.sendMessage(output, MSG_ID.CONSOLE, 4.0, true);
            } catch (e) {
                // Silently ignore errors in console mirroring
            }
        }
    }
};

// Create default port for CLI communication
// Stored in closure-scoped variable to survive JSExport proxy GC.
try {
    __ipcDefaultPort = hs.ipc.localPort("Hammerspoon2", __ipcDefaultHandler);
    if (!__ipcDefaultPort) {
        console.error("Failed to create default IPC port 'Hammerspoon2'");
    }
} catch (e) {
    console.error("Error creating default IPC port:", e);
}

// Tab completion function for REPL (minimal v1.0 implementation)
// Stored in closure-scoped variable to survive JSExport proxy GC.
// Known module names for tab completion.
// JSExport proxy properties are not enumerable via Object.keys() or for...in,
// so we maintain a static list matching ModuleRootAPI.
var __ipcKnownModules = [
    "appinfo", "application", "ax", "console", "fs", "hashing",
    "hotkey", "ipc", "permissions", "osascript", "screen", "task",
    "timer", "ui", "window"
];

var __ipcCompletionsForInputString = function(inputString) {
    // Complete hs.* module names
    if (inputString.startsWith("hs.")) {
        return __ipcKnownModules
            .map(function(m) { return "hs." + m; })
            .filter(function(c) { return c.startsWith(inputString); });
    }

    // Future enhancement: complete other globals, properties, methods
    return [];
};
// Expose completionsForInputString as a global function.
// This avoids assigning directly to the hs JSExport proxy,
// which would be lost when the GC reclaims the proxy wrapper.
var completionsForInputString = __ipcCompletionsForInputString;
