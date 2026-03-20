//
//  PermissionsManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 09/10/2025.
//

import Foundation
@unsafe @preconcurrency import ApplicationServices.HIServices.AXUIElement
import AVFoundation

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

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .screencapture: return "Screen Recording"
        }
    }

    var permissionDescription: String {
        switch self {
        case .accessibility:
            return "Allows Hammerspoon to control and monitor other applications via the Accessibility APIs."
        case .camera:
            return "Allows Hammerspoon scripts to access the camera."
        case .microphone:
            return "Allows Hammerspoon scripts to access the microphone."
        case .screencapture:
            return "Allows Hammerspoon to capture screen content for automation and scripting."
        }
    }
}

@_documentation(visibility: private)
@MainActor
class PermissionsManager {
    static let shared = PermissionsManager()

    func state(_ permType: PermissionsType) -> PermissionsState {
        switch permType {
        case .accessibility:
            return AXIsProcessTrusted() ? .trusted : .notTrusted
        case .camera:
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            return status == .authorized ? .trusted : .notTrusted
        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            return status == .authorized ? .trusted : .notTrusted
        case .screencapture:
            return CGPreflightScreenCaptureAccess() ? .trusted : .notTrusted
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
        }
    }
}
