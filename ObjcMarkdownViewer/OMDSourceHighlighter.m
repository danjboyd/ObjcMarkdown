// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSourceHighlighter.h"

#include "cmark-gfm.h"
#include "OMGFMParser.h"

typedef struct {
    NSColor *headingColor;
    NSColor *blockquoteColor;
    NSColor *listColor;
    NSColor *linkColor;
    NSColor *emphasisColor;
    NSColor *codeColor;
    NSColor *mathColor;
} OMDSourceHighlightPalette;

typedef NS_ENUM(NSUInteger, OMDSourceBlockStyle) {
    OMDSourceBlockStyleNone = 0,
    OMDSourceBlockStyleList = 1,
    OMDSourceBlockStyleBlockquote = 2,
    OMDSourceBlockStyleHeading = 3,
    OMDSourceBlockStyleCode = 4
};

NSString * const OMDSourceHighlighterOptionHighContrast = @"OMDSourceHighlighterOptionHighContrast";
NSString * const OMDSourceHighlighterOptionAccentColor = @"OMDSourceHighlighterOptionAccentColor";

static const NSUInteger OMDParserBackedHighlightMaxLength = 120000;

static BOOL OMDColorRGBA(NSColor *color, CGFloat *red, CGFloat *green, CGFloat *blue, CGFloat *alpha)
{
    if (color == nil) {
        return NO;
    }

    @try {
        NSColor *rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (rgbColor == nil) {
            return NO;
        }
        if (red != NULL) {
            *red = [rgbColor redComponent];
        }
        if (green != NULL) {
            *green = [rgbColor greenComponent];
        }
        if (blue != NULL) {
            *blue = [rgbColor blueComponent];
        }
        if (alpha != NULL) {
            *alpha = [rgbColor alphaComponent];
        }
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

static NSColor *OMDColorBlend(NSColor *base, NSColor *target, CGFloat mix)
{
    CGFloat br = 0.0;
    CGFloat bg = 0.0;
    CGFloat bb = 0.0;
    CGFloat ba = 1.0;
    CGFloat tr = 0.0;
    CGFloat tg = 0.0;
    CGFloat tb = 0.0;
    CGFloat ta = 1.0;

    if (!OMDColorRGBA(base, &br, &bg, &bb, &ba) ||
        !OMDColorRGBA(target, &tr, &tg, &tb, &ta)) {
        return base;
    }

    if (mix < 0.0) {
        mix = 0.0;
    } else if (mix > 1.0) {
        mix = 1.0;
    }

    CGFloat inv = 1.0 - mix;
    return [NSColor colorWithCalibratedRed:(br * inv) + (tr * mix)
                                     green:(bg * inv) + (tg * mix)
                                      blue:(bb * inv) + (tb * mix)
                                     alpha:(ba * inv) + (ta * mix)];
}

static OMDSourceHighlightPalette OMDPaletteForBackground(NSColor *backgroundColor,
                                                          BOOL highContrast,
                                                          NSColor *accentColor)
{
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    BOOL hasRGB = OMDColorRGBA(backgroundColor, &red, &green, &blue, NULL);
    CGFloat luminance = hasRGB ? ((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) : 0.0;
    BOOL darkBackground = luminance < 0.5;

    OMDSourceHighlightPalette palette;
    if (darkBackground) {
        palette.headingColor = [NSColor colorWithCalibratedRed:0.47 green:0.72 blue:0.99 alpha:1.0];
        palette.blockquoteColor = [NSColor colorWithCalibratedRed:0.61 green:0.72 blue:0.55 alpha:1.0];
        palette.listColor = [NSColor colorWithCalibratedRed:0.55 green:0.78 blue:0.72 alpha:1.0];
        palette.linkColor = [NSColor colorWithCalibratedRed:0.38 green:0.68 blue:0.97 alpha:1.0];
        palette.emphasisColor = [NSColor colorWithCalibratedRed:0.78 green:0.56 blue:0.87 alpha:1.0];
        palette.codeColor = [NSColor colorWithCalibratedRed:0.95 green:0.78 blue:0.45 alpha:1.0];
        palette.mathColor = [NSColor colorWithCalibratedRed:0.48 green:0.76 blue:0.74 alpha:1.0];
    } else {
        palette.headingColor = [NSColor colorWithCalibratedRed:0.10 green:0.31 blue:0.72 alpha:1.0];
        palette.blockquoteColor = [NSColor colorWithCalibratedRed:0.22 green:0.45 blue:0.22 alpha:1.0];
        palette.listColor = [NSColor colorWithCalibratedRed:0.18 green:0.48 blue:0.45 alpha:1.0];
        palette.linkColor = [NSColor colorWithCalibratedRed:0.00 green:0.36 blue:0.74 alpha:1.0];
        palette.emphasisColor = [NSColor colorWithCalibratedRed:0.51 green:0.20 blue:0.63 alpha:1.0];
        palette.codeColor = [NSColor colorWithCalibratedRed:0.67 green:0.34 blue:0.00 alpha:1.0];
        palette.mathColor = [NSColor colorWithCalibratedRed:0.00 green:0.46 blue:0.45 alpha:1.0];
    }

    if (highContrast) {
        NSColor *target = darkBackground ? [NSColor whiteColor] : [NSColor blackColor];
        palette.headingColor = OMDColorBlend(palette.headingColor, target, 0.28);
        palette.blockquoteColor = OMDColorBlend(palette.blockquoteColor, target, 0.24);
        palette.listColor = OMDColorBlend(palette.listColor, target, 0.24);
        palette.linkColor = OMDColorBlend(palette.linkColor, target, 0.30);
        palette.emphasisColor = OMDColorBlend(palette.emphasisColor, target, 0.30);
        palette.codeColor = OMDColorBlend(palette.codeColor, target, 0.26);
        palette.mathColor = OMDColorBlend(palette.mathColor, target, 0.28);
    }

    if (accentColor != nil) {
        palette.headingColor = accentColor;
        palette.linkColor = accentColor;
        palette.emphasisColor = OMDColorBlend(accentColor,
                                              darkBackground ? [NSColor whiteColor] : [NSColor blackColor],
                                              highContrast ? 0.30 : 0.18);
    }

    return palette;
}

static NSRegularExpression *OMDInlineCodeRegex(void)
{
    static NSRegularExpression *regex = nil;
    if (regex == nil) {
        regex = [[NSRegularExpression alloc] initWithPattern:@"`[^`\\n]+`" options:0 error:NULL];
    }
    return regex;
}

static NSRegularExpression *OMDLinkRegex(void)
{
    static NSRegularExpression *regex = nil;
    if (regex == nil) {
        regex = [[NSRegularExpression alloc] initWithPattern:@"\\[[^\\]\\n]+\\]\\([^\\)\\n]+\\)" options:0 error:NULL];
    }
    return regex;
}

static NSRegularExpression *OMDBoldRegex(void)
{
    static NSRegularExpression *regex = nil;
    if (regex == nil) {
        regex = [[NSRegularExpression alloc] initWithPattern:@"(?:\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__)" options:0 error:NULL];
    }
    return regex;
}

static NSRegularExpression *OMDItalicRegex(void)
{
    static NSRegularExpression *regex = nil;
    if (regex == nil) {
        regex = [[NSRegularExpression alloc] initWithPattern:@"(?<!\\*)\\*[^*\\n]+\\*(?!\\*)|(?<!_)_[^_\\n]+_(?!_)"
                                                      options:0
                                                        error:NULL];
    }
    return regex;
}

static NSRegularExpression *OMDInlineMathRegex(void)
{
    static NSRegularExpression *regex = nil;
    if (regex == nil) {
        regex = [[NSRegularExpression alloc] initWithPattern:@"\\$[^$\\n]+\\$" options:0 error:NULL];
    }
    return regex;
}

static NSRegularExpression *OMDDisplayMathRegex(void)
{
    static NSRegularExpression *regex = nil;
    if (regex == nil) {
        regex = [[NSRegularExpression alloc] initWithPattern:@"\\$\\$[\\s\\S]*?\\$\\$" options:0 error:NULL];
    }
    return regex;
}

static BOOL OMDHasOrderedListMarker(NSString *trimmed)
{
    if (trimmed == nil || [trimmed length] < 2) {
        return NO;
    }
    NSUInteger index = 0;
    NSUInteger length = [trimmed length];
    while (index < length) {
        unichar ch = [trimmed characterAtIndex:index];
        if (ch >= '0' && ch <= '9') {
            index += 1;
            continue;
        }
        break;
    }
    if (index == 0 || index >= length) {
        return NO;
    }
    unichar marker = [trimmed characterAtIndex:index];
    if (marker != '.' && marker != ')') {
        return NO;
    }
    return YES;
}

static BOOL OMDHasListMarker(NSString *trimmed)
{
    if (trimmed == nil || [trimmed length] < 2) {
        return NO;
    }
    unichar bullet = [trimmed characterAtIndex:0];
    if ((bullet == '-' || bullet == '+' || bullet == '*') &&
        ([trimmed characterAtIndex:1] == ' ' || [trimmed characterAtIndex:1] == '\t')) {
        return YES;
    }
    return OMDHasOrderedListMarker(trimmed);
}

static BOOL OMDHasHeadingMarker(NSString *trimmed)
{
    if (trimmed == nil || [trimmed length] < 2) {
        return NO;
    }
    NSUInteger i = 0;
    NSUInteger length = [trimmed length];
    while (i < length && i < 6 && [trimmed characterAtIndex:i] == '#') {
        i += 1;
    }
    if (i == 0 || i >= length) {
        return NO;
    }
    unichar separator = [trimmed characterAtIndex:i];
    return separator == ' ' || separator == '\t';
}

static NSUInteger OMDSourceBlockStylePriority(OMDSourceBlockStyle style)
{
    switch (style) {
        case OMDSourceBlockStyleCode:
            return 500;
        case OMDSourceBlockStyleHeading:
            return 400;
        case OMDSourceBlockStyleBlockquote:
            return 300;
        case OMDSourceBlockStyleList:
            return 200;
        case OMDSourceBlockStyleNone:
        default:
            return 0;
    }
}

// The parser's block style for each line, indexed by line number (1-based),
// as bytes; a line keeps the style that matters most.
static void OMDSetLineStyle(NSMutableData *lineStyles,
                            NSUInteger lineNumber,
                            OMDSourceBlockStyle style)
{
    if (lineStyles == nil || lineNumber == 0 || style == OMDSourceBlockStyleNone) {
        return;
    }
    if (lineNumber >= [lineStyles length]) {
        [lineStyles setLength:lineNumber + 1];
    }
    uint8_t *styles = (uint8_t *)[lineStyles mutableBytes];
    OMDSourceBlockStyle existingStyle = (OMDSourceBlockStyle)styles[lineNumber];
    if (OMDSourceBlockStylePriority(existingStyle) >= OMDSourceBlockStylePriority(style)) {
        return;
    }
    styles[lineNumber] = (uint8_t)style;
}

static void OMDApplyNodeStyleToLines(cmark_node *node,
                                     NSMutableData *lineStyles,
                                     OMDSourceBlockStyle style)
{
    if (node == NULL || lineStyles == nil || style == OMDSourceBlockStyleNone) {
        return;
    }

    int startLine = cmark_node_get_start_line(node);
    int endLine = cmark_node_get_end_line(node);
    if (startLine <= 0 || endLine <= 0 || endLine < startLine) {
        return;
    }

    NSUInteger line = (NSUInteger)startLine;
    NSUInteger finalLine = (NSUInteger)endLine;
    for (; line <= finalLine; line++) {
        OMDSetLineStyle(lineStyles, line, style);
    }
}

static void OMDCollectParserLineStyles(cmark_node *node,
                                       NSMutableData *lineStyles,
                                       BOOL inBlockquote,
                                       BOOL inList,
                                       BOOL inCode)
{
    cmark_node *cursor = node;
    while (cursor != NULL) {
        cmark_node_type type = cmark_node_get_type(cursor);
        BOOL nodeInBlockquote = inBlockquote || type == CMARK_NODE_BLOCK_QUOTE;
        BOOL nodeInList = inList || type == CMARK_NODE_LIST || type == CMARK_NODE_ITEM;
        BOOL nodeInCode = inCode || type == CMARK_NODE_CODE_BLOCK;

        OMDSourceBlockStyle style = OMDSourceBlockStyleNone;
        if (nodeInCode) {
            style = OMDSourceBlockStyleCode;
        } else if (type == CMARK_NODE_HEADING) {
            style = OMDSourceBlockStyleHeading;
        } else if (nodeInBlockquote) {
            style = OMDSourceBlockStyleBlockquote;
        } else if (nodeInList) {
            style = OMDSourceBlockStyleList;
        }

        OMDApplyNodeStyleToLines(cursor, lineStyles, style);

        cmark_node *child = cmark_node_first_child(cursor);
        if (child != NULL) {
            OMDCollectParserLineStyles(child,
                                       lineStyles,
                                       nodeInBlockquote,
                                       nodeInList,
                                       nodeInCode);
        }
        cursor = cmark_node_next(cursor);
    }
}

static NSData *OMDParserBackedLineStyles(NSString *markdown)
{
    if (markdown == nil || [markdown length] == 0) {
        return nil;
    }
    if ([markdown length] > OMDParserBackedHighlightMaxLength) {
        return nil;
    }

    NSData *utf8 = [markdown dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    if (utf8 == nil || [utf8 length] == 0) {
        return nil;
    }

    cmark_node *document = OMGFMParseDocument((const char *)[utf8 bytes],
                                                (size_t)[utf8 length],
                                                CMARK_OPT_DEFAULT | CMARK_OPT_SOURCEPOS);
    if (document == NULL) {
        return nil;
    }

    NSMutableData *lineStyles = [NSMutableData data];
    cmark_node *rootChild = cmark_node_first_child(document);
    if (rootChild != NULL) {
        OMDCollectParserLineStyles(rootChild, lineStyles, NO, NO, NO);
    }
    cmark_node_free(document);

    return lineStyles;
}

// A line of the source as a pass sees it (#333).
typedef struct {
    NSUInteger start;          // its first character
    NSUInteger contentLength;  // without its line ending
    NSUInteger end;            // after its line ending
    NSUInteger trimmedStart;   // after its leading spaces and tabs
    uint8_t code;              // the parser's block style, or OMDSourceLineFence
} OMDSourceLine;

// A fence's delimiter line or a line inside a fence: code colour, whatever
// the parser says.
enum { OMDSourceLineFence = 0x80 };

static BOOL OMDIsFenceDelimiterAt(const unichar *chars, NSUInteger start, NSUInteger length, unichar marker)
{
    if (length < 3) {
        return NO;
    }
    if (marker != '`' && marker != '~') {
        marker = chars[start];
    }
    if (marker != '`' && marker != '~') {
        return NO;
    }
    NSUInteger run = 0;
    while (run < length && chars[start + run] == marker) {
        run += 1;
    }
    return run >= 3;
}

// The text's lines, with each one's block code. unusualBreaksOut says
// whether the text breaks lines with something other than \n or \r\n (a
// lone \r, U+0085, U+2028, U+2029), which the inline patterns can match
// across.
static NSData *OMDSourceLinesForText(NSString *text, NSData *parserLineStyles, BOOL *unusualBreaksOut)
{
    NSUInteger length = [text length];
    NSMutableData *lines = [NSMutableData data];
    BOOL unusual = NO;
    if (length == 0) {
        if (unusualBreaksOut != NULL) {
            *unusualBreaksOut = NO;
        }
        return lines;
    }

    unichar *chars = (unichar *)malloc(sizeof(unichar) * length);
    if (chars == NULL) {
        return nil;
    }
    [text getCharacters:chars range:NSMakeRange(0, length)];

    const uint8_t *parserStyles = (const uint8_t *)[parserLineStyles bytes];
    NSUInteger parserLineCount = [parserLineStyles length];
    BOOL insideFence = NO;
    unichar activeFenceMarker = 0;
    NSUInteger cursor = 0;
    NSUInteger lineNumber = 1;
    while (cursor < length) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(cursor, 0)];
        OMDSourceLine line;
        line.start = lineRange.location;
        line.end = NSMaxRange(lineRange);
        if (line.end <= cursor) {
            line.end = cursor + 1;
        }
        NSUInteger contentLength = line.end - line.start;
        while (contentLength > 0) {
            unichar ch = chars[line.start + contentLength - 1];
            if (ch == '\n' || ch == '\r') {
                contentLength -= 1;
                continue;
            }
            break;
        }
        line.contentLength = contentLength;
        NSUInteger index = line.start + contentLength;
        for (; index < line.end; index++) {
            unichar ch = chars[index];
            if (ch == '\r' && (index + 1 >= length || chars[index + 1] != '\n')) {
                unusual = YES;
            }
        }
        index = line.start;
        while (index < line.start + contentLength) {
            unichar ch = chars[index];
            if (ch == 0x85 || ch == 0x2028 || ch == 0x2029) {
                unusual = YES;
            }
            index += 1;
        }
        NSUInteger trimmed = line.start;
        while (trimmed < line.start + contentLength && (chars[trimmed] == ' ' || chars[trimmed] == '\t')) {
            trimmed += 1;
        }
        line.trimmedStart = trimmed;
        NSUInteger trimmedLength = line.start + contentLength - trimmed;

        if (insideFence) {
            line.code = OMDSourceLineFence;
            if (OMDIsFenceDelimiterAt(chars, trimmed, trimmedLength, activeFenceMarker)) {
                insideFence = NO;
                activeFenceMarker = 0;
            }
        } else if (OMDIsFenceDelimiterAt(chars, trimmed, trimmedLength, 0)) {
            insideFence = YES;
            activeFenceMarker = chars[trimmed];
            line.code = OMDSourceLineFence;
        } else {
            line.code = lineNumber < parserLineCount ? parserStyles[lineNumber] : (uint8_t)OMDSourceBlockStyleNone;
        }
        [lines appendBytes:&line length:sizeof(line)];
        cursor = line.end;
        lineNumber += 1;
    }
    free(chars);
    if (unusualBreaksOut != NULL) {
        *unusualBreaksOut = unusual;
    }
    return lines;
}

// The index of the line holding offset (the last line for the text's end).
static NSUInteger OMDSourceLineIndexForOffset(const OMDSourceLine *lines, NSUInteger count, NSUInteger offset)
{
    NSUInteger low = 0;
    NSUInteger high = count;
    while (high - low > 1) {
        NSUInteger middle = low + (high - low) / 2;
        if (lines[middle].start <= offset) {
            low = middle;
        } else {
            high = middle;
        }
    }
    return low;
}

static BOOL OMDSourceLineIsBlank(const OMDSourceLine *line)
{
    return line->trimmedStart >= line->start + line->contentLength;
}

static NSArray *OMDDisplayMathRanges(NSString *text)
{
    NSMutableArray *ranges = [NSMutableArray array];
    NSRegularExpression *regex = OMDDisplayMathRegex();
    if (regex == nil || [text length] == 0) {
        return ranges;
    }
    NSArray *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, [text length])];
    for (NSTextCheckingResult *match in matches) {
        if ([match range].length > 0) {
            [ranges addObject:[NSValue valueWithRange:[match range]]];
        }
    }
    return ranges;
}

