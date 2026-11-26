//
//  HSWindowPrivate.h
//  Hammerspoon 2
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Makes the application that owns a window frontmost, bringing forward that window and none of
/// its other windows.
///
/// SetFrontProcessWithOptions(kSetFrontProcessFrontWindowOnly) can't be told which window to bring
/// forward: WindowServer picks the application's last used window, so focusing a window on one
/// display can pull another of the application's windows forward on a different display (#488).
/// SkyLight's private @c _SLPSSetFrontProcessWithOptions takes the window instead. Window switchers
/// such as AltTab and yabai use it, and it doesn't need System Integrity Protection disabled.
///
/// This doesn't make the window key; HSWindow.focus() does that through Accessibility. AltTab and
/// yabai also post synthetic event records (@c SLPSPostEventRecordTo) to make it key, but those
/// arrive asynchronously, after later Accessibility calls: focusing two windows of an application
/// in quick succession then left the first one key.
///
/// The functions are looked up at runtime, so this returns @c NO rather than crashing if a macOS
/// update removes them, and the caller can fall back to SetFrontProcessWithOptions.
///
/// @param pid       The process that owns the window.
/// @param windowID  The window's CGWindowID.
/// @return @c YES if the application was made frontmost through the window, @c NO if that is
///         unavailable or WindowServer refused it.
BOOL HSWindowBringToFront(pid_t pid, CGWindowID windowID);
