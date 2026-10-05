// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDFillViews.h"
#import "OMDViewerColors.h"

@implementation OMDFlippedFillView

@synthesize fillColor = _fillColor;

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _fillColor = [OMDResolvedPanelBackdropColor() retain];
    }
    return self;
}

- (void)dealloc
{
    [_fillColor release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)setFillColor:(NSColor *)fillColor
{
    if (_fillColor == fillColor) {
        return;
    }
    [_fillColor release];
    _fillColor = [fillColor retain];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSColor *fill = (_fillColor != nil ? _fillColor : [NSColor clearColor]);
    [fill setFill];
    NSRectFill([self bounds]);
}

@end

@implementation OMDPreviewCanvasView

- (BOOL)isFlipped
{
    return YES;
}

@end

@implementation OMDFlippedView

- (BOOL)isFlipped
{
    return YES;
}

@end
