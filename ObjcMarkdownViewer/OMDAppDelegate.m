// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDAppDelegate.h"
#import "OMDWindowController.h"

@implementation OMDAppDelegate

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _mainWindowController = [[OMDWindowController alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_mainWindowController release];
    [super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [_mainWindowController applicationWillFinishLaunching:notification];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [_mainWindowController applicationDidFinishLaunching:notification];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [_mainWindowController applicationDidBecomeActive:notification];
}

- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename
{
    return [_mainWindowController application:application openFile:filename];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
    return [_mainWindowController applicationShouldTerminateAfterLastWindowClosed:application];
}

#if !defined(GNUSTEP)
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)application
{
    (void)application;
    return YES;
}
#endif

@end
