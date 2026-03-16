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
    NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/MonitorPanel.framework"];
    if (![bundle load]) return NO;

    Class MPDisplayClass = NSClassFromString(@"MPDisplay");
    if (!MPDisplayClass) return NO;

    MPDisplay *display = [[MPDisplayClass alloc] initWithCGSDisplayID:(int)displayID];
    display.orientation = degrees;
    return YES;
}
