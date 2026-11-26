//
//  PermissionsManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import Foundation
@unsafe @preconcurrency import ApplicationServices.HIServices.AXUIElement
import AVFoundation
import CoreLocation
import UserNotifications
import IOKit.hid
import CoreBluetooth
import EventKit

@_documentation(visibility: private)
enum PermissionsState: Int {
    case notTrusted = 0
    case trusted
    case unknown
}

@_documentation(visibility: private)
enum PermissionsType: Int, CaseIterable {
    case accessibility = 0
    case camera
    case microphone
    case notifications
    case screencapture
    case location
    case inputMonitoring
    case bluetooth
    case calendars
    case reminders

    var displayName: String {
        switch self {
        case .accessibility:  return "Accessibility"
        case .camera:         return "Camera"
        case .microphone:     return "Microphone"
        case .notifications:  return "Notifications"
        case .screencapture:  return "Screen Recording"
        case .location:       return "Location"
        case .inputMonitoring: return "Input Monitoring"
        case .bluetooth:      return "Bluetooth"
        case .calendars:      return "Calendars"
        case .reminders:      return "Reminders"
        }
    }

    var permissionDescription: String {
        switch self {
        case .accessibility:  return "Allows controlling and monitoring other applications"
        case .camera:         return "Allows accessing the camera"
        case .microphone:     return "Allows accessing the microphone"
        case .notifications:  return "Allows displaying system notifications"
        case .screencapture:  return "Allows capturing screen content"
        case .location:       return "Allows accessing this computer's location"
        case .inputMonitoring: return "Allows per-keyboard access to modifier key state and LEDs"
        case .bluetooth:      return "Allows inspecting, connecting to and scanning for Bluetooth devices"
        case .calendars:      return "Allows reading calendar events"
        case .reminders:      return "Allows reading and changing reminders"
        }
    }

    var settingsURL: URL {
        let path: String
        switch self {
        case .accessibility:  path = "Privacy_Accessibility"
        case .camera:         path = "Privacy_Camera"
        case .microphone:     path = "Privacy_Microphone"
        case .notifications:  return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        case .screencapture:  path = "Privacy_ScreenCapture"
        case .location:       path = "Privacy_LocationServices"
        case .inputMonitoring: path = "Privacy_ListenEvent"
        case .bluetooth:      path = "Privacy_Bluetooth"
        case .calendars:      path = "Privacy_Calendars"
        case .reminders:      path = "Privacy_Reminders"
        }
        // swiftlint:disable:next force_unwrapping
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)")!
    }
}

@_documentation(visibility: private)
@MainActor
class PermissionsManager: NSObject {
    static let shared = PermissionsManager()

    private var locationManager: CLLocationManager?
    private var locationCallback: (@Sendable (Bool) -> Void)?

    // Asking for Bluetooth access means starting CoreBluetooth; this manager exists only until
    // the user has answered
    private var bluetoothManager: CBCentralManager?
    private var bluetoothCallbacks: [@Sendable (Bool) -> Void] = []

    // The event store asking for calendar or reminders access (.calendars/.reminders), kept until
    // the user has answered, with every caller waiting for that answer
    private var eventKitStores: [PermissionsType: EKEventStore] = [:]
    private var eventKitCallbacks: [PermissionsType: [@Sendable (Bool) -> Void]] = [:]

    // Notification authorization has no synchronous status API, so we cache the last known state.
    // The cache is populated on first check and after every request.
    private var cachedNotificationState: PermissionsState = .unknown

    isolated deinit {
        locationManager?.delegate = nil
        bluetoothManager?.delegate = nil
    }

