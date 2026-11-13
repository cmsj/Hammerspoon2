//
//  ExtensionLoader.swift
//  Hammerspoon 2
//

import Foundation
import ObjectiveC
import HammerspoonSDK

/// An extension whose code has been loaded. It stays loaded for the life of the process: macOS
/// can't safely unload Objective-C or Swift code, so a changed extension needs an app restart.
struct LoadedExtension {
    let manifest: ExtensionManifest
    let signature: ExtensionSignature
    let moduleType: any HSModuleAPI.Type
    /// The path of the extension's binary, as the Objective-C runtime knows it
    let imagePath: String
}

/// Loads third-party extensions: bundles of native code, built against the HammerspoonSDK
/// framework, that scripts load with `require('ext:<name>')`.
///
/// Before any of an extension's code runs, it checks that:
/// - extensions are turned on in Settings (they're off by default),
/// - the bundle's Info.plist names it, and asks for an SDK version this app provides,
/// - its code signature is valid,
/// - its code runs on this Mac,
/// - it doesn't contain its own copy of the SDK, and
/// - the user has allowed this exact build to load (they're asked the first time, and again
///   whenever it changes).
///
/// Once it's loaded, it checks that its classes don't clash with existing ones and that its
/// JSExport methods don't leak what they return. An extension that fails those can't be unloaded,
/// so it stays unusable until Hammerspoon 2 restarts.
///
/// Module instances are created per engine by `ModuleRoot.extensionModule(named:)`; this only
/// loads code, once per process.
final class ExtensionLoader {
    static let shared = ExtensionLoader(
        searchPaths: {
            ExtensionSearchPaths.installed(userDirectory: SettingsManager.shared.extensionsDirectory,
                                           spoonsDirectory: SpoonManager.shared.spoonsDirectory)
        },
        isEnabled: { SettingsManager.shared.allowExtensions }
    )

    private let searchPaths: () -> ExtensionSearchPaths
    private let isEnabled: () -> Bool
    private let approver: any ExtensionApprover
    private let approvals: ExtensionApprovals
    private let hostSDKVersion: HSSDKVersion
    private let hostOSVersion: BuildVersion

    private var loaded: [String: LoadedExtension] = [:]

    /// Extensions whose code loaded but can't be used, and why
    private var unusable: [String: ExtensionError] = [:]

    /// The cdhash of each loaded extension's bundle when we last warned that it had changed, so
    /// each change is only reported once
    private var reportedChanges: [String: String] = [:]

    /// The classes in loaded extensions whose JSExport members return objects, for
    /// `NullReturnsInstaller` to wrap in each new context
    private(set) var exportedClasses: [NullReturnsInstaller.ExportedClass] = []

    /// - Parameters:
    ///   - searchPaths: Where extension bundles are found
    ///   - isEnabled: Whether extensions may be loaded at all
    ///   - approver: Asks the user to allow an extension
    ///   - approvals: The builds the user has allowed
    ///   - hostSDKVersion: The SDK version this app provides
    ///   - hostOSVersion: The version of macOS extensions must run on
    init(searchPaths: @escaping () -> ExtensionSearchPaths,
         isEnabled: @escaping () -> Bool,
         approver: any ExtensionApprover = AlertExtensionApprover(),
         approvals: ExtensionApprovals = ExtensionApprovals(),
         hostSDKVersion: HSSDKVersion = HSSDK.version,
         hostOSVersion: BuildVersion = .currentOS) {
        self.searchPaths = searchPaths
        self.isEnabled = isEnabled
        self.approver = approver
        self.approvals = approvals
        self.hostSDKVersion = hostSDKVersion
        self.hostOSVersion = hostOSVersion
    }

    /// Loads an extension's code, if it isn't loaded already.
    /// - Parameter name: The extension's name
    /// - Throws: `ExtensionError` if the extension can't be loaded or used
    /// - Returns: The loaded extension
    func load(named name: String) throws(ExtensionError) -> LoadedExtension {
        guard isEnabled() else { throw .disabled }
        if let failure = unusable[name] { throw failure }
        if let existing = loaded[name] {
            // Its code is loaded for good, but if the user has since removed their approval in
            // Settings, they're asked again before a config can use it
            try ensureApproved(existing.manifest, signature: existing.signature)
            warnIfChanged(existing)
            return existing
        }

        guard ExtensionManifest.isValidName(name) else { throw .invalidName(name) }
        let location = try searchPaths().locate(name)
        let manifest = try ExtensionManifest.read(name: name, in: location.directory, hostSDKVersion: hostSDKVersion,
                                                  spoonName: location.spoon)
        let signature = try inspect(manifest)
        try ensureApproved(manifest, signature: signature)

        do {
            let extensionInfo = try loadCode(of: manifest, signature: signature)
            loaded[name] = extensionInfo
            AKInfo("Loaded extension \(name) (SDK \(manifest.sdkVersion), signed by \(signature.signerName ?? "an ad-hoc signature"))")
            return extensionInfo
        } catch {
            unusable[name] = error
            throw error
        }
    }

