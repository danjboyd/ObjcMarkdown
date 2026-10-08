// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDAppDelegate.h"
#import "OMDWindowController.h"
#import "OMDPreferencesController.h"
#import <objc/runtime.h>

#if defined(GNUSTEP)
@interface GPStandardUpdaterController : NSObject
- (instancetype)initWithPackagedConfiguration:(NSError **)error;
- (void)setParentWindow:(NSWindow *)parentWindow;
- (void)start;
- (void)checkForUpdates:(id)sender;
@end
#endif

// A method Settings calls on its delegate.
static BOOL OMDIsPreferencesDelegateSelector(SEL selector)
{
    struct objc_method_description description =
        protocol_getMethodDescription(@protocol(OMDPreferencesControllerDelegate), selector, YES, YES);
    return description.name != NULL;
}

// One Settings changes ("setScrollSpeedPreference:"); the rest read.
static BOOL OMDIsPreferencesSetterSelector(SEL selector)
{
    return OMDIsPreferencesDelegateSelector(selector) && [NSStringFromSelector(selector) hasPrefix:@"set"];
}

@implementation OMDAppDelegate

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _windowActionNames = [[NSMutableSet alloc] init];
        _mainWindowController = [[OMDWindowController alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_mainWindowController release];
    [_preferencesController release];
    [_updaterController release];
    [_windowActionNames release];
    [super dealloc];
}

#pragma mark Application events

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [_mainWindowController applicationWillFinishLaunching:notification];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [_mainWindowController applicationDidFinishLaunching:notification];
#if defined(GNUSTEP)
    if (_updaterController == nil) {
        NSError *updateError = nil;
        GPStandardUpdaterController *controller = [[GPStandardUpdaterController alloc] initWithPackagedConfiguration:&updateError];
        if (controller == nil) {
            NSLog(@"Updater disabled: %@", [updateError localizedDescription]);
        } else {
            [controller setParentWindow:[_mainWindowController mainWindow]];
            [controller start];
            _updaterController = controller;
        }
    }
#endif
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [[self activeWindowController] applicationDidBecomeActive:notification];
}

- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename
{
    return [_mainWindowController application:application openFile:filename];
}

// Quitting asks about every unsaved document in every window first.
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)application
{
    (void)application;
    NSArray *controllers = [self openWindowControllers];
    for (OMDWindowController *controller in controllers) {
        if (![controller reviewUnsavedDocumentsForAction:@"quitting"]) {
            return NSTerminateCancel;
        }
    }
    // Nothing is left to recover: each change was saved or let go.
    for (OMDWindowController *controller in controllers) {
        [controller discardRecoverySnapshot];
    }
    return NSTerminateNow;
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

#pragma mark Windows

- (NSArray *)visibleWindowControllers
{
    NSMutableArray *controllers = [NSMutableArray array];
    for (NSWindow *window in [NSApp orderedWindows]) {
        id delegate = [window delegate];
        if ([window isVisible] && [delegate isKindOfClass:[OMDWindowController class]] &&
            ![controllers containsObject:delegate]) {
            [controllers addObject:delegate];
        }
    }
    return controllers;
}

// The controllers of the windows on screen or in the Dock, front first.
- (NSArray *)openWindowControllers
{
    NSMutableArray *controllers = [NSMutableArray arrayWithArray:[self visibleWindowControllers]];
    for (NSWindow *window in [NSApp windows]) {
        id delegate = [window delegate];
        if ([window isMiniaturized] && [delegate isKindOfClass:[OMDWindowController class]] &&
            ![controllers containsObject:delegate]) {
            [controllers addObject:delegate];
        }
    }
    return controllers;
}

- (OMDWindowController *)activeWindowController
{
    NSWindow *candidates[2] = { [NSApp keyWindow], [NSApp mainWindow] };
    NSUInteger index = 0;
    for (; index < 2; index++) {
        id delegate = [candidates[index] delegate];
        if ([delegate isKindOfClass:[OMDWindowController class]]) {
            return delegate;
        }
    }
    NSArray *visible = [self visibleWindowControllers];
    if ([visible count] > 0) {
        return [visible objectAtIndex:0];
    }
    return _mainWindowController;
}

#pragma mark The main menu

- (void)routeWindowActionsOfMenu:(NSMenu *)menu
{
    for (NSMenuItem *item in [menu itemArray]) {
        SEL action = [item action];
        if ([item target] == self && action != NULL &&
            ![[self class] instancesRespondToSelector:action]) {
            [_windowActionNames addObject:NSStringFromSelector(action)];
        }
        if ([item submenu] != nil) {
            [self routeWindowActionsOfMenu:[item submenu]];
        }
    }
    // Open Recent's items, which the first window's controller fills.
    [_windowActionNames addObject:@"openRecentDocumentFromMenuItem:"];
    [_windowActionNames addObject:@"clearRecentDocumentsMenu:"];
}

- (BOOL)routesWindowAction:(SEL)selector
{
    return selector != NULL && [_windowActionNames containsObject:NSStringFromSelector(selector)];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [_mainWindowController menuNeedsUpdate:menu];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL action = [item action];
    if (action == @selector(checkForUpdates:)) {
        return _updaterController != nil;
    }
    OMDWindowController *controller = [self activeWindowController];
    if ([self routesWindowAction:action] && [controller respondsToSelector:action]) {
        return [controller validateMenuItem:item];
    }
    return [self routesWindowAction:action] ? NO : YES;
}

- (void)checkForUpdates:(id)sender
{
#if defined(GNUSTEP)
    if (_updaterController != nil) {
        [(GPStandardUpdaterController *)_updaterController checkForUpdates:sender];
        return;
    }
#else
    (void)sender;
#endif
    NSBeep();
}

#pragma mark Settings

- (OMDPreferencesController *)preferencesController
{
    if (_preferencesController == nil) {
        // Settings asks this delegate, which reads from the window in
        // front and applies changes to every window (below).
        _preferencesController = [[OMDPreferencesController alloc]
            initWithDelegate:(id<OMDPreferencesControllerDelegate>)self];
    }
    return _preferencesController;
}

#pragma mark Passing messages on to windows

- (BOOL)respondsToSelector:(SEL)selector
{
    if ([super respondsToSelector:selector]) {
        return YES;
    }
    if ([self routesWindowAction:selector] || OMDIsPreferencesDelegateSelector(selector)) {
        return [[self activeWindowController] respondsToSelector:selector];
    }
    return NO;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    if (signature == nil &&
        ([self routesWindowAction:selector] || OMDIsPreferencesDelegateSelector(selector))) {
        signature = [OMDWindowController instanceMethodSignatureForSelector:selector];
    }
    return signature;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    SEL selector = [invocation selector];
    if (OMDIsPreferencesSetterSelector(selector)) {
        for (OMDWindowController *controller in [self openWindowControllers]) {
            if ([controller respondsToSelector:selector]) {
                [invocation invokeWithTarget:controller];
            }
        }
        return;
    }
    OMDWindowController *controller = [self activeWindowController];
    if (([self routesWindowAction:selector] || OMDIsPreferencesDelegateSelector(selector)) &&
        [controller respondsToSelector:selector]) {
        [invocation invokeWithTarget:controller];
        return;
    }
    [super forwardInvocation:invocation];
}

@end
