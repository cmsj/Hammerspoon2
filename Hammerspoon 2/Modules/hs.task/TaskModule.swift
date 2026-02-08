//
//  TaskModule.swift
//  Hammerspoon 2
//
//  Created by Claude on 03/02/2026.
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

// MARK: - Declare our JavaScript API

/// Module for running external processes
@objc protocol HSTaskModuleAPI: JSExport {
    /// Create a new task
    /// - Parameters:
    ///   - launchPath: The full path to the executable to run
    ///   - arguments: An array of arguments to pass to the executable
    ///   - completionCallback: Optional callback function called when the task terminates
    ///   - environment: Optional dictionary of environment variables for the task
    ///   - streamingCallback: Optional callback function called when the task produces output
    /// - Returns: A task object. Call start() to begin execution.
    @objc(new:::::)
    func new(_ launchPath: String, _ arguments: [String], _ completionCallback: JSValue?, _ environment: JSValue?, _ streamingCallback: JSValue?) -> HSTask
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

    @objc func new(_ launchPath: String, _ arguments: [String], _ completionCallback: JSValue? = nil, _ environment: JSValue? = nil, _ streamingCallback: JSValue? = nil) -> HSTask {
        // Parse environment dictionary if provided
        var envDict: [String: String]? = nil
        if let envValue = environment, envValue.isObject && !envValue.isFunction {
            envDict = envValue.toDictionary() as? [String: String]
        }

        let task = HSTask(
            launchPath: launchPath,
            arguments: arguments,
            environment: envDict,
            terminationCallback: completionCallback,
            streamingCallback: streamingCallback
        )

        tasks.append(task)
        return task
    }
}
