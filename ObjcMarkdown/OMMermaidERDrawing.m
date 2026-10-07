// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMermaidERDrawing.h"
#import "OMMermaidERDiagram.h"
#import "OMFontSupport.h"

#include <math.h>

// Cardinality markers occupy this much of the edge, measured out from the box.
static const CGFloat OMMermaidMarkerZone = 20.0;
static const CGFloat OMMermaidMarkerHalfWidth = 4.5;
static const CGFloat OMMermaidMarkerRadius = 3.0;
// A diagram never shrinks below this, even when it overflows the text column;
// past it the drawing stops being readable and overflow is the better tradeoff.
static const CGFloat OMMermaidMinimumDrawScale = 0.55;

#pragma mark - Style

@implementation OMMermaidERDrawingStyle

@synthesize titleFont = _titleFont;
@synthesize attributeFont = _attributeFont;
@synthesize labelFont = _labelFont;
@synthesize borderColor = _borderColor;
@synthesize titleBackgroundColor = _titleBackgroundColor;
@synthesize bodyBackgroundColor = _bodyBackgroundColor;
@synthesize textColor = _textColor;
@synthesize keyColor = _keyColor;
@synthesize commentColor = _commentColor;
@synthesize edgeColor = _edgeColor;
@synthesize borderWidth = _borderWidth;

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _borderWidth = 1.0;
    }
    return self;
}

- (void)dealloc
{
    [_titleFont release];
    [_attributeFont release];
    [_labelFont release];
    [_borderColor release];
    [_titleBackgroundColor release];
    [_bodyBackgroundColor release];
    [_textColor release];
    [_keyColor release];
    [_commentColor release];
    [_edgeColor release];
    [super dealloc];
}

@end

#pragma mark - Measuring

