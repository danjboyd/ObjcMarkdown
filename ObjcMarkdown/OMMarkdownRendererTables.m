// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Pipe tables: laid out as text, or drawn as an attachment when allowed to overflow.

#import "OMMarkdownRendererInternal.h"

typedef NS_ENUM(NSUInteger, OMPipeTableAlignment) {
    OMPipeTableAlignmentLeft = 0,
    OMPipeTableAlignmentCenter = 1,
    OMPipeTableAlignmentRight = 2
};

NSString *OMTrimmedCellText(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static CGFloat OMPipeTableHorizontalPadding(CGFloat scale)
{
    CGFloat padding = 10.0 * scale;
    if (padding < 6.0) {
        padding = 6.0;
    }
    return padding;
}

static BOOL OMPipeTableNeedsStackedFallback(NSArray *columnWidths,
                                            CGFloat layoutWidth,
                                            CGFloat indent,
                                            NSFont *tableFont,
                                            CGFloat cellHorizontalPadding,
                                            CGFloat scale)
{
    if (columnWidths == nil || [columnWidths count] == 0) {
        return NO;
    }
    if (layoutWidth <= 0.0) {
        return NO;
    }

    CGFloat availableWidth = layoutWidth - indent - (16.0 * scale);
    if (availableWidth <= 0.0) {
        return YES;
    }
    CGFloat minimumColumnTextWidth = 44.0 * scale;
    if (minimumColumnTextWidth < 28.0) {
        minimumColumnTextWidth = 28.0;
    }
    CGFloat minimumGridWidth = ((CGFloat)[columnWidths count] *
                                (minimumColumnTextWidth + (cellHorizontalPadding * 2.0))) +
                               (2.0 * scale);
    if (availableWidth < minimumGridWidth) {
        return YES;
    }
    return NO;
}

static CGFloat OMPipeTableTextWidth(NSString *text, NSFont *font)
{
    if (text == nil || [text length] == 0) {
        return 0.0;
    }
    if (font == nil) {
        return (CGFloat)[text length] * 7.0;
    }
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    NSSize size = [text sizeWithAttributes:attrs];
    return size.width;
}

static NSUInteger OMPipeTableWidthUnitsForText(NSString *text,
                                               NSFont *font,
                                               CGFloat spaceWidth)
{
    CGFloat width = OMPipeTableTextWidth(text, font);
    if (width <= 0.0) {
        return 0;
    }
    if (spaceWidth <= 0.0) {
        spaceWidth = 4.0;
    }
    return (NSUInteger)ceil(width / spaceWidth);
}

static NSString *OMPipeTableColumnLabel(NSArray *headers, NSUInteger columnIndex)
{
    if (headers != nil && columnIndex < [headers count]) {
        NSString *header = OMTrimmedCellText([headers objectAtIndex:columnIndex]);
        if ([header length] > 0) {
            return header;
        }
    }
    return [NSString stringWithFormat:@"Column %lu", (unsigned long)(columnIndex + 1)];
}

static NSString *OMPipeTableStackedText(NSArray *rows)
{
    if (rows == nil || [rows count] == 0) {
        return @"";
    }

    NSArray *headers = [rows objectAtIndex:0];
    NSUInteger columnCount = [headers count];
    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger rowIndex = 1;
    for (; rowIndex < [rows count]; rowIndex++) {
        NSArray *row = [rows objectAtIndex:rowIndex];
        [lines addObject:[NSString stringWithFormat:@"Row %lu", (unsigned long)rowIndex]];
        NSUInteger columnIndex = 0;
        for (; columnIndex < columnCount; columnIndex++) {
            NSString *label = OMPipeTableColumnLabel(headers, columnIndex);
            NSString *value = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : @"");
            [lines addObject:[NSString stringWithFormat:@"  %@: %@", label, value]];
        }
        if (rowIndex + 1 < [rows count]) {
            [lines addObject:@""];
        }
    }

    if ([lines count] == 0) {
        [lines addObject:[headers componentsJoinedByString:@" | "]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *OMPipeTableVisibleCellText(NSString *cellMarkdown)
{
    NSString *normalized = (cellMarkdown != nil ? cellMarkdown : @"");
    if ([normalized length] == 0) {
        return @"";
    }

    NSData *data = [normalized dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return OMTrimmedCellText(normalized);
    }

    const char *bytes = (const char *)[data bytes];
    NSUInteger length = [data length];
    cmark_node *document = OMGFMParseDocument(bytes, length, (int)CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return OMTrimmedCellText(normalized);
    }

    NSMutableArray *parts = [NSMutableArray array];
    cmark_node *child = cmark_node_first_child(document);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        if (type == CMARK_NODE_PARAGRAPH) {
            NSString *plain = OMInlinePlainText(child);
            if (plain != nil && [plain length] > 0) {
                [parts addObject:plain];
            }
        }
        child = cmark_node_next(child);
    }
    cmark_node_free(document);

    if ([parts count] == 0) {
        return OMTrimmedCellText(normalized);
    }
    return [[parts componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray *OMPipeTableVisibleRows(NSArray *rows)
{
    if (rows == nil || [rows count] == 0) {
        return [NSArray array];
    }

    NSMutableArray *visibleRows = [NSMutableArray arrayWithCapacity:[rows count]];
    for (NSArray *row in rows) {
        NSMutableArray *visibleCells = [NSMutableArray arrayWithCapacity:[row count]];
        for (NSString *cell in row) {
            NSString *plain = OMPipeTableVisibleCellText(cell);
            [visibleCells addObject:(plain != nil ? plain : @"")];
        }
        [visibleRows addObject:visibleCells];
    }
    return visibleRows;
}

static BOOL OMThemeBackgroundIsDark(OMTheme *theme)
{
    if (theme == nil || theme.baseBackgroundColor == nil) {
        return NO;
    }
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!OMColorRGBA(theme.baseBackgroundColor, &red, &green, &blue, NULL)) {
        return NO;
    }
    CGFloat luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
    return luminance < 0.5;
}

NSColor *OMPipeTableBorderColorForTheme(OMTheme *theme)
{
    if (OMThemeBackgroundIsDark(theme)) {
        return [NSColor colorWithCalibratedRed:(61.0 / 255.0)
                                         green:(68.0 / 255.0)
                                          blue:(77.0 / 255.0)
                                         alpha:1.0];
    }
    return [NSColor colorWithCalibratedRed:(208.0 / 255.0)
                                     green:(215.0 / 255.0)
                                      blue:(222.0 / 255.0)
                                     alpha:1.0];
}

NSColor *OMPipeTableHeaderBackgroundColorForTheme(OMTheme *theme)
{
    if (OMThemeBackgroundIsDark(theme)) {
        return [NSColor colorWithCalibratedRed:(22.0 / 255.0)
                                         green:(27.0 / 255.0)
                                          blue:(34.0 / 255.0)
                                         alpha:1.0];
    }
    return [NSColor colorWithCalibratedRed:(246.0 / 255.0)
                                     green:(248.0 / 255.0)
                                      blue:(250.0 / 255.0)
                                     alpha:1.0];
}

NSColor *OMPipeTableBodyBackgroundColorForTheme(OMTheme *theme)
{
    if (OMThemeBackgroundIsDark(theme)) {
        return [NSColor colorWithCalibratedRed:(13.0 / 255.0)
                                         green:(17.0 / 255.0)
                                          blue:(23.0 / 255.0)
                                         alpha:1.0];
    }
    if (theme != nil && theme.baseBackgroundColor != nil) {
        return theme.baseBackgroundColor;
    }
    return [NSColor whiteColor];
}

static NSMutableAttributedString *OMPipeTableAttributedCellContent(NSString *cellMarkdown,
                                                                   OMTheme *theme,
                                                                   NSDictionary *cellAttributes,
                                                                   CGFloat scale,
                                                                   const OMRenderContext *renderContext)
{
    NSString *normalized = (cellMarkdown != nil ? cellMarkdown : @"");
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    if ([normalized length] == 0) {
        return result;
    }

    NSData *data = [normalized dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        OMAppendString(result, normalized, cellAttributes);
        return result;
    }

    const char *bytes = (const char *)[data bytes];
    NSUInteger length = [data length];
    NSUInteger cmarkOptions = (renderContext != NULL && renderContext->parsingOptions != nil)
                              ? [renderContext->parsingOptions cmarkOptions]
                              : (NSUInteger)CMARK_OPT_DEFAULT;
    cmark_node *document = OMGFMParseDocument(bytes, length, (int)cmarkOptions);
    if (document == NULL) {
        OMAppendString(result, normalized, cellAttributes);
        return result;
    }

    NSMutableDictionary *inlineAttributes = [NSMutableDictionary dictionaryWithDictionary:cellAttributes];
    BOOL rendered = NO;
    cmark_node *child = cmark_node_first_child(document);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        if (type == CMARK_NODE_PARAGRAPH) {
            OMRenderInlines(child, theme, result, inlineAttributes, scale, renderContext);
            rendered = YES;
        }
        child = cmark_node_next(child);
    }
    if (!rendered) {
        OMAppendString(result, normalized, cellAttributes);
    }
    cmark_node_free(document);
    return result;
}

static NSFont *OMPipeTableGridFont(NSFont *fallbackFont, CGFloat size)
{
    CGFloat resolvedSize = size;
    if (resolvedSize <= 0.0 && fallbackFont != nil) {
        resolvedSize = [fallbackFont pointSize];
    }
    if (resolvedSize <= 0.0) {
        resolvedSize = 14.0;
    }

    if (fallbackFont != nil) {
        NSFont *resized = [NSFont fontWithName:[fallbackFont fontName] size:resolvedSize];
        if (resized != nil) {
            return resized;
        }
    }

    NSArray *fallbackNames = [NSArray arrayWithObjects:
                              @"Helvetica Neue",
                              @"Helvetica",
                              @"Arial",
                              @"Liberation Sans",
                              @"DejaVu Sans",
                              @"Sans",
                              nil];
    for (NSString *fontName in fallbackNames) {
        NSFont *candidate = [NSFont fontWithName:fontName size:resolvedSize];
        if (candidate != nil) {
            return candidate;
        }
    }
    return [NSFont systemFontOfSize:resolvedSize];
}

static void OMPipeTableNormalizeCellSegment(NSMutableAttributedString *segment)
{
    if (segment == nil || [segment length] == 0) {
        return;
    }

    NSInteger index = (NSInteger)[segment length] - 1;
    for (; index >= 0; index--) {
        unichar ch = [[segment string] characterAtIndex:(NSUInteger)index];
        if (ch == '\n' || ch == '\r' || ch == '\t') {
            [segment replaceCharactersInRange:NSMakeRange((NSUInteger)index, 1) withString:@" "];
        }
    }
}

static NSTextAlignment OMPipeTableTextAlignment(OMPipeTableAlignment alignment)
{
    switch (alignment) {
        case OMPipeTableAlignmentCenter:
            return NSCenterTextAlignment;
        case OMPipeTableAlignmentRight:
            return NSRightTextAlignment;
        case OMPipeTableAlignmentLeft:
        default:
            return NSLeftTextAlignment;
    }
}

static NSMutableArray *OMPipeTableColumnWidthsInPoints(NSArray *visibleRows,
                                                       NSUInteger columnCount,
                                                       NSFont *tableFont,
                                                       NSFont *headerFont,
                                                       CGFloat scale)
{
    NSMutableArray *widths = [NSMutableArray arrayWithCapacity:columnCount];
    CGFloat minimumWidth = 44.0 * scale;
    if (minimumWidth < 28.0) {
        minimumWidth = 28.0;
    }
    NSUInteger columnIndex = 0;
    for (; columnIndex < columnCount; columnIndex++) {
        [widths addObject:[NSNumber numberWithDouble:minimumWidth]];
    }

    NSUInteger rowIndex = 0;
    for (; rowIndex < [visibleRows count]; rowIndex++) {
        NSArray *row = [visibleRows objectAtIndex:rowIndex];
        NSFont *rowFont = (rowIndex == 0 && headerFont != nil) ? headerFont : tableFont;
        NSDictionary *measureAttrs = nil;
        if (rowFont != nil) {
            measureAttrs = [NSDictionary dictionaryWithObject:rowFont forKey:NSFontAttributeName];
        }

        columnIndex = 0;
        for (; columnIndex < columnCount; columnIndex++) {
            NSString *text = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : @"");
            if (text == nil) {
                text = @"";
            }
            NSSize textSize = [text sizeWithAttributes:measureAttrs];
            CGFloat measured = ceil(textSize.width);
            if (measured < minimumWidth) {
                measured = minimumWidth;
            }
            CGFloat existing = [[widths objectAtIndex:columnIndex] doubleValue];
            if (measured > existing) {
                [widths replaceObjectAtIndex:columnIndex
                                  withObject:[NSNumber numberWithDouble:measured]];
            }
        }
    }
    return widths;
}

static NSMutableArray *OMPipeTableAttributedColumnWidthsInPoints(NSArray *attributedRows,
                                                                 NSUInteger columnCount,
                                                                 CGFloat scale)
{
    NSMutableArray *widths = [NSMutableArray arrayWithCapacity:columnCount];
    CGFloat minimumWidth = 44.0 * scale;
    if (minimumWidth < 28.0) {
        minimumWidth = 28.0;
    }
    NSUInteger columnIndex = 0;
    for (; columnIndex < columnCount; columnIndex++) {
        [widths addObject:[NSNumber numberWithDouble:minimumWidth]];
    }

    NSUInteger rowIndex = 0;
    for (; rowIndex < [attributedRows count]; rowIndex++) {
        NSArray *row = [attributedRows objectAtIndex:rowIndex];
        columnIndex = 0;
        for (; columnIndex < columnCount; columnIndex++) {
            NSAttributedString *segment = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : nil);
            CGFloat measured = 0.0;
            if (segment != nil && [segment length] > 0) {
                NSSize textSize = [segment size];
                // Small guard band prevents edge clipping from font metric rounding.
                measured = ceil(textSize.width + (1.0 * scale));
            }
            if (measured < minimumWidth) {
                measured = minimumWidth;
            }
            CGFloat existing = [[widths objectAtIndex:columnIndex] doubleValue];
            if (measured > existing) {
                [widths replaceObjectAtIndex:columnIndex
                                  withObject:[NSNumber numberWithDouble:measured]];
            }
        }
    }
    return widths;
}

static void OMPipeTableConstrainColumnWidths(NSMutableArray *columnWidths,
                                             CGFloat maxContentWidth,
                                             CGFloat minimumColumnWidth)
{
    if (columnWidths == nil || [columnWidths count] == 0 || maxContentWidth <= 0.0) {
        return;
    }
    if (minimumColumnWidth < 24.0) {
        minimumColumnWidth = 24.0;
    }

    CGFloat total = 0.0;
    for (NSNumber *value in columnWidths) {
        total += [value doubleValue];
    }
    if (total <= maxContentWidth) {
        return;
    }

    while (total > maxContentWidth) {
        NSUInteger widestIndex = NSNotFound;
        CGFloat widestWidth = 0.0;
        NSUInteger index = 0;
        for (; index < [columnWidths count]; index++) {
            CGFloat width = [[columnWidths objectAtIndex:index] doubleValue];
            if (width > minimumColumnWidth && width > widestWidth) {
                widestWidth = width;
                widestIndex = index;
            }
        }
        if (widestIndex == NSNotFound) {
            break;
        }
        CGFloat reduced = widestWidth - 1.0;
        if (reduced < minimumColumnWidth) {
            reduced = minimumColumnWidth;
        }
        [columnWidths replaceObjectAtIndex:widestIndex
                                withObject:[NSNumber numberWithDouble:reduced]];
        total -= (widestWidth - reduced);
        if ((widestWidth - reduced) <= 0.0) {
            break;
        }
    }
}

static NSMutableAttributedString *OMPipeTableDrawableSegment(NSAttributedString *segment,
                                                             OMPipeTableAlignment alignment,
                                                             NSLineBreakMode lineBreakMode)
{
    if (segment == nil) {
        return nil;
    }

    NSMutableAttributedString *drawSegment = [[segment mutableCopy] autorelease];
    if ([drawSegment length] == 0) {
        return drawSegment;
    }

    NSMutableParagraphStyle *drawStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [drawStyle setAlignment:OMPipeTableTextAlignment(alignment)];
    [drawStyle setLineBreakMode:lineBreakMode];
    [drawSegment addAttribute:NSParagraphStyleAttributeName
                        value:drawStyle
                        range:NSMakeRange(0, [drawSegment length])];
    return drawSegment;
}

static CGFloat OMPipeTableMeasuredTextHeight(NSAttributedString *segment,
                                             CGFloat width,
                                             CGFloat fallbackLineHeight)
{
    if (segment == nil || [segment length] == 0 || width <= 0.0) {
        return fallbackLineHeight;
    }

    NSTextStorage *storage = [[[NSTextStorage alloc] initWithAttributedString:segment] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, FLT_MAX)] autorelease];
    [container setLineFragmentPadding:0.0];
    [layoutManager addTextContainer:container];
    [storage addLayoutManager:layoutManager];
    [layoutManager ensureLayoutForTextContainer:container];

    NSRect usedRect = [layoutManager usedRectForTextContainer:container];
    CGFloat height = ceil(usedRect.size.height);
    if (height < fallbackLineHeight) {
        height = fallbackLineHeight;
    }
    return height;
}

