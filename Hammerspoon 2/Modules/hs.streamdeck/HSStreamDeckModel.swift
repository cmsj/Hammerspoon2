//
//  HSStreamDeckModel.swift
//  Hammerspoon 2
//

import Foundation

// MARK: - Per-model configuration

/// The image format a device's buttons expect.
///
/// Deliberately not named `.none` for the no-image-support case — that collides with
/// `Optional.none` and silently breaks `==` comparisons against an optional model.
enum HSStreamDeckImageCodec {
    case unsupported
    case bmp
    case jpeg
}

/// The wire format used when writing a button image to a device. There are only three
/// distinct layouts across every Elgato Stream Deck model, so this (plus the byte
/// constants in `HSStreamDeckModel`) is all that varies per device — no per-model
/// subclassing is needed.
enum HSStreamDeckImageWriteStyle {
    /// No image support (Pedal). Not named `.none` — see `HSStreamDeckImageCodec`.
    case unsupported
    /// Original: exactly two pages, each half the image data, report ID 0x02.
    case legacyHalves
    /// Mini/MiniV2: paginated, page counter + last-page bool in the header.
    case legacyPaginated
    /// OriginalV2/XL/XLV2/Mk2/Plus: paginated with little-endian page-length/page-number
    /// header fields and a final-page bool, written as an output report.
    case v2
}

/// Static, per-product-ID configuration for a Stream Deck model. This is the entire
/// "per-device" surface — every device-specific behaviour in `HSStreamDeckDevice` is
/// driven by one of these values rather than by subclassing.
struct HSStreamDeckModel {
    let deckType: String

    let keyColumns: Int
    let keyRows: Int
    let imageWidth: Int
    let imageHeight: Int
    let imageCodec: HSStreamDeckImageCodec
    let imageFlipX: Bool
    let imageFlipY: Bool
    let imageRotationDegrees: Int
    /// True only for the original Stream Deck, whose USB reports present each row of
    /// keys mirrored left-to-right relative to their physical position.
    let mirrorsKeyIndexPerRow: Bool

    let encoderColumns: Int
    let encoderRows: Int
    let dataEncoderOffset: Int

    let lcdStripWidth: Int
    let lcdStripHeight: Int
    let lcdReportLength: Int
    let lcdReportHeaderLength: Int

    let simpleReportLength: Int
    let reportLength: Int
    let reportHeaderLength: Int
    let dataKeyOffset: Int

    let imageWriteStyle: HSStreamDeckImageWriteStyle

    let resetCommand: [UInt8]
    /// nil for devices with no brightness control (the Pedal).
    let setBrightnessCommand: [UInt8]?

    let serialNumberCommand: Int
    let firmwareVersionCommand: Int
    let serialNumberReadOffset: Int
    let firmwareReadOffset: Int

    var keyCount: Int { keyColumns * keyRows }
    var encoderCount: Int { encoderColumns * encoderRows }
    var hasScreen: Bool { lcdStripWidth > 0 && lcdStripHeight > 0 }

    /// Maps a physical key index (1-based) to the index used in USB reports and
    /// `setButtonImage()`/`setButtonColor()`, mirroring each row when `mirrorsKeyIndexPerRow`
    /// is set (Original only).
    func transformKeyIndex(_ sourceKey: Int) -> Int {
        guard mirrorsKeyIndexPerRow, keyColumns > 0 else { return sourceKey }
        let zeroBased = sourceKey - 1
        let row = zeroBased / keyColumns
        let col = zeroBased % keyColumns
        let mirroredCol = keyColumns - 1 - col
        return row * keyColumns + mirroredCol + 1
    }
}

// MARK: - Product ID table

extension HSStreamDeckModel {
    static let usbVendorIDElgato = 0x0fd9