static CGFloat OMMermaidTextWidth(NSString *text, NSFont *font)
{
    if (text == nil || [text length] == 0) {
        return 0.0;
    }
    if (font == nil) {
        return (CGFloat)[text length] * 7.0;
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    return [text sizeWithAttributes:attributes].width;
}

static CGFloat OMMermaidLineHeight(NSFont *font)
{
    if (font == nil) {
        return 14.0;
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    CGFloat height = [@"Hg" sizeWithAttributes:attributes].height;
    return height > 0.0 ? height : ([font pointSize] * 1.2);
}

@implementation OMMermaidERStyleMeasurer

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

- (CGFloat)mermaidWidthForEntityTitle:(NSString *)title
{
    return OMMermaidTextWidth(title, [_style titleFont]);
}

- (CGFloat)mermaidWidthForAttributeText:(NSString *)text
{
    return OMMermaidTextWidth(text, [_style attributeFont]);
}

- (CGFloat)mermaidWidthForRelationshipLabel:(NSString *)label
{
    return OMMermaidTextWidth(label, [_style labelFont]);
}

@end

OMMermaidERLayoutMetrics *OMMermaidERMetricsForStyle(OMMermaidERDrawingStyle *style)
{
    OMMermaidERLayoutMetrics *metrics = [OMMermaidERLayoutMetrics defaultMetrics];
    if (style == nil) {
        return metrics;
    }

    CGFloat titleLine = OMMermaidLineHeight([style titleFont]);
    CGFloat attributeLine = OMMermaidLineHeight([style attributeFont]);
    CGFloat labelLine = OMMermaidLineHeight([style labelFont]);

    [metrics setTitleHeight:ceil(titleLine + 10.0)];
    [metrics setAttributeRowHeight:ceil(attributeLine + 4.0)];
    [metrics setLabelHeight:ceil(labelLine)];
    [metrics setBoxHorizontalPadding:ceil(attributeLine * 0.55)];
    [metrics setColumnGap:ceil(attributeLine * 0.7)];
    [metrics setMinimumBoxWidth:ceil(titleLine * 5.0)];
    [metrics setRankSpacing:ceil(titleLine * 2.6)];
    [metrics setSiblingSpacing:ceil(titleLine * 1.8)];
    [metrics setEdgeLaneSpacing:ceil(labelLine + 6.0)];
    [metrics setMargin:ceil(attributeLine * 0.6)];
    return metrics;
}

#pragma mark - Coordinate mapping

// Layout geometry is y-down with its origin at the top left; text views may be
// flipped either way, so every point goes through here.
static NSPoint OMMermaidViewPoint(NSPoint point, NSRect frame, BOOL flipped, CGFloat scale)
{
    if (flipped) {
        return NSMakePoint(NSMinX(frame) + (point.x * scale),
                           NSMinY(frame) + (point.y * scale));
    }
    return NSMakePoint(NSMinX(frame) + (point.x * scale),
                       NSMaxY(frame) - (point.y * scale));
}

static NSRect OMMermaidViewRect(NSRect rect, NSRect frame, BOOL flipped, CGFloat scale)
{
    CGFloat width = rect.size.width * scale;
    CGFloat height = rect.size.height * scale;
    CGFloat x = NSMinX(frame) + (rect.origin.x * scale);
    CGFloat y = flipped
        ? (NSMinY(frame) + (rect.origin.y * scale))
        : (NSMaxY(frame) - ((rect.origin.y + rect.size.height) * scale));
    return NSMakeRect(x, y, width, height);
}

#pragma mark - Drawing helpers

static void OMMermaidDrawText(NSString *text,
                              NSFont *font,
                              NSColor *color,
                              NSRect rect,
                              BOOL centered)
{
    if (text == nil || [text length] == 0 || rect.size.width <= 0.0 || font == nil) {
        return;
    }

    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    [attributes setObject:font forKey:NSFontAttributeName];
    if (color != nil) {
        [attributes setObject:color forKey:NSForegroundColorAttributeName];
    }

    NSSize size = [text sizeWithAttributes:attributes];
    CGFloat x = centered ? (NSMidX(rect) - (size.width / 2.0)) : NSMinX(rect);
    CGFloat y = NSMidY(rect) - (size.height / 2.0);
    [text drawAtPoint:NSMakePoint(x, y) withAttributes:attributes];
}

// Draws one cardinality marker at pointA, oriented along the segment running
// from pointA toward pointB (that is, away from the entity box).
static void OMMermaidDrawCardinalityMarker(OMMermaidERCardinality cardinality,
                                           NSPoint pointA,
                                           NSPoint pointB,
                                           NSColor *color,
                                           CGFloat lineWidth,
                                           CGFloat scale)
{
    CGFloat dx = pointB.x - pointA.x;
    CGFloat dy = pointB.y - pointA.y;
    CGFloat length = sqrt((dx * dx) + (dy * dy));
    if (length < 1.0) {
        return;
    }

    CGFloat zone = OMMermaidMarkerZone * scale;
    if (zone > length * 0.8) {
        zone = length * 0.8;
    }
    if (zone < 6.0) {
        return;
    }
    CGFloat unit = zone / (OMMermaidMarkerZone * scale);

    NSPoint direction = NSMakePoint(dx / length, dy / length);
    NSPoint normal = NSMakePoint(-direction.y, direction.x);
    CGFloat halfWidth = OMMermaidMarkerHalfWidth * scale * unit;
    CGFloat radius = OMMermaidMarkerRadius * scale * unit;

    BOOL many = (cardinality == OMMermaidERCardinalityZeroOrMore ||
                 cardinality == OMMermaidERCardinalityOneOrMore);
    BOOL optional = (cardinality == OMMermaidERCardinalityZeroOrOne ||
                     cardinality == OMMermaidERCardinalityZeroOrMore);

    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:lineWidth];

    if (many) {
        // Crow's foot: apex out along the edge, toes on the box.
        NSPoint apex = NSMakePoint(pointA.x + (direction.x * zone * 0.5),
                                   pointA.y + (direction.y * zone * 0.5));
        NSPoint left = NSMakePoint(pointA.x + (normal.x * halfWidth),
                                   pointA.y + (normal.y * halfWidth));
        NSPoint right = NSMakePoint(pointA.x - (normal.x * halfWidth),
                                    pointA.y - (normal.y * halfWidth));
        [path moveToPoint:apex];
        [path lineToPoint:left];
        [path moveToPoint:apex];
        [path lineToPoint:right];
        [path moveToPoint:apex];
        [path lineToPoint:pointA];
    }

    // The "one" bar sits beyond the foot when there is one.
    CGFloat barOffset = many ? (zone * 0.75) : (zone * 0.4);
    if (!optional || !many) {
        NSPoint barCenter = NSMakePoint(pointA.x + (direction.x * barOffset),
                                        pointA.y + (direction.y * barOffset));
        [path moveToPoint:NSMakePoint(barCenter.x + (normal.x * halfWidth),
                                      barCenter.y + (normal.y * halfWidth))];
        [path lineToPoint:NSMakePoint(barCenter.x - (normal.x * halfWidth),
                                      barCenter.y - (normal.y * halfWidth))];
    }
    if (cardinality == OMMermaidERCardinalityExactlyOne) {
        NSPoint secondBar = NSMakePoint(pointA.x + (direction.x * zone * 0.68),
                                        pointA.y + (direction.y * zone * 0.68));
        [path moveToPoint:NSMakePoint(secondBar.x + (normal.x * halfWidth),
                                      secondBar.y + (normal.y * halfWidth))];
        [path lineToPoint:NSMakePoint(secondBar.x - (normal.x * halfWidth),
                                      secondBar.y - (normal.y * halfWidth))];
    }
    [path stroke];

    if (optional) {
        CGFloat circleOffset = many ? (zone * 0.9) : (zone * 0.72);
        NSPoint center = NSMakePoint(pointA.x + (direction.x * circleOffset),
                                     pointA.y + (direction.y * circleOffset));
        NSRect circleRect = NSMakeRect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0);
        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:circleRect];
        [circle setLineWidth:lineWidth];
        [circle stroke];
    }
}

