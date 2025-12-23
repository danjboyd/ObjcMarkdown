// ObjcMarkdown
// SPDX-License-Identifier: Apache-2.0

#import "OMMarkdownRenderer.h"
#import "OMTheme.h"

#include <cmark.h>
#include <stdlib.h>
#include <string.h>

static NSFont *OMFontWithTraits(NSFont *font, NSFontTraitMask traits)
{
    if (font == nil) {
        return nil;
    }
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *converted = [manager convertFont:font toHaveTrait:traits];
    return converted != nil ? converted : font;
}

static void OMAppendString(NSMutableAttributedString *output,
                           NSString *string,
                           NSDictionary *attributes)
{
    if (string == nil || [string length] == 0) {
        return;
    }
    NSAttributedString *segment = [[[NSAttributedString alloc] initWithString:string
                                                                    attributes:attributes] autorelease];
    [output appendAttributedString:segment];
}

static NSMutableParagraphStyle *OMParagraphStyleWithIndent(CGFloat firstIndent,
                                                           CGFloat headIndent,
                                                           CGFloat spacingAfter,
                                                           CGFloat lineSpacing,
                                                           CGFloat lineHeightMultiple,
                                                           CGFloat fontSize)
{
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setFirstLineHeadIndent:firstIndent];
    [style setHeadIndent:headIndent];
    [style setParagraphSpacing:spacingAfter];
    [style setLineSpacing:lineSpacing];
    [style setLineHeightMultiple:lineHeightMultiple];
    if (fontSize > 0.0 && lineHeightMultiple > 0.0) {
        CGFloat lineHeight = fontSize * lineHeightMultiple;
        [style setMinimumLineHeight:lineHeight];
        [style setMaximumLineHeight:lineHeight];
    }
    return style;
}

static void OMTrimTrailingNewlines(NSMutableAttributedString *output)
{
    while ([output length] > 0) {
        unichar ch = [[output string] characterAtIndex:[output length] - 1];
        if (ch == '\n') {
            [output deleteCharactersInRange:NSMakeRange([output length] - 1, 1)];
        } else {
            break;
        }
    }
}

static void OMRenderInlines(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            CGFloat scale);

static void OMRenderBlocks(cmark_node *node,
                           OMTheme *theme,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *attributes,
                           NSMutableArray *codeRanges,
                           NSMutableArray *blockquoteRanges,
                           NSMutableArray *listStack,
                           NSUInteger quoteLevel,
                           CGFloat scale,
                           CGFloat layoutWidth);

static NSMutableDictionary *OMListContext(NSMutableArray *listStack)
{
    return [listStack count] > 0 ? [listStack lastObject] : nil;
}

static BOOL OMIsTightList(NSMutableArray *listStack)
{
    NSMutableDictionary *list = OMListContext(listStack);
    if (list == nil) {
        return NO;
    }
    return [[list objectForKey:@"tight"] boolValue];
}

static NSString *OMListPrefix(NSMutableArray *listStack)
{
    NSMutableDictionary *list = OMListContext(listStack);
    if (list == nil) {
        return @"";
    }

    cmark_list_type type = (cmark_list_type)[[list objectForKey:@"type"] intValue];
    if (type == CMARK_BULLET_LIST) {
        return @"- ";
    }

    NSNumber *index = [list objectForKey:@"index"];
    if (index == nil) {
        return @"1. ";
    }
    return [NSString stringWithFormat:@"%@. ", index];
}

static void OMIncrementListIndex(NSMutableArray *listStack)
{
    NSMutableDictionary *list = OMListContext(listStack);
    if (list == nil) {
        return;
    }
    NSNumber *index = [list objectForKey:@"index"];
    if (index == nil) {
        return;
    }
    [list setObject:[NSNumber numberWithInteger:[index integerValue] + 1] forKey:@"index"];
}

static NSDictionary *OMHeadingAttributes(OMTheme *theme, NSUInteger level, CGFloat scale)
{
    static const CGFloat scales[6] = { 1.6, 1.4, 1.2, 1.1, 1.0, 0.95 };
    CGFloat baseSize = theme.baseFont != nil ? [theme.baseFont pointSize] : 14.0;
    NSUInteger idx = level > 0 ? level - 1 : 0;
    if (idx > 5) {
        idx = 5;
    }
    return [theme headingAttributesForSize:(baseSize * scales[idx] * scale)];
}

