//
//  HSOCRResult.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// The result of a text recognition operation on an image.
///
/// An `HSOCRResult` is returned by `hs.ocr.recognizeText()` and bundles the
/// full recognized text together with an array of per-region observations,
/// each carrying its own confidence score and bounding box.
///
/// - Example:
/// ```js
/// const result = await hs.ocr.recognizeText('/tmp/image.png')
/// console.log('Full text: ' + result.text)
/// console.log('Regions found: ' + result.observations.length)
/// result.observations.forEach(obs => {
///     console.log(obs.text + ' (' + (obs.confidence * 100).toFixed(0) + '%)')
/// })
/// ```
@objc protocol HSOCRResultAPI: HSTypeAPI, JSExport {

    /// The Swift type name, for JavaScript introspection.
    ///
    /// - Example:
    /// ```js
    /// const result = await hs.ocr.recognizeText('/tmp/image.png')
    /// console.log(result.typeName) // "HSOCRResult"
    /// ```
    @objc var typeName: String { get }

    /// The full recognized text from the image, with each observation's text
    /// joined by newlines in the order Vision returned them.
    ///
    /// Use this when you only need the raw text and don't care about bounding
    /// boxes or per-region confidence scores.
    ///
    /// - Example:
    /// ```js
    /// const result = await hs.ocr.recognizeText('/tmp/receipt.png')
    /// const lines = result.text.split('\n')
    /// lines.forEach(line => console.log(line))
    /// ```
    @objc var text: String { get }

    /// The individual text observations that make up this result.
    ///
    /// Each entry in the array is an `HSOCRObservation` with its own `text`,
    /// `confidence`, and `bounds` properties. Observations are returned in the
    /// order Vision produced them (typically top-to-bottom, left-to-right, but
    /// this is image-dependent).
    ///
    /// - Example:
    /// ```js
    /// const result = await hs.ocr.recognizeText('/tmp/image.png')
    /// const confident = result.observations.filter(o => o.confidence > 0.9)
    /// console.log('High-confidence regions: ' + confident.length)
    /// confident.forEach(obs => {
    ///     const b = obs.bounds
    ///     console.log(obs.text + ' at x=' + b.x.toFixed(3) + ' y=' + b.y.toFixed(3))
    /// })
    /// ```
    @objc var observations: [HSOCRObservation] { get }
}

@_documentation(visibility: private)
@MainActor
@objc class HSOCRResult: NSObject, HSOCRResultAPI {
    @objc var typeName = "HSOCRResult"
    @objc let text: String
    @objc let observations: [HSOCRObservation]

    init(observations: [HSOCRObservation]) {
        self.observations = observations
        self.text = observations.map(\.text).joined(separator: "\n")
        super.init()
    }

    isolated deinit {
        AKTrace("deinit of HSOCRResult")
    }
}
