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

// A Mermaid style colour: "#rgb", "#rgba", "#rrggbb", "#rrggbbaa",
// "rgb(r, g, b)", "rgba(r, g, b, a)", "none"/"transparent" or a common
// CSS name. nil when not understood.
static NSColor *OMFlowColorFromCSS(NSString *value)
{
    NSString *text = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    if ([text hasSuffix:@"!important"]) {
        text = [[text substringToIndex:[text length] - 10] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    if ([text length] == 0) {
        return nil;
    }
    if ([text isEqualToString:@"none"] || [text isEqualToString:@"transparent"]) {
        return [NSColor colorWithCalibratedWhite:0.0 alpha:0.0];
    }
    if ([text hasPrefix:@"#"]) {
        NSString *hex = [text substringFromIndex:1];
        if ([hex length] == 3 || [hex length] == 4) {
            NSMutableString *expanded = [NSMutableString string];
            NSUInteger index = 0;
            for (; index < [hex length]; index++) {
                unichar ch = [hex characterAtIndex:index];
                [expanded appendFormat:@"%C%C", ch, ch];
            }
            hex = expanded;
        }
        if ([hex length] != 6 && [hex length] != 8) {
            return nil;
        }
        unsigned int components[4] = { 0, 0, 0, 255 };
        NSUInteger index = 0;
        for (; index < [hex length] / 2; index++) {
            NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(index * 2, 2)]];
            if (![scanner scanHexInt:&components[index]]) {
                return nil;
            }
        }
        return [NSColor colorWithCalibratedRed:components[0] / 255.0 green:components[1] / 255.0
                                          blue:components[2] / 255.0 alpha:components[3] / 255.0];
    }
    if ([text hasPrefix:@"rgb"]) {
        NSRange open = [text rangeOfString:@"("];
        NSRange close = [text rangeOfString:@")" options:NSBackwardsSearch];
        if (open.location == NSNotFound || close.location == NSNotFound || close.location < open.location) {
            return nil;
        }
        NSArray *parts = [[text substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))]
                          componentsSeparatedByString:@","];
        if ([parts count] < 3) {
            return nil;
        }
        CGFloat alpha = [parts count] > 3 ? [[parts objectAtIndex:3] doubleValue] : 1.0;
        return [NSColor colorWithCalibratedRed:[[parts objectAtIndex:0] doubleValue] / 255.0
                                         green:[[parts objectAtIndex:1] doubleValue] / 255.0
                                          blue:[[parts objectAtIndex:2] doubleValue] / 255.0
                                         alpha:MAX(0.0, MIN(1.0, alpha))];
    }
    static NSDictionary *names = nil;
    if (names == nil) {
        names = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"#000000", @"black", @"#ffffff", @"white", @"#808080", @"gray", @"#808080", @"grey",
            @"#d3d3d3", @"lightgray", @"#d3d3d3", @"lightgrey", @"#a9a9a9", @"darkgray", @"#a9a9a9", @"darkgrey",
            @"#ff0000", @"red", @"#008000", @"green", @"#0000ff", @"blue", @"#ffff00", @"yellow",
            @"#ffa500", @"orange", @"#800080", @"purple", @"#ffc0cb", @"pink", @"#a52a2a", @"brown",
            @"#00ffff", @"cyan", @"#ff00ff", @"magenta", @"#add8e6", @"lightblue", @"#90ee90", @"lightgreen",
            @"#00008b", @"darkblue", @"#006400", @"darkgreen", @"#8b0000", @"darkred", @"#ffd700", @"gold",
            @"#f5f5dc", @"beige", @"#e6e6fa", @"lavender", @"#000080", @"navy", @"#008080", @"teal",
            @"#808000", @"olive", @"#800000", @"maroon", @"#00ff00", @"lime", @"#c0c0c0", @"silver", nil];
    }
    NSString *hex = [names objectForKey:text];
    return hex != nil ? OMFlowColorFromCSS(hex) : nil;
}

// A style length such as "4px" or "2", in points; fallback when absent.
static CGFloat OMFlowLengthFromCSS(NSString *value, CGFloat fallback)
{
    if ([value length] == 0) {
        return fallback;
    }
    CGFloat length = [value doubleValue];
    return length > 0.0 ? length : fallback;
}

