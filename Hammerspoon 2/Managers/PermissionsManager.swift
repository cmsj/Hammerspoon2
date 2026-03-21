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
    case screencapture
    case location

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .screencapture: return "Screen Recording"
        case .location: return "Location"
        }
    }

    var permissionDescription: String {
        switch self {
        case .accessibility:
            return "Allows controlling and monitoring other applications"
        case .camera:
            return "Allows accessing the camera"
        case .microphone:
            return "Allows accessing the microphone"
        case .screencapture:
            return "Allows capturing screen content"
        case .location:
            return "Allows accessing this computer's location"
        }
    }

    var settingsURL: URL {
        let path: String
        switch self {
        case .accessibility: path = "Privacy_Accessibility"
        case .camera:        path = "Privacy_Camera"
        case .microphone:    path = "Privacy_Microphone"
        case .screencapture: path = "Privacy_ScreenCapture"
        case .location:      path = "Privacy_LocationServices"
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
        case .screencapture:
            return CGPreflightScreenCaptureAccess() ? .trusted : .notTrusted
        case .location:
            switch CLLocationManager().authorizationStatus {
            case .authorized, .authorizedAlways: return .trusted
            case .notDetermined:                 return .unknown
            default:                             return .notTrusted
            }
        }
    }

    func check(_ permType: PermissionsType) -> Bool {
        switch permType {
        case .accessibility:
            return AXIsProcessTrusted()
        case .camera:
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            return status == .authorized
        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            return status == .authorized
        case .screencapture:
            return CGPreflightScreenCaptureAccess()
        case .location:
            let status = CLLocationManager().authorizationStatus
            return status == .authorized || status == .authorizedAlways
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
