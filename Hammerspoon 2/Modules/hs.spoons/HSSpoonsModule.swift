//
//  HSSpoonsModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import JavaScriptCoreExtras

/// Load, install and update Spoons - packaged, reusable pieces of configuration.
///
/// Spoons live in the `Spoons` directory inside your config directory. Every Spoon you load is
/// also available on `hs.spoons` under its name, so `hs.spoons.load("Greeter")` makes
/// `hs.spoons.Greeter` available to the rest of your config. That's why a Spoon can't be named
/// after one of this module's own methods or properties.
///
/// Spoons can be installed from any GitHub repository (`"owner/repo"`), or from a zip file at any
/// `https://` URL. There's no central list of Spoons: you choose where each one comes from, so
/// only install Spoons from sources you trust. Pin the version you install with `ref` (a GitHub
/// tag or commit) or `sha256` (for a zip URL), and nothing changes until you choose to.
///
/// ## Quick start
///
/// ```js
/// // Installs Greeter the first time this runs, then loads it, configures it and starts it
/// hs.spoons.use("Greeter", {
///     source: "jane/hs2-spoons",
///     ref: "v1.2.0",
///     config: { message: "Time for a break!" },
///     start: true
/// })
/// ```
@objc protocol HSSpoonsModuleAPI: JSExport {
    /// Load an installed Spoon by name, or a Spoon from any directory with the `path` option. A
    /// Spoon must contain a well-formed `spoon.json` (with
    /// non-empty `name`, `author`, `version`, and `description` fields) and an `init.js`, or
    /// loading fails with an exception. `init.js` is loaded through the same `require()` used for
    /// the rest of your config, so it can itself `require()` further files from within the
    /// Spoon's own directory using relative paths. On success, the Spoon is also stored on
    /// `hs.spoons` under its name, so other code can reach it without loading it again.
    ///
    /// `init.js` must set `module.exports` to an object (not a function) - loading fails with an
    /// exception otherwise. Its `name`, `author`,
    /// `description`, and `version` properties are then set from `spoon.json`, overwriting any
    /// of the same name the Spoon's own `init.js` set, so that information is always present and
    /// always reflects what's on disk (a warning is logged if `spoon.json`'s `name` doesn't
    /// match the Spoon's directory name). If the resulting object has an `init()` method, it's called
    /// automatically (with `this` bound to the object) before `load()` returns - matching
    /// Hammerspoon 1's behavior. An exception thrown from `init()` fails the load: nothing is
    /// stored on `hs.spoons`, and `load()` throws. Unlike `init.js` itself (which `require()`
    /// only ever evaluates once), `init()` runs again on every `load()` call for the same Spoon,
    /// since the same cached object is returned each time - write it to be safe to call more
    /// than once, or do one-time setup at `init.js`'s top level instead.
    ///
    /// If the object has a `bindings` object (its actions, keyed by name), it's given a generic
    /// `bindHotkeys(mapping)` before `init()` runs, which binds the hotkeys in `mapping` (e.g.
    /// `{ show: [["cmd", "alt"], "g"] }`) to those actions, and an `unbindHotkeys(actions)` that
    /// unbinds them again. These replace any `bindHotkeys()` and `unbindHotkeys()` the Spoon
    /// exports itself. A Spoon without `bindings` keeps its own, if it has them. See the Spoons
    /// guide for the details.
    ///
    /// `path` is for developing a Spoon: it loads the Spoon straight from that directory (such as
    /// a `.spoon2` bundle in your own checkout of its repository), instead of from `Spoons/`, so
    /// reloading your config picks up your changes. Nothing is installed or copied, and a Spoon
    /// of the same name that's installed is ignored. A warning is logged each time, so a config
    /// that still points at a development copy doesn't go unnoticed.
    ///
    /// A Spoon whose `spoon.json` has a `minimumHSVersion` isn't loaded by an older Hammerspoon 2
    /// (see `hs.appinfo.version`): `init.js` isn't run, and `load()` throws, naming both versions.
    ///
    /// The exception's `code` is `ENOTINSTALLED` if there's no such Spoon, `ENOTFOUND` if `path`
    /// isn't a directory, `EINVALIDARG` if the name can't be a Spoon's or an option is malformed,
    /// `EINVALIDSPOON` if the Spoon is malformed, or `EVERSION` if it needs a newer Hammerspoon 2.
    /// An exception thrown by the Spoon's own code is
    /// passed on as it is.
    /// - Parameter name: The Spoon's name, matching its directory name under `Spoons/`. It's also the name it's stored under on `hs.spoons`.
    /// - Parameter options?: Where to load the Spoon from
    ///   - path?: {string} A directory to load the Spoon from instead of `Spoons/`. A relative path
    ///     is relative to your config directory, and `~` is your home directory.
    /// - Returns: {Object} Whatever the Spoon's `init.js` assigned to `module.exports`
    /// - Throws: true
    /// - Example:
    /// ```js
    /// try {
    ///     const Greeter = hs.spoons.load("Greeter")
    ///     console.log(Greeter.version)
    ///     // ...later, from anywhere...
    ///     hs.spoons.Greeter.show()
    /// } catch (err) {
    ///     console.error(err.message)
    /// }
    ///
    /// // While working on a Spoon, load it from your own copy of it
    /// hs.spoons.load("MySpoon", { path: "~/src/my-spoons/MySpoon.spoon2" })
    /// ```
    @objc func load(_ name: String, _ options: [String: Any]?) -> JSValue?

