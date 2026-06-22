//
//  HSTranslationSession.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
@unsafe @preconcurrency import Translation

/// JavaScript-visible API for a translation session bound to a specific language pair.
@objc protocol HSTranslationSessionAPI: HSTypeAPI, JSExport {
    /// The Swift type name, for JavaScript introspection.
    ///
    /// - Example:
    /// ```js
    /// const session = hs.translation.session("en", "fr")
    /// console.log(session.typeName) // "HSTranslationSession"
    /// ```
    @objc var typeName: String { get }

    /// BCP-47 identifier of the source language (e.g. `"en"`).
    ///
    /// - Example:
    /// ```js
    /// const session = hs.translation.session("en", "fr")
    /// console.log(session.sourceLanguage) // "en"
    /// ```
    @objc var sourceLanguage: String { get }

    /// BCP-47 identifier of the target language (e.g. `"fr"`).
    ///
    /// - Example:
    /// ```js
    /// const session = hs.translation.session("en", "fr")
    /// console.log(session.targetLanguage) // "fr"
    /// ```
    @objc var targetLanguage: String { get }

    /// Translate a string from the session's source language to its target language.
    ///
    /// - Parameter text: The text to translate.
    /// - Returns: {Promise<string>} A Promise resolving to the translated string,
    ///   or rejecting with an error message if translation fails.
    /// - Example:
    /// ```js
    /// const session = hs.translation.session("en", "fr")
    /// session.translate("Hello, world!").then(result => console.log(result))
    /// // "Bonjour le monde !"
    /// ```
    @objc func translate(_ text: String) -> JSPromise?
}

@_documentation(visibility: private)
@MainActor
@objc class HSTranslationSession: NSObject, HSTranslationSessionAPI {
    @objc var typeName = "HSTranslationSession"
    @objc let sourceLanguage: String
    @objc let targetLanguage: String

    private let translationSession: TranslationSession

    init(sourceLanguage: String, targetLanguage: String, session: TranslationSession) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.translationSession = session
        super.init()
        AKTrace("Init of HSTranslationSession: \(sourceLanguage) -> \(targetLanguage)")
    }

    @objc func translate(_ text: String) -> JSPromise? {
        guard let context = JSContext.current() else {
            AKError("hs.translation: translate() called outside a JS context")
            return nil
        }

        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                do {
                    let response = try await self.translationSession.translate(text)
                    holder.resolveWith(response.targetText)
                } catch {
                    holder.rejectWithMessage(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        if #available(macOS 26.0, *) {
            translationSession.cancel()
        }
    }

    isolated deinit {
        cancel()
        AKTrace("Deinit of HSTranslationSession: \(sourceLanguage) -> \(targetLanguage)")
    }
}