@interface OMDSourceHighlightState ()
- (BOOL)omdHasPass;
- (NSData *)omdLines;
- (NSArray *)omdDisplayMath;
- (NSUInteger)omdLength;
- (NSRange)omdEditedRange;
- (NSInteger)omdChangeInLength;
- (void)omdRecordLines:(NSData *)lines displayMath:(NSArray *)displayMath length:(NSUInteger)length;
- (BOOL)omdColouredWithBaseColor:(NSColor *)baseColor
                 backgroundColor:(NSColor *)backgroundColor
                         options:(NSDictionary *)options;
- (void)omdRecordBaseColor:(NSColor *)baseColor
           backgroundColor:(NSColor *)backgroundColor
                   options:(NSDictionary *)options;
@end

@implementation OMDSourceHighlightState

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _editedRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}

- (void)dealloc
{
    [_lines release];
    [_displayMath release];
    [_baseColor release];
    [_backgroundColor release];
    [_options release];
    [super dealloc];
}

- (void)noteEditedRange:(NSRange)range changeInLength:(NSInteger)delta
{
    if (!_hasPass) {
        return;
    }
    if (_editedRange.location == NSNotFound) {
        _editedRange = range;
        _changeInLength = delta;
        return;
    }
    // The earlier edits, moved into the text as it is after this one. The
    // replaced text ran from range.location to replacedEnd before it.
    NSInteger replacedEnd = (NSInteger)NSMaxRange(range) - delta;
    NSInteger low = (NSInteger)_editedRange.location;
    NSInteger high = (NSInteger)NSMaxRange(_editedRange);
    if (low > (NSInteger)range.location) {
        low = low >= replacedEnd ? low + delta : (NSInteger)range.location;
    }
    if (high > (NSInteger)range.location) {
        high = high >= replacedEnd ? high + delta : (NSInteger)NSMaxRange(range);
    }
    if (low > (NSInteger)range.location) {
        low = (NSInteger)range.location;
    }
    if (high < (NSInteger)NSMaxRange(range)) {
        high = (NSInteger)NSMaxRange(range);
    }
    if (low < 0 || high < low) {
        [self reset];
        return;
    }
    _editedRange = NSMakeRange((NSUInteger)low, (NSUInteger)(high - low));
    _changeInLength += delta;
}

