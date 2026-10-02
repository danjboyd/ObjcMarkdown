// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMermaidFlowchartDrawing.h"
#import "OMMermaidFlowchart.h"
#import "OMMermaidERDrawing.h"
#include <math.h>

// Below this a diagram is too small to read; it draws wider than the page.
static const CGFloat OMFlowMinimumDrawScale = 0.55;

static NSDictionary *OMFlowTextAttributes(NSFont *font, NSColor *color)
{
    NSMutableParagraphStyle *paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraph setAlignment:NSCenterTextAlignment];
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithObject:paragraph forKey:NSParagraphStyleAttributeName];
    if (font != nil) {
        [attributes setObject:font forKey:NSFontAttributeName];
    }
    if (color != nil) {
        [attributes setObject:color forKey:NSForegroundColorAttributeName];
    }
    return attributes;
}

static NSSize OMFlowTextSize(NSString *text, NSFont *font)
{
    CGFloat width = 0.0;
    CGFloat lineHeight = font != nil ? ceil([font ascender] - [font descender] + 2.0) : 16.0;
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        width = MAX(width, [line sizeWithAttributes:OMFlowTextAttributes(font, nil)].width);
    }
    return NSMakeSize(ceil(width), lineHeight * (CGFloat)MAX((NSUInteger)1, [lines count]));
}

@implementation OMMermaidFlowStyleMeasurer

- (instancetype)initWithStyle:(OMMermaidERDrawingStyle *)style
{
    self = [super init];
    if (self != nil) {
        _style = [style retain];
    }
    return self;
}

- (void)dealloc
{
    [_style release];
    [super dealloc];
}

- (NSSize)mermaidFlowSizeForNodeLabel:(NSString *)label
{
    return OMFlowTextSize(label, [_style attributeFont]);
}

- (NSSize)mermaidFlowSizeForEdgeLabel:(NSString *)label
{
    return OMFlowTextSize(label, [_style labelFont]);
}

@end

@implementation OMMermaidFlowchartAttachmentCell

@synthesize layout = _layout;
@synthesize drawScale = _drawScale;

- (instancetype)initWithLayout:(OMMermaidFlowchartLayout *)layout
                         style:(OMMermaidERDrawingStyle *)style
                     drawScale:(CGFloat)drawScale
{
    self = [super init];
    if (self != nil) {
        _layout = [layout retain];
        _style = [style retain];
        _drawScale = drawScale > 0.01 ? drawScale : 1.0;
    }
    return self;
}

- (void)dealloc
{
    [_layout release];
    [_style release];
    [super dealloc];
}

- (NSSize)cellSize
{
    NSSize size = [_layout size];
    return NSMakeSize(ceil(size.width * _drawScale), ceil(size.height * _drawScale));
}

// Diagram coordinates (y down) into the view's.
- (NSPoint)om_point:(NSPoint)point inFrame:(NSRect)frame flipped:(BOOL)flipped
{
    CGFloat x = NSMinX(frame) + point.x * _drawScale;
    CGFloat y = flipped ? NSMinY(frame) + point.y * _drawScale : NSMaxY(frame) - point.y * _drawScale;
    return NSMakePoint(x, y);
}

- (NSRect)om_rect:(NSRect)rect inFrame:(NSRect)frame flipped:(BOOL)flipped
{
    NSPoint topLeft = [self om_point:rect.origin inFrame:frame flipped:flipped];
    CGFloat height = NSHeight(rect) * _drawScale;
    return NSMakeRect(topLeft.x, flipped ? topLeft.y : topLeft.y - height, NSWidth(rect) * _drawScale, height);
}

- (NSFont *)om_scaledFont:(NSFont *)font
{
    if (font == nil || _drawScale >= 0.999) {
        return font;
    }
    NSFont *scaled = [NSFont fontWithName:[font fontName] size:[font pointSize] * _drawScale];
    return scaled != nil ? scaled : font;
}

- (void)om_drawText:(NSString *)text font:(NSFont *)font color:(NSColor *)color inRect:(NSRect)rect
{
    if ([text length] == 0 || font == nil) {
        return;
    }
    NSSize size = OMFlowTextSize(text, font);
    NSRect textRect = NSMakeRect(NSMinX(rect), NSMidY(rect) - size.height / 2.0, NSWidth(rect), size.height);
    [text drawInRect:textRect withAttributes:OMFlowTextAttributes(font, color)];
}

