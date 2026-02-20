// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDCodeCopyButton.h"

@interface OMDCodeCopyButton () {
    NSTrackingRectTag _trackingRectTag;
    BOOL _hovering;
}
- (void)omd_updateTrackingRect;
@end

@implementation OMDCodeCopyButton

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _trackingRectTag = 0;
        _hovering = NO;
        [self setAlphaValue:0.72];
    }
    return self;
}

- (void)dealloc
{
    if (_trackingRectTag != 0) {
        [self removeTrackingRect:_trackingRectTag];
        _trackingRectTag = 0;
    }
    [super dealloc];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self omd_updateTrackingRect];
}

- (void)setFrame:(NSRect)frameRect
{
    [super setFrame:frameRect];
    [self omd_updateTrackingRect];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    NSCursor *cursor = [NSCursor pointingHandCursor];
    if (cursor == nil) {
        cursor = [NSCursor arrowCursor];
    }
    [self addCursorRect:[self bounds] cursor:cursor];
}

- (void)mouseEntered:(NSEvent *)event
{
    _hovering = YES;
    [self setAlphaValue:1.0];
    [super mouseEntered:event];
}

- (void)mouseExited:(NSEvent *)event
{
    _hovering = NO;
    [self setAlphaValue:0.72];
    [super mouseExited:event];
}

- (void)mouseDown:(NSEvent *)event
{
    [self setAlphaValue:1.0];
    [super mouseDown:event];
    if (!_hovering) {
        [self setAlphaValue:0.72];
    }
}

- (void)omd_updateTrackingRect
{
    if (_trackingRectTag != 0) {
        [self removeTrackingRect:_trackingRectTag];
        _trackingRectTag = 0;
    }
    if ([self window] == nil) {
        return;
    }
    _trackingRectTag = [self addTrackingRect:[self bounds]
                                       owner:self
                                    userData:NULL
                                assumeInside:NO];
}

@end
