//
//  AXObserverHub.swift
//  Hammerspoon 2
//

import Foundation
import AppKit
import ApplicationServices
import AXSwift

/// The process-wide owner of Accessibility observers, shared by every module (and every engine)
/// that needs AX notifications.
///
/// Each application gets at most one `AXObserver`, however many clients watch it, and each
/// element+notification pair is registered with it once, however many clients ask for it. A
/// registration is removed from the observer when its last client lets go of it, and the observer
/// is stopped when its application has no registrations left.
///
/// Clients are plain Swift objects (see ``Client``), not JS-facing ones, so modules can build
/// Swift-level features on AX notifications without going through `hs.ax`'s JS watchers.
///
/// Delivery is by process and notification, not element: a client receives every notification of
/// a type it registered for in that process, whatever element it was delivered with, because AX
/// delivers notifications registered on an application element with the descendant they happened
/// on (e.g. AXWindowCreated arrives with the new window). Each client routes them to the right
/// place itself.
@_documentation(visibility: private)
@MainActor
final class AXObserverHub {
    static let shared = AXObserverHub()

    /// One client's interest in AX notifications. Registrations are made and removed through the
    /// client, and all of them are removed by ``invalidate()``, or when the client is released.
    /// How a client receives the notifications it registered for
    typealias Handler = @MainActor (_ element: UIElement, _ notification: UIElement.AXNotification, _ pid: pid_t) -> Void

    final class Client {
        fileprivate let handler: Handler
        fileprivate weak var hub: AXObserverHub?

        fileprivate init(hub: AXObserverHub, handler: @escaping Handler) {
            self.hub = hub
            self.handler = handler
        }

        isolated deinit {
            hub?.release(ObjectIdentifier(self))
        }

        /// Registers for `notification` on `element`, which belongs to process `pid`. Registering
        /// a pair this client already has is not an error.
        func add(_ notification: UIElement.AXNotification, element: UIElement, pid: pid_t) throws(AXError) {
            guard let hub else { throw AXError.failure }
            try hub.add(Registration(pid: pid, element: element, notification: notification), for: self)
        }

        /// Removes this client's registration for `notification` on `element`, if it has one
        func remove(_ notification: UIElement.AXNotification, element: UIElement) {
            hub?.removeRegistrations(for: ObjectIdentifier(self)) { $0.element == element && $0.notification == notification }
        }

        /// Removes all of this client's registrations on `element`
        func removeAll(element: UIElement) {
            hub?.removeRegistrations(for: ObjectIdentifier(self)) { $0.element == element }
        }

        /// Removes all of this client's registrations in process `pid`
        func removeAll(pid: pid_t) {
            hub?.removeRegistrations(for: ObjectIdentifier(self)) { $0.pid == pid }
        }

        /// Removes all of this client's registrations. The client stays usable.
        func invalidate() {
            hub?.removeRegistrations(for: ObjectIdentifier(self)) { _ in true }
        }

        /// Whether this client is registered for `notification` on `element`
        func isRegistered(_ notification: UIElement.AXNotification, element: UIElement) -> Bool {
            hub?.registrations(of: self).contains { $0.element == element && $0.notification == notification } ?? false
        }

        /// The number of this client's registrations, for tests
        var registrationCount: Int { hub?.registrations(of: self).count ?? 0 }
    }

    /// One element+notification pair in one process
    fileprivate struct Registration: Hashable {
        let pid: pid_t
        let element: UIElement
        let notification: UIElement.AXNotification
    }

    /// A client, held weakly so a released client never receives notifications
    private struct WeakClient {
        weak var client: Client?
    }

    private var observers: [pid_t: Observer] = [:]
    /// The clients holding each registration. A registration is in the observer exactly while
    /// it's a key here.
    private var holders: [Registration: Set<ObjectIdentifier>] = [:]
    private var clients: [ObjectIdentifier: WeakClient] = [:]
    private var terminationObserver: (any NSObjectProtocol)?

