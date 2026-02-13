// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDLineNumberRulerView.h"

@interface OMDLineNumberRulerView ()
- (void)textDidChange:(NSNotification *)notification;
- (void)clipViewBoundsDidChange:(NSNotification *)notification;
- (void)updateRuleThickness;
- (NSUInteger)lineNumberForCharacterIndex:(NSUInteger)characterIndex inString:(NSString *)text;
@end

@implementation OMDLineNumberRulerView
{
    NSTextView *_textView;
}

- (instancetype)initWithScrollView:(NSScrollView *)scrollView textView:(NSTextView *)textView
{
    self = [super initWithScrollView:scrollView orientation:NSVerticalRuler];
    if (self) {
        _textView = [textView retain];
        [self setClientView:textView];

        NSClipView *clipView = [scrollView contentView];
        [clipView setPostsBoundsChangedNotifications:YES];

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self
                   selector:@selector(textDidChange:)
                       name:NSTextDidChangeNotification
                     object:_textView];
        [center addObserver:self
                   selector:@selector(clipViewBoundsDidChange:)
                       name:NSViewBoundsDidChangeNotification
                     object:clipView];
        [center addObserver:self
                   selector:@selector(clipViewBoundsDidChange:)
                       name:NSViewFrameDidChangeNotification
                     object:clipView];

        [self updateRuleThickness];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_textView release];
    [super dealloc];
}

- (void)invalidateLineNumbers
{
    [self updateRuleThickness];
    [self setNeedsDisplay:YES];
}

- (void)textDidChange:(NSNotification *)notification
{
    [self invalidateLineNumbers];
}

- (void)clipViewBoundsDidChange:(NSNotification *)notification
{
    [self setNeedsDisplay:YES];
}

- (void)updateRuleThickness
{
    NSString *text = [_textView string];
    NSUInteger lineCount = 1;
    NSUInteger length = [text length];
    for (NSUInteger i = 0; i < length; i++) {
        if ([text characterAtIndex:i] == '\n') {
            lineCount += 1;
        }
    }

    NSUInteger digits = 1;
    NSUInteger value = lineCount;
    while (value >= 10) {
        value /= 10;
        digits += 1;
    }

    CGFloat thickness = 12.0 + (CGFloat)(digits * 8.0) + 8.0;
    if (thickness < 30.0) {
        thickness = 30.0;
    }
    [self setRuleThickness:thickness];
}

- (NSUInteger)lineNumberForCharacterIndex:(NSUInteger)characterIndex inString:(NSString *)text
{
    if (text == nil || [text length] == 0) {
        return 1;
    }

    NSUInteger cappedIndex = characterIndex;
    if (cappedIndex > [text length]) {
        cappedIndex = [text length];
    }

    NSUInteger line = 1;
    for (NSUInteger i = 0; i < cappedIndex; i++) {
        if ([text characterAtIndex:i] == '\n') {
            line += 1;
        }
    }
    return line;
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect
{
    NSScrollView *scrollView = [self scrollView];
    if (scrollView == nil || _textView == nil) {
        return;
    }

    NSColor *backgroundColor = [NSColor controlBackgroundColor];
    if (backgroundColor == nil) {
        backgroundColor = [NSColor windowBackgroundColor];
    }
    [backgroundColor setFill];
    NSRectFill(rect);

    NSColor *separatorColor = [NSColor gridColor];
    if (separatorColor == nil) {
        separatorColor = [NSColor darkGrayColor];
    }
    [separatorColor setFill];
    NSRect separatorRect = NSMakeRect(NSWidth([self bounds]) - 1.0, NSMinY(rect), 1.0, NSHeight(rect));
    NSRectFill(separatorRect);

    NSLayoutManager *layoutManager = [_textView layoutManager];
    NSTextContainer *textContainer = [_textView textContainer];
    if (layoutManager == nil || textContainer == nil) {
        return;
    }

    NSString *text = [_textView string];
    NSUInteger textLength = [text length];
    if (textLength == 0) {
        return;
    }

    NSRect visibleRect = [[scrollView contentView] bounds];
    NSRange visibleGlyphRange = [layoutManager glyphRangeForBoundingRect:visibleRect inTextContainer:textContainer];
    if (visibleGlyphRange.length == 0) {
        return;
    }

    NSFont *textFont = [_textView font];
    CGFloat fontSize = textFont != nil ? [textFont pointSize] : 12.0;
    NSFont *numberFont = [NSFont userFixedPitchFontOfSize:MAX(9.0, fontSize - 1.0)];
    if (numberFont == nil) {
        numberFont = [NSFont fontWithName:@"Courier" size:MAX(9.0, fontSize - 1.0)];
    }
    if (numberFont == nil) {
        numberFont = [NSFont systemFontOfSize:MAX(9.0, fontSize - 1.0)];
    }

    NSColor *textColor = [NSColor disabledControlTextColor];
    if (textColor == nil) {
        textColor = [NSColor controlTextColor];
    }
    if (textColor == nil) {
        textColor = [NSColor textColor];
    }

    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                numberFont, NSFontAttributeName,
                                textColor, NSForegroundColorAttributeName,
                                nil];

    NSUInteger firstVisibleGlyph = visibleGlyphRange.location;
    NSUInteger lastVisibleGlyph = NSMaxRange(visibleGlyphRange) - 1;
    NSUInteger firstVisibleCharacter = [layoutManager characterIndexForGlyphAtIndex:firstVisibleGlyph];
    NSUInteger lastVisibleCharacter = [layoutManager characterIndexForGlyphAtIndex:lastVisibleGlyph];
    if (lastVisibleCharacter > textLength) {
        lastVisibleCharacter = textLength;
    }

    NSRange firstLineRange = [text lineRangeForRange:NSMakeRange(firstVisibleCharacter, 0)];
    NSUInteger lineStart = firstLineRange.location;
    NSUInteger lineNumber = [self lineNumberForCharacterIndex:lineStart inString:text];
    NSPoint textOrigin = [_textView textContainerOrigin];

    while (lineStart < textLength) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(lineStart, 0)];
        if (lineRange.location > lastVisibleCharacter + 1) {
            break;
        }

        NSRange glyphRangeForLine = [layoutManager glyphRangeForCharacterRange:NSMakeRange(lineRange.location, 1)
                                                           actualCharacterRange:NULL];
        if (glyphRangeForLine.length == 0) {
            lineNumber += 1;
            lineStart = NSMaxRange(lineRange);
            continue;
        }

        NSRect lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphRangeForLine.location
                                                           effectiveRange:NULL];
        CGFloat y = lineRect.origin.y + textOrigin.y;
        NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
        NSSize labelSize = [label sizeWithAttributes:attributes];
        CGFloat x = NSWidth([self bounds]) - labelSize.width - 6.0;
        if (x < 2.0) {
            x = 2.0;
        }
        [label drawAtPoint:NSMakePoint(x, y) withAttributes:attributes];

        lineNumber += 1;
        lineStart = NSMaxRange(lineRange);
    }
}

@end