static NSString *OMRuleLineString(NSFont *font, CGFloat width)
{
    if (font == nil || width <= 0.0) {
        return @"────────────────────────────────────────────────────────";
    }

    NSDictionary *attrs = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    NSSize charSize = [@"─" sizeWithAttributes:attrs];
    CGFloat charWidth = charSize.width > 0.0 ? charSize.width : 6.0;
    NSInteger count = (NSInteger)floor(width / charWidth);
    if (count < 8) {
        count = 8;
    }

    NSMutableString *rule = [NSMutableString stringWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) {
        [rule appendString:@"─"];
    }
    return rule;
}

@interface OMMarkdownRenderer ()
@property (nonatomic, retain) OMTheme *theme;
@property (nonatomic, retain) NSArray *codeBlockRanges;
@property (nonatomic, retain) NSArray *blockquoteRanges;
@end

@implementation OMMarkdownRenderer

@synthesize zoomScale = _zoomScale;
@synthesize layoutWidth = _layoutWidth;
@synthesize codeBlockRanges = _codeBlockRanges;
@synthesize blockquoteRanges = _blockquoteRanges;

- (instancetype)init
{
    return [self initWithTheme:[OMTheme defaultTheme]];
}

- (instancetype)initWithTheme:(OMTheme *)theme
{
    self = [super init];
    if (self) {
        if (theme == nil) {
            theme = [OMTheme defaultTheme];
        }
        _theme = [theme retain];
        _zoomScale = 1.0;
        _layoutWidth = 0.0;
    }
    return self;
}

- (void)dealloc
{
    [_codeBlockRanges release];
    [_blockquoteRanges release];
    [_theme release];
    [super dealloc];
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown
{
    if (markdown == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    NSData *markdownData = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    if (markdownData == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    const char *bytes = (const char *)[markdownData bytes];
    size_t length = (size_t)[markdownData length];
    cmark_node *document = cmark_parse_document(bytes, length, CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return [[[NSAttributedString alloc] initWithString:markdown] autorelease];
    }

    NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] init] autorelease];
    NSMutableDictionary *attributes = [[[self.theme baseAttributes] mutableCopy] autorelease];
    CGFloat scale = self.zoomScale > 0.01 ? self.zoomScale : 1.0;
    if (self.theme.baseFont != nil) {
        NSFont *scaledFont = [NSFont fontWithName:[self.theme.baseFont fontName]
                                             size:[self.theme.baseFont pointSize] * scale];
        if (scaledFont != nil) {
            [attributes setObject:scaledFont forKey:NSFontAttributeName];
        } else {
            [attributes setObject:self.theme.baseFont forKey:NSFontAttributeName];
        }
    }
    if ([attributes objectForKey:NSForegroundColorAttributeName] == nil && self.theme.baseTextColor != nil) {
        [attributes setObject:self.theme.baseTextColor forKey:NSForegroundColorAttributeName];
    }

    NSMutableArray *listStack = [NSMutableArray array];
    NSMutableArray *codeRanges = [NSMutableArray array];
    NSMutableArray *blockquoteRanges = [NSMutableArray array];
    OMRenderBlocks(document, self.theme, output, attributes, codeRanges, blockquoteRanges, listStack, 0, scale, self.layoutWidth);
    [self setCodeBlockRanges:codeRanges];
    [self setBlockquoteRanges:blockquoteRanges];
    OMTrimTrailingNewlines(output);
    cmark_node_free(document);
    return output;
}

- (NSColor *)backgroundColor
{
    return self.theme.baseBackgroundColor;
}

