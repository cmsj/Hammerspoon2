//
//  MultiRootFSModuleLoader.swift
//  Hammerspoon 2
//
//  Created by Codex on 28/12/2025.
//

import Foundation
import InternalESModuleForSwiftJavaScriptCore
import JavaScriptCore

@_documentation(visibility: private)
final class MultiRootFSModuleLoader: ESModuleLoaderDelegate {
    private let virtualMachine: JSVirtualMachine
    private var baseRoots: [URL]
    private var moduleCache: [URL: ESModuleScript] = [:]

    init(virtualMachine: JSVirtualMachine, baseURLs: [URL]) {
        self.virtualMachine = virtualMachine
        self.baseRoots = baseURLs.map { $0.standardizedFileURL }
    }

    func module(for url: URL) throws -> ESModuleScript? {
        guard let moduleURL = resolveModuleURL(url: url) else {
            return nil
        }

        if let cached = moduleCache[moduleURL] {
            return cached
        }

        let source = try String(contentsOf: moduleURL, encoding: .utf8)
        let module = try ESModuleScript(
            withSource: source,
            andSourceURL: moduleURL,
            andBytecodeCache: nil,
            inVirtualMachine: virtualMachine
        )
        moduleCache[moduleURL] = module
        return module
    }

    func fetchModule(
        in context: JSContext,
        identifier: String,
        resolve: @escaping (ESModuleScript) -> Void,
        reject: @escaping (JSValue) -> Void
    ) {
        guard let moduleURL = resolveModuleURL(identifier: identifier) else {
            reject(
                JSValue(
                    newErrorFromMessage: "Unable to resolve module identifier: \(identifier)",
                    in: context))
            return
        }

        do {
            guard let module = try module(for: moduleURL) else {
                reject(
                    JSValue(
                        newErrorFromMessage: "Unable to resolve module URL: \(moduleURL.path)",
                        in: context))
                return
            }
            resolve(module)
        } catch {
            reject(
                JSValue(
                    newErrorFromMessage: "Unable to load module \(moduleURL.path): \(error)",
                    in: context))
        }
    }

    private func resolveModuleURL(identifier: String) -> URL? {
        let candidate: URL
        if let url = URL(string: identifier), url.scheme != nil {
            guard url.isFileURL else {
                return nil
            }
            candidate = url
        } else {
            let expandedPath = NSString(string: identifier).expandingTildeInPath
            if expandedPath.hasPrefix("/") {
                candidate = URL(fileURLWithPath: expandedPath)
            } else {
                for root in baseRoots {
                    let probe = URL(fileURLWithPath: expandedPath, relativeTo: root)
                        .standardizedFileURL
                    if isWithinAllowedRoots(probe)
                        && FileManager.default.fileExists(atPath: probe.path)
                    {
                        return probe
                    }
                }
                return nil
            }
        }

        let normalized = candidate.standardizedFileURL
        return isWithinAllowedRoots(normalized) ? normalized : nil
    }

    private func resolveModuleURL(url: URL) -> URL? {
        guard url.isFileURL else {
            return nil
        }
        let normalized = url.standardizedFileURL
        return isWithinAllowedRoots(normalized) ? normalized : nil
    }

    private func isWithinAllowedRoots(_ url: URL) -> Bool {
        let path = url.path
        for root in baseRoots {
            let rootPath = root.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if path == rootPath || path.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }
    
    func willEvaluateModule(at key: URL) {
        
    }
}