static CGFloat OMPipeTableRoundToPixel(CGFloat value)
{
    return floor(value + 0.5);
}

static NSRect OMPipeTableIntegralRect(NSRect rect)
{
    CGFloat minX = floor(rect.origin.x);
    CGFloat minY = floor(rect.origin.y);
    CGFloat maxX = ceil(rect.origin.x + rect.size.width);
    CGFloat maxY = ceil(rect.origin.y + rect.size.height);
    return NSMakeRect(minX, minY, maxX - minX, maxY - minY);
}

static BOOL OMPipeTableComputeLayout(NSArray *visibleRows,
                                     NSArray *attributedRows,
                                     NSUInteger rowCount,
                                     NSUInteger columnCount,
                                     NSFont *tableFont,
                                     NSFont *headerFont,
                                     CGFloat scale,
                                     CGFloat maxWidth,
                                     NSMutableArray **columnWidthsOut,
                                     NSMutableArray **rowHeightsOut,
                                     CGFloat *borderWidthOut,
                                     CGFloat *horizontalPaddingOut,
                                     CGFloat *verticalPaddingOut,
                                     CGFloat *totalWidthOut,
                                     CGFloat *totalHeightOut)
{
    if (visibleRows == nil || rowCount == 0 || columnCount == 0) {
        return NO;
    }

    CGFloat borderWidth = (scale >= 1.0 ? 1.0 : scale);
    if (borderWidth < 1.0) {
        borderWidth = 1.0;
    }
    CGFloat horizontalPadding = OMPipeTableRoundToPixel(12.0 * scale);
    if (horizontalPadding < 8.0) {
        horizontalPadding = 8.0;
    }
    CGFloat verticalPadding = OMPipeTableRoundToPixel(6.0 * scale);
    if (verticalPadding < 4.0) {
        verticalPadding = 4.0;
    }

    NSMutableArray *columnWidths = nil;
    if (attributedRows != nil && [attributedRows count] == rowCount) {
        columnWidths = OMPipeTableAttributedColumnWidthsInPoints(attributedRows,
                                                                 columnCount,
                                                                 scale);
    } else {
        columnWidths = OMPipeTableColumnWidthsInPoints(visibleRows,
                                                       columnCount,
                                                       tableFont,
                                                       headerFont,
                                                       scale);
    }
    CGFloat chromeWidth = ((CGFloat)columnCount * (horizontalPadding * 2.0)) +
                          ((CGFloat)(columnCount + 1) * borderWidth);
    if (maxWidth > 0.0) {
        CGFloat maxContentWidth = maxWidth - chromeWidth;
        OMPipeTableConstrainColumnWidths(columnWidths, maxContentWidth, 44.0 * scale);
    }

    CGFloat bodyLineHeight = tableFont != nil
                             ? ceil([tableFont ascender] - [tableFont descender] + [tableFont leading])
                             : ceil(16.0 * scale);
    if (bodyLineHeight < (12.0 * scale)) {
        bodyLineHeight = 12.0 * scale;
    }
    CGFloat headerLineHeight = headerFont != nil
                               ? ceil([headerFont ascender] - [headerFont descender] + [headerFont leading])
                               : bodyLineHeight;
    if (headerLineHeight < bodyLineHeight) {
        headerLineHeight = bodyLineHeight;
    }

    NSMutableArray *rowHeights = [NSMutableArray arrayWithCapacity:rowCount];
    NSUInteger rowIndex = 0;
    for (; rowIndex < rowCount; rowIndex++) {
        CGFloat lineHeight = (rowIndex == 0 ? headerLineHeight : bodyLineHeight);
        CGFloat contentHeight = lineHeight;
        if (attributedRows != nil && [attributedRows count] == rowCount) {
            NSArray *row = [attributedRows objectAtIndex:rowIndex];
            NSUInteger columnIndex = 0;
            for (; columnIndex < columnCount; columnIndex++) {
                NSAttributedString *segment = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : nil);
                OMPipeTableAlignment alignment = OMPipeTableAlignmentLeft;
                NSMutableAttributedString *measureSegment = OMPipeTableDrawableSegment(segment,
                                                                                       alignment,
                                                                                       NSLineBreakByWordWrapping);
                CGFloat contentWidth = [[columnWidths objectAtIndex:columnIndex] doubleValue];
                CGFloat measured = OMPipeTableMeasuredTextHeight(measureSegment,
                                                                 contentWidth,
                                                                 lineHeight);
                if (measured > contentHeight) {
                    contentHeight = measured;
                }
            }
        }
        CGFloat rowHeight = ceil(contentHeight + (verticalPadding * 2.0));
        [rowHeights addObject:[NSNumber numberWithDouble:rowHeight]];
    }

    CGFloat totalContentWidth = 0.0;
    for (NSNumber *value in columnWidths) {
        totalContentWidth += [value doubleValue];
    }
    CGFloat totalWidth = ceil(totalContentWidth + chromeWidth);

    CGFloat totalRowsHeight = 0.0;
    for (NSNumber *value in rowHeights) {
        totalRowsHeight += [value doubleValue];
    }
    CGFloat totalHeight = ceil(totalRowsHeight + ((CGFloat)(rowCount + 1) * borderWidth));

    if (totalWidth <= 0.0 || totalHeight <= 0.0) {
        return NO;
    }

    if (columnWidthsOut != NULL) {
        *columnWidthsOut = columnWidths;
    }
    if (rowHeightsOut != NULL) {
        *rowHeightsOut = rowHeights;
    }
    if (borderWidthOut != NULL) {
        *borderWidthOut = borderWidth;
    }
    if (horizontalPaddingOut != NULL) {
        *horizontalPaddingOut = horizontalPadding;
    }
    if (verticalPaddingOut != NULL) {
        *verticalPaddingOut = verticalPadding;
    }
    if (totalWidthOut != NULL) {
        *totalWidthOut = totalWidth;
    }
    if (totalHeightOut != NULL) {
        *totalHeightOut = totalHeight;
    }
    return YES;
}

