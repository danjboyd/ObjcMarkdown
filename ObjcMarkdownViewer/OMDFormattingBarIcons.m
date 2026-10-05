// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDFormattingBarIcons.h"
#import "OMDFormattingBarController.h"

static const CGFloat OMDFormattingIconSize = 16.0;
static const CGFloat OMDFormattingIconStroke = 1.5;

static NSBezierPath *OMDIconLine(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x1, y1)];
    [path lineToPoint:NSMakePoint(x2, y2)];
    [path setLineWidth:OMDFormattingIconStroke];
    [path setLineCapStyle:NSRoundLineCapStyle];
    return path;
}

static NSBezierPath *OMDIconPolyline(const NSPoint *points, NSUInteger count)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSUInteger index = 0;
    for (; index < count; index++) {
        if (index == 0) {
            [path moveToPoint:points[index]];
        } else {
            [path lineToPoint:points[index]];
        }
    }
    [path setLineWidth:OMDFormattingIconStroke];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];
    return path;
}

static void OMDIconStrokeFrame(NSRect rect, CGFloat radius)
{
    NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    [frame setLineWidth:OMDFormattingIconStroke];
    [frame stroke];
}

static void OMDIconFillDot(CGFloat x, CGFloat y, CGFloat radius)
{
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - radius, y - radius, radius * 2.0, radius * 2.0)] fill];
}

static void OMDIconDrawLetter(NSString *letter, NSFont *font, NSColor *color)
{
    if (font == nil) {
        return;
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        font, NSFontAttributeName,
        color, NSForegroundColorAttributeName,
        nil];
    NSSize size = [letter sizeWithAttributes:attributes];
    NSPoint origin = NSMakePoint(floor((OMDFormattingIconSize - size.width) / 2.0),
                                 floor((OMDFormattingIconSize - size.height) / 2.0));
    [letter drawAtPoint:origin withAttributes:attributes];
}

// Lines of text to the right of a list or quote marker.
static void OMDIconTextLines(CGFloat x, const CGFloat *ys, NSUInteger count, CGFloat lastLineEnd)
{
    NSUInteger index = 0;
    for (; index < count; index++) {
        CGFloat end = (index + 1 == count && lastLineEnd > 0.0) ? lastLineEnd : 14.5;
        [OMDIconLine(x, ys[index], end, ys[index]) stroke];
    }
}

