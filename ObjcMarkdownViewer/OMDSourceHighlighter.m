// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSourceHighlighter.h"

#include <cmark.h>

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

static NSString *OMDTrimLeadingWhitespace(NSString *line)
{
    if (line == nil || [line length] == 0) {
        return @"";
    }
    NSUInteger length = [line length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [line characterAtIndex:index];
        if (ch == ' ' || ch == '\t') {
            index += 1;
            continue;
        }
        break;
    }
    return (index > 0) ? [line substringFromIndex:index] : line;
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

static BOOL OMDIsFenceDelimiter(NSString *trimmed, unichar marker)
{
    if (trimmed == nil || [trimmed length] < 3) {
        return NO;
    }
    if (marker != '`' && marker != '~') {
        marker = [trimmed characterAtIndex:0];
    }
    if (marker != '`' && marker != '~') {
        return NO;
    }

    NSUInteger run = 0;
    NSUInteger length = [trimmed length];
    while (run < length && [trimmed characterAtIndex:run] == marker) {
        run += 1;
    }
    return run >= 3;
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

static void OMDSetLineStyle(NSMutableDictionary *lineStyles,
                            NSUInteger lineNumber,
                            OMDSourceBlockStyle style)
{
    if (lineStyles == nil || lineNumber == 0 || style == OMDSourceBlockStyleNone) {
        return;
    }

    NSNumber *key = [NSNumber numberWithUnsignedInteger:lineNumber];
    NSNumber *existing = [lineStyles objectForKey:key];
    OMDSourceBlockStyle existingStyle = existing != nil ? (OMDSourceBlockStyle)[existing unsignedIntegerValue]
                                                        : OMDSourceBlockStyleNone;
    if (OMDSourceBlockStylePriority(existingStyle) >= OMDSourceBlockStylePriority(style)) {
        return;
    }

    [lineStyles setObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)style] forKey:key];
}

static void OMDApplyNodeStyleToLines(cmark_node *node,
                                     NSMutableDictionary *lineStyles,
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
                                       NSMutableDictionary *lineStyles,
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

static NSDictionary *OMDParserBackedLineStyles(NSString *markdown)
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

    cmark_node *document = cmark_parse_document((const char *)[utf8 bytes],
                                                (size_t)[utf8 length],
                                                CMARK_OPT_DEFAULT | CMARK_OPT_SOURCEPOS);
    if (document == NULL) {
        return nil;
    }

    NSMutableDictionary *lineStyles = [NSMutableDictionary dictionary];
    cmark_node *rootChild = cmark_node_first_child(document);
    if (rootChild != NULL) {
        OMDCollectParserLineStyles(rootChild, lineStyles, NO, NO, NO);
    }
    cmark_node_free(document);

    return lineStyles;
}

