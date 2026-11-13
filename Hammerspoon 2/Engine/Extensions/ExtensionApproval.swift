//
//  ExtensionApproval.swift
//  Hammerspoon 2
//

import AppKit
import Foundation

/// Asks the user whether an extension may load. Extensions run native code inside Hammerspoon 2,
/// with every permission the user has given it, so nothing a config script does can approve one.
protocol ExtensionApprover {
    /// Asks whether the extension may load
    /// - Parameters:
    ///   - manifest: The extension
    ///   - signature: Its verified signature
    /// - Returns: true if the user allowed it
    func approve(_ manifest: ExtensionManifest, signature: ExtensionSignature) -> Bool
}

/// Asks with a modal alert. The config that's loading the extension waits for the answer.
struct AlertExtensionApprover: ExtensionApprover {
    func approve(_ manifest: ExtensionManifest, signature: ExtensionSignature) -> Bool {
        let signer: String
        if let signerName = signature.signerName {
            signer = "It's signed by \(signerName)."
        } else {
            signer = "It isn't signed by an identified developer."
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow the extension \"\(manifest.name)\" to load?"
        alert.informativeText = """
            Your config wants to load the extension at \(manifest.bundleURL.path)\(manifest.spoonName.map { ", which comes with the Spoon \($0)" } ?? ""). \(signer)

            Extensions run their own code inside Hammerspoon 2, with all of the permissions you've given it, such as Accessibility and Input Monitoring. Only allow extensions from developers you trust.

            You'll be asked again if the extension changes.
            """
        // The safe choice is the default, so pressing Return doesn't load unknown code
        alert.addButton(withTitle: "Don't Allow")
        alert.addButton(withTitle: "Allow")

        // The config waits for an answer, so the alert must be seen. Activating is only a
        // request, which macOS refuses while the user is working in another app, and the alert
        // would then open behind that app's windows, so it also floats above them.
        NSApplication.shared.activate()
        alert.window.level = .floating
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// The user's approval of one build of an extension
nonisolated struct ExtensionApproval: Equatable, Identifiable {
    /// The extension's name
    let name: String
    /// The cdhash of the build they allowed
    let cdHash: String
    /// Who signed that build, or nil if it had an ad-hoc signature
    let signerName: String?
    /// When they allowed it
    let date: Date

    var id: String { name }
}

/// The extensions the user has allowed to load, each by the cdhash of the build they allowed,
/// stored in UserDefaults.
struct ExtensionApprovals {
    static let defaultsKey = "approvedExtensions"

    private enum Field {
        static let cdHash = "cdHash"
        static let signerName = "signerName"
        static let date = "date"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var stored: [String: [String: Any]] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String: Any]] ?? [:]
    }

    /// Every approval, sorted by extension name
    var all: [ExtensionApproval] {
        stored.compactMap { name, fields in
            guard let cdHash = fields[Field.cdHash] as? String else { return nil }
            return ExtensionApproval(name: name,
                                     cdHash: cdHash,
                                     signerName: fields[Field.signerName] as? String,
                                     date: fields[Field.date] as? Date ?? .distantPast)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether the user has allowed exactly this build of the extension
    func isApproved(_ name: String, signature: ExtensionSignature) -> Bool {
        stored[name]?[Field.cdHash] as? String == signature.cdHash
    }

    /// Records that the user allowed this build of the extension, replacing any earlier build
    func approve(_ name: String, signature: ExtensionSignature) {
        var fields: [String: Any] = [Field.cdHash: signature.cdHash, Field.date: Date()]
        fields[Field.signerName] = signature.signerName
        var updated = stored
        updated[name] = fields
        defaults.set(updated, forKey: Self.defaultsKey)
    }

    /// Forgets the approval of an extension, so the user is asked again the next time a config
    /// loads it
    func revoke(_ name: String) {
        var updated = stored
        updated.removeValue(forKey: name)
        defaults.set(updated, forKey: Self.defaultsKey)
    }

    /// Forgets every approval
    func revokeAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