    private init() {
        // Drop everything belonging to an application that quits: its observer and elements are
        // dead, so nothing registered there can fire again. Clients that keep their own state
        // about the process watch for this themselves. The PID is read inside the closure, so the
        // notification itself needn't cross into the main actor.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.forgetProcess(pid)
            }
        }
    }

    /// Makes a new client, which receives the notifications it registers for through `handler`
    func makeClient(handler: @escaping Handler) -> Client {
        let client = Client(hub: self, handler: handler)
        clients[ObjectIdentifier(client)] = WeakClient(client: client)
        return client
    }

    /// The number of processes with an observer, for tests
    var observerCount: Int { observers.count }

    /// Whether process `pid` has an observer, for tests
    func hasObserver(for pid: pid_t) -> Bool { observers[pid] != nil }

    // MARK: - Registration

    private func registrations(of client: Client) -> [Registration] {
        let id = ObjectIdentifier(client)
        return holders.compactMap { $0.value.contains(id) ? $0.key : nil }
    }

    private func add(_ registration: Registration, for client: Client) throws(AXError) {
        let id = ObjectIdentifier(client)
        if holders[registration] != nil {
            holders[registration]?.insert(id)
            return
        }

        let pid = registration.pid
        let createdObserver = observers[pid] == nil
        let observer: Observer
        if let existing = observers[pid] {
            observer = existing
        } else {
            observer = try Observer(processID: pid) { [weak self] (_: Observer, element: UIElement, notification: UIElement.AXNotification) in
                self?.deliver(element: element, notification: notification, pid: pid)
            }
            observers[pid] = observer
            AKDebug("AXObserverHub: Created observer for PID \(pid)")
        }

        do {
            try observer.addNotification(registration.notification, forElement: registration.element)
        } catch {
            if createdObserver {
                observers.removeValue(forKey: pid)?.stop()
            }
            throw error
        }
        holders[registration] = [id]
    }

    /// Removes every registration of a client that's going away, and the client itself
    private func release(_ id: ObjectIdentifier) {
        removeRegistrations(for: id) { _ in true }
        clients.removeValue(forKey: id)
    }

    private func removeRegistrations(for id: ObjectIdentifier, where predicate: (Registration) -> Bool) {
        var emptiedPIDs = Set<pid_t>()

        for (registration, ids) in holders where ids.contains(id) && predicate(registration) {
            var remaining = ids
            remaining.remove(id)
            if !remaining.isEmpty {
                holders[registration] = remaining
                continue
            }

            holders.removeValue(forKey: registration)
            emptiedPIDs.insert(registration.pid)
            guard let observer = observers[registration.pid] else { continue }
            do {
                try observer.removeNotification(registration.notification, forElement: registration.element)
            } catch {
                // Expected when the element has already gone away, taking its registrations with it
                AKDebug("AXObserverHub: Couldn't remove \(registration.notification.rawValue) for PID \(registration.pid): \(error)")
            }
        }

        for pid in emptiedPIDs where !holders.keys.contains(where: { $0.pid == pid }) {
            observers.removeValue(forKey: pid)?.stop()
            AKDebug("AXObserverHub: Removed observer for PID \(pid) (no more registrations)")
        }
    }

    // MARK: - Delivery

    /// Hands a notification to every client registered for its type in process `pid`. Internal
    /// rather than private so tests can simulate delivery, since real AX callbacks don't reach
    /// the test runner.
    func deliver(element: UIElement, notification: UIElement.AXNotification, pid: pid_t) {
        // Collected up front, since a handler may add or remove registrations
        var targetIDs = Set<ObjectIdentifier>()
        for (registration, ids) in holders where registration.pid == pid && registration.notification == notification {
            targetIDs.formUnion(ids)
        }
        let targets = targetIDs.compactMap { clients[$0]?.client }
        for client in targets {
            client.handler(element, notification, pid)
        }
    }

    // MARK: - Process termination

    /// Discards every registration, and the observer, for a process that has quit, without
    /// telling AX about elements that no longer exist
    func forgetProcess(_ pid: pid_t) {
        holders = holders.filter { $0.key.pid != pid }
        observers.removeValue(forKey: pid)?.stop()
        clients = clients.filter { $0.value.client != nil }
    }
}
