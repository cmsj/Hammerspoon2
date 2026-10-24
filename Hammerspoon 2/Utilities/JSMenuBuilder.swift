//
//  JSMenuBuilder.swift
//  Hammerspoon 2
//

import AppKit
import JavaScriptCore

/// Builds `NSMenu`s from arrays of JS menu item objects, as accepted by `hs.menubar` and `hs.dockicon`.
///
/// Menu item object keys:
/// - `title` (string, required): The item label. `"-"` (or `"---"`) makes a separator line.
/// - `fn` (function): Called when the item is chosen.
/// - `checked` (boolean): Shows a checkmark next to the item.
/// - `disabled` (boolean): Greys the item out.
/// - `tooltip` (string): Shown when hovering over the item.
/// - `color` (HSColor or hex string): The colour of the title text.
/// - `icon` (HSImage): Shown to the left of the title.
/// - `menu` (array): Nested menu item objects, making a submenu.
///
/// The `fn` callbacks are owned by `owner`, and their handlers are collected in `handlers`, which the caller
/// must keep (and detach from `owner` once done with) for as long as the menu can be used. Reading the
/// entries runs JS, which can do anything to the caller meanwhile, so the caller should only store
/// `handlers` once building is complete, checking its own state hasn't changed underneath it.
@MainActor
struct JSMenuBuilder {
    /// The JS-exported object that owns the entries' callbacks
    let owner: AnyObject
    /// Prefixes log messages, e.g. "hs.menubar"
    let logPrefix: String
    /// The handlers for every item built so far that has a callback
    private(set) var handlers: [JSMenuItemHandler] = []

    init(owner: AnyObject, logPrefix: String) {
        self.owner = owner
        self.logPrefix = logPrefix
    }

    /// Builds a menu from an array of JS menu item objects
    mutating func makeMenu(from entries: JSValue) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in makeItems(from: entries) {
            menu.addItem(item)
        }
        return menu
    }

    /// Builds menu items from an array of JS menu item objects, skipping any without a title
    mutating func makeItems(from entries: JSValue) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let count = Int(entries.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        for i in 0..<count {
            if let entry = entries.objectAtIndexedSubscript(i),
               let item = makeItem(from: entry) {
                items.append(item)
            }
        }
        return items
    }

    private mutating func makeItem(from entry: JSValue) -> NSMenuItem? {
        guard let titleValue = entry.objectForKeyedSubscript("title"),
              !titleValue.isUndefined,
              let title = titleValue.toString() else { return nil }

        if title == "-" || title == "---" {
            return NSMenuItem.separator()
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

        if let dv = entry.objectForKeyedSubscript("disabled"), dv.isBoolean {
            item.isEnabled = !dv.toBool()
        } else {
            item.isEnabled = true
        }

        if let cv = entry.objectForKeyedSubscript("checked"), cv.isBoolean, cv.toBool() {
            item.state = .on
        } else {
            item.state = .off
        }

        if let tv = entry.objectForKeyedSubscript("tooltip"),
           !tv.isUndefined, !tv.isNull,
           let tip = tv.toString() {
            item.toolTip = tip
        }

        if let colorValue = entry.objectForKeyedSubscript("color"),
           !colorValue.isUndefined, !colorValue.isNull {
            if let color = HSColor.fromJSValue(colorValue) {
                item.attributedTitle = NSAttributedString(string: title, attributes: [
                    .foregroundColor: color.nsColor,
                    .font: NSFont.menuFont(ofSize: 0),
                ])
            } else {
                AKWarning("\(logPrefix): Ignoring menu item color for \"\(title)\": expected an HSColor or a hex string")
            }
        }

        if let iv = entry.objectForKeyedSubscript("icon"),
           let hsImage = iv.toObjectOf(HSImage.self) as? HSImage,
           let img = hsImage.image.copy() as? NSImage {
            img.size = NSSize(width: 16, height: 16)
            item.image = img
        }

        if let fv = entry.objectForKeyedSubscript("fn"),
           fv.isObject, !fv.isNull, !fv.isUndefined {
            let handler = JSMenuItemHandler(value: fv, owner: owner, logPrefix: logPrefix)
            handlers.append(handler)
            item.target = handler
            item.action = #selector(JSMenuItemHandler.invoke(_:))
        }

        if let sv = entry.objectForKeyedSubscript("menu"), sv.isArray {
            item.submenu = makeMenu(from: sv)
        }

        return item
    }
}

/// The target of a menu item built by `JSMenuBuilder`, calling its JS function when it's chosen
@MainActor
final class JSMenuItemHandler: NSObject {
    private var callback: JSCallback?
    private let logPrefix: String

    init(value: JSValue, owner: AnyObject, logPrefix: String) {
        self.callback = JSCallback(value: value, owner: owner)
        self.logPrefix = logPrefix
        super.init()
    }

    /// Disconnects the item's function, so choosing it does nothing
    func detach(from owner: AnyObject) {
        callback?.detach(from: owner)
        callback = nil
    }

    @objc func invoke(_ sender: Any?) {
        guard let value = callback?.value else { return }
        value.call(withArguments: [])
        if let ctx = value.context,
           let exception = ctx.exception,
           !exception.isUndefined {
            AKError("\(logPrefix): Error in menu item callback: \(exception.toString() ?? "unknown error")")
            ctx.exception = nil
        }
    }
}

extension Array where Element == JSMenuItemHandler {
    /// Detaches every handler from `owner` and empties the array
    @MainActor
    mutating func detachAll(from owner: AnyObject) {
        for handler in self {
            handler.detach(from: owner)
        }
        removeAll()
    }
}
