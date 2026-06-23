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
/// const image = await HSImage.fromURL("https://example.com/image.png")
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
/// img.size = HSSize(100, 100)
///
/// // Crop image
/// const cropped = img.croppedCopy(HSRect(10, 10, 50, 50))
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
    /// const img = await HSImage.fromURL("https://example.com/image.png")
    /// ```
    @objc static func fromURL(_ url: String) -> JSPromise?

    /// The size of the image. Setting this resizes the image in place to the exact dimensions.
    /// - Example:
    /// ```js
    /// const img = HSImage.fromPath("/path/to/image.png")
    /// console.log(img.size)       // HSSize { w: 200, h: 150 }
    /// img.size = HSSize(100, 75)  // resize in place
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
    /// const copy = img.copyImage()
    /// copy.size = HSSize(64, 64)
    /// ```
    @objc func copyImage() -> HSImage?

    /// Create a cropped copy of the image
    /// - Parameter rect: HSRect defining the crop area (x, y, w, h)
    /// - Returns: A new cropped HSImage, or null if the rect falls outside the image bounds
    /// - Example:
    /// ```js
    /// const cropped = img.croppedCopy(HSRect(10, 10, 80, 60))
    /// ```
    @objc func croppedCopy(_ rect: HSRect) -> HSImage?

    /// Save the image to a file
    /// - Parameter path: Destination file path (extension determines format: png, jpg, tiff, bmp, gif)
    /// - Returns: true if saved successfully, false otherwise
    /// - Example:
    /// ```js
    /// img.saveToFile("/tmp/output.png")
    /// ```
    @objc func saveToFile(_ path: String) -> Bool

    /// Replace this image's content by loading a new image from a file path.
    ///
    /// If this image is bound to a UI element, the canvas re-renders automatically.
    /// - Parameter path: Path to the image file. `~` is expanded.
    /// - Example:
    /// ```js
    /// const reactive = HSImage.fromPath("/path/to/initial.png")
    /// // ...later...
    /// reactive.replaceFromFile("/path/to/updated.png")
    /// ```
    @objc func replaceFromFile(_ path: String)

    /// Replace this image's content with that of another HSImage.
    ///
    /// If this image is bound to a UI element, the canvas re-renders automatically.
    /// - Parameter image: The HSImage whose content to copy
    /// - Example:
    /// ```js
    /// const reactive = HSImage.fromName("NSStatusAvailable")
    /// // ...later...
    /// reactive.replaceWithImage(HSImage.fromName("NSStatusUnavailable"))
    /// ```
    @objc func replaceWithImage(_ image: HSImage)
}

@Observable
@objc class HSImage: NSObject, HSImageAPI {
    @objc var typeName = "HSImage"

    var image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init()
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
        set { image = resizeImage(image, to: newValue.size) }
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

    @objc func copyImage() -> HSImage? {
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

        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": fileType = .jpeg
        case "tiff", "tif": fileType = .tiff
        case "bmp":         fileType = .bmp
        case "gif":         fileType = .gif
        default:            fileType = .png
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapRep.representation(using: fileType, properties: [:]) else {
            AKError("HSImage: Failed to convert image for saving")
            return false
        }

        do {
            try imageData.write(to: url)
            return true
        } catch {
            AKError("HSImage: Failed to save image: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reactive Mutation

    @objc func replaceFromFile(_ path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard let newImage = NSImage(contentsOfFile: expandedPath) else {
            AKError("HSImage: Failed to load image from path: \(path)")
            return
        }
        image = newImage
    }

    @objc func replaceWithImage(_ other: HSImage) {
        image = other.image
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

        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: rect.size),
                    from: NSRect(origin: rect.origin, size: rect.size),
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