    private func refreshNotificationState() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            // Extract the Sendable enum value before crossing into the main actor task.
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .authorized, .provisional: self.cachedNotificationState = .trusted
                case .denied:                   self.cachedNotificationState = .notTrusted
                default:                        self.cachedNotificationState = .unknown
                }
            }
        }
    }

    func state(_ permType: PermissionsType) -> PermissionsState {
        switch permType {
        case .accessibility:
            return AXIsProcessTrusted() ? .trusted : .notTrusted
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:    return .trusted
            case .notDetermined: return .unknown
            default:             return .notTrusted
            }
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:    return .trusted
            case .notDetermined: return .unknown
            default:             return .notTrusted
            }
        case .notifications:
            if cachedNotificationState == .unknown { refreshNotificationState() }
            return cachedNotificationState
        case .screencapture:
            return CGPreflightScreenCaptureAccess() ? .trusted : .notTrusted
        case .location:
            switch CLLocationManager().authorizationStatus {
            case .authorized, .authorizedAlways: return .trusted
            case .notDetermined:                 return .unknown
            default:                             return .notTrusted
            }
        case .inputMonitoring:
            switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
            case kIOHIDAccessTypeGranted:  return .trusted
            case kIOHIDAccessTypeDenied:   return .notTrusted
            default:                       return .unknown
            }
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .trusted
            case .notDetermined: return .unknown
            default:             return .notTrusted
            }
        case .calendars:
            // .writeOnly isn't enough to read events, so it counts as not trusted
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess:    return .trusted
            case .notDetermined: return .unknown
            default:             return .notTrusted
            }
        case .reminders:
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .fullAccess:    return .trusted
            case .notDetermined: return .unknown
            default:             return .notTrusted
            }
        }
    }

    func check(_ permType: PermissionsType) -> Bool {
        switch permType {
        case .accessibility:
            return AXIsProcessTrusted()
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .notifications:
            if cachedNotificationState == .unknown { refreshNotificationState() }
            return cachedNotificationState == .trusted
        case .screencapture:
            return CGPreflightScreenCaptureAccess()
        case .location:
            let status = CLLocationManager().authorizationStatus
            return status == .authorized || status == .authorizedAlways
        case .inputMonitoring:
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .bluetooth:
            return CBManager.authorization == .allowedAlways
        case .calendars:
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .reminders:
            return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        }
    }

    func request(_ permType: PermissionsType, callback: (@Sendable (Bool) -> Void)? = nil) {
        switch permType {
        case .accessibility:
            let options = unsafe [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        case .camera:
            let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)

            switch currentStatus {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video, completionHandler: callback ?? { _ in })
            case .authorized:
                callback?(true)
            default:
                callback?(false)
            }
        case .microphone:
            let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

            switch currentStatus {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: callback ?? { _ in })
            case .authorized:
                callback?(true)
            default:
                callback?(false)
            }
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
                if let error {
                    Task { @MainActor in
                        AKError("hs.permissions.requestNotifications(): \(error.localizedDescription)")
                    }
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.cachedNotificationState = granted ? .trusted : .notTrusted
                    callback?(granted)
                }
            }
        case .screencapture:
            CGRequestScreenCaptureAccess()
        case .location:
            let manager = CLLocationManager()
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                callback?(true)
            case .notDetermined:
                locationManager = manager
                locationCallback = callback
                manager.delegate = self
                manager.requestAlwaysAuthorization()
            default:
                callback?(false)
            }
        case .inputMonitoring:
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            callback?(granted)
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways:
                callback?(true)
            case .notDetermined:
                if let callback { bluetoothCallbacks.append(callback) }
                if bluetoothManager == nil {
                    // Creating a manager is what shows the prompt; its first state update
                    // arrives once the user has answered
                    bluetoothManager = CBCentralManager(delegate: self, queue: .main,
                                                        options: [CBCentralManagerOptionShowPowerAlertKey: false])
                }
            default:
                callback?(false)
            }
        case .calendars:
            requestEventKitAccess(.calendars, entity: .event, callback: callback)
        case .reminders:
            requestEventKitAccess(.reminders, entity: .reminder, callback: callback)
        }
    }

    /// Asks for full access to calendar events or reminders, sharing one prompt between every
    /// caller that asks while it's showing
    private func requestEventKitAccess(_ permType: PermissionsType, entity: EKEntityType,
                                       callback: (@Sendable (Bool) -> Void)?) {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess:
            callback?(true)
        case .notDetermined:
            if let callback { eventKitCallbacks[permType, default: []].append(callback) }
            guard eventKitStores[permType] == nil else { return }
            let store = EKEventStore()
            eventKitStores[permType] = store
            // Called on an arbitrary queue, so it must not be main-actor isolated
            let completion: @Sendable (Bool, (any Error)?) -> Void = { [weak self] granted, error in
                let message = error?.localizedDescription
                Task { @MainActor [weak self] in
                    if let message { AKError("hs.permissions.request\(permType.displayName)(): \(message)") }
                    guard let self else { return }
                    let callbacks = self.eventKitCallbacks.removeValue(forKey: permType) ?? []
                    self.eventKitStores[permType] = nil
                    callbacks.forEach { $0(granted) }
                }
            }
            if entity == .reminder {
                store.requestFullAccessToReminders(completion: completion)
            } else {
                store.requestFullAccessToEvents(completion: completion)
            }
        default:
            callback?(false)
        }
    }
}

extension PermissionsManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let authorization = CBManager.authorization
        guard authorization != .notDetermined else { return }
        MainActor.assumeIsolated {
            let callbacks = bluetoothCallbacks
            bluetoothCallbacks.removeAll()
            bluetoothManager?.delegate = nil
            bluetoothManager = nil
            callbacks.forEach { $0(authorization == .allowedAlways) }
        }
    }
}

extension PermissionsManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let granted = status == .authorized || status == .authorizedAlways
        Task { @MainActor [weak self] in
            guard let self else { return }
            let callback = self.locationCallback
            self.locationCallback = nil
            self.locationManager = nil
            callback?(granted)
        }
    }
}
