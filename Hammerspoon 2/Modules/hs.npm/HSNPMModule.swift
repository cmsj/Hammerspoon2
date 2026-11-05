//
//  HSNPMModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - Declare our JavaScript API

/// Installs npm packages for your config without npm or node. It reads `package.json` and
/// `.npmrc` from your config directory, downloads each dependency from its registry, and
/// unpacks it into `node_modules` there, where `require("name")` finds it.
@objc protocol HSNPMModuleAPI: JSExport {
    /// Installs the `dependencies` listed in the `package.json` in your config directory, and
    /// theirs, into `node_modules` next to it, skipping any package already present in a
    /// version that satisfies the requested range. This also happens automatically before your
    /// config is loaded whenever a `package.json` exists, so you only need to call it yourself
    /// after editing `package.json` to pick up changes without a reload. Registries and credentials come from
    /// `.npmrc` in your config directory and in your home directory, so scoped packages
    /// (`@my-org/foo`) can come from a private registry such as GitHub Packages.
    /// - Returns: {Promise<string[]>} Resolves with every installed package as `name@version`,
    ///   or rejects with the reason the install failed.
    /// - Example:
    /// ```js
    /// hs.npm.install().then(pkgs => {
    ///     console.log("Installed: " + pkgs.join(", "))
    ///     const dayjs = require("dayjs")
    ///     console.log(dayjs().format())
    /// }).catch(err => console.error(err))
    /// ```
    @objc func install() -> JSPromise?
}

// MARK: - Implement the module

@_documentation(visibility: private)
@MainActor
@objc class HSNPMModule: NSObject, HSModuleAPI, HSNPMModuleAPI {
    var moduleName = "hs.npm"
    let engineID: UUID

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKGarbage("Init of \(moduleName): \(engineID)")
    }

    func shutdown() {}

    isolated deinit {
        AKGarbage("Deinit of \(moduleName): \(engineID)")
    }

    @objc func toString() -> String {
        "<\(moduleName)>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    @objc func install() -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let projectDir = SettingsManager.shared.configLocation.deletingLastPathComponent()
        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                do {
                    holder.resolveWith(try await NPMInstaller.install(projectDir: projectDir))
                } catch {
                    AKError("hs.npm.install(): \(error.localizedDescription)")
                    holder.rejectWith(error)
                }
            }
        }
    }
}
