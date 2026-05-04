// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDLineNumberRulerView.h"

static BOOL OMDKeyLatencyProfilingEnabled(void)
{
    static NSInteger enabled = -1;
    if (enabled < 0) {
        NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:@"OMD_KEYLATENCY"];
        enabled = ([value length] > 0 && ![value isEqualToString:@"0"]) ? 1 : 0;
    }
    return enabled == 1;
}

static NSTimeInterval OMDKeyLatencyNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

static double OMDKeyLatencyThresholdMS(void)
{
    static double threshold = -1.0;
    if (threshold < 0.0) {
        NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:@"OMD_KEYLATENCY_THRESHOLD_MS"];
        threshold = [value length] > 0 ? [value doubleValue] : 4.0;
        if (threshold < 0.0) {
            threshold = 0.0;
        }
    }
    return threshold;
}

static double OMDKeyLatencyMS(NSTimeInterval start, NSTimeInterval end)
{
    return (end - start) * 1000.0;
}

@interface OMDLineNumberRulerView ()
- (void)textDidChange:(NSNotification *)notification;
- (void)clipViewBoundsDidChange:(NSNotification *)notification;
- (void)updateRuleThickness;
- (NSArray *)lineStartIndexesForString:(NSString *)text;
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
    BOOL profiling = OMDKeyLatencyProfilingEnabled();
    NSTimeInterval start = profiling ? OMDKeyLatencyNow() : 0.0;
    [self updateRuleThickness];
    [self setNeedsDisplay:YES];
    if (profiling) {
        NSTimeInterval end = OMDKeyLatencyNow();
        double totalMS = OMDKeyLatencyMS(start, end);
        if (totalMS >= OMDKeyLatencyThresholdMS()) {
            NSLog(@"OMDKeyLatency lineNumbersInvalidate total=%.2fms length=%lu",
                  totalMS,
                  (unsigned long)[[_textView string] length]);
        }
    }
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
    BOOL profiling = OMDKeyLatencyProfilingEnabled();
    NSTimeInterval start = profiling ? OMDKeyLatencyNow() : 0.0;
    NSUInteger lineCount = [[self lineStartIndexesForString:[_textView string]] count];

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
    if (profiling) {
        NSTimeInterval end = OMDKeyLatencyNow();
        double totalMS = OMDKeyLatencyMS(start, end);
        if (totalMS >= OMDKeyLatencyThresholdMS()) {
            NSLog(@"OMDKeyLatency lineNumbersThickness total=%.2fms lines=%lu length=%lu thickness=%.1f",
                  totalMS,
                  (unsigned long)lineCount,
                  (unsigned long)[[_textView string] length],
                  thickness);
        }
    }
}

