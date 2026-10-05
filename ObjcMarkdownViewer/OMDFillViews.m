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

@implementation OMDRoundedCardView

@synthesize borderColor = _borderColor;
@synthesize cornerRadius = _cornerRadius;

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        [self setFillColor:OMDResolvedPanelCardFillColor()];
        _borderColor = [OMDResolvedPanelCardBorderColor() retain];
        _cornerRadius = 12.0;
    }
    return self;
}

- (void)dealloc
{
    [_borderColor release];
    [super dealloc];
}

- (void)setBorderColor:(NSColor *)borderColor
{
    if (_borderColor == borderColor) {
        return;
    }
    [_borderColor release];
    _borderColor = [borderColor retain];
    [self setNeedsDisplay:YES];
}

- (void)setCornerRadius:(CGFloat)cornerRadius
{
    if (_cornerRadius == cornerRadius) {
        return;
    }
    _cornerRadius = cornerRadius;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                         xRadius:_cornerRadius
                                                         yRadius:_cornerRadius];
    NSColor *fill = ([self fillColor] != nil ? [self fillColor] : [NSColor clearColor]);
    [fill setFill];
    [path fill];
    if (_borderColor != nil) {
        [_borderColor setStroke];
        [path setLineWidth:1.0];
        [path stroke];
    }
}

@end
