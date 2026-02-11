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

// Actor to safely track active tasks across threads
private actor TaskTracker {
    private var activeTasks = Set<ObjectIdentifier>()

    func register(_ task: HSTask) {
        activeTasks.insert(ObjectIdentifier(task))
    }

    func unregister(_ task: HSTask) {
        activeTasks.remove(ObjectIdentifier(task))
    }

    func count() -> Int {
        return activeTasks.count
    }

    func clear() {
        activeTasks.removeAll()
    }
}

@_documentation(visibility: private)
@objc class HSTaskModule: NSObject, HSModuleAPI, HSTaskModuleAPI {
    var name = "hs.task"

    // Keep weak references to tasks for shutdown cleanup
    // Uses weak references to allow JavaScript garbage collection
    // Running tasks stay alive via their Process termination handler closure
    private var tasks = NSHashTable<HSTask>.weakObjects()

    // Track active tasks for testing purposes (thread-safe via actor)
    private let taskTracker = TaskTracker()

    // MARK: - Module lifecycle
    override required init() { super.init() }

    func shutdown() {
        // Terminate all running tasks that still exist
        for task in tasks.allObjects.filter({ $0.isRunning }) {
            task._shutdown()
        }
        tasks.removeAllObjects()

        Task {
            await taskTracker.clear()
        }
    }

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Task Tracking (for testing)

    func registerActiveTask(_ task: HSTask) {
        Task {
            await taskTracker.register(task)
        }
    }

    func unregisterActiveTask(_ task: HSTask) {
        Task {
            await taskTracker.unregister(task)
        }
    }

    @MainActor
    func waitForAllTasksToComplete(timeout: TimeInterval = 5.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let count = await taskTracker.count()

            if count == 0 {
                return true
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return false
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
            streamingCallback: streamingCallback,
            module: self
        )

        tasks.add(task)
        return task
    }
}
