// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDTextView.h"

@implementation OMDTextView

- (void)dealloc
{
    [_codeBlockRanges release];
    [_codeBlockBackgroundColor release];
    [_codeBlockBorderColor release];
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
    CGFloat cornerRadius = self.codeBlockCornerRadius > 0.0 ? self.codeBlockCornerRadius : 6.0;
    CGFloat borderWidth = self.codeBlockBorderWidth > 0.0 ? self.codeBlockBorderWidth : 1.0;
    NSColor *borderColor = self.codeBlockBorderColor;
    CGFloat minX = origin.x + inset.width - paddingX;
    CGFloat maxX = origin.x + [self bounds].size.width - inset.width + paddingX;

    for (NSValue *value in self.codeBlockRanges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        if (glyphRange.length == 0) {
            continue;
        }

        NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];
        NSRect blockBounds = blockRect;
        blockBounds.origin.x = origin.x + blockRect.origin.x;
        blockBounds.origin.y = origin.y + blockRect.origin.y;

        blockBounds.origin.x -= paddingX;
        blockBounds.size.width += paddingX * 2.0;
        blockBounds.origin.y -= paddingY;
        blockBounds.size.height += paddingY * 2.0;

        if (blockBounds.origin.x < minX) {
            CGFloat delta = minX - blockBounds.origin.x;
            blockBounds.origin.x = minX;
            blockBounds.size.width -= delta;
        }
        CGFloat rightEdge = NSMaxX(blockBounds);
        if (rightEdge > maxX) {
            blockBounds.size.width -= (rightEdge - maxX);
        }
        if (blockBounds.size.width < 1.0 || blockBounds.size.height < 1.0) {
            continue;
        }

        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:blockBounds
                                                             xRadius:cornerRadius
                                                             yRadius:cornerRadius];
        [self.codeBlockBackgroundColor setFill];
        [path fill];
        if (borderColor != nil && borderWidth > 0.0) {
            [path setLineWidth:borderWidth];
            [borderColor setStroke];
            [path stroke];
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
