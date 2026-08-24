//
//  HSStreamDeckImageRendering.swift
//  Hammerspoon 2
//

import Foundation
import AppKit

/// Image preparation for Stream Deck button/screen writes: resize, rotate, flip, and
/// encode as raw BMP or JPEG bytes, matching the byte-for-byte layout the hardware
/// expects (ported from Hammerspoon v1's NSImage+BMP/JPEG/Rotated/Flipped categories).
/// Shared across every model — device-specific behaviour is entirely data-driven via
/// `HSStreamDeckModel`, not per-device code.
enum HSStreamDeckImageRendering {

    /// Resizes, rotates, and flips `image` to the device's button size, then encodes it
    /// in the format the device expects. Returns `nil` for devices with no image support
    /// (the Pedal).
    static func renderForDevice(_ image: NSImage, model: HSStreamDeckModel) -> Data? {
        guard model.imageWidth > 0, model.imageHeight > 0 else { return nil }
        let targetSize = NSSize(width: model.imageWidth, height: model.imageHeight)
        return render(image, to: targetSize, model: model)
    }

    /// Resizes, rotates, and flips `image` to the size of a single encoder tile on the
    /// LCD strip (Stream Deck Plus), then encodes it. Returns `nil` for devices with no
    /// screen (everything except the Plus).
    static func renderScreenImage(_ image: NSImage, model: HSStreamDeckModel) -> Data? {
        guard model.hasScreen, model.encoderColumns > 0 else { return nil }
        let encoderWidth = model.lcdStripWidth / model.encoderColumns
        let targetSize = NSSize(width: encoderWidth, height: model.lcdStripHeight)
        return render(image, to: targetSize, model: model)
    }

    private static func render(_ image: NSImage, to targetSize: NSSize, model: HSStreamDeckModel) -> Data? {
        guard model.imageCodec != .unsupported else { return nil }

        var rendered = resized(image, to: targetSize)
        rendered = rotated(rendered, degrees: model.imageRotationDegrees)
        rendered = flipped(rendered, horizontal: model.imageFlipX, vertical: model.imageFlipY)

        switch model.imageCodec {
        case .bmp:  return bmpData(from: rendered)
        case .jpeg: return jpegData(from: rendered)
        case .unsupported: return nil
        }
    }

    /// A solid-fill swatch at the device's button size, used by `setButtonColor()`.
    static func solidColorImage(_ color: NSColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }

    // MARK: - Transform steps