- (NSBezierPath *)om_pathForShape:(OMMermaidFlowNodeShape)shape inRect:(NSRect)box
{
    switch (shape) {
        case OMMermaidFlowNodeShapeRounded:
            return [NSBezierPath bezierPathWithRoundedRect:box xRadius:8.0 * _drawScale yRadius:8.0 * _drawScale];
        case OMMermaidFlowNodeShapeStadium: {
            CGFloat radius = NSHeight(box) / 2.0;
            return [NSBezierPath bezierPathWithRoundedRect:box xRadius:radius yRadius:radius];
        }
        case OMMermaidFlowNodeShapeCircle:
            return [NSBezierPath bezierPathWithOvalInRect:box];
        case OMMermaidFlowNodeShapeDiamond: {
            NSBezierPath *path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(NSMidX(box), NSMinY(box))];
            [path lineToPoint:NSMakePoint(NSMaxX(box), NSMidY(box))];
            [path lineToPoint:NSMakePoint(NSMidX(box), NSMaxY(box))];
            [path lineToPoint:NSMakePoint(NSMinX(box), NSMidY(box))];
            [path closePath];
            return path;
        }
        default:
            return [NSBezierPath bezierPathWithRoundedRect:box xRadius:2.0 * _drawScale yRadius:2.0 * _drawScale];
    }
}

- (void)om_drawEdgesInFrame:(NSRect)frame flipped:(BOOL)flipped
{
    NSColor *edgeColor = [_style edgeColor] != nil ? [_style edgeColor] : [NSColor grayColor];
    NSFont *labelFont = [self om_scaledFont:[_style labelFont]];
    for (OMMermaidFlowEdgeLayout *edgeLayout in [_layout edgeLayouts]) {
        OMMermaidFlowEdge *edge = [edgeLayout edge];
        NSArray *points = [edgeLayout points];
        NSBezierPath *line = [NSBezierPath bezierPath];
        NSUInteger index = 0;
        for (; index < [points count]; index++) {
            NSPoint p = [self om_point:[[points objectAtIndex:index] pointValue] inFrame:frame flipped:flipped];
            if (index == 0) {
                [line moveToPoint:p];
            } else {
                [line lineToPoint:p];
            }
        }
        CGFloat width = ([edge style] == OMMermaidFlowEdgeStyleThick ? 2.6 : 1.3) * MAX(_drawScale, 0.75);
        [line setLineWidth:width];
        if ([edge style] == OMMermaidFlowEdgeStyleDotted) {
            CGFloat dash[2] = { 3.0 * _drawScale + 1.0, 3.0 * _drawScale + 1.0 };
            [line setLineDash:dash count:2 phase:0.0];
        }
        [edgeColor set];
        [line stroke];

        if ([edge hasArrow] && [points count] >= 2) {
            NSPoint tip = [self om_point:[[points lastObject] pointValue] inFrame:frame flipped:flipped];
            NSPoint from = [self om_point:[[points objectAtIndex:[points count] - 2] pointValue] inFrame:frame flipped:flipped];
            CGFloat angle = atan2(tip.y - from.y, tip.x - from.x);
            CGFloat length = 9.0 * MAX(_drawScale, 0.75);
            CGFloat spread = 0.42;
            NSBezierPath *head = [NSBezierPath bezierPath];
            [head moveToPoint:tip];
            [head lineToPoint:NSMakePoint(tip.x - length * cos(angle - spread), tip.y - length * sin(angle - spread))];
            [head lineToPoint:NSMakePoint(tip.x - length * cos(angle + spread), tip.y - length * sin(angle + spread))];
            [head closePath];
            [head fill];
        }

        if ([edge label] != nil && !NSIsEmptyRect([edgeLayout labelFrame])) {
            NSRect labelRect = [self om_rect:[edgeLayout labelFrame] inFrame:frame flipped:flipped];
            NSColor *background = [_style bodyBackgroundColor] != nil ? [_style bodyBackgroundColor] : [NSColor whiteColor];
            [background setFill];
            NSRectFill(labelRect);
            [self om_drawText:OMMermaidFlowDisplayText([edge label])
                         font:labelFont
                        color:[_style textColor]
                       inRect:labelRect];
        }
    }
}

