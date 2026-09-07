//
//  CanvasElementType.swift
//  Hammerspoon 2
//

import Foundation

/// The fixed set of valid `type` discriminator values for canvas elements.
///
/// Element data itself is stored and passed around as `[String: Any]` dictionaries
/// (mirroring v1 Hammerspoon's table-based canvas elements), not a typed struct per
/// element type -- this enum exists only for exhaustiveness/typo-safety inside
/// `CanvasElementDrawing`'s type switch.
enum CanvasElementType: String {
    case rectangle
    case circle
    case oval
    case arc
    case ellipticalArc
    case segments
    case points
    case text
    case image
    case canvas
    case resetClip
}
