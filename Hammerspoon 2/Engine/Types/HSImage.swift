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
///     .then(image => console.log("Image loaded:", image.size()))
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
/// const size = img.size()  // Returns HSSize
///
/// // Resize image
/// const resized = img.setSize({w: 100, h: 100}, false)  // Proportional
///
/// // Crop image
/// const cropped = img.croppedCopy({x: 10, y: 10, w: 50, h: 50})
///
/// // Save to file
/// img.saveToFile("/path/to/output.png")
/// ```
@objc protocol HSImageAPI: HSTypeAPI, JSExport {
    /// Load an image from a file path
    /// - Parameter path: Path to the image file
    /// - Returns: An HSImage object, or null if the file couldn't be loaded
    @objc static func fromPath(_ path: String) -> HSImage?

    /// Load a system image by name
    /// - Parameter name: Name of the system image (e.g., "NSComputer", "NSFolder")
    /// - Returns: An HSImage object, or null if the image couldn't be found
    @objc static func fromName(_ name: String) -> HSImage?

    /// Load an app's icon by bundle identifier
    /// - Parameter bundleID: Bundle identifier of the application
    /// - Returns: An HSImage object, or null if the app couldn't be found
    @objc static func fromAppBundle(_ bundleID: String) -> HSImage?

    /// Get the icon for a file
    /// - Parameter path: Path to the file
    /// - Returns: An HSImage object representing the file's icon
    @objc static func iconForFile(_ path: String) -> HSImage?

    /// Get the icon for a file type
    /// - Parameter fileType: File extension or UTI (e.g., "png", "public.png")
    /// - Returns: An HSImage object representing the file type's icon
    @objc static func iconForFileType(_ fileType: String) -> HSImage?

    /// Load an image from a URL (asynchronous)
    /// - Parameter url: URL string of the image
    /// - Returns: {Promise<HSImage>} A Promise that resolves to the loaded image, or rejects on error
    @objc static func fromURL(_ url: String) -> JSPromise?

    /// Get or set the image size
    /// - Parameter size: Optional HSSize to set (if provided, returns a resized copy)
    /// - Returns: The current size as HSSize, or a resized copy if size was provided
    @objc func size(_ size: JSValue) -> JSValue

    /// Get or set the image name
    /// - Parameter name: Optional name to set
    /// - Returns: The current or new name
    @objc func name(_ name: JSValue) -> String?

    /// Create a resized copy of the image
    /// - Parameters:
    ///   - size: Target size as HSSize
    ///   - absolute: If true, resize exactly to specified dimensions. If false, maintain aspect ratio
    /// - Returns: A new resized HSImage
    @objc func setSize(_ size: JSValue, _ absolute: Bool) -> HSImage?

    /// Create a copy of the image
    /// - Returns: A new HSImage copy
    @objc func copyImage() -> HSImage?

    /// Create a cropped copy of the image
    /// - Parameter rect: HSRect defining the crop area
    /// - Returns: A new cropped HSImage, or null if cropping failed
    @objc func croppedCopy(_ rect: JSValue) -> HSImage?

    /// Save the image to a file
    /// - Parameter path: Destination file path (extension determines format: png, jpg, tiff, bmp, gif)
    /// - Returns: true if saved successfully, false otherwise
    @objc func saveToFile(_ path: String) -> Bool

    /// Get or set the template image flag
    /// - Parameter state: Optional boolean to set template state
    /// - Returns: Current template state
    @objc func template(_ state: JSValue) -> Bool
}

@objc class HSImage: NSObject, HSImageAPI {
    @objc var typeName = "HSImage"
    private(set) var image: NSImage

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

