// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// A safe subset of inline and block HTML, as GitHub READMEs use it:
// emphasis, code and keyboard keys, super- and subscripts, links, images
// with a width, line breaks, centred paragraphs, headings, lists, details
// and summaries, rules and simple tables. Nothing runs: scripts, styles
// and embedded content are dropped, other tags are dropped and their text
// kept, comments go.

#import "OMMarkdownRendererInternal.h"
#import "OMFontSupport.h"

#include <math.h>

NSString * const OMHTMLStyleStackAttributeName = @"OMHTMLStyleStack";

// ---------------------------------------------------------------- tokens

typedef void (^OMHTMLTextHandler)(NSString *text);
typedef void (^OMHTMLTagHandler)(NSString *name, BOOL closing, BOOL selfClosing,
                                 NSDictionary *attributes, NSString *raw);

static BOOL OMHTMLIsNameStart(unichar ch)
{
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

static BOOL OMHTMLIsNameCharacter(unichar ch)
{
    return OMHTMLIsNameStart(ch) || (ch >= '0' && ch <= '9') || ch == '-' || ch == ':' || ch == '_';
}

static BOOL OMHTMLIsSpace(unichar ch)
{
    return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\f';
}

// Splits html into text and tags; comments, doctypes and processing
// instructions are skipped. A "<" that starts no tag is text.
static void OMEnumerateHTML(NSString *html, OMHTMLTextHandler onText, OMHTMLTagHandler onTag)
{
    NSUInteger length = [html length];
    NSUInteger index = 0;
    NSUInteger textStart = 0;
    while (index < length) {
        if ([html characterAtIndex:index] != '<') {
            index += 1;
            continue;
        }
        NSUInteger tagStart = index;
        NSUInteger end = NSNotFound;
        if ([html length] >= index + 4 && [[html substringWithRange:NSMakeRange(index, 4)] isEqualToString:@"<!--"]) {
            NSRange close = [html rangeOfString:@"-->" options:0 range:NSMakeRange(index + 4, length - index - 4)];
            end = close.location == NSNotFound ? length : NSMaxRange(close);
            if (tagStart > textStart) {
                onText([html substringWithRange:NSMakeRange(textStart, tagStart - textStart)]);
            }
            index = end;
            textStart = end;
            continue;
        }
        if (index + 1 < length && ([html characterAtIndex:index + 1] == '!' || [html characterAtIndex:index + 1] == '?')) {
            NSRange close = [html rangeOfString:@">" options:0 range:NSMakeRange(index, length - index)];
            end = close.location == NSNotFound ? length : NSMaxRange(close);
            if (tagStart > textStart) {
                onText([html substringWithRange:NSMakeRange(textStart, tagStart - textStart)]);
            }
            index = end;
            textStart = end;
            continue;
        }

        NSUInteger cursor = index + 1;
        BOOL closing = NO;
        if (cursor < length && [html characterAtIndex:cursor] == '/') {
            closing = YES;
            cursor += 1;
        }
        if (cursor >= length || !OMHTMLIsNameStart([html characterAtIndex:cursor])) {
            index += 1;
            continue;
        }
        NSUInteger nameStart = cursor;
        while (cursor < length && OMHTMLIsNameCharacter([html characterAtIndex:cursor])) {
            cursor += 1;
        }
        NSString *name = [[html substringWithRange:NSMakeRange(nameStart, cursor - nameStart)] lowercaseString];
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        BOOL selfClosing = NO;
        BOOL complete = NO;
        while (cursor < length) {
            unichar ch = [html characterAtIndex:cursor];
            if (OMHTMLIsSpace(ch)) {
                cursor += 1;
                continue;
            }
            if (ch == '>') {
                cursor += 1;
                complete = YES;
                break;
            }
            if (ch == '/') {
                selfClosing = YES;
                cursor += 1;
                continue;
            }
            if (!OMHTMLIsNameCharacter(ch)) {
                cursor += 1;
                continue;
            }
            NSUInteger attributeStart = cursor;
            while (cursor < length && OMHTMLIsNameCharacter([html characterAtIndex:cursor])) {
                cursor += 1;
            }
            NSString *attributeName = [[html substringWithRange:NSMakeRange(attributeStart, cursor - attributeStart)] lowercaseString];
            while (cursor < length && OMHTMLIsSpace([html characterAtIndex:cursor])) {
                cursor += 1;
            }
            NSString *value = @"";
            if (cursor < length && [html characterAtIndex:cursor] == '=') {
                cursor += 1;
                while (cursor < length && OMHTMLIsSpace([html characterAtIndex:cursor])) {
                    cursor += 1;
                }
                if (cursor < length && ([html characterAtIndex:cursor] == '"' || [html characterAtIndex:cursor] == '\'')) {
                    unichar quote = [html characterAtIndex:cursor];
                    NSUInteger valueStart = cursor + 1;
                    NSUInteger valueEnd = valueStart;
                    while (valueEnd < length && [html characterAtIndex:valueEnd] != quote) {
                        valueEnd += 1;
                    }
                    value = [html substringWithRange:NSMakeRange(valueStart, valueEnd - valueStart)];
                    cursor = valueEnd < length ? valueEnd + 1 : length;
                } else {
                    NSUInteger valueStart = cursor;
                    while (cursor < length && !OMHTMLIsSpace([html characterAtIndex:cursor]) &&
                           [html characterAtIndex:cursor] != '>') {
                        cursor += 1;
                    }
                    value = [html substringWithRange:NSMakeRange(valueStart, cursor - valueStart)];
                }
            }
            [attributes setObject:value forKey:attributeName];
        }
        if (!complete) {
            index += 1;
            continue;
        }
        if (tagStart > textStart) {
            onText([html substringWithRange:NSMakeRange(textStart, tagStart - textStart)]);
        }
        onTag(name, closing, selfClosing, attributes, [html substringWithRange:NSMakeRange(tagStart, cursor - tagStart)]);
        index = cursor;
        textStart = cursor;
    }
    if (textStart < length) {
        onText([html substringFromIndex:textStart]);
    }
}

// "&amp;", "&#169;", "&#xA9;" and the common named entities, decoded.
NSString *OMHTMLDecodeEntities(NSString *text)
{
    if ([text rangeOfString:@"&"].location == NSNotFound) {
        return text;
    }
    static NSDictionary *named = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        named = [[NSDictionary alloc] initWithObjectsAndKeys:
                 @"&", @"amp", @"<", @"lt", @">", @"gt", @"\"", @"quot", @"'", @"apos",
                 @" ", @"nbsp", @"©", @"copy", @"®", @"reg", @"™", @"trade",
                 @"…", @"hellip", @"—", @"mdash", @"–", @"ndash", @"«", @"laquo",
                 @"»", @"raquo", @"‘", @"lsquo", @"’", @"rsquo", @"“", @"ldquo",
                 @"”", @"rdquo", @"•", @"bull", @"·", @"middot", @"×", @"times",
                 @"→", @"rarr", @"←", @"larr", @"°", @"deg", nil];
    });
    NSMutableString *result = [NSMutableString stringWithCapacity:[text length]];
    NSUInteger length = [text length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [text characterAtIndex:index];
        if (ch != '&') {
            [result appendFormat:@"%C", ch];
            index += 1;
            continue;
        }
        NSRange semicolon = [text rangeOfString:@";" options:0
                                          range:NSMakeRange(index, MIN(length - index, (NSUInteger)12))];
        if (semicolon.location == NSNotFound) {
            [result appendString:@"&"];
            index += 1;
            continue;
        }
        NSString *entity = [text substringWithRange:NSMakeRange(index + 1, semicolon.location - index - 1)];
        NSString *replacement = nil;
        if ([entity hasPrefix:@"#x"] || [entity hasPrefix:@"#X"]) {
            unsigned int value = 0;
            if ([[NSScanner scannerWithString:[entity substringFromIndex:2]] scanHexInt:&value] && value > 0 && value < 0x110000) {
                replacement = value < 0x10000
                    ? [NSString stringWithFormat:@"%C", (unichar)value]
                    : [[[NSString alloc] initWithBytes:&value length:4 encoding:NSUTF32LittleEndianStringEncoding] autorelease];
            }
        } else if ([entity hasPrefix:@"#"]) {
            NSInteger value = [[entity substringFromIndex:1] integerValue];
            if (value > 0 && value < 0x110000) {
                uint32_t scalar = (uint32_t)value;
                replacement = value < 0x10000
                    ? [NSString stringWithFormat:@"%C", (unichar)value]
                    : [[[NSString alloc] initWithBytes:&scalar length:4 encoding:NSUTF32LittleEndianStringEncoding] autorelease];
            }
        } else {
            replacement = [named objectForKey:entity];
        }
        if (replacement != nil) {
            [result appendString:replacement];
            index = NSMaxRange(semicolon);
        } else {
            [result appendString:@"&"];
            index += 1;
        }
    }
    return result;
}

