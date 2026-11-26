//
//  WindowNeighbours.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import AXSwift

/// Finds the windows lying in a direction from a window, for `HSWindow.windowsToEast()` and
/// friends. The ranking follows Hammerspoon 1's `hs.window:windowsToEast()`.
enum WindowNeighbours {
    enum Direction: String, CaseIterable {
        case east, west, north, south
    }

    /// A window being ranked: its ID, frame (top-left origin) and z-order (0 is frontmost)
    struct Candidate: Equatable {
        let id: Int
        let frame: CGRect
        let z: Int
    }

    /// Ranks `candidates` lying in `direction` from a window, nearest first.
    ///
    /// A candidate counts if its centre is further along `direction` than the window's centre (with
    /// `strict`, by more than it is off to the side, i.e. within 45° of the axis). Each is scored by
    /// its distance divided by cos(A/2), where A is the angle between `direction` and the line to
    /// its centre, so windows straight ahead beat nearer ones off to the side. The z-order is added
    /// as a tie-break.
    ///
    /// With `frontmost`, windows behind the starting window that it almost entirely covers are left
    /// out, and a window that overlaps a nearer one and is in front of it is moved ahead of it, so
    /// windows that can actually be seen come first.
    /// - Returns: The IDs of the matching candidates, nearest first
    static func rank(from origin: Candidate, candidates: [Candidate], direction: Direction, frontmost: Bool, strict: Bool) -> [Int] {
        var pool = candidates.filter { $0.id != origin.id && !$0.frame.isEmpty }
        if frontmost {
            pool.removeAll { $0.z > origin.z && isFullyBehind($0.frame, origin.frame) }
        }

        let from = CGPoint(x: origin.frame.midX, y: origin.frame.midY)
        struct Scored {
            let candidate: Candidate
            let score: Double
        }
        var scored: [Scored] = []
        for candidate in pool {
            let dx = candidate.frame.midX - from.x
            let dy = candidate.frame.midY - from.y
            // How far the candidate is along the direction, and how far off to the side. y grows
            // downwards, so north is towards smaller y.
            let (forward, lateral): (Double, Double)
            switch direction {
            case .east: (forward, lateral) = (dx, dy)
            case .west: (forward, lateral) = (-dx, dy)
            case .north: (forward, lateral) = (-dy, dx)
            case .south: (forward, lateral) = (dy, dx)
            }
            guard forward > (strict ? abs(lateral) : 0) else { continue }
            let angle = atan2(lateral, forward)
            let score = hypot(forward, lateral) / cos(angle / 2) + Double(candidate.z)
            scored.append(Scored(candidate: candidate, score: score))
        }
        scored.sort { $0.score < $1.score }

        var ranked = scored.map(\.candidate)
        if frontmost {
            // Move any window that's in front of, and overlaps, a nearer one ahead of it. Each swap
            // puts a window with a smaller z-order at position i, so this always finishes.
            var i = 0
            while i < ranked.count {
                var swapped = false
                for j in ranked.indices.dropFirst(i + 1) where ranked[j].z < ranked[i].z {
                    let overlap = ranked[i].frame.intersection(ranked[j].frame)
                    if !overlap.isNull && overlap.width > 5 && overlap.height > 5 {
                        ranked.swapAt(i, j)
                        swapped = true
                        break
                    }
                }
                if !swapped {
                    i += 1
                }
            }
        }
        return ranked.map(\.id)
    }

    /// Whether at least 95% of `frame` lies within `front`
    private static func isFullyBehind(_ frame: CGRect, _ front: CGRect) -> Bool {
        let overlap = frame.intersection(front)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= frame.width * frame.height * 0.95
    }

    // MARK: - Live windows

    /// The IDs of the ordinary windows on screen, front to back
    @MainActor
    static func onScreenWindowIDs() -> [(pid: pid_t, id: CGWindowID)] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                return nil
            }
            return (pid, id)
        }
    }

    /// The windows on screen, front to back
    @MainActor
    static func onScreenWindows() -> [HSWindow] {
        let ordered = onScreenWindowIDs()

        return withAXTimeoutLimit(0.25) {
            var byID: [CGWindowID: HSWindow] = [:]
            var seenPIDs = Set<pid_t>()
            for (pid, _) in ordered where seenPIDs.insert(pid).inserted {
                guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
                for element in WindowEnumerator.windowElements(for: app) {
                    let id = WindowEnumerator.windowID(of: element)
                    if id != 0 {
                        byID[id] = HSWindow(element: element, app: app)
                    }
                }
            }
            return ordered.compactMap { byID[$0.id] }
        }
    }

    /// The windows in `direction` from `window`, nearest first.
    /// - Parameters:
    ///   - candidates: The windows to choose from, or nil for every window on screen. Windows that
    ///     aren't on screen are ignored either way.
    @MainActor
    static func windows(from window: HSWindow, in direction: Direction, candidates: [HSWindow]?, frontmost: Bool, strict: Bool) -> [HSWindow] {
        guard let originFrame = window.frame?.rect else { return [] }

        let zOrder = onScreenWindowIDs().map { Int($0.id) }
        var zIndex: [Int: Int] = [:]
        for (index, id) in zOrder.enumerated() where zIndex[id] == nil {
            zIndex[id] = index
        }

        let pool = candidates ?? onScreenWindows()
        var byID: [Int: HSWindow] = [:]
        var ranked: [Candidate] = []
        for candidate in pool {
            guard let z = zIndex[candidate.id], byID[candidate.id] == nil, let frame = candidate.frame?.rect else { continue }
            byID[candidate.id] = candidate
            ranked.append(Candidate(id: candidate.id, frame: frame, z: z))
        }

        // A window that isn't on screen goes behind all of them
        let origin = Candidate(id: window.id, frame: originFrame, z: zIndex[window.id] ?? zOrder.count)
        return rank(from: origin, candidates: ranked, direction: direction, frontmost: frontmost, strict: strict).compactMap { byID[$0] }
    }
}