- (void)reset
{
    _hasPass = NO;
    [_lines release];
    _lines = nil;
    [_displayMath release];
    _displayMath = nil;
    _length = 0;
    _editedRange = NSMakeRange(NSNotFound, 0);
    _changeInLength = 0;
}

static BOOL OMDSameObject(id left, id right)
{
    return left == right || [left isEqual:right];
}

- (BOOL)omdColouredWithBaseColor:(NSColor *)baseColor
                 backgroundColor:(NSColor *)backgroundColor
                         options:(NSDictionary *)options
{
    return OMDSameObject(_baseColor, baseColor) && OMDSameObject(_backgroundColor, backgroundColor) &&
           OMDSameObject(_options, options);
}

- (void)omdRecordBaseColor:(NSColor *)baseColor
           backgroundColor:(NSColor *)backgroundColor
                   options:(NSDictionary *)options
{
    [_baseColor release];
    _baseColor = [baseColor retain];
    [_backgroundColor release];
    _backgroundColor = [backgroundColor retain];
    [_options release];
    _options = [options copy];
}

- (BOOL)omdHasPass
{
    return _hasPass;
}

- (NSData *)omdLines
{
    return _lines;
}

- (NSArray *)omdDisplayMath
{
    return _displayMath;
}

- (NSUInteger)omdLength
{
    return _length;
}

