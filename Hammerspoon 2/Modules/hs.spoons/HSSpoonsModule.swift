//
//  HSSpoonsModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

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
    /// Load an installed Spoon by name. A Spoon must contain a well-formed `spoon.json` (with
    /// non-empty `name`, `author`, `version`, and `description` fields) and an `init.js`, or
    /// loading fails with an exception. `init.js` is loaded through the same `require()` used for
    /// the rest of your config, so it can itself `require()` further files from within the
    /// Spoon's own directory using relative paths. On success, the Spoon is also stored on
    /// `hs.spoons` under its name, so other code can reach it without loading it again.
    ///
    /// `init.js` must set `module.exports` to an object (or a function, since functions are
    /// objects too) - loading fails with an exception otherwise. Its `author`, `description`,
    /// and `version` properties are then set from `spoon.json`, overwriting any of the same
    /// name the Spoon's own `init.js` set, so that information is always present and always
    /// reflects what's on disk. If the resulting object has an `init()` method, it's called
    /// automatically (with `this` bound to the object) before `load()` returns - matching
    /// Hammerspoon 1's behavior. An exception thrown from `init()` fails the load: nothing is
    /// stored on `hs.spoons`, and `load()` throws. Unlike `init.js` itself (which `require()`
    /// only ever evaluates once), `init()` runs again on every `load()` call for the same Spoon,
    /// since the same cached object is returned each time - write it to be safe to call more
    /// than once, or do one-time setup at `init.js`'s top level instead.
    ///
    /// The exception's `code` is `ENOTINSTALLED` if there's no such Spoon, `EINVALIDARG` if the name
    /// can't be a Spoon's, or `EINVALIDSPOON` if the Spoon is malformed. An exception thrown by the
    /// Spoon's own code is passed on as it is.
    /// - Parameter name: The Spoon's name, matching its directory name under `Spoons/`
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
    /// ```
    @objc func load(_ name: String) -> JSValue?

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
    /// - Parameter options: {{source: string, ref?: string, sha256?: string, force?: boolean}} `source` is a GitHub repository (`"owner/repo"` or its `https://github.com/...` URL) or the `https://` URL of a zip file. `ref` is a branch, tag or commit to install from (GitHub only; the default branch if omitted). `sha256` is the expected SHA-256 of the download. `force: true` replaces a Spoon that's already installed, rather than failing.
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
    /// - Parameter options?: {{ref?: string, sha256?: string}} As for `install()`
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
    /// // Update every Spoon that was installed from a source
    /// for (const spoon of hs.spoons.installed().filter(s => s.source)) {
    ///     hs.spoons.update(spoon.name)
    ///         .then(updated => { if (updated) console.log(`Updated ${spoon.name}`) })
    ///         .catch(err => console.error(`${spoon.name}: ${err.message}`))
    /// }
    /// ```
    @objc func update(_ name: String) -> JSPromise?

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
}

@_documentation(visibility: private)
@MainActor
@objc class HSSpoonsModule: NSObject, HSModuleAPI, HSSpoonsModuleAPI {
    var moduleName = "hs.spoons"
    let engineID: UUID
    let installer: SpoonInstaller
    @objc var use: JSFunction?

    private let session: URLSession
    private var operations: [UUID: Task<Void, Never>] = [:]
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

    @objc func load(_ name: String) -> JSValue? {
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

        let spoonDir = installer.spoonManager.spoonsDirectory.appendingPathComponent(name)
        let initJSURL = spoonDir.appendingPathComponent("init.js")

        let metadata: SpoonMetadata
        do {
            metadata = try installer.spoonManager.validateSpoon(at: spoonDir)
        } catch {
            if !installer.isInstalled(name) {
                return fail("No Spoon named '\(name)' is installed in \(installer.spoonManager.spoonsDirectory.path)", code: .notInstalled)
            }
            return fail("'\(name)' \(error.localizedDescription)")
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

        guard let result, result.isObject else {
            return fail("'\(name)' must set module.exports to an object")
        }

        // Authoritative from spoon.json, so these always reflect it even if the Spoon's own
        // init.js also happens to set properties of the same name.
        result.setValue(metadata.author, forProperty: "author")
        result.setValue(metadata.description, forProperty: "description")
        result.setValue(metadata.version, forProperty: "version")

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
        return run(in: context) { [installer] in
            try await installer.update(name: name)
        }
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
