//
//  HSPowerModule.swift
//  Hammerspoon 2
//

import AppKit
import Foundation
import JavaScriptCore
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Module API protocol

/// Monitor and control system power: prevent sleep, read battery state, respond to
/// power events, and lock or sleep the machine.
///
/// ## Preventing sleep
///
/// ```js
/// // Prevent the display from sleeping while a task runs
/// hs.power.preventSleep("display")
/// // ... do work ...
/// hs.power.allowSleep("display")
/// ```
///
/// ## Watching for system events
///
/// ```js
/// hs.power.addEventWatcher(event => {
///     if (event === "screensDidLock") console.log("Screen locked!")
/// })
/// ```
///
/// ## Reading battery state
///
/// ```js
/// const info = hs.power.batteryInfo()
/// if (info) {
///     console.log(`Battery: ${info.percentage}%, ${info.timeRemaining} minutes remaining`)
/// }
/// ```
@objc protocol HSPowerModuleAPI: JSExport {

    // MARK: Sleep Prevention

    /// Prevents the specified type of system sleep.
    ///
    /// Creates an IOKit power assertion that stops macOS from allowing the specified
    /// type of sleep. Call `allowSleep` with the same type to release the assertion.
    /// - Parameter type: The sleep type to prevent. One of: `"display"` (prevent display
    ///   idle sleep), `"systemIdle"` (prevent system idle sleep), `"system"` (prevent
    ///   all system sleep, including from power button or lid close).
    /// - Returns: `true` if the assertion was created successfully.
    /// - Example:
    ///   ```js
    ///   hs.power.preventSleep("display")
    ///   ```
    func preventSleep(_ type: String) -> Bool

    /// Releases a previously created sleep prevention assertion.
    ///
    /// - Parameter type: The sleep type to allow again. One of: `"display"`, `"systemIdle"`, `"system"`.
    /// - Returns: `true` if an assertion existed and was released, `false` if none was active.
    /// - Example:
    ///   ```js
    ///   hs.power.allowSleep("display")
    ///   ```
    func allowSleep(_ type: String) -> Bool

    /// Returns whether Hammerspoon is currently preventing the specified type of sleep.
    ///
    /// - Parameter type: The sleep type to check. One of: `"display"`, `"systemIdle"`, `"system"`.
    /// - Returns: `true` if this sleep type is currently being prevented.
    /// - Example:
    ///   ```js
    ///   if (hs.power.isSleepPrevented("display")) console.log("display sleep is prevented")
    ///   ```
    func isSleepPrevented(_ type: String) -> Bool

    /// Simulates user activity, briefly resetting the display idle timer.
    ///
    /// Equivalent to moving the mouse — does not create a persistent assertion.
    /// - Example:
    ///   ```js
    ///   hs.power.declareActivity()
    ///   ```
    func declareActivity()

    /// Returns the active power management assertions from all processes on the system.
    ///
    /// - Returns: An array of objects with `pid` (number), `name` (string), and `type` (string) properties.
    /// - Example:
    ///   ```js
    ///   hs.power.currentAssertions().forEach(a => console.log(a.pid + " " + a.name))
    ///   ```
    func currentAssertions() -> [[String: Any]]

    // MARK: System Actions

    /// Puts the system to sleep immediately.
    ///
    /// Requires the Automation permission for System Events.
    /// - Example:
    ///   ```js
    ///   hs.power.systemSleep()
    ///   ```
    func systemSleep()

    /// Locks the screen immediately.
    ///
    /// - Example:
    ///   ```js
    ///   hs.power.lockScreen()
    ///   ```
    func lockScreen()

    /// Starts the screensaver immediately.
    ///
    /// - Example:
    ///   ```js
    ///   hs.power.startScreensaver()
    ///   ```
    func startScreensaver()

    // MARK: Battery & Power State

    /// The current battery charge percentage (0–100), or `-1` if no battery is present.
    ///
    /// - Example:
    ///   ```js
    ///   console.log("Battery:" + hs.power.percentage + "%")
    ///   ```
    var percentage: Int { get }

    /// Whether the battery is currently charging.
    ///
    /// Returns `false` when no battery is present.
    /// - Example:
    ///   ```js
    ///   if (hs.power.isCharging) console.log("Charging")
    ///   ```
    var isCharging: Bool { get }

    /// The current power source.
    ///
    /// Returns `"ac"` when plugged in, `"battery"` when on battery power, `"ups"` when
    /// powered by a UPS, or `"unknown"` if the source cannot be determined.
    /// - Example:
    ///   ```js
    ///   if (hs.power.powerSource === "battery") console.log("Running on battery")
    ///   ```
    var powerSource: String { get }

