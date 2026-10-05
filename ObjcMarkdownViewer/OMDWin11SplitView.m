// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDWin11SplitView.h"
#import "OMDViewerColors.h"

#include <math.h>

@implementation OMDWin11SplitView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _dividerTrackingTags = [[NSMutableArray alloc] init];
        _hoveredDividerIndex = -1;
        _activeDividerIndex = -1;
        [self setDividerStyle:NSSplitViewDividerStyleThin];
        [self setDraggedBarWidth:OMDWin11SplitDividerHitThickness];
        if ([self respondsToSelector:@selector(setDividerColor:)]) {
            [self setDividerColor:OMDResolvedSubtleSeparatorColor()];
        }
    }
    return self;
}

- (void)dealloc
{
    NSUInteger i = 0;
    for (i = 0; i < [_dividerTrackingTags count]; i++) {
        [self removeTrackingRect:(NSTrackingRectTag)[[_dividerTrackingTags objectAtIndex:i] integerValue]];
    }
    [_dividerTrackingTags release];
    [super dealloc];
}

- (NSUInteger)omdDividerCount
{
    NSUInteger subviewCount = [[self subviews] count];
    return (subviewCount > 0 ? (subviewCount - 1) : 0);
}

- (NSRect)omdDividerRectForIndex:(NSUInteger)index
{
    NSArray *subviews = [self subviews];
    NSRect bounds = [self bounds];
    CGFloat thickness = [self dividerThickness];
    NSRect leadingFrame = NSZeroRect;

    if ((index + 1) >= [subviews count]) {
        return NSZeroRect;
    }

    leadingFrame = [[subviews objectAtIndex:index] frame];
    if ([self isVertical]) {
        return NSMakeRect(NSMaxX(leadingFrame),
                          NSMinY(bounds),
                          thickness,
                          NSHeight(bounds));
    }

    return NSMakeRect(NSMinX(bounds),
                      NSMaxY(leadingFrame),
                      NSWidth(bounds),
                      thickness);
}

- (NSRect)omdInteractiveDividerRectForIndex:(NSUInteger)index
{
    NSRect effectiveRect = [self omdDividerRectForIndex:index];
    CGFloat extra = 0.0;

    if (NSEqualRects(effectiveRect, NSZeroRect)) {
        return NSZeroRect;
    }

    if ([self isVertical]) {
        extra = MAX(0.0, OMDWin11SplitDividerHitThickness - NSWidth(effectiveRect));
        effectiveRect.origin.x -= floor(extra / 2.0);
        effectiveRect.size.width += extra;
    } else {
        extra = MAX(0.0, OMDWin11SplitDividerHitThickness - NSHeight(effectiveRect));
        effectiveRect.origin.y -= floor(extra / 2.0);
        effectiveRect.size.height += extra;
    }

    return NSIntersectionRect(effectiveRect, [self bounds]);
}

- (NSInteger)omdDividerIndexForPoint:(NSPoint)point
{
    NSUInteger dividerCount = [self omdDividerCount];
    NSUInteger index = 0;

    for (index = 0; index < dividerCount; index++) {
        if (NSPointInRect(point, [self omdInteractiveDividerRectForIndex:index])) {
            return (NSInteger)index;
        }
    }

    return -1;
}

- (NSInteger)omdDividerIndexForDrawRect:(NSRect)dividerRect
{
    NSUInteger dividerCount = [self omdDividerCount];
    NSUInteger index = 0;

    for (index = 0; index < dividerCount; index++) {
        NSRect candidateRect = [self omdDividerRectForIndex:index];

        if (NSEqualRects(candidateRect, dividerRect)) {
            return (NSInteger)index;
        }
        if ([self isVertical]) {
            if (fabs(NSMidX(candidateRect) - NSMidX(dividerRect)) < 0.5) {
                return (NSInteger)index;
            }
        } else {
            if (fabs(NSMidY(candidateRect) - NSMidY(dividerRect)) < 0.5) {
                return (NSInteger)index;
            }
        }
    }

    return -1;
}

- (void)omdInvalidateCursorRects
{
    NSWindow *window = [self window];

    [self discardCursorRects];
    if (window != nil) {
        [window invalidateCursorRectsForView:self];
    }
}

- (void)omdRebuildDividerTrackingRects
{
    NSUInteger i = 0;
    NSUInteger dividerCount = [self omdDividerCount];

    for (i = 0; i < [_dividerTrackingTags count]; i++) {
        [self removeTrackingRect:(NSTrackingRectTag)[[_dividerTrackingTags objectAtIndex:i] integerValue]];
    }
    [_dividerTrackingTags removeAllObjects];

    for (i = 0; i < dividerCount; i++) {
        NSRect trackingRect = [self omdInteractiveDividerRectForIndex:i];
        NSTrackingRectTag tag = 0;

        if (NSEqualRects(trackingRect, NSZeroRect)) {
            continue;
        }

        tag = [self addTrackingRect:trackingRect
                              owner:self
                           userData:(void *)(intptr_t)(i + 1)
                       assumeInside:NO];
        [_dividerTrackingTags addObject:[NSNumber numberWithInteger:tag]];
    }

    if (_hoveredDividerIndex >= (NSInteger)dividerCount) {
        _hoveredDividerIndex = -1;
    }
    if (_activeDividerIndex >= (NSInteger)dividerCount) {
        _activeDividerIndex = -1;
    }
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self omdRebuildDividerTrackingRects];
    [self omdInvalidateCursorRects];
}

