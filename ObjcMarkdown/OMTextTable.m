// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMTextTable.h"
#import "OMRenderedObject.h"

NSString * const OMTextTableAttributeName = @"OMTextTable";
NSString * const OMTextTableRowAttributeName = @"OMTextTableRow";

@implementation OMTextTable

@synthesize columnEdges = _columnEdges;
@synthesize rowCount = _rowCount;
@synthesize borderWidth = _borderWidth;
@synthesize borderColor = _borderColor;
@synthesize headerBackgroundColor = _headerBackgroundColor;
@synthesize bodyBackgroundColor = _bodyBackgroundColor;
@synthesize markdown = _markdown;
@synthesize renderedObject = _renderedObject;

- (instancetype)initWithColumnEdges:(NSArray *)columnEdges
                           rowCount:(NSUInteger)rowCount
                        borderWidth:(CGFloat)borderWidth
                        borderColor:(NSColor *)borderColor
              headerBackgroundColor:(NSColor *)headerBackgroundColor
                bodyBackgroundColor:(NSColor *)bodyBackgroundColor
                           markdown:(NSString *)markdown
{
    self = [super init];
    if (self != nil) {
        _columnEdges = [columnEdges copy];
        _rowCount = rowCount;
        _borderWidth = borderWidth;
        _borderColor = [borderColor retain];
        _headerBackgroundColor = [headerBackgroundColor retain];
        _bodyBackgroundColor = [bodyBackgroundColor retain];
        _markdown = [markdown copy];
    }
    return self;
}

- (void)dealloc
{
    [_columnEdges release];
    [_borderColor release];
    [_headerBackgroundColor release];
    [_bodyBackgroundColor release];
    [_markdown release];
    [_renderedObject release];
    [super dealloc];
}

@end

// The vertical extent of the line fragments holding glyphs.
static BOOL OMTextTableRowExtent(NSLayoutManager *layoutManager, NSRange glyphs, CGFloat *top, CGFloat *bottom)
{
    BOOL found = NO;
    NSUInteger glyph = glyphs.location;
    while (glyph < NSMaxRange(glyphs)) {
        NSRange fragmentGlyphs;
        NSRect fragment = [layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&fragmentGlyphs];
        if (fragmentGlyphs.length == 0) {
            break;
        }
        if (!found) {
            *top = NSMinY(fragment);
            *bottom = NSMaxY(fragment);
            found = YES;
        } else {
            *top = MIN(*top, NSMinY(fragment));
            *bottom = MAX(*bottom, NSMaxY(fragment));
        }
        glyph = NSMaxRange(fragmentGlyphs);
    }
    return found;
}

// The selection starts at a line's first glyph, which in a table is past
// the first cell's padding; fill that padding too on each line of the row
// whose first character is selected, so the selection has no gap.
static void OMFillSelectedRowPadding(NSLayoutManager *layoutManager, NSRange rowGlyphs, CGFloat left, NSPoint origin)
{
    NSTextView *textView = [layoutManager firstTextView];
    NSArray *selection = [textView selectedRanges];
    if (textView == nil || [selection count] == 0) {
        return;
    }
    NSColor *color = [[textView selectedTextAttributes] objectForKey:NSBackgroundColorAttributeName];
    if (color == nil) {
        color = [NSColor selectedTextBackgroundColor];
    }
    NSUInteger glyph = rowGlyphs.location;
    while (glyph < NSMaxRange(rowGlyphs)) {
        NSRange fragmentGlyphs;
        NSRect fragment = [layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&fragmentGlyphs];
        if (fragmentGlyphs.length == 0) {
            break;
        }
        NSUInteger character = [layoutManager characterIndexForGlyphAtIndex:fragmentGlyphs.location];
        BOOL selected = NO;
        for (NSValue *range in selection) {
            if (NSLocationInRange(character, [range rangeValue])) {
                selected = YES;
                break;
            }
        }
        CGFloat textX = origin.x + NSMinX(fragment) + [layoutManager locationForGlyphAtIndex:fragmentGlyphs.location].x;
        if (selected && textX > left) {
            // A pixel into the selection, so their edges leave no seam.
            [color set];
            NSRectFill(NSMakeRect(left, origin.y + NSMinY(fragment), ceil(textX) + 1.0 - left, NSHeight(fragment)));
        }
        glyph = NSMaxRange(fragmentGlyphs);
    }
}

