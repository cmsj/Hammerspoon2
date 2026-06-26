//
//  HSOCRModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore
import Vision

/// Recognize text in images using Apple's Vision framework.
///
/// `hs.ocr` provides access to on-device text recognition without requiring
/// network access or any third-party dependencies. Pass a file path to
/// `recognizeText()` and receive back an `HSOCRResult` containing the full
/// recognized text and individual per-region observations with confidence
/// scores and normalized bounding boxes.
///
/// - Example:
/// ```js
/// // Basic: print all text found in an image
/// hs.ocr.recognizeText('/tmp/screenshot.png')
///     .then(result => {
///         console.log(result.text)
///     })
///     .catch(err => console.log('OCR failed: ' + err))
/// ```
///
/// - Example:
/// ```js
/// // Advanced: filter to high-confidence observations only
/// const result = await hs.ocr.recognizeText('/tmp/photo.png', {
///     minimumConfidence: 0.8,
///     recognitionLevel: 'accurate'
/// })
/// result.observations.forEach(obs => {
///     const b = obs.bounds
///     console.log(obs.text + ' at (' + b.x.toFixed(3) + ', ' + b.y.toFixed(3) + ') ' + b.w.toFixed(3) + 'x' + b.h.toFixed(3))
/// })
/// ```
@objc protocol HSOCRModuleAPI: JSExport {

    /// Recognize text in the image at the given file path.
    ///
    /// Returns a Promise that resolves with an `HSOCRResult` containing all
    /// recognized text and per-region observations. The image must exist on
    /// disk; URLs and data buffers are not supported.
    ///
    /// Recognition is performed on a background thread; the main thread is
    /// not blocked during the operation.
    ///
    /// The optional `options` object may contain:
    /// - `recognitionLevel` (`"accurate"` | `"fast"`, default `"accurate"`):
    ///   `"accurate"` uses a larger neural network for better results;
    ///   `"fast"` trades accuracy for speed.
    /// - `minimumConfidence` (number 0–1, default `0`):
    ///   Observations whose `confidence` is below this threshold are excluded
    ///   from `result.observations` (and therefore from `result.text`).
    /// - `languages` (array of BCP-47 strings, e.g. `["en-US", "fr-FR"]`):
    ///   Hints Vision toward specific languages. Use `supportedLanguages()` to
    ///   enumerate the available codes for the current device.
    /// - `automaticallyDetectsLanguage` (boolean, default `false`):
    ///   When `true`, Vision selects recognition languages automatically.
    ///   Overrides `languages` when set.
    ///
    /// - Parameter path: Absolute path to the image file.
    /// - Parameter options: Optional configuration object (see description).
    /// - Returns: {Promise<HSOCRResult>} Resolves with the recognition result.
    ///
    /// - Example:
    /// ```js
    /// // Async/await style
    /// async function getTextFromImage(imagePath) {
    ///     const result = await hs.ocr.recognizeText(imagePath)
    ///     return result.text
    /// }
    /// ```
    ///
    /// - Example:
    /// ```js
    /// // Promise chain style, with options
    /// hs.ocr.recognizeText('/tmp/image.png', { minimumConfidence: 0.75 })
    ///     .then(result => console.log('Found ' + result.observations.length + ' regions'))
    ///     .catch(err => console.log('Error: ' + err))
    /// ```
    @objc func recognizeText(_ path: String, _ options: [String: Any]?) -> JSPromise?

    /// Returns the BCP-47 language codes supported by the Vision text recognizer
    /// on this device.
    ///
    /// The set of languages varies between macOS versions and hardware. Call
    /// this at runtime to discover which codes are valid for the `languages`
    /// option passed to `recognizeText()`.
    ///
    /// - Returns: An array of BCP-47 language code strings (e.g. `["en-US", "fr-FR"]`).
    ///
    /// - Example:
    /// ```js
    /// const langs = hs.ocr.supportedLanguages()
    /// console.log('Supported languages: ' + langs.join(', '))
    /// ```
    @objc func supportedLanguages() -> [String]
}

/// Configuration parsed from the JS options object on the main actor.
/// `Sendable` so it can be captured into a `Task.detached` closure safely.
private struct OCRConfig: Sendable {
    var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    var minimumConfidence: Float = 0
    var languages: [String] = []
    var automaticallyDetectsLanguage: Bool = false

    init(from options: [String: Any]?) {
        guard let options else { return }

        if let level = options["recognitionLevel"] as? String {
            recognitionLevel = (level == "fast") ? .fast : .accurate
        }
        if let minConf = options["minimumConfidence"] as? Double {
            minimumConfidence = Float(minConf)
        }
        if let langs = options["languages"] as? [String] {
            languages = langs
        }
        if let autoDetect = options["automaticallyDetectsLanguage"] as? Bool {
            automaticallyDetectsLanguage = autoDetect
        }
    }
}

/// Raw observation data bridged across actor boundaries.
private struct RawObservation: Sendable {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

@_documentation(visibility: private)
@MainActor
@objc class HSOCRModule: NSObject, HSModuleAPI, HSOCRModuleAPI {
    var name = "hs.ocr"
    let engineID: UUID

    required init(engineID: UUID) {
        self.engineID = engineID
        super.init()
        AKTrace("Init of \(name): \(engineID)")
    }

    isolated deinit {
        AKTrace("Deinit of \(name): \(engineID)")
    }

    func shutdown() {
        AKTrace("Shutdown of \(name): \(engineID)")
    }

    // MARK: - HSOCRModuleAPI

    @objc func recognizeText(_ path: String, _ options: [String: Any]?) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let config = OCRConfig(from: options)
        let fileURL = URL(fileURLWithPath: path)

        return wrapAsyncInJSPromise(in: context) { holder in
            Task.detached(priority: .userInitiated) {
                do {
                    let raw = try Self.runRecognition(fileURL: fileURL, config: config)
                    await MainActor.run {
                        let observations = raw.map {
                            HSOCRObservation(text: $0.text, confidence: $0.confidence, boundingBox: $0.boundingBox)
                        }
                        holder.resolveWith(HSOCRResult(observations: observations))
                    }
                } catch {
                    await MainActor.run {
                        holder.rejectWithMessage(error.localizedDescription)
                    }
                }
            }
        }
    }

    @objc func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        let languages = (try? request.supportedRecognitionLanguages()) ?? []
        return languages
    }

    // MARK: - Private Vision work (nonisolated — runs on background Task)

    private nonisolated static func runRecognition(fileURL: URL, config: OCRConfig) throws -> [RawObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = config.recognitionLevel
        request.minimumTextHeight = 0
        if !config.languages.isEmpty {
            request.recognitionLanguages = config.languages
        }
        request.automaticallyDetectsLanguage = config.automaticallyDetectsLanguage

        let handler = VNImageRequestHandler(url: fileURL, options: [:])
        try handler.perform([request])

        guard let results = request.results else { return [] }
        return results.compactMap { observation -> RawObservation? in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= config.minimumConfidence else { return nil }
            return RawObservation(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
}