    /// Download a Spoon and install it into the `Spoons` directory. It isn't loaded: call
    /// `hs.spoons.load()` (or use `hs.spoons.use()`, which does both) once it's installed.
    ///
    /// The source is downloaded as a zip file. Its Spoons are every `*.spoon2` directory at its top
    /// level or in a `Spoons` directory, or, if there are none, the whole archive, if it's a single
    /// Spoon. An archive that holds a single directory, as a repository's does, is looked inside.
    ///
    /// The Promise rejects with an `Error` whose `code` says what went wrong: `EINVALIDARG`,
    /// `ENOTFOUND` (no such repository, ref, URL, or Spoon in the archive), `ENETWORK`,
    /// `EINTEGRITY` (the download didn't match `sha256`), `EINVALIDSPOON`, `EEXISTS`, or `EIO` (for
    /// anything else, such as failing to write the Spoon to disk).
    /// - Parameter name: The name of the Spoon to install
    /// - Parameter options: Where to install the Spoon from
    ///   - source: {string} A GitHub repository (`"owner/repo"` or its `https://github.com/...` URL)
    ///     or the `https://` URL of a zip file
    ///   - ref?: {string} A branch, tag or commit to install from (GitHub only; the default branch
    ///     if omitted)
    ///   - sha256?: {string} The expected SHA-256 of the download
    ///   - force?: {boolean} `true` replaces a Spoon that's already installed, rather than failing
    /// - Returns: {Promise<{name: string, version: string, author: string, description: string, source: string, ref: string | null, commit: string | null}>} Resolves with the installed Spoon's details
    /// - Example:
    /// ```js
    /// hs.spoons.install("Greeter", { source: "jane/hs2-spoons", ref: "v1.2.0" })
    ///     .then(info => console.log(`Installed ${info.name} ${info.version}`))
    ///     .catch(err => console.error(`${err.code}: ${err.message}`))
    /// ```
    @objc func install(_ name: String, _ options: [String: Any]?) -> JSPromise?

    /// List the Spoons that can be installed from a source, without installing anything.
    /// - Parameter source: A GitHub repository (`"owner/repo"` or its `https://github.com/...` URL) or the `https://` URL of a zip file
    /// - Parameter options?: Where to look, as for `install()`
    ///   - ref?: {string} A branch, tag or commit to look in (GitHub only; the default branch if
    ///     omitted)
    ///   - sha256?: {string} The expected SHA-256 of the download
    /// - Returns: {Promise<{name: string, version: string, author: string, description: string}[]>} Resolves with the Spoons found
    /// - Example:
    /// ```js
    /// hs.spoons.available("jane/hs2-spoons").then(spoons => {
    ///     spoons.forEach(s => console.log(`${s.name} ${s.version}: ${s.description}`))
    /// })
    /// ```
    @objc func available(_ source: String, _ options: [String: Any]?) -> JSPromise?

    /// Update an installed Spoon: download it again from where it was installed from (the same
    /// source, ref and URL), and reinstall it if its version has changed. A Spoon installed from
    /// a pinned tag, commit or versioned URL doesn't change; install the newer one with
    /// `install(name, { ..., force: true })` instead.
    ///
    /// Besides the codes `install()` uses, the Promise rejects with `ENOTINSTALLED`, `ENOSOURCE`
    /// for a Spoon that wasn't installed by `install()` (or was since replaced some other way, such
    /// as by opening a `.spoon2` file), or `ECANCELED` if the Spoon was reinstalled while the
    /// update was downloading.
    /// - Parameter name: The name of the installed Spoon
    /// - Returns: {Promise<boolean>} Resolves with true if the Spoon was updated, or false if it was already up to date
    /// - Example:
    /// ```js
    /// hs.spoons.update("Greeter")
    ///     .then(updated => { if (updated) console.log("Updated Greeter") })
    ///     .catch(err => console.error(`Greeter: ${err.message}`))
    /// ```
    @objc func update(_ name: String) -> JSPromise?

