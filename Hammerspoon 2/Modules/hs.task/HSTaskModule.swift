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
    ///   - onTermination: {((exitCode: number, exitReason: string) => void) | null} Optional callback called when the task terminates with exit code and reason
    ///   - environment: Optional dictionary of environment variables for the task
    ///   - onOutput: {((stream: string, data: string) => void) | null} Optional callback called when the task produces output; stream is "stdout" or "stderr"
    /// - Returns: A task object. Call start() to begin execution.
    /// - Example:
    /// ```js
    /// const task = hs.task.create("/usr/bin/env", ["printenv", "PATH"], (code, reason) => {
    ///     console.log("exited", code)
    /// })
    /// task.start()
    /// ```
    @objc(create:::::)
    func create(_ launchPath: String, _ arguments: [String], _ onTermination: JSFunction?, _ environment: [String: String]?, _ onOutput: JSFunction?) -> HSTask

    /// SKIP_DOCS
    @objc var runAsync: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var shell: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var parallel: JSFunction? { get set }

    /// Run multiple tasks in sequence. Swift-retained storage for the JS implementation.
    /// - Example:
    /// ```js
    /// hs.task.sequence([
    ///     ["/bin/echo", ["one"]],
    ///     ["/bin/echo", ["two"]]
    /// ]).then(results => console.log(results))
    /// ```
    @objc var sequence: JSFunction? { get set }

    /// SKIP_DOCS
    @objc var builder: JSFunction? { get set }

    /// TaskBuilder class. Swift-retained storage for the JS implementation.
    /// - Example:
    /// ```js
    /// const b = new hs.task.TaskBuilder().launchPath("/bin/echo")
    /// ```
    @objc var TaskBuilder: JSFunction? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSTaskModule: NSObject, HSModuleAPI, HSTaskModuleAPI {
    var moduleName = "hs.task"
    let engineID: UUID

    // Running tasks are kept alive by the tracker while active; completed/never-started tasks
    // are ordinary garbage once JS drops them.
    private var tasks = HSObjectTracker<HSTask>()

    // Swift-retained storage for JS-defined functions
    @objc var runAsync: JSFunction? = nil
    @objc var shell: JSFunction? = nil
    @objc var parallel: JSFunction? = nil
    @objc var sequence: JSFunction? = nil
    @objc var builder: JSFunction? = nil
    @objc var TaskBuilder: JSFunction? = nil

    // MARK: - Module lifecycle
    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        for task in tasks.allObjects {
            task.destroy()
        }
        tasks.removeAllObjects()
        runAsync = nil
        shell = nil
        parallel = nil
        sequence = nil
        builder = nil
        TaskBuilder = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        let n = tasks.activeCount
        return "<\(moduleName): \(n) running task\(n == 1 ? "" : "s")>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Task Tracking (for testing)

    @MainActor
    func waitForAllTasksToComplete(timeout: TimeInterval = 5.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if tasks.activeCount == 0 {
                return true
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return false
    }

    // MARK: - Task constructors

    @objc func create(_ launchPath: String, _ arguments: [String], _ onTermination: JSFunction? = nil, _ environment: [String: String]? = nil, _ onOutput: JSFunction? = nil) -> HSTask {

        let task = HSTask(
            launchPath: launchPath,
            arguments: arguments,
            environment: environment,
            onTermination: onTermination,
            onOutput: onOutput,
            tracker: tasks
        )

        tasks.add(task)
        return task
    }
}