- (NSRange)omdEditedRange
{
    return _editedRange;
}

- (NSInteger)omdChangeInLength
{
    return _changeInLength;
}

- (void)omdRecordLines:(NSData *)lines displayMath:(NSArray *)displayMath length:(NSUInteger)length
{
    [_lines release];
    _lines = [lines retain];
    [_displayMath release];
    _displayMath = [displayMath retain];
    _length = length;
    _hasPass = YES;
    _editedRange = NSMakeRange(NSNotFound, 0);
    _changeInLength = 0;
}

@end

// The display math outside region, moved by shift if it's after it, or NO
// when a span crosses the region's edge.
static BOOL OMDDisplayMathOutsideRegion(NSArray *ranges, NSRange region, NSInteger shift, NSMutableArray *outside)
{
    for (NSValue *value in ranges) {
        NSRange range = [value rangeValue];
        if (NSMaxRange(range) <= region.location) {
            [outside addObject:value];
        } else if (range.location >= NSMaxRange(region)) {
            [outside addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)((NSInteger)range.location + shift),
                                                                   range.length)]];
        } else if (range.location < region.location || NSMaxRange(range) > NSMaxRange(region)) {
            return NO;
        }
    }
    return YES;
}

// The lines an incremental pass colours, given what the last pass saw: the
// edited lines widened to the blank lines around them. NO when only a full
// pass is right: no last pass, nothing to compare with, or a line outside
// those lines whose block code changed (a fence, list continuation or
// indented code from above), or display math that changed outside them.
static BOOL OMDIncrementalLines(OMDSourceHighlightState *state,
                                const OMDSourceLine *lines,
                                NSUInteger count,
                                NSUInteger length,
                                NSArray *displayMath,
                                NSUInteger *firstOut,
                                NSUInteger *lastOut,
                                BOOL *unchangedOut)
{
    *unchangedOut = NO;
    if (state == nil || ![state omdHasPass] || count == 0) {
        return NO;
    }
    NSRange edited = [state omdEditedRange];
    NSInteger delta = [state omdChangeInLength];
    if ((NSInteger)[state omdLength] + delta != (NSInteger)length) {
        return NO;
    }
    if (edited.location == NSNotFound) {
        *unchangedOut = YES;
        return YES;
    }
    if (NSMaxRange(edited) > length) {
        return NO;
    }

    NSUInteger first = OMDSourceLineIndexForOffset(lines, count, edited.location > 0 ? edited.location - 1 : 0);
    NSUInteger endOffset = NSMaxRange(edited) < length ? NSMaxRange(edited) : length - 1;
    NSUInteger last = OMDSourceLineIndexForOffset(lines, count, endOffset);
    while (first > 0) {
        first -= 1;
        if (OMDSourceLineIsBlank(&lines[first])) {
            break;
        }
    }
    while (last + 1 < count) {
        last += 1;
        if (OMDSourceLineIsBlank(&lines[last])) {
            break;
        }
    }

    NSData *oldData = [state omdLines];
    const OMDSourceLine *oldLines = (const OMDSourceLine *)[oldData bytes];
    NSUInteger oldCount = [oldData length] / sizeof(OMDSourceLine);
    NSInteger lineShift = (NSInteger)count - (NSInteger)oldCount;
    NSUInteger index = 0;
    for (; index < first; index++) {
        if (index >= oldCount || oldLines[index].start != lines[index].start ||
            oldLines[index].code != lines[index].code) {
            return NO;
        }
    }
    for (index = last + 1; index < count; index++) {
        NSInteger oldIndex = (NSInteger)index - lineShift;
        if (oldIndex < (NSInteger)first || oldIndex >= (NSInteger)oldCount ||
            (NSInteger)oldLines[oldIndex].start + delta != (NSInteger)lines[index].start ||
            oldLines[oldIndex].code != lines[index].code) {
            return NO;
        }
    }

    NSRange region = NSMakeRange(lines[first].start, lines[last].end - lines[first].start);
    NSInteger oldRegionLength = (NSInteger)region.length - delta;
    if (oldRegionLength < 0) {
        return NO;
    }
    NSMutableArray *outsideNow = [NSMutableArray array];
    NSMutableArray *outsideBefore = [NSMutableArray array];
    if (!OMDDisplayMathOutsideRegion(displayMath, region, 0, outsideNow) ||
        !OMDDisplayMathOutsideRegion([state omdDisplayMath],
                                     NSMakeRange(region.location, (NSUInteger)oldRegionLength),
                                     delta,
                                     outsideBefore) ||
        ![outsideNow isEqualToArray:outsideBefore]) {
        return NO;
    }

    *firstOut = first;
    *lastOut = last;
    return YES;
}

