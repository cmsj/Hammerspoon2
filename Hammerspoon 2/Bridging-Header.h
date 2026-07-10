//
//  Bridging-Header.h
//  Hammerspoon 2
//

#import "Modules/hs.screen/HSScreenRotation.h"

// JSSynchronousGarbageCollectForDebugging is exported from JavaScriptCore.framework
// but not declared in its public headers. It runs a full synchronous GC cycle
// (mark + sweep + finalize) before returning — unlike JSGarbageCollect, which
// schedules an asynchronous collection and returns immediately. The synchronous
// variant is required to ensure ObjC bridge CFRelease calls complete before
// the VM is torn down; see JSEngine.deleteContext() for details.
#import <JavaScriptCore/JavaScriptCore.h>
JS_EXPORT void JSSynchronousGarbageCollectForDebugging(JSContextRef ctx);