    /// Whether Low Power Mode is currently active.
    ///
    /// - Example:
    ///   ```js
    ///   if (hs.power.isLowPowerMode) console.log("Low power mode active")
    ///   ```
    var isLowPowerMode: Bool { get }

    /// The current thermal state of the system.
    ///
    /// Returns one of: `"nominal"`, `"fair"`, `"serious"`, `"critical"`.
    /// - Example:
    ///   ```js
    ///   console.log("Thermal state: " + hs.power.thermalState)
    ///   ```
    var thermalState: String { get }

    /// Returns a snapshot of all available battery information, or `null` if no battery is present.
    ///
    /// The returned object contains (values may be `null` if unavailable on the current hardware):
    /// - `percentage` — charge level 0–100
    /// - `isCharging` — whether charging
    /// - `isCharged` — whether fully charged
    /// - `source` — `"ac"`, `"battery"`, `"ups"`, or `"unknown"`
    /// - `health` — health string, e.g. `"Good"`
    /// - `healthCondition` — health condition detail, or `null`
    /// - `cycleCount` — charge cycle count
    /// - `capacity` — current capacity in mAh
    /// - `maxCapacity` — current maximum capacity in mAh
    /// - `designCapacity` — original design capacity in mAh
    /// - `voltage` — voltage in millivolts
    /// - `amperage` — current in milliamps (negative when discharging)
    /// - `watts` — power in watts (negative when discharging)
    /// - `temperature` — temperature in °C
    /// - `timeRemaining` — estimated minutes remaining, or `null` if calculating
    /// - `timeToFullCharge` — estimated minutes to full charge, or `null` if not applicable
    /// - `serial` — battery serial number
    /// - Returns: An object with battery fields, or `null` if no battery is present.
    /// - Example:
    ///   ```js
    ///   const info = hs.power.batteryInfo()
    ///   if (info) console.log(`${info.percentage}% — ${info.timeRemaining}m remaining`)
    ///   ```
    func batteryInfo() -> [String: Any]?

    // MARK: Event Watcher (Pattern A)

    /// Registers a listener that fires when system power events occur.
    ///
    /// The listener receives a single string identifying the event. Possible values:
    /// `"screensDidSleep"`, `"screensDidWake"`, `"screensDidLock"`, `"screensDidUnlock"`,
    /// `"screensaverDidStart"`, `"screensaverDidStop"`, `"screensaverWillStop"`,
    /// `"systemWillSleep"`, `"systemDidWake"`, `"systemWillPowerOff"`,
    /// `"sessionDidBecomeActive"`, `"sessionDidResignActive"`.
    ///
    /// The OS notification subscription starts lazily on the first listener and
    /// is released automatically when the last listener is removed.
    /// - Parameter listener: {(eventName: string) => void} A function called with the power event name string.
    /// - Example:
    ///   ```js
    ///   hs.power.addEventWatcher(event => console.log("Power event: " + event))
    ///   ```
    func addEventWatcher(_ listener: JSFunction)

    /// Removes a previously registered power event listener.
    ///
    /// - Parameter listener: The function originally passed to `addEventWatcher`.
    /// - Example:
    ///   ```js
    ///   const handler = event => console.log(event)
    ///   hs.power.addEventWatcher(handler)
    ///   hs.power.removeEventWatcher(handler)
    ///   ```
    func removeEventWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addEventWatcher:) func _addEventWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeEventWatcher()
    /// SKIP_DOCS
    @objc var _eventWatcherEmitter: JSFunction? { get set }

    // MARK: Battery Watcher (Pattern A)

    /// Registers a listener that fires whenever battery state changes.
    ///
    /// The listener receives no arguments; call `batteryInfo()` or read individual
    /// properties inside the callback to determine what changed.
    ///
    /// The OS notification subscription starts lazily on the first listener and
    /// is released automatically when the last listener is removed.
    /// - Parameter listener: {() => void} A function called with no arguments on battery state change.
    /// - Example:
    ///   ```js
    ///   hs.power.addBatteryWatcher(() => {
    ///       console.log("Battery now: " + hs.power.percentage + "%")
    ///   })
    ///   ```
    func addBatteryWatcher(_ listener: JSFunction)

    /// Removes a previously registered battery change listener.
    ///
    /// - Parameter listener: The function originally passed to `addBatteryWatcher`.
    /// - Example:
    ///   ```js
    ///   const handler = () => console.log("battery changed")
    ///   hs.power.addBatteryWatcher(handler)
    ///   hs.power.removeBatteryWatcher(handler)
    ///   ```
    func removeBatteryWatcher(_ listener: JSFunction)

    /// SKIP_DOCS
    @objc(_addBatteryWatcher:) func _addBatteryWatcher(_ callback: JSFunction)
    /// SKIP_DOCS
    @objc func _removeBatteryWatcher()
    /// SKIP_DOCS
    @objc var _batteryWatcherEmitter: JSFunction? { get set }
}