// ---------------------------------------------------------------- styles

// An opened tag's changes to the attributes, with what they replaced, so
// its closing tag puts them back. The stack is a private attribute the
// renderer removes from its output at the end.
static void OMHTMLPushStyle(NSMutableDictionary *attributes, NSString *tag, NSDictionary *changes)
{
    NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithCapacity:[changes count]];
    for (id key in changes) {
        id previous = [attributes objectForKey:key];
        [saved setObject:(previous != nil ? previous : [NSNull null]) forKey:key];
        id value = [changes objectForKey:key];
        if (value == [NSNull null]) {
            [attributes removeObjectForKey:key];
        } else {
            [attributes setObject:value forKey:key];
        }
    }
    NSArray *stack = [attributes objectForKey:OMHTMLStyleStackAttributeName];
    NSMutableArray *next = stack != nil ? [[stack mutableCopy] autorelease] : [NSMutableArray array];
    [next addObject:[NSDictionary dictionaryWithObjectsAndKeys:tag, @"tag", saved, @"saved", nil]];
    [attributes setObject:[NSArray arrayWithArray:next] forKey:OMHTMLStyleStackAttributeName];
}

static void OMHTMLPopStyle(NSMutableDictionary *attributes, NSString *tag)
{
    NSArray *stack = [attributes objectForKey:OMHTMLStyleStackAttributeName];
    NSInteger index = (NSInteger)[stack count] - 1;
    while (index >= 0 && ![[[stack objectAtIndex:(NSUInteger)index] objectForKey:@"tag"] isEqualToString:tag]) {
        index -= 1;
    }
    if (index < 0) {
        return;
    }
    NSInteger top = (NSInteger)[stack count] - 1;
    for (; top >= index; top--) {
        NSDictionary *saved = [[stack objectAtIndex:(NSUInteger)top] objectForKey:@"saved"];
        for (id key in saved) {
            id value = [saved objectForKey:key];
            if (value == [NSNull null]) {
                [attributes removeObjectForKey:key];
            } else {
                [attributes setObject:value forKey:key];
            }
        }
    }
    if (index == 0) {
        [attributes removeObjectForKey:OMHTMLStyleStackAttributeName];
    } else {
        [attributes setObject:[stack subarrayWithRange:NSMakeRange(0, (NSUInteger)index)]
                       forKey:OMHTMLStyleStackAttributeName];
    }
}