static BOOL OMDRangesIntersect(NSRange left, NSRange right)
{
    if (left.length == 0 || right.length == 0) {
        return NO;
    }
    return NSIntersectionRange(left, right).length > 0;
}

@implementation OMDSourceHighlighter

+ (void)omdApplyRegex:(NSRegularExpression *)regex
                color:(NSColor *)color
     attributedString:(NSMutableAttributedString *)attributedString
              inRange:(NSRange)range
{
    if (regex == nil || color == nil || attributedString == nil || range.length == 0) {
        return;
    }
    NSString *text = [attributedString string];
    if ([text length] == 0) {
        return;
    }

    NSArray *matches = [regex matchesInString:text options:0 range:range];
    for (NSTextCheckingResult *match in matches) {
        NSRange matchRange = [match range];
        if (matchRange.length == 0) {
            continue;
        }
        [attributedString addAttribute:NSForegroundColorAttributeName
                                 value:color
                                 range:matchRange];
    }
}

// Colours lines first through last (whole lines, with their endings) as a
// pass over the whole text would.
+ (void)omdColorLines:(const OMDSourceLine *)lines
                first:(NSUInteger)first
                 last:(NSUInteger)last
          displayMath:(NSArray *)displayMath
              palette:(OMDSourceHighlightPalette)palette
            baseColor:(NSColor *)baseColor
     attributedString:(NSMutableAttributedString *)attributedString
{
    NSString *text = [attributedString string];
    NSRange range = NSMakeRange(lines[first].start, lines[last].end - lines[first].start);
    if (range.length == 0) {
        return;
    }
    NSMutableArray *fencedRanges = [NSMutableArray array];

    [attributedString beginEditing];
    [attributedString addAttribute:NSForegroundColorAttributeName value:baseColor range:range];
    // Source text has no ligatures (#125): GNUstep forms "fi" from U+FB01,
    // which a monospaced font draws in one cell, so columns would shift.
    [attributedString addAttribute:NSLigatureAttributeName value:[NSNumber numberWithInt:0] range:range];

    NSUInteger index = first;
    for (; index <= last; index++) {
        const OMDSourceLine *line = &lines[index];
        if (line->contentLength == 0) {
            continue;
        }
        NSRange contentRange = NSMakeRange(line->start, line->contentLength);
        if (line->code == OMDSourceLineFence) {
            [fencedRanges addObject:[NSValue valueWithRange:contentRange]];
            continue;
        }

        OMDSourceBlockStyle effectiveStyle = (OMDSourceBlockStyle)line->code;
        NSUInteger contentEnd = NSMaxRange(contentRange);
        if (effectiveStyle == OMDSourceBlockStyleNone && line->trimmedStart < contentEnd) {
            unichar lead = [text characterAtIndex:line->trimmedStart];
            if (lead == '#' || lead == '>' || lead == '-' || lead == '+' || lead == '*' ||
                (lead >= '0' && lead <= '9')) {
                NSString *trimmed = [text substringWithRange:NSMakeRange(line->trimmedStart,
                                                                         contentEnd - line->trimmedStart)];
                if (OMDHasHeadingMarker(trimmed)) {
                    effectiveStyle = OMDSourceBlockStyleHeading;
                } else if ([trimmed hasPrefix:@">"]) {
                    effectiveStyle = OMDSourceBlockStyleBlockquote;
                } else if (OMDHasListMarker(trimmed)) {
                    effectiveStyle = OMDSourceBlockStyleList;
                }
            }
        }

        NSColor *color = nil;
        switch (effectiveStyle) {
            case OMDSourceBlockStyleHeading:
                color = palette.headingColor;
                break;
            case OMDSourceBlockStyleBlockquote:
                color = palette.blockquoteColor;
                break;
            case OMDSourceBlockStyleList:
                color = palette.listColor;
                break;
            case OMDSourceBlockStyleCode:
                color = palette.codeColor;
                break;
            case OMDSourceBlockStyleNone:
            default:
                break;
        }
        if (color != nil) {
            [attributedString addAttribute:NSForegroundColorAttributeName
                                     value:color
                                     range:contentRange];
        }
    }

    // The inline patterns don't match across a line break, so matching
    // within whole lines finds what matching the whole text would.
    [self omdApplyRegex:OMDLinkRegex()
                  color:palette.linkColor
       attributedString:attributedString
                inRange:range];
    [self omdApplyRegex:OMDBoldRegex()
                  color:palette.emphasisColor
       attributedString:attributedString
                inRange:range];
    [self omdApplyRegex:OMDItalicRegex()
                  color:palette.emphasisColor
       attributedString:attributedString
                inRange:range];
    // Display math can span lines and blocks: its spans come from the whole
    // text.
    for (NSValue *value in displayMath) {
        NSRange mathRange = NSIntersectionRange([value rangeValue], range);
        if (OMDRangesIntersect(mathRange, range)) {
            [attributedString addAttribute:NSForegroundColorAttributeName
                                     value:palette.mathColor
                                     range:mathRange];
        }
    }
    [self omdApplyRegex:OMDInlineMathRegex()
                  color:palette.mathColor
       attributedString:attributedString
                inRange:range];
    [self omdApplyRegex:OMDInlineCodeRegex()
                  color:palette.codeColor
       attributedString:attributedString
                inRange:range];

    for (NSValue *value in fencedRanges) {
        [attributedString addAttribute:NSForegroundColorAttributeName
                                 value:palette.codeColor
                                 range:[value rangeValue]];
    }
    [attributedString endEditing];
}

