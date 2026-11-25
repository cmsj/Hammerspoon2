//
//  HSImage.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 26/02/2026.
//

import Foundation
import JavaScriptCore
import AppKit
import UniformTypeIdentifiers
import Observation

// ---------------------------------------------------------------
// MARK: - Bridge Class (JavaScript Interface)
// ---------------------------------------------------------------

/// Bridge type for working with images in JavaScript
///
/// HSImage provides a comprehensive API for loading, manipulating, and saving images.
/// It supports various image sources including files, system icons, app bundles, and URLs.
///
/// ## Loading Images
///
/// ```javascript
/// // Load from file
/// const img = HSImage.fromPath("/path/to/image.png")
///
/// // Load system image
/// const icon = HSImage.fromName("NSComputer")
///
/// // Load app icon
/// const appIcon = HSImage.fromAppBundle("com.apple.Safari")
///
/// // Load from URL (asynchronous with Promise)
/// HSImage.fromURL("https://example.com/image.png")
///     .then(image => console.log("Image loaded:", image.size))
///     .catch(err => console.error("Failed to load image:", err))
///
/// // Or with async/await
/// async function loadImage() {
///     const image = await HSImage.fromURL("https://example.com/image.png")
///     console.log("Image loaded:", image.size)
/// }
/// ```
///
/// ## Image Manipulation
///
/// ```javascript
/// const img = HSImage.fromPath("/path/to/image.png")
///
/// // Get size
/// const size = img.size  // Returns HSSize
///
/// // Resize image (mutates in place)
/// img.size = new HSSize(100, 100)
///
/// // Crop image
/// const cropped = img.croppedCopy(new HSRect(10, 10, 50, 50))
///
/// // Save to file
/// img.saveToFile("/path/to/output.png")
/// ```
@objc protocol HSImageAPI: HSTypeAPI, JSExport {
    /// Load an image from a file path
    /// - Parameter path: Path to the image file
    /// - Returns: An HSImage object, or null if the file couldn't be loaded
    /// - Example:
    /// ```js
    /// const img = HSImage.fromPath("/path/to/image.png")
    /// ```
    @objc static func fromPath(_ path: String) -> HSImage?

    /// Load a system image by name
    /// - Parameter name: Name of the system image (e.g., "NSComputer", "NSFolder")
    /// - Returns: An HSImage object, or null if the image couldn't be found
    /// - Example:
    /// ```js
    /// const icon = HSImage.fromName("NSComputer")
    /// ```
    @objc static func fromName(_ name: String) -> HSImage?

    /// Load a system symbol by name
    /// - Parameter name: Name of the symbol (e.g., "hammer", "questionmark.circle")
    /// - Returns: An HSImage object, or null if the symbol couldn't be found
    /// - Example:
    /// ```js
    /// const sym = HSImage.fromSymbol("star.fill")
    /// ```
    @objc static func fromSymbol(_ name: String) -> HSImage?

    /// Load an app's icon by bundle identifier
    /// - Parameters:
    ///   - bundleID: Bundle identifier of the application
    ///   - withFallbackSymbol?: The name of an SF Symbol to use if no bundle image could be loaded. Defaults to questionmark.circle
    /// - Returns: An HSImage object, or null if the app couldn't be found
    /// - Example:
    /// ```js
    /// const appIcon = HSImage.fromAppBundle("com.apple.Safari")
    /// ```
    @objc static func fromAppBundle(_ bundleID: String, _ withFallbackSymbol: String) -> HSImage?

    /// Get the icon for a file
    /// - Parameter path: Path to the file
    /// - Returns: An HSImage object representing the file's icon
    /// - Example:
    /// ```js
    /// const icon = HSImage.iconForFile("/Applications/Safari.app")
    /// ```
    @objc static func iconForFile(_ path: String) -> HSImage?

    /// Get the icon for a file type
    /// - Parameter fileType: File extension or UTI (e.g., "png", "public.png")
    /// - Returns: An HSImage object representing the file type's icon
    /// - Example:
    /// ```js
    /// const icon = HSImage.iconForFileType("pdf")
    /// ```
    @objc static func iconForFileType(_ fileType: String) -> HSImage?

    /// Load an image from a URL (asynchronous)
    /// - Parameter url: URL string of the image
    /// - Returns: {Promise<HSImage>} A Promise that resolves to the loaded image, or rejects on error
    /// - Example:
    /// ```js
    /// HSImage.fromURL("https://example.com/image.png")
    ///     .then(img => console.log("Image loaded:", img.size))
    /// ```
    @objc static func fromURL(_ url: String) -> JSPromise?

