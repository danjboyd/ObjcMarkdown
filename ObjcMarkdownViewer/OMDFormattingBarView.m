// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDFormattingBarView.h"

@implementation OMDFormattingBarView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _fillColor = [[NSColor colorWithCalibratedRed:0.96 green:0.97 blue:0.98 alpha:1.0] retain];
        _borderColor = [[NSColor colorWithCalibratedRed:0.84 green:0.87 blue:0.90 alpha:1.0] retain];
    }
    return self;
}

- (void)dealloc
{
    [_fillColor release];
    [_borderColor release];
    [super dealloc];
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

- (void)setBorderColor:(NSColor *)borderColor
{
    if (_borderColor == borderColor) {
        return;
    }
    [_borderColor release];
    _borderColor = [borderColor retain];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect bounds = [self bounds];
    if (_fillColor != nil) {
        [_fillColor setFill];
        NSRectFill(bounds);
    }
    if (_borderColor != nil) {
        [_borderColor setFill];
        NSRect line = NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), 1.0);
        NSRectFill(line);
    }
}

@end
