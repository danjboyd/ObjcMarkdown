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

@end
