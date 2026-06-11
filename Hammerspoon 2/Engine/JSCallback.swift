//
//  JSCallback.swift
//  Hammerspoon 2
//

import JavaScriptCore

/// Wraps a JS callback value using JSManagedValue to prevent the retain cycle
/// that arises when a JS-exported Swift object stores a JSValue directly.
///
/// **The cycle without JSCallback:**
/// Swift object → JSValue → JSContext → JS wrapper → Swift object
///
/// **With JSCallback:**
/// Swift object → JSManagedValue (VM-tracked, conditional) — no cycle.
/// The VM keeps the managed value alive only while the owner is reachable
/// from JS. When JS GC collects the wrapper, the managed value becomes nil
/// and the owner can be freed.
///
/// **Key design:** the JSVirtualMachine is resolved from `value.context` at
/// init time, so construction works regardless of whether JS is actively
/// executing. This allows `detach(from:)` to work correctly even when called
/// outside a JS execution context (e.g., from `shutdown()`).
///
/// Usage:
/// ```swift
/// self.callback = JSCallback(value: jsValue, owner: self)
///
/// // In deinit or a destroy() method — owner must be passed explicitly
/// // because a weak var to self would already be zeroed in deinit:
/// callback?.detach(from: self)
/// callback = nil
///
/// // To invoke:
/// callback?.value?.call(withArguments: [])
/// ```
final class JSCallback {
    private var managed: JSManagedValue?
    private weak var vm: JSVirtualMachine?

    /// Creates a JSCallback for a value passed through the JS→Swift bridge.
    ///
    /// Returns nil if the value is not an object/function.
    init?(value: JSValue, owner: AnyObject) {
        guard value.isObject else { return nil }
        guard let currentVM = value.context?.virtualMachine else { return nil }

        let managedValue = JSManagedValue(value: value)
        currentVM.addManagedReference(managedValue, withOwner: owner)

        self.managed = managedValue
        self.vm = currentVM
    }

    /// The current JavaScript value. May return nil if the value has been garbage collected
    /// because JS dropped all references to the owner.
    var value: JSValue? { managed?.value }

    /// Call the callback JavaScript function
    /// - Parameter arguments: An array of arguments to pass to the JavaScript function
    /// - Returns: Whatever the JavaScript callback returns
    func call(withArguments arguments: [Any]!) -> JSValue! {
        return value?.call(withArguments: arguments)
    }

    /// Removes the VM-managed reference, allowing both the callback and owner to be collected.
    ///
    /// Call this before the owner is deallocated. Pass the owner explicitly — do not rely
    /// on a stored `weak var` to the owner, as weak references are zeroed before `deinit`
    /// body execution.
    func detach(from owner: AnyObject) {
        guard let managed = managed else { return }
        vm?.removeManagedReference(managed, withOwner: owner)
        self.managed = nil
        self.vm = nil
    }
}
