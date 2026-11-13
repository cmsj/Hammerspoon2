//
//  SettingsManager.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/10/2025.
//

import Foundation
import SwiftUI
@_spi(HammerspoonHost) import HammerspoonSDK

enum DockMenubarType: String, CaseIterable, Identifiable {
    var id: Self { self }

    case dock
    case menuBar
    case both
    case neither

    var displayName: String {
        switch self {
        case .dock:
            return "Dock only"
        case .menuBar:
            return "Menu bar only"
        case .both:
            return "Dock and Menu bar"
        case .neither:
            return "Neither"
        }
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .menuBar, .neither:
            return .accessory
        default:
            return .regular
        }
    }

    var showMenuItem: Bool {
        get {
            switch self {
            case .menuBar, .both:
                return true
            default:
                return false
            }
        }
        set {
            if newValue == true {
                // We should never actually take this branch, because there should be no way
                // for SwiftUI/macOS to initiate us being in the menubar. This branch is
                // included here only for completeness sake.
                switch self {
                case .dock:
                    self = .both
                default:
                    // We're already intending to be in the menubar, so no action required
                    return
                }
            } else {
                // This is the branch that actually matters, because the user manually removed
                // our menubar item from the menubar.
                switch self {
                case .both, .menuBar:
                    self = .dock
                default:
                    // We should never hit this because how could the menubar item have been
                    // removed if it wasn't configured to be there.
                    return
                }
            }
        }
    }
}

/// What to do when the app is launched again while it's already running (e.g. from Finder,
/// Spotlight or `open -a`), which macOS delivers as a reopen event rather than a second launch.
/// Clicking the Dock icon is also a reopen event.
enum ReopenAction: String, CaseIterable, Identifiable {
    var id: Self { self }

    case showConsole
    case callback
    case doNothing

    var displayName: String {
        switch self {
        case .showConsole:
            return "Show Console"
        case .callback:
            return "Call hs.onRelaunch"
        case .doNothing:
            return "Do Nothing"
        }
    }
}

protocol SettingsManagerDelegate: AnyObject {
    func settingsDidChange()
}

