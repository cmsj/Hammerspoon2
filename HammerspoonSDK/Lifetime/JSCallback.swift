//
//  JSCallback.swift
//  HammerspoonSDK
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
@MainActor
public final class JSCallback {
    private var managed: JSManagedValue?
    private weak var vm: JSVirtualMachine?
    private weak var context: JSContext?

    /// Creates a JSCallback for a value passed through the JS→Swift bridge.
    ///
    /// Returns nil if the value is not an object/function.
    public init?(value: JSValue, owner: AnyObject, silentOnUndefined: Bool = false) {
        if silentOnUndefined && value.isUndefined {
            // We were called from a place that allows optional callbacks, so we silently return with no error
            return nil
        }
        guard value.isCallable else {
            AKError("Unable to create JSCallback: value is not a function")
            return nil
        }
        guard let context = value.context, let currentVM = context.virtualMachine else {
            AKError("Unable to create JSCallback: value has no VM")
            return nil
        }

        let managedValue = JSManagedValue(value: value)
        currentVM.addManagedReference(managedValue, withOwner: owner)

        self.managed = managedValue
        self.vm = currentVM
        self.context = context
    }

    /// The current JavaScript value. May return nil if the value has been garbage collected
    /// because JS dropped all references to the owner.
    public var value: JSValue? { managed?.value }

    /// Call the callback JavaScript function
    /// - Parameter arguments: An array of arguments to pass to the JavaScript function
    /// - Returns: Whatever the JavaScript callback returns
    public func call(withArguments arguments: [Any]!) -> JSValue! {
        return value?.call(withArguments: arguments)
    }

    /// Moves the callback to a new owner, so it lives as long as `newOwner` is reachable from JS
    /// rather than `oldOwner`. For example, a web view element hands its callbacks to the window
    /// it's attached to, since the user holds the window, not the element.
    /// - Parameters:
    ///   - oldOwner: The current owner
    ///   - newOwner: The new owner, which must be a JS-exported object
    public func transferOwnership(from oldOwner: AnyObject, to newOwner: AnyObject) {
        guard let managed, let vm else { return }
        vm.addManagedReference(managed, withOwner: newOwner)
        vm.removeManagedReference(managed, withOwner: oldOwner)
    }

    /// Removes the VM-managed reference, allowing both the callback and owner to be collected.
    ///
    /// Call this before the owner is deallocated. Pass the owner explicitly — do not rely
    /// on a stored `weak var` to the owner, as weak references are zeroed before `deinit`
    /// body execution.
    public func detach(from owner: AnyObject) {
        guard let managed = managed else { return }
        vm?.removeManagedReference(managed, withOwner: owner)
        self.managed = nil
        self.vm = nil
        DeferredManagedValueRelease.shared.add(managed, from: context)
    }

    isolated deinit {
        // Dropped without detach(from:). The value is still in its owner's graph, so this only
        // covers a scan that is already in flight, but that's the common case: the owner is
        // usually gone too, and with it the wrapper whose scan could pick the value up again.
        if let managed { DeferredManagedValueRelease.shared.add(managed, from: context) }
    }
}

/// Keeps released `JSManagedValue`s alive until a GC cycle has finished marking since they
/// were released.
///
/// When the GC marks a JS-exported object, a heap helper thread walks that object's managed
/// references (`scanExternalObjectGraph`), retaining and autoreleasing each `JSManagedValue` it
/// finds. If we drop our last reference before the helper pops its autorelease pool,
/// `-[JSManagedValue dealloc]` runs on the helper thread and takes the JSLock, which deadlocks
/// against a mutator that holds the JSLock while waiting for the GC to finish (#375).
///
/// Once `removeManagedReference` has run, no new scan can find the value, so it's enough to
/// outlive the scans already in flight, and those all finish before their cycle's marking does.
/// To find out when that has happened, values are released in batches, and each batch gets a
/// `GCSentinel`: a native object wrapped in a JS object that nothing references, created after
/// every value in the batch was released. JSC only finalizes the wrapper, releasing the sentinel,
/// after a cycle's marking has finished. Cycles don't overlap, so that's either the cycle that was
/// running when the values were released or a later one, and either way every scan that could
/// have picked them up is over. The sentinel then tells us that batch, and any older one, is
/// safe to drop.
@MainActor
final class DeferredManagedValueRelease {
    static let shared = DeferredManagedValueRelease()