static NSFont *OMHTMLFontResized(NSFont *font, CGFloat factor)
{
    if (font == nil) {
        return nil;
    }
    NSFont *resized = OMFontAtSize(font, MAX(6.0, floor([font pointSize] * factor + 0.5)));
    return resized != nil ? resized : font;
}

// The changes an inline tag makes to attributes, or nil if it isn't one.
static NSDictionary *OMHTMLInlineStyleChanges(NSString *name,
                                              NSDictionary *tagAttributes,
                                              NSDictionary *attributes,
                                              OMTheme *theme,
                                              CGFloat scale,
                                              const OMRenderContext *renderContext)
{
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : 14.0 * scale;
    if ([name isEqualToString:@"b"] || [name isEqualToString:@"strong"]) {
        NSFont *bold = OMFontWithTraits(font, NSBoldFontMask);
        return bold != nil ? [NSDictionary dictionaryWithObject:bold forKey:NSFontAttributeName] : [NSDictionary dictionary];
    }
    if ([name isEqualToString:@"i"] || [name isEqualToString:@"em"] || [name isEqualToString:@"cite"] ||
        [name isEqualToString:@"var"] || [name isEqualToString:@"dfn"]) {
        NSFont *italic = OMFontWithTraits(font, NSItalicFontMask);
        return italic != nil ? [NSDictionary dictionaryWithObject:italic forKey:NSFontAttributeName] : [NSDictionary dictionary];
    }
    if ([name isEqualToString:@"code"] || [name isEqualToString:@"kbd"] || [name isEqualToString:@"samp"] ||
        [name isEqualToString:@"tt"]) {
        NSDictionary *code = [theme codeAttributesForSize:size];
        return code != nil ? code : [NSDictionary dictionary];
    }
    if ([name isEqualToString:@"u"] || [name isEqualToString:@"ins"]) {
        return [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
                                           forKey:NSUnderlineStyleAttributeName];
    }
    if ([name isEqualToString:@"sup"] || [name isEqualToString:@"sub"]) {
        BOOL up = [name isEqualToString:@"sup"];
        NSMutableDictionary *changes = [NSMutableDictionary dictionary];
        NSFont *small = OMHTMLFontResized(font, 0.75);
        if (small != nil) {
            [changes setObject:small forKey:NSFontAttributeName];
        }
        // NSSuperscriptAttributeName, not a baseline offset: GNUstep applies
        // NSBaselineOffsetAttributeName upside down.
        [changes setObject:[NSNumber numberWithInt:(up ? 1 : -1)] forKey:NSSuperscriptAttributeName];
        return changes;
    }
    if ([name isEqualToString:@"small"]) {
        NSFont *small = OMHTMLFontResized(font, 0.85);
        return small != nil ? [NSDictionary dictionaryWithObject:small forKey:NSFontAttributeName] : [NSDictionary dictionary];
    }
    if ([name isEqualToString:@"mark"]) {
        return [NSDictionary dictionaryWithObject:[NSColor colorWithCalibratedRed:1.0 green:0.92 blue:0.55 alpha:1.0]
                                           forKey:NSBackgroundColorAttributeName];
    }
    if ([name isEqualToString:@"a"]) {
        NSString *href = [tagAttributes objectForKey:@"href"];
        NSURL *url = [href length] > 0 ? OMResolvedLinkURL(href, renderContext) : nil;
        if (url == nil) {
            return [NSDictionary dictionary];
        }
        NSMutableDictionary *changes = [NSMutableDictionary dictionaryWithObject:url forKey:NSLinkAttributeName];
        if (theme.linkColor != nil) {
            [changes setObject:theme.linkColor forKey:NSForegroundColorAttributeName];
        }
        NSString *title = [tagAttributes objectForKey:@"title"];
        [changes setObject:([title length] > 0 ? title : href) forKey:NSToolTipAttributeName];
        return changes;
    }
    if ([name isEqualToString:@"span"] || [name isEqualToString:@"font"] || [name isEqualToString:@"abbr"] ||
        [name isEqualToString:@"q"] || [name isEqualToString:@"time"] || [name isEqualToString:@"bdi"] ||
        [name isEqualToString:@"bdo"] || [name isEqualToString:@"wbr"] || [name isEqualToString:@"data"]) {
        return [NSDictionary dictionary];
    }
    return nil;
}

