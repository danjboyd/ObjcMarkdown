// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <AppKit/AppKit.h>

@class OMRenderedObject;

// Attribute on the text of a table laid out as text: the OMTextTable it
// belongs to. Each visual line is a paragraph whose cells are tab-separated.
FOUNDATION_EXPORT NSString * const OMTextTableAttributeName;
// Attribute on each row's text: NSNumber row index, 0 for the header.
FOUNDATION_EXPORT NSString * const OMTextTableRowAttributeName;

// The grid a text table is drawn with. Column edges are x positions in text
// container coordinates (the coordinates indents and tab stops use).
@interface OMTextTable : NSObject
{
    NSArray *_columnEdges;
    NSUInteger _rowCount;
    CGFloat _borderWidth;
    NSColor *_borderColor;
    NSColor *_headerBackgroundColor;
    NSColor *_bodyBackgroundColor;
    NSString *_markdown;
    OMRenderedObject *_renderedObject;
}

- (instancetype)initWithColumnEdges:(NSArray *)columnEdges
                           rowCount:(NSUInteger)rowCount
                        borderWidth:(CGFloat)borderWidth
                        borderColor:(NSColor *)borderColor
              headerBackgroundColor:(NSColor *)headerBackgroundColor
                bodyBackgroundColor:(NSColor *)bodyBackgroundColor
                           markdown:(NSString *)markdown;

// NSNumber x positions: the left edge of each column, then the table's right edge.
@property (nonatomic, readonly) NSArray *columnEdges;
@property (nonatomic, readonly) NSUInteger rowCount;
@property (nonatomic, readonly) CGFloat borderWidth;
@property (nonatomic, readonly) NSColor *borderColor;
@property (nonatomic, readonly) NSColor *headerBackgroundColor;
@property (nonatomic, readonly) NSColor *bodyBackgroundColor;
// The table as written in the Markdown source.
@property (nonatomic, readonly, copy) NSString *markdown;
// Where the table came from (kind OMRenderedObjectKindTable), once known.
@property (nonatomic, retain) OMRenderedObject *renderedObject;

@end

// Draws the backgrounds and rules of every text table with glyphs in
// glyphRange, laid out by layoutManager, with the container at origin.
FOUNDATION_EXPORT void OMDrawTextTablesForGlyphRange(NSLayoutManager *layoutManager,
                                                      NSRange glyphRange,
                                                      NSPoint origin);
// The same in two passes, so a selection drawn between them leaves the rules visible.
FOUNDATION_EXPORT void OMDrawTextTableBackgroundsForGlyphRange(NSLayoutManager *layoutManager,
                                                                NSRange glyphRange,
                                                                NSPoint origin);
FOUNDATION_EXPORT void OMDrawTextTableRulesForGlyphRange(NSLayoutManager *layoutManager,
                                                          NSRange glyphRange,
                                                          NSPoint origin);