static void OMDDrawFormattingIcon(NSInteger tag, NSColor *color)
{
    [color setStroke];
    [color setFill];

    switch (tag) {
        case OMDFormattingCommandTagBold:
            OMDIconDrawLetter(@"B", [NSFont boldSystemFontOfSize:13.0], color);
            break;
        case OMDFormattingCommandTagItalic: {
            [OMDIconLine(7.0, 13.0, 13.0, 13.0) stroke];
            [OMDIconLine(3.0, 3.0, 9.0, 3.0) stroke];
            [OMDIconLine(10.0, 13.0, 6.0, 3.0) stroke];
            break;
        }
        case OMDFormattingCommandTagStrike:
            OMDIconDrawLetter(@"S", [NSFont systemFontOfSize:13.0], color);
            [OMDIconLine(2.0, 8.0, 14.0, 8.0) stroke];
            break;
        case OMDFormattingCommandTagInlineCode: {
            NSPoint left[] = { {6.0, 3.5}, {1.5, 8.0}, {6.0, 12.5} };
            NSPoint right[] = { {10.0, 3.5}, {14.5, 8.0}, {10.0, 12.5} };
            [OMDIconPolyline(left, 3) stroke];
            [OMDIconPolyline(right, 3) stroke];
            break;
        }
        case OMDFormattingCommandTagCodeFence: {
            OMDIconStrokeFrame(NSMakeRect(1.5, 2.0, 13.0, 12.0), 2.0);
            NSPoint left[] = { {6.5, 5.5}, {4.5, 8.0}, {6.5, 10.5} };
            NSPoint right[] = { {9.5, 5.5}, {11.5, 8.0}, {9.5, 10.5} };
            [OMDIconPolyline(left, 3) stroke];
            [OMDIconPolyline(right, 3) stroke];
            break;
        }
        case OMDFormattingCommandTagLink: {
            // Two chain links on a diagonal.
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:8.0 yBy:8.0];
            [transform rotateByDegrees:45.0];
            [transform translateXBy:-8.0 yBy:-8.0];
            [NSGraphicsContext saveGraphicsState];
            [transform concat];
            OMDIconStrokeFrame(NSMakeRect(0.5, 5.75, 8.5, 4.5), 2.25);
            OMDIconStrokeFrame(NSMakeRect(7.0, 5.75, 8.5, 4.5), 2.25);
            [NSGraphicsContext restoreGraphicsState];
            break;
        }
        case OMDFormattingCommandTagImage: {
            OMDIconStrokeFrame(NSMakeRect(1.5, 2.0, 13.0, 12.0), 1.5);
            NSBezierPath *hills = [NSBezierPath bezierPath];
            [hills moveToPoint:NSMakePoint(3.0, 3.5)];
            [hills lineToPoint:NSMakePoint(6.5, 8.0)];
            [hills lineToPoint:NSMakePoint(9.0, 5.5)];
            [hills lineToPoint:NSMakePoint(10.5, 7.0)];
            [hills lineToPoint:NSMakePoint(13.0, 3.5)];
            [hills closePath];
            [hills fill];
            OMDIconFillDot(10.8, 10.6, 1.4);
            break;
        }
        case OMDFormattingCommandTagListBullet: {
            CGFloat ys[] = { 12.5, 8.0, 3.5 };
            OMDIconFillDot(2.5, 12.5, 1.4);
            OMDIconFillDot(2.5, 8.0, 1.4);
            OMDIconFillDot(2.5, 3.5, 1.4);
            OMDIconTextLines(6.0, ys, 3, 0.0);
            break;
        }
        case OMDFormattingCommandTagListNumber: {
            CGFloat ys[] = { 12.5, 8.0, 3.5 };
            NSFont *digitFont = [NSFont boldSystemFontOfSize:5.5];
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                digitFont, NSFontAttributeName,
                color, NSForegroundColorAttributeName,
                nil];
            NSArray *digits = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
            NSUInteger index = 0;
            for (; index < [digits count]; index++) {
                NSString *digit = [digits objectAtIndex:index];
                NSSize size = [digit sizeWithAttributes:attributes];
                [digit drawAtPoint:NSMakePoint(1.0, ys[index] - (size.height / 2.0))
                    withAttributes:attributes];
            }
            OMDIconTextLines(6.0, ys, 3, 0.0);
            break;
        }
        case OMDFormattingCommandTagListTask: {
            CGFloat ys[] = { 11.25, 4.75 };
            NSBezierPath *checked = [NSBezierPath bezierPathWithRect:NSMakeRect(1.5, 9.0, 4.5, 4.5)];
            NSBezierPath *unchecked = [NSBezierPath bezierPathWithRect:NSMakeRect(1.5, 2.5, 4.5, 4.5)];
            [checked setLineWidth:1.2];
            [unchecked setLineWidth:1.2];
            [checked stroke];
            [unchecked stroke];
            NSPoint tick[] = { {2.5, 11.4}, {3.6, 10.2}, {5.4, 12.6} };
            NSBezierPath *tickPath = OMDIconPolyline(tick, 3);
            [tickPath setLineWidth:1.2];
            [tickPath stroke];
            OMDIconTextLines(8.5, ys, 2, 0.0);
            break;
        }
        case OMDFormattingCommandTagBlockQuote: {
            CGFloat ys[] = { 12.5, 8.0, 3.5 };
            NSRectFill(NSMakeRect(1.5, 2.5, 2.0, 11.0));
            OMDIconTextLines(6.5, ys, 3, 11.0);
            break;
        }
        case OMDFormattingCommandTagTable: {
            OMDIconStrokeFrame(NSMakeRect(1.5, 2.0, 13.0, 12.0), 1.5);
            [OMDIconLine(1.5, 6.0, 14.5, 6.0) stroke];
            [OMDIconLine(1.5, 10.0, 14.5, 10.0) stroke];
            [OMDIconLine(6.0, 2.0, 6.0, 14.0) stroke];
            [OMDIconLine(10.0, 2.0, 10.0, 14.0) stroke];
            break;
        }
        case OMDFormattingCommandTagHorizontalRule: {
            NSBezierPath *rule = OMDIconLine(1.5, 8.0, 14.5, 8.0);
            [rule setLineWidth:2.0];
            [rule stroke];
            [[color colorWithAlphaComponent:0.45] setStroke];
            [OMDIconLine(3.0, 12.5, 13.0, 12.5) stroke];
            [OMDIconLine(3.0, 3.5, 13.0, 3.5) stroke];
            break;
        }
        default:
            break;
    }
}

NSImage *OMDFormattingBarIcon(NSInteger commandTag, NSColor *color)
{
    switch (commandTag) {
        case OMDFormattingCommandTagBold:
        case OMDFormattingCommandTagItalic:
        case OMDFormattingCommandTagStrike:
        case OMDFormattingCommandTagInlineCode:
        case OMDFormattingCommandTagLink:
        case OMDFormattingCommandTagImage:
        case OMDFormattingCommandTagListBullet:
        case OMDFormattingCommandTagListNumber:
        case OMDFormattingCommandTagListTask:
        case OMDFormattingCommandTagBlockQuote:
        case OMDFormattingCommandTagCodeFence:
        case OMDFormattingCommandTagTable:
        case OMDFormattingCommandTagHorizontalRule:
            break;
        default:
            return nil;
    }

    // Named system colours ignore colorWithAlphaComponent: on GNUstep.
    NSColor *drawColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (drawColor == nil) {
        drawColor = [NSColor colorWithCalibratedWhite:0.2 alpha:1.0];
    }

    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(OMDFormattingIconSize, OMDFormattingIconSize)] autorelease];
    [image lockFocus];
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    OMDDrawFormattingIcon(commandTag, drawColor);
    [image unlockFocus];
    return image;
}