@_documentation(visibility: private)
@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    private struct WeakDelegate {
        weak var object: AnyObject?
        let notify: () -> Void

        init<T: SettingsManagerDelegate>(_ delegate: T) {
            object = delegate
            notify = { [weak delegate] in delegate?.settingsDidChange() }
        }

        var isAlive: Bool { object != nil }
    }

    @ObservationIgnored
    private var delegates: [ObjectIdentifier: WeakDelegate] = [:]

    func addDelegate<T: SettingsManagerDelegate>(_ delegate: T) {
        delegates[ObjectIdentifier(delegate)] = WeakDelegate(delegate)
    }

    func removeDelegate<T: SettingsManagerDelegate>(_ delegate: T) {
        delegates.removeValue(forKey: ObjectIdentifier(delegate))
    }

    func removeAllDelegates() {
        delegates.removeAll()
    }

    private func notifyDelegates() {
        delegates = delegates.filter { $0.value.isAlive }
        delegates.values.forEach { $0.notify() }
    }

    enum Keys: String, CaseIterable {
        case configLocation
        case consoleHistoryLength
        case relaunchOnReload
        case dockMenuBehaviour
        case hasCompletedOnboarding
        case garbageLoggingEnabled
        case consoleAlwaysOnTop
        case consoleAlpha
        case reopenAction
        case importSpoonsOnOpen
        case offerCrashReports
        case allowExtensions

        var id: String { "\(self)" }

        var defaultValue: Any {
            switch self {
            case .configLocation:
                return URL(filePath: NSString("~/.config/Hammerspoon2/init.js").expandingTildeInPath)
            case .consoleHistoryLength:
                return 100
            case .relaunchOnReload:
                return false
            case .dockMenuBehaviour:
                return DockMenubarType.both.rawValue
            case .hasCompletedOnboarding:
                return false
            case .garbageLoggingEnabled:
                return false
            case .consoleAlwaysOnTop:
                return false
            case .consoleAlpha:
                return 1.0
            case .reopenAction:
                return ReopenAction.showConsole.rawValue
            case .importSpoonsOnOpen, .offerCrashReports:
                return true
            case .allowExtensions:
                return false
            }
        }
    }

    var configLocation: URL {
        didSet {
            UserDefaults.standard.set(configLocation, forKey: Keys.configLocation.rawValue)
            notifyDelegates()
        }
    }
    var consoleHistoryLength: Int {
        didSet {
            UserDefaults.standard.set(consoleHistoryLength, forKey: Keys.consoleHistoryLength.rawValue)
            notifyDelegates()
        }
    }
    var relaunchOnReload: Bool {
        didSet {
            UserDefaults.standard.set(relaunchOnReload, forKey: Keys.relaunchOnReload.rawValue)
            notifyDelegates()
        }
    }
    var dockMenuBehaviour: DockMenubarType {
        didSet {
            UserDefaults.standard.set(dockMenuBehaviour.rawValue, forKey: Keys.dockMenuBehaviour.rawValue)
            notifyDelegates()
        }
    }
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding.rawValue)
            notifyDelegates()
        }
    }
    var garbageLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(garbageLoggingEnabled, forKey: Keys.garbageLoggingEnabled.rawValue)
            akSetGarbageLoggingEnabled(garbageLoggingEnabled)
            notifyDelegates()
        }
    }
    var consoleAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(consoleAlwaysOnTop, forKey: Keys.consoleAlwaysOnTop.rawValue)
            notifyDelegates()
        }
    }
    var consoleAlpha: Double {
        didSet {
            UserDefaults.standard.set(consoleAlpha, forKey: Keys.consoleAlpha.rawValue)
            notifyDelegates()
        }
    }

    /// Whether to offer to report crashes on GitHub the next time the app launches.
    var offerCrashReports: Bool {
        didSet {
            UserDefaults.standard.set(offerCrashReports, forKey: Keys.offerCrashReports.rawValue)
            notifyDelegates()
        }
    }

    var reopenAction: ReopenAction {
        didSet {
            UserDefaults.standard.set(reopenAction.rawValue, forKey: Keys.reopenAction.rawValue)
            notifyDelegates()
        }
    }

    /// Whether opening a `.spoon2` bundle (e.g. double-clicking it in Finder) installs it.
    /// When off, the bundle is handed to the user's config like any other opened file.
    var importSpoonsOnOpen: Bool {
        didSet {
            UserDefaults.standard.set(importSpoonsOnOpen, forKey: Keys.importSpoonsOnOpen.rawValue)
            notifyDelegates()
        }
    }

    /// Whether scripts may load extensions (native code built against HammerspoonSDK) with
    /// `require('ext:<name>')`. Off by default, since an extension runs with all of the app's
    /// permissions.
    var allowExtensions: Bool {
        didSet {
            UserDefaults.standard.set(allowExtensions, forKey: Keys.allowExtensions.rawValue)
            notifyDelegates()
        }
    }

    /// The extensions the user has allowed to load, by name. `ExtensionLoader` records approvals
    /// in UserDefaults, and this follows them.
    private(set) var approvedExtensions: [ExtensionApproval] = []

    /// Forgets the user's approval of an extension, so they're asked again the next time a
    /// config loads it
    func revokeExtensionApproval(_ name: String) {
        ExtensionApprovals().revoke(name)
        approvedExtensions = ExtensionApprovals().all
    }

    /// Where extension bundles are installed: an Extensions folder next to the config file
    var extensionsDirectory: URL {
        configLocation.deletingLastPathComponent().appendingPathComponent("Extensions", isDirectory: true)
    }

    @ObservationIgnored
    private var defaultsObserver: (any NSObjectProtocol)?

    init() {
        UserDefaults.standard.register(defaults: [
            Keys.configLocation.rawValue: Keys.configLocation.defaultValue,
            Keys.consoleHistoryLength.rawValue: Keys.consoleHistoryLength.defaultValue,
            Keys.relaunchOnReload.rawValue: Keys.relaunchOnReload.defaultValue,
            Keys.dockMenuBehaviour.rawValue: Keys.dockMenuBehaviour.defaultValue,
            Keys.hasCompletedOnboarding.rawValue: Keys.hasCompletedOnboarding.defaultValue,
            Keys.garbageLoggingEnabled.rawValue: Keys.garbageLoggingEnabled.defaultValue,
            Keys.consoleAlwaysOnTop.rawValue: Keys.consoleAlwaysOnTop.defaultValue,
            Keys.consoleAlpha.rawValue: Keys.consoleAlpha.defaultValue,
            Keys.reopenAction.rawValue: Keys.reopenAction.defaultValue,
            Keys.importSpoonsOnOpen.rawValue: Keys.importSpoonsOnOpen.defaultValue,
            Keys.offerCrashReports.rawValue: Keys.offerCrashReports.defaultValue,
            Keys.allowExtensions.rawValue: Keys.allowExtensions.defaultValue
        ])

        // swiftlint:disable force_cast
        configLocation = UserDefaults.standard.url(forKey: Keys.configLocation.rawValue)
            ?? (Keys.configLocation.defaultValue as! URL)
        consoleHistoryLength = UserDefaults.standard.integer(forKey: Keys.consoleHistoryLength.rawValue)
        relaunchOnReload = UserDefaults.standard.bool(forKey: Keys.relaunchOnReload.rawValue)
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding.rawValue)
        garbageLoggingEnabled = UserDefaults.standard.bool(forKey: Keys.garbageLoggingEnabled.rawValue)
        consoleAlwaysOnTop = UserDefaults.standard.bool(forKey: Keys.consoleAlwaysOnTop.rawValue)
        consoleAlpha = min(max(UserDefaults.standard.double(forKey: Keys.consoleAlpha.rawValue), 0.2), 1.0)
        importSpoonsOnOpen = UserDefaults.standard.bool(forKey: Keys.importSpoonsOnOpen.rawValue)
        offerCrashReports = UserDefaults.standard.bool(forKey: Keys.offerCrashReports.rawValue)
        allowExtensions = UserDefaults.standard.bool(forKey: Keys.allowExtensions.rawValue)
        approvedExtensions = ExtensionApprovals().all

        let dockMenuBehaviourString = UserDefaults.standard.string(forKey: Keys.dockMenuBehaviour.rawValue) ?? Keys.dockMenuBehaviour.defaultValue as! String
        dockMenuBehaviour = DockMenubarType(rawValue: dockMenuBehaviourString) ?? .both

        let reopenActionString = UserDefaults.standard.string(forKey: Keys.reopenAction.rawValue) ?? Keys.reopenAction.defaultValue as! String
        reopenAction = ReopenAction(rawValue: reopenActionString) ?? .showConsole
        // swiftlint:enable force_cast

        // didSet does not fire for assignments made inside this initializer, so the
        // AKGarbage gate needs to be seeded explicitly to match the persisted value.
        // This must come after every stored property is initialized.
        akSetGarbageLoggingEnabled(garbageLoggingEnabled)

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncFromUserDefaults() }
        }
    }

    isolated deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func syncFromUserDefaults() {
        // swiftlint:disable:next force_cast
        let newConfigLocation = UserDefaults.standard.url(forKey: Keys.configLocation.rawValue) ?? (Keys.configLocation.defaultValue as! URL)
        if newConfigLocation != configLocation { configLocation = newConfigLocation }

        let newConsoleHistoryLength = UserDefaults.standard.integer(forKey: Keys.consoleHistoryLength.rawValue)
        if newConsoleHistoryLength != consoleHistoryLength { consoleHistoryLength = newConsoleHistoryLength }

        let newRelaunchOnReload = UserDefaults.standard.bool(forKey: Keys.relaunchOnReload.rawValue)
        if newRelaunchOnReload != relaunchOnReload { relaunchOnReload = newRelaunchOnReload }

        let newDockMenuBehaviour = UserDefaults.standard.string(forKey: Keys.dockMenuBehaviour.rawValue)
        if let newDockMenuBehaviour, newDockMenuBehaviour != dockMenuBehaviour.rawValue {
            if let behaviour = DockMenubarType(rawValue: newDockMenuBehaviour) {
                dockMenuBehaviour = behaviour
            }
        }

        let newReopenAction = UserDefaults.standard.string(forKey: Keys.reopenAction.rawValue)
        if let newReopenAction, newReopenAction != reopenAction.rawValue {
            if let action = ReopenAction(rawValue: newReopenAction) {
                reopenAction = action
            }
        }

        let newHasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding.rawValue)
        if newHasCompletedOnboarding != hasCompletedOnboarding { hasCompletedOnboarding = newHasCompletedOnboarding }

        let newGarbageLoggingEnabled = UserDefaults.standard.bool(forKey: Keys.garbageLoggingEnabled.rawValue)
        if newGarbageLoggingEnabled != garbageLoggingEnabled { garbageLoggingEnabled = newGarbageLoggingEnabled }

        let newConsoleAlwaysOnTop = UserDefaults.standard.bool(forKey: Keys.consoleAlwaysOnTop.rawValue)
        if newConsoleAlwaysOnTop != consoleAlwaysOnTop { consoleAlwaysOnTop = newConsoleAlwaysOnTop }

        let newImportSpoonsOnOpen = UserDefaults.standard.bool(forKey: Keys.importSpoonsOnOpen.rawValue)
        if newImportSpoonsOnOpen != importSpoonsOnOpen { importSpoonsOnOpen = newImportSpoonsOnOpen }

        let newAllowExtensions = UserDefaults.standard.bool(forKey: Keys.allowExtensions.rawValue)
        if newAllowExtensions != allowExtensions { allowExtensions = newAllowExtensions }

        let newApprovedExtensions = ExtensionApprovals().all
        if newApprovedExtensions != approvedExtensions { approvedExtensions = newApprovedExtensions }

        // Clamped in case another preferences client (e.g. iCloud sync) stores a value
        // outside the range the console UI allows, so displayed and applied opacity agree.
        let newConsoleAlpha = min(max(UserDefaults.standard.double(forKey: Keys.consoleAlpha.rawValue), 0.2), 1.0)
        if newConsoleAlpha != consoleAlpha { consoleAlpha = newConsoleAlpha }

        let newOfferCrashReports = UserDefaults.standard.bool(forKey: Keys.offerCrashReports.rawValue)
        if newOfferCrashReports != offerCrashReports { offerCrashReports = newOfferCrashReports }
    }
}