- (void)om_drawNodesInFrame:(NSRect)frame flipped:(BOOL)flipped
{
    NSFont *font = [self om_scaledFont:[_style attributeFont]];
    NSColor *fill = [_style titleBackgroundColor] != nil ? [_style titleBackgroundColor] : [_style bodyBackgroundColor];
    for (OMMermaidFlowNodeLayout *nodeLayout in [_layout nodeLayouts]) {
        NSRect box = [self om_rect:[nodeLayout frame] inFrame:frame flipped:flipped];
        OMMermaidFlowNodeShape shape = [[nodeLayout node] shape];
        NSBezierPath *path = [self om_pathForShape:shape inRect:box];
        if (fill != nil) {
            [fill setFill];
            [path fill];
        }
        [[_style borderColor] set];
        [path setLineWidth:MAX(1.0, [_style borderWidth] * _drawScale)];
        [path stroke];
        if (shape == OMMermaidFlowNodeShapeSubroutine) {
            CGFloat inset = 7.0 * _drawScale;
            NSBezierPath *bars = [NSBezierPath bezierPath];
            [bars moveToPoint:NSMakePoint(NSMinX(box) + inset, NSMinY(box))];
            [bars lineToPoint:NSMakePoint(NSMinX(box) + inset, NSMaxY(box))];
            [bars moveToPoint:NSMakePoint(NSMaxX(box) - inset, NSMinY(box))];
            [bars lineToPoint:NSMakePoint(NSMaxX(box) - inset, NSMaxY(box))];
            [bars setLineWidth:MAX(1.0, [_style borderWidth] * _drawScale)];
            [bars stroke];
        }
        [self om_drawText:[nodeLayout text] font:font color:[_style textColor] inRect:box];
    }
}

- (void)om_drawInFrame:(NSRect)frame flipped:(BOOL)flipped
{
    [NSGraphicsContext saveGraphicsState];
    // Edges first, so nodes sit on top of their ends.
    [self om_drawEdgesInFrame:frame flipped:flipped];
    [self om_drawNodesInFrame:frame flipped:flipped];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [self om_drawInFrame:cellFrame flipped:(controlView != nil ? [controlView isFlipped] : NO)];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView characterIndex:(NSUInteger)charIndex
{
    [self drawWithFrame:cellFrame inView:controlView];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
        layoutManager:(NSLayoutManager *)layoutManager
{
    [self drawWithFrame:cellFrame inView:controlView];
}

@end

NSAttributedString *OMMermaidFlowchartAttachmentAttributedString(OMMermaidFlowchart *flowchart,
                                                                 OMMermaidERDrawingStyle *style,
                                                                 CGFloat maximumWidth,
                                                                 NSDictionary *attributes)
{
    if (flowchart == nil || style == nil) {
        return nil;
    }
    OMMermaidFlowStyleMeasurer *measurer = [[[OMMermaidFlowStyleMeasurer alloc] initWithStyle:style] autorelease];
    OMMermaidFlowchartLayout *layout = [OMMermaidFlowchartLayout layoutForFlowchart:flowchart measurer:measurer];
    if (layout == nil) {
        return nil;
    }
    CGFloat drawScale = 1.0;
    NSSize size = [layout size];
    if (maximumWidth > 0.0 && size.width > maximumWidth) {
        drawScale = MAX(OMFlowMinimumDrawScale, maximumWidth / size.width);
    }
    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    OMMermaidFlowchartAttachmentCell *cell = [[[OMMermaidFlowchartAttachmentCell alloc] initWithLayout:layout
                                                                                                 style:style
                                                                                             drawScale:drawScale] autorelease];
    [cell setAttachment:attachment];
    [attachment setAttachmentCell:cell];

    NSMutableDictionary *attachmentAttributes = [NSMutableDictionary dictionaryWithDictionary:(attributes != nil ? attributes : [NSDictionary dictionary])];
    [attachmentAttributes setObject:attachment forKey:NSAttachmentAttributeName];
    unichar attachmentCharacter = NSAttachmentCharacter;
    return [[[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&attachmentCharacter length:1]
                                            attributes:attachmentAttributes] autorelease];
}