    @objc static func fromAppBundle(_ bundleID: String) -> HSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            AKError("HSImage: Failed to find app with bundle ID: \(bundleID)")
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        return image.toBridge()
    }

    @objc static func iconForFile(_ path: String) -> HSImage? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let image = NSWorkspace.shared.icon(forFile: expandedPath)
        return image.toBridge()
    }

    @objc static func iconForFileType(_ fileType: String) -> HSImage? {
        let image: NSImage

        // Try as UTI first
        if let uti = UTType(fileType) {
            image = NSWorkspace.shared.icon(for: uti)
        } else if let uti = UTType(filenameExtension: fileType) {
            // Try as file extension
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

    @objc func size(_ sizeValue: JSValue) -> JSValue {
        if sizeValue.isUndefined || sizeValue.isNull {
            // Getter - return current size as HSSize
            let size = image.size
            let hsSize = CGSize(width: size.width, height: size.height).toBridge()
            if let context = JSContext.current() {
                return JSValue(object: hsSize, in: context)
            }
            return JSValue()
        } else {
            // Setter - return resized copy
            if let newSize = sizeValue.toCGSize() {
                let resizedImage = resizeImage(image, to: newSize, absolute: false)
                let hsImage = resizedImage.toBridge()
                if let context = JSContext.current() {
                    return JSValue(object: hsImage, in: context)
                }
            }
            return JSValue()
        }
    }

    @objc func name(_ nameValue: JSValue) -> String? {
        if nameValue.isUndefined || nameValue.isNull {
            // Getter
            return image.name()
        } else {
            // Setter
            if let newName = nameValue.toString() {
                image.setName(newName)
                return newName
            }
            return image.name()
        }
    }

    // MARK: - Image Manipulation

    @objc func setSize(_ sizeValue: JSValue, _ absolute: Bool) -> HSImage? {
        guard let targetSize = sizeValue.toCGSize() else {
            AKError("HSImage: Invalid size provided to setSize")
            return nil
        }

        let resizedImage = resizeImage(image, to: targetSize, absolute: absolute)
        return resizedImage.toBridge()
    }

    @objc func copyImage() -> HSImage? {
        guard let copiedImage = image.copy() as? NSImage else {
            return nil
        }
        return copiedImage.toBridge()
    }

    @objc func croppedCopy(_ rectValue: JSValue) -> HSImage? {
        guard let cropRect = rectValue.toCGRect() else {
            AKError("HSImage: Invalid rect provided to croppedCopy")
            return nil
        }

        guard let croppedImage = cropImage(image, to: cropRect) else {
            AKError("HSImage: Failed to crop image")
            return nil
        }

        return croppedImage.toBridge()
    }

    @objc func saveToFile(_ path: String) -> Bool {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        // Determine file type from extension
        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "png":
            fileType = .png
        case "jpg", "jpeg":
            fileType = .jpeg
        case "tiff", "tif":
            fileType = .tiff
        case "bmp":
            fileType = .bmp
        case "gif":
            fileType = .gif
        default:
            fileType = .png  // Default to PNG
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let imageData = bitmapImage.representation(using: fileType, properties: [:]) else {
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

    @objc func template(_ stateValue: JSValue) -> Bool {
        if stateValue.isUndefined || stateValue.isNull {
            // Getter
            return image.isTemplate
        } else {
            // Setter
            if stateValue.isBoolean {
                let newState = stateValue.toBool()
                image.isTemplate = newState
                return newState
            }
            return image.isTemplate
        }
    }

    // MARK: - Helper Methods

    private func resizeImage(_ image: NSImage, to targetSize: CGSize, absolute: Bool) -> NSImage {
        let originalSize = image.size

        let newSize: CGSize
        if absolute {
            // Absolute sizing - use exact dimensions
            newSize = targetSize
        } else {
            // Proportional sizing - maintain aspect ratio
            let widthRatio = targetSize.width / originalSize.width
            let heightRatio = targetSize.height / originalSize.height
            let ratio = min(widthRatio, heightRatio)

            newSize = CGSize(
                width: originalSize.width * ratio,
                height: originalSize.height * ratio
            )
        }

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }

    private func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage? {
        let imageRect = CGRect(origin: .zero, size: image.size)

        // Ensure crop rect is within image bounds
        guard imageRect.contains(rect) else {
            return nil
        }

        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()

        let sourceRect = NSRect(x: rect.origin.x,
                               y: rect.origin.y,
                               width: rect.size.width,
                               height: rect.size.height)
        let destRect = NSRect(origin: .zero, size: rect.size)

        image.draw(in: destRect,
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
    /// Convert NSImage to HSImage bridge type
    func toBridge() -> HSImage {
        HSImage(image: self)
    }
}

// ---------------------------------------------------------------
// MARK: - JSValue Convenience Extension
// ---------------------------------------------------------------

extension JSValue {
    /// Convert a JSValue to an NSImage
    /// Supports:
    /// - HSImage objects
    /// - File paths (strings)
    func toNSImage() -> NSImage? {
        if let bridge = self.toObjectOf(HSImage.self) as? HSImage {
            return bridge.image
        } else if self.isString, let path = self.toString() {
            return NSImage(contentsOfFile: NSString(string: path).expandingTildeInPath)
        }
        return nil
    }
}

