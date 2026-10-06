//
//  HSCameraIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
import AVFoundation
@testable import Hammerspoon_2

private nonisolated func hasNoCamera() -> Bool {
    let deviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .external,
        .continuityCamera,
    ]
    let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: deviceTypes,
        mediaType: .video,
        position: .unspecified
    )
    return session.devices.isEmpty
}

private nonisolated func hasCameraPermission() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .video) == .authorized
}

@Suite("hs.camera tests", .serialized)
struct HSCameraTests {

    // MARK: - API Structure Tests (no hardware required)
    @Suite("hs.camera API structure tests", .serialized)
    struct HSCameraAPIStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCameraModule.self, as: "camera")
            return harness
        }

        @Test("_addWatcher reports success, then refuses a second subscription by returning false")
        func testAddWatcherReportsRefusal() {
            let harness = makeHarness()
            harness.eval("""
            var first = hs.camera._addWatcher(function() {});
            var second = hs.camera._addWatcher(function() {});
            hs.camera._removeWatcher();
            """)
            #expect(!harness.hasException)
            #expect(harness.evalBool("first") == true)
            #expect(harness.evalBool("second") == false)
        }

        @Test("hs.camera object exists")
        func testModuleExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.camera") == "object")
        }

        @Test("all() method exists and returns an array")
        func testAllMethodExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.camera.all") == "function")
            harness.expectTrue("Array.isArray(hs.camera.all())")
        }

        @Test("findByName() method exists and returns null for unknown name")
        func testFindByNameMethodExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.camera.findByName") == "function")
            let result = harness.evalValue("hs.camera.findByName('__nonexistent__')")
            #expect(result?.isNull == true || result?.isUndefined == true)
        }

        @Test("findByUID() method exists and returns null for unknown UID")
        func testFindByUIDMethodExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.camera.findByUID") == "function")
            let result = harness.evalValue("hs.camera.findByUID('__nonexistent__')")
            #expect(result?.isNull == true || result?.isUndefined == true)
        }

        @Test("on, off and once methods exist")
        func testWatcherMethodsExist() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.camera.on") == "function")
            #expect(harness.evalTypeOf("hs.camera.off") == "function")
            #expect(harness.evalTypeOf("hs.camera.once") == "function")
        }

        @Test("on/off/once survive garbage collection of the module's JS wrapper")
        func testOnOffOnceSurviveModuleWrapperGC() {
            let (harness, _) = JSTestHarness.makeUnpinned(HSCameraModule.self, as: "camera")

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.camera.on") == "function")
            #expect(harness.evalTypeOf("hs.camera.off") == "function")
            #expect(harness.evalTypeOf("hs.camera.once") == "function")

            harness.eval("""
                var fn = function(c) {};
                hs.camera.on('connected', fn);
                hs.camera.off('connected', fn);
            """)
            #expect(!harness.hasException)
        }

        @Test("hs.camera.js emitter factory survives garbage collection of the module wrapper")
        func testCameraEmitterFactorySurvivesGC() {
            // `makeHarness()` (via `loadModule`) stores the module wrapper permanently as a
            // property of `hs`, which would keep that specific wrapper JS-reachable for the
            // rest of the test and make garbage collection a no-op — defeating the point of
            // this test. `makeUnpinned` instead mirrors what `ModuleRoot.camera` actually does
            // in production: `hs.camera` is a *computed* accessor handing back the same Swift
            // singleton on every access, without any particular JS wrapper for it ever being
            // pinned — letting JavaScriptCore's wrapper cache actually collect an unreferenced
            // wrapper, and running the real `hs.camera.js` (not a reimplementation) against it.
            let (harness, _) = JSTestHarness.makeUnpinned(HSCameraModule.self, as: "camera")
            #expect(harness.evalTypeOf("hs.camera._makeCameraEmitter") == "function")

            // Nothing above stored the wrapper `hs.camera` resolved to while running that script,
            // so it's now eligible for collection. If the factory were still a bare JS expando
            // (the pre-fix bug) rather than the native `_makeCameraEmitter` property, it would
            // live on that now-collectible wrapper and be lost; a subsequent `hs.camera` access
            // would return a fresh wrapper without it.
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            #expect(harness.evalTypeOf("hs.camera._makeCameraEmitter") == "function")
            // Confirm the survivor is a genuine, working LazyWatcherEmitter, not just any
            // object shaped like one.
            harness.expectTrue("""
            (function() {
                var e = hs.camera._makeCameraEmitter({ _addWatcher: function() {}, _removeWatcher: function() {} });
                return typeof e.on === 'function' && typeof e.off === 'function' && typeof e.once === 'function';
            })()
        """)
        }

        @Test("module-level on() / off() cycle is safe")
        func testModuleWatcherCycle() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var fn = function(c) {};
                hs.camera.on('connected', fn);
                hs.camera.off('connected', fn);
                return true;
            })()
        """)
        }

        @Test("off() with an unregistered listener does not crash")
        func testOffUnregisteredWatcherIsSafe() {
            let harness = makeHarness()
            harness.eval("hs.camera.off('connected', function() {})")
            #expect(!harness.hasException)
        }

        @Test("on() with the same listener twice does not crash")
        func testOnIdempotent() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var fn = function(c) {};
                hs.camera.on('connected', fn);
                hs.camera.on('connected', fn);
                hs.camera.off('connected', fn);
                return true;
            })()
        """)
        }

        @Test("on() throws when given a non-function")
        func testOnThrowsOnNonFunction() {
            let harness = makeHarness()
            var threw = false
            harness.registerCallback("onThrew") { threw = true }
            harness.eval("""
            try {
                hs.camera.on('connected', "not a function");
            } catch(e) {
                __test_callback("onThrew");
            }
        """)
            #expect(threw)
        }

        @Test("listeners only receive the event they registered for")
        func testListenersAreFilteredByEvent() {
            let harness = makeHarness()
            harness.eval("""
                var connectedCount = 0;
                var disconnectedCount = 0;
                hs.camera.on('connected', function() { connectedCount++; });
                hs.camera.on('disconnected', function() { disconnectedCount++; });
                hs.camera._watcherEmitter.emit('connected', {});
            """)
            harness.expectEqual("connectedCount", 1)
            harness.expectEqual("disconnectedCount", 0)
            #expect(!harness.hasException)
        }

        @Test("multiple module-level listeners can be registered")
        func testMultipleModuleListeners() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var fn1 = function(c) {};
                var fn2 = function(c) {};
                hs.camera.on('connected', fn1);
                hs.camera.on('connected', fn2);
                hs.camera.off('connected', fn1);
                hs.camera.off('connected', fn2);
                return true;
            })()
        """)
        }
    }

    // MARK: - Camera property tests (hardware required)

    @Suite("hs.camera device property tests", .serialized,
           .disabled(if: hasNoCamera(), "No camera hardware present"))
    struct HSCameraPropertyTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCameraModule.self, as: "camera")
            return harness
        }

        @Test("all() returns at least one camera")
        func testAllReturnsCameras() {
            let harness = makeHarness()
            harness.expectTrue("hs.camera.all().length > 0")
        }

        @Test("each camera has a non-empty uid string")
        func testCameraUID() {
            let harness = makeHarness()
            harness.expectTrue("""
            hs.camera.all().every(function(c) {
                return typeof c.uid === 'string' && c.uid.length > 0;
            })
        """)
        }

        @Test("each camera has a non-empty name string")
        func testCameraName() {
            let harness = makeHarness()
            harness.expectTrue("""
            hs.camera.all().every(function(c) {
                return typeof c.name === 'string' && c.name.length > 0;
            })
        """)
        }

        @Test("each camera has a boolean isInUse property")
        func testCameraIsInUseIsBoolean() {
            let harness = makeHarness()
            harness.expectTrue("""
            hs.camera.all().every(function(c) {
                return typeof c.isInUse === 'boolean';
            })
        """)
        }

        @Test("camera isInUse is false when not in use")
        func testCameraIsInUseFalseWhenIdle() {
            let harness = makeHarness()
            harness.expectFalse("hs.camera.all()[0].isInUse")
        }

        @Test("camera has captureImage() method")
        func testCaptureImageMethodExists() {
            let harness = makeHarness()
            #expect(harness.evalTypeOf("hs.camera.all()[0].captureImage") == "function")
        }

        @Test("camera has on, off and once methods")
        func testCameraWatcherMethodsExist() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var c = hs.camera.all()[0];
                return typeof c.on === 'function' &&
                       typeof c.off === 'function' &&
                       typeof c.once === 'function';
            })()
        """)
        }

        @Test("findByName() round-trips through all()")
        func testFindByNameRoundTrip() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var cameras = hs.camera.all();
                if (cameras.length === 0) return true;
                var first = cameras[0];
                var found = hs.camera.findByName(first.name);
                return found !== null && found.uid === first.uid;
            })()
        """)
        }

        @Test("findByUID() round-trips through all()")
        func testFindByUIDRoundTrip() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var cameras = hs.camera.all();
                if (cameras.length === 0) return true;
                var first = cameras[0];
                var found = hs.camera.findByUID(first.uid);
                return found !== null && found.name === first.name;
            })()
        """)
        }

        @Test("all() returns consistent objects across multiple calls")
        func testAllReturnsCachedObjects() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var a = hs.camera.all()[0];
                var b = hs.camera.all()[0];
                return a.uid === b.uid && a.name === b.name;
            })()
        """)
        }

        @Test("typeName is 'HSCamera'")
        func testTypeName() {
            let harness = makeHarness()
            harness.expectEqual("hs.camera.all()[0].typeName", "HSCamera")
        }
    }

    // MARK: - Per-camera watcher tests (hardware required)

    @Suite("hs.camera per-camera watcher tests", .serialized,
           .disabled(if: hasNoCamera(), "No camera hardware present"))
    struct HSCameraWatcherTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCameraModule.self, as: "camera")
            return harness
        }

        @Test("per-camera on() / off() cycle is safe")
        func testAddRemoveCycle() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var cam = hs.camera.all()[0];
                var fn = function(inUse) {};
                cam.on(fn);
                cam.off(fn);
                return true;
            })()
        """)
        }

        @Test("per-camera off() with unregistered listener does not crash")
        func testRemoveUnregisteredWatcher() {
            let harness = makeHarness()
            harness.eval("hs.camera.all()[0].off(function() {})")
            #expect(!harness.hasException)
        }

        @Test("per-camera on() with same listener twice does not crash")
        func testOnIdempotent() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var cam = hs.camera.all()[0];
                var fn = function(inUse) {};
                cam.on(fn);
                cam.on(fn);
                cam.off(fn);
                return true;
            })()
        """)
        }

        @Test("per-camera on() throws when given a non-function")
        func testOnThrowsOnNonFunction() {
            let harness = makeHarness()
            var threw = false
            harness.registerCallback("cameraWatcherThrew") { threw = true }
            harness.eval("""
            try {
                hs.camera.all()[0].on("not a function");
            } catch(e) {
                __test_callback("cameraWatcherThrew");
            }
        """)
            #expect(threw)
        }

        @Test("per-camera on() throws if the native watcher fails to start")
        func testOnThrowsWhenNativeStartFails() {
            // Regression test for a code review comment (same class of bug fixed for
            // hs.power's battery watcher): if the per-device _addWatcher fails (e.g. the CMIO
            // device lookup for this camera's UID fails), the LazyWatcherEmitter's start()
            // function must throw rather than silently succeed - otherwise the listener gets
            // recorded as if the watcher were running and never receives events. Simulates the
            // native failure by swapping in a stub that returns false, since the real CMIO
            // lookup can't be forced to fail from a test.
            //
            // on()/once() are native Swift methods that invokeMethod into the JS emitter; an
            // exception the caller catches must not also reach the context's exceptionHandler
            // (which logs it as an error), hence the !hasException check.
            let harness = makeHarness()
            harness.eval("""
                var _failCam = hs.camera.all()[0];
                _failCam._addWatcher = function(fn) { return false; };
                var threw = false;
                try {
                    _failCam.on(function() {});
                } catch (err) {
                    threw = true;
                }
            """)
            #expect(!harness.hasException)
            harness.expectTrue("threw")
        }

        @Test("per-camera once() fires only one time")
        func testOnceFiresOnlyOnce() {
            let harness = makeHarness()
            // Drive the real per-camera emitter directly rather than needing a real
            // camera-in-use transition - mirrors how the module-level tests simulate events.
            harness.eval("""
            var _onceCount = 0;
            var _onceCam = hs.camera.all()[0];
            _onceCam.once(function() { _onceCount++; });
            _onceCam._watcherEmitter.emit('change', true);
            _onceCam._watcherEmitter.emit('change', false);
        """)
            harness.expectEqual("_onceCount", 1)
            #expect(!harness.hasException)
        }

        @Test("multiple cameras can have independent watchers")
        func testMultipleCameraWatchers() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var cameras = hs.camera.all();
                var fns = cameras.map(function() { return function(inUse) {}; });
                for (var i = 0; i < cameras.length; i++) {
                    cameras[i].on(fns[i]);
                }
                for (var i = 0; i < cameras.length; i++) {
                    cameras[i].off(fns[i]);
                }
                return true;
            })()
        """)
        }

        @Test("multiple listeners on the same camera all fire")
        func testMultipleListenersOnSameCamera() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var cam = hs.camera.all()[0];
                var fn1 = function(inUse) {};
                var fn2 = function(inUse) {};
                cam.on(fn1);
                cam.on(fn2);
                cam.off(fn1);
                cam.off(fn2);
                return true;
            })()
        """)
        }

        @Test("per-camera on() finds its emitter factory after the hs.camera module wrapper is collected")
        func testOnSurvivesModuleWrapperGC() {
            // hs.camera exposed as a computed accessor (see makeUnpinned), not a stored value,
            // so no particular JS wrapper for the module is kept reachable.
            let (harness, _) = JSTestHarness.makeUnpinned(HSCameraModule.self, as: "camera")

            harness.eval("var __gcTestCamera = hs.camera.all()[0];")
            #expect(!harness.hasException)

            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)
            unsafe JSSynchronousGarbageCollectForDebugging(harness.context.jsGlobalContextRef)

            // HSCamera.on() re-fetches `hs.camera` from JS on every call and reads
            // `_makeCameraEmitter` off whatever wrapper it finds there — which, after a GC pass
            // with no wrapper pinned, could be a fresh one. That's only safe because the factory
            // is the native `_makeCameraEmitter` property (Swift-object-backed, so any wrapper
            // for the same object exposes it) rather than a JS expando, so a real end-to-end
            // on()/off() cycle must still succeed here.
            harness.eval("""
            var fn = function(inUse) {};
            __gcTestCamera.on(fn);
            __gcTestCamera.off(fn);
        """)
            #expect(!harness.hasException)
        }
    }

    // MARK: - captureImage() tests (hardware + permission required)

    @Suite("hs.camera captureImage() tests", .serialized,
           .disabled(if: hasNoCamera() || !hasCameraPermission(),
                     "No camera hardware or camera permission not granted"))
    struct HSCameraCaptureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSCameraModule.self, as: "camera")
            return harness
        }

        @Test("captureImage() returns a Promise")
        func testCaptureImageReturnsPromise() {
            let harness = makeHarness()
            harness.expectTrue("""
            (function() {
                var cam = hs.camera.all()[0];
                var result = cam.captureImage();
                return result !== null && typeof result.then === 'function';
            })()
        """)
        }

        @Test("captureImage() resolves with an HSImage that has non-zero dimensions")
        @MainActor
        func testCaptureImageResolvesWithImage() async throws {
            let harness = makeHarness()

            harness.eval("""
            var _captureResolved = false;
            var _captureRejected = false;
            var _capturedImage = null;
            hs.camera.all()[0].captureImage()
                .then(function(img) {
                    _captureResolved = true;
                    _capturedImage = img;
                })
                .catch(function(err) {
                    _captureRejected = true;
                    console.error("captureImage rejected: " + err);
                });
        """)

            let completed = await harness.waitForAsync(timeout: 15.0) {
                let resolved = harness.eval("_captureResolved") as? Bool ?? false
                let rejected = harness.eval("_captureRejected") as? Bool ?? false
                return resolved || rejected
            }

            #expect(completed, "captureImage() did not complete within 15 seconds")

            let resolved = harness.eval("_captureResolved") as? Bool ?? false
            let rejected = harness.eval("_captureRejected") as? Bool ?? false
            #expect(resolved, "captureImage() was rejected (rejected=\(rejected))")

            harness.expectTrue("""
            (function() {
                if (!_capturedImage) return false;
                var size = _capturedImage.size;
                return typeof size === 'object' && size.w > 0 && size.h > 0;
            })()
        """)
        }

        @Test("successive captureImage() calls on the same camera both succeed")
        @MainActor
        func testSuccessiveCapturesSucceed() async throws {
            let harness = makeHarness()

            harness.eval("""
            var _capture1Done = false, _capture2Done = false;
            var _capture1OK = false, _capture2OK = false;
            hs.camera.all()[0].captureImage()
                .then(function(img) { _capture1OK = true; _capture1Done = true; })
                .catch(function() { _capture1Done = true; });
            hs.camera.all()[0].captureImage()
                .then(function(img) { _capture2OK = true; _capture2Done = true; })
                .catch(function() { _capture2Done = true; });
        """)

            let completed = await harness.waitForAsync(timeout: 30.0) {
                let done1 = harness.eval("_capture1Done") as? Bool ?? false
                let done2 = harness.eval("_capture2Done") as? Bool ?? false
                return done1 && done2
            }

            #expect(completed, "One or both captureImage() calls did not complete")

            let ok1 = harness.eval("_capture1OK") as? Bool ?? false
            let ok2 = harness.eval("_capture2OK") as? Bool ?? false
            #expect(ok1, "First captureImage() failed")
            #expect(ok2, "Second captureImage() failed")
        }
    }
}
