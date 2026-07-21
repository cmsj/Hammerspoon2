//
//  HSScreenPrivate.h
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

/// Returns the aggregated ambient light level in lux for the given display, or
/// @c nil if the display does not expose an ambient light sensor.
///
/// Uses DisplayServices.framework's @c DisplayServicesClient, loaded once via
/// @c dispatch_once and reused for all subsequent calls.
///
/// @param displayID  The CGDirectDisplayID of the display to query.
/// @return The lux reading as an @c NSNumber, or @c nil if unsupported or unavailable.
NSNumber *_Nullable HSScreenAmbientLight(CGDirectDisplayID displayID);
