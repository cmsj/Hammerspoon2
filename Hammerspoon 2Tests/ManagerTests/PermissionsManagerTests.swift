//
//  PermissionsManagerTests.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 20/03/2026.
//

import Testing
import Foundation
@testable import Hammerspoon_2

struct PermissionsTypeMetadataTests {

    // MARK: - CaseIterable

    @Test("PermissionsType has all expected cases")
    func testAllCasesContents() {
        let expected: [PermissionsType] = [.accessibility, .camera, .microphone, .screencapture, .location]
        #expect(PermissionsType.allCases == expected)
    }

    // MARK: - displayName

    @Test("accessibility displayName is correct")
    func testAccessibilityDisplayName() {
        #expect(PermissionsType.accessibility.displayName == "Accessibility")
    }

    @Test("camera displayName is correct")
    func testCameraDisplayName() {
        #expect(PermissionsType.camera.displayName == "Camera")
    }

    @Test("microphone displayName is correct")
    func testMicrophoneDisplayName() {
        #expect(PermissionsType.microphone.displayName == "Microphone")
    }

    @Test("screencapture displayName is correct")
    func testScreencaptureDisplayName() {
        #expect(PermissionsType.screencapture.displayName == "Screen Recording")
    }

    @Test("location displayName is correct")
    func testLocationDisplayName() {
        #expect(PermissionsType.location.displayName == "Location")
    }

    @Test("All permission types have non-empty displayName")
    func testAllDisplayNamesNonEmpty() {
        for permType in PermissionsType.allCases {
            #expect(!permType.displayName.isEmpty, "displayName should not be empty for \(permType)")
        }
    }

    // MARK: - permissionDescription

    @Test("All permission types have non-empty description")
    func testAllDescriptionsNonEmpty() {
        for permType in PermissionsType.allCases {
            #expect(!permType.permissionDescription.isEmpty, "description should not be empty for \(permType)")
        }
    }

    @Test("accessibility description mentions Accessibility APIs")
    func testAccessibilityDescription() {
        #expect(PermissionsType.accessibility.permissionDescription.contains("Accessibility"))
    }

    @Test("camera description mentions camera")
    func testCameraDescription() {
        let desc = PermissionsType.camera.permissionDescription.lowercased()
        #expect(desc.contains("camera"))
    }

    @Test("microphone description mentions microphone")
    func testMicrophoneDescription() {
        let desc = PermissionsType.microphone.permissionDescription.lowercased()
        #expect(desc.contains("microphone"))
    }

    @Test("screencapture description mentions screen")
    func testScreencaptureDescription() {
        let desc = PermissionsType.screencapture.permissionDescription.lowercased()
        #expect(desc.contains("screen"))
    }

    @Test("location description mentions location")
    func testLocationDescription() {
        let desc = PermissionsType.location.permissionDescription.lowercased()
        #expect(desc.contains("location"))
    }

    @Test("Each permission type has a unique displayName")
    func testUniqueDisplayNames() {
        let names = PermissionsType.allCases.map { $0.displayName }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "All displayNames should be unique")
    }

    @Test("Each permission type has a unique description")
    func testUniqueDescriptions() {
        let descs = PermissionsType.allCases.map { $0.permissionDescription }
        let uniqueDescs = Set(descs)
        #expect(descs.count == uniqueDescs.count, "All descriptions should be unique")
    }
}