    /// The size of the image. Setting this resizes the image in place to the exact dimensions.
    /// - Example:
    /// ```js
    /// const img = HSImage.fromPath("/path/to/image.png")
    /// console.log(img.size)       // HSSize { w: 200, h: 150 }
    /// img.size = new HSSize(100, 75)  // resize in place
    /// ```
    @objc var size: HSSize { get set }

    /// The name of the image, or null if not set.
    /// - Example:
    /// ```js
    /// const img = HSImage.fromName("NSComputer")
    /// console.log(img.name)  // "NSComputer"
    /// img.name = "MyIcon"
    /// ```
    @objc var name: String? { get set }

    /// Whether the image is a template image.
    ///
    /// Template images are tinted by the system to match the appearance context (e.g. menu bar icons).
    /// - Example:
    /// ```js
    /// const img = HSImage.fromSymbol("star.fill")
    /// img.template = true
    /// ```
    @objc var template: Bool { get set }

    /// Create a copy of the image
    /// - Returns: A new HSImage copy
    /// - Example:
    /// ```js
    /// const copy = img.duplicate()
    /// copy.size = new HSSize(64, 64)
    /// ```
    @objc func duplicate() -> HSImage?

    /// Create a cropped copy of the image
    ///
    /// The crop area is measured from the top left corner of the image, like the frames of screens and windows,
    /// so a screen snapshot can be cropped to a window's frame (after subtracting the screen's origin).
    /// - Parameter rect: HSRect defining the crop area (x, y, w, h), with `y` measured down from the top of the image
    /// - Returns: A new cropped HSImage, or null if the rect falls outside the image bounds
    /// - Example:
    /// ```js
    /// const cropped = img.croppedCopy(new HSRect(10, 10, 80, 60))
    /// ```
    @objc func croppedCopy(_ rect: HSRect) -> HSImage?

    /// Save the image to a file. The file is written atomically, so anything reading it sees
    /// either the previous contents or the complete new image, never a partial write.
    /// - Parameter path: Destination file path (extension determines format: png, jpg, tiff, bmp, gif)
    /// - Returns: true if saved successfully, false otherwise
    /// - Example:
    /// ```js
    /// img.saveToFile("/tmp/output.png")
    /// ```
    @objc func saveToFile(_ path: String) -> Bool

    /// Encode the image and return it as a base64 `data:` URL, without writing anything to disk.
    ///
    /// This is useful for handing an image to anything that accepts data URLs, such as web views or
    /// JSON messages sent to other programs.
    /// - Parameter type?: The image format, case-insensitive: `"png"` (the default), `"jpeg"`/`"jpg"`, `"tiff"`/`"tif"`, `"bmp"` or `"gif"`
    /// - Returns: A string such as `"data:image/png;base64,iVBOR..."`, or null if the format is unknown or the image couldn't be encoded
    /// - Example:
    /// ```js
    /// const url = HSImage.fromSymbol("star.fill").toDataURL()
    /// console.log(url.slice(0, 22))  // "data:image/png;base64,"
    /// const jpeg = img.toDataURL("jpeg")
    /// ```
    @objc func toDataURL(_ type: String?) -> String?

    /// Encode the image and return its bytes as a `Uint8Array`, without writing anything to disk.
    ///
    /// The bytes are the same as `saveToFile()` would write for that format, so they can be sent over
    /// a socket, used as an HTTP body, stored in a database, and so on.
    /// - Parameter type?: The image format, case-insensitive: `"png"` (the default), `"jpeg"`/`"jpg"`, `"tiff"`/`"tif"`, `"bmp"` or `"gif"`
    /// - Returns: {Uint8Array | null} The encoded image bytes, or null if the format is unknown or the image couldn't be encoded
    /// - Example:
    /// ```js
    /// const bytes = HSImage.fromSymbol("star.fill").toUint8Array("png")
    /// console.log(bytes.length)
    /// ```
    @objc func toUint8Array(_ type: String?) -> JSValue?

    /// Replace this image's content.
    ///
    /// If this image is bound to a UI element, the canvas re-renders automatically.
    /// - Parameter value: {string | HSImage} A file path string (`~` is expanded) or another HSImage object
    /// - Example:
    /// ```js
    /// const reactive = HSImage.fromName("NSStatusAvailable")
    /// reactive.set("/path/to/image.png")
    /// reactive.set(HSImage.fromName("NSStatusUnavailable"))
    /// ```
    @objc func set(_ value: JSValue)
}

@Observable
@objc class HSImage: NSObject, HSImageAPI {
    @objc var typeName = "HSImage"

    @objc func toString() -> String {
        return "<\(typeName): \(Int(image.size.width))x\(Int(image.size.height))>"
    }