    /// Checks every extension a Spoon comes with, as `load(named:)` would before asking the user,
    /// without asking or loading anything. Used when a Spoon is installed, so a broken extension
    /// is reported then, rather than when a config first requires it.
    /// - Parameter spoon: The Spoon's directory
    /// - Throws: `ExtensionError` for the first extension that couldn't be loaded
    func checkExtensions(inSpoonAt spoon: URL) throws(ExtensionError) {
        let directory = spoon.appendingPathComponent(ExtensionSearchPaths.spoonExtensionsFolder, isDirectory: true)
        let bundles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles])) ?? []
        for bundle in bundles where bundle.pathExtension == ExtensionManifest.bundleExtension {
            let manifest = try ExtensionManifest.read(name: bundle.deletingPathExtension().lastPathComponent, in: directory,
                                                      hostSDKVersion: hostSDKVersion, spoonName: spoon.lastPathComponent)
            _ = try inspect(manifest)
        }
    }

    /// Whether an extension's code has been loaded into the process
    func isLoaded(_ name: String) -> Bool {
        loaded[name] != nil
    }

    // MARK: - Private

    /// Loads the bundle's code and checks it can be used. Once this has started, the code is in
    /// the process for good, so any failure makes the extension unusable until restart.
    private func loadCode(of manifest: ExtensionManifest, signature: ExtensionSignature) throws(ExtensionError) -> LoadedExtension {
        let name = manifest.name
        guard let bundle = Bundle(url: manifest.bundleURL) else {
            throw .loadFailed(name: name, reason: "it isn't a bundle")
        }
        do {
            try bundle.loadAndReturnError()
        } catch {
            throw .loadFailed(name: name, reason: error.localizedDescription)
        }

        // The bundle could have been replaced between checking its signature and loading it
        guard ExtensionSignature.readUnverified(bundleAt: manifest.bundleURL)?.cdHash == signature.cdHash else {
            throw .invalidSignature(name: name, reason: "it changed while it was being loaded")
        }

        guard let executable = bundle.executableURL, let image = Self.loadedImage(at: executable) else {
            throw .loadFailed(name: name, reason: "its code isn't loaded after loading the bundle")
        }

        // Checked before looking up any class by name, since a clashing name finds the other class
        let classes = Self.classes(inImage: image)
        let collisions = classes.filter { $0.isShadowed }.map(\.name)
        guard collisions.isEmpty else {
            throw .classCollision(name: name, classes: collisions.sorted())
        }

        guard let principalClass = classes.first(where: { $0.name == manifest.principalClassName })?.cls else {
            throw .loadFailed(name: name, reason: "its principal class, \(manifest.principalClassName), isn't in the bundle")
        }
        guard let moduleType = principalClass as? any HSModuleAPI.Type else {
            throw .invalidPrincipalClass(name: name, className: manifest.principalClassName)
        }

        let leaking = Self.retainedResultSelectors(of: classes.map(\.cls))
        guard leaking.isEmpty else {
            throw .retainedResultMethods(name: name, selectors: leaking)
        }

        exportedClasses += NullReturnsInstaller.findExportedClasses(inImage: image)
        return LoadedExtension(manifest: manifest, signature: signature, moduleType: moduleType, imagePath: image)
    }

    /// Checks the extension's signature, and that it can run here, without loading it
    /// - Returns: Its verified signature
    private func inspect(_ manifest: ExtensionManifest) throws(ExtensionError) -> ExtensionSignature {
        let signature = try ExtensionSignature.verify(bundleAt: manifest.bundleURL, name: manifest.name)
        try checkCanRun(manifest)
        return signature
    }

    /// Checks, without loading it, that the extension's code can run here, and that it doesn't
    /// bring its own copy of the SDK. These are checked
    /// before the user is asked to allow it, since they'd make it fail whatever the answer.
    private func checkCanRun(_ manifest: ExtensionManifest) throws(ExtensionError) {
        let name = manifest.name

        // A second copy of the SDK would define all its classes a second time
        if let copy = Self.bundledSDK(in: manifest.bundleURL) {
            throw .bundlesSDK(name: name, at: copy)
        }

        let binary: ExtensionBinary
        do {
            binary = try ExtensionBinary.read(at: manifest.executableURL)
        } catch {
            throw .unsupportedBinary(name: name, reason: "its code, \(manifest.executableURL.lastPathComponent), isn't a 64-bit Mach-O binary")
        }
        guard binary.architectures.contains(ExtensionBinary.hostArchitecture) else {
            throw .unsupportedBinary(name: name, reason: "its code isn't built for this Mac's processor")
        }
        if let minimumOS = binary.minimumOS, hostOSVersion < minimumOS {
            throw .requiresNewerMacOS(name: name, required: minimumOS, current: hostOSVersion)
        }
    }

    /// A HammerspoonSDK.framework anywhere inside a bundle
    private static func bundledSDK(in bundle: URL) -> URL? {
        let contents = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil)
        while let url = contents?.nextObject() as? URL {
            if url.lastPathComponent == "HammerspoonSDK.framework" {
                return url
            }
        }
        return nil
    }

    /// Asks the user to allow the extension, unless they already have
    private func ensureApproved(_ manifest: ExtensionManifest, signature: ExtensionSignature) throws(ExtensionError) {
        guard !approvals.isApproved(manifest.name, signature: signature) else { return }
        guard approver.approve(manifest, signature: signature) else { throw .notApproved(name: manifest.name) }
        approvals.approve(manifest.name, signature: signature)
    }

    private func warnIfChanged(_ loadedExtension: LoadedExtension) {
        let name = loadedExtension.manifest.name
        guard let current = ExtensionSignature.readUnverified(bundleAt: loadedExtension.manifest.bundleURL),
              current.cdHash != loadedExtension.signature.cdHash,
              reportedChanges[name] != current.cdHash else { return }
        reportedChanges[name] = current.cdHash
        AKWarning("The extension \(name) has changed since it was loaded. Restart Hammerspoon 2 to use the new version.")
    }

    /// The path the Objective-C runtime knows a loaded binary by, which may differ from `url` by
    /// symlinks (such as /var and /private/var)
    private static func loadedImage(at url: URL) -> String? {
        let target = url.resolvingSymlinksInPath().path
        var count: UInt32 = 0
        let names = unsafe objc_copyImageNames(&count)
        defer { unsafe free(UnsafeMutableRawPointer(names)) }
        return unsafe UnsafeBufferPointer(start: names, count: Int(count))
            .lazy
            .map { unsafe String(cString: $0) }
            .first { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == target }
    }

    /// The classes in a binary, each with whether the Objective-C runtime resolves its name to a
    /// class in another binary, which happens when two binaries define a class with the same name.
    private static func classes(inImage image: String) -> [(name: String, cls: AnyClass, isShadowed: Bool)] {
        var count: UInt32 = 0
        guard let names = unsafe objc_copyClassNamesForImage(image, &count) else { return [] }
        defer { unsafe free(UnsafeMutableRawPointer(names)) }
        return unsafe UnsafeBufferPointer(start: names, count: Int(count)).compactMap { cName in
            guard let cls = unsafe objc_getClass(cName) as? AnyClass else { return nil }
            let owner = unsafe class_getImageName(cls).map { unsafe String(cString: $0) }
            return (unsafe String(cString: cName), cls, owner != image)
        }
    }

    /// The JSExport selectors that return an object with a retain JavaScriptCore never releases,
    /// because they're in the alloc/new/copy/mutableCopy method families (#309).
    static func retainedResultSelectors(of classes: [AnyClass]) -> [String] {
        guard let jsExport = unsafe objc_getProtocol("JSExport") else { return [] }
        var result = Set<String>()
        for cls in classes {
            for proto in NullReturnsInstaller.exportedProtocols(of: cls, jsExport: jsExport) {
                for isInstance in [true, false] {
                    var count: UInt32 = 0
                    guard let methods = unsafe protocol_copyMethodDescriptionList(proto, true, isInstance, &count) else { continue }
                    defer { unsafe free(methods) }
                    for unsafe method in unsafe UnsafeBufferPointer(start: methods, count: Int(count)) {
                        guard let selector = unsafe method.name, unsafe NullReturnsInstaller.returnsObject(method.types) else { continue }
                        let selectorName = NSStringFromSelector(selector)
                        if isInRetainedFamily(selectorName) {
                            result.insert(selectorName)
                        }
                    }
                }
            }
        }
        return result.sorted()
    }

    /// Whether a selector is in a method family whose results are returned retained: ignoring
    /// leading underscores, it starts with alloc, new, copy or mutableCopy, followed by anything
    /// other than a lowercase letter.
    static func isInRetainedFamily(_ selector: String) -> Bool {
        let name = selector.drop { $0 == "_" }
        return ["alloc", "new", "copy", "mutableCopy"].contains { family in
            guard name.hasPrefix(family) else { return false }
            guard let next = name.dropFirst(family.count).first else { return true }
            return !next.isLowercase
        }
    }
}
