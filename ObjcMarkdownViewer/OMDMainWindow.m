// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDMainWindow.h"

@implementation OMDMainWindow

- (void)performClose:(id)sender
{
    (void)sender;

    id delegate = [self delegate];
    BOOL shouldClose = YES;
    if (delegate != nil && [delegate respondsToSelector:@selector(windowShouldClose:)]) {
        shouldClose = [delegate windowShouldClose:self];
    }

    if (shouldClose) {
        [self close];
    }
}

// Zoom In's key equivalent is "="; with Shift the key gives "+", which a
// menu item can't also match (and GNUstep can't hide a second item).
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    NSUInteger modifiers = [event modifierFlags] & (NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask);
    if ([event type] == NSKeyDown && modifiers == NSCommandKeyMask &&
        [[event charactersIgnoringModifiers] isEqualToString:@"+"] &&
        [NSApp sendAction:@selector(zoomIn:) to:nil from:self]) {
        return YES;
    }
    return [super performKeyEquivalent:event];
}

@end