- (void)adjustSubviews
{
    [super adjustSubviews];
    [self omdRebuildDividerTrackingRects];
    [self omdInvalidateCursorRects];
}

- (void)mouseEntered:(NSEvent *)event
{
    NSInteger dividerIndex = (NSInteger)(intptr_t)[event userData] - 1;

    if (_hoveredDividerIndex != dividerIndex) {
        _hoveredDividerIndex = dividerIndex;
        [self setNeedsDisplay:YES];
    }

    [super mouseEntered:event];
}

- (void)mouseExited:(NSEvent *)event
{
    NSInteger dividerIndex = (NSInteger)(intptr_t)[event userData] - 1;

    if (_hoveredDividerIndex == dividerIndex && _activeDividerIndex != dividerIndex) {
        _hoveredDividerIndex = -1;
        [self setNeedsDisplay:YES];
    }

    [super mouseExited:event];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSWindow *window = [self window];

    _activeDividerIndex = [self omdDividerIndexForPoint:point];
    if (_activeDividerIndex >= 0) {
        _hoveredDividerIndex = _activeDividerIndex;
        [self setNeedsDisplay:YES];
    }

    [super mouseDown:event];

    _activeDividerIndex = -1;
    if (window != nil) {
        NSPoint currentPoint = [self convertPoint:[window mouseLocationOutsideOfEventStream] fromView:nil];
        _hoveredDividerIndex = [self omdDividerIndexForPoint:currentPoint];
    } else {
        _hoveredDividerIndex = -1;
    }
    [self omdRebuildDividerTrackingRects];
    [self setNeedsDisplay:YES];
}

- (void)resetCursorRects
{
    NSCursor *cursor = ([self isVertical]
                        ? [NSCursor resizeLeftRightCursor]
                        : [NSCursor resizeUpDownCursor]);
    NSUInteger dividerCount = [self omdDividerCount];
    NSUInteger index = 0;

    for (index = 0; index < dividerCount; index++) {
        NSRect interactiveRect = [self omdInteractiveDividerRectForIndex:index];

        if (!NSEqualRects(interactiveRect, NSZeroRect)) {
            [self addCursorRect:interactiveRect cursor:cursor];
        }
    }
}

- (CGFloat)dividerThickness
{
    return OMDWin11SplitDividerThickness;
}

- (void)drawDividerInRect:(NSRect)dividerRect
{
    NSColor *background = OMDResolvedChromeBackgroundColor();
    NSColor *separator = OMDResolvedSubtleSeparatorColor();
    NSColor *accent = OMDResolvedAccentColor();
    NSInteger dividerIndex = [self omdDividerIndexForDrawRect:dividerRect];
    BOOL hovered = (dividerIndex >= 0 && dividerIndex == _hoveredDividerIndex);
    BOOL active = (dividerIndex >= 0 && dividerIndex == _activeDividerIndex);
    BOOL dark = OMDColorIsDark(background);
    NSColor *bandColor = nil;
    NSColor *lineColor = nil;
    NSRect strokeRect = dividerRect;

    if (background == nil) {
        background = [NSColor clearColor];
    }
    if (separator == nil) {
        separator = [NSColor colorWithCalibratedWhite:0.80 alpha:1.0];
    }
    if ([separator respondsToSelector:@selector(colorWithAlphaComponent:)]) {
        separator = [separator colorWithAlphaComponent:(OMDColorIsDark(background) ? 0.58 : 0.78)];
    }

    if (active) {
        bandColor = OMDColorByBlending(background, accent, dark ? 0.22 : 0.16);
        lineColor = accent;
    } else if (hovered) {
        bandColor = OMDColorByBlending(background, separator, dark ? 0.30 : 0.20);
        lineColor = OMDColorByBlending(separator, accent, 0.28);
    } else {
        bandColor = OMDColorByBlending(background, separator, dark ? 0.22 : 0.15);
        lineColor = separator;
    }

    [bandColor setFill];
    NSRectFill(dividerRect);

    if ([self isVertical]) {
        CGFloat lineWidth = MIN(NSWidth(dividerRect), (active || hovered) ? 2.0 : 1.0);
        strokeRect.origin.x = floor(NSMidX(dividerRect) - (lineWidth / 2.0));
        strokeRect.size.width = MAX(1.0, lineWidth);
    } else {
        CGFloat lineHeight = MIN(NSHeight(dividerRect), (active || hovered) ? 2.0 : 1.0);
        strokeRect.origin.y = floor(NSMidY(dividerRect) - (lineHeight / 2.0));
        strokeRect.size.height = MAX(1.0, lineHeight);
    }

    if ([lineColor respondsToSelector:@selector(colorWithAlphaComponent:)]) {
        lineColor = [lineColor colorWithAlphaComponent:(active ? 0.96 : (hovered ? 0.90 : (dark ? 0.82 : 0.80)))];
    }

    [lineColor setFill];
    NSRectFill(strokeRect);
}

@end
