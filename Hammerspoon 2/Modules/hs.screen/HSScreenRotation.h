//
//  HSScreenRotation.h
//  Hammerspoon 2
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Sets the rotation of the display identified by @c displayID.
///
/// Uses MonitorPanel.framework's MPDisplay API, which works on both Intel and
/// Apple Silicon (unlike the deprecated IOKit IOServiceRequestProbe approach).
///
/// @param displayID  The CGDirectDisplayID of the display to rotate.
/// @param degrees    The desired rotation in degrees: 0, 90, 180, or 270.
/// @return @c YES on success, @c NO if the framework or class could not be loaded.
BOOL HSScreenSetRotation(CGDirectDisplayID displayID, int degrees);