static NSRange OMDNormalizedTargetRange(NSRange targetRange, NSUInteger totalLength)
{
    if (totalLength == 0) {
        return NSMakeRange(0, 0);
    }

    if (targetRange.location == NSNotFound) {
        return NSMakeRange(0, totalLength);
    }

    NSUInteger location = targetRange.location;
    if (location > totalLength) {
        location = totalLength;
    }

    NSUInteger length = targetRange.length;
    if (length == 0 && location < totalLength) {
        length = 1;
    }
    if (length > (totalLength - location)) {
        length = totalLength - location;
    }
    return NSMakeRange(location, length);
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
    [self highlightAttributedString:(NSMutableAttributedString *)textStorage
                      baseTextColor:baseTextColor
                    backgroundColor:backgroundColor
                            options:options
                        targetRange:targetRange];
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
    if (attributedString == nil) {
        return;
    }
    NSUInteger length = [attributedString length];
    if (length == 0) {
        return;
    }

    NSRange effectiveRange = OMDNormalizedTargetRange(targetRange, length);
    if (effectiveRange.length == 0) {
        return;
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
    NSDictionary *parserLineStyles = OMDParserBackedLineStyles(text);
    NSMutableArray *fencedRanges = [NSMutableArray array];

    [attributedString beginEditing];
    [attributedString addAttribute:NSForegroundColorAttributeName value:baseColor range:effectiveRange];

    BOOL insideFence = NO;
    unichar activeFenceMarker = 0;
    NSUInteger cursor = 0;
    NSUInteger lineNumber = 1;
    while (cursor < length) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(cursor, 0)];
        NSUInteger lineStart = lineRange.location;
        NSUInteger contentLength = lineRange.length;

        while (contentLength > 0) {
            unichar ch = [text characterAtIndex:lineStart + contentLength - 1];
            if (ch == '\n' || ch == '\r') {
                contentLength -= 1;
                continue;
            }
            break;
        }

        NSRange contentRange = NSMakeRange(lineStart, contentLength);
        BOOL shouldColorLine = OMDRangesIntersect(contentRange, effectiveRange);

        NSString *line = [text substringWithRange:contentRange];
        NSString *trimmed = OMDTrimLeadingWhitespace(line);

        OMDSourceBlockStyle parserStyle = OMDSourceBlockStyleNone;
        NSNumber *styleValue = [parserLineStyles objectForKey:[NSNumber numberWithUnsignedInteger:lineNumber]];
        if (styleValue != nil) {
            parserStyle = (OMDSourceBlockStyle)[styleValue unsignedIntegerValue];
        }

        if (insideFence) {
            if (shouldColorLine) {
                [fencedRanges addObject:[NSValue valueWithRange:contentRange]];
            }
            if (OMDIsFenceDelimiter(trimmed, activeFenceMarker)) {
                insideFence = NO;
                activeFenceMarker = 0;
            }
            cursor = NSMaxRange(lineRange);
            lineNumber += 1;
            continue;
        }

        if (OMDIsFenceDelimiter(trimmed, 0)) {
            insideFence = YES;
            activeFenceMarker = [trimmed characterAtIndex:0];
            if (shouldColorLine) {
                [fencedRanges addObject:[NSValue valueWithRange:contentRange]];
            }
            cursor = NSMaxRange(lineRange);
            lineNumber += 1;
            continue;
        }

        OMDSourceBlockStyle effectiveStyle = parserStyle;
        if (effectiveStyle == OMDSourceBlockStyleNone) {
            if (OMDHasHeadingMarker(trimmed)) {
                effectiveStyle = OMDSourceBlockStyleHeading;
            } else if ([trimmed hasPrefix:@">"]) {
                effectiveStyle = OMDSourceBlockStyleBlockquote;
            } else if (OMDHasListMarker(trimmed)) {
                effectiveStyle = OMDSourceBlockStyleList;
            }
        }

        if (shouldColorLine && contentRange.length > 0) {
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

        cursor = NSMaxRange(lineRange);
        lineNumber += 1;
    }

    [self omdApplyRegex:OMDLinkRegex()
                  color:palette.linkColor
       attributedString:attributedString
                inRange:effectiveRange];
    [self omdApplyRegex:OMDBoldRegex()
                  color:palette.emphasisColor
       attributedString:attributedString
                inRange:effectiveRange];
    [self omdApplyRegex:OMDItalicRegex()
                  color:palette.emphasisColor
       attributedString:attributedString
                inRange:effectiveRange];
    [self omdApplyRegex:OMDDisplayMathRegex()
                  color:palette.mathColor
       attributedString:attributedString
                inRange:effectiveRange];
    [self omdApplyRegex:OMDInlineMathRegex()
                  color:palette.mathColor
       attributedString:attributedString
                inRange:effectiveRange];
    [self omdApplyRegex:OMDInlineCodeRegex()
                  color:palette.codeColor
       attributedString:attributedString
                inRange:effectiveRange];

    for (NSValue *value in fencedRanges) {
        NSRange range = [value rangeValue];
        if (range.length == 0) {
            continue;
        }
        [attributedString addAttribute:NSForegroundColorAttributeName
                                 value:palette.codeColor
                                 range:range];
    }
    [attributedString endEditing];
}

@end
