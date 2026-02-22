//
//  UIFrame.swift
//  Hammerspoon 2
//
//  Created by Claude Code on 12/02/2026.
//

import Foundation
import CoreGraphics

/// Represents a dimension that can be either absolute or percentage-based
enum UIDimension {
    case absolute(CGFloat)
    case percentage(CGFloat)  // 0.0 to 1.0
    case fill  // Fill available space

    /// Parse a value from JavaScript (number or string like "50%")
    static func parse(_ value: Any) -> UIDimension {
        if let number = value as? NSNumber {
            return .absolute(CGFloat(number.doubleValue))
        } else if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            if trimmed == "fill" || trimmed == "100%" {
                return .fill
            } else if trimmed.hasSuffix("%") {
                let percentString = trimmed.dropLast()
                if let percent = Double(percentString) {
                    return .percentage(CGFloat(percent / 100.0))
                }
            }
        }
        return .absolute(0)
    }

    /// Resolve to an absolute value given a container dimension
    func resolve(containerSize: CGFloat) -> CGFloat {
        switch self {
        case .absolute(let value):
            return value
        case .percentage(let percent):
            return containerSize * percent
        case .fill:
            return containerSize
        }
    }
}

/// Represents a frame that supports both absolute and percentage-based dimensions
struct UIFrame {
    var width: UIDimension
    var height: UIDimension
    var x: UIDimension?
    var y: UIDimension?

    /// Create a frame from a JavaScript dictionary
    static func from(dict: [String: Any]) -> UIFrame? {
        var frame = UIFrame(width: .fill, height: .fill)

        if let w = dict["w"] ?? dict["width"] {
            frame.width = UIDimension.parse(w)
        }
        if let h = dict["h"] ?? dict["height"] {
            frame.height = UIDimension.parse(h)
        }
        if let xVal = dict["x"] {
            frame.x = UIDimension.parse(xVal)
        }
        if let yVal = dict["y"] {
            frame.y = UIDimension.parse(yVal)
        }

        return frame
    }

    /// Resolve to a CGRect given a container size
    func resolve(containerSize: CGSize) -> CGRect {
        let width = self.width.resolve(containerSize: containerSize.width)
        let height = self.height.resolve(containerSize: containerSize.height)
        let x = self.x?.resolve(containerSize: containerSize.width) ?? 0
        let y = self.y?.resolve(containerSize: containerSize.height) ?? 0

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