// MARK: - Module implementation

@safe @_documentation(visibility: private)
@MainActor
@objc class HSPowerModule: NSObject, HSModuleAPI, HSPowerModuleAPI {
    var name = "hs.power"
    let engineID: UUID

    private var sleepAssertions: [String: IOPMAssertionID] = [:]

    @objc var _eventWatcherEmitter: JSFunction? = nil
    private var eventWatcherCallback: JSFunction?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    @objc var _batteryWatcherEmitter: JSFunction? = nil
    private var batteryWatcherCallback: JSFunction?
    private var batteryRunLoopSource: CFRunLoopSource?
    private var batteryContextPointer: UnsafeMutableRawPointer?

    private static let workspaceEvents: [(NSNotification.Name, String)] = [
        (NSWorkspace.screensDidSleepNotification,        "screensDidSleep"),
        (NSWorkspace.screensDidWakeNotification,         "screensDidWake"),
        (NSWorkspace.willSleepNotification,              "systemWillSleep"),
        (NSWorkspace.didWakeNotification,                "systemDidWake"),
        (NSWorkspace.willPowerOffNotification,           "systemWillPowerOff"),
        (NSWorkspace.sessionDidBecomeActiveNotification, "sessionDidBecomeActive"),
        (NSWorkspace.sessionDidResignActiveNotification, "sessionDidResignActive"),
    ]