    private struct Batch {
        let token: Int
        let values: [JSManagedValue]
    }

    /// Batches are tracked per context, because a GC cycle in one VM says nothing about another.
    private struct ContextState {
        weak var context: JSContext?
        var pending: [JSManagedValue] = []
        var sealed: [Batch] = []
        var sealScheduled = false
    }

    private var states: [ObjectIdentifier: ContextState] = [:]
    private var nextToken = 0

    private init() {}

    /// Holds `value` until it's safe to release.
    /// - Parameters:
    ///   - value: A managed value that has already been removed from its owners
    ///   - context: The context the value came from. If it has gone, so has every wrapper that
    ///     could have been scanning the value, and it's released straight away.
    func add(_ value: JSManagedValue, from context: JSContext?) {
        guard let context else { return }
        let id = ObjectIdentifier(context)
        var state = states[id] ?? ContextState(context: context)
        if state.context !== context {
            // A new context at a dead one's address. The old one's values are safe to drop.
            state = ContextState(context: context)
        }
        state.pending.append(value)
        if !state.sealScheduled {
            state.sealScheduled = true
            // One sentinel per main-actor turn, rather than one per value.
            Task { self.seal(id) }
        }
        states[id] = state
    }

    /// Closes the pending batch and creates its sentinel.
    private func seal(_ id: ObjectIdentifier) {
        guard var state = states[id] else { return }
        state.sealScheduled = false
        guard let context = state.context else {
            // The context has gone, and with it every wrapper that could have been scanning.
            states[id] = nil
            return
        }
        nextToken += 1
        state.sealed.append(Batch(token: nextToken, values: state.pending))
        state.pending = []
        states[id] = state
        // Wrapped and immediately dropped, so the wrapper is garbage from the start.
        _ = JSValue(object: GCSentinel(contextID: id, token: nextToken), in: context)
    }

    /// Called when a sentinel's wrapper has been finalized.
    fileprivate func cycleCompleted(contextID id: ObjectIdentifier, token: Int) {
        guard var state = states[id] else { return }
        // Every batch up to this one was sealed before the sentinel was created, so a cycle that
        // finished marking after the sentinel existed also covers them. This is where the last
        // references are dropped, on the main thread.
        state.sealed.removeAll { $0.token <= token }
        if state.context == nil && state.pending.isEmpty && state.sealed.isEmpty {
            states[id] = nil
        } else {
            states[id] = state
        }
    }
}

/// Released when JSC finalizes its JS wrapper, which happens only after a GC cycle has
/// finished marking.
private nonisolated final class GCSentinel: NSObject {
    private let contextID: ObjectIdentifier
    private let token: Int

    init(contextID: ObjectIdentifier, token: Int) {
        self.contextID = contextID
        self.token = token
    }

    deinit {
        // Finalization may happen on any thread; the batches belong to the main actor.
        Task { @MainActor [contextID, token] in
            DeferredManagedValueRelease.shared.cycleCompleted(contextID: contextID, token: token)
        }
    }
}

extension JSValue {
    /// Whether the value is a JS function. JavaScriptCore's ObjC API has no direct way to ask.
    var isCallable: Bool {
        guard isObject, let context else { return false }
        let globalContext = unsafe context.jsGlobalContextRef
        guard let object = unsafe JSValueToObject(globalContext, jsValueRef, nil) else { return false }
        return unsafe JSObjectIsFunction(globalContext, object)
    }
}