    /// Update every installed Spoon, as `update()` does, logging each one to the Console as it's
    /// done, and then a summary. Spoons installed from the same source share one download, and
    /// different sources are downloaded one at a time. Spoons installed some other way than by
    /// `install()` (such as by opening a `.spoon2` file) are skipped, since there's nowhere to
    /// update them from. A Spoon that fails to update doesn't stop the others. `isUpdating` is
    /// true until they've all finished.
    ///
    /// Typing `hs.spoons.updateAll()` into the Console is enough: the updates start straight away,
    /// and their progress is logged there. The returned Promise is for code that wants the
    /// results. It never rejects: a Spoon that couldn't be updated has a status of `"failed"`, and
    /// an `error` with the code and message `update()` would have rejected with.
    /// - Returns: {Promise<{name: string, status: "updated" | "upToDate" | "skipped" | "failed", error: {code: string, message: string} | null}[]>} Resolves with what happened to each installed Spoon, sorted by name
    /// - Example:
    /// ```js
    /// hs.spoons.updateAll().then(results => {
    ///     const updated = results.filter(r => r.status === "updated").map(r => r.name)
    ///     if (updated.length > 0) hs.notify.show("Spoons updated", updated.join(", "))
    /// })
    /// ```
    @objc func updateAll() -> JSPromise?

    /// Whether `update()` or `updateAll()` is running. It stays true for the whole of an
    /// `updateAll()`.
    /// - Example:
    /// ```js
    /// if (!hs.spoons.isUpdating) hs.spoons.updateAll()
    /// ```
    @objc var isUpdating: Bool { get }

    /// Remove an installed Spoon. If it's already loaded, it keeps running until your config is
    /// reloaded, so stop it first if it has a `stop()` method.
    /// - Parameter name: The name of the installed Spoon
    /// - Returns: true if the Spoon was removed, or false if it wasn't installed
    /// - Throws: true
    /// - Example:
    /// ```js
    /// hs.spoons.uninstall("Greeter")
    /// ```
    @objc func uninstall(_ name: String) -> Bool

    /// List the installed Spoons. Those installed by `install()` also say where they came from.
    /// - Returns: {{name: string, version: string, author: string, description: string, source?: string, ref?: string | null, commit?: string | null}[]} The installed Spoons, sorted by name
    /// - Example:
    /// ```js
    /// hs.spoons.installed().forEach(s => console.log(`${s.name} ${s.version} from ${s.source ?? "a file"}`))
    /// ```
    @objc func installed() -> [[String: Any]]

