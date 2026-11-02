//
//  HSSkyLight.swift
//  Hammerspoon 2
//

import Foundation
import CoreGraphics

/// A thin wrapper around the private SkyLight framework functions hs.spaces needs.
///
/// SkyLight is the private framework WindowServer clients (including the Dock and Mission
/// Control) use to manage Spaces. It can report on spaces and the windows on them, but it can't
/// add, remove, or switch spaces in a way the Dock notices - see HSMissionControl for those. None of this is public API: every function is resolved at
/// runtime with dlsym, so a macOS update that renames or removes one makes `shared` nil (and
/// hs.spaces report itself unavailable) rather than crashing at launch. A signature change,
/// however, can't be detected - that's the inherent risk of this module.
///
/// Signatures follow those used by long-standing open source consumers of these functions
/// (Hammerspoon 1's hs.spaces, yabai), and were verified against macOS 27.
// @safe: the unsafe storage is the C function pointers below. They're only ever called with
// values this class creates itself, and the Unmanaged results are consumed immediately.
@safe @_documentation(visibility: private)
final class HSSkyLight {
    typealias ConnectionID = Int32
    typealias SpaceID = UInt64

    /// The values SLSSpaceGetType returns for the kinds of space we know about
    enum SpaceKind: Int32 {
        case user = 0
        case system = 2
        case fullscreen = 4
    }

    /// Mask for SLSCopySpacesForWindows meaning "every space the window is on"
    private static let allSpacesMask: Int32 = 0x7
    /// Option for SLSCopyWindowsWithOptionsAndTags that lists windows ordered onto a space
    private static let windowsOnSpaceOption: UInt32 = 0x2

    private typealias MainConnectionIDFn = @convention(c) () -> ConnectionID
    private typealias GetActiveSpaceFn = @convention(c) (ConnectionID) -> SpaceID
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private typealias CopyManagedDisplayForSpaceFn = @convention(c) (ConnectionID, SpaceID) -> Unmanaged<CFString>?
    private typealias SpaceGetTypeFn = @convention(c) (ConnectionID, SpaceID) -> Int32
    private typealias CopySpacesForWindowsFn = @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyWindowsWithOptionsAndTagsFn = @convention(c) (
        ConnectionID, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?

    /// The loaded framework, or nil if SkyLight or any of the symbols we need is missing.
    /// The framework is never unloaded - it's already mapped into every AppKit process anyway.
    static let shared: HSSkyLight? = HSSkyLight()

    private let connection: ConnectionID
    private let getActiveSpaceFn: GetActiveSpaceFn
    private let copyManagedDisplaySpacesFn: CopyManagedDisplaySpacesFn
    private let copyManagedDisplayForSpaceFn: CopyManagedDisplayForSpaceFn
    private let spaceGetTypeFn: SpaceGetTypeFn
    private let copySpacesForWindowsFn: CopySpacesForWindowsFn
    private let copyWindowsWithOptionsAndTagsFn: CopyWindowsWithOptionsAndTagsFn

    private init?() {
        guard let handle = unsafe dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            AKError("hs.spaces: unable to load the private SkyLight framework")
            return nil
        }

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = unsafe dlsym(handle, name) else {
                AKError("hs.spaces: SkyLight symbol \(name) is missing from this version of macOS")
                return nil
            }
            return unsafe unsafeBitCast(symbol, to: type)
        }

        guard let mainConnectionID = load("SLSMainConnectionID", as: MainConnectionIDFn.self),
              let getActiveSpace = load("SLSGetActiveSpace", as: GetActiveSpaceFn.self),
              let copyManagedDisplaySpaces = unsafe load("SLSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self),
              let copyManagedDisplayForSpace = unsafe load("SLSCopyManagedDisplayForSpace", as: CopyManagedDisplayForSpaceFn.self),
              let spaceGetType = load("SLSSpaceGetType", as: SpaceGetTypeFn.self),
              let copySpacesForWindows = unsafe load("SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self),
              let copyWindowsWithOptionsAndTags = unsafe load("SLSCopyWindowsWithOptionsAndTags", as: CopyWindowsWithOptionsAndTagsFn.self)
        else {
            return nil
        }

        connection = mainConnectionID()
        getActiveSpaceFn = getActiveSpace
        unsafe copyManagedDisplaySpacesFn = copyManagedDisplaySpaces
        unsafe copyManagedDisplayForSpaceFn = copyManagedDisplayForSpace
        spaceGetTypeFn = spaceGetType
        unsafe copySpacesForWindowsFn = copySpacesForWindows
        unsafe copyWindowsWithOptionsAndTagsFn = copyWindowsWithOptionsAndTags
    }

    // MARK: - Displays and spaces

    /// One entry per managed display, in SkyLight's order
    struct ManagedDisplay {
        /// SkyLight's identifier for the display - its UUID, or "Main" when all displays
        /// share one set of spaces ("Displays have separate Spaces" turned off)
        let identifier: String
        let currentSpace: SpaceID?
        let spaces: [SpaceID]
    }

    /// The space that currently has keyboard focus
    var activeSpace: SpaceID {
        getActiveSpaceFn(connection)
    }

    /// Every managed display and the spaces on it
    func managedDisplays() -> [ManagedDisplay] {
        rawManagedDisplaySpaces().compactMap { display in
            guard let identifier = display["Display Identifier"] as? String else { return nil }
            let spaces = (display["Spaces"] as? [[String: Any]] ?? []).compactMap(Self.spaceID(from:))
            let currentSpace = (display["Current Space"] as? [String: Any]).flatMap(Self.spaceID(from:))
            return ManagedDisplay(identifier: identifier, currentSpace: currentSpace, spaces: spaces)
        }
    }

    /// SLSCopyManagedDisplaySpaces's result, unparsed
    func rawManagedDisplaySpaces() -> [[String: Any]] {
        unsafe copyManagedDisplaySpacesFn(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
    }

    private static func spaceID(from space: [String: Any]) -> SpaceID? {
        (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
    }

    /// The managed display identifier of the display holding `space`
    func displayIdentifier(for space: SpaceID) -> String? {
        unsafe copyManagedDisplayForSpaceFn(connection, space)?.takeRetainedValue() as String?
    }

    /// The raw SLSSpaceGetType value for `space`
    func type(of space: SpaceID) -> Int32 {
        spaceGetTypeFn(connection, space)
    }

    // MARK: - Windows

    /// Every space `window` is on (more than one for windows set to appear on all spaces)
    func spaces(forWindow window: CGWindowID) -> [SpaceID] {
        let windows = [NSNumber(value: window)] as CFArray
        let spaces = unsafe copySpacesForWindowsFn(connection, Self.allSpacesMask, windows)?.takeRetainedValue() as? [NSNumber]
        return spaces?.map(\.uint64Value) ?? []
    }

    /// The IDs of every window on `space`, of any kind (including menus, panels, etc)
    func windows(onSpace space: SpaceID) -> [CGWindowID] {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        let spaces = [NSNumber(value: space)] as CFArray
        let windows = unsafe copyWindowsWithOptionsAndTagsFn(connection, 0, spaces, Self.windowsOnSpaceOption, &setTags, &clearTags)?
            .takeRetainedValue() as? [NSNumber]
        return windows?.map(\.uint32Value) ?? []
    }
}
