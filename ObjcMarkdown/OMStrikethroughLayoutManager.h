// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <AppKit/AppKit.h>

// Draws NSStrikethroughStyleAttributeName, which GNUstep's NSLayoutManager
// and string drawing accept but never draw (elsewhere it adds nothing), and
// the grids of tables laid out as text (OMTextTableAttributeName).
@interface OMStrikethroughLayoutManager : NSLayoutManager

// Rects (as NSValue, in the coordinates drawGlyphsForGlyphRange:atPoint:
// draws in) of the strikethrough lines for glyphs drawn at origin.
- (NSArray *)strikethroughLineRectsForGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin;

@end

// Draws the strikethrough lines for string laid out as -drawInRect:rect lays
// it out, so call it right after -drawInRect:. flipped is whether the current
// context is flipped. Does nothing off GNUstep or without strikethrough.
FOUNDATION_EXPORT void OMDrawStrikethroughForAttributedString(NSAttributedString *string, NSRect rect, BOOL flipped);
