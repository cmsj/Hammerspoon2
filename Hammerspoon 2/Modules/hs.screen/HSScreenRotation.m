//
//  HSScreenRotation.m
//  Hammerspoon 2
//

#import "HSScreenRotation.h"

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
