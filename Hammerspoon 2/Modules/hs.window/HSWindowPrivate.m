//
//  HSWindowPrivate.m
//  Hammerspoon 2
//

#import "HSWindowPrivate.h"
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>

// The signature follows AltTab and yabai, which have relied on it for years.
typedef CGError (*HSSetFrontProcessWithWindowFn)(ProcessSerialNumber *psn, uint32_t windowID, uint32_t mode);

// _SLPSSetFrontProcessWithOptions mode: activate as though the user had chosen the window.
static const uint32_t kHSCPSUserGenerated = 0x200;

BOOL HSWindowBringToFront(pid_t pid, CGWindowID windowID) {
    static HSSetFrontProcessWithWindowFn setFrontProcessWithWindow;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (handle) {
            setFrontProcessWithWindow = (HSSetFrontProcessWithWindowFn)dlsym(handle, "_SLPSSetFrontProcessWithOptions");
        }
    });
    if (!setFrontProcessWithWindow) {
        return NO;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ProcessSerialNumber psn;
    if (GetProcessForPID(pid, &psn) != noErr) {
        return NO;
    }
#pragma clang diagnostic pop

    return setFrontProcessWithWindow(&psn, windowID, kHSCPSUserGenerated) == kCGErrorSuccess;
}
