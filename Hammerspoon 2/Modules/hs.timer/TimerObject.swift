//
//  TimerObject.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

import Foundation
import JavaScriptCore

/// Object representing a timer
@objc protocol HSTimerObjectAPI: HSTypeAPI, JSExport {
    /// The timer's interval in seconds
    @objc var interval: TimeInterval { get }

    /// Whether the timer repeats
    @objc var repeats: Bool { get }

    /// Start the timer
    @objc func start()

    /// Stop the timer
    @objc func stop()

    /// Immediately fire the timer's callback
    @objc func fire()

    /// Check if the timer is currently running
    /// - Returns: true if the timer is running, false otherwise
    @objc func running() -> Bool

    /// Get the number of seconds until the timer next fires
    /// - Returns: Seconds until next trigger, or a negative value if the timer is not running
    @objc func nextTrigger() -> TimeInterval

    /// Set when the timer should next fire
    /// - Parameter seconds: Number of seconds from now when the timer should fire
    @objc func setNextTrigger(_ seconds: TimeInterval)
}

@_documentation(visibility: private)
@objc class HSTimerObject: NSObject, HSTimerObjectAPI {
    @objc var typeName = "HSTimer"
    private var timer: Timer?
    private let callback: JSValue
    private let continueOnError: Bool

    @objc let interval: TimeInterval
    @objc let repeats: Bool

    init(interval: TimeInterval, repeats: Bool, callback: JSValue, continueOnError: Bool = false) {
        self.interval = interval
        self.repeats = repeats
        self.callback = callback
        self.continueOnError = continueOnError
        super.init()
    }

    isolated deinit {
        timer?.invalidate()
        print("deinit of HSTimerObject: interval=\(interval), repeats=\(repeats)")
    }

    @objc func start() {
        // If already running, don't create a new timer
        if timer?.isValid == true {
            return
        }

        timer = Timer.scheduledTimer(timeInterval: interval,
                                     target: self,
                                     selector: #selector(timerDidFire),
                                     userInfo: nil,
                                     repeats: repeats)

        // Add to common run loop modes so timer fires during modal dialogs, etc.
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    @objc func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc func fire() {
        // Fire immediately, bypassing the timer
        timerDidFire()
    }

    @objc func running() -> Bool {
        return timer?.isValid ?? false
    }

    @objc func nextTrigger() -> TimeInterval {
        guard let timer = timer, timer.isValid else {
            return -1
        }

        let fireDate = timer.fireDate
        let now = Date()
        return fireDate.timeIntervalSince(now)
    }

    @objc func setNextTrigger(_ seconds: TimeInterval) {
        guard let timer = timer, timer.isValid else {
            AKWarning("hs.timer:setNextTrigger(): Timer is not running")
            return
        }

        let newFireDate = Date(timeIntervalSinceNow: seconds)
        timer.fireDate = newFireDate
        return
    }

    @objc private func timerDidFire() {
        // Check if callback is actually a function
        guard callback.isObject else {
            AKError("hs.timer: callback is not a function")
            if !continueOnError {
                stop()
            }
            return
        }

        // Call the callback
        callback.call(withArguments: [])

        // Check for JavaScript errors
        if let context = callback.context,
           let exception = context.exception,
           !exception.isUndefined {
            AKError("hs.timer: Error in callback: \(exception.toString() ?? "unknown error")")

            // Clear the exception
            context.exception = nil

            // Stop the timer if we're not supposed to continue on error
            if !continueOnError {
                stop()
            }
        }

        // For one-shot timers, clean up after firing
        if !repeats {
            timer = nil
        }
    }
}