#pragma mark - Attachment cell

@implementation OMMermaidERDiagramAttachmentCell

@synthesize layout = _layout;
@synthesize drawScale = _drawScale;

static NSFont *OMMermaidScaledFont(NSFont *font, CGFloat scale)
{
    if (font == nil) {
        return nil;
    }
    if (scale >= 0.999) {
        return font;
    }
    NSFont *scaled = OMFontAtSize(font, [font pointSize] * scale);
    return scaled != nil ? scaled : font;
}

- (instancetype)initWithLayout:(OMMermaidERDiagramLayout *)layout
                         style:(OMMermaidERDrawingStyle *)style
                     drawScale:(CGFloat)drawScale
{
    self = [super init];
    if (self != nil) {
        _layout = [layout retain];
        _style = [style retain];
        _drawScale = drawScale > 0.01 ? drawScale : 1.0;
        _scaledTitleFont = [OMMermaidScaledFont([style titleFont], _drawScale) retain];
        _scaledAttributeFont = [OMMermaidScaledFont([style attributeFont], _drawScale) retain];
        _scaledLabelFont = [OMMermaidScaledFont([style labelFont], _drawScale) retain];
    }
    return self;
}

- (void)dealloc
{
    [_layout release];
    [_style release];
    [_scaledTitleFont release];
    [_scaledAttributeFont release];
    [_scaledLabelFont release];
    [super dealloc];
}

- (NSSize)cellSize
{
    NSSize size = [_layout size];
    return NSMakeSize(ceil(size.width * _drawScale), ceil(size.height * _drawScale));
}