    // Set by hs.spoons.js. Must be pre-declared properties, or JSC drops them on GC (issue #185).
    /// SKIP_DOCS
    @objc var use: JSFunction? { get set }
    /// SKIP_DOCS
    @objc var _installBindHotkeys: JSFunction? { get set }
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpoonsModule: NSObject, HSModuleAPI, HSSpoonsModuleAPI {
    var moduleName = "hs.spoons"
    let engineID: UUID
    let installer: SpoonInstaller
    @objc var use: JSFunction?
    @objc var _installBindHotkeys: JSFunction?

    private let session: URLSession
    private var operations: [UUID: Task<Void, Never>] = [:]
    // How many update() and updateAll() calls haven't finished. Each counts from when it's called,
    // so isUpdating is true as soon as it returns, and updateAll() counts once for its whole run.
    private var activeUpdates = 0
    // Names stored on this module's JS wrapper by load(), which may be overwritten by loading
    // them again. Any other name the wrapper already has is one of the module's own members.
    private var loadedNames: Set<String> = []

    required convenience init(engineID: UUID) {
        self.init(engineID: engineID, spoonManager: .shared)
    }

    /// - Parameter fetch: Downloads a URL. Defaults to a URLSession owned by the module, which
    ///   `shutdown()` cancels.
    init(engineID: UUID, spoonManager: SpoonManager, fetch: SpoonFetcher? = nil) {
        self.engineID = engineID
        session = URLSession(configuration: .ephemeral)
        installer = SpoonInstaller(spoonManager: spoonManager, fetch: fetch ?? SpoonInstaller.fetcher(using: session))
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {
        for operation in operations.values {
            operation.cancel()
        }
        operations.removeAll()
        session.invalidateAndCancel()
        loadedNames.removeAll()
        use = nil
        _installBindHotkeys = nil
    }

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        "<\(moduleName): \(loadedNames.count) loaded>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    // MARK: - Loading

    @objc func load(_ name: String, _ options: [String: Any]?) -> JSValue? {
        guard let context = JSContext.current() else { return nil }

        func fail(_ message: String, code: SpoonInstallError.Code = .invalidSpoon) -> JSValue? {
            let error = JSValue(newErrorFromMessage: "hs.spoons.load(): \(message)", in: context)
            error?.setValue(code.rawValue, forProperty: "code")
            context.exception = error
            return nil
        }

        guard SpoonManager.isValidSpoonName(name) else {
            return fail(SpoonImportError.invalidName(name).localizedDescription, code: .invalidArgument)
        }
        guard let namespace = JSValue(object: self, in: context) else {
            return fail("hs.spoons is not available")
        }
        if !loadedNames.contains(name), namespace.hasProperty(name) {
            return fail("'\(name)' can't be loaded, because hs.spoons.\(name) is part of hs.spoons itself", code: .invalidArgument)
        }

        let path: String?
        do {
            path = try Options(options).string("path")
        } catch let error as SpoonInstallError {
            return fail(error.message, code: error.code)
        } catch {
            return fail(error.localizedDescription, code: .invalidArgument)
        }

        let spoonDir: URL
        if let path {
            spoonDir = developmentDirectory(path)
            let isDirectory = try? spoonDir.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            guard isDirectory == true else {
                return fail("'\(name)' can't be loaded from \(spoonDir.path), because it isn't a directory", code: .notFound)
            }
            AKWarning("hs.spoons: loading '\(name)' from \(spoonDir.path), not from \(installer.spoonManager.spoonsDirectory.path)")
        } else {
            spoonDir = installer.spoonManager.spoonsDirectory.appendingPathComponent(name)
        }
        let initJSURL = spoonDir.appendingPathComponent("init.js")

        let metadata: SpoonMetadata
        do {
            metadata = try installer.spoonManager.validateSpoon(at: spoonDir)
        } catch {
            if path == nil, !installer.isInstalled(name) {
                return fail("No Spoon named '\(name)' is installed in \(installer.spoonManager.spoonsDirectory.path)", code: .notInstalled)
            }
            return fail("'\(name)' \(error.localizedDescription)")
        }

        if let failure = installer.spoonManager.versionRequirementFailure(for: metadata) {
            return fail(failure, code: .unsupportedVersion)
        }

        guard let requireFn = context.globalObject.objectForKeyedSubscript("require"), !requireFn.isUndefined else {
            return fail("require() is not available")
        }

        // If init.js itself throws, that's the exception we want visible to our caller -
        // context.exception is already left set to it by callCapturingException.
        let result = context.callCapturingException {
            requireFn.call(withArguments: [initJSURL.path])
        }
        if context.exception != nil {
            return result
        }

        guard let result, result.isObject, !result.isFunction else {
            return fail("'\(name)' must set module.exports to an object")
        }

        if metadata.name != name {
            AKWarning("hs.spoons: '\(name)' has the name '\(metadata.name)' in its spoon.json, which doesn't match the name it was loaded as")
        }

        // Authoritative from spoon.json, so these always reflect it even if the Spoon's own
        // init.js also happens to set properties of the same name.
        result.setValue(metadata.name, forProperty: "name")
        result.setValue(metadata.author, forProperty: "author")
        result.setValue(metadata.description, forProperty: "description")
        result.setValue(metadata.version, forProperty: "version")

        // A Spoon that exports `bindings` gets a generic bindHotkeys() and unbindHotkeys() for them,
        // in place of any of its own. Before init(), so init() can use them too.
        if let installBindHotkeys = _installBindHotkeys {
            _ = context.callCapturingException {
                installBindHotkeys.call(withArguments: [result, metadata.name])
            }
            if context.exception != nil {
                return nil
            }
        }

        // Matches v1: call init() automatically if the Spoon defines one.
        if let initFn = result.objectForKeyedSubscript("init"), !initFn.isUndefined {
            _ = context.callCapturingException {
                result.invokeMethod("init", withArguments: [])
            }
            if context.exception != nil {
                return nil
            }
        }

        namespace.setValue(result, forProperty: name)
        loadedNames.insert(name)
        return result
    }

    // MARK: - Installing

    @objc func install(_ name: String, _ options: [String: Any]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return run(in: context) { [installer] in
            let options = Options(options)
            guard let source = try options.string("source") else {
                throw SpoonInstallError(.invalidArgument, "install() needs a source: a GitHub repository (\"owner/repo\") or a zip URL")
            }
            let installed = try await installer.install(
                name: name,
                source: source,
                ref: try options.string("ref"),
                sha256: try options.string("sha256"),
                force: try options.bool("force")
            )
            return installed.dictionary
        }
    }

    @objc func available(_ source: String, _ options: [String: Any]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        return run(in: context) { [installer] in
            let options = Options(options)
            let spoons = try await installer.available(
                source: source,
                ref: try options.string("ref"),
                sha256: try options.string("sha256")
            )
            return spoons.map { InstalledSpoon(name: $0.name, metadata: $0.metadata, record: nil).dictionary }
        }
    }

    @objc func update(_ name: String) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        activeUpdates += 1
        return run(in: context) { [weak self, installer] in
            defer { self?.activeUpdates -= 1 }
            return try await installer.update(name: name)
        }
    }

    @objc func updateAll() -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        AKInfo("hs.spoons.updateAll(): checking for updates")
        activeUpdates += 1
        return run(in: context) { [weak self, installer] in
            defer { self?.activeUpdates -= 1 }
            let results = try await installer.updateAll { result in
                switch result.status {
                case .updated:
                    break // update() has already logged the old and new versions
                case .upToDate:
                    AKInfo("hs.spoons.updateAll(): \(result.name) is up to date")
                case .skipped:
                    AKInfo("hs.spoons.updateAll(): skipped \(result.name), which wasn't installed by hs.spoons.install()")
                case .failed:
                    let error = result.error.map { "\($0.message) (\($0.code.rawValue))" } ?? "unknown error"
                    AKError("hs.spoons.updateAll(): couldn't update \(result.name): \(error)")
                }
            }
            let count = { (status: SpoonUpdateResult.Status) in results.count { $0.status == status } }
            let updated = results.filter { $0.status == .updated }.map(\.name)
            let updatedNames = updated.isEmpty ? "" : " (\(updated.joined(separator: ", ")))"
            AKInfo("hs.spoons.updateAll(): finished: \(updated.count) updated\(updatedNames), \(count(.upToDate)) up to date, \(count(.skipped)) skipped, \(count(.failed)) failed")
            return results.map(\.dictionary)
        }
    }