static NSImage *OMPipeTableImageFromRows(NSArray *attributedRows,
                                         NSArray *visibleRows,
                                         NSArray *alignments,
                                         NSFont *tableFont,
                                         NSFont *headerFont,
                                         NSColor *borderColor,
                                         NSColor *headerBackgroundColor,
                                         NSColor *bodyBackgroundColor,
                                         CGFloat scale,
                                         CGFloat maxWidth)
{
    if (attributedRows == nil || [attributedRows count] == 0 ||
        alignments == nil || [alignments count] == 0) {
        return nil;
    }

    NSUInteger rowCount = [attributedRows count];
    NSUInteger columnCount = [alignments count];

    NSMutableArray *columnWidths = nil;
    NSMutableArray *rowHeights = nil;
    CGFloat borderWidth = 0.0;
    CGFloat horizontalPadding = 0.0;
    CGFloat verticalPadding = 0.0;
    CGFloat totalWidth = 0.0;
    CGFloat totalHeight = 0.0;
    if (!OMPipeTableComputeLayout(visibleRows,
                                  attributedRows,
                                  rowCount,
                                  columnCount,
                                  tableFont,
                                  headerFont,
                                  scale,
                                  maxWidth,
                                  &columnWidths,
                                  &rowHeights,
                                  &borderWidth,
                                  &horizontalPadding,
                                  &verticalPadding,
                                  &totalWidth,
                                  &totalHeight)) {
        return nil;
    }

    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(totalWidth, totalHeight)] autorelease];
    [image lockFocus];

    NSColor *resolvedBorderColor = (borderColor != nil ? borderColor : [NSColor lightGrayColor]);
    [resolvedBorderColor setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, totalWidth, totalHeight));

    CGFloat y = totalHeight - borderWidth;
    NSUInteger rowIndex = 0;
    for (; rowIndex < rowCount; rowIndex++) {
        CGFloat rowHeight = [[rowHeights objectAtIndex:rowIndex] doubleValue];
        y -= rowHeight;

        NSColor *rowBackground = (rowIndex == 0 ? headerBackgroundColor : bodyBackgroundColor);
        if (rowBackground == nil) {
            rowBackground = [NSColor whiteColor];
        }

        CGFloat x = borderWidth;
        NSUInteger colIndex = 0;
        for (; colIndex < columnCount; colIndex++) {
            CGFloat contentWidth = [[columnWidths objectAtIndex:colIndex] doubleValue];
            CGFloat cellWidth = contentWidth + (horizontalPadding * 2.0);
            NSRect cellRect = NSMakeRect(x, y, cellWidth, rowHeight);
            [rowBackground setFill];
            NSRectFill(cellRect);

            NSArray *rowSegments = [attributedRows objectAtIndex:rowIndex];
            NSAttributedString *segment = (colIndex < [rowSegments count] ? [rowSegments objectAtIndex:colIndex] : nil);
            if (segment != nil && [segment length] > 0) {
                OMPipeTableAlignment alignment = (OMPipeTableAlignment)[[alignments objectAtIndex:colIndex] unsignedIntegerValue];
                NSMutableAttributedString *drawSegment = OMPipeTableDrawableSegment(segment,
                                                                                    alignment,
                                                                                    NSLineBreakByWordWrapping);

                NSRect textRect = NSInsetRect(cellRect, horizontalPadding, verticalPadding);
                [drawSegment drawInRect:textRect];
                OMDrawStrikethroughForAttributedString(drawSegment, textRect, NO);
            }

            x += cellWidth + borderWidth;
        }

        y -= borderWidth;
    }

    [image unlockFocus];
    return image;
}