    private static let original = HSStreamDeckModel(
        deckType: "Elgato Stream Deck (Original v1)",
        keyColumns: 5, keyRows: 3,
        imageWidth: 72, imageHeight: 72, imageCodec: .bmp,
        imageFlipX: true, imageFlipY: true, imageRotationDegrees: 0,
        mirrorsKeyIndexPerRow: true,
        encoderColumns: 0, encoderRows: 0, dataEncoderOffset: 0,
        lcdStripWidth: 0, lcdStripHeight: 0, lcdReportLength: 0, lcdReportHeaderLength: 0,
        simpleReportLength: 17, reportLength: 8192, reportHeaderLength: 16, dataKeyOffset: 1,
        imageWriteStyle: .legacyHalves,
        resetCommand: [0x0B, 0x63],
        setBrightnessCommand: [0x05, 0x55, 0xAA, 0xD1, 0x01, 0xFF],
        serialNumberCommand: 0x3, firmwareVersionCommand: 0x4,
        serialNumberReadOffset: 5, firmwareReadOffset: 5
    )

    private static let originalV2 = HSStreamDeckModel(
        deckType: "Elgato Stream Deck (V2)",
        keyColumns: 5, keyRows: 3,
        imageWidth: 72, imageHeight: 72, imageCodec: .jpeg,
        imageFlipX: true, imageFlipY: true, imageRotationDegrees: 0,
        mirrorsKeyIndexPerRow: false,
        encoderColumns: 0, encoderRows: 0, dataEncoderOffset: 0,
        lcdStripWidth: 0, lcdStripHeight: 0, lcdReportLength: 0, lcdReportHeaderLength: 0,
        simpleReportLength: 32, reportLength: 1024, reportHeaderLength: 8, dataKeyOffset: 4,
        imageWriteStyle: .v2,
        resetCommand: [0x03, 0x02],
        setBrightnessCommand: [0x03, 0x08, 0xFF],
        serialNumberCommand: 0x06, firmwareVersionCommand: 0x05,
        serialNumberReadOffset: 2, firmwareReadOffset: 6
    )

    private static let mini = HSStreamDeckModel(
        deckType: "Elgato Stream Deck (Mini)",
        keyColumns: 3, keyRows: 2,
        imageWidth: 80, imageHeight: 80, imageCodec: .bmp,
        imageFlipX: false, imageFlipY: true, imageRotationDegrees: 90,
        mirrorsKeyIndexPerRow: false,
        encoderColumns: 0, encoderRows: 0, dataEncoderOffset: 0,
        lcdStripWidth: 0, lcdStripHeight: 0, lcdReportLength: 0, lcdReportHeaderLength: 0,
        simpleReportLength: 17, reportLength: 1024, reportHeaderLength: 16, dataKeyOffset: 1,
        imageWriteStyle: .legacyPaginated,
        resetCommand: [0x0B, 0x63],
        setBrightnessCommand: [0x05, 0x55, 0xAA, 0xD1, 0x01, 0xFF],
        serialNumberCommand: 0x03, firmwareVersionCommand: 0x4,
        serialNumberReadOffset: 5, firmwareReadOffset: 5
    )

    private static let xl = HSStreamDeckModel(
        deckType: "Elgato Stream Deck (XL)",
        keyColumns: 8, keyRows: 4,
        imageWidth: 96, imageHeight: 96, imageCodec: .jpeg,
        imageFlipX: true, imageFlipY: true, imageRotationDegrees: 0,
        mirrorsKeyIndexPerRow: false,
        encoderColumns: 0, encoderRows: 0, dataEncoderOffset: 0,
        lcdStripWidth: 0, lcdStripHeight: 0, lcdReportLength: 0, lcdReportHeaderLength: 0,
        simpleReportLength: 32, reportLength: 1024, reportHeaderLength: 8, dataKeyOffset: 4,
        imageWriteStyle: .v2,
        resetCommand: [0x03, 0x02],
        setBrightnessCommand: [0x03, 0x08, 0xFF],
        serialNumberCommand: 0x06, firmwareVersionCommand: 0x05,
        serialNumberReadOffset: 2, firmwareReadOffset: 6
    )