+ (NSRange)omdHighlightAttributedString:(NSMutableAttributedString *)attributedString
                          baseTextColor:(NSColor *)baseTextColor
                        backgroundColor:(NSColor *)backgroundColor
                                options:(NSDictionary *)options
                            targetRange:(NSRange)targetRange
                                  state:(OMDSourceHighlightState *)state
{
    NSRange none = NSMakeRange(NSNotFound, 0);
    if (attributedString == nil) {
        return none;
    }
    NSUInteger length = [attributedString length];
    if (length == 0) {
        [state omdRecordLines:[NSData data] displayMath:[NSArray array] length:0];
        return none;
    }

    NSColor *baseColor = baseTextColor != nil ? baseTextColor : [NSColor textColor];
    if (baseColor == nil) {
        baseColor = [NSColor blackColor];
    }

    BOOL highContrast = NO;
    if ([[options objectForKey:OMDSourceHighlighterOptionHighContrast] respondsToSelector:@selector(boolValue)]) {
        highContrast = [[options objectForKey:OMDSourceHighlighterOptionHighContrast] boolValue];
    }
    NSColor *accentColor = [options objectForKey:OMDSourceHighlighterOptionAccentColor];
    if (accentColor != nil && ![accentColor isKindOfClass:[NSColor class]]) {
        accentColor = nil;
    }

    OMDSourceHighlightPalette palette = OMDPaletteForBackground(backgroundColor, highContrast, accentColor);

    NSString *text = [attributedString string];
    NSData *parserLineStyles = OMDParserBackedLineStyles(text);
    BOOL unusualBreaks = NO;
    NSData *lineData = OMDSourceLinesForText(text, parserLineStyles, &unusualBreaks);
    const OMDSourceLine *lines = (const OMDSourceLine *)[lineData bytes];
    NSUInteger count = [lineData length] / sizeof(OMDSourceLine);
    if (count == 0) {
        [state reset];
        return none;
    }
    NSArray *displayMath = OMDDisplayMathRanges(text);

    NSUInteger first = 0;
    NSUInteger last = count - 1;
    if (targetRange.location != NSNotFound) {
        // A caller's own range: whole lines, and nothing to compare with
        // next time.
        NSUInteger location = targetRange.location < length ? targetRange.location : length - 1;
        NSUInteger end = NSMaxRange(targetRange) > location ? NSMaxRange(targetRange) - 1 : location;
        if (end >= length) {
            end = length - 1;
        }
        first = OMDSourceLineIndexForOffset(lines, count, location);
        last = OMDSourceLineIndexForOffset(lines, count, end);
        [state reset];
    } else if (state != nil) {
        if (![state omdColouredWithBaseColor:baseTextColor backgroundColor:backgroundColor options:options]) {
            [state reset];
            [state omdRecordBaseColor:baseTextColor backgroundColor:backgroundColor options:options];
        }
        BOOL unchanged = NO;
        NSUInteger incrementalFirst = 0;
        NSUInteger incrementalLast = 0;
        if (!unusualBreaks &&
            OMDIncrementalLines(state, lines, count, length, displayMath,
                                &incrementalFirst, &incrementalLast, &unchanged)) {
            if (unchanged) {
                [state omdRecordLines:lineData displayMath:displayMath length:length];
                return none;
            }
            first = incrementalFirst;
            last = incrementalLast;
        }
        [state omdRecordLines:lineData displayMath:displayMath length:length];
    }

    [self omdColorLines:lines
                  first:first
                   last:last
            displayMath:displayMath
                palette:palette
              baseColor:baseColor
       attributedString:attributedString];
    return NSMakeRange(lines[first].start, lines[last].end - lines[first].start);
}