- (NSArray *)lineStartIndexesForString:(NSString *)text
{
    NSMutableArray *lineStarts = [NSMutableArray arrayWithObject:[NSNumber numberWithUnsignedInteger:0]];
    NSUInteger length = [text length];
    for (NSUInteger i = 0; i < length; i++) {
        if ([text characterAtIndex:i] == '\n') {
            [lineStarts addObject:[NSNumber numberWithUnsignedInteger:i + 1]];
        }
    }
    return lineStarts;
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
    BOOL profiling = OMDKeyLatencyProfilingEnabled();
    NSTimeInterval start = profiling ? OMDKeyLatencyNow() : 0.0;
    NSUInteger drawnLabels = 0;
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
    NSArray *lineStarts = [self lineStartIndexesForString:text];

    NSRect visibleRect = [[scrollView contentView] bounds];
    NSPoint textOrigin = [_textView textContainerOrigin];
    NSFont *layoutFont = [_textView font];
    if (layoutFont == nil) {
        layoutFont = [NSFont systemFontOfSize:12.0];
    }
    CGFloat lineHeight = [layoutManager defaultLineHeightForFont:layoutFont];
    if (lineHeight < 1.0) {
        lineHeight = 14.0;
    }
    NSRect visibleTextRect = visibleRect;
    visibleTextRect.origin.x -= textOrigin.x;
    visibleTextRect.origin.y -= textOrigin.y;
    visibleTextRect.size.height += 2.0 * lineHeight;
    if (visibleTextRect.origin.y > lineHeight) {
        visibleTextRect.origin.y -= lineHeight;
    } else {
        visibleTextRect.origin.y = 0.0;
    }

    NSRange visibleGlyphRange = [layoutManager glyphRangeForBoundingRect:visibleTextRect inTextContainer:textContainer];
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
    NSUInteger firstVisibleCharacter = [layoutManager characterIndexForGlyphAtIndex:firstVisibleGlyph];

    NSRange firstLineRange = [text lineRangeForRange:NSMakeRange(firstVisibleCharacter, 0)];
    NSUInteger firstLineStart = firstLineRange.location;
    NSUInteger lineNumber = [self lineNumberForCharacterIndex:firstLineStart inString:text];
    NSUInteger firstLineIndex = 0;
    NSUInteger lineStartCount = [lineStarts count];
    for (NSUInteger i = 0; i < lineStartCount; i++) {
        NSUInteger candidate = [[lineStarts objectAtIndex:i] unsignedIntegerValue];
        if (candidate >= firstLineStart) {
            firstLineIndex = i;
            lineNumber = i + 1;
            break;
        }
    }

    for (NSUInteger i = firstLineIndex; i < lineStartCount; i++) {
        NSUInteger lineStart = [[lineStarts objectAtIndex:i] unsignedIntegerValue];

        BOOL emptyTrailingLine = (lineStart == textLength && textLength > 0);
        NSRange lineRange = emptyTrailingLine ? NSMakeRange(lineStart, 0) : [text lineRangeForRange:NSMakeRange(lineStart, 0)];

        NSRange glyphRangeForLine = NSMakeRange(NSNotFound, 0);
        if (emptyTrailingLine) {
            NSRange previousGlyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(textLength - 1, 1)
                                                               actualCharacterRange:NULL];
            if (previousGlyphRange.length > 0) {
                glyphRangeForLine = previousGlyphRange;
            }
        } else if (lineRange.length > 0) {
            glyphRangeForLine = [layoutManager glyphRangeForCharacterRange:NSMakeRange(lineRange.location, 1)
                                                           actualCharacterRange:NULL];
        }
        if (glyphRangeForLine.length == 0) {
            lineNumber += 1;
            continue;
        }

        NSRect lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphRangeForLine.location
                                                           effectiveRange:NULL];
        CGFloat y = lineRect.origin.y + textOrigin.y - visibleRect.origin.y;
        if (emptyTrailingLine) {
            y += lineHeight;
        }
        NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
        NSSize labelSize = [label sizeWithAttributes:attributes];
        CGFloat x = NSWidth([self bounds]) - labelSize.width - 6.0;
        if (x < 2.0) {
            x = 2.0;
        }
        if (y + labelSize.height < NSMinY(rect) - 2.0) {
            lineNumber += 1;
            continue;
        }
        if (y > NSMaxY(rect) + 2.0) {
            break;
        }
        [label drawAtPoint:NSMakePoint(x, y) withAttributes:attributes];
        drawnLabels += 1;

        lineNumber += 1;
    }

    if (profiling) {
        NSTimeInterval end = OMDKeyLatencyNow();
        double totalMS = OMDKeyLatencyMS(start, end);
        if (totalMS >= OMDKeyLatencyThresholdMS()) {
            NSLog(@"OMDKeyLatency lineNumbersDraw total=%.2fms labels=%lu length=%lu rect=%@",
                  totalMS,
                  (unsigned long)drawnLabels,
                  (unsigned long)textLength,
                  NSStringFromRect(rect));
        }
    }
}

- (void)mouseDown:(NSEvent *)event
{
    // Keep the line-number gutter inert to avoid NSRulerView interaction artifacts.
    (void)event;
}

- (void)mouseDragged:(NSEvent *)event
{
    (void)event;
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
}

- (void)rightMouseDown:(NSEvent *)event
{
    (void)event;
}

- (void)otherMouseDown:(NSEvent *)event
{
    (void)event;
}

@end