- (void)om_drawEntitiesInFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
    CGFloat lineWidth = MAX(1.0, [_style borderWidth] * _drawScale);

    for (OMMermaidEREntityLayout *entity in [_layout entityLayouts]) {
        NSRect boxRect = OMMermaidViewRect([entity frame], cellFrame, flipped, _drawScale);
        NSRect titleRect = OMMermaidViewRect([entity titleFrame], cellFrame, flipped, _drawScale);

        if ([_style bodyBackgroundColor] != nil) {
            [[_style bodyBackgroundColor] setFill];
            NSRectFill(boxRect);
        }
        if ([_style titleBackgroundColor] != nil) {
            [[_style titleBackgroundColor] setFill];
            NSRectFill(titleRect);
        }

        [[_style borderColor] set];
        NSBezierPath *border = [NSBezierPath bezierPathWithRect:boxRect];
        [border setLineWidth:lineWidth];
        [border stroke];

        NSBezierPath *titleRule = [NSBezierPath bezierPath];
        [titleRule setLineWidth:lineWidth];
        CGFloat ruleY = flipped ? NSMaxY(titleRect) : NSMinY(titleRect);
        [titleRule moveToPoint:NSMakePoint(NSMinX(titleRect), ruleY)];
        [titleRule lineToPoint:NSMakePoint(NSMaxX(titleRect), ruleY)];
        [titleRule stroke];

        OMMermaidDrawText([[entity entity] displayName],
                          _scaledTitleFont,
                          [_style textColor],
                          titleRect,
                          YES);

        for (OMMermaidERAttributeRowLayout *row in [entity attributeRows]) {
            OMMermaidERAttribute *attribute = [row attribute];
            OMMermaidDrawText([attribute type],
                              _scaledAttributeFont,
                              [_style textColor],
                              OMMermaidViewRect([row typeFrame], cellFrame, flipped, _drawScale),
                              NO);
            OMMermaidDrawText([attribute name],
                              _scaledAttributeFont,
                              [_style textColor],
                              OMMermaidViewRect([row nameFrame], cellFrame, flipped, _drawScale),
                              NO);
            if ([[attribute keys] count] > 0) {
                OMMermaidDrawText([[attribute keys] componentsJoinedByString:@","],
                                  _scaledAttributeFont,
                                  [_style keyColor],
                                  OMMermaidViewRect([row keyFrame], cellFrame, flipped, _drawScale),
                                  NO);
            }
            if ([attribute comment] != nil) {
                OMMermaidDrawText([attribute comment],
                                  _scaledAttributeFont,
                                  [_style commentColor],
                                  OMMermaidViewRect([row commentFrame], cellFrame, flipped, _drawScale),
                                  NO);
            }
        }
    }
}

- (void)om_drawEdgesInFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
    CGFloat lineWidth = MAX(1.0, [_style borderWidth] * _drawScale);

    for (OMMermaidEREdgeLayout *edge in [_layout edgeLayouts]) {
        NSArray *points = [edge points];
        if ([points count] < 2) {
            continue;
        }

        NSBezierPath *path = [NSBezierPath bezierPath];
        [path setLineWidth:lineWidth];
        NSUInteger index = 0;
        for (; index < [points count]; index++) {
            NSPoint point = OMMermaidViewPoint([[points objectAtIndex:index] pointValue],
                                               cellFrame, flipped, _drawScale);
            if (index == 0) {
                [path moveToPoint:point];
            } else {
                [path lineToPoint:point];
            }
        }
        [[_style edgeColor] set];
        if (![[edge relationship] isIdentifying]) {
            CGFloat pattern[2];
            pattern[0] = 4.0 * _drawScale;
            pattern[1] = 3.0 * _drawScale;
            [path setLineDash:pattern count:2 phase:0.0];
        }
        [path stroke];

        NSPoint start = OMMermaidViewPoint([[points objectAtIndex:0] pointValue],
                                           cellFrame, flipped, _drawScale);
        NSPoint afterStart = OMMermaidViewPoint([[points objectAtIndex:1] pointValue],
                                                cellFrame, flipped, _drawScale);
        NSPoint end = OMMermaidViewPoint([[points lastObject] pointValue],
                                         cellFrame, flipped, _drawScale);
        NSPoint beforeEnd = OMMermaidViewPoint([[points objectAtIndex:[points count] - 2] pointValue],
                                               cellFrame, flipped, _drawScale);

        OMMermaidDrawCardinalityMarker([[edge relationship] leftCardinality],
                                       start, afterStart,
                                       [_style edgeColor], lineWidth, _drawScale);
        OMMermaidDrawCardinalityMarker([[edge relationship] rightCardinality],
                                       end, beforeEnd,
                                       [_style edgeColor], lineWidth, _drawScale);

        NSRect labelFrame = [edge labelFrame];
        if (!NSIsEmptyRect(labelFrame)) {
            NSRect labelRect = OMMermaidViewRect(labelFrame, cellFrame, flipped, _drawScale);
            if ([_style bodyBackgroundColor] != nil) {
                [[_style bodyBackgroundColor] setFill];
                NSRectFill(labelRect);
            }
            OMMermaidDrawText([[edge relationship] label],
                              _scaledLabelFont,
                              [_style commentColor],
                              labelRect,
                              YES);
        }
    }
}

