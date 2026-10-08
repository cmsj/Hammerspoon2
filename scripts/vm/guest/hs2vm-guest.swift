//
//  hs2vm-guest.swift
//  Runs INSIDE the guest via `tart exec` (whose guest agent holds Accessibility and PostEvent)
//  to drive the GUI session: synthesize mouse and keyboard input, and close notification banners.
//
//  This replaces VNC, whose Virtualization.framework server asserts (killing the whole VM) when
//  setting up some client connections.
//
//  Usage:
//    hs2vm-guest click|doubleclick|rightclick|move <x> <y>
//    hs2vm-guest drag <x1> <y1> <x2> <y2>
//    hs2vm-guest key <chord> [chord...]      e.g. key cmd+space   key cmd+a delete
//    hs2vm-guest type <text>
//    hs2vm-guest dismiss-notifications [timeout-seconds]
//
//  Coordinates are screenshot pixels (as `screencapture` produces them), converted to points
//  using the main display's backing scale factor.
//

import AppKit
import ApplicationServices

struct UsageError: Error, CustomStringConvertible {
    let description: String
}

// MARK: - Mouse

let source = CGEventSource(stateID: .hidSystemState)
let scale = NSScreen.main?.backingScaleFactor ?? 1

func point(_ x: String, _ y: String) throws -> CGPoint {
    guard let x = Double(x), let y = Double(y) else { throw UsageError(description: "bad coordinates \(x),\(y)") }
    return CGPoint(x: x / scale, y: y / scale)
}

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(20_000)
}

func mouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left, clickState: Int64 = 1) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
    event?.setIntegerValueField(.mouseEventClickState, value: clickState)
    post(event)
}

func click(at point: CGPoint, button: CGMouseButton, count: Int) {
    let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
    mouse(.mouseMoved, at: point)
    for clickState in 1...count {
        mouse(down, at: point, button: button, clickState: Int64(clickState))
        mouse(up, at: point, button: button, clickState: Int64(clickState))
    }
}

func drag(from start: CGPoint, to end: CGPoint, steps: Int = 20) {
    mouse(.mouseMoved, at: start)
    mouse(.leftMouseDown, at: start)
    for step in 1...steps {
        let t = Double(step) / Double(steps)
        mouse(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
    }
    mouse(.leftMouseUp, at: end)
}

// MARK: - Keyboard

/// US ANSI virtual key codes (Carbon kVK_*).
let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
    "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
    ".": 47, "`": 50,
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53,
    "esc": 53, "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
    "f10": 109, "f11": 103, "f12": 111,
]

let modifiers: [String: (code: CGKeyCode, flag: CGEventFlags)] = [
    "cmd": (55, .maskCommand), "command": (55, .maskCommand),
    "shift": (56, .maskShift),
    "alt": (58, .maskAlternate), "opt": (58, .maskAlternate), "option": (58, .maskAlternate),
    "ctrl": (59, .maskControl), "control": (59, .maskControl),
    "fn": (63, .maskSecondaryFn),
]

func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
    event?.flags = flags
    post(event)
}

/// Presses e.g. "cmd+shift+4": modifiers down in order, the key, then modifiers up in reverse.
func chord(_ spec: String) throws {
    let parts = spec.lowercased().split(separator: "+").map(String.init)
    guard let last = parts.last, let code = keyCodes[last] else { throw UsageError(description: "unknown key in '\(spec)'") }
    var held: [(code: CGKeyCode, flag: CGEventFlags)] = []
    var flags: CGEventFlags = []
    for name in parts.dropLast() {
        guard let modifier = modifiers[name] else { throw UsageError(description: "unknown modifier '\(name)' in '\(spec)'") }
        flags.insert(modifier.flag)
        key(modifier.code, down: true, flags: flags)
        held.append(modifier)
    }
    key(code, down: true, flags: flags)
    key(code, down: false, flags: flags)
    for modifier in held.reversed() {
        flags.remove(modifier.flag)
        key(modifier.code, down: false, flags: flags)
    }
}

/// Types text as Unicode strings rather than key codes, so it's layout-independent.
func type(_ text: String) {
    for character in text {
        let utf16 = Array(String(character).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            post(event)
        }
    }
}

// MARK: - Notifications

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

/// Depth-first search for elements offering a close action: single banners expose a named
/// custom "Close" action alongside AXPress, and stacks of banners expose "Clear All".
func closeActions(in element: AXUIElement, depth: Int = 0) -> [(AXUIElement, String)] {
    var found: [(AXUIElement, String)] = []
    var names: CFArray?
    if AXUIElementCopyActionNames(element, &names) == .success, let names = names as? [String],
       let close = names.first(where: { $0 == "AXClose" || $0.hasPrefix("Name:Close") || $0.hasPrefix("Name:Clear All") }) {
        found.append((element, close))
    }
    guard depth < 12, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return found }
    for child in children { found += closeActions(in: child, depth: depth + 1) }
    return found
}

/// Closes banners as they appear until none have arrived for 5s after the first, or the
/// timeout passes. Boot-time banners arrive in bursts (Background Activity, then Xcode's
/// extensions), and the Cirrus Labs one never goes away by itself.
func dismissNotifications(timeout: Double) -> Int {
    let deadline = Date().addingTimeInterval(timeout)
    var closed = 0
    var lastClose: Date?
    while true {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui") {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            for window in attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                for (element, action) in closeActions(in: window)
                    where AXUIElementPerformAction(element, action as CFString) == .success {
                    closed += 1
                    lastClose = Date()
                }
            }
        }
        if let lastClose, Date().timeIntervalSince(lastClose) >= 5 { return closed }
        if Date() >= deadline { return closed }
        Thread.sleep(forTimeInterval: 0.5)
    }
}

// MARK: - Main

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw UsageError(description: "usage: hs2vm-guest <command> [args]") }
    let rest = Array(args.dropFirst())
    switch command {
    case "click", "doubleclick", "rightclick", "move":
        guard rest.count == 2 else { throw UsageError(description: "usage: \(command) <x> <y>") }
        let at = try point(rest[0], rest[1])
        switch command {
        case "move": mouse(.mouseMoved, at: at)
        case "rightclick": click(at: at, button: .right, count: 1)
        case "doubleclick": click(at: at, button: .left, count: 2)
        default: click(at: at, button: .left, count: 1)
        }
    case "drag":
        guard rest.count == 4 else { throw UsageError(description: "usage: drag <x1> <y1> <x2> <y2>") }
        drag(from: try point(rest[0], rest[1]), to: try point(rest[2], rest[3]))
    case "key":
        guard !rest.isEmpty else { throw UsageError(description: "usage: key <chord> [chord...]") }
        for spec in rest {
            try chord(spec)
            usleep(50_000)
        }
    case "type":
        guard rest.count == 1 else { throw UsageError(description: "usage: type <text>") }
        type(rest[0])
    case "dismiss-notifications":
        print("closed \(dismissNotifications(timeout: Double(rest.first ?? "") ?? 0)) notification(s)")
    default:
        throw UsageError(description: "unknown command \(command)")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("hs2vm-guest: \(error)\n".utf8))
    exit(1)
}