static BOOL OMHTMLIsHiddenTag(NSString *name)
{
    static NSSet *hidden = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hidden = [[NSSet alloc] initWithObjects:@"script", @"style", @"template", @"textarea", @"iframe",
                  @"object", @"embed", @"noscript", @"head", @"title", @"svg", @"math", @"select",
                  @"button", @"form", @"canvas", @"audio", @"video", nil];
    });
    return [hidden containsObject:name];
}

static BOOL OMHTMLIsVoidTag(NSString *name)
{
    return [name isEqualToString:@"br"] || [name isEqualToString:@"img"] || [name isEqualToString:@"hr"] ||
           [name isEqualToString:@"input"] || [name isEqualToString:@"meta"] || [name isEqualToString:@"link"] ||
           [name isEqualToString:@"source"] || [name isEqualToString:@"wbr"] || [name isEqualToString:@"col"];
}

// ---------------------------------------------------------------- objects

static void OMHTMLAppendLineBreak(NSMutableAttributedString *output, NSDictionary *attributes)
{
    NSMutableDictionary *breakAttributes = [[attributes mutableCopy] autorelease];
    [breakAttributes setObject:[NSNumber numberWithBool:YES] forKey:OMHardLineBreakAttributeName];
    OMAppendString(output, @"\n", breakAttributes);
}