static void OMRenderParagraph(cmark_node *node,
                              OMTheme *theme,
                              NSMutableAttributedString *output,
                              NSMutableDictionary *attributes,
                              NSMutableArray *listStack,
                              NSUInteger quoteLevel,
                              CGFloat scale)
{
    NSMutableDictionary *paraAttrs = [attributes mutableCopy];
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale);
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    NSParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 12.0 * scale, 0.0, 1.725, fontSize);
    [paraAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMRenderInlines(node, theme, output, paraAttrs, scale);
    [paraAttrs release];

    if (OMIsTightList(listStack)) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static void OMRenderHeading(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            NSUInteger quoteLevel,
                            CGFloat scale,
                            CGFloat layoutWidth)
{
    int level = cmark_node_get_heading_level(node);
    NSMutableDictionary *headingAttrs = [attributes mutableCopy];
    NSDictionary *headingStyle = OMHeadingAttributes(theme, (NSUInteger)level, scale);
    [headingAttrs addEntriesFromDictionary:headingStyle];

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale);
    NSFont *font = [headingAttrs objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 14.0 * scale, 0.0, 1.38, fontSize);
    CGFloat spacingBefore = (level >= 2 && level <= 3) ? 20.0 * scale : 10.0 * scale;
    [style setParagraphSpacingBefore:spacingBefore];
    [headingAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMRenderInlines(node, theme, output, headingAttrs, scale);
    [headingAttrs release];
    OMAppendString(output, @"\n", attributes);

    if (level <= 3 && theme.hrColor != nil) {
        NSMutableDictionary *ruleAttrs = [attributes mutableCopy];
        NSFont *font = [attributes objectForKey:NSFontAttributeName];
        CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
        NSFont *ruleFont = [NSFont systemFontOfSize:MAX(1.0, size * 0.35)];
        if (ruleFont != nil) {
            [ruleAttrs setObject:ruleFont forKey:NSFontAttributeName];
        }
        [ruleAttrs setObject:theme.hrColor forKey:NSForegroundColorAttributeName];
        NSMutableParagraphStyle *ruleStyle = OMParagraphStyleWithIndent(indent, indent, 12.0 * scale, 0.0, 1.15, size);
        [ruleStyle setMinimumLineHeight:MAX(1.0, size * 0.5)];
        [ruleAttrs setObject:ruleStyle forKey:NSParagraphStyleAttributeName];

        CGFloat availableWidth = layoutWidth > 0.0 ? (layoutWidth - indent) : 0.0;
        NSString *rule = OMRuleLineString(ruleFont, availableWidth);
        OMAppendString(output, rule, ruleAttrs);
        OMAppendString(output, @"\n\n", attributes);
        [ruleAttrs release];
    } else {
        OMAppendString(output, @"\n", attributes);
    }
}

static void OMRenderCodeBlock(cmark_node *node,
                              OMTheme *theme,
                              NSMutableAttributedString *output,
                              NSMutableDictionary *attributes,
                              NSUInteger quoteLevel,
                              CGFloat scale,
                              NSMutableArray *codeRanges)
{
    const char *literal = cmark_node_get_literal(node);
    NSString *code = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";

    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    NSDictionary *codeAttrs = [theme codeAttributesForSize:size];

    NSMutableDictionary *blockAttrs = [attributes mutableCopy];
    [blockAttrs addEntriesFromDictionary:codeAttrs];

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + 20.0 * scale;
    CGFloat padding = 16.0 * scale;
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent + padding,
                                                                indent + padding,
                                                                14.0 * scale,
                                                                0.0,
                                                                1.5,
                                                                size);
    [style setParagraphSpacingBefore:10.0 * scale];
    [style setTailIndent:-padding];
    [blockAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    NSUInteger startLocation = [output length];
    OMAppendString(output, code, blockAttrs);
    if ([code length] > 0) {
        [codeRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, [code length])]];
    }
    if (![code hasSuffix:@"\n"]) {
        OMAppendString(output, @"\n", blockAttrs);
    }
    OMAppendString(output, @"\n", attributes);
    [blockAttrs release];
}

static void OMRenderThematicBreak(OMTheme *theme,
                                  NSMutableAttributedString *output,
                                  NSMutableDictionary *attributes,
                                  CGFloat layoutWidth)
{
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    NSString *rule = OMRuleLineString(font, layoutWidth);
    OMAppendString(output, rule, attributes);
    OMAppendString(output, @"\n\n", attributes);
}