    private static let mk2 = HSStreamDeckModel(
        deckType: "Elgato Stream Deck (Mk2)",
        keyColumns: 5, keyRows: 3,
        imageWidth: 72, imageHeight: 72, imageCodec: .jpeg,
        imageFlipX: true, imageFlipY: true, imageRotationDegrees: 0,
        mirrorsKeyIndexPerRow: false,
        encoderColumns: 0, encoderRows: 0, dataEncoderOffset: 0,
        lcdStripWidth: 0, lcdStripHeight: 0, lcdReportLength: 0, lcdReportHeaderLength: 0,
        simpleReportLength: 32, reportLength: 1024, reportHeaderLength: 8, dataKeyOffset: 4,
        imageWriteStyle: .v2,
        resetCommand: [0x03, 0x02],
        setBrightnessCommand: [0x03, 0x08, 0xFF],
        serialNumberCommand: 0x06, firmwareVersionCommand: 0x05,
        serialNumberReadOffset: 2, firmwareReadOffset: 6
    )

    private static let plus = HSStreamDeckModel(
        deckType: "Elgato Stream Deck Plus",
        keyColumns: 4, keyRows: 2,
        imageWidth: 120, imageHeight: 120, imageCodec: .jpeg,
        imageFlipX: false, imageFlipY: false, imageRotationDegrees: 0,
        mirrorsKeyIndexPerRow: false,
        encoderColumns: 4, encoderRows: 1, dataEncoderOffset: 5,
        lcdStripWidth: 800, lcdStripHeight: 100, lcdReportLength: 1024, lcdReportHeaderLength: 16,
        simpleReportLength: 32, reportLength: 1024, reportHeaderLength: 8, dataKeyOffset: 4,
        imageWriteStyle: .v2,
        resetCommand: [0x03, 0x02],
        setBrightnessCommand: [0x03, 0x08, 0xFF],
        serialNumberCommand: 0x06, firmwareVersionCommand: 0x05,
        serialNumberReadOffset: 2, firmwareReadOffset: 6
    )

    private static let pedal = HSStreamDeckModel(
        deckType: "Elgato Stream Deck Pedal",
        keyColumns: 3, keyRows: 1,
        imageWidth: 0, imageHeight: 0, imageCodec: .unsupported,
        imageFlipX: false, imageFlipY: false, imageRotationDegrees: 0,
        mirrorsKeyIndexPerRow: false,
        encoderColumns: 0, encoderRows: 0, dataEncoderOffset: 0,
        lcdStripWidth: 0, lcdStripHeight: 0, lcdReportLength: 0, lcdReportHeaderLength: 0,
        simpleReportLength: 32, reportLength: 1024, reportHeaderLength: 8, dataKeyOffset: 4,
        imageWriteStyle: .unsupported,
        resetCommand: [0x03, 0x02],
        setBrightnessCommand: nil,
        serialNumberCommand: 0x06, firmwareVersionCommand: 0x05,
        serialNumberReadOffset: 2, firmwareReadOffset: 6
    )

    /// Product IDs, as issued by Elgato (vendor ID `usbVendorIDElgato`). Adding support for
    /// a future model is a single new entry here — nothing else needs to change.
    private static let byProductID: [Int: HSStreamDeckModel] = [
        0x0060: original,
        0x006d: originalV2,
        0x0063: mini,
        0x0090: mini,      // Mini V2 — identical wire protocol to the Mini
        0x006c: xl,
        0x008F: xl,        // XL V2 — identical wire protocol to the XL
        0x0080: mk2,
        0x0084: plus,
        0x0086: pedal,
    ]

    static func forProductID(_ productID: Int) -> HSStreamDeckModel? {
        byProductID[productID]
    }

    static var allProductIDs: [Int] { Array(byProductID.keys) }
}