+ (void)highlightTextStorage:(NSTextStorage *)textStorage
               baseTextColor:(NSColor *)baseTextColor
             backgroundColor:(NSColor *)backgroundColor
{
    [self highlightTextStorage:textStorage
                 baseTextColor:baseTextColor
               backgroundColor:backgroundColor
                       options:nil
                   targetRange:NSMakeRange(NSNotFound, 0)];
}

+ (void)highlightTextStorage:(NSTextStorage *)textStorage
               baseTextColor:(NSColor *)baseTextColor
             backgroundColor:(NSColor *)backgroundColor
                     options:(NSDictionary *)options
                 targetRange:(NSRange)targetRange
{
    if (textStorage == nil) {
        return;
    }
    [self omdHighlightAttributedString:textStorage
                         baseTextColor:baseTextColor
                       backgroundColor:backgroundColor
                               options:options
                           targetRange:targetRange
                                 state:nil];
}

+ (NSRange)highlightTextStorage:(NSTextStorage *)textStorage
                  baseTextColor:(NSColor *)baseTextColor
                backgroundColor:(NSColor *)backgroundColor
                        options:(NSDictionary *)options
                          state:(OMDSourceHighlightState *)state
{
    return [self omdHighlightAttributedString:textStorage
                                baseTextColor:baseTextColor
                              backgroundColor:backgroundColor
                                      options:options
                                  targetRange:NSMakeRange(NSNotFound, 0)
                                        state:state];
}

+ (void)highlightAttributedString:(NSMutableAttributedString *)attributedString
                    baseTextColor:(NSColor *)baseTextColor
                  backgroundColor:(NSColor *)backgroundColor
{
    [self highlightAttributedString:attributedString
                      baseTextColor:baseTextColor
                    backgroundColor:backgroundColor
                            options:nil
                        targetRange:NSMakeRange(NSNotFound, 0)];
}

+ (void)highlightAttributedString:(NSMutableAttributedString *)attributedString
                    baseTextColor:(NSColor *)baseTextColor
                  backgroundColor:(NSColor *)backgroundColor
                          options:(NSDictionary *)options
                      targetRange:(NSRange)targetRange
{
    [self omdHighlightAttributedString:attributedString
                         baseTextColor:baseTextColor
                       backgroundColor:backgroundColor
                               options:options
                           targetRange:targetRange
                                 state:nil];
}

@end
