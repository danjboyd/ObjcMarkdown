// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDToolbarViews.h"
#import "OMDViewerColors.h"

#include <math.h>

@implementation OMDToolbarToolTipView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _toolTipRects = [[NSMutableArray alloc] init];
        _toolTipStrings = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_toolTipRects release];
    [_toolTipStrings release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)rebuildToolTipRects
{
    [self removeAllToolTips];
    NSUInteger count = [_toolTipRects count];
    for (NSUInteger i = 0; i < count; i++) {
        [self addToolTipRect:[[_toolTipRects objectAtIndex:i] rectValue]
                       owner:self
                    userData:(void *)((NSInteger)i)];
    }
}

- (void)setFrame:(NSRect)frameRect
{
    [super setFrame:frameRect];
    [self rebuildToolTipRects];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self rebuildToolTipRects];
}

- (void)setToolTip:(NSString *)toolTip forRect:(NSRect)rect
{
    if (toolTip == nil) {
        toolTip = @"";
    }

    NSUInteger count = [_toolTipRects count];
    for (NSUInteger i = 0; i < count; i++) {
        if (NSEqualRects([[_toolTipRects objectAtIndex:i] rectValue], rect)) {
            [_toolTipStrings replaceObjectAtIndex:i withObject:toolTip];
            [self rebuildToolTipRects];
            return;
        }
    }

    [_toolTipRects addObject:[NSValue valueWithRect:rect]];
    [_toolTipStrings addObject:toolTip];
    [self rebuildToolTipRects];
}

- (NSString *)view:(NSView *)view
  stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point
          userData:(void *)data
{
    (void)view;
    (void)tag;
    (void)point;
    NSInteger index = (NSInteger)data;
    if (index < 0 || index >= (NSInteger)[_toolTipStrings count]) {
        return nil;
    }
    NSString *toolTip = [_toolTipStrings objectAtIndex:(NSUInteger)index];
    return [toolTip length] > 0 ? toolTip : nil;
}

@end

@implementation OMDToolbarActionGlyphOverlayView

