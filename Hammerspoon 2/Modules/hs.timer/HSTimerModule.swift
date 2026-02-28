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
    @objc func create(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimer

    /// Create a new timer (alias for create())
    /// - Parameters:
    ///   - interval: The interval in seconds at which the timer should fire
    ///   - callback: A JavaScript function to call when the timer fires
    ///   - continueOnError: If true, the timer will continue running even if the callback throws an error
    /// - Returns: A timer object. Call start() to begin the timer.
    @objc(new:::)
    func new(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimer

    /// Create and start a one-shot timer
    /// - Parameters:
    ///   - seconds: Number of seconds to wait before firing
    ///   - callback: A JavaScript function to call when the timer fires
    /// - Returns: A timer object (already started)
    @objc func doAfter(_ seconds: TimeInterval, _ callback: JSValue) -> HSTimer

    /// Create and start a repeating timer
    /// - Parameters:
    ///   - interval: The interval in seconds at which the timer should fire
    ///   - callback: A JavaScript function to call when the timer fires
    /// - Returns: A timer object (already started)
    @objc func doEvery(_ interval: TimeInterval, _ callback: JSValue) -> HSTimer

    /// Create and start a timer that fires at a specific time
    /// - Parameters:
    ///   - time: Seconds since midnight (local time) when the timer should first fire
    ///   - repeatInterval: If provided, the timer will repeat at this interval. Pass 0 for one-shot.
    ///   - callback: A JavaScript function to call when the timer fires
    ///   - continueOnError: If true, the timer will continue running even if the callback throws an error
    /// - Returns: A timer object (already started)
    @objc(doAt::::)
    func doAt(_ time: TimeInterval, _ repeatInterval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool) -> HSTimer

    /// Block execution for a specified number of microseconds (strongly discouraged)
    /// - Parameter microseconds: Number of microseconds to sleep
    /// - Note: This blocks the entire application and should be avoided. Use timers instead.
    @objc func usleep(_ microseconds: UInt32)

    /// Get the current time as seconds since the UNIX epoch with sub-second precision
    /// - Returns: Fractional seconds since midnight, January 1, 1970 UTC
    @objc func secondsSinceEpoch() -> TimeInterval

    /// Get the number of nanoseconds since the system was booted (excluding sleep time)
    /// - Returns: Nanoseconds since boot
    @objc func absoluteTime() -> UInt64

    /// Get the number of seconds since local midnight
    /// - Returns: Seconds since midnight in the local timezone
    @objc func localTime() -> TimeInterval

    /// Converts minutes to seconds
    /// - Parameter n: A number of minutes
    /// - Returns: The equivalent number of seconds
    @objc func minutes(_ n: Double) -> Double

    /// Converts hours to seconds
    /// - Parameter n: A number of hours
    /// - Returns: The equivalent number of seconds
    @objc func hours(_ n: Double) -> Double

    /// Converts days to seconds
    /// - Parameter n: A number of days
    /// - Returns: The equivalent number of seconds
    @objc func days(_ n: Double) -> Double

    /// Converts weeks to seconds
    /// - Parameter n: A number of weeks
    /// - Returns: The equivalent number of seconds
    @objc func weeks(_ n: Double) -> Double

    /// Repeat a function until a predicate returns true. Swift-retained storage for the JS implementation.
    @objc var doUntil: JSValue? { get set }

    /// Repeat a function while a predicate returns true. Swift-retained storage for the JS implementation.
    @objc var doWhile: JSValue? { get set }

    /// Wait to call a function until a predicate returns true. Swift-retained storage for the JS implementation.
    @objc var waitUntil: JSValue? { get set }

    /// Wait to call a function until a predicate returns false. Swift-retained storage for the JS implementation.
    @objc var waitWhile: JSValue? { get set }
}

// MARK: - Implementation

@_documentation(visibility: private)
@objc class HSTimerModule: NSObject, HSModuleAPI, HSTimerModuleAPI {
    var name = "hs.timer"

    // MARK: - Module lifecycle
    override required init() { super.init() }

    func shutdown() {
        // Timers clean themselves up in their deinit
    }

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Swift-retained storage for JS-defined functions
    @objc var doUntil: JSValue? = nil
    @objc var doWhile: JSValue? = nil
    @objc var waitUntil: JSValue? = nil
    @objc var waitWhile: JSValue? = nil

    // MARK: - Timer constructors

    @objc func create(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool = false) -> HSTimer {
        return HSTimer(interval: interval, repeats: true, callback: callback, continueOnError: continueOnError)
    }

    @objc(new:::)
    func new(_ interval: TimeInterval, _ callback: JSValue, _ continueOnError: Bool = false) -> HSTimer {
        return create(interval, callback, continueOnError)
    }

    @objc func doAfter(_ seconds: TimeInterval, _ callback: JSValue) -> HSTimer {
        let timer = HSTimer(interval: seconds, repeats: false, callback: callback)
        timer.start()
        return timer
    }

    @objc func doEvery(_ interval: TimeInterval, _ callback: JSValue) -> HSTimer {
        let timer = HSTimer(interval: interval, repeats: true, callback: callback)
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

        // Create initial one-shot timer to fire at the target time
        let timer = HSTimer(interval: secondsUntilTarget, repeats: false, callback: callback, continueOnError: continueOnError)

        // If repeatInterval is specified, we'll need to reschedule after each fire
        // This is handled in JavaScript for simplicity
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
