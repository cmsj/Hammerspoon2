//
//  HSOCRObservation.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// A single region of text recognized in an image.
///
/// Instances are delivered inside the `observations` array of an `HSOCRResult`.
/// Each observation represents a discrete text run found in the source image,
/// along with a confidence score and a normalized bounding box.
///
/// Bounding-box coordinates use a **normalized top-left-origin** system:
/// `(0, 0)` is the top-left corner of the image and `(1, 1)` is the bottom-right.
/// This matches the convention used by most image-processing tools and differs
/// from Vision's internal bottom-left-origin system (the conversion is automatic).
///
/// - Example:
/// ```js
/// const result = await hs.ocr.recognizeText('/tmp/image.png')
/// result.observations.forEach(obs => {
///     const pct = (obs.confidence * 100).toFixed(0)
///     console.log(obs.text + ' (' + pct + '% confidence)')
///     const b = obs.bounds
///     console.log('  region: x=' + b.x.toFixed(3) + ' y=' + b.y.toFixed(3)
///                 + ' w=' + b.width.toFixed(3) + ' h=' + b.height.toFixed(3))
/// })
/// ```
@objc protocol HSOCRObservationAPI: HSTypeAPI, JSExport {

    /// The Swift type name, for JavaScript introspection.
    ///
    /// - Example:
    /// ```js
    /// const result = await hs.ocr.recognizeText('/tmp/image.png')
    /// console.log(result.observations[0].typeName) // "HSOCRObservation"
    /// ```
    @objc var typeName: String { get }

    /// The recognized text string for this observation.
    ///
    /// - Example:
    /// ```js
    /// const result = await hs.ocr.recognizeText('/tmp/image.png')
    /// result.observations.forEach(obs => console.log(obs.text))
    /// ```
    @objc var text: String { get }

    /// Recognition confidence in the range `0.0` (uncertain) to `1.0` (certain).
    ///
    /// Use `minimumConfidence` in the options passed to `recognizeText()` to
    /// pre-filter observations below a threshold rather than filtering here.
    ///
    /// - Example:
    /// ```js
    /// const result = await hs.ocr.recognizeText('/tmp/image.png')
    /// const highConf = result.observations.filter(o => o.confidence > 0.9)
    /// console.log('High-confidence regions: ' + highConf.length)
    /// ```
    @objc var confidence: Double { get }

    /// Normalized bounding box of this observation in the source image.
    ///
    /// An object with keys `x`, `y`, `width`, and `height`, all in the
    /// range 0–1 with **top-left origin** (`(0, 0)` = top-left corner,
    /// `(1, 1)` = bottom-right corner).
    ///
    /// - Example:
    /// ```js
    /// const result = await hs.ocr.recognizeText('/tmp/image.png')
    /// const b = result.observations[0].bounds
    /// // Check if the observation is in the top half of the image
    /// if (b.y + b.height / 2 < 0.5) {
    ///     console.log('Text is in the top half:', result.observations[0].text)
    /// }
    /// ```
    @objc var bounds: [String: Double] { get }
}

@_documentation(visibility: private)
@MainActor
@objc class HSOCRObservation: NSObject, HSOCRObservationAPI {
    @objc var typeName = "HSOCRObservation"
    @objc let text: String
    @objc let confidence: Double
    @objc let bounds: [String: Double]

    init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = Double(confidence)
        // Vision uses normalized coordinates with origin at the bottom-left of the image.
        // Convert to top-left origin: flip Y so (0,0) becomes the image's top-left corner.
        self.bounds = [
            "x":      Double(boundingBox.minX),
            "y":      Double(1.0 - boundingBox.maxY),
            "width":  Double(boundingBox.width),
            "height": Double(boundingBox.height)
        ]
        super.init()
    }

    isolated deinit {
        AKTrace("deinit of HSOCRObservation")
    }
}
