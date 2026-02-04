//
//  TaskModule.swift
//  Hammerspoon 2
//
//  Created by Claude on 03/02/2026.
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

/// Module for running external processes
@objc protocol HSTaskModuleAPI: JSExport {
    /// Create a new task
    /// - Parameters:
    ///   - launchPath: The full path to the executable to run
    ///   - arguments: An array of arguments to pass to the executable
    ///   - callbackOrEnvironment: Either a callback function or an environment dictionary
    ///   - streamCallbackOrEnvironment: Either a streaming callback function or an environment dictionary (if first param was a callback)
    ///   - streamCallback: Optional streaming callback when environment is provided as third parameter
    /// - Returns: A task object. Call start() to begin execution.
    /// - Note: This function has flexible arguments to support both old and new API styles:
    ///   - new(path, args, callback) - Simple callback when task completes
    ///   - new(path, args, callback, streamCallback) - Callback for completion and streaming output
    ///   - new(path, args, environment, callback) - Environment variables and callback
    ///   - new(path, args, environment, callback, streamCallback) - Full control
    @objc(new:::::)
    func new(_ launchPath: String, _ arguments: [String], _ callbackOrEnvironment: JSValue?, _ streamCallbackOrEnvironment: JSValue?, _ streamCallback: JSValue?) -> HSTask
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSTaskModule: NSObject, HSModuleAPI, HSTaskModuleAPI {
    var name = "hs.task"

    // Keep track of all running tasks
    private var tasks: [HSTask] = []

    // MARK: - Module lifecycle
    override required init() { super.init() }

    func shutdown() {
        // Terminate all running tasks
        for task in tasks {
            if task.isRunning() {
                task.terminate()
            }
        }
        tasks.removeAll()
    }

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Task constructors

    @objc func new(_ launchPath: String, _ arguments: [String], _ callbackOrEnvironment: JSValue? = nil, _ streamCallbackOrEnvironment: JSValue? = nil, _ streamCallback: JSValue? = nil) -> HSTask {
        var environment: [String: String]? = nil
        var terminationCallback: JSValue? = nil
        var streamingCallback: JSValue? = nil

        // Parse the flexible arguments
        // If callbackOrEnvironment is a dictionary, it's the environment
        if let callbackOrEnv = callbackOrEnvironment {
            if callbackOrEnv.isObject && !callbackOrEnv.isFunction {
                // It's a dictionary (environment)
                if let envDict = callbackOrEnv.toDictionary() as? [String: String] {
                    environment = envDict
                }
                // The termination callback is the next parameter
                terminationCallback = streamCallbackOrEnvironment
                // The streaming callback is the 5th parameter
                streamingCallback = streamCallback
            } else if callbackOrEnv.isFunction {
                // It's the termination callback
                terminationCallback = callbackOrEnv
                // Check if streamCallbackOrEnvironment is also a function (streaming callback)
                if let streamOrEnv = streamCallbackOrEnvironment {
                    if streamOrEnv.isFunction {
                        streamingCallback = streamOrEnv
                    }
                }
            }
        }

        let task = HSTask(
            launchPath: launchPath,
            arguments: arguments,
            environment: environment,
            terminationCallback: terminationCallback,
            streamingCallback: streamingCallback
        )

        tasks.append(task)
        return task
    }
}