@interface OMPipeTableAttachmentCell : NSTextAttachmentCell
{
    NSArray *_attributedRows;
    NSArray *_alignments;
    NSArray *_columnWidths;
    NSArray *_rowHeights;
    NSColor *_borderColor;
    NSColor *_headerBackgroundColor;
    NSColor *_bodyBackgroundColor;
    CGFloat _borderWidth;
    CGFloat _horizontalPadding;
    CGFloat _verticalPadding;
    NSSize _tableSize;
}
- (instancetype)initWithAttributedRows:(NSArray *)attributedRows
                            alignments:(NSArray *)alignments
                          columnWidths:(NSArray *)columnWidths
                            rowHeights:(NSArray *)rowHeights
                           borderColor:(NSColor *)borderColor
                 headerBackgroundColor:(NSColor *)headerBackgroundColor
                   bodyBackgroundColor:(NSColor *)bodyBackgroundColor
                           borderWidth:(CGFloat)borderWidth
                     horizontalPadding:(CGFloat)horizontalPadding
                       verticalPadding:(CGFloat)verticalPadding
                             tableSize:(NSSize)tableSize;
@end

@implementation OMPipeTableAttachmentCell

- (instancetype)initWithAttributedRows:(NSArray *)attributedRows
                            alignments:(NSArray *)alignments
                          columnWidths:(NSArray *)columnWidths
                            rowHeights:(NSArray *)rowHeights
                           borderColor:(NSColor *)borderColor
                 headerBackgroundColor:(NSColor *)headerBackgroundColor
                   bodyBackgroundColor:(NSColor *)bodyBackgroundColor
                           borderWidth:(CGFloat)borderWidth
                     horizontalPadding:(CGFloat)horizontalPadding
                       verticalPadding:(CGFloat)verticalPadding
                             tableSize:(NSSize)tableSize
{
    self = [super init];
    if (self != nil) {
        _attributedRows = [attributedRows copy];
        _alignments = [alignments copy];
        _columnWidths = [columnWidths copy];
        _rowHeights = [rowHeights copy];
        _borderColor = [(borderColor != nil ? borderColor : [NSColor lightGrayColor]) retain];
        _headerBackgroundColor = [(headerBackgroundColor != nil ? headerBackgroundColor : [NSColor whiteColor]) retain];
        _bodyBackgroundColor = [(bodyBackgroundColor != nil ? bodyBackgroundColor : [NSColor whiteColor]) retain];
        _borderWidth = borderWidth;
        _horizontalPadding = horizontalPadding;
        _verticalPadding = verticalPadding;
        _tableSize = tableSize;
    }
    return self;
}