static void OMRenderList(cmark_node *node,
                         OMTheme *theme,
                         NSMutableAttributedString *output,
                         NSMutableDictionary *attributes,
                         NSMutableArray *codeRanges,
                         NSMutableArray *blockquoteRanges,
                         NSMutableArray *listStack,
                         NSUInteger quoteLevel,
                         CGFloat scale,
                         CGFloat layoutWidth)
{
    cmark_list_type type = cmark_node_get_list_type(node);
    int start = cmark_node_get_list_start(node);
    BOOL tight = cmark_node_get_list_tight(node) ? YES : NO;

    NSMutableDictionary *listInfo = [NSMutableDictionary dictionary];
    [listInfo setObject:[NSNumber numberWithInt:type] forKey:@"type"];
    [listInfo setObject:[NSNumber numberWithInt:start > 0 ? start : 1] forKey:@"index"];
    [listInfo setObject:[NSNumber numberWithBool:tight] forKey:@"tight"];
    [listStack addObject:listInfo];

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
        child = cmark_node_next(child);
    }

    [listStack removeLastObject];
    BOOL nested = [listStack count] > 0;
    BOOL parentIsItem = NO;
    cmark_node *parent = cmark_node_parent(node);
    if (parent != NULL && cmark_node_get_type(parent) == CMARK_NODE_ITEM) {
        parentIsItem = YES;
    }
    if (parentIsItem) {
        return;
    }
    if (nested || tight) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static void OMRenderListItem(cmark_node *node,
                             OMTheme *theme,
                             NSMutableAttributedString *output,
                             NSMutableDictionary *attributes,
                             NSMutableArray *codeRanges,
                             NSMutableArray *blockquoteRanges,
                             NSMutableArray *listStack,
                             NSUInteger quoteLevel,
                             CGFloat scale,
                             CGFloat layoutWidth)
{
    NSUInteger startLocation = [output length];
    NSString *prefix = OMListPrefix(listStack);
    OMAppendString(output, prefix, attributes);

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
        child = cmark_node_next(child);
    }

    NSUInteger endLocation = [output length];
    CGFloat baseIndent = (CGFloat)(quoteLevel * 20.0 * scale);
    CGFloat listIndent = (CGFloat)([listStack count] * 18.0 * scale);
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    BOOL hasNestedList = NO;
    cmark_node *scan = cmark_node_first_child(node);
    while (scan != NULL) {
        if (cmark_node_get_type(scan) == CMARK_NODE_LIST) {
            hasNestedList = YES;
            break;
        }
        scan = cmark_node_next(scan);
    }
    CGFloat spacingAfter = [listStack count] > 1 ? 2.0 * scale : 8.0 * scale;
    if (hasNestedList) {
        spacingAfter = 2.0 * scale;
    }
    NSParagraphStyle *style = OMParagraphStyleWithIndent(baseIndent + listIndent,
                                                        baseIndent + listIndent + 20.0 * scale,
                                                        spacingAfter,
                                                        0.0,
                                                        1.61,
                                                        fontSize);
    if (endLocation > startLocation) {
        NSString *text = [output string];
        NSRange searchRange = NSMakeRange(startLocation, endLocation - startLocation);
        NSRange newlineRange = [text rangeOfString:@"\n" options:0 range:searchRange];
        NSUInteger lineEnd = newlineRange.location != NSNotFound ? newlineRange.location : endLocation;
        if (lineEnd > startLocation) {
            [output addAttribute:NSParagraphStyleAttributeName
                           value:style
                           range:NSMakeRange(startLocation, lineEnd - startLocation)];
        }
    }
    OMIncrementListIndex(listStack);
}

static void OMRenderBlocks(cmark_node *node,
                           OMTheme *theme,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *attributes,
                           NSMutableArray *codeRanges,
                           NSMutableArray *blockquoteRanges,
                           NSMutableArray *listStack,
                           NSUInteger quoteLevel,
                           CGFloat scale,
                           CGFloat layoutWidth)
{
    cmark_node_type type = cmark_node_get_type(node);
    if (type == CMARK_NODE_BLOCK_QUOTE) {
        NSUInteger startLocation = [output length];
        cmark_node *child = cmark_node_first_child(node);
        while (child != NULL) {
            OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel + 1, scale, layoutWidth);
            child = cmark_node_next(child);
        }
        NSUInteger endLocation = [output length];
        if (endLocation > startLocation) {
            [blockquoteRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, endLocation - startLocation)]];
        }
        return;
    }
    switch (type) {
        case CMARK_NODE_DOCUMENT:
            break;
        case CMARK_NODE_PARAGRAPH:
            OMRenderParagraph(node, theme, output, attributes, listStack, quoteLevel, scale);
            return;
        case CMARK_NODE_HEADING:
            OMRenderHeading(node, theme, output, attributes, quoteLevel, scale, layoutWidth);
            return;
        case CMARK_NODE_CODE_BLOCK:
            OMRenderCodeBlock(node, theme, output, attributes, quoteLevel, scale, codeRanges);
            return;
        case CMARK_NODE_THEMATIC_BREAK:
            OMRenderThematicBreak(theme, output, attributes, layoutWidth);
            return;
        case CMARK_NODE_BLOCK_QUOTE:
            quoteLevel += 1;
            break;
        case CMARK_NODE_LIST:
            OMRenderList(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
            return;
        case CMARK_NODE_ITEM:
            OMRenderListItem(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
            return;
        case CMARK_NODE_HTML_BLOCK:
        case CMARK_NODE_CUSTOM_BLOCK:
            return;
        default:
            break;
    }

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
        child = cmark_node_next(child);
    }
}

