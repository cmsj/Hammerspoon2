//
//  HSScreenPrivate.m
//  Hammerspoon 2
//

#import "HSScreenPrivate.h"

// MARK: - Rotation

@interface MPDisplay : NSObject
- (instancetype)initWithCGSDisplayID:(int)displayID;
@property(nonatomic) int orientation;
@end

BOOL HSScreenSetRotation(CGDirectDisplayID displayID, int degrees) {
    static Class MPDisplayClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/MonitorPanel.framework"];
        if ([bundle load]) {
            MPDisplayClass = NSClassFromString(@"MPDisplay");
        }
    });
    if (!MPDisplayClass) return NO;

    MPDisplay *display = [[MPDisplayClass alloc] initWithCGSDisplayID:(int)displayID];
    if (!display) return NO;

    display.orientation = degrees;
    return YES;
}

// MARK: - Ambient Light Sensor

// Function pointer type matching copyPropertyForKey:andDisplay:'s signature.
// Returned id is treated as autoreleased (+0), consistent with the Swift reference
// implementation that used takeUnretainedValue().
typedef id _Nullable (*DSCopyPropertyFn)(id _Nonnull, SEL _Nonnull, NSString * _Nonnull, uint64_t);

NSNumber *_Nullable HSScreenAmbientLight(CGDirectDisplayID displayID) {
    static id dsClient = nil;
    static DSCopyPropertyFn dsCopyFn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:
            @"/System/Library/PrivateFrameworks/DisplayServices.framework"];
        if (![bundle load]) return;

        Class cls = NSClassFromString(@"DisplayServicesClient");
        if (!cls) return;

        id instance = [[cls alloc] init];
        if (!instance) return;

        SEL sel = NSSelectorFromString(@"copyPropertyForKey:andDisplay:");
        if (![instance respondsToSelector:sel]) return;

        IMP imp = [instance methodForSelector:sel];
        if (!imp) return;

        dsClient = instance;
        dsCopyFn = (DSCopyPropertyFn)(void *)imp;
    });

    if (!dsClient || !dsCopyFn) return nil;

    SEL sel = NSSelectorFromString(@"copyPropertyForKey:andDisplay:");
    id result = nil;
    @try {
        result = (__bridge_transfer id)dsCopyFn(dsClient, sel, @"AggregatedLux", (uint64_t)displayID);
    } @catch (...) {
        return nil;
    }

    if (![result isKindOfClass:[NSNumber class]]) return nil;
    return (NSNumber *)result;
}
