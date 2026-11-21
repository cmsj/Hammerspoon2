//
//  HSSpacesPrivate.m
//  Hammerspoon 2
//

#import "HSSpacesPrivate.h"
#import <objc/runtime.h>

// The parts of SkyLight's SLSBridgedMoveWindowsToManagedSpaceOperation (and its superclass,
// SLSAsynchronousBridgedWindowManagementOperation) that we use. Declared on NSObject so the
// compiler knows the signatures; whether the real class has them is checked at runtime.
@interface NSObject (HSSpacesBridgedMoveOperation)
- (instancetype)initWithWindows:(NSArray<NSNumber *> *)windows spaceID:(uint64_t)spaceID;
- (void)performWithWMBridgeDelegate;
@end

BOOL HSSpacesMoveWindowsToSpace(NSArray<NSNumber *> *windows, uint64_t spaceID) {
    Class operationClass = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
    if (!operationClass
        || ![operationClass instancesRespondToSelector:@selector(initWithWindows:spaceID:)]
        || ![operationClass instancesRespondToSelector:@selector(performWithWMBridgeDelegate)]) {
        return NO;
    }

    id operation = [[operationClass alloc] initWithWindows:windows spaceID:spaceID];
    if (!operation) {
        return NO;
    }
    [operation performWithWMBridgeDelegate];
    return YES;
}
