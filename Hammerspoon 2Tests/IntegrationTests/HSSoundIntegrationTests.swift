//
//  HSSoundIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.sound tests")
struct HSSoundTests {

    // MARK: - Suite 1: API Structure

    @Suite("hs.sound API structure tests")
    struct HSSoundStructureTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSoundModule.self, as: "sound")
            return harness
        }

        @Test("fromFile is a function")
        func testFromFileIsFunction() {
            makeHarness().expectTrue("typeof hs.sound.fromFile === 'function'")
        }

        @Test("named is a function")
        func testNamedIsFunction() {
            makeHarness().expectTrue("typeof hs.sound.named === 'function'")
        }

        @Test("systemSounds is a function")
        func testSystemSoundsIsFunction() {
            makeHarness().expectTrue("typeof hs.sound.systemSounds === 'function'")
        }

        @Test("named returns null for a nonexistent sound without throwing")
        func testNamedNonexistent() {
            let harness = makeHarness()
            harness.eval("var r = hs.sound.named('__this_sound_does_not_exist__')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }

        @Test("fromFile returns null for a nonexistent path without throwing")
        func testFromFileBadPath() {
            let harness = makeHarness()
            harness.eval("var r = hs.sound.fromFile('/nonexistent/path/sound.aiff')")
            harness.expectTrue("r === null || r === undefined")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 2: System Sounds

    @Suite("hs.sound system sounds tests")
    struct HSSoundSystemSoundsTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSoundModule.self, as: "sound")
            return harness
        }

        @Test("systemSounds returns an array")
        func testSystemSoundsReturnsArray() {
            makeHarness().expectTrue("Array.isArray(hs.sound.systemSounds())")
        }

        @Test("systemSounds returns a non-empty array")
        func testSystemSoundsNonEmpty() {
            makeHarness().expectTrue("hs.sound.systemSounds().length > 0")
        }

        @Test("systemSounds contains Basso")
        func testSystemSoundsContainsBasso() {
            makeHarness().expectTrue("hs.sound.systemSounds().includes('Basso')")
        }

        @Test("systemSounds is sorted")
        func testSystemSoundsSorted() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var sounds = hs.sound.systemSounds()
                    var sorted = sounds.slice().sort()
                    return JSON.stringify(sounds) === JSON.stringify(sorted)
                })()
            """)
        }
    }

    // MARK: - Suite 3: Sound Object Properties and Methods

    @Suite("hs.sound object tests")
    struct HSSoundObjectTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSoundModule.self, as: "sound")
            return harness
        }

        @Test("named returns an object with expected properties")
        func testNamedObjectProperties() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso')")
            harness.expectTrue("typeof s === 'object'")
            harness.expectTrue("typeof s.identifier === 'string' && s.identifier.length > 0")
            harness.expectTrue("typeof s.duration === 'number' && s.duration > 0")
            harness.expectTrue("typeof s.currentTime === 'number'")
            harness.expectTrue("typeof s.volume === 'number'")
            harness.expectTrue("typeof s.loops === 'boolean'")
            harness.expectTrue("typeof s.isPlaying === 'boolean'")
            #expect(!harness.hasException)
        }

        @Test("named sound has the expected name property")
        func testNamedSoundHasName() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso')")
            harness.expectEqual("s.name", "Basso")
            #expect(!harness.hasException)
        }

        @Test("isPlaying is false before play is called")
        func testIsPlayingInitiallyFalse() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso')")
            harness.expectTrue("s.isPlaying === false")
            #expect(!harness.hasException)
        }

        @Test("two named calls produce objects with different identifiers")
        func testUniqueIdentifiers() {
            let harness = makeHarness()
            harness.expectTrue("""
                (function() {
                    var a = hs.sound.named('Basso')
                    var b = hs.sound.named('Glass')
                    return a.identifier !== b.identifier
                })()
            """)
            #expect(!harness.hasException)
        }

        @Test("volume assignment round-trips correctly")
        func testVolumeRoundTrip() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso'); s.volume = 0.5")
            harness.expectTrue("Math.abs(s.volume - 0.5) < 0.02")
            #expect(!harness.hasException)
        }

        @Test("loops assignment round-trips correctly")
        func testLoopsRoundTrip() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso'); s.loops = true")
            harness.expectTrue("s.loops === true")
            #expect(!harness.hasException)
        }

        @Test("play returns the sound object for chaining")
        func testPlayReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso'); var r = s.play(); s.stop()")
            harness.expectTrue("r === s")
            #expect(!harness.hasException)
        }

        @Test("stop returns the sound object for chaining")
        func testStopReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso'); s.play(); var r = s.stop()")
            harness.expectTrue("r === s")
            #expect(!harness.hasException)
        }

        @Test("setCallback returns the sound object for chaining")
        func testSetCallbackReturnsSelf() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso'); var r = s.setCallback(function(){})")
            harness.expectTrue("r === s")
            #expect(!harness.hasException)
        }

        @Test("removeCallback returns the sound object for chaining")
        func testRemoveCallbackReturnsSelf() {
            let harness = makeHarness()
            harness.eval("""
                var s = hs.sound.named('Basso')
                s.setCallback(function(){})
                var r = s.removeCallback()
            """)
            harness.expectTrue("r === s")
            #expect(!harness.hasException)
        }

        @Test("destroy can be called without throwing")
        func testDestroyDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso'); s.destroy()")
            #expect(!harness.hasException)
        }

        @Test("destroy can be called twice without throwing")
        func testDoubleDestroyDoesNotThrow() {
            let harness = makeHarness()
            harness.eval("var s = hs.sound.named('Basso'); s.destroy(); s.destroy()")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 4: Callback

    @Suite("hs.sound callback tests")
    struct HSSoundCallbackTests {
        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSSoundModule.self, as: "sound")
            return harness
        }

        @Test("callback fires when a sound finishes playing")
        func testCallbackFiresOnCompletion() {
            let harness = makeHarness()
            var callbackFired = false
            harness.registerCallback("onDone") {
                callbackFired = true
            }
            harness.eval("""
                var s = hs.sound.named('Basso')
                s.setCallback(function() {
                    __test_callback('onDone')
                })
                s.play()
            """)
            let ok = harness.waitFor(timeout: 3.0) { callbackFired }
            #expect(ok, "Callback should have fired after sound finished")
            #expect(!harness.hasException)
        }
    }

    // MARK: - Suite 5: Memory Leak Tests

    @Suite("hs.sound memory leak tests")
    struct HSSoundLeakTests {
        @Test("HSSound is released after module shutdown")
        func testSoundDoesNotLeakAfterShutdown() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSSoundModule.self, as: "sound")

                harness.eval("var s = hs.sound.named('Basso')")
                harness.eval("s.play()")

                if let swift = harness.evalValue("s")?.toObjectOf(HSSound.self) as? HSSound {
                    tracker.track(swift)
                }

                harness.eval("s = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }

        @Test("HSSound with callback does not leak after shutdown")
        func testSoundWithCallbackDoesNotLeak() {
            let tracker = WeakLeakTracker()
            autoreleasepool {
                let harness = JSTestHarness()
                harness.loadModule(HSSoundModule.self, as: "sound")

                harness.eval("""
                    var s = hs.sound.named('Basso')
                    s.setCallback(function() {})
                    s.play()
                """)

                if let swift = harness.evalValue("s")?.toObjectOf(HSSound.self) as? HSSound {
                    tracker.track(swift)
                }

                harness.eval("s = null")
                harness.shutdownForLeakTest()
            }
            tracker.assertNoLeaks()
        }
    }
}