static void OMRenderInlines(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            CGFloat scale)
{
    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        switch (type) {
            case CMARK_NODE_TEXT: {
                const char *literal = cmark_node_get_literal(child);
                NSString *text = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                OMAppendString(output, text, attributes);
                break;
            }
            case CMARK_NODE_SOFTBREAK:
                OMAppendString(output, @" ", attributes);
                break;
            case CMARK_NODE_LINEBREAK:
                OMAppendString(output, @"\n", attributes);
                break;
            case CMARK_NODE_CODE: {
                const char *literal = cmark_node_get_literal(child);
                NSString *text = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                NSFont *font = [attributes objectForKey:NSFontAttributeName];
                CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
                NSDictionary *codeAttrs = [theme codeAttributesForSize:size];
                NSMutableDictionary *inlineAttrs = [attributes mutableCopy];
                [inlineAttrs addEntriesFromDictionary:codeAttrs];
                OMAppendString(output, text, inlineAttrs);
                [inlineAttrs release];
                break;
            }
            case CMARK_NODE_EMPH: {
                NSMutableDictionary *emphAttrs = [attributes mutableCopy];
                NSFont *font = [emphAttrs objectForKey:NSFontAttributeName];
                NSFont *newFont = OMFontWithTraits(font, NSItalicFontMask);
                if (newFont != nil) {
                    [emphAttrs setObject:newFont forKey:NSFontAttributeName];
                }
                OMRenderInlines(child, theme, output, emphAttrs, scale);
                [emphAttrs release];
                break;
            }
            case CMARK_NODE_STRONG: {
                NSMutableDictionary *strongAttrs = [attributes mutableCopy];
                NSFont *font = [strongAttrs objectForKey:NSFontAttributeName];
                NSFont *newFont = OMFontWithTraits(font, NSBoldFontMask);
                if (newFont != nil) {
                    [strongAttrs setObject:newFont forKey:NSFontAttributeName];
                }
                OMRenderInlines(child, theme, output, strongAttrs, scale);
                [strongAttrs release];
                break;
            }
            case CMARK_NODE_LINK: {
                const char *url = cmark_node_get_url(child);
                NSString *urlString = url != NULL ? [NSString stringWithUTF8String:url] : @"";
                NSMutableDictionary *linkAttrs = [attributes mutableCopy];
                if ([urlString length] > 0) {
                    NSURL *linkURL = [NSURL URLWithString:urlString];
                    if (linkURL == nil) {
                        linkURL = [NSURL fileURLWithPath:urlString];
                    }
                    if (linkURL != nil) {
                        [linkAttrs setObject:linkURL forKey:NSLinkAttributeName];
                    }
                }
                if (theme.linkColor != nil) {
                    [linkAttrs setObject:theme.linkColor forKey:NSForegroundColorAttributeName];
                }
                OMRenderInlines(child, theme, output, linkAttrs, scale);
                [linkAttrs release];
                break;
            }
            case CMARK_NODE_IMAGE: {
                OMAppendString(output, @"[image]", attributes);
                break;
            }
            case CMARK_NODE_HTML_INLINE:
            case CMARK_NODE_CUSTOM_INLINE:
                break;
            default:
                OMRenderInlines(child, theme, output, attributes, scale);
                break;
        }
        child = cmark_node_next(child);
    }
}

@end