- (void)dealloc
{
    [_attributedRows release];
    [_alignments release];
    [_columnWidths release];
    [_rowHeights release];
    [_borderColor release];
    [_headerBackgroundColor release];
    [_bodyBackgroundColor release];
    [super dealloc];
}

- (NSSize)cellSize
{
    return _tableSize;
}

- (void)om_drawTableInFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
    if (_attributedRows == nil || [_attributedRows count] == 0 ||
        _alignments == nil || [_alignments count] == 0 ||
        _columnWidths == nil || [_columnWidths count] == 0 ||
        _rowHeights == nil || [_rowHeights count] == 0) {
        return;
    }

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    NSRect tableRect = OMPipeTableIntegralRect(cellFrame);
    if (tableRect.size.width < _tableSize.width) {
        tableRect.size.width = _tableSize.width;
    }
    if (tableRect.size.height < _tableSize.height) {
        tableRect.size.height = _tableSize.height;
    }

    [_borderColor setFill];
    NSRectFill(tableRect);

    NSUInteger rowCount = [_attributedRows count];
    NSUInteger columnCount = [_alignments count];
    CGFloat y = flipped ? (NSMinY(tableRect) + _borderWidth) : (NSMaxY(tableRect) - _borderWidth);
    NSUInteger rowIndex = 0;
    for (; rowIndex < rowCount; rowIndex++) {
        CGFloat rowHeight = [[_rowHeights objectAtIndex:rowIndex] doubleValue];
        if (!flipped) {
            y -= rowHeight;
        }

        NSColor *rowBackground = (rowIndex == 0 ? _headerBackgroundColor : _bodyBackgroundColor);
        if (rowBackground == nil) {
            rowBackground = [NSColor whiteColor];
        }

        CGFloat x = NSMinX(tableRect) + _borderWidth;
        NSUInteger colIndex = 0;
        for (; colIndex < columnCount; colIndex++) {
            CGFloat contentWidth = [[_columnWidths objectAtIndex:colIndex] doubleValue];
            CGFloat cellWidth = contentWidth + (_horizontalPadding * 2.0);
            NSRect cellRect = OMPipeTableIntegralRect(NSMakeRect(x, y, cellWidth, rowHeight));
            [rowBackground setFill];
            NSRectFill(cellRect);

            NSArray *rowSegments = [_attributedRows objectAtIndex:rowIndex];
            NSAttributedString *segment = (colIndex < [rowSegments count] ? [rowSegments objectAtIndex:colIndex] : nil);
            if (segment != nil && [segment length] > 0) {
                OMPipeTableAlignment alignment = (OMPipeTableAlignment)[[_alignments objectAtIndex:colIndex] unsignedIntegerValue];
                NSMutableAttributedString *drawSegment = OMPipeTableDrawableSegment(segment,
                                                                                    alignment,
                                                                                    NSLineBreakByWordWrapping);

                NSRect textRect = OMPipeTableIntegralRect(NSInsetRect(cellRect,
                                                                      _horizontalPadding,
                                                                      _verticalPadding));
                [drawSegment drawInRect:textRect];
                OMDrawStrikethroughForAttributedString(drawSegment, textRect, flipped);
            }
            x += cellWidth + _borderWidth;
        }
        if (flipped) {
            y += rowHeight + _borderWidth;
        } else {
            y -= _borderWidth;
        }
    }
    [context restoreGraphicsState];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawTableInFrame:cellFrame flipped:flipped];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
{
    (void)charIndex;
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawTableInFrame:cellFrame flipped:flipped];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
        layoutManager:(NSLayoutManager *)layoutManager
{
    (void)charIndex;
    (void)layoutManager;
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawTableInFrame:cellFrame flipped:flipped];
}

@end

static NSAttributedString *OMPipeTableAttachmentAttributedString(NSArray *attributedRows,
                                                                 NSArray *visibleRows,
                                                                 NSArray *alignments,
                                                                 NSFont *tableFont,
                                                                 NSFont *headerFont,
                                                                 NSColor *borderColor,
                                                                 NSColor *headerBackgroundColor,
                                                                 NSColor *bodyBackgroundColor,
                                                                 CGFloat scale,
                                                                 CGFloat maxWidth,
                                                                 NSDictionary *attributes)
{
    if (attributedRows == nil || [attributedRows count] == 0 ||
        alignments == nil || [alignments count] == 0) {
        return nil;
    }

    NSUInteger rowCount = [attributedRows count];
    NSUInteger columnCount = [alignments count];
    NSMutableArray *columnWidths = nil;
    NSMutableArray *rowHeights = nil;
    CGFloat borderWidth = 0.0;
    CGFloat horizontalPadding = 0.0;
    CGFloat verticalPadding = 0.0;
    CGFloat totalWidth = 0.0;
    CGFloat totalHeight = 0.0;
    BOOL hasLayout = OMPipeTableComputeLayout(visibleRows,
                                              attributedRows,
                                              rowCount,
                                              columnCount,
                                              tableFont,
                                              headerFont,
                                              scale,
                                              maxWidth,
                                              &columnWidths,
                                              &rowHeights,
                                              &borderWidth,
                                              &horizontalPadding,
                                              &verticalPadding,
                                              &totalWidth,
                                              &totalHeight);
    if (!hasLayout) {
        return nil;
    }

    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    OMPipeTableAttachmentCell *cell = [[[OMPipeTableAttachmentCell alloc] initWithAttributedRows:attributedRows
                                                                                        alignments:alignments
                                                                                      columnWidths:columnWidths
                                                                                        rowHeights:rowHeights
                                                                                       borderColor:borderColor
                                                                             headerBackgroundColor:headerBackgroundColor
                                                                               bodyBackgroundColor:bodyBackgroundColor
                                                                                       borderWidth:borderWidth
                                                                                 horizontalPadding:horizontalPadding
                                                                                   verticalPadding:verticalPadding
                                                                                         tableSize:NSMakeSize(totalWidth, totalHeight)] autorelease];
    if (cell != nil) {
        [attachment setAttachmentCell:cell];
    } else {
        NSImage *tableImage = OMPipeTableImageFromRows(attributedRows,
                                                       visibleRows,
                                                       alignments,
                                                       tableFont,
                                                       headerFont,
                                                       borderColor,
                                                       headerBackgroundColor,
                                                       bodyBackgroundColor,
                                                       scale,
                                                       maxWidth);
        if (tableImage == nil) {
            return nil;
        }
        NSTextAttachmentCell *imageCell = [[[NSTextAttachmentCell alloc] initImageCell:tableImage] autorelease];
        [attachment setAttachmentCell:imageCell];
    }

    NSMutableDictionary *attachmentAttributes = [NSMutableDictionary dictionary];
    if (attributes != nil) {
        [attachmentAttributes addEntriesFromDictionary:attributes];
    }
    [attachmentAttributes setObject:attachment forKey:NSAttachmentAttributeName];

    unichar attachmentChar = NSAttachmentCharacter;
    NSString *attachmentString = [NSString stringWithCharacters:&attachmentChar length:1];
    return [[[NSAttributedString alloc] initWithString:attachmentString
                                            attributes:attachmentAttributes] autorelease];
}

static CGFloat OMTextTableSegmentWidth(NSAttributedString *segment)
{
    return [segment length] > 0 ? ceil([segment size].width) : 0.0;
}

static NSAttributedString *OMTextTableTrimTrailingSpaces(NSAttributedString *segment)
{
    NSString *text = [segment string];
    NSUInteger end = [text length];
    while (end > 0 && [text characterAtIndex:end - 1] == ' ') {
        end -= 1;
    }
    return end == [text length] ? segment : [segment attributedSubstringFromRange:NSMakeRange(0, end)];
}