// MARK: - SettingsManagerProtocol Conformance
extension SettingsManager: SettingsManagerProtocol {
    func resetToDefaults() {
        // swiftlint:disable force_cast
        configLocation = Keys.configLocation.defaultValue as! URL
        consoleHistoryLength = Keys.consoleHistoryLength.defaultValue as! Int
        relaunchOnReload = Keys.relaunchOnReload.defaultValue as! Bool
        garbageLoggingEnabled = Keys.garbageLoggingEnabled.defaultValue as! Bool
        consoleAlwaysOnTop = Keys.consoleAlwaysOnTop.defaultValue as! Bool
        consoleAlpha = Keys.consoleAlpha.defaultValue as! Double
        importSpoonsOnOpen = Keys.importSpoonsOnOpen.defaultValue as! Bool
        offerCrashReports = Keys.offerCrashReports.defaultValue as! Bool
        allowExtensions = Keys.allowExtensions.defaultValue as! Bool
        ExtensionApprovals().revokeAll()
        approvedExtensions = []

        // swiftlint:disable force_unwrapping
        let dockMenuType = DockMenubarType(rawValue: Keys.dockMenuBehaviour.defaultValue as! String)!
        dockMenuBehaviour = dockMenuType

        reopenAction = ReopenAction(rawValue: Keys.reopenAction.defaultValue as! String)!
        // swiftlint:enable force_cast force_unwrapping
    }
}
