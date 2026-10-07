// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDWin11SplitView.h"

#include <math.h>

@implementation OMDWin11SplitView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        // A thin divider the theme draws (NSSplitView's own drawing, in the
        // theme's divider colour); the app paints no chrome (#84).
        [self setDividerStyle:NSSplitViewDividerStyleThin];
        [self setDraggedBarWidth:OMDWin11SplitDividerHitThickness];
    }
    return self;
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

- (void)omdInvalidateCursorRects
{
    NSWindow *window = [self window];

    [self discardCursorRects];
    if (window != nil) {
        [window invalidateCursorRectsForView:self];
    }
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
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

// libs-gui shares a resize out in proportion to the subviews' lengths,
// dividing by their total. Early in setup, with the window too narrow for
// the explorer and the explorer then collapsed, both panes were 0 wide and
// every frame came out NaN (the AppImage smoke launch died on them). Give
// the last subview the length first so the proportions are defined.
- (void)omdEnsureSubviewsHaveLength
{
    NSArray *subviews = [self subviews];
    NSUInteger count = [subviews count];
    BOOL vertical = [self isVertical];
    CGFloat total = 0.0;
    NSUInteger i = 0;

    if (count == 0) {
        return;
    }
    for (i = 0; i < count; i++) {
        NSRect frame = [[subviews objectAtIndex:i] frame];
        total += vertical ? NSWidth(frame) : NSHeight(frame);
    }
    if (isfinite(total) && total >= 1.0) {
        return;
    }
    NSRect bounds = [self bounds];
    CGFloat length = MAX(1.0, vertical ? NSWidth(bounds) : NSHeight(bounds));
    for (i = 0; i < count; i++) {
        NSView *subview = [subviews objectAtIndex:i];
        BOOL last = (i + 1 == count);
        NSRect frame = vertical
            ? NSMakeRect(NSMinX(bounds), NSMinY(bounds), last ? length : 0.0, NSHeight(bounds))
            : NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), last ? length : 0.0);
        [subview setFrame:frame];
    }
}

- (void)adjustSubviews
{
    [self omdEnsureSubviewsHaveLength];
    [super adjustSubviews];
    [self omdSnapSubviewsToPixels];
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
    [self omdInvalidateCursorRects];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
    [super mouseDown:event];
    [self omdSnapSubviewsToPixels];
    [self omdInvalidateCursorRects];
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

@end
