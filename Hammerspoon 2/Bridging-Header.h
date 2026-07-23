//
//  Bridging-Header.h
//  Hammerspoon 2
//

#import "Modules/hs.screen/HSScreenPrivate.h"

// JSSynchronousGarbageCollectForDebugging is exported from JavaScriptCore.framework
// but not declared in its public headers. It runs a full synchronous GC cycle
// (mark + sweep + finalize) before returning — unlike JSGarbageCollect, which
// schedules an asynchronous collection and returns immediately. The synchronous
// variant is required to ensure ObjC bridge CFRelease calls complete before
// the VM is torn down; see JSEngine.deleteContext() for details.
#import <JavaScriptCore/JavaScriptCore.h>
JS_EXPORT void JSSynchronousGarbageCollectForDebugging(JSContextRef ctx);

// IOHIDGetAccelerationWithKey / IOHIDSetAccelerationWithKey were deprecated in macOS 10.12
// but remain the only public API for reading and writing live mouse-acceleration values
// for the current session. These wrappers silence the deprecation warnings so they can be
// called from Swift without polluting the build log.
#import <IOKit/hidsystem/IOHIDLib.h>

static inline kern_return_t
hs_IOHIDGetAccelerationWithKey(io_connect_t handle, CFStringRef key, double *acceleration) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return IOHIDGetAccelerationWithKey(handle, key, acceleration);
#pragma clang diagnostic pop
}

static inline kern_return_t
hs_IOHIDSetAccelerationWithKey(io_connect_t handle, CFStringRef key, double acceleration) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return IOHIDSetAccelerationWithKey(handle, key, acceleration);
#pragma clang diagnostic pop
}

