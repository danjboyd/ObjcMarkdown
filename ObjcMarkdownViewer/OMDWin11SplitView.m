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

    // No divider next to a hidden subview (the collapsed explorer).
    if ([[subviews objectAtIndex:index] isHidden] || [[subviews objectAtIndex:index + 1] isHidden]) {
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

// libs-gui shares out a resize in proportion, which leaves subviews at
// fractions of a pixel (and a hidden one's neighbour slightly outside the
// split view). Views under a fractional offset redraw slivers that don't
// line up, which repaints the preview over the theme's overlay scroller
// while it's dragged. Put every edge back on a whole pixel: each visible
// subview keeps its rounded length, the last visible one takes the rest,
// and a hidden one (left as it is, for when it's shown again) takes no
// room and no divider.
- (void)omdSnapSubviewsToPixels
{
    NSArray *subviews = [self subviews];
    NSUInteger count = [subviews count];
    NSRect bounds = [self bounds];
    BOOL vertical = [self isVertical];
    CGFloat total = vertical ? NSWidth(bounds) : NSHeight(bounds);
    CGFloat divider = [self dividerThickness];
    CGFloat offset = 0.0;
    NSInteger lastVisible = -1;
    NSUInteger i = 0;

    for (i = 0; i < count; i++) {
        if (![[subviews objectAtIndex:i] isHidden]) {
            lastVisible = (NSInteger)i;
        }
    }
    for (i = 0; i < count; i++) {
        NSView *subview = [subviews objectAtIndex:i];
        NSRect current = [subview frame];
        CGFloat length = 0.0;
        NSRect frame;

        if ([subview isHidden]) {
            continue;
        }
        if ((NSInteger)i == lastVisible) {
            length = total - offset;
        } else {
            length = MIN(round(vertical ? NSWidth(current) : NSHeight(current)), total - offset);
        }
        length = MAX(0.0, length);
        if (vertical) {
            frame = NSMakeRect(NSMinX(bounds) + offset, NSMinY(bounds), length, NSHeight(bounds));
        } else {
            frame = NSMakeRect(NSMinX(bounds), NSMinY(bounds) + offset, NSWidth(bounds), length);
        }
        if (!NSEqualRects(frame, current)) {
            [subview setFrame:frame];
        }
        if ((NSInteger)i != lastVisible) {
            offset += length + divider;
        }
    }
}

- (void)adjustSubviews
{
    [super adjustSubviews];
    [self omdSnapSubviewsToPixels];
    [self omdRebuildDividerTrackingRects];
    [self omdInvalidateCursorRects];
}

// As in Cocoa, the position is where the divider starts: the leading
// subview ends there. libs-gui centres the divider on it instead, which
// made the leading subview half a divider narrower than asked, and a split
// ratio read back from it shrink a little every time it was applied.
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex
{
    NSArray *subviews = [self subviews];
    id delegate = [self delegate];

    if (dividerIndex < 0 || (NSUInteger)dividerIndex + 1 >= [subviews count]) {
        return;
    }
    if ([delegate respondsToSelector:@selector(splitView:constrainSplitPosition:ofSubviewAt:)]) {
        position = [delegate splitView:self constrainSplitPosition:position ofSubviewAt:dividerIndex];
    }
    // libs-gui also lays the subviews out first if it never has.
    [super setPosition:position ofDividerAtIndex:dividerIndex];

    NSView *leading = [subviews objectAtIndex:(NSUInteger)dividerIndex];
    NSRect frame = [leading frame];
    if ([self isVertical]) {
        frame.size.width = MAX(0.0, round(position - NSMinX(frame)));
    } else {
        frame.size.height = MAX(0.0, round(position - NSMinY(frame)));
    }
    [leading setFrame:frame];
    [self omdSnapSubviewsToPixels];
    [self omdRebuildDividerTrackingRects];
    [self omdInvalidateCursorRects];
    [self setNeedsDisplay:YES];
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
    [self omdSnapSubviewsToPixels];

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