    @objc var isUpdating: Bool {
        activeUpdates > 0
    }

    @objc func uninstall(_ name: String) -> Bool {
        do {
            return try installer.uninstall(name: name)
        } catch {
            if let context = JSContext.current() {
                context.exception = JSValue(newErrorFromMessage: "hs.spoons.uninstall(): \(error.localizedDescription)", in: context)
            }
            return false
        }
    }

    @objc func installed() -> [[String: Any]] {
        installer.installed().map(\.dictionary)
    }

    // MARK: - Private

    /// The directory a `path` passed to `load()` names: relative to the config directory, with
    /// `~` expanded
    private func developmentDirectory(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let configDir = installer.spoonManager.spoonsDirectory.deletingLastPathComponent()
        return URL(filePath: expanded, directoryHint: .isDirectory, relativeTo: configDir).absoluteURL.standardizedFileURL
    }

    /// Runs `body` as a Promise in `context`, rejecting with a coded Error if it throws. The work
    /// is cancelled, and the Promise never settles, if the module shuts down first.
    private func run(in context: JSContext, _ body: @escaping @MainActor () async throws -> Any) -> JSPromise? {
        wrapAsyncInJSPromise(in: context) { [weak self] holder in
            guard let self else { return }
            let id = UUID()
            operations[id] = Task { [weak self] in
                defer { self?.operations[id] = nil }
                do {
                    let result = try await body()
                    guard !Task.isCancelled else { return }
                    holder.resolveWith(result)
                } catch is CancellationError {
                    return
                } catch let error as SpoonInstallError {
                    guard !Task.isCancelled else { return }
                    holder.rejectWith(code: error.code.rawValue, message: error.message)
                } catch {
                    guard !Task.isCancelled else { return }
                    holder.rejectWith(code: SpoonInstallError.Code.io.rawValue, message: error.localizedDescription)
                }
            }
        }
    }

    /// Reads typed values from an options object passed from JS
    private struct Options {
        let values: [String: Any]

        init(_ values: [String: Any]?) {
            self.values = values ?? [:]
        }

        func string(_ key: String) throws -> String? {
            guard let value = values[key], !(value is NSNull) else { return nil }
            guard let string = value as? String else {
                throw SpoonInstallError(.invalidArgument, "'\(key)' must be a string")
            }
            return string
        }

        func bool(_ key: String) throws -> Bool {
            guard let value = values[key], !(value is NSNull) else { return false }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw SpoonInstallError(.invalidArgument, "'\(key)' must be a boolean")
            }
            return number.boolValue
        }
    }
}