    private static func resized(_ image: NSImage, to size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    private static func rotated(_ image: NSImage, degrees: Int) -> NSImage {
        guard degrees != 0 else { return image }
        let size = image.size
        let normalized = ((degrees % 360) + 360) % 360
        let canvasSize = (normalized == 90 || normalized == 270)
            ? NSSize(width: size.height, height: size.width)
            : size

        let result = NSImage(size: canvasSize)
        result.lockFocus()

        let rotation = NSAffineTransform()
        rotation.rotate(byDegrees: CGFloat(degrees))
        let centering = NSAffineTransform()
        centering.translateX(by: canvasSize.width / 2, yBy: canvasSize.height / 2)
        rotation.append(centering as AffineTransform)
        rotation.concat()

        let corner = NSPoint(x: -size.width / 2, y: -size.height / 2)
        image.draw(at: corner, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)

        result.unlockFocus()
        return result
    }

    private static func flipped(_ image: NSImage, horizontal: Bool, vertical: Bool) -> NSImage {
        guard horizontal || vertical else { return image }
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let transform = NSAffineTransform()
        transform.translateX(by: horizontal ? size.width : 0, yBy: vertical ? size.height : 0)
        transform.scaleX(by: horizontal ? -1.0 : 1.0, yBy: vertical ? -1.0 : 1.0)
        transform.concat()

        image.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    // MARK: - Encoding

    /// Renders `image` into a fixed-size 32-bit RGBA bitmap matching its current `.size`.
    /// JPEG output has no alpha channel, so callers filling for JPEG pre-fill black
    /// (matching v1) to avoid transparent regions compositing against garbage.
    private static func renderBitmap(_ image: NSImage, fillBlackBackground: Bool) -> NSBitmapImageRep? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        guard width > 0, height > 0,
              let bitmap = unsafe NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        if fillBlackBackground {
            NSColor.black.drawSwatch(in: NSRect(origin: .zero, size: image.size))
        }
        image.draw(at: .zero, from: .zero,
                   operation: fillBlackBackground ? .sourceOver : .copy, fraction: 1.0)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    /// A 24-bit, bottom-up, BGR-ordered, row-padded-to-4-bytes BMP — the exact layout
    /// the original/Mini Stream Decks expect. Not produced via `NSBitmapImageRep`'s own
    /// BMP representation, since that doesn't guarantee this specific byte layout.
    private static func bmpData(from image: NSImage) -> Data? {
        guard let bitmap = renderBitmap(image, fillBlackBackground: false),
              let source = unsafe bitmap.bitmapData else { return nil }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let samplesPerPixel = bitmap.samplesPerPixel

        let extraBytes = (4 - (width * 3) % 4) % 4
        let rowBytes = width * 3 + extraBytes
        let pixelDataSize = rowBytes * height

        var data = Data(capacity: 14 + 40 + pixelDataSize)

        // BITMAPFILEHEADER (14 bytes)
        data.append(contentsOf: littleEndianBytes(UInt16(0x4D42)))        // bfType "BM"
        data.append(contentsOf: littleEndianBytes(UInt32(0)))             // bfSize (unused for BI_RGB)
        data.append(contentsOf: littleEndianBytes(UInt16(0)))             // bfReserved1
        data.append(contentsOf: littleEndianBytes(UInt16(0)))             // bfReserved2
        data.append(contentsOf: littleEndianBytes(UInt32(14 + 40)))       // bfOffBits

        // BITMAPINFOHEADER (40 bytes)
        data.append(contentsOf: littleEndianBytes(UInt32(40)))            // biSize
        data.append(contentsOf: littleEndianBytes(UInt32(width)))         // biWidth
        data.append(contentsOf: littleEndianBytes(UInt32(height)))        // biHeight
        data.append(contentsOf: littleEndianBytes(UInt16(1)))             // biPlanes
        data.append(contentsOf: littleEndianBytes(UInt16(24)))            // biBitCount
        data.append(contentsOf: littleEndianBytes(UInt32(0)))             // biCompression (BI_RGB)
        data.append(contentsOf: littleEndianBytes(UInt32(pixelDataSize))) // biSizeImage
        data.append(contentsOf: littleEndianBytes(UInt32(0)))             // biXPelsPerMeter
        data.append(contentsOf: littleEndianBytes(UInt32(0)))             // biYPelsPerMeter
        data.append(contentsOf: littleEndianBytes(UInt32(0)))             // biClrUsed
        data.append(contentsOf: littleEndianBytes(UInt32(0)))             // biClrImportant

        // Pixel data: bottom-up, BGR, padded rows.
        var pixels = [UInt8](repeating: 0, count: pixelDataSize)
        for row in 0..<height {
            let sourceRow = height - 1 - row
            let sourceRowStart = sourceRow * width * samplesPerPixel
            let destRowStart = row * rowBytes
            for column in 0..<width {
                let sourceIndex = sourceRowStart + column * samplesPerPixel
                let destIndex = destRowStart + column * 3
                pixels[destIndex]     = unsafe source[sourceIndex + 2]   // B
                pixels[destIndex + 1] = unsafe source[sourceIndex + 1]   // G
                pixels[destIndex + 2] = unsafe source[sourceIndex]       // R
            }
        }
        data.append(contentsOf: pixels)

        return data
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let bitmap = renderBitmap(image, fillBlackBackground: true) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 1.0])
    }

    // MARK: - Byte helpers

    private static func littleEndianBytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private static func littleEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }
}