static CGFloat OMHTMLLength(NSString *value)
{
    if ([value length] == 0 || [value hasSuffix:@"%"]) {
        return 0.0;
    }
    double number = [value doubleValue];
    return number > 0.0 ? (CGFloat)number : 0.0;
}

// <img>: the image, scaled down to its width (or height) if it has one,
// or its alt text.
static void OMHTMLAppendImage(NSDictionary *tagAttributes,
                              NSString *raw,
                              NSMutableAttributedString *output,
                              NSDictionary *attributes,
                              CGFloat scale,
                              const OMRenderContext *renderContext)
{
    NSString *src = [tagAttributes objectForKey:@"src"];
    NSString *alt = OMHTMLDecodeEntities([tagAttributes objectForKey:@"alt"] != nil ? [tagAttributes objectForKey:@"alt"] : @"");
    NSAttributedString *image = nil;
    if ([src length] > 0 && OMShouldRenderImages(renderContext)) {
        image = OMImageAttachmentForURLString(OMHTMLDecodeEntities(src),
                                              [[attributes mutableCopy] autorelease],
                                              scale,
                                              renderContext);
    }
    if (image == nil) {
        if ([alt length] > 0) {
            OMAppendString(output, alt, attributes);
        }
        return;
    }
    NSTextAttachment *attachment = [image attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL];
    NSSize size = [(NSTextAttachmentCell *)[attachment attachmentCell] cellSize];
    CGFloat width = OMHTMLLength([tagAttributes objectForKey:@"width"]) * scale;
    CGFloat height = OMHTMLLength([tagAttributes objectForKey:@"height"]) * scale;
    if (width <= 0.0 && height > 0.0 && size.height > 0.0) {
        width = size.width * height / size.height;
    }
    if (width > 0.0) {
        image = OMAttributedStringFittingImagesToWidth(image, floor(width));
    }
    NSUInteger start = [output length];
    OMAppendAttributedSegment(output, image);
    NSString *title = [tagAttributes objectForKey:@"title"];
    NSString *toolTip = [title length] > 0 ? OMHTMLDecodeEntities(title) : ([alt length] > 0 ? alt : nil);
    if (toolTip != nil && [output length] > start) {
        [output addAttribute:NSToolTipAttributeName value:toolTip range:NSMakeRange(start, [output length] - start)];
    }
    OMTagAppendedObject(output, start, OMRenderedObjectKindImage, raw, nil);
}

