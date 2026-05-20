//
//  HSTranslationModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
@unsafe @preconcurrency import Translation

/// Translate text between languages using the macOS on-device Translation framework.
///
/// Language identifiers use BCP-47 format (e.g. `"en"`, `"fr"`, `"zh-Hans"`).
/// Call `hs.translation.supportedLanguages()` to list every language the framework
/// recognises, and `hs.translation.status()` to check whether a specific pair is
/// installed and ready for offline use.
///
/// Language packs are downloaded through
/// **System Settings → General → Language & Region → Translation Languages**.
/// `hs.translation` cannot trigger downloads programmatically; `session()` returns
/// `null` when the requested pair is not yet installed.
///
/// ## Quick start
///
/// ```js
/// hs.translation.status("en", "fr").then(s => {
///     if (s === "installed") {
///         const session = hs.translation.session("en", "fr")
///         session.translate("Good morning").then(r => console.log(r))
///     } else {
///         console.log("Install en→fr in System Settings → Language & Region → Translation Languages")
///     }
/// })
/// ```
@objc protocol HSTranslationModuleAPI: JSExport {
    /// All language codes supported by the on-device translation engine.
    ///
    /// Resolves to an array of BCP-47 identifiers (e.g. `["ar", "de", "en", "es", "fr"]`).
    /// This covers every language the framework knows about, regardless of whether
    /// the packs are installed locally. Use `status()` to distinguish installed
    /// pairs from merely supported ones.
    ///
    /// - Returns: {Promise<string[]>} Resolves to an array of BCP-47 language code strings.
    /// - Example:
    /// ```js
    /// hs.translation.supportedLanguages().then(langs => {
    ///     console.log(langs.includes("fr")) // true
    /// })
    /// ```
    @objc func supportedLanguages() -> JSPromise?

    /// Check the installation status of a language pair.
    ///
    /// Resolves to one of three strings:
    /// - `"installed"` — downloaded and ready for offline translation.
    /// - `"supported"` — available but not yet downloaded.
    /// - `"unsupported"` — not available on this system.
    ///
    /// - Parameter sourceLanguage: BCP-47 code of the source language (e.g. `"en"`).
    /// - Parameter targetLanguage: BCP-47 code of the target language (e.g. `"fr"`).
    /// - Returns: {Promise<string>} Resolves to `"installed"`, `"supported"`, or `"unsupported"`.
    /// - Example:
    /// ```js
    /// hs.translation.status("en", "fr").then(s => console.log(s))
    /// // "installed"
    /// ```
    @objc func status(_ sourceLanguage: String, _ targetLanguage: String) -> JSPromise?

    /// Create a translation session for a language pair.
    ///
    /// Returns an `HSTranslationSession`, or `null` if the system is running macOS
    /// older than 26.0.
    ///
    /// - Parameter sourceLanguage: BCP-47 code of the source language (e.g. `"en"`).
    /// - Parameter targetLanguage: BCP-47 code of the target language (e.g. `"fr"`).
    /// - Returns: An `HSTranslationSession`, or `null` on unsupported versions of macOS.
    /// - Example:
    /// ```js
    /// const session = hs.translation.session("en", "fr")
    /// if (session) {
    ///     session.translate("Hello").then(r => console.log(r))
    /// } else {
    ///     console.log("Language pair not installed")
    /// }
    /// ```
    @objc func session(_ sourceLanguage: String, _ targetLanguage: String) -> HSTranslationSession?
}

@_documentation(visibility: private)
@MainActor
@objc class HSTranslationModule: NSObject, HSModuleAPI, HSTranslationModuleAPI {
    var name = "hs.translation"
    let engineID: UUID

    // Weak refs: sessions are released when JS GC drops them.
    // allObjects returns only live sessions; dead entries are compacted on each access.
    private var sessions = HSWeakObjectSet<HSTranslationSession>()

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    func shutdown() {
        sessions.allObjects.forEach { $0.cancel() }
        sessions.removeAllObjects()
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    // MARK: - HSTranslationModuleAPI

    @objc func supportedLanguages() -> JSPromise? {
        guard let context = JSContext.current() else {
            AKError("hs.translation.supportedLanguages: called outside a JS context")
            return nil
        }

        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                let langs = await LanguageAvailability().supportedLanguages
                holder.resolveWith(langs.map { $0.minimalIdentifier })
            }
        }
    }

    @objc func status(_ sourceLanguage: String, _ targetLanguage: String) -> JSPromise? {
        guard let context = JSContext.current() else {
            AKError("hs.translation.status: called outside a JS context")
            return nil
        }

        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                let source = Locale.Language(identifier: sourceLanguage)
                let target = Locale.Language(identifier: targetLanguage)
                let langStatus = await LanguageAvailability().status(from: source, to: target)
                switch langStatus {
                case .installed:
                    holder.resolveWith("installed")
                case .supported:
                    holder.resolveWith("supported")
                case .unsupported:
                    holder.resolveWith("unsupported")
                @unknown default:
                    holder.resolveWith("unsupported")
                }
            }
        }
    }

    @objc func session(_ sourceLanguage: String, _ targetLanguage: String) -> HSTranslationSession? {
        guard #available(macOS 26.0, *) else {
            AKWarning("hs.translation.session: TranslationSession.init(installedSource:target:) requires macOS 26.0 or later")
            return nil
        }
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let ts = TranslationSession(installedSource: source, target: target)

        let session = HSTranslationSession(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            session: ts
        )
        sessions.add(session)
        return session
    }
}
