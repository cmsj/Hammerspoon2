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

// Storage for registered CLI instances
// Always clear instances on module load - forces re-registration after reload
// This is safe because hs.reload() destroys the entire JS context
hs.ipc.__registeredCLIInstances = {};
console.log("[IPC] Initialized __registeredCLIInstances (cleared any previous instances)");

// Store original print function
hs.ipc.__originalPrint = (typeof print !== 'undefined') ? print : console.log;

// Default message handler for IPC protocol
// DEFENSIVE: Wrapped in try-catch to ensure Hammerspoon never crashes from IPC errors
hs.ipc.__defaultHandler = function(port, msgID, data) {
    try {
        // DEFENSIVE: Ensure storage objects exist before processing any message
        // This prevents TypeError if objects become undefined during runtime
        if (!hs.ipc.__registeredCLIInstances) {
            console.log("[IPC] CRITICAL: __registeredCLIInstances was undefined, re-initializing");
            hs.ipc.__registeredCLIInstances = {};
        }
        if (!hs.ipc.__remotePorts) {
            console.log("[IPC] CRITICAL: __remotePorts was undefined, re-initializing");
            hs.ipc.__remotePorts = {};
        }
        console.log("[IPC] Storage check complete. Instances:", Object.keys(hs.ipc.__registeredCLIInstances).length, "RemotePorts:", hs.ipc.__remotePorts ? Object.keys(hs.ipc.__remotePorts).length : 0);

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
                console.error("[IPC] Failed to create remote port for instance:", instanceID);
                console.error("[IPC] Possible cause: macOS message port limit reached");
                console.error("[IPC] Suggestion: Add delays between rapid hs2 invocations");
                return "error: failed to create remote port - resource limit reached";
            }

            // Store remote port to prevent garbage collection
            // This is CRITICAL - without this, the remote port object gets deallocated
            // and causes crashes when callbacks try to access it
            if (!hs.ipc.__remotePorts) {
                hs.ipc.__remotePorts = {};
            }
            hs.ipc.__remotePorts[instanceID] = remote;

            // Create instance object with isolated _cli and print
            hs.ipc.__registeredCLIInstances[instanceID] = {
                _cli: {
                    remote: remote,
                    quietMode: quiet,
                    console: consoleMirroring,
                    args: customArgs
                },
                print: function(...args) {
                    console.log("[DEBUG] Instance print called for", instanceID, "args:", args);
                    // DEFENSIVE: Check if storage still exists (can be cleared on reload)
                    if (!hs.ipc.__registeredCLIInstances) {
                        console.log("[IPC] CRITICAL: __registeredCLIInstances undefined in instance.print() for", instanceID);
                        console.log("[IPC] WARNING: Print output lost - instance storage cleared (likely due to reload)");
                        return;
                    }

                    const instance = hs.ipc.__registeredCLIInstances[instanceID];
                    if (!instance) {
                        console.log("[DEBUG] Instance not found!");
                        return;
                    }
                    if (instance._cli.quietMode) {
                        console.log("[DEBUG] Quiet mode enabled, skipping");
                        return;
                    }

                    const output = args.map(a => String(a)).join('\t') + '\n';
                    console.log("[DEBUG] Sending message via remote port:", output);
                    instance._cli.remote.sendMessage(output, MSG_ID.OUTPUT, 4.0, true);  // oneWay=true to avoid deadlock
                    console.log("[DEBUG] Message sent");
                }
            };

            // Log instance counts
            const instanceCount = Object.keys(hs.ipc.__registeredCLIInstances).length;
            const remotePortCount = hs.ipc.__remotePorts ? Object.keys(hs.ipc.__remotePorts).length : 0;
            console.log("[IPC] REGISTER complete. Instances: " + instanceCount + ", RemotePorts: " + remotePortCount);

            return "ok";

        } else if (msgID === MSG_ID.UNREGISTER) {
            // UNREGISTER: instanceID
            const instanceID = data;

            // Defensive: Safe cleanup even if instance doesn't exist
            try {
                if (hs.ipc.__registeredCLIInstances && hs.ipc.__registeredCLIInstances[instanceID]) {
                    const instance = hs.ipc.__registeredCLIInstances[instanceID];
                    if (instance && instance._cli && instance._cli.remote) {
                        try {
                            instance._cli.remote.delete();
                        } catch (e) {
                            console.error("[IPC] Error deleting remote port:", e);
                        }
                    }
                    delete hs.ipc.__registeredCLIInstances[instanceID];
                }

                // Clean up remote port storage to prevent resource leak
                if (hs.ipc.__remotePorts && hs.ipc.__remotePorts[instanceID]) {
                    delete hs.ipc.__remotePorts[instanceID];
                }

                // Log instance counts after cleanup
                const instanceCount = hs.ipc.__registeredCLIInstances ? Object.keys(hs.ipc.__registeredCLIInstances).length : 0;
                const remotePortCount = hs.ipc.__remotePorts ? Object.keys(hs.ipc.__remotePorts).length : 0;
                console.log("[IPC] UNREGISTER complete. Instances: " + instanceCount + ", RemotePorts: " + remotePortCount);
            } catch (e) {
                console.error("[IPC] Error during UNREGISTER cleanup:", e);
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

            // DEFENSIVE: Verify storage object exists before accessing
            if (!hs.ipc.__registeredCLIInstances) {
                console.log("[IPC] CRITICAL: __registeredCLIInstances undefined during COMMAND/QUERY, re-initializing");
                hs.ipc.__registeredCLIInstances = {};
            }

            const instance = hs.ipc.__registeredCLIInstances[instanceID];
            if (!instance) {
                console.log("[IPC] ERROR: Instance", instanceID, "not registered. Storage object exists:", !!hs.ipc.__registeredCLIInstances);
                console.log("[IPC] ERROR: Registered instances:", hs.ipc.__registeredCLIInstances ? Object.keys(hs.ipc.__registeredCLIInstances) : 'undefined');
                return "error: instance not registered - client must reconnect";
            }

            console.log("[DEBUG] Executing code for instance", instanceID, ":", code);
            console.log("[DEBUG] Instance print function:", typeof instance.print);

            // Execute code with instance-specific _cli and print as parameters
            let result;
            let evalError = null;

            // Detect if code looks like a single expression vs multiple statements
            // If it contains semicolons (except in strings) or newlines, it's likely multi-statement
            const trimmedCode = code.trim();
            const hasStatements = trimmedCode.includes(';') || trimmedCode.includes('\n') ||
                                  trimmedCode.includes('{') || trimmedCode.includes('const ') ||
                                  trimmedCode.includes('let ') || trimmedCode.includes('var ');

            if (hasStatements) {
                console.log("[DEBUG] Multi-statement code detected, executing directly");
                // Execute directly without implicit return
                try {
                    const fn = new Function('_cli', 'print', code);
                    result = fn(instance._cli, instance.print);
                    console.log("[DEBUG] Success, result:", result);
                } catch (e) {
                    console.log("[DEBUG] Execution failed:", e);
                    evalError = e;
                }
            } else {
                console.log("[DEBUG] Single expression detected, trying with implicit return");
                // Try with implicit return for single expressions
                try {
                    const fn = new Function('_cli', 'print', 'return ' + code);
                    result = fn(instance._cli, instance.print);
                    console.log("[DEBUG] Success with implicit return, result:", result);
                } catch (e1) {
                    console.log("[DEBUG] Implicit return failed:", e1, "- trying without return");
                    // Try without return
                    try {
                        const fn = new Function('_cli', 'print', code);
                        result = fn(instance._cli, instance.print);
                        console.log("[DEBUG] Success without return, result:", result);
                    } catch (e2) {
                        console.log("[DEBUG] Both attempts failed:", e2);
                        evalError = e2;
                    }
                }
            }

            // Handle errors
            if (evalError) {
                try {
                    const errorMsg = String(evalError) + '\n';
                    instance._cli.remote.sendMessage(errorMsg, MSG_ID.ERROR, 4.0, true);  // oneWay=true
                } catch (e) {
                    console.error("[IPC] Failed to send error message to client:", e);
                }
                return "error";
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
                    console.error("[IPC] Failed to send result to client:", e);
                    return "error: send failed";
                }
                return "ok";
            } else {
                // For QUERY, return result directly
                try {
                    return (result !== undefined && result !== null) ? String(result) : "";
                } catch (e) {
                    console.error("[IPC] Failed to convert result to string:", e);
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

// Enhanced print() function that mirrors to all CLI instances with console mirroring enabled
hs.ipc.print = function(...args) {
    // Call original print
    hs.ipc.__originalPrint(...args);

    // DEFENSIVE: Ensure storage object exists before iterating
    if (!hs.ipc.__registeredCLIInstances) {
        console.log("[IPC] CRITICAL: __registeredCLIInstances undefined in hs.ipc.print(), re-initializing");
        console.log("[IPC] WARNING: Console mirroring skipped due to missing storage");
        hs.ipc.__registeredCLIInstances = {};
        // Cannot mirror to instances that don't exist, but we've recovered the object
        // Just call original print and return
        hs.ipc.__originalPrint(...args);
        return;
    }

    // Mirror to all CLI instances with console mirroring enabled
    const output = args.map(a => String(a)).join('\t') + '\n';

    for (const instanceID in hs.ipc.__registeredCLIInstances) {
        const instance = hs.ipc.__registeredCLIInstances[instanceID];
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
try {
    hs.ipc.__default = hs.ipc.localPort("Hammerspoon2", hs.ipc.__defaultHandler);
    if (!hs.ipc.__default) {
        console.error("Failed to create default IPC port 'Hammerspoon2'");
    }
} catch (e) {
    console.error("Error creating default IPC port:", e);
}

// Replace global print with IPC-aware version
if (typeof print !== 'undefined') {
    print = hs.ipc.print;
}

// Tab completion function for REPL (minimal v1.0 implementation)
hs.completionsForInputString = function(inputString) {
    const completions = [];

    // Complete hs.* module names
    if (inputString.startsWith("hs.")) {
        const prefix = "hs.";
        const modules = Object.keys(hs).filter(k => k !== "__proto__" && !k.startsWith("__"));
        const fullNames = modules.map(m => prefix + m);
        return fullNames.filter(c => c.startsWith(inputString));
    }

    // Future enhancement: complete other globals, properties, methods
    // For v1.0, only complete hs.* modules

    return completions;
};
