//
//  HSSpacesPrivate.h
//  Hammerspoon 2
//

#import <Foundation/Foundation.h>

/// Asks WindowServer to move windows to a managed space, through SkyLight's private
/// @c SLSBridgedMoveWindowsToManagedSpaceOperation.
///
/// SkyLight's plain C functions for this (@c SLSMoveWindowsToManagedSpace, and the compat-ID
/// trick Hammerspoon 1 used) silently do nothing for other processes' windows since macOS 14.5.
/// The bridged operation is what WindowManager itself goes through, and works for any window.
/// It's asynchronous: this returns once the request has been sent, not once the windows have moved.
///
/// The class is looked up at runtime, so this returns @c NO rather than crashing if a macOS
/// update removes it or changes its initializer.
///
/// @param windows  The CGWindowIDs of the windows to move, as NSNumbers.
/// @param spaceID  The ManagedSpaceID of the space to move them to.
/// @return @c YES if the request was sent, @c NO if the operation is unavailable.
BOOL HSSpacesMoveWindowsToSpace(NSArray<NSNumber *> *_Nonnull windows, uint64_t spaceID);