// The tags that work the same inline and in a block. Returns NO for one
// it leaves to the caller.
static BOOL OMHTMLApplyCommonTag(NSString *name,
                                 BOOL closing,
                                 NSDictionary *tagAttributes,
                                 NSString *raw,
                                 NSMutableAttributedString *output,
                                 NSMutableDictionary *attributes,
                                 OMTheme *theme,
                                 CGFloat scale,
                                 const OMRenderContext *renderContext)
{
    if ([name isEqualToString:@"br"]) {
        if (!closing) {
            OMHTMLAppendLineBreak(output, attributes);
        }
        return YES;
    }
    if ([name isEqualToString:@"img"]) {
        if (!closing) {
            OMHTMLAppendImage(tagAttributes, raw, output, attributes, scale, renderContext);
        }
        return YES;
    }
    if (closing) {
        if (OMHTMLInlineStyleChanges(name, tagAttributes, attributes, theme, scale, renderContext) != nil) {
            OMHTMLPopStyle(attributes, name);
            return YES;
        }
        return NO;
    }
    NSDictionary *changes = OMHTMLInlineStyleChanges(name, tagAttributes, attributes, theme, scale, renderContext);
    if (changes == nil) {
        return NO;
    }
    if (!OMHTMLIsVoidTag(name)) {
        OMHTMLPushStyle(attributes, name, changes);
    }
    return YES;
}

// ---------------------------------------------------------------- inline

// One inline HTML node: cmark hands each tag over on its own, so an opened
// style applies to the inline siblings that follow until its closing tag.
void OMAppendSafeInlineHTML(NSString *html,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            OMTheme *theme,
                            CGFloat scale,
                            const OMRenderContext *renderContext)
{
    OMEnumerateHTML(html,
                    ^(NSString *text) {
                        OMAppendString(output, OMHTMLDecodeEntities(text), attributes);
                    },
                    ^(NSString *name, BOOL closing, BOOL selfClosing, NSDictionary *tagAttributes, NSString *raw) {
                        (void)selfClosing;
                        OMHTMLApplyCommonTag(name, closing, tagAttributes, raw, output, attributes, theme, scale, renderContext);
                    });
}

// ---------------------------------------------------------------- blocks

static BOOL OMHTMLOutputAtLineStart(NSMutableAttributedString *output, NSUInteger blockStart)
{
    NSUInteger length = [output length];
    return length == blockStart || [[output string] characterAtIndex:length - 1] == '\n';
}

static void OMHTMLEndLine(NSMutableAttributedString *output, NSDictionary *attributes, NSUInteger blockStart)
{
    if (!OMHTMLOutputAtLineStart(output, blockStart)) {
        OMAppendString(output, @"\n", attributes);
    }
}

static NSDictionary *OMHTMLAlignmentChanges(NSString *name, NSDictionary *tagAttributes, NSDictionary *attributes)
{
    NSString *align = [[tagAttributes objectForKey:@"align"] lowercaseString];
    if ([name isEqualToString:@"center"]) {
        align = @"center";
    }
    NSTextAlignment alignment;
    if ([align isEqualToString:@"center"]) {
        alignment = NSCenterTextAlignment;
    } else if ([align isEqualToString:@"right"]) {
        alignment = NSRightTextAlignment;
    } else if ([align isEqualToString:@"left"]) {
        alignment = NSLeftTextAlignment;
    } else {
        return [NSDictionary dictionary];
    }
    NSParagraphStyle *current = [attributes objectForKey:NSParagraphStyleAttributeName];
    NSMutableParagraphStyle *style = current != nil ? [[current mutableCopy] autorelease]
                                                    : [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setAlignment:alignment];
    return [NSDictionary dictionaryWithObject:style forKey:NSParagraphStyleAttributeName];
}

static BOOL OMHTMLIsBlockTag(NSString *name)
{
    static NSSet *blocks = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blocks = [[NSSet alloc] initWithObjects:@"p", @"div", @"center", @"section", @"article", @"header",
                  @"footer", @"main", @"nav", @"aside", @"figure", @"figcaption", @"picture", @"address",
                  @"blockquote", @"details", @"dl", @"dt", @"dd", @"pre", @"caption", nil];
    });
    return [blocks containsObject:name];
}

