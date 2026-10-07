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

// SetFrontProcessWithOptions is still the only API that activates another application while
// bringing forward only its front window (kSetFrontProcessFrontWindowOnly).
// NSRunningApplication.activate can only raise all windows or none, and since macOS 14 it is
// refused outright unless the caller is the active application, which Hammerspoon usually is
// not. Hammerspoon 1 relies on the same call (HSuicore.m setFrontmost:). It was deprecated in
// macOS 10.9, which makes it unavailable in Swift (not just deprecated, which @diagnose could
// silence), so it has to be called from here.
#import <ApplicationServices/ApplicationServices.h>

static inline bool
hs_SetFrontProcess(pid_t pid, bool allWindows) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ProcessSerialNumber psn;
    if (GetProcessForPID(pid, &psn) != noErr) {
        return false;
    }
    return SetFrontProcessWithOptions(&psn, allWindows ? 0 : kSetFrontProcessFrontWindowOnly) == noErr;
#pragma clang diagnostic pop
}