    private static let distributedEvents: [(String, String)] = [
        ("com.apple.screensaver.didstart", "screensaverDidStart"),
        ("com.apple.screensaver.didstop",  "screensaverDidStop"),
        ("com.apple.screensaver.willstop", "screensaverWillStop"),
        ("com.apple.screenIsLocked",       "screensDidLock"),
        ("com.apple.screenIsUnlocked",     "screensDidUnlock"),
    ]

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKDebug("Init of \(name): \(engineID)")
    }

    func shutdown() {
        for type in Array(sleepAssertions.keys) {
            _ = allowSleep(type)
        }
        _removeEventWatcher()
        _removeBatteryWatcher()
        _eventWatcherEmitter = nil
        _batteryWatcherEmitter = nil
    }

    isolated deinit {
        AKDebug("Deinit of \(name): \(engineID)")
    }

    // MARK: - Sleep Prevention

    func preventSleep(_ type: String) -> Bool {
        guard sleepAssertions[type] == nil else { return true }

        let assertionType: CFString
        switch type {
        case "display":
            assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case "systemIdle":
            assertionType = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case "system":
            assertionType = kIOPMAssertionTypePreventSystemSleep as CFString
        default:
            AKWarning("hs.power.preventSleep: unknown type '\(type)' — use 'display', 'systemIdle', or 'system'")
            return false
        }

        var assertionID: IOPMAssertionID = 0
        let result = unsafe IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Hammerspoon 2" as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            AKError("hs.power.preventSleep(\(type)): IOPMAssertionCreateWithName failed (\(result))")
            return false
        }

        sleepAssertions[type] = assertionID
        AKTrace("hs.power.preventSleep(\(type)): assertion \(assertionID) created")
        return true
    }

    func allowSleep(_ type: String) -> Bool {
        guard let assertionID = sleepAssertions[type] else { return false }

        let result = IOPMAssertionRelease(assertionID)

        if result != kIOReturnSuccess {
            AKError("hs.power.allowSleep(\(type)): IOPMAssertionRelease failed (\(result))")
            return false
        }

        sleepAssertions.removeValue(forKey: type)
        AKTrace("hs.power.allowSleep(\(type)): assertion \(assertionID) released")
        return true
    }

    func isSleepPrevented(_ type: String) -> Bool {
        return sleepAssertions[type] != nil
    }

    func declareActivity() {
        var assertionID: IOPMAssertionID = 0
        _ = unsafe IOPMAssertionDeclareUserActivity(
            "Hammerspoon 2" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
    }

    func currentAssertions() -> [[String: Any]] {
        var ref: Unmanaged<CFDictionary>?
        guard unsafe IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess,
              let dict = unsafe ref?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return []
        }

        var result: [[String: Any]] = []
        for (pid, list) in dict {
            for entry in list {
                var item: [String: Any] = ["pid": pid.intValue]
                if let n = entry["AssertName"] as? String { item["name"] = n }
                if let t = entry["AssertType"] as? String { item["type"] = t }
                result.append(item)
            }
        }
        return result
    }

    // MARK: - System Actions

    func systemSleep() {
        let script = NSAppleScript(source: #"tell application "System Events" to sleep"#)
        var error: NSDictionary?
        unsafe script?.executeAndReturnError(&error)
        if let error {
            AKError("hs.power.systemSleep: \(error)")
        }
    }

    func lockScreen() {
        let cgSession = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cgSession)
        process.arguments = ["-suspend"]
        do {
            try process.run()
            AKTrace("hs.power.lockScreen: CGSession -suspend launched")
        } catch {
            AKError("hs.power.lockScreen: failed to launch CGSession: \(error)")
        }
    }

    func startScreensaver() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        )
        AKTrace("hs.power.startScreensaver: ScreenSaverEngine opened")
    }

    // MARK: - Battery & Power State

    var percentage: Int {
        return batteryRegistryProperties()?["CurrentCapacity"] as? Int ?? -1
    }

    var isCharging: Bool {
        return batteryRegistryProperties()?["IsCharging"] as? Bool ?? false
    }

    var powerSource: String {
        return resolvePowerSource()
    }

    var isLowPowerMode: Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:        return "nominal"
        case .fair:           return "fair"
        case .serious:        return "serious"
        case .critical:       return "critical"
        @unknown default:     return "nominal"
        }
    }

    func batteryInfo() -> [String: Any]? {
        guard let props = batteryRegistryProperties() else { return nil }

        var info: [String: Any] = [:]
        info["percentage"] = props["CurrentCapacity"] as? Int ?? -1
        info["isCharging"] = props["IsCharging"] as? Bool ?? false
        info["isCharged"]  = props["FullyCharged"] as? Bool ?? false

        // Read power source info once for both source and health data
        if let blob = unsafe IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            info["source"] = resolvePowerSource(from: blob)

            let sourcesRef = unsafe IOPSCopyPowerSourcesList(blob).takeRetainedValue() as NSArray
            if let source = sourcesRef.firstObject,
               let desc = unsafe IOPSGetPowerSourceDescription(blob, source as AnyObject)?
                            .takeUnretainedValue() as? [String: Any] {
                info["health"]          = desc["BatteryHealth"] as? String ?? "Unknown"
                info["healthCondition"] = desc["BatteryHealthCondition"] ?? NSNull()
            } else {
                info["health"]          = "Unknown"
                info["healthCondition"] = NSNull()
            }
        } else {
            info["source"]          = "unknown"
            info["health"]          = "Unknown"
            info["healthCondition"] = NSNull()
        }

        info["cycleCount"]     = props["CycleCount"]              as? Int ?? NSNull()
        info["capacity"]       = props["AppleRawCurrentCapacity"] as? Int ?? NSNull()
        info["maxCapacity"]    = props["AppleRawMaxCapacity"]     as? Int ?? NSNull()
        info["designCapacity"] = props["DesignCapacity"]          as? Int ?? NSNull()
        info["voltage"]        = props["Voltage"]                 as? Int ?? NSNull()

        if let amps = props["Amperage"] as? Int {
            info["amperage"] = amps
            if let volts = props["Voltage"] as? Int {
                // mV × mA ÷ 10^6 = W; sign naturally conveys charge vs discharge
                info["watts"] = Double(volts) * Double(amps) / 1_000_000.0
            } else {
                info["watts"] = NSNull()
            }
        } else {
            info["amperage"] = NSNull()
            info["watts"]    = NSNull()
        }

        if let raw = props["Temperature"] as? Int {
            info["temperature"] = Double(raw) / 100.0
        } else {
            info["temperature"] = NSNull()
        }

        // 65535 is the sentinel value meaning "calculating" or "unlimited"
        let calculating = 65535
        if let t = props["TimeRemaining"] as? Int, t != calculating, t > 0 {
            info["timeRemaining"] = t
        } else if let t = props["AvgTimeToEmpty"] as? Int, t != calculating, t > 0 {
            info["timeRemaining"] = t
        } else {
            info["timeRemaining"] = NSNull()
        }

        if let t = props["AvgTimeToFull"] as? Int, t != calculating, t > 0 {
            info["timeToFullCharge"] = t
        } else {
            info["timeToFullCharge"] = NSNull()
        }

        info["serial"] = props["Serial"] as? String ?? NSNull()
        return info
    }

    // MARK: - Event Watcher (Pattern A)

    func addEventWatcher(_ listener: JSFunction) {
        _eventWatcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    func removeEventWatcher(_ listener: JSFunction) {
        _eventWatcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addEventWatcher:) func _addEventWatcher(_ callback: JSFunction) {
        guard eventWatcherCallback == nil else {
            AKWarning("hs.power._addEventWatcher: already watching — refusing second subscription")
            return
        }
        eventWatcherCallback = callback

        for (name, event) in HSPowerModule.workspaceEvents {
            let obs = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.fireEvent(event) }
            }
            workspaceObservers.append(obs)
        }

        for (name, event) in HSPowerModule.distributedEvents {
            let obs = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.fireEvent(event) }
            }
            distributedObservers.append(obs)
        }

        AKTrace("hs.power._addEventWatcher: started")
    }

    @objc func _removeEventWatcher() {
        guard eventWatcherCallback != nil else { return }

        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        for obs in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        workspaceObservers.removeAll()
        distributedObservers.removeAll()
        eventWatcherCallback = nil

        AKTrace("hs.power._removeEventWatcher: stopped")
    }

    // MARK: - Battery Watcher (Pattern A)

    func addBatteryWatcher(_ listener: JSFunction) {
        _batteryWatcherEmitter?.invokeMethod("on", withArguments: [listener])
    }

    func removeBatteryWatcher(_ listener: JSFunction) {
        _batteryWatcherEmitter?.invokeMethod("removeListener", withArguments: [listener])
    }

    @objc(_addBatteryWatcher:) func _addBatteryWatcher(_ callback: JSFunction) {
        guard batteryWatcherCallback == nil else {
            AKWarning("hs.power._addBatteryWatcher: already watching — refusing second subscription")
            return
        }
        batteryWatcherCallback = callback

        let ptr = unsafe Unmanaged.passRetained(self).toOpaque()
        unsafe batteryContextPointer = ptr

        // The callback fires on the main RunLoop, so MainActor.assumeIsolated is safe.
        // The outer closure captures nothing from the surrounding scope, making it
        // implicitly @convention(c) as required by IOPSNotificationCreateRunLoopSource.
        let callback: IOPowerSourceCallbackType = { context in
            guard let ctx = unsafe context else { return }
            let module = unsafe Unmanaged<HSPowerModule>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated {
                _ = module.batteryWatcherCallback?.call(withArguments: [])
            }
        }
        let source = unsafe IOPSNotificationCreateRunLoopSource(callback, ptr)?.takeRetainedValue()

        guard let source else {
            AKError("hs.power._addBatteryWatcher: IOPSNotificationCreateRunLoopSource failed")
            unsafe Unmanaged<HSPowerModule>.fromOpaque(ptr).release()
            unsafe batteryContextPointer = nil
            batteryWatcherCallback = nil
            return
        }

        batteryRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        AKTrace("hs.power._addBatteryWatcher: started")
    }

    @objc func _removeBatteryWatcher() {
        guard batteryWatcherCallback != nil else { return }

        if let source = batteryRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            batteryRunLoopSource = nil
        }
        if let ptr = unsafe batteryContextPointer {
            unsafe Unmanaged<HSPowerModule>.fromOpaque(ptr).release()
            unsafe batteryContextPointer = nil
        }
        batteryWatcherCallback = nil

        AKTrace("hs.power._removeBatteryWatcher: stopped")
    }

    // MARK: - Private Helpers

    private func batteryRegistryProperties() -> [String: Any]? {
        let service = unsafe IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMPowerSource")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard unsafe IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let props = unsafe propsRef?.takeRetainedValue() as? [String: Any] else { return nil }
        return props
    }

    private func resolvePowerSource() -> String {
        guard let blob = unsafe IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return "unknown" }
        return resolvePowerSource(from: blob)
    }

    private func resolvePowerSource(from blob: CFTypeRef) -> String {
        guard let str = unsafe IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? else {
            return "unknown"
        }
        switch str {
        case "AC Power":      return "ac"
        case "Battery Power": return "battery"
        case "UPS Power":     return "ups"
        default:              return "unknown"
        }
    }

    private func fireEvent(_ event: String) {
        _ = eventWatcherCallback?.call(withArguments: [event])
    }
}