    nonisolated override var description: String {
        MainActor.assumeIsolated { toString() }
    }

    var image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init()
        JSExtraMemory.report(Self.estimatedByteCount(of: image))
    }

    /// Roughly how much memory the image's pixels take, at 4 bytes per pixel.
    ///
    /// A bitmap holds all its pixels, so the largest bitmap representation is counted in full.
    /// Other representations (app icons, symbols, PDFs) render on demand at the size the image is
    /// drawn, however large they say they can go: an app icon offers 2048x2048 but draws at
    /// 32x32 points. Those are counted at the image's size on a 2x display.
    static func estimatedByteCount(of image: NSImage) -> Int {
        let drawnWidth = image.size.width * 2
        let drawnHeight = image.size.height * 2
        let drawnBytes = JSExtraMemory.byteCount(pixelsWide: drawnWidth, pixelsHigh: drawnHeight)

        let representationBytes = image.representations.map { rep in
            let bytes = JSExtraMemory.byteCount(pixelsWide: Double(rep.pixelsWide), pixelsHigh: Double(rep.pixelsHigh))
            return rep is NSBitmapImageRep ? bytes : min(bytes, drawnBytes)
        }
        let largest = representationBytes.max() ?? 0
        return largest > 0 ? largest : drawnBytes
    }

    // MARK: - Factory Methods

    @objc static func fromPath(_ path: String) -> HSImage? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard let image = NSImage(contentsOfFile: expandedPath) else {
            AKError("HSImage: Failed to load image from path: \(path)")
            return nil
        }
        return image.toBridge()
    }

    @objc static func fromName(_ name: String) -> HSImage? {
        guard let image = NSImage(named: NSImage.Name(name)) else {
            AKError("HSImage: Failed to find system image named: \(name)")
            return nil
        }
        return image.toBridge()
    }

    @objc static func fromSymbol(_ name: String) -> HSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            AKError("HSImage: Failed to find symbol named: \(name)")
            return nil
        }
        return image.toBridge()
    }

    @objc static func fromAppBundle(_ bundleID: String, _ withFallbackSymbol: String) -> HSImage? {
        let fallbackSymbol = withFallbackSymbol == "undefined" ? "questionmark.circle" : withFallbackSymbol

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path).toBridge()
        }
        return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil)?.toBridge()
    }

    @objc static func iconForFile(_ path: String) -> HSImage? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return NSWorkspace.shared.icon(forFile: expandedPath).toBridge()
    }

    @objc static func iconForFileType(_ fileType: String) -> HSImage? {
        let image: NSImage
        if let uti = UTType(fileType) {
            image = NSWorkspace.shared.icon(for: uti)
        } else if let uti = UTType(filenameExtension: fileType) {
            image = NSWorkspace.shared.icon(for: uti)
        } else {
            AKError("HSImage: Failed to find icon for file type: \(fileType)")
            return nil
        }
        return image.toBridge()
    }

    @objc static func fromURL(_ urlString: String) -> JSPromise? {
        guard let url = URL(string: urlString) else {
            AKError("HSImage: Invalid URL: \(urlString)")
            return JSEngine.shared.createRejectedPromise(with: "Invalid URL: \(urlString)")
        }

        return JSEngine.shared.createPromise { holder in
            Task { @MainActor in
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let image = NSImage(data: data) else {
                        AKError("HSImage: Failed to create image from URL data")
                        holder.rejectWithMessage("Failed to create image from URL data")
                        return
                    }
                    holder.resolveWith(image.toBridge())
                } catch {
                    AKError("HSImage: Failed to load image from URL: \(error.localizedDescription)")
                    holder.rejectWithMessage("Failed to load image: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Properties

    @objc var size: HSSize {
        get { image.size.toBridge() }
        set {
            image = resizeImage(image, to: newValue.size)
            JSExtraMemory.report(Self.estimatedByteCount(of: image))
        }
    }

    @objc var name: String? {
        get { image.name() }
        set { _ = image.setName(newValue) }
    }

    @objc var template: Bool {
        get { image.isTemplate }
        set { image.isTemplate = newValue }
    }

    // MARK: - Image Manipulation

    @objc func duplicate() -> HSImage? {
        guard let copiedImage = image.copy() as? NSImage else { return nil }
        return copiedImage.toBridge()
    }

    @objc func croppedCopy(_ rect: HSRect) -> HSImage? {
        guard let croppedImage = cropImage(image, to: rect.rect) else {
            AKError("HSImage: Failed to crop image (rect may fall outside image bounds)")
            return nil
        }
        return croppedImage.toBridge()
    }

    @objc func saveToFile(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        let format = Self.encodingFormat(for: url.pathExtension) ?? Self.defaultEncodingFormat

        guard let imageData = encodedData(format.fileType) else {
            AKError("HSImage: Failed to convert image for saving")
            return false
        }

        do {
            try imageData.write(to: url, options: .atomic)
            return true
        } catch {
            AKError("HSImage: Failed to save image: \(error.localizedDescription)")
            return false
        }
    }

    @objc func toDataURL(_ type: String?) -> String? {
        guard let format = Self.requestedEncodingFormat(type, "toDataURL") else { return nil }
        guard let data = encodedData(format.fileType) else {
            AKError("HSImage: toDataURL() failed to encode image as \(format.mimeType)")
            return nil
        }
        return "data:\(format.mimeType);base64,\(data.base64EncodedString())"
    }

    @objc func toUint8Array(_ type: String?) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        guard let format = Self.requestedEncodingFormat(type, "toUint8Array") else { return nil }
        guard let data = encodedData(format.fileType) else {
            AKError("HSImage: toUint8Array() failed to encode image as \(format.mimeType)")
            return nil
        }
        guard let array = context.makeUint8Array(data) else {
            AKError("HSImage: toUint8Array() could not allocate a Uint8Array")
            return nil
        }
        return array
    }

    // MARK: - Reactive Mutation

    @objc func set(_ value: JSValue) {
        if let newImage = HSImage.fromJSValue(value) {
            image = newImage.image
        }
    }

    // MARK: - Internal Helpers

    /// Create an HSImage from a JSValue (supports HSImage objects or file path strings).
    /// Used by the hs.ui builder.
    static func fromJSValue(_ value: JSValue) -> HSImage? {
        if let hsImage = value.toObjectOf(HSImage.self) as? HSImage {
            return hsImage
        } else if value.isString, let path = value.toString() {
            return HSImage.fromPath(path)
        }
        return nil
    }

    /// An image format that HSImage can encode to.
    struct EncodingFormat {
        let fileType: NSBitmapImageRep.FileType
        let mimeType: String
    }

    static let defaultEncodingFormat = EncodingFormat(fileType: .png, mimeType: "image/png")

    /// Map a format name or file extension (case-insensitive) to an encoding format.
    /// - Returns: The format, or nil if the name isn't one HSImage can encode to
    static func encodingFormat(for name: String) -> EncodingFormat? {
        switch name.lowercased() {
        case "png":         return defaultEncodingFormat
        case "jpg", "jpeg": return EncodingFormat(fileType: .jpeg, mimeType: "image/jpeg")
        case "tiff", "tif": return EncodingFormat(fileType: .tiff, mimeType: "image/tiff")
        case "bmp":         return EncodingFormat(fileType: .bmp, mimeType: "image/bmp")
        case "gif":         return EncodingFormat(fileType: .gif, mimeType: "image/gif")
        default:            return nil
        }
    }

    /// The format a JS caller asked for, defaulting to PNG when the argument was omitted.
    /// Logs an error and returns nil for an unknown format.
    private static func requestedEncodingFormat(_ type: String?, _ method: String) -> EncodingFormat? {
        // An omitted trailing String? argument arrives from JSExport as the literal "undefined"
        switch type {
        case nil, "undefined", "null":
            return defaultEncodingFormat
        case let type?:
            guard let format = encodingFormat(for: type) else {
                AKError("HSImage: \(method)() unknown image type '\(type)'. Use png, jpeg, tiff, bmp or gif.")
                return nil
            }
            return format
        }
    }

    /// Encode the image in the given format.
    private func encodedData(_ fileType: NSBitmapImageRep.FileType) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: fileType, properties: [:])
    }

    private func resizeImage(_ source: NSImage, to targetSize: CGSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: targetSize),
                    from: NSRect(origin: .zero, size: source.size),
                    operation: .copy,
                    fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    private func cropImage(_ source: NSImage, to rect: CGRect) -> NSImage? {
        guard CGRect(origin: .zero, size: source.size).contains(rect) else { return nil }

        // The rect measures y from the top, but NSImage's own coordinates measure it from the bottom
        let sourceRect = NSRect(x: rect.minX, y: source.size.height - rect.maxY,
                                width: rect.width, height: rect.height)

        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: rect.size),
                    from: sourceRect,
                    operation: .copy,
                    fraction: 1.0)
        croppedImage.unlockFocus()
        return croppedImage
    }
}

// ---------------------------------------------------------------
// MARK: - Bridge Extension
// ---------------------------------------------------------------

extension NSImage {
    func toBridge() -> HSImage {
        HSImage(image: self)
    }
}
