//
//  HSKeychainIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import Security
import Synchronization
@testable import Hammerspoon_2

/// Builds made without code signing (CI, hs2vm) have no keychain access group, so only a signed
/// local build can run the real-keychain tests
private nonisolated func hasKeychainEntitlement() -> Bool {
    SecurityKeychainStore.entitledAccessGroup() != nil
}

/// Evaluates `promise`, and waits for it to settle into `__value` or `__error`
private func settle(_ harness: JSTestHarness, _ promise: String) async -> Bool {
    harness.eval("""
        var __settled = false, __value = undefined, __error = undefined;
        (\(promise)).then(v => { __value = v; __settled = true }, e => { __error = e; __settled = true });
        """)
    return await harness.waitForAsync(timeout: 5) { harness.evalBool("__settled") == true }
}

@Suite("hs.keychain tests")
struct HSKeychainTests {

    // MARK: - API structure

    @Suite("hs.keychain API structure")
    struct HSKeychainStructureTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeychainModule(engineID: UUID(), store: MockKeychainStore()), as: "keychain")
            return harness
        }

        @Test("functions are functions", arguments: ["set", "get", "remove", "items"])
        func testFunctions(name: String) {
            #expect(makeHarness().evalTypeOf("hs.keychain.\(name)") == "function")
        }

        @Test("isAvailable reflects the store")
        func testIsAvailable() {
            #expect(makeHarness().evalBool("hs.keychain.isAvailable") == true)

            let harness = JSTestHarness()
            harness.loadModule(HSKeychainModule(engineID: UUID(), store: SecurityKeychainStore(accessGroup: nil)),
                               as: "keychain")
            #expect(harness.evalBool("hs.keychain.isAvailable") == false)
        }
    }

    // MARK: - Behaviour, against a fake store

    @Suite("hs.keychain behaviour")
    struct HSKeychainBehaviourTests {
        let store = MockKeychainStore()

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeychainModule(engineID: UUID(), store: store), as: "keychain")
            return harness
        }

        @Test("a stored secret can be read back")
        func testRoundTrip() async {
            let harness = makeHarness()
            harness.eval("hs.keychain.set('svc', 'alice', 's3cret')")
            #expect(!harness.hasException)

            #expect(await settle(harness, "hs.keychain.get('svc', 'alice')"))
            #expect(harness.evalString("__value") == "s3cret")
            #expect(harness.evalBool("__error === undefined") == true)
        }

        @Test("set replaces an existing secret")
        func testReplace() async {
            let harness = makeHarness()
            harness.eval("hs.keychain.set('svc', 'alice', 'one'); hs.keychain.set('svc', 'alice', 'two')")
            #expect(await settle(harness, "hs.keychain.get('svc', 'alice')"))
            #expect(harness.evalString("__value") == "two")
        }

        @Test("get resolves to null for a missing secret")
        func testGetMissing() async {
            let harness = makeHarness()
            #expect(await settle(harness, "hs.keychain.get('svc', 'nobody')"))
            #expect(harness.evalBool("__value === null") == true)
        }

        @Test("get passes its reason to the store, and an omitted reason as nil")
        func testReason() async {
            let harness = makeHarness()
            #expect(await settle(harness, "hs.keychain.get('svc', 'alice', 'log in')"))
            #expect(store.state.withLock { $0.lastReason } == .some("log in"))

            #expect(await settle(harness, "hs.keychain.get('svc', 'alice')"))
            #expect(store.state.withLock { $0.lastReason } == .some(nil))
        }

        @Test("get rejects a missing account with EINVALIDARG")
        func testGetMissingAccount() async {
            let harness = makeHarness()
            #expect(await settle(harness, "hs.keychain.get('svc')"))
            #expect(harness.evalString("__error.code") == "EINVALIDARG")
            #expect(harness.evalBool("__error instanceof Error") == true)
        }

        @Test("get rejects with the store's error code and OSStatus")
        func testGetFailure() async {
            store.state.withLock { $0.failure = KeychainError(status: errSecUserCanceled) }
            let harness = makeHarness()
            #expect(await settle(harness, "hs.keychain.get('svc', 'alice')"))
            #expect(harness.evalString("__error.code") == "ECANCELED")
            #expect(harness.evalInt("__error.status") == Int(errSecUserCanceled))
            #expect(harness.evalBool("__error.message.startsWith('hs.keychain.get(): ')") == true)
        }

        @Test("set passes its options to the store")
        func testOptions() throws {
            let harness = makeHarness()
            harness.eval("""
                hs.keychain.set('svc', 'alice', 'x', { label: 'L', comment: 'C', requireUserPresence: true })
                hs.keychain.set('svc', 'bob', 'y', { synchronizable: true })
                """)
            #expect(!harness.hasException)

            let alice = try #require(store.write(service: "svc", account: "alice"))
            #expect(alice == KeychainWrite(service: "svc", account: "alice", secret: "x", label: "L", comment: "C",
                                           synchronizable: false, requireUserPresence: true))
            let bob = try #require(store.write(service: "svc", account: "bob"))
            #expect(bob.synchronizable && !bob.requireUserPresence && bob.label == nil)
        }

        @Test("set throws EINVALIDARG for bad arguments", arguments: [
            "hs.keychain.set('', 'alice', 'x')",
            "hs.keychain.set('svc', '', 'x')",
            "hs.keychain.set('svc')",
            "hs.keychain.set('svc', 'alice', 'x', { lable: 'typo' })",
            "hs.keychain.set('svc', 'alice', 'x', { label: 42 })",
            "hs.keychain.set('svc', 'alice', 'x', { synchronizable: 1 })",
            "hs.keychain.set('svc', 'alice', 'x', { synchronizable: true, requireUserPresence: true })",
        ])
        func testSetInvalid(script: String) {
            let harness = makeHarness()
            harness.eval("var err; try { \(script) } catch (e) { err = e }")
            #expect(harness.evalString("err && err.code") == "EINVALIDARG")
            #expect(store.state.withLock { $0.items.isEmpty })
        }

        @Test("set throws the store's error")
        func testSetFailure() {
            store.state.withLock { $0.failure = KeychainError(status: errSecInteractionNotAllowed) }
            let harness = makeHarness()
            harness.eval("var err; try { hs.keychain.set('svc', 'alice', 'x') } catch (e) { err = e }")
            #expect(harness.evalString("err.code") == "EINTERACTION")
            #expect(harness.evalInt("err.status") == Int(errSecInteractionNotAllowed))
        }

        @Test("remove reports whether there was a secret")
        func testRemove() async {
            let harness = makeHarness()
            harness.eval("hs.keychain.set('svc', 'alice', 'x')")
            #expect(harness.evalBool("hs.keychain.remove('svc', 'alice')") == true)
            #expect(harness.evalBool("hs.keychain.remove('svc', 'alice')") == false)
            #expect(await settle(harness, "hs.keychain.get('svc', 'alice')"))
            #expect(harness.evalBool("__value === null") == true)
        }

        @Test("items lists secrets without their values, optionally for one service")
        func testItems() {
            let harness = makeHarness()
            harness.eval("""
                hs.keychain.set('b', 'bob', 'secret-1', { label: 'Bob', comment: 'note' })
                hs.keychain.set('a', 'zed', 'secret-2')
                hs.keychain.set('a', 'amy', 'secret-3', { synchronizable: true })
                var all = hs.keychain.items()
                var onlyA = hs.keychain.items('a')
                """)
            #expect(!harness.hasException)
            #expect(harness.evalString("all.map(i => i.service + '/' + i.account).join(',')") == "a/amy,a/zed,b/bob")
            #expect(harness.evalString("onlyA.map(i => i.account).join(',')") == "amy,zed")
            #expect(harness.evalBool("JSON.stringify(all).includes('secret-')") == false)
            #expect(harness.evalString("all[2].label") == "Bob")
            #expect(harness.evalString("all[2].comment") == "note")
            #expect(harness.evalBool("all[2].created instanceof Date") == true)
            #expect(harness.evalBool("all[0].synchronizable") == true)
            #expect(harness.evalBool("all[1].synchronizable") == false)
            #expect(harness.evalBool("all[1].label === undefined") == true)
        }

        @Test("items rejects an empty service")
        func testItemsEmptyService() {
            let harness = makeHarness()
            harness.eval("var err; try { hs.keychain.items('') } catch (e) { err = e }")
            #expect(harness.evalString("err.code") == "EINVALIDARG")
        }

        @Test("without a keychain access group, everything fails with ENOENTITLEMENT")
        func testUnavailable() async {
            let harness = JSTestHarness()
            harness.loadModule(HSKeychainModule(engineID: UUID(), store: SecurityKeychainStore(accessGroup: nil)),
                               as: "keychain")
            for script in ["hs.keychain.set('svc', 'a', 'x')", "hs.keychain.remove('svc', 'a')", "hs.keychain.items()"] {
                harness.eval("var err = undefined; try { \(script) } catch (e) { err = e }")
                #expect(harness.evalString("err && err.code") == "ENOENTITLEMENT", "\(script)")
            }
            #expect(await settle(harness, "hs.keychain.get('svc', 'a')"))
            #expect(harness.evalString("__error.code") == "ENOENTITLEMENT")
        }
    }

    // MARK: - The real keychain

    /// Uses a unique service per test, and removes it afterwards. Nothing here reads a secret
    /// stored with requireUserPresence, which would show an authentication prompt.
    @Suite("hs.keychain real keychain", .serialized,
           .enabled(if: hasKeychainEntitlement(), "This build isn't signed with a keychain access group"))
    struct HSKeychainRealTests {
        let service = "net.tenshu.Hammerspoon-2.tests.\(UUID().uuidString)"

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSKeychainModule.self, as: "keychain")
            harness.eval("var svc = '\(service)'")
            return harness
        }

        /// Removes every item the test stored. items() can't see the ones that require user
        /// presence, so the test names those.
        private func cleanUp(accounts: [String] = []) {
            let store = SecurityKeychainStore()
            let listed = ((try? store.items(service: service)) ?? []).map(\.account)
            for account in listed + accounts {
                _ = try? store.remove(service: service, account: account)
            }
        }

        @Test("set, get, replace, list and remove a secret")
        func testRoundTrip() async {
            defer { cleanUp() }
            let harness = makeHarness()
            #expect(harness.evalBool("hs.keychain.isAvailable") == true)

            harness.eval("hs.keychain.set(svc, 'alice', 'one', { label: 'Test item', comment: 'from a test' })")
            #expect(!harness.hasException)
            #expect(await settle(harness, "hs.keychain.get(svc, 'alice')"))
            #expect(harness.evalString("__value") == "one")

            harness.eval("hs.keychain.set(svc, 'alice', 'two ✓')")
            #expect(await settle(harness, "hs.keychain.get(svc, 'alice')"))
            #expect(harness.evalString("__value") == "two ✓")

            harness.eval("var items = hs.keychain.items(svc)")
            #expect(harness.evalInt("items.length") == 1)
            #expect(harness.evalString("items[0].account") == "alice")
            // Replacing a secret replaces its attributes too
            #expect(harness.evalBool("items[0].label === undefined") == true)
            #expect(harness.evalBool("items[0].modified instanceof Date") == true)

            #expect(harness.evalBool("hs.keychain.remove(svc, 'alice')") == true)
            #expect(harness.evalBool("hs.keychain.remove(svc, 'alice')") == false)
            #expect(await settle(harness, "hs.keychain.get(svc, 'alice')"))
            #expect(harness.evalBool("__value === null") == true)
        }

        @Test("a secret that requires user presence is replaced, left out of items() and removed without a prompt")
        func testUserPresenceItem() {
            defer { cleanUp(accounts: ["bob"]) }
            let harness = makeHarness()
            harness.eval("""
                hs.keychain.set(svc, 'alice', 'plain')
                hs.keychain.set(svc, 'bob', 'guarded', { requireUserPresence: true })
                hs.keychain.set(svc, 'bob', 'guarded again', { requireUserPresence: true })
                """)
            #expect(!harness.hasException)
            // macOS won't reveal anything about it without authenticating, so it isn't listed
            #expect(harness.evalString("hs.keychain.items(svc).map(i => i.account).join(',')") == "alice")
            #expect(harness.evalBool("hs.keychain.remove(svc, 'bob')") == true)
            #expect(harness.evalBool("hs.keychain.remove(svc, 'bob')") == false)
        }
    }
}