// "5 5" or "5,5" as a dash pattern; NO when absent or not a pattern.
static BOOL OMFlowDashFromCSS(NSString *value, CGFloat dash[2])
{
    NSArray *parts = [[value stringByReplacingOccurrencesOfString:@"," withString:@" "]
                      componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *numbers = [NSMutableArray array];
    for (NSString *part in parts) {
        if ([part doubleValue] > 0.0) {
            [numbers addObject:part];
        }
    }
    if ([numbers count] == 0) {
        return NO;
    }
    dash[0] = [[numbers objectAtIndex:0] doubleValue];
    dash[1] = [numbers count] > 1 ? [[numbers objectAtIndex:1] doubleValue] : dash[0];
    return YES;
}

static NSColor *OMFlowBlend(NSColor *base, NSColor *mix, CGFloat fraction)
{
    NSColor *a = [base colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSColor *b = [mix colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (a == nil || b == nil) {
        return base;
    }
    return [NSColor colorWithCalibratedRed:[a redComponent] + ([b redComponent] - [a redComponent]) * fraction
                                     green:[a greenComponent] + ([b greenComponent] - [a greenComponent]) * fraction
                                      blue:[a blueComponent] + ([b blueComponent] - [a blueComponent]) * fraction
                                     alpha:1.0];
}

// Text on a styled fill with no styled text colour: dark on a light fill,
// light on a dark one, so a light fill stays readable in the dark theme.
static NSColor *OMFlowTextColorOnFill(NSColor *fill, NSColor *fallback)
{
    NSColor *rgb = [fill colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (rgb == nil || [rgb alphaComponent] < 0.5) {
        return fallback;
    }
    CGFloat luminance = 0.2126 * [rgb redComponent] + 0.7152 * [rgb greenComponent] + 0.0722 * [rgb blueComponent];
    return luminance > 0.55 ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
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
        NSDictionary *properties = [[nodeLayout node] styleProperties];
        NSColor *nodeFill = OMFlowColorFromCSS([properties objectForKey:@"fill"]);
        NSColor *nodeStroke = OMFlowColorFromCSS([properties objectForKey:@"stroke"]);
        NSColor *nodeText = OMFlowColorFromCSS([properties objectForKey:@"color"]);
        CGFloat strokeWidth = OMFlowLengthFromCSS([properties objectForKey:@"stroke-width"], [_style borderWidth]);
        if (nodeFill != nil || fill != nil) {
            [(nodeFill != nil ? nodeFill : fill) setFill];
            [path fill];
        }
        [(nodeStroke != nil ? nodeStroke : [_style borderColor]) set];
        [path setLineWidth:MAX(1.0, strokeWidth * _drawScale)];
        CGFloat dash[2];
        if (OMFlowDashFromCSS([properties objectForKey:@"stroke-dasharray"], dash)) {
            dash[0] *= _drawScale;
            dash[1] *= _drawScale;
            [path setLineDash:dash count:2 phase:0.0];
        }
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
        if (nodeText == nil && nodeFill != nil) {
            nodeText = OMFlowTextColorOnFill(nodeFill, [_style textColor]);
        }
        [self om_drawText:[nodeLayout text] font:font color:(nodeText != nil ? nodeText : [_style textColor]) inRect:box];
    }
}

// A subgraph's fill: its style's, else a faint tint of the border on the page.
- (NSColor *)om_fillForSubgraph:(OMMermaidFlowSubgraph *)subgraph
{
    NSColor *fill = OMFlowColorFromCSS([[subgraph styleProperties] objectForKey:@"fill"]);
    if (fill != nil) {
        return fill;
    }
    NSColor *background = [_style bodyBackgroundColor] != nil ? [_style bodyBackgroundColor] : [NSColor whiteColor];
    NSColor *border = [_style borderColor] != nil ? [_style borderColor] : [NSColor grayColor];
    return OMFlowBlend(background, border, 0.12);
}

// Subgraph frames, outermost first, so nested ones sit on top.
- (void)om_drawSubgraphsInFrame:(NSRect)frame flipped:(BOOL)flipped
{
    NSColor *border = [_style borderColor] != nil ? [_style borderColor] : [NSColor grayColor];
    for (OMMermaidFlowSubgraphLayout *subgraphLayout in [_layout subgraphLayouts]) {
        NSDictionary *properties = [[subgraphLayout subgraph] styleProperties];
        NSColor *stroke = OMFlowColorFromCSS([properties objectForKey:@"stroke"]);
        NSRect box = [self om_rect:[subgraphLayout frame] inFrame:frame flipped:flipped];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:4.0 * _drawScale yRadius:4.0 * _drawScale];
        [[self om_fillForSubgraph:[subgraphLayout subgraph]] setFill];
        [path fill];
        [(stroke != nil ? stroke : border) set];
        [path setLineWidth:MAX(1.0, OMFlowLengthFromCSS([properties objectForKey:@"stroke-width"], [_style borderWidth]) * _drawScale)];
        CGFloat dash[2];
        if (OMFlowDashFromCSS([properties objectForKey:@"stroke-dasharray"], dash)) {
            dash[0] *= _drawScale;
            dash[1] *= _drawScale;
            [path setLineDash:dash count:2 phase:0.0];
        }
        [path stroke];
    }
}

// Titles go over the edges, each on a patch of its frame's fill.
- (void)om_drawSubgraphTitlesInFrame:(NSRect)frame flipped:(BOOL)flipped
{
    NSFont *titleFont = [self om_scaledFont:[_style labelFont]];
    for (OMMermaidFlowSubgraphLayout *subgraphLayout in [_layout subgraphLayouts]) {
        OMMermaidFlowSubgraph *subgraph = [subgraphLayout subgraph];
        NSString *title = OMMermaidFlowDisplayText([subgraph title]);
        NSRect titleRect = [self om_rect:[subgraphLayout titleFrame] inFrame:frame flipped:flipped];
        NSSize size = OMFlowTextSize(title, titleFont);
        CGFloat width = MIN(NSWidth(titleRect), size.width + 6.0 * _drawScale);
        [[self om_fillForSubgraph:subgraph] setFill];
        NSRectFill(NSMakeRect(NSMidX(titleRect) - width / 2.0, NSMidY(titleRect) - size.height / 2.0, width, size.height));
        NSColor *text = OMFlowColorFromCSS([[subgraph styleProperties] objectForKey:@"color"]);
        NSColor *styledFill = OMFlowColorFromCSS([[subgraph styleProperties] objectForKey:@"fill"]);
        if (text == nil && styledFill != nil) {
            text = OMFlowTextColorOnFill(styledFill, [_style textColor]);
        }
        [self om_drawText:title font:titleFont color:(text != nil ? text : [_style textColor]) inRect:titleRect];
    }
}

- (void)om_drawInFrame:(NSRect)frame flipped:(BOOL)flipped
{
    [NSGraphicsContext saveGraphicsState];
    // Subgraphs behind everything; edges before nodes, so nodes sit on
    // top of their ends.
    [self om_drawSubgraphsInFrame:frame flipped:flipped];
    [self om_drawEdgesInFrame:frame flipped:flipped];
    [self om_drawSubgraphTitlesInFrame:frame flipped:flipped];
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
