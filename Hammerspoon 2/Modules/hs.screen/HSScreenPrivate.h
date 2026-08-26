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

/// Returns the current software brightness of the given display, from 0.0 to 1.0.
///
/// Uses DisplayServices.framework's @c DisplayServicesGetBrightness, which (unlike the
/// deprecated IOKit @c IODisplay approach used on Intel Macs) works on Apple Silicon's
/// built-in displays and Apple/LG displays that support software brightness.
///
/// @param displayID  The CGDirectDisplayID of the display to query.
/// @return The brightness as a value from 0.0 to 1.0, or @c NAN if unsupported or unavailable.
double HSScreenGetBrightness(CGDirectDisplayID displayID);

/// Sets the software brightness of the given display.
///
/// @param displayID   The CGDirectDisplayID of the display to change.
/// @param brightness  The desired brightness, from 0.0 to 1.0.
/// @return @c YES on success, @c NO if unsupported or the call failed.
BOOL HSScreenSetBrightness(CGDirectDisplayID displayID, double brightness);
