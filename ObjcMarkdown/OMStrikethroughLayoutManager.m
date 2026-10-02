// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMStrikethroughLayoutManager.h"

static NSString * const OMStrikeRectKey = @"rect";
static NSString * const OMStrikeColorKey = @"color";

@interface OMStrikethroughLayoutManager ()
- (NSArray *)strikethroughLinesForGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin;
@end

@implementation OMStrikethroughLayoutManager

// The colour a struck run is drawn in: its strikethrough colour, else its text colour.
- (NSColor *)strikethroughColorAtCharacterIndex:(NSUInteger)index
{
    NSTextStorage *storage = [self textStorage];
    NSColor *color = [storage attribute:NSStrikethroughColorAttributeName atIndex:index effectiveRange:NULL];
    if (color == nil) {
        color = [storage attribute:NSForegroundColorAttributeName atIndex:index effectiveRange:NULL];
    }
    return color != nil ? color : [NSColor textColor];
}

// One {rect, color} per line fragment each struck run crosses.
- (NSArray *)strikethroughLinesForGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin
{
    NSMutableArray *lines = [NSMutableArray array];
    NSTextStorage *storage = [self textStorage];
    if (storage == nil || glyphRange.length == 0) {
        return lines;
    }
    NSRange characters = [self characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
    NSString *text = [storage string];
    NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
    NSUInteger index = characters.location;
    while (index < NSMaxRange(characters)) {
        NSRange run;
        NSNumber *style = [storage attribute:NSStrikethroughStyleAttributeName
                                     atIndex:index
                       longestEffectiveRange:&run
                                     inRange:NSMakeRange(index, NSMaxRange(characters) - index)];
        index = NSMaxRange(run);
        if ([style integerValue] == 0) {
            continue;
        }
        // Leave a line break at the end of the run unstruck.
        while (run.length > 0 && [newlines characterIsMember:[text characterAtIndex:NSMaxRange(run) - 1]]) {
            run.length -= 1;
        }
        NSRange runGlyphs = NSIntersectionRange([self glyphRangeForCharacterRange:run actualCharacterRange:NULL],
                                                glyphRange);
        NSUInteger glyph = runGlyphs.location;
        while (glyph < NSMaxRange(runGlyphs)) {
            NSRange fragmentGlyphs;
            NSRect fragment = [self lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&fragmentGlyphs];
            NSRange segment = NSIntersectionRange(runGlyphs, fragmentGlyphs);
            if (segment.length == 0) {
                break;
            }
            NSTextContainer *container = [self textContainerForGlyphAtIndex:segment.location effectiveRange:NULL];
            NSRect box = [self boundingRectForGlyphRange:segment inTextContainer:container];
            NSUInteger firstCharacter = [self characterIndexForGlyphAtIndex:segment.location];
            NSFont *font = [storage attribute:NSFontAttributeName atIndex:firstCharacter effectiveRange:NULL];
            if (font == nil) {
                font = [NSFont userFontOfSize:0.0];
            }
            // locationForGlyphAtIndex: is the baseline, measured from the
            // fragment's top in the text system's flipped coordinates.
            CGFloat baseline = NSMinY(fragment) + [self locationForGlyphAtIndex:segment.location].y;
            CGFloat thickness = MAX(1.0, floor([font pointSize] * 0.06 + 0.5));
            CGFloat middle = baseline - [font xHeight] * 0.5;
            NSRect line = NSMakeRect(origin.x + NSMinX(box),
                                     origin.y + floor(middle - thickness * 0.5),
                                     NSWidth(box),
                                     thickness);
            if (NSWidth(line) > 0.0) {
                [lines addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSValue valueWithRect:line], OMStrikeRectKey,
                                  [self strikethroughColorAtCharacterIndex:firstCharacter], OMStrikeColorKey,
                                  nil]];
            }
            glyph = NSMaxRange(segment);
        }
    }
    return lines;
}

- (NSArray *)strikethroughLineRectsForGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin
{
    NSMutableArray *rects = [NSMutableArray array];
    for (NSDictionary *line in [self strikethroughLinesForGlyphRange:glyphRange atPoint:origin]) {
        [rects addObject:[line objectForKey:OMStrikeRectKey]];
    }
    return rects;
}

#if defined(GNUSTEP)
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
{
    [super drawGlyphsForGlyphRange:glyphsToShow atPoint:origin];
    NSArray *lines = [self strikethroughLinesForGlyphRange:glyphsToShow atPoint:origin];
    if ([lines count] == 0) {
        return;
    }
    [NSGraphicsContext saveGraphicsState];
    for (NSDictionary *line in lines) {
        [(NSColor *)[line objectForKey:OMStrikeColorKey] set];
        NSRectFill([[line objectForKey:OMStrikeRectKey] rectValue]);
    }
    [NSGraphicsContext restoreGraphicsState];
}
#endif

@end

void OMDrawStrikethroughForAttributedString(NSAttributedString *string, NSRect rect, BOOL flipped)
{
#if defined(GNUSTEP)
    if ([string length] == 0 || NSWidth(rect) <= 0.0) {
        return;
    }
    NSRange effective;
    id style = [string attribute:NSStrikethroughStyleAttributeName
                         atIndex:0
           longestEffectiveRange:&effective
                         inRange:NSMakeRange(0, [string length])];
    if (style == nil && NSMaxRange(effective) >= [string length]) {
        return;
    }
    // Lay the string out the way GNUstep's string drawing does.
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:string];
    OMStrikethroughLayoutManager *layoutManager = [[OMStrikethroughLayoutManager alloc] init];
    NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(NSWidth(rect), 1.0e7)];
    [container setLineFragmentPadding:0.0];
    [layoutManager addTextContainer:container];
    [storage addLayoutManager:layoutManager];
    NSRange glyphs = [layoutManager glyphRangeForTextContainer:container];
    NSArray *lines = [layoutManager strikethroughLinesForGlyphRange:glyphs atPoint:NSZeroPoint];
    [NSGraphicsContext saveGraphicsState];
    for (NSDictionary *line in lines) {
        NSRect laidOut = [[line objectForKey:OMStrikeRectKey] rectValue];
        CGFloat y = flipped ? NSMinY(rect) + NSMinY(laidOut)
                            : NSMaxY(rect) - NSMaxY(laidOut);
        [(NSColor *)[line objectForKey:OMStrikeColorKey] set];
        NSRectFill(NSMakeRect(NSMinX(rect) + NSMinX(laidOut), y, NSWidth(laidOut), NSHeight(laidOut)));
    }
    [NSGraphicsContext restoreGraphicsState];
    [container release];
    [layoutManager release];
    [storage release];
#else
    (void)string;
    (void)rect;
    (void)flipped;
#endif
}