- (BOOL)isFlipped
{
    return YES;
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

- (void)setFileActionsControl:(NSSegmentedControl *)fileControl
        utilityActionsControl:(NSSegmentedControl *)utilityControl
{
    _fileActionsControl = fileControl;
    _utilityActionsControl = utilityControl;
    [self setNeedsDisplay:YES];
}

- (void)drawGlyphAtIndex:(NSInteger)index inRect:(NSRect)rect enabled:(BOOL)enabled
{
    NSRect glyphRect = NSInsetRect(rect, 14.0, 6.0);
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSColor *color = enabled ? OMDResolvedControlTextColor() : OMDResolvedMutedTextColor();
    CGFloat midX = NSMidX(glyphRect);
    CGFloat midY = NSMidY(glyphRect);

    [color setStroke];
    [color setFill];
    [path setLineWidth:1.7];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];

    switch (index) {
        case 0:
            [path appendBezierPathWithRect:NSMakeRect(NSMinX(glyphRect) + 1.0, NSMinY(glyphRect) + 2.0,
                                                       NSWidth(glyphRect) - 2.0, NSHeight(glyphRect) - 4.0)];
            [path moveToPoint:NSMakePoint(NSMinX(glyphRect) + 6.0, NSMinY(glyphRect) + 2.0)];
            [path lineToPoint:NSMakePoint(NSMinX(glyphRect) + 6.0, NSMaxY(glyphRect) - 2.0)];
            break;
        case 1:
            [path moveToPoint:NSMakePoint(NSMinX(glyphRect) + 1.0, midY - 3.0)];
            [path lineToPoint:NSMakePoint(NSMinX(glyphRect) + 6.0, midY - 3.0)];
            [path lineToPoint:NSMakePoint(NSMinX(glyphRect) + 8.5, midY - 6.0)];
            [path lineToPoint:NSMakePoint(NSMaxX(glyphRect) - 1.0, midY - 6.0)];
            [path lineToPoint:NSMakePoint(NSMaxX(glyphRect) - 1.0, NSMaxY(glyphRect) - 3.0)];
            [path lineToPoint:NSMakePoint(NSMinX(glyphRect) + 1.0, NSMaxY(glyphRect) - 3.0)];
            [path closePath];
            break;
        case 2:
            [path appendBezierPathWithRect:NSInsetRect(glyphRect, 2.0, 1.0)];
            [path moveToPoint:NSMakePoint(NSMinX(glyphRect) + 5.0, NSMinY(glyphRect) + 2.0)];
            [path lineToPoint:NSMakePoint(NSMaxX(glyphRect) - 5.0, NSMinY(glyphRect) + 2.0)];
            [path moveToPoint:NSMakePoint(NSMinX(glyphRect) + 5.0, NSMaxY(glyphRect) - 5.0)];
            [path lineToPoint:NSMakePoint(NSMaxX(glyphRect) - 5.0, NSMaxY(glyphRect) - 5.0)];
            break;
        case 3:
            [path appendBezierPathWithRect:NSMakeRect(NSMinX(glyphRect) + 2.0, midY,
                                                       NSWidth(glyphRect) - 4.0, NSHeight(glyphRect) / 2.0 - 2.0)];
            [path moveToPoint:NSMakePoint(midX, NSMinY(glyphRect) + 1.0)];
            [path lineToPoint:NSMakePoint(midX, midY + 4.0)];
            [path moveToPoint:NSMakePoint(midX, NSMinY(glyphRect) + 1.0)];
            [path lineToPoint:NSMakePoint(midX - 4.0, NSMinY(glyphRect) + 5.0)];
            [path moveToPoint:NSMakePoint(midX, NSMinY(glyphRect) + 1.0)];
            [path lineToPoint:NSMakePoint(midX + 4.0, NSMinY(glyphRect) + 5.0)];
            break;
        case 4:
            [path appendBezierPathWithRect:NSMakeRect(NSMinX(glyphRect) + 3.0, NSMinY(glyphRect) + 1.0,
                                                       NSWidth(glyphRect) - 6.0, 5.0)];
            [path appendBezierPathWithRect:NSMakeRect(NSMinX(glyphRect) + 1.0, midY - 2.0,
                                                       NSWidth(glyphRect) - 2.0, 8.0)];
            [path moveToPoint:NSMakePoint(NSMinX(glyphRect) + 5.0, NSMaxY(glyphRect) - 2.0)];
            [path lineToPoint:NSMakePoint(NSMaxX(glyphRect) - 5.0, NSMaxY(glyphRect) - 2.0)];
            break;
        default:
            [path appendBezierPathWithOvalInRect:NSInsetRect(glyphRect, 4.0, 4.0)];
            [path moveToPoint:NSMakePoint(midX, NSMinY(glyphRect) + 1.0)];
            [path lineToPoint:NSMakePoint(midX, NSMinY(glyphRect) + 4.0)];
            [path moveToPoint:NSMakePoint(midX, NSMaxY(glyphRect) - 1.0)];
            [path lineToPoint:NSMakePoint(midX, NSMaxY(glyphRect) - 4.0)];
            [path moveToPoint:NSMakePoint(NSMinX(glyphRect) + 1.0, midY)];
            [path lineToPoint:NSMakePoint(NSMinX(glyphRect) + 4.0, midY)];
            [path moveToPoint:NSMakePoint(NSMaxX(glyphRect) - 1.0, midY)];
            [path lineToPoint:NSMakePoint(NSMaxX(glyphRect) - 4.0, midY)];
            break;
    }

    [path stroke];
}

- (void)drawRect:(NSRect)dirtyRect
{
    CGFloat groupGap = OMDToolbarActionGroupSpacing;
    CGFloat segmentWidth = OMDToolbarActionSegmentWidth;
    CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
    NSInteger index = 0;

    (void)dirtyRect;

    for (index = 0; index < 3; index++) {
        [self drawGlyphAtIndex:index
                        inRect:NSMakeRect(segmentWidth * index, controlY, segmentWidth, OMDToolbarControlHeight)
                       enabled:(_fileActionsControl == nil || [_fileActionsControl isEnabledForSegment:index])];
    }
    for (index = 0; index < 3; index++) {
        [self drawGlyphAtIndex:index + 3
                        inRect:NSMakeRect((segmentWidth * 3.0) + groupGap + (segmentWidth * index),
                                          controlY,
                                          segmentWidth,
                                          OMDToolbarControlHeight)
                       enabled:(_utilityActionsControl == nil || [_utilityActionsControl isEnabledForSegment:index])];
    }
}

@end
