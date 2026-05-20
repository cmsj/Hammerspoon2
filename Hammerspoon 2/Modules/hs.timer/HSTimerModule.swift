//
//  TimerModule.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 06/11/2025.
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

/// Module for creating and managing timers
@objc protocol HSTimerModuleAPI: JSExport {
    /// Create a new timer
    /// - Parameters:
    ///   - interval: The interval in seconds at which the timer should fire
    ///   - callback: A JavaScript function to call when the timer fires
    ///   - continueOnError: If true, the timer will continue running even if the callback throws an error
    /// - Returns: A timer object. Call start() to begin the timer.
    /// - Example:
    /// ```js
    /// const t = hs.timer.create(5, () => console.log("tick"), false)
    /// t.start()
    /// ```
    @objc func create(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimer

    /// Create a new timer (alias for create())
    /// - Parameters:
    ///   - interval: The interval in seconds at which the timer should fire
    ///   - callback: A JavaScript function to call when the timer fires
    ///   - continueOnError: If true, the timer will continue running even if the callback throws an error
    /// - Returns: A timer object. Call start() to begin the timer.
    /// - Example:
    /// ```js
    /// const t = hs.timer.new(5, () => console.log("tick"), false)
    /// t.start()
    /// ```
    @objc(new:::)
    func new(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimer

    /// Create and start a one-shot timer
    /// - Parameters:
    ///   - seconds: Number of seconds to wait before firing
    ///   - callback: A JavaScript function to call when the timer fires
    /// - Returns: A timer object (already started)
    /// - Example:
    /// ```js
    /// hs.timer.doAfter(5, () => console.log("fired"))
    /// ```
    @objc func doAfter(_ seconds: TimeInterval, _ callback: JSValue) -> HSTimer

    /// Create and start a repeating timer
    /// - Parameters:
    ///   - interval: The interval in seconds at which the timer should fire
    ///   - callback: A JavaScript function to call when the timer fires
    /// - Returns: A timer object (already started)
    /// - Example:
    /// ```js
    /// hs.timer.doEvery(60, () => console.log("every minute"))
    /// ```
    @objc func doEvery(_ interval: TimeInterval, _ callback: JSValue) -> HSTimer

    /// Create and start a timer that fires at a specific time
    /// - Parameters:
    ///   - time: Seconds since midnight (local time) when the timer should first fire
    ///   - repeatInterval: If provided, the timer will repeat at this interval. Pass 0 for one-shot.
    ///   - callback: A JavaScript function to call when the timer fires
    ///   - continueOnError: If true, the timer will continue running even if the callback throws an error
    /// - Returns: A timer object (already started)
    /// - Example:
    /// ```js
    /// // Fire at 9am every day
    /// hs.timer.doAt(9 * 3600, 86400, () => console.log("morning"), false)
    /// ```
    @objc(doAt::::)
    func doAt(_ time: TimeInterval, _ repeatInterval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimer

    /// Block execution for a specified number of microseconds (strongly discouraged)
    /// - Parameter microseconds: Number of microseconds to sleep
    /// - Note: This blocks the entire application and should be avoided. Use timers instead.
    /// - Example:
    /// ```js
    /// hs.timer.usleep(100000)  // 100ms
    /// ```
    @objc func usleep(_ microseconds: UInt32)

    /// Get the current time as seconds since the UNIX epoch with sub-second precision
    /// - Returns: Fractional seconds since midnight, January 1, 1970 UTC
    /// - Example:
    /// ```js
    /// console.log(hs.timer.secondsSinceEpoch())
    /// ```
    @objc func secondsSinceEpoch() -> TimeInterval

    /// Get the number of nanoseconds since the system was booted (excluding sleep time)
    /// - Returns: Nanoseconds since boot
    /// - Example:
    /// ```js
    /// console.log(hs.timer.absoluteTime())
    /// ```
    @objc func absoluteTime() -> UInt64

    /// Get the number of seconds since local midnight
    /// - Returns: Seconds since midnight in the local timezone
    /// - Example:
    /// ```js
    /// console.log(hs.timer.localTime())
    /// ```
    @objc func localTime() -> TimeInterval

    /// Converts minutes to seconds
    /// - Parameter n: A number of minutes
    /// - Returns: The equivalent number of seconds
    /// - Example:
    /// ```js
    /// console.log(hs.timer.minutes(5))  // 300
    /// ```
    @objc func minutes(_ n: Double) -> Double

    /// Converts hours to seconds
    /// - Parameter n: A number of hours
    /// - Returns: The equivalent number of seconds
    /// - Example:
    /// ```js
    /// console.log(hs.timer.hours(2))  // 7200
    /// ```
    @objc func hours(_ n: Double) -> Double

    /// Converts days to seconds
    /// - Parameter n: A number of days
    /// - Returns: The equivalent number of seconds
    /// - Example:
    /// ```js
    /// console.log(hs.timer.days(1))  // 86400
    /// ```
    @objc func days(_ n: Double) -> Double

    /// Converts weeks to seconds
    /// - Parameter n: A number of weeks
    /// - Returns: The equivalent number of seconds
    /// - Example:
    /// ```js
    /// console.log(hs.timer.weeks(1))  // 604800
    /// ```
    @objc func weeks(_ n: Double) -> Double

    /// Repeat a function until a predicate returns true. Swift-retained storage for the JS implementation.
    /// - Example:
    /// ```js
    /// let count = 0
    /// hs.timer.doUntil(() => count >= 3, () => { count++; console.log(count) }, 1)
    /// ```
    @objc var doUntil: JSValue? { get set }

    /// Repeat a function while a predicate returns true. Swift-retained storage for the JS implementation.
    /// - Example:
    /// ```js
    /// let count = 0
    /// hs.timer.doWhile(() => count < 3, () => { count++; console.log(count) }, 1)
    /// ```
    @objc var doWhile: JSValue? { get set }

    /// Wait to call a function until a predicate returns true. Swift-retained storage for the JS implementation.
    /// - Example:
    /// ```js
    /// hs.timer.waitUntil(() => someCondition, () => console.log("ready"), 0.5)
    /// ```
    @objc var waitUntil: JSValue? { get set }

    /// Wait to call a function until a predicate returns false. Swift-retained storage for the JS implementation.
    /// - Example:
    /// ```js
    /// hs.timer.waitWhile(() => stillLoading, () => console.log("done"), 0.5)
    /// ```
    @objc var waitWhile: JSValue? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSTimerModule: NSObject, HSModuleAPI, HSTimerModuleAPI {
    var name = "hs.timer"
    let engineID: UUID

    // Weak refs: running timers stay alive via the Foundation run loop (Timer target);
    // stopped/GC'd timers are automatically zeroed. allObjects only returns live timers.
    private var timers = HSWeakObjectSet<HSTimer>()

    // MARK: - Module lifecycle
    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for timer in timers.allObjects {
            timer.stop()
        }
        timers.removeAllObjects()
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    // MARK: - Swift-retained storage for JS-defined functions
    @objc var doUntil: JSValue? = nil
    @objc var doWhile: JSValue? = nil
    @objc var waitUntil: JSValue? = nil
    @objc var waitWhile: JSValue? = nil

    // MARK: - Timer constructors

    @objc func create(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool = false) -> HSTimer {
        let timer = HSTimer(interval: interval, repeats: true, callback: callback, continueOnError: continueOnError)
        timers.add(timer)
        return timer
    }

    @objc(new:::)
    func new(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool = false) -> HSTimer {
        return create(interval, callback, continueOnError)
    }

    @objc func doAfter(_ seconds: TimeInterval, _ callback: JSValue) -> HSTimer {
        let timer = HSTimer(interval: seconds, repeats: false, callback: callback)
        timers.add(timer)
        timer.start()
        return timer
    }

    @objc func doEvery(_ interval: TimeInterval, _ callback: JSValue) -> HSTimer {
        let timer = HSTimer(interval: interval, repeats: true, callback: callback)
        timers.add(timer)
        timer.start()
        return timer
    }

    @objc func doAt(_ time: TimeInterval, _ repeatInterval: TimeInterval = 0, _ callback: JSValue, _ continueOnError: Bool = false) -> HSTimer {
        // Calculate seconds until target time (time is seconds since midnight)
        let now = localTime()
        var secondsUntilTarget = time - now

        // If the target time has passed today, schedule for tomorrow
        if secondsUntilTarget < 0 {
            secondsUntilTarget += 86400 // Add 24 hours
        }

        let timer = HSTimer(interval: secondsUntilTarget, repeats: false, callback: callback, continueOnError: continueOnError)
        timers.add(timer)
        timer.start()
        return timer
    }

    // MARK: - Time conversion utilities

    @objc func minutes(_ n: Double) -> Double { return n * 60 }
    @objc func hours(_ n: Double) -> Double { return n * 3600 }
    @objc func days(_ n: Double) -> Double { return n * 86400 }
    @objc func weeks(_ n: Double) -> Double { return n * 604800 }

    // MARK: - Utility functions

    @objc func usleep(_ microseconds: UInt32) {
        Foundation.usleep(microseconds)
    }

    @objc func secondsSinceEpoch() -> TimeInterval {
        return Date().timeIntervalSince1970
    }

    @objc func absoluteTime() -> UInt64 {
        var info = mach_timebase_info_data_t()
        unsafe mach_timebase_info(&info)

        let currentTime = mach_absolute_time()
        let nanos = currentTime * UInt64(info.numer) / UInt64(info.denom)
        return nanos
    }

    @objc func localTime() -> TimeInterval {
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        return now.timeIntervalSince(midnight)
    }
}