// An HTML block, laid out as paragraphs: text with its whitespace collapsed,
// the inline tags above, and the block tags GitHub READMEs use.
void OMAppendSafeBlockHTML(NSString *html,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *blockAttributes,
                           OMTheme *theme,
                           CGFloat scale,
                           const OMRenderContext *renderContext)
{
    NSMutableDictionary *attributes = [[blockAttributes mutableCopy] autorelease];
    NSUInteger blockStart = [output length];
    __block NSUInteger hiddenDepth = 0;
    __block NSUInteger preDepth = 0;
    NSMutableArray *lists = [NSMutableArray array];       // per open list: counter (0 for bullets)
    NSMutableArray *cellsInRow = [NSMutableArray array];   // per open row: cells so far
    CGFloat layoutWidth = renderContext != NULL ? renderContext->layoutWidth : 0.0;

    OMEnumerateHTML(html,
        ^(NSString *text) {
            if (hiddenDepth > 0) {
                return;
            }
            NSString *decoded = OMHTMLDecodeEntities(text);
            if (preDepth == 0) {
                NSMutableString *collapsed = [NSMutableString stringWithCapacity:[decoded length]];
                BOOL lastSpace = OMHTMLOutputAtLineStart(output, blockStart) ||
                                 ([output length] > blockStart && [[output string] characterAtIndex:[output length] - 1] == ' ');
                NSUInteger i = 0;
                for (; i < [decoded length]; i++) {
                    unichar ch = [decoded characterAtIndex:i];
                    if (OMHTMLIsSpace(ch)) {
                        if (!lastSpace) {
                            [collapsed appendString:@" "];
                            lastSpace = YES;
                        }
                    } else {
                        [collapsed appendFormat:@"%C", ch];
                        lastSpace = NO;
                    }
                }
                decoded = collapsed;
            }
            if ([decoded length] > 0) {
                OMAppendString(output, decoded, attributes);
            }
        },
        ^(NSString *name, BOOL closing, BOOL selfClosing, NSDictionary *tagAttributes, NSString *raw) {
            if (OMHTMLIsHiddenTag(name)) {
                if (closing) {
                    hiddenDepth = hiddenDepth > 0 ? hiddenDepth - 1 : 0;
                } else if (!selfClosing) {
                    hiddenDepth += 1;
                }
                return;
            }
            if (hiddenDepth > 0) {
                return;
            }
            if ([name isEqualToString:@"hr"]) {
                OMHTMLEndLine(output, attributes, blockStart);
                OMRenderHTMLThematicBreak(theme, output, attributes, layoutWidth);
                return;
            }
            if ([name isEqualToString:@"br"] || [name isEqualToString:@"img"]) {
                OMHTMLApplyCommonTag(name, closing, tagAttributes, raw, output, attributes, theme, scale, renderContext);
                return;
            }
            if (OMHTMLIsBlockTag(name) || [name isEqualToString:@"summary"]) {
                OMHTMLEndLine(output, attributes, blockStart);
                if ([name isEqualToString:@"pre"]) {
                    preDepth = closing ? (preDepth > 0 ? preDepth - 1 : 0) : preDepth + 1;
                }
                if (closing) {
                    OMHTMLPopStyle(attributes, name);
                } else {
                    NSMutableDictionary *changes = [NSMutableDictionary dictionaryWithDictionary:
                                                    OMHTMLAlignmentChanges(name, tagAttributes, attributes)];
                    if ([name isEqualToString:@"summary"] || [name isEqualToString:@"dt"]) {
                        NSFont *bold = OMFontWithTraits([attributes objectForKey:NSFontAttributeName], NSBoldFontMask);
                        if (bold != nil) {
                            [changes setObject:bold forKey:NSFontAttributeName];
                        }
                    } else if ([name isEqualToString:@"pre"]) {
                        NSFont *font = [attributes objectForKey:NSFontAttributeName];
                        NSDictionary *code = [theme codeAttributesForSize:(font != nil ? [font pointSize] : 14.0 * scale)];
                        if (code != nil) {
                            [changes addEntriesFromDictionary:code];
                        }
                    }
                    OMHTMLPushStyle(attributes, name, changes);
                }
                return;
            }
            if ([name length] == 2 && [name characterAtIndex:0] == 'h' &&
                [name characterAtIndex:1] >= '1' && [name characterAtIndex:1] <= '6') {
                OMHTMLEndLine(output, attributes, blockStart);
                if (closing) {
                    OMHTMLPopStyle(attributes, name);
                } else {
                    NSMutableDictionary *changes = [NSMutableDictionary dictionaryWithDictionary:
                                                    OMHeadingAttributesForLevel(theme, (NSUInteger)([name characterAtIndex:1] - '0'), scale)];
                    [changes removeObjectForKey:NSParagraphStyleAttributeName];
                    [changes addEntriesFromDictionary:OMHTMLAlignmentChanges(name, tagAttributes, attributes)];
                    OMHTMLPushStyle(attributes, name, changes);
                }
                return;
            }
            if ([name isEqualToString:@"ul"] || [name isEqualToString:@"ol"]) {
                OMHTMLEndLine(output, attributes, blockStart);
                if (closing) {
                    if ([lists count] > 0) {
                        [lists removeLastObject];
                    }
                } else {
                    [lists addObject:[NSNumber numberWithInteger:([name isEqualToString:@"ol"] ? 1 : 0)]];
                }
                return;
            }
            if ([name isEqualToString:@"li"]) {
                OMHTMLEndLine(output, attributes, blockStart);
                if (!closing) {
                    NSMutableString *prefix = [NSMutableString string];
                    NSUInteger depth = [lists count];
                    NSUInteger level = 1;
                    for (; level < depth; level++) {
                        [prefix appendString:@"    "];
                    }
                    NSInteger counter = depth > 0 ? [[lists lastObject] integerValue] : 0;
                    if (counter > 0) {
                        [prefix appendFormat:@"%ld. ", (long)counter];
                        [lists replaceObjectAtIndex:depth - 1 withObject:[NSNumber numberWithInteger:counter + 1]];
                    } else {
                        [prefix appendString:@"• "];
                    }
                    OMAppendString(output, prefix, attributes);
                }
                return;
            }
            if ([name isEqualToString:@"table"] || [name isEqualToString:@"thead"] ||
                [name isEqualToString:@"tbody"] || [name isEqualToString:@"tfoot"]) {
                OMHTMLEndLine(output, attributes, blockStart);
                return;
            }
            if ([name isEqualToString:@"tr"]) {
                OMHTMLEndLine(output, attributes, blockStart);
                if (closing) {
                    if ([cellsInRow count] > 0) {
                        [cellsInRow removeLastObject];
                    }
                } else {
                    [cellsInRow addObject:[NSNumber numberWithInteger:0]];
                }
                return;
            }
            if ([name isEqualToString:@"td"] || [name isEqualToString:@"th"]) {
                if (closing) {
                    OMHTMLPopStyle(attributes, name);
                    return;
                }
                NSInteger cells = [cellsInRow count] > 0 ? [[cellsInRow lastObject] integerValue] : 0;
                if (cells > 0) {
                    OMAppendString(output, @"\t", attributes);
                }
                if ([cellsInRow count] > 0) {
                    [cellsInRow replaceObjectAtIndex:[cellsInRow count] - 1 withObject:[NSNumber numberWithInteger:cells + 1]];
                }
                NSDictionary *changes = [NSDictionary dictionary];
                if ([name isEqualToString:@"th"]) {
                    NSFont *bold = OMFontWithTraits([attributes objectForKey:NSFontAttributeName], NSBoldFontMask);
                    if (bold != nil) {
                        changes = [NSDictionary dictionaryWithObject:bold forKey:NSFontAttributeName];
                    }
                }
                OMHTMLPushStyle(attributes, name, changes);
                return;
            }
            OMHTMLApplyCommonTag(name, closing, tagAttributes, raw, output, attributes, theme, scale, renderContext);
        });

    // Trailing spaces before the block's end go.
    while ([output length] > blockStart && [[output string] characterAtIndex:[output length] - 1] == ' ') {
        [output deleteCharactersInRange:NSMakeRange([output length] - 1, 1)];
    }
    if ([output length] > blockStart) {
        OMHTMLEndLine(output, blockAttributes, blockStart);
        OMAppendString(output, @"\n", blockAttributes);
    }
}
