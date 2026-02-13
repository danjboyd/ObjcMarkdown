// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDSourceTextView.h"

@implementation OMDSourceTextView

- (void)changeFont:(id)sender
{
    id target = nil;
    NSWindow *window = [self window];
    if (window != nil) {
        id delegate = [window delegate];
        if (delegate != nil && delegate != self && [delegate respondsToSelector:@selector(changeFont:)]) {
            target = delegate;
        }
    }

    if (target == nil) {
        id appDelegate = [NSApp delegate];
        if (appDelegate != nil && appDelegate != self && [appDelegate respondsToSelector:@selector(changeFont:)]) {
            target = appDelegate;
        }
    }

    if (target != nil) {
        [NSApp sendAction:@selector(changeFont:) to:target from:sender];
        return;
    }

    [super changeFont:sender];
}

- (void)keyDown:(NSEvent *)event
{
    if (event != nil) {
        NSUInteger flags = [event modifierFlags];
        NSUInteger normalized = flags & (NSControlKeyMask | NSShiftKeyMask | NSAlternateKeyMask | NSCommandKeyMask);
        if (normalized == (NSControlKeyMask | NSShiftKeyMask)) {
            NSString *chars = [event charactersIgnoringModifiers];
            if ([chars length] > 0) {
                unichar ch = [chars characterAtIndex:0];
                if (ch == NSLeftArrowFunctionKey) {
                    [self doCommandBySelector:@selector(moveWordLeftAndModifySelection:)];
                    return;
                }
                if (ch == NSRightArrowFunctionKey) {
                    [self doCommandBySelector:@selector(moveWordRightAndModifySelection:)];
                    return;
                }
            }
        }
    }
    [super keyDown:event];
}

@end