- (void)om_drawDiagramInFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
    if (_layout == nil || _style == nil) {
        return;
    }

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];
    // Edges first so that boxes paint over the marker zone if the two overlap.
    [self om_drawEdgesInFrame:cellFrame flipped:flipped];
    [self om_drawEntitiesInFrame:cellFrame flipped:flipped];
    [context restoreGraphicsState];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawDiagramInFrame:cellFrame flipped:flipped];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
{
    (void)charIndex;
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawDiagramInFrame:cellFrame flipped:flipped];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
        layoutManager:(NSLayoutManager *)layoutManager
{
    (void)charIndex;
    (void)layoutManager;
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawDiagramInFrame:cellFrame flipped:flipped];
}

@end

#pragma mark - Attachment construction

NSAttributedString *OMMermaidERAttachmentAttributedString(OMMermaidERDiagram *diagram,
                                                          OMMermaidERDrawingStyle *style,
                                                          CGFloat maximumWidth,
                                                          NSDictionary *attributes)
{
    if (diagram == nil || style == nil) {
        return nil;
    }

    OMMermaidERStyleMeasurer *measurer = [[[OMMermaidERStyleMeasurer alloc] initWithStyle:style] autorelease];
    OMMermaidERDiagramLayout *layout =
        [OMMermaidERDiagramLayout layoutForDiagram:diagram
                                           metrics:OMMermaidERMetricsForStyle(style)
                                          measurer:measurer];
    if (layout == nil) {
        return nil;
    }

    CGFloat drawScale = 1.0;
    NSSize size = [layout size];
    if (maximumWidth > 0.0 && size.width > maximumWidth && size.width > 0.0) {
        drawScale = maximumWidth / size.width;
        if (drawScale < OMMermaidMinimumDrawScale) {
            drawScale = OMMermaidMinimumDrawScale;
        }
    }

    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    OMMermaidERDiagramAttachmentCell *cell =
        [[[OMMermaidERDiagramAttachmentCell alloc] initWithLayout:layout
                                                            style:style
                                                        drawScale:drawScale] autorelease];
    if (cell == nil) {
        return nil;
    }
    [cell setAttachment:attachment];
    [attachment setAttachmentCell:cell];

    NSMutableDictionary *attachmentAttributes = [NSMutableDictionary dictionary];
    if (attributes != nil) {
        [attachmentAttributes addEntriesFromDictionary:attributes];
    }
    [attachmentAttributes setObject:attachment forKey:NSAttachmentAttributeName];

    unichar attachmentCharacter = NSAttachmentCharacter;
    NSString *attachmentString = [NSString stringWithCharacters:&attachmentCharacter length:1];
    return [[[NSAttributedString alloc] initWithString:attachmentString
                                            attributes:attachmentAttributes] autorelease];
}
