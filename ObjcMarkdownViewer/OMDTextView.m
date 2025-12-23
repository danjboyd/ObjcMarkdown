// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDTextView.h"

@implementation OMDTextView

- (void)dealloc
{
    [_codeBlockRanges release];
    [_codeBlockBackgroundColor release];
    [_blockquoteRanges release];
    [_blockquoteLineColor release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [self drawCodeBlockBackgrounds];
    [super drawRect:dirtyRect];
    [self drawBlockquoteLines];
}

- (void)drawCodeBlockBackgrounds
{
    if (self.codeBlockBackgroundColor == nil || [self.codeBlockRanges count] == 0) {
        return;
    }

    NSLayoutManager *layoutManager = [self layoutManager];
    NSTextContainer *container = [self textContainer];
    if (layoutManager == nil || container == nil) {
        return;
    }

    [self.codeBlockBackgroundColor setFill];

    NSPoint origin = [self textContainerOrigin];
    NSSize inset = [self textContainerInset];
    CGFloat paddingX = self.codeBlockPadding.width;
    CGFloat paddingY = self.codeBlockPadding.height;

    for (NSValue *value in self.codeBlockRanges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        NSUInteger glyphIndex = glyphRange.location;
        while (glyphIndex < NSMaxRange(glyphRange)) {
            NSRange lineRange;
            NSRect lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphIndex
                                                             effectiveRange:&lineRange];
            if (NSMaxRange(lineRange) > NSMaxRange(glyphRange)) {
                lineRange.length = NSMaxRange(glyphRange) - lineRange.location;
            }

            NSRect lineBounds = lineRect;
            lineBounds.origin.x = origin.x + inset.width;
            lineBounds.size.width = [self bounds].size.width - (inset.width * 2.0);
            lineBounds.origin.y = origin.y + lineRect.origin.y;
            lineBounds.size.height = lineRect.size.height;

            lineBounds.origin.x -= paddingX;
            lineBounds.size.width += paddingX * 2.0;
            lineBounds.origin.y -= paddingY / 2.0;
            lineBounds.size.height += paddingY;

            NSRectFill(lineBounds);
            glyphIndex = NSMaxRange(lineRange);
        }
    }
}

- (void)drawBlockquoteLines
{
    if (self.blockquoteLineColor == nil || [self.blockquoteRanges count] == 0) {
        return;
    }

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];
    [context setCompositingOperation:NSCompositeDestinationOver];

    NSLayoutManager *layoutManager = [self layoutManager];
    NSTextContainer *container = [self textContainer];
    if (layoutManager == nil || container == nil) {
        [context restoreGraphicsState];
        return;
    }

    [self.blockquoteLineColor setFill];

    NSPoint origin = [self textContainerOrigin];
    NSSize inset = [self textContainerInset];
    CGFloat lineWidth = self.blockquoteLineWidth > 0.0 ? self.blockquoteLineWidth : 3.0;

    for (NSValue *value in self.blockquoteRanges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        if (glyphRange.length == 0) {
            continue;
        }

        NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];

        NSUInteger charIndex = charRange.location;
        if (charIndex < [[self textStorage] length]) {
            (void)[[self textStorage] attributesAtIndex:charIndex effectiveRange:NULL];
        }
        CGFloat lineX = origin.x + inset.width - 24.0;
        CGFloat minX = origin.x + inset.width - 20.0;
        if (lineX < minX) {
            lineX = minX;
        }

        NSRect lineBounds = blockRect;
        lineBounds.origin.x = lineX;
        lineBounds.origin.y = origin.y + blockRect.origin.y;
        lineBounds.size.width = lineWidth;

        NSRectFill(lineBounds);
    }

    [context restoreGraphicsState];
}

@end