static void OMDrawTextTables(NSLayoutManager *layoutManager, NSRange glyphRange, NSPoint origin, BOOL fills, BOOL rules)
{
    NSTextStorage *storage = [layoutManager textStorage];
    if (storage == nil || glyphRange.length == 0) {
        return;
    }
    NSRange characters = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
    if (NSMaxRange(characters) > [storage length]) {
        return;
    }
    NSUInteger index = characters.location;
    while (index < NSMaxRange(characters)) {
        NSRange rowRange;
        OMTextTable *table = [storage attribute:OMTextTableAttributeName
                                        atIndex:index
                          longestEffectiveRange:&rowRange
                                        inRange:characters];
        NSRange tableRun = rowRange;
        index = NSMaxRange(rowRange);
        if (table == nil || [[table columnEdges] count] < 2) {
            continue;
        }
        // Each row, whole, even where it starts or ends outside the range drawn.
        NSUInteger rowIndex = tableRun.location;
        while (rowIndex < NSMaxRange(tableRun)) {
            NSRange row;
            NSNumber *number = [storage attribute:OMTextTableRowAttributeName
                                          atIndex:rowIndex
                            longestEffectiveRange:&row
                                          inRange:NSMakeRange(0, [storage length])];
            rowIndex = MAX(rowIndex + 1, MIN(NSMaxRange(row), NSMaxRange(tableRun)));
            if (number == nil) {
                continue;
            }
            NSRange rowGlyphs = [layoutManager glyphRangeForCharacterRange:row actualCharacterRange:NULL];
            CGFloat top = 0.0;
            CGFloat bottom = 0.0;
            if (!OMTextTableRowExtent(layoutManager, rowGlyphs, &top, &bottom)) {
                continue;
            }
            NSArray *edges = [table columnEdges];
            CGFloat border = [table borderWidth];
            CGFloat left = origin.x + [[edges objectAtIndex:0] doubleValue];
            CGFloat right = origin.x + [[edges lastObject] doubleValue] + border;
            CGFloat minY = origin.y + top;
            CGFloat maxY = origin.y + bottom;
            NSUInteger rowNumber = [number unsignedIntegerValue];
            BOOL lastRow = (rowNumber + 1 >= [table rowCount]);

            [NSGraphicsContext saveGraphicsState];
            NSColor *fill = (rowNumber == 0 ? [table headerBackgroundColor] : [table bodyBackgroundColor]);
            if (fills && fill != nil) {
                [fill set];
                NSRectFill(NSMakeRect(left, minY, right - left, maxY - minY));
            }
            if (fills) {
                OMFillSelectedRowPadding(layoutManager, rowGlyphs, left, origin);
            }
            if (rules) {
                [[table borderColor] set];
                // The rule above each row, the one below the last, and the column edges.
                NSRectFill(NSMakeRect(left, minY, right - left, border));
                if (lastRow) {
                    NSRectFill(NSMakeRect(left, maxY - border, right - left, border));
                }
                for (NSNumber *edge in edges) {
                    NSRectFill(NSMakeRect(origin.x + [edge doubleValue], minY, border, maxY - minY));
                }
            }
            [NSGraphicsContext restoreGraphicsState];
        }
    }
}

void OMDrawTextTablesForGlyphRange(NSLayoutManager *layoutManager, NSRange glyphRange, NSPoint origin)
{
    OMDrawTextTables(layoutManager, glyphRange, origin, YES, YES);
}

void OMDrawTextTableBackgroundsForGlyphRange(NSLayoutManager *layoutManager, NSRange glyphRange, NSPoint origin)
{
    OMDrawTextTables(layoutManager, glyphRange, origin, YES, NO);
}

void OMDrawTextTableRulesForGlyphRange(NSLayoutManager *layoutManager, NSRange glyphRange, NSPoint origin)
{
    OMDrawTextTables(layoutManager, glyphRange, origin, NO, YES);
}