// A cell's content broken into lines no wider than width: at spaces where it
// can, inside a word only when the word alone is too wide.
static NSArray *OMTextTableWrappedCellLines(NSAttributedString *cell, CGFloat width)
{
    if ([cell length] == 0 || width <= 0.0 || OMTextTableSegmentWidth(cell) <= width) {
        return [NSArray arrayWithObject:OMTextTableTrimTrailingSpaces(cell)];
    }
    NSString *text = [cell string];
    NSUInteger length = [text length];
    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger lineStart = 0;
    NSUInteger index = 0;
    CGFloat lineWidth = 0.0;
    while (index < length) {
        // One word and the spaces after it.
        NSUInteger wordEnd = index;
        while (wordEnd < length && [text characterAtIndex:wordEnd] != ' ') {
            wordEnd += 1;
        }
        NSUInteger tokenEnd = wordEnd;
        while (tokenEnd < length && [text characterAtIndex:tokenEnd] == ' ') {
            tokenEnd += 1;
        }
        CGFloat wordWidth = OMTextTableSegmentWidth([cell attributedSubstringFromRange:NSMakeRange(index, wordEnd - index)]);
        CGFloat tokenWidth = OMTextTableSegmentWidth([cell attributedSubstringFromRange:NSMakeRange(index, tokenEnd - index)]);
        if (lineWidth > 0.0 && lineWidth + wordWidth > width) {
            [lines addObject:OMTextTableTrimTrailingSpaces([cell attributedSubstringFromRange:NSMakeRange(lineStart, index - lineStart)])];
            lineStart = index;
            lineWidth = 0.0;
        }
        if (lineWidth == 0.0 && wordWidth > width) {
            // Break the word itself, as much per line as fits.
            NSUInteger cut = index;
            while (cut < wordEnd) {
                NSUInteger next = cut + 1;
                while (next < wordEnd &&
                       OMTextTableSegmentWidth([cell attributedSubstringFromRange:NSMakeRange(cut, next + 1 - cut)]) <= width) {
                    next += 1;
                }
                if (next >= wordEnd) {
                    break;
                }
                [lines addObject:[cell attributedSubstringFromRange:NSMakeRange(cut, next - cut)]];
                cut = next;
            }
            lineStart = cut;
            lineWidth = OMTextTableSegmentWidth([cell attributedSubstringFromRange:NSMakeRange(cut, tokenEnd - cut)]);
            index = tokenEnd;
            continue;
        }
        lineWidth += tokenWidth;
        index = tokenEnd;
    }
    if (lineStart < length) {
        [lines addObject:OMTextTableTrimTrailingSpaces([cell attributedSubstringFromRange:NSMakeRange(lineStart, length - lineStart)])];
    }
    return lines;
}

// Lays the table out as text: one paragraph per visual line, cells separated
// by tabs placed (left tab stops only, all GNUstep has) where each cell's
// alignment puts it, and an OMTextTable describing the grid to draw around them.
static void OMAppendTextTable(NSArray *attributedRows,
                              NSArray *alignments,
                              NSArray *columnWidths,
                              CGFloat indent,
                              CGFloat borderWidth,
                              CGFloat horizontalPadding,
                              CGFloat verticalPadding,
                              NSFont *tableFont,
                              CGFloat lineHeight,
                              NSColor *borderColor,
                              NSColor *headerBackgroundColor,
                              NSColor *bodyBackgroundColor,
                              NSString *markdown,
                              NSDictionary *tableAttrs,
                              NSMutableAttributedString *output)
{
    NSUInteger columnCount = [columnWidths count];
    NSMutableArray *edges = [NSMutableArray arrayWithCapacity:columnCount + 1];
    CGFloat x = floor(indent);
    NSUInteger column = 0;
    for (; column < columnCount; column++) {
        [edges addObject:[NSNumber numberWithDouble:x]];
        x += borderWidth + 2.0 * horizontalPadding + ceil([[columnWidths objectAtIndex:column] doubleValue]);
    }
    [edges addObject:[NSNumber numberWithDouble:x]];
    NSUInteger rowCount = [attributedRows count];
    OMTextTable *table = [[[OMTextTable alloc] initWithColumnEdges:edges
                                                          rowCount:rowCount
                                                       borderWidth:borderWidth
                                                       borderColor:borderColor
                                             headerBackgroundColor:headerBackgroundColor
                                               bodyBackgroundColor:bodyBackgroundColor
                                                          markdown:markdown] autorelease];

    // Text sits on the bottom of a line taller than its font; split that
    // extra between the row's top and bottom padding.
    CGFloat natural = tableFont != nil ? ceil([tableFont ascender] - [tableFont descender] + [tableFont leading]) : lineHeight;
    CGFloat extra = MAX(0.0, lineHeight - natural);

    NSUInteger rowIndex = 0;
    for (; rowIndex < rowCount; rowIndex++) {
        NSArray *row = [attributedRows objectAtIndex:rowIndex];
        NSMutableArray *cellLines = [NSMutableArray arrayWithCapacity:columnCount];
        NSUInteger lineCount = 1;
        for (column = 0; column < columnCount; column++) {
            NSAttributedString *cell = column < [row count] ? [row objectAtIndex:column] : nil;
            NSArray *lines = cell != nil
                ? OMTextTableWrappedCellLines(cell, ceil([[columnWidths objectAtIndex:column] doubleValue]))
                : [NSArray array];
            [cellLines addObject:lines];
            lineCount = MAX(lineCount, [lines count]);
        }
        NSUInteger rowStart = [output length];
        NSUInteger lineIndex = 0;
        for (; lineIndex < lineCount; lineIndex++) {
            NSMutableAttributedString *line = [[[NSMutableAttributedString alloc] init] autorelease];
            NSMutableArray *tabStops = [NSMutableArray array];
            CGFloat firstX = 0.0;
            for (column = 0; column < columnCount; column++) {
                NSArray *lines = [cellLines objectAtIndex:column];
                NSAttributedString *segment = lineIndex < [lines count] ? [lines objectAtIndex:lineIndex] : nil;
                CGFloat contentX = [[edges objectAtIndex:column] doubleValue] + borderWidth + horizontalPadding;
                CGFloat contentWidth = ceil([[columnWidths objectAtIndex:column] doubleValue]);
                CGFloat segmentWidth = OMTextTableSegmentWidth(segment);
                CGFloat segmentX = contentX;
                OMPipeTableAlignment alignment = column < [alignments count]
                    ? (OMPipeTableAlignment)[[alignments objectAtIndex:column] unsignedIntegerValue]
                    : OMPipeTableAlignmentLeft;
                if (alignment == OMPipeTableAlignmentCenter) {
                    segmentX = contentX + floor(MAX(0.0, contentWidth - segmentWidth) / 2.0);
                } else if (alignment == OMPipeTableAlignmentRight) {
                    segmentX = contentX + MAX(0.0, contentWidth - segmentWidth);
                }
                if (column == 0) {
                    firstX = segmentX;
                } else {
                    OMAppendString(line, @"\t", tableAttrs);
                    NSTextTab *tab = [[[NSTextTab alloc] initWithType:NSLeftTabStopType location:segmentX] autorelease];
                    [tabStops addObject:tab];
                }
                if (segment != nil) {
                    [line appendAttributedString:segment];
                }
            }
            if ([line length] == 0) {
                OMAppendString(line, @" ", tableAttrs);
            }
            OMAppendString(line, @"\n", tableAttrs);

            NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
            [style setFirstLineHeadIndent:firstX];
            [style setHeadIndent:firstX];
            [style setTabStops:tabStops];
            CGFloat minimum = lineHeight;
            if (lineIndex == 0) {
                minimum += borderWidth + verticalPadding - floor(extra / 2.0);
            }
            [style setMinimumLineHeight:minimum];
            if (lineIndex + 1 == lineCount) {
                [style setLineSpacing:verticalPadding + floor(extra / 2.0) +
                                      (rowIndex + 1 == rowCount ? borderWidth : 0.0)];
            }
            [line addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [line length])];
            [output appendAttributedString:line];
        }
        NSRange rowRange = NSMakeRange(rowStart, [output length] - rowStart);
        [output addAttribute:OMTextTableRowAttributeName value:[NSNumber numberWithUnsignedInteger:rowIndex] range:rowRange];
        [output addAttribute:OMTextTableAttributeName value:table range:rowRange];
    }
}

static void OMRenderPipeTable(NSArray *rows,
                              NSArray *alignments,
                              OMTheme *theme,
                              NSMutableAttributedString *output,
                              NSMutableDictionary *attributes,
                              NSMutableArray *listStack,
                              NSUInteger quoteLevel,
                              CGFloat scale,
                              CGFloat layoutWidth,
                              NSString *tableMarkdown,
                              NSArray *cellNodes,
                              const OMRenderContext *renderContext)
{
    if (rows == nil || [rows count] == 0 || alignments == nil || [alignments count] == 0) {
        return;
    }

    NSUInteger columnCount = [alignments count];
    NSArray *visibleRows = OMPipeTableVisibleRows(rows);

    NSMutableDictionary *tableAttrs = [attributes mutableCopy];
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    CGFloat tableFontSize = fontSize;
    if (tableFontSize < 12.0 * scale) {
        tableFontSize = 12.0 * scale;
    }
    NSFont *tableFont = font;
    if (tableFont == nil && theme.baseFont != nil) {
        tableFont = [NSFont fontWithName:[theme.baseFont fontName]
                                    size:[theme.baseFont pointSize] * scale];
    }
    if (tableFont == nil) {
        tableFont = [NSFont systemFontOfSize:tableFontSize];
    }
    tableFont = OMPipeTableGridFont(tableFont, tableFontSize);
    if (tableFont != nil) {
        tableFontSize = [tableFont pointSize];
        [tableAttrs setObject:tableFont forKey:NSFontAttributeName];
    }

    CGFloat spaceWidth = OMPipeTableTextWidth(@" ", tableFont);
    if (spaceWidth <= 0.0) {
        spaceWidth = 4.0;
    }
    NSFont *headerFont = tableFont != nil ? OMFontWithTraits(tableFont, NSBoldFontMask) : nil;
    if (headerFont == nil && tableFont != nil) {
        headerFont = [NSFont boldSystemFontOfSize:[tableFont pointSize]];
    }

    NSMutableArray *columnWidths = [NSMutableArray arrayWithCapacity:columnCount];
    NSUInteger colIndex = 0;
    for (; colIndex < columnCount; colIndex++) {
        [columnWidths addObject:[NSNumber numberWithUnsignedInteger:1]];
    }

    NSUInteger rowIndexForWidths = 0;
    for (; rowIndexForWidths < [visibleRows count]; rowIndexForWidths++) {
        NSArray *row = [visibleRows objectAtIndex:rowIndexForWidths];
        NSFont *rowFont = (rowIndexForWidths == 0 && headerFont != nil) ? headerFont : tableFont;
        NSUInteger column = 0;
        for (; column < columnCount; column++) {
            NSString *cell = (column < [row count] ? [row objectAtIndex:column] : @"");
            NSUInteger widthUnits = OMPipeTableWidthUnitsForText(cell, rowFont, spaceWidth);
            if (widthUnits < 1) {
                widthUnits = 1;
            }
            NSUInteger existing = [[columnWidths objectAtIndex:column] unsignedIntegerValue];
            if (widthUnits > existing) {
                [columnWidths replaceObjectAtIndex:column withObject:[NSNumber numberWithUnsignedInteger:widthUnits]];
            }
        }
    }

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    NSParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 10.0 * scale, 0.0, 1.52, tableFontSize);
    [tableAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    CGFloat cellHorizontalPadding = OMPipeTableHorizontalPadding(scale);
    BOOL allowTableHorizontalOverflow = (renderContext != NULL &&
                                         renderContext->allowTableHorizontalOverflow);
    BOOL useStackedFallback = NO;
    if (!allowTableHorizontalOverflow) {
        useStackedFallback = OMPipeTableNeedsStackedFallback(columnWidths,
                                                             layoutWidth,
                                                             indent,
                                                             tableFont,
                                                             cellHorizontalPadding,
                                                             scale);
    }
    if (useStackedFallback) {
        NSString *tableText = OMPipeTableStackedText(visibleRows);
        if (font != nil) {
            [tableAttrs setObject:font forKey:NSFontAttributeName];
        }
        NSMutableAttributedString *tableSegment = [[[NSMutableAttributedString alloc] initWithString:tableText
                                                                                           attributes:tableAttrs] autorelease];
        OMAppendAttributedSegment(output, tableSegment);
        [tableAttrs release];
        if (OMIsTightList(listStack)) {
            OMAppendString(output, @"\n", attributes);
        } else {
            OMAppendString(output, @"\n\n", attributes);
        }
        return;
    }

    NSColor *borderColor = OMPipeTableBorderColorForTheme(theme);
    NSColor *headerBackgroundColor = OMPipeTableHeaderBackgroundColorForTheme(theme);
    NSColor *bodyBackgroundColor = OMPipeTableBodyBackgroundColorForTheme(theme);
    NSMutableArray *attributedRows = [NSMutableArray arrayWithCapacity:[rows count]];
    NSUInteger rowIndex = 0;
    for (; rowIndex < [rows count]; rowIndex++) {
        NSArray *row = [rows objectAtIndex:rowIndex];
        BOOL headerRow = (rowIndex == 0);
        NSMutableArray *attributedCells = [NSMutableArray arrayWithCapacity:columnCount];

        for (colIndex = 0; colIndex < columnCount; colIndex++) {
            NSString *cellText = (colIndex < [row count] ? [row objectAtIndex:colIndex] : @"");
            NSMutableDictionary *cellAttrs = [tableAttrs mutableCopy];
            if (headerRow && headerFont != nil) {
                [cellAttrs setObject:headerFont forKey:NSFontAttributeName];
            }

            // Render the cell cmark-gfm parsed: it has already unescaped "\|"
            // and resolved reference links against the whole document.
            NSArray *rowNodes = rowIndex < [cellNodes count] ? [cellNodes objectAtIndex:rowIndex] : nil;
            cmark_node *cellNode = colIndex < [rowNodes count]
                ? (cmark_node *)[[rowNodes objectAtIndex:colIndex] pointerValue] : NULL;
            NSMutableAttributedString *cellSegment = nil;
            if (cellNode != NULL) {
                cellSegment = [[[NSMutableAttributedString alloc] init] autorelease];
                OMRenderInlines(cellNode, theme, cellSegment, [[cellAttrs mutableCopy] autorelease], scale, renderContext);
            } else {
                cellSegment = OMPipeTableAttributedCellContent(cellText, theme, cellAttrs, scale, renderContext);
            }
            OMPipeTableNormalizeCellSegment(cellSegment);
            if ([cellSegment length] == 0) {
                OMAppendString(cellSegment, @" ", cellAttrs);
            }
            NSAttributedString *immutableCell = [[[NSAttributedString alloc] initWithAttributedString:cellSegment] autorelease];
            [attributedCells addObject:immutableCell];
            [cellAttrs release];
        }
        [attributedRows addObject:attributedCells];
    }

    CGFloat maxTableWidth = 0.0;
    if (allowTableHorizontalOverflow) {
        if (layoutWidth > 0.0) {
            CGFloat overflowGuardWidth = 4096.0 * scale;
            CGFloat layoutRelativeWidth = layoutWidth * 4.0;
            if (layoutRelativeWidth > overflowGuardWidth) {
                overflowGuardWidth = layoutRelativeWidth;
            }
            maxTableWidth = overflowGuardWidth;
        }
    } else if (layoutWidth > 0.0) {
        maxTableWidth = layoutWidth - indent - (16.0 * scale);
        if (maxTableWidth < 120.0 * scale) {
            maxTableWidth = 120.0 * scale;
        }
    }

    // As text, so it can be selected, searched and its links clicked; the
    // drawn attachment stays for tables allowed to run wider than the view.
    NSMutableArray *textColumnWidths = nil;
    CGFloat textBorderWidth = 1.0;
    CGFloat textHorizontalPadding = 0.0;
    CGFloat textVerticalPadding = 0.0;
    if (!allowTableHorizontalOverflow &&
        OMPipeTableComputeLayout(visibleRows,
                                 attributedRows,
                                 [attributedRows count],
                                 columnCount,
                                 tableFont,
                                 headerFont,
                                 scale,
                                 maxTableWidth,
                                 &textColumnWidths,
                                 NULL,
                                 &textBorderWidth,
                                 &textHorizontalPadding,
                                 &textVerticalPadding,
                                 NULL,
                                 NULL)) {
        OMAppendTextTable(attributedRows,
                          alignments,
                          textColumnWidths,
                          indent,
                          textBorderWidth,
                          textHorizontalPadding,
                          textVerticalPadding,
                          tableFont,
                          ceil(tableFontSize * 1.5),
                          borderColor,
                          headerBackgroundColor,
                          bodyBackgroundColor,
                          tableMarkdown,
                          tableAttrs,
                          output);
        [tableAttrs release];
        if (!OMIsTightList(listStack)) {
            OMAppendString(output, @"\n", attributes);
        }
        return;
    }

    NSAttributedString *tableAttachment = OMPipeTableAttachmentAttributedString(attributedRows,
                                                                                visibleRows,
                                                                                alignments,
                                                                                tableFont,
                                                                                headerFont,
                                                                                borderColor,
                                                                                headerBackgroundColor,
                                                                                bodyBackgroundColor,
                                                                                scale,
                                                                                maxTableWidth,
                                                                                tableAttrs);
    if (tableAttachment != nil) {
        OMAppendAttributedSegment(output, tableAttachment);
    } else {
        NSString *tableText = OMPipeTableStackedText(visibleRows);
        OMAppendString(output, tableText, tableAttrs);
    }
    [tableAttrs release];

    if (OMIsTightList(listStack)) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

// Raw Markdown of a GFM table cell, cut from its source line using the byte
// columns cmark-gfm records (1-based UTF-8 offsets on the whole line, so this
// holds inside block quotes and list items too).
static NSString *OMGFMTableCellMarkdown(cmark_node *cell, const OMRenderContext *renderContext)
{
    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    int line = cmark_node_get_start_line(cell);
    int startColumn = cmark_node_get_start_column(cell);
    int endColumn = cmark_node_get_end_column(cell);
    if (sourceLines != nil && line >= 1 && (NSUInteger)line <= [sourceLines count] &&
        startColumn >= 1 && endColumn >= startColumn) {
        NSData *bytes = [[sourceLines objectAtIndex:(NSUInteger)line - 1] dataUsingEncoding:NSUTF8StringEncoding];
        if ((NSUInteger)endColumn <= [bytes length]) {
            NSData *slice = [bytes subdataWithRange:NSMakeRange((NSUInteger)startColumn - 1,
                                                                (NSUInteger)(endColumn - startColumn + 1))];
            NSString *text = [[[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding] autorelease];
            if (text != nil) {
                return OMTrimmedCellText(text);
            }
        }
    }
    return OMInlinePlainText(cell);
}

void OMRenderGFMTable(cmark_node *node,
                      OMTheme *theme,
                      NSMutableAttributedString *output,
                      NSMutableDictionary *attributes,
                      NSMutableArray *listStack,
                      NSUInteger quoteLevel,
                      CGFloat scale,
                      CGFloat layoutWidth,
                      const OMRenderContext *renderContext)
{
    NSUInteger columnCount = cmark_gfm_extensions_get_table_columns(node);
    if (columnCount == 0) {
        return;
    }
    uint8_t *alignmentBytes = cmark_gfm_extensions_get_table_alignments(node);
    NSMutableArray *alignments = [NSMutableArray arrayWithCapacity:columnCount];
    NSUInteger column = 0;
    for (; column < columnCount; column++) {
        uint8_t alignment = alignmentBytes != NULL ? alignmentBytes[column] : 0;
        OMPipeTableAlignment value = OMPipeTableAlignmentLeft;
        if (alignment == 'c') {
            value = OMPipeTableAlignmentCenter;
        } else if (alignment == 'r') {
            value = OMPipeTableAlignmentRight;
        }
        [alignments addObject:[NSNumber numberWithUnsignedInteger:value]];
    }

    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *cellNodes = [NSMutableArray array];
    cmark_node *row = cmark_node_first_child(node);
    for (; row != NULL; row = cmark_node_next(row)) {
        if (cmark_node_get_type(row) != CMARK_NODE_TABLE_ROW) {
            continue;
        }
        NSMutableArray *cells = [NSMutableArray arrayWithCapacity:columnCount];
        NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:columnCount];
        cmark_node *cell = cmark_node_first_child(row);
        for (; cell != NULL && [cells count] < columnCount; cell = cmark_node_next(cell)) {
            if (cmark_node_get_type(cell) == CMARK_NODE_TABLE_CELL) {
                [cells addObject:OMGFMTableCellMarkdown(cell, renderContext)];
                [nodes addObject:[NSValue valueWithPointer:cell]];
            }
        }
        while ([cells count] < columnCount) {
            [cells addObject:@""];
        }
        [rows addObject:cells];
        [cellNodes addObject:nodes];
    }
    if ([rows count] == 0) {
        return;
    }

    NSUInteger objectStart = [output length];
    NSString *tableMarkdown = OMSourceTextForNodeLines(node, renderContext);
    OMRenderPipeTable(rows,
                      alignments,
                      theme,
                      output,
                      attributes,
                      listStack,
                      quoteLevel,
                      scale,
                      layoutWidth,
                      tableMarkdown,
                      cellNodes,
                      renderContext);
    // A table laid out as text is no attachment; anything inside its cells
    // (math, images) is tagged on its own.
    BOOL laidOutAsText = (objectStart < [output length] &&
                          [output attribute:OMTextTableAttributeName atIndex:objectStart effectiveRange:NULL] != nil);
    if (tableMarkdown != nil && !laidOutAsText) {
        OMTagAppendedObject(output, objectStart, OMRenderedObjectKindTable, tableMarkdown, nil);
    }
}
