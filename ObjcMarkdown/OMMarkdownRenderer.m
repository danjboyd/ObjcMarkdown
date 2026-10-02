// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMarkdownRenderer.h"
#import "OMMarkdownRendererInternal.h"
#include "OMEmojiShortcodes.inc"

NSString * const OMMarkdownRendererMathArtifactsDidWarmNotification = @"OMMarkdownRendererMathArtifactsDidWarmNotification";
NSString * const OMMarkdownRendererRemoteImagesDidWarmNotification = @"OMMarkdownRendererRemoteImagesDidWarmNotification";
NSString * const OMMarkdownRendererAnchorSourceStartLineKey = @"sourceStartLine";
NSString * const OMMarkdownRendererAnchorSourceEndLineKey = @"sourceEndLine";
NSString * const OMMarkdownRendererAnchorTargetStartKey = @"targetStart";
NSString * const OMMarkdownRendererAnchorTargetLengthKey = @"targetLength";
NSString * const OMMarkdownRendererAnchorBlockIDKey = @"blockID";
NSString * const OMMarkdownRendererHeadingLevelKey = @"OMMarkdownRendererHeadingLevel";
NSString * const OMMarkdownRendererHeadingTitleKey = @"OMMarkdownRendererHeadingTitle";
NSString * const OMMarkdownRendererHeadingAnchorKey = @"OMMarkdownRendererHeadingAnchor";
NSString * const OMMarkdownRendererHeadingRangeKey = @"OMMarkdownRendererHeadingRange";
NSString * const OMMarkdownRendererHeadingSourceLineKey = @"OMMarkdownRendererHeadingSourceLine";
NSString * const OMMarkdownRendererHeadingAnchorAttributeName = @"OMMarkdownRendererHeadingAnchor";
NSString * const OMMarkdownRendererBlockquoteColorAttributeName = @"OMMarkdownRendererBlockquoteColor";
NSString * const OMMarkdownRendererDiagramRangeKey = @"OMMarkdownRendererDiagramRange";
NSString * const OMMarkdownRendererDiagramSourceKey = @"OMMarkdownRendererDiagramSource";


// Indent of a list item's content, so every block in an item (not only its
// first line) lines up under the item's text. Zero outside lists.
CGFloat OMListContentIndent(const OMRenderContext *renderContext, CGFloat scale)
{
    NSUInteger depth = (renderContext != NULL && renderContext->listStack != nil) ? [renderContext->listStack count] : 0;
    return depth > 0 ? ((CGFloat)depth * 18.0 + 20.0) * scale : 0.0;
}


NSTimeInterval OMNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

#if defined(_WIN32)
static NSString *OMWindowsNormalizedPath(NSString *value)
{
    if (value == nil) {
        return nil;
    }
    return [value stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
}

static NSString *OMWindowsQuoteCommandArgument(NSString *value)
{
    if (value == nil) {
        return @"\"\"";
    }

    NSMutableString *quoted = [NSMutableString stringWithString:@"\""];
    NSUInteger length = [value length];
    NSUInteger index = 0;
    while (index < length) {
        unichar character = [value characterAtIndex:index];
        if (character == '\\') {
            NSUInteger slashStart = index;
            while (index < length && [value characterAtIndex:index] == '\\') {
                index += 1;
            }
            NSUInteger slashCount = index - slashStart;
            BOOL beforeQuoteOrEnd = (index == length || [value characterAtIndex:index] == '"');
            NSUInteger copies = beforeQuoteOrEnd ? (slashCount * 2) : slashCount;
            while (copies-- > 0) {
                [quoted appendString:@"\\"];
            }
            if (index < length && [value characterAtIndex:index] == '"') {
                [quoted appendString:@"\\\""];
                index += 1;
            }
            continue;
        }
        if (character == '"') {
            [quoted appendString:@"\\\""];
        } else {
            [quoted appendFormat:@"%C", character];
        }
        index += 1;
    }
    [quoted appendString:@"\""];
    return quoted;
}

static NSString *OMWindowsTaskScriptPath(NSString *workingDirectory)
{
    if (workingDirectory == nil || [workingDirectory length] == 0) {
        return nil;
    }
    return [workingDirectory stringByAppendingPathComponent:@"omd-run-task.cmd"];
}
#endif

static BOOL OMTruthyFlagValue(NSString *value)
{
    if (value == nil) {
        return NO;
    }
    NSString *lower = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [lower isEqualToString:@"1"] ||
           [lower isEqualToString:@"true"] ||
           [lower isEqualToString:@"yes"] ||
           [lower isEqualToString:@"on"];
}

static BOOL OMPerformanceLoggingEnabled(void)
{
    static dispatch_once_t onceToken;
    static BOOL enabled = NO;
    dispatch_once(&onceToken, ^{
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_PERF_LOG"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_PERF_LOG"];
        }
        if (flag != nil && [flag length] > 0) {
            enabled = OMTruthyFlagValue(flag);
        } else {
            enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownPerfLog"];
        }
    });
    return enabled;
}


OMMarkdownParsingOptions *OMRenderContextParsingOptions(const OMRenderContext *renderContext)
{
    if (renderContext == NULL) {
        return nil;
    }
    return renderContext->parsingOptions;
}

BOOL OMShouldParseMathSpans(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return YES;
    }
    return [options mathRenderingPolicy] != OMMarkdownMathRenderingPolicyDisabled;
}

BOOL OMNativeDiagramRenderingEnabled(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return YES;
    }
    return [options diagramRenderingPolicy] == OMMarkdownDiagramRenderingPolicyNative;
}

BOOL OMExternalMathRenderingEnabled(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return NO;
    }
    return [options mathRenderingPolicy] == OMMarkdownMathRenderingPolicyExternalTools;
}

NSUInteger OMMathMaximumFormulaLength(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil || [options maximumMathFormulaLength] == 0) {
        return 2048;
    }
    return [options maximumMathFormulaLength];
}

NSTimeInterval OMExternalToolTimeout(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return 4.0;
    }
    NSTimeInterval timeout = [options externalToolTimeout];
    if (timeout <= 0.0) {
        return 4.0;
    }
    return timeout;
}

static BOOL OMShouldRenderImages(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return YES;
    }
    return [options renderImages];
}

BOOL OMShouldAllowRemoteImages(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return NO;
    }
    return [options allowRemoteImages];
}

static NSSet *OMAllowedImageSchemes(void)
{
    static NSSet *schemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        schemes = [[NSSet alloc] initWithObjects:@"file", @"http", @"https", nil];
    });
    return schemes;
}

static NSSet *OMAllowedLinkSchemes(void)
{
    static NSSet *schemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        schemes = [[NSSet alloc] initWithObjects:@"file", @"http", @"https", @"mailto", nil];
    });
    return schemes;
}

static BOOL OMURLUsesAllowedScheme(NSURL *url, NSSet *allowedSchemes)
{
    if (url == nil || allowedSchemes == nil) {
        return NO;
    }
    NSString *scheme = [[url scheme] lowercaseString];
    if (scheme == nil || [scheme length] == 0) {
        return NO;
    }
    return [allowedSchemes containsObject:scheme];
}

BOOL OMURLUsesAllowedImageScheme(NSURL *url)
{
    return OMURLUsesAllowedScheme(url, OMAllowedImageSchemes());
}

BOOL OMURLUsesAllowedLinkScheme(NSURL *url)
{
    return OMURLUsesAllowedScheme(url, OMAllowedLinkSchemes());
}

static BOOL OMTreeSitterRuntimeAvailable(void)
{
    static dispatch_once_t onceToken;
    static BOOL available = NO;
    dispatch_once(&onceToken, ^{
        available = NO;

        const char *libraryCandidates[] = {
            "libtree-sitter.so",
            "libtree-sitter.so.0",
            "libtree-sitter.so.0.22",
            "libtree-sitter.dylib",
#if defined(_WIN32)
            "tree-sitter.dll",
            "libtree-sitter.dll",
#endif
            NULL
        };
        const char **cursor = libraryCandidates;
        for (; *cursor != NULL; cursor++) {
#if defined(_WIN32)
            HMODULE handle = LoadLibraryA(*cursor);
            if (handle != NULL) {
                available = YES;
                FreeLibrary(handle);
                break;
            }
#else
            void *handle = dlopen(*cursor, RTLD_LAZY | RTLD_LOCAL);
            if (handle != NULL) {
                available = YES;
                dlclose(handle);
                break;
            }
#endif
        }

        if (!available) {
            available = (OMExecutablePathNamed(@"tree-sitter") != nil);
        }

    });
    return available;
}

BOOL OMShouldApplyCodeSyntaxHighlighting(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options != nil && ![options codeSyntaxHighlightingEnabled]) {
        return NO;
    }
    return OMTreeSitterRuntimeAvailable();
}

static OMMarkdownHTMLPolicy OMHTMLPolicyForBlockNode(const OMRenderContext *renderContext,
                                                     BOOL blockNode)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return OMMarkdownHTMLPolicyRenderAsText;
    }
    return blockNode ? [options blockHTMLPolicy] : [options inlineHTMLPolicy];
}


NSFont *OMFontWithTraits(NSFont *font, NSFontTraitMask traits)
{
    if (font == nil) {
        return nil;
    }
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *converted = [manager convertFont:font toHaveTrait:traits];
    return converted != nil ? converted : font;
}

static void OMApplyItalicFallbackIfNeeded(NSMutableDictionary *attributes, NSFont *originalFont, NSFont *resolvedFont)
{
    if (attributes == nil) {
        return;
    }

    if (resolvedFont != nil && originalFont != nil && resolvedFont != originalFont) {
        return;
    }

    if ([attributes objectForKey:NSObliquenessAttributeName] == nil) {
        [attributes setObject:[NSNumber numberWithDouble:0.2]
                       forKey:NSObliquenessAttributeName];
    }
}


void OMAppendString(NSMutableAttributedString *output,
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

void OMAppendAttributedSegment(NSMutableAttributedString *output,
                               NSAttributedString *segment)
{
    if (segment == nil || [segment length] == 0) {
        return;
    }
    [output appendAttributedString:segment];
}

NSMutableParagraphStyle *OMParagraphStyleWithIndent(CGFloat firstIndent,
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
    }
    return style;
}

// Marks the newline of a Markdown hard break while a paragraph renders.
static NSString * const OMHardLineBreakAttributeName = @"OMHardLineBreak";

// GNUstep lays out only '\n' as a line break (not U+2028), so a hard break
// starts a new text paragraph. Drop the paragraph spacing at those breaks so
// the Markdown paragraph keeps its normal line rhythm.
static void OMTightenHardLineBreaks(NSMutableAttributedString *output, NSRange range)
{
    NSUInteger segmentStart = range.location;
    NSUInteger index = range.location;
    NSUInteger end = NSMaxRange(range);
    while (index < end) {
        NSRange effective;
        id marker = [output attribute:OMHardLineBreakAttributeName atIndex:index effectiveRange:&effective];
        if (marker == nil) {
            index = MIN(NSMaxRange(effective), end);
            continue;
        }
        NSParagraphStyle *style = [output attribute:NSParagraphStyleAttributeName atIndex:segmentStart effectiveRange:NULL];
        if (style != nil && [style paragraphSpacing] > 0.0) {
            NSMutableParagraphStyle *tight = [[style mutableCopy] autorelease];
            [tight setParagraphSpacing:0.0];
            [output addAttribute:NSParagraphStyleAttributeName
                           value:tight
                           range:NSMakeRange(segmentStart, index + 1 - segmentStart)];
        }
        [output removeAttribute:OMHardLineBreakAttributeName range:NSMakeRange(index, 1)];
        segmentStart = index + 1;
        index += 1;
    }
}


// GNUstep's typesetter ignores paragraph spacing and honours only minimum
// line heights, so the empty line between blocks is what spaces them. Size it
// like GitHub: 1em between blocks, 1.5em before a heading, plus the code
// background's padding next to a code block. Blank lines inside code blocks
// keep their height.
static void OMSizeBlockGaps(NSMutableAttributedString *output,
                            NSArray *codeRanges,
                            CGFloat baseSize,
                            CGFloat scale)
{
    NSString *text = [output string];
    NSUInteger length = [text length];
    if (length < 2) {
        return;
    }
    NSMutableIndexSet *code = [NSMutableIndexSet indexSet];
    for (NSValue *value in codeRanges) {
        [code addIndexesInRange:[value rangeValue]];
    }
    CGFloat codePadding = 14.0 * scale;
    NSMutableDictionary *styles = [NSMutableDictionary dictionary];
    NSUInteger index = 1;
    for (; index < length; index++) {
        if ([text characterAtIndex:index] != '\n' || [text characterAtIndex:index - 1] != '\n' ||
            [code containsIndex:index]) {
            continue;
        }
        BOOL beforeHeading = (index + 1 < length &&
                              [output attribute:OMMarkdownRendererHeadingAnchorAttributeName
                                        atIndex:index + 1
                                 effectiveRange:NULL] != nil);
        CGFloat gap = baseSize * (beforeHeading ? 1.5 : 1.0);
        if ([code containsIndex:index - 1]) {
            gap += codePadding;
        }
        if (index + 1 < length && [code containsIndex:index + 1]) {
            gap += codePadding;
        }
        gap = floor(gap + 0.5);
        NSNumber *key = [NSNumber numberWithDouble:gap];
        NSMutableParagraphStyle *style = [styles objectForKey:key];
        if (style == nil) {
            style = [[[NSMutableParagraphStyle alloc] init] autorelease];
            [style setMinimumLineHeight:gap];
            [style setMaximumLineHeight:gap];
            [styles setObject:style forKey:key];
        }
        [output addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(index, 1)];
    }
}

// Ranges recorded before the trailing newlines were trimmed, cut to the text
// that remains (a quote or code block ending the document ran past it).
static NSArray *OMRangesClampedToLength(NSArray *ranges, NSUInteger length)
{
    NSMutableArray *clamped = [NSMutableArray arrayWithCapacity:[ranges count]];
    for (NSValue *value in ranges) {
        NSRange range = [value rangeValue];
        if (range.location >= length) {
            continue;
        }
        if (NSMaxRange(range) > length) {
            range.length = length - range.location;
        }
        [clamped addObject:[NSValue valueWithRange:range]];
    }
    return clamped;
}

static NSCharacterSet *OMEmojiCharacterSet(void);

// Fonts chosen for emoji by default are colour fonts GNUstep can't draw
// (they show as "?"); draw the table's emoji with Symbola instead.
static void OMApplyEmojiFont(NSMutableAttributedString *output, NSArray *codeRanges)
{
    static NSString *emojiFontName = @"Symbola";
    NSString *text = [output string];
    NSCharacterSet *emoji = OMEmojiCharacterSet();
    NSRange found = [text rangeOfCharacterFromSet:emoji];
    if (found.location == NSNotFound || [NSFont fontWithName:emojiFontName size:12.0] == nil) {
        return;
    }
    NSMutableIndexSet *code = [NSMutableIndexSet indexSet];
    for (NSValue *value in codeRanges) {
        [code addIndexesInRange:[value rangeValue]];
    }
    while (found.location != NSNotFound) {
        if (![code containsIndex:found.location]) {
            NSFont *font = [output attribute:NSFontAttributeName atIndex:found.location effectiveRange:NULL];
            NSFont *emojiFont = [NSFont fontWithName:emojiFontName size:(font != nil ? [font pointSize] : 14.0)];
            if (emojiFont != nil) {
                [output addAttribute:NSFontAttributeName value:emojiFont range:found];
            }
        }
        NSUInteger next = NSMaxRange(found);
        found = next < [text length]
            ? [text rangeOfCharacterFromSet:emoji options:0 range:NSMakeRange(next, [text length] - next)]
            : NSMakeRange(NSNotFound, 0);
    }
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


static void OMRenderBlocks(cmark_node *node,
                           OMTheme *theme,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *attributes,
                           NSMutableArray *codeRanges,
                           NSMutableArray *blockquoteRanges,
                           NSMutableArray *listStack,
                           NSUInteger quoteLevel,
                           CGFloat scale,
                           CGFloat layoutWidth,
                           const OMRenderContext *renderContext);


static NSMutableDictionary *OMListContext(NSMutableArray *listStack)
{
    return [listStack count] > 0 ? [listStack lastObject] : nil;
}

BOOL OMIsTightList(NSMutableArray *listStack)
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
        // Disc, circle, then square with nesting, as GitHub does.
        NSUInteger depth = [listStack count];
        return depth <= 1 ? @"\u2022 " : (depth == 2 ? @"\u25E6 " : @"\u25AA ");
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
    // GitHub's heading sizes, relative to body text.
    static const CGFloat scales[6] = { 2.0, 1.5, 1.25, 1.0, 0.875, 0.85 };
    CGFloat baseSize = theme.baseFont != nil ? [theme.baseFont pointSize] : 14.0;
    NSUInteger idx = level > 0 ? level - 1 : 0;
    if (idx > 5) {
        idx = 5;
    }
    return [theme headingAttributesForSize:(baseSize * scales[idx] * scale)];
}

// A horizontal rule drawn as a line, replacing rows of box-drawing glyphs
// (which reflowed badly and were copied as text).
@interface OMRuleAttachmentCell : NSTextAttachmentCell
{
    NSColor *_color;
    NSSize _size;
    CGFloat _thickness;
}
- (instancetype)initWithColor:(NSColor *)color width:(CGFloat)width thickness:(CGFloat)thickness height:(CGFloat)height;
@end

@implementation OMRuleAttachmentCell

- (instancetype)initWithColor:(NSColor *)color width:(CGFloat)width thickness:(CGFloat)thickness height:(CGFloat)height
{
    self = [super initTextCell:@""];
    if (self != nil) {
        _color = [(color != nil ? color : [NSColor lightGrayColor]) retain];
        _thickness = MAX(1.0, thickness);
        _size = NSMakeSize(MAX(1.0, width), MAX(_thickness, height));
    }
    return self;
}

- (void)dealloc
{
    [_color release];
    [super dealloc];
}

- (NSSize)cellSize
{
    return _size;
}

- (NSPoint)cellBaselineOffset
{
    return NSZeroPoint;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSRect line = NSMakeRect(NSMinX(cellFrame),
                             floor(NSMidY(cellFrame) - _thickness * 0.5),
                             NSWidth(cellFrame),
                             _thickness);
    [_color set];
    NSRectFill(line);
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
{
    [self drawWithFrame:cellFrame inView:controlView];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
        layoutManager:(NSLayoutManager *)layoutManager
{
    [self drawWithFrame:cellFrame inView:controlView];
}

@end

// Appends a rule paragraph: one attachment line, thickness tall plus padding.
static void OMAppendRule(NSMutableAttributedString *output,
                         NSDictionary *attributes,
                         NSColor *color,
                         CGFloat width,
                         CGFloat thickness,
                         CGFloat indent,
                         CGFloat spacingAfter)
{
    if (width <= 0.0) {
        width = 400.0;
    }
    CGFloat height = thickness + 2.0;
    OMRuleAttachmentCell *cell = [[[OMRuleAttachmentCell alloc] initWithColor:color
                                                                       width:width
                                                                   thickness:thickness
                                                                      height:height] autorelease];
    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    [attachment setAttachmentCell:cell];
    [cell setAttachment:attachment];

    NSMutableDictionary *ruleAttrs = [NSMutableDictionary dictionaryWithDictionary:attributes];
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setFirstLineHeadIndent:indent];
    [style setHeadIndent:indent];
    [style setMinimumLineHeight:height];
    [style setMaximumLineHeight:height];
    [style setParagraphSpacing:spacingAfter];
    [ruleAttrs setObject:style forKey:NSParagraphStyleAttributeName];
    [ruleAttrs setObject:[NSFont systemFontOfSize:1.0] forKey:NSFontAttributeName];
    [ruleAttrs setObject:attachment forKey:NSAttachmentAttributeName];
    unichar attachmentCharacter = NSAttachmentCharacter;
    OMAppendString(output, [NSString stringWithCharacters:&attachmentCharacter length:1], ruleAttrs);
    [ruleAttrs removeObjectForKey:NSAttachmentAttributeName];
    OMAppendString(output, @"\n", ruleAttrs);
}


void OMAppendInlineTextFromNode(cmark_node *node, NSMutableString *buffer)
{
    if (node == NULL || buffer == nil) {
        return;
    }

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        switch (type) {
            case CMARK_NODE_TEXT:
            case CMARK_NODE_CODE:
            case CMARK_NODE_HTML_INLINE:
            case CMARK_NODE_CUSTOM_INLINE: {
                const char *literal = cmark_node_get_literal(child);
                if (literal != NULL) {
                    NSString *text = [NSString stringWithUTF8String:literal];
                    if (text != nil) {
                        [buffer appendString:text];
                    }
                }
                break;
            }
            case CMARK_NODE_SOFTBREAK:
            case CMARK_NODE_LINEBREAK:
                [buffer appendString:@" "];
                break;
            default:
                OMAppendInlineTextFromNode(child, buffer);
                break;
        }
        child = cmark_node_next(child);
    }
}

NSString *OMInlinePlainText(cmark_node *node)
{
    NSMutableString *buffer = [NSMutableString string];
    OMAppendInlineTextFromNode(node, buffer);
    return [buffer stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

BOOL OMMarkerIsEscaped(NSString *text, NSUInteger location)
{
    if (text == nil || [text length] == 0 || location == 0 || location > [text length]) {
        return NO;
    }

    NSUInteger backslashCount = 0;
    NSInteger index = (NSInteger)location - 1;
    while (index >= 0) {
        if ([text characterAtIndex:(NSUInteger)index] != '\\') {
            break;
        }
        backslashCount += 1;
        index -= 1;
    }
    return (backslashCount % 2) == 1;
}


static void OMAppendHTMLLiteral(const char *literal,
                                NSMutableAttributedString *output,
                                NSMutableDictionary *attributes,
                                BOOL blockNode,
                                const OMRenderContext *renderContext)
{
    NSString *html = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
    if (html == nil || [html length] == 0) {
        return;
    }

    // Strike tags are applied under every HTML policy: GFM "~~" reaches cmark
    // as <del> through OMNormalizeGFMStrikethroughMarkdown.
    NSString *trimmed = [html stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lower = [trimmed lowercaseString];
    if (!blockNode && ([lower isEqualToString:@"<del>"] ||
        [lower isEqualToString:@"<s>"] ||
        [lower isEqualToString:@"<strike>"])) {
        [attributes setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
                       forKey:NSStrikethroughStyleAttributeName];
        return;
    }
    if (!blockNode && ([lower isEqualToString:@"</del>"] ||
        [lower isEqualToString:@"</s>"] ||
        [lower isEqualToString:@"</strike>"])) {
        [attributes removeObjectForKey:NSStrikethroughStyleAttributeName];
        return;
    }

    if (OMHTMLPolicyForBlockNode(renderContext, blockNode) == OMMarkdownHTMLPolicyIgnore) {
        return;
    }

    OMAppendString(output, html, attributes);
    if (blockNode) {
        OMAppendString(output, @"\n\n", attributes);
    }
}


static NSDictionary *OMEmojiShortcodeTable(void)
{
    static NSDictionary *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *built = [NSMutableDictionary dictionary];
        size_t index = 0;
        for (; index < sizeof(OMEmojiShortcodes) / sizeof(OMEmojiShortcodes[0]); index++) {
            unichar character = OMEmojiShortcodes[index].character;
            [built setObject:[NSString stringWithCharacters:&character length:1]
                      forKey:[NSString stringWithUTF8String:OMEmojiShortcodes[index].name]];
        }
        table = [built copy];
    });
    return table;
}

// The emoji characters the shortcode table can produce.
static NSCharacterSet *OMEmojiCharacterSet(void)
{
    static NSCharacterSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *built = [[NSMutableCharacterSet alloc] init];
        size_t index = 0;
        for (; index < sizeof(OMEmojiShortcodes) / sizeof(OMEmojiShortcodes[0]); index++) {
            [built addCharactersInRange:NSMakeRange(OMEmojiShortcodes[index].character, 1)];
        }
        set = built;
    });
    return set;
}

// ":name:" -> emoji, for GitHub shortcodes in the table; others stay as typed.
static NSString *OMStringByReplacingEmojiShortcodes(NSString *text)
{
    if (text == nil || [text rangeOfString:@":"].location == NSNotFound) {
        return text;
    }
    NSDictionary *table = OMEmojiShortcodeTable();
    NSMutableString *result = nil;
    NSUInteger length = [text length];
    NSUInteger copied = 0;
    NSUInteger index = 0;
    while (index < length) {
        if ([text characterAtIndex:index] != ':') {
            index += 1;
            continue;
        }
        NSUInteger end = index + 1;
        while (end < length && end - index <= 48) {
            unichar ch = [text characterAtIndex:end];
            BOOL nameCharacter = (ch < 128 && (isalnum((int)ch) || ch == '_' || ch == '+' || ch == '-'));
            if (!nameCharacter) {
                break;
            }
            end += 1;
        }
        if (end < length && [text characterAtIndex:end] == ':' && end > index + 1) {
            NSString *emoji = [table objectForKey:[text substringWithRange:NSMakeRange(index + 1, end - index - 1)]];
            if (emoji != nil) {
                if (result == nil) {
                    result = [NSMutableString stringWithCapacity:length];
                }
                [result appendString:[text substringWithRange:NSMakeRange(copied, index - copied)]];
                [result appendString:emoji];
                copied = end + 1;
                index = end + 1;
                continue;
            }
        }
        index += 1;
    }
    if (result == nil) {
        return text;
    }
    [result appendString:[text substringFromIndex:copied]];
    return result;
}

static void OMAppendTextWithMathSpans(NSString *text,
                                      OMTheme *theme,
                                      NSMutableAttributedString *output,
                                      NSMutableDictionary *attributes,
                                      CGFloat scale,
                                      const OMRenderContext *renderContext)
{
    if (text == nil || [text length] == 0) {
        return;
    }
    if (!OMShouldParseMathSpans(renderContext)) {
        OMAppendString(output, OMStringByReplacingEmojiShortcodes(text), attributes);
        return;
    }

    NSUInteger length = [text length];
    NSUInteger cursor = 0;
    while (cursor < length) {
        NSUInteger dollarLocation = NSNotFound;
        for (NSUInteger i = cursor; i < length; i++) {
            if ([text characterAtIndex:i] == '$' && !OMDollarIsEscaped(text, i)) {
                dollarLocation = i;
                break;
            }
        }

        if (dollarLocation == NSNotFound) {
            OMAppendString(output, OMStringByReplacingEmojiShortcodes([text substringWithRange:NSMakeRange(cursor, length - cursor)]), attributes);
            break;
        }

        if (dollarLocation > cursor) {
            OMAppendString(output, OMStringByReplacingEmojiShortcodes([text substringWithRange:NSMakeRange(cursor, dollarLocation - cursor)]), attributes);
        }

        BOOL renderedMath = NO;
        BOOL isDisplayStart = (dollarLocation + 1 < length &&
                               [text characterAtIndex:dollarLocation + 1] == '$');

        if (isDisplayStart) {
            NSUInteger contentStart = dollarLocation + 2;
            NSUInteger i = contentStart;
            while (i + 1 < length) {
                if ([text characterAtIndex:i] == '$' &&
                    [text characterAtIndex:i + 1] == '$' &&
                    !OMDollarIsEscaped(text, i)) {
                    if (i > contentStart) {
                        NSString *formula = [text substringWithRange:NSMakeRange(contentStart, i - contentStart)];
                        formula = OMRawMathFormula(formula, YES, renderContext);
                        OMAppendDisplayMathFormula(formula,
                                                   theme,
                                                   output,
                                                   attributes,
                                                   scale,
                                                   renderContext);
                        renderedMath = YES;
                        cursor = i + 2;
                    }
                    break;
                }
                i += 1;
            }
        } else if (dollarLocation + 1 < length &&
                   !OMCharacterIsWhitespaceOrNewline([text characterAtIndex:dollarLocation + 1])) {
            NSUInteger i = dollarLocation + 1;
            while (i < length) {
                if ([text characterAtIndex:i] == '$' && !OMDollarIsEscaped(text, i)) {
                    BOOL precededByWhitespace = (i == 0) ? YES : OMCharacterIsWhitespaceOrNewline([text characterAtIndex:i - 1]);
                    BOOL followedByDigit = (i + 1 < length) ? OMCharacterIsDigit([text characterAtIndex:i + 1]) : NO;
                    BOOL adjacentToDollar = (i > 0 && [text characterAtIndex:i - 1] == '$') ||
                                            (i + 1 < length && [text characterAtIndex:i + 1] == '$');
                    if (!precededByWhitespace && !followedByDigit && !adjacentToDollar) {
                        NSString *formula = [text substringWithRange:NSMakeRange(dollarLocation + 1, i - (dollarLocation + 1))];
                        formula = OMRawMathFormula(formula, NO, renderContext);
                        if ([formula length] > 0) {
                            NSAttributedString *attachment = OMMathAttachmentAttributedString(formula,
                                                                                               theme,
                                                                                               attributes,
                                                                                               scale,
                                                                                               NO,
                                                                                               renderContext);
                            if (attachment != nil) {
                                NSUInteger objectStart = [output length];
                                OMAppendAttributedSegment(output, attachment);
                                OMTagAppendedObject(output,
                                                    objectStart,
                                                    OMRenderedObjectKindInlineMath,
                                                    formula,
                                                    [NSString stringWithFormat:@"$%@$", formula]);
                            } else {
                                NSDictionary *mathAttrs = OMMathAttributes(theme, attributes, scale, NO);
                                OMAppendString(output, OMReadableMathFallbackString(formula), mathAttrs);
                            }
                            renderedMath = YES;
                            cursor = i + 1;
                        }
                        break;
                    }
                }
                i += 1;
            }
        }

        if (!renderedMath) {
            OMAppendString(output, @"$", attributes);
            cursor = dollarLocation + 1;
        }
    }
}


@interface OMMarkdownRenderer ()
@property (nonatomic, retain) NSArray *codeBlockRanges;
@property (nonatomic, retain) NSArray *blockquoteRanges;
@property (nonatomic, retain) NSArray *blockAnchors;
@property (nonatomic, retain) NSArray *diagramBlocks;
@property (nonatomic, retain) NSArray *headings;
- (NSAttributedString *)om_attributedStringFromMarkdown:(NSString *)markdown;
@end

@implementation OMMarkdownRenderer

+ (NSString *)anchorSlugForHeadingTitle:(NSString *)title
{
    return OMHeadingAnchorSlug(title);
}

+ (void)invalidateCachedMathForFormula:(NSString *)formula
{
    if ([formula length] == 0) {
        return;
    }
    NSMutableDictionary *generations = OMMathFormulaGenerations();
    @synchronized (generations) {
        NSUInteger next = [[generations objectForKey:formula] unsignedIntegerValue] + 1;
        [generations setObject:[NSNumber numberWithUnsignedInteger:next] forKey:formula];
    }
}

+ (NSArray *)localImageURLsInMarkdown:(NSString *)markdown baseURL:(NSURL *)baseURL
{
    NSData *data = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return [NSArray array];
    }
    cmark_node *document = OMGFMParseDocument([data bytes], [data length], CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return [NSArray array];
    }
    OMMarkdownParsingOptions *options = [[[OMMarkdownParsingOptions alloc] init] autorelease];
    [options setBaseURL:baseURL];
    OMRenderContext context = {0};
    context.parsingOptions = options;
    NSMutableArray *urls = [NSMutableArray array];
    cmark_iter *iter = cmark_iter_new(document);
    cmark_event_type event;
    while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        cmark_node *node = cmark_iter_get_node(iter);
        if (event != CMARK_EVENT_ENTER || cmark_node_get_type(node) != CMARK_NODE_IMAGE) {
            continue;
        }
        const char *literal = cmark_node_get_url(node);
        NSURL *url = OMResolvedImageURL(literal ? [NSString stringWithUTF8String:literal] : nil, &context);
        if ([url isFileURL] && ![urls containsObject:url]) {
            [urls addObject:url];
        }
    }
    cmark_iter_free(iter);
    cmark_node_free(document);
    return urls;
}

@synthesize zoomScale = _zoomScale;
@synthesize layoutWidth = _layoutWidth;
@synthesize allowTableHorizontalOverflow = _allowTableHorizontalOverflow;
@synthesize asynchronousMathGenerationEnabled = _asynchronousMathGenerationEnabled;
@synthesize parsingOptions = _parsingOptions;
@synthesize codeBlockRanges = _codeBlockRanges;
@synthesize blockquoteRanges = _blockquoteRanges;
@synthesize blockAnchors = _blockAnchors;

+ (BOOL)isTreeSitterAvailable
{
    return OMTreeSitterRuntimeAvailable();
}

- (instancetype)init
{
    return [self initWithTheme:[OMTheme defaultTheme]
                parsingOptions:[OMMarkdownParsingOptions defaultOptions]];
}

- (instancetype)initWithTheme:(OMTheme *)theme
{
    return [self initWithTheme:theme
                parsingOptions:[OMMarkdownParsingOptions defaultOptions]];
}

- (instancetype)initWithTheme:(OMTheme *)theme parsingOptions:(OMMarkdownParsingOptions *)parsingOptions
{
    self = [super init];
    if (self) {
        NSRecursiveLock *lock = OMAppKitGlobalLock();
        [lock lock];
        if (theme == nil) {
            theme = [OMTheme defaultTheme];
        }
        if (parsingOptions == nil) {
            parsingOptions = [OMMarkdownParsingOptions defaultOptions];
        }
        [lock unlock];
        _theme = [theme retain];
        _parsingOptions = [parsingOptions copy];
        _zoomScale = 1.0;
        _layoutWidth = 0.0;
        _allowTableHorizontalOverflow = NO;
        _asynchronousMathGenerationEnabled = NO;
    }
    return self;
}

- (void)dealloc
{
    [_codeBlockRanges release];
    [_blockquoteRanges release];
    [_blockAnchors release];
    [_diagramBlocks release];
    [_headings release];
    [_parsingOptions release];
    [_theme release];
    [super dealloc];
}

- (void)setParsingOptions:(OMMarkdownParsingOptions *)parsingOptions
{
    OMMarkdownParsingOptions *resolved = parsingOptions;
    if (resolved == nil) {
        resolved = [OMMarkdownParsingOptions defaultOptions];
    }
    if (_parsingOptions == resolved) {
        return;
    }
    [_parsingOptions release];
    _parsingOptions = [resolved copy];
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown
{
    NSRecursiveLock *lock = OMAppKitGlobalLock();
    [lock lock];
    @try {
        return [self om_attributedStringFromMarkdown:markdown];
    } @finally {
        [lock unlock];
    }
}

- (NSAttributedString *)om_attributedStringFromMarkdown:(NSString *)markdown
{
    if (markdown == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    NSString *markdownForParsing = OMMarkdownByBlankingFrontMatter(markdown);
    if (markdownForParsing == nil) {
        markdownForParsing = markdown;
    }

    BOOL perfLogging = OMPerformanceLoggingEnabled();
    NSTimeInterval totalStart = perfLogging ? OMNow() : 0.0;

    NSData *markdownData = [markdownForParsing dataUsingEncoding:NSUTF8StringEncoding];
    if (markdownData == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    const char *bytes = (const char *)[markdownData bytes];
    size_t length = (size_t)[markdownData length];
    NSUInteger cmarkOptions = self.parsingOptions != nil ? [self.parsingOptions cmarkOptions] : (NSUInteger)CMARK_OPT_DEFAULT;
    NSTimeInterval parseStart = perfLogging ? OMNow() : 0.0;
    cmark_node *document = OMGFMParseDocument(bytes, length, (int)cmarkOptions);
    NSTimeInterval parseMs = perfLogging ? ((OMNow() - parseStart) * 1000.0) : 0.0;
    if (document == NULL) {
        if (perfLogging) {
            NSLog(@"[Perf][Renderer] parse failed chars=%lu parse=%.1fms total=%.1fms",
                  (unsigned long)[markdown length],
                  parseMs,
                  (OMNow() - totalStart) * 1000.0);
        }
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
    NSMutableArray *blockAnchors = [NSMutableArray array];
    NSMutableArray *diagramBlocks = [NSMutableArray array];
    NSMutableArray *consumedDisplayMathLineRanges = [NSMutableArray array];
    NSArray *sourceLines = OMSourceLinesForMarkdown(markdown);
    OMMathPerfStats stats = {0};
    OMRenderContext renderContext;
    renderContext.parsingOptions = self.parsingOptions;
    renderContext.sourceLines = sourceLines;
    OMBlockSignatureIndex *blockSignatures = [[[OMBlockSignatureIndex alloc] initWithSourceLines:sourceLines] autorelease];
    renderContext.blockSignatures = blockSignatures;
    renderContext.blockAnchors = blockAnchors;
    renderContext.diagramBlocks = diagramBlocks;
    renderContext.listStack = listStack;
    renderContext.quoteKinds = [NSMutableArray array];
    NSMutableArray *headings = [NSMutableArray array];
    renderContext.headings = headings;
    renderContext.headingSlugCounts = [NSMutableDictionary dictionary];
    renderContext.consumedDisplayMathLineRanges = consumedDisplayMathLineRanges;
    renderContext.rawMathSources = [NSMutableDictionary dictionary];
    renderContext.mathPerfStats = &stats;
    renderContext.layoutWidth = self.layoutWidth;
    renderContext.allowTableHorizontalOverflow = self.allowTableHorizontalOverflow;
    renderContext.asynchronousMathGenerationEnabled = self.asynchronousMathGenerationEnabled;
    NSTimeInterval renderStart = perfLogging ? OMNow() : 0.0;
    OMRenderBlocks(document,
                   self.theme,
                   output,
                   attributes,
                   codeRanges,
                   blockquoteRanges,
                   listStack,
                   0,
                   scale,
                   self.layoutWidth,
                   &renderContext);
    NSTimeInterval renderMs = perfLogging ? ((OMNow() - renderStart) * 1000.0) : 0.0;
    [self setBlockAnchors:blockAnchors];
    [self setDiagramBlocks:diagramBlocks];
    [self setHeadings:headings];
    OMTrimTrailingNewlines(output);
    [self setCodeBlockRanges:OMRangesClampedToLength(codeRanges, [output length])];
    [self setBlockquoteRanges:OMRangesClampedToLength(blockquoteRanges, [output length])];
    OMApplyEmojiFont(output, codeRanges);
    OMSizeBlockGaps(output,
                    codeRanges,
                    (self.theme.baseFont != nil ? [self.theme.baseFont pointSize] : 14.0) * scale,
                    scale);
    [output removeAttribute:OMHardLineBreakAttributeName range:NSMakeRange(0, [output length])];
    OMResolvePendingRenderedObjects(output, blockAnchors, markdown);
    cmark_node_free(document);
    if (perfLogging) {
        NSLog(@"[Perf][Renderer] total=%.1fms parse=%.1fms render=%.1fms charsIn=%lu charsOut=%lu zoom=%.2f width=%.1f math(req=%lu hit=%lu miss=%lu assetHit=%lu assetMiss=%lu ok=%lu fail=%lu total=%.1fms latex=%lums/%lu dvisvgm=%lums/%lu decode=%.1fms)",
              (OMNow() - totalStart) * 1000.0,
              parseMs,
              renderMs,
              (unsigned long)[markdown length],
              (unsigned long)[output length],
              self.zoomScale,
              self.layoutWidth,
              (unsigned long)stats.mathRequests,
              (unsigned long)stats.mathCacheHits,
              (unsigned long)stats.mathCacheMisses,
              (unsigned long)stats.mathAssetCacheHits,
              (unsigned long)stats.mathAssetCacheMisses,
              (unsigned long)stats.mathRendered,
              (unsigned long)stats.mathFailures,
              stats.mathTotalSeconds * 1000.0,
              (unsigned long)(stats.latexSeconds * 1000.0 + 0.5),
              (unsigned long)stats.latexRuns,
              (unsigned long)(stats.dvisvgmSeconds * 1000.0 + 0.5),
              (unsigned long)stats.dvisvgmRuns,
              stats.svgDecodeSeconds * 1000.0);
    }
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
                              CGFloat scale,
                              const OMRenderContext *renderContext)
{
    NSMutableDictionary *paraAttrs = [attributes mutableCopy];
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    NSParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 12.0 * scale, 0.0, 1.5, fontSize);
    [paraAttrs setObject:style forKey:NSParagraphStyleAttributeName];
    BOOL inAlert = (renderContext != NULL && [[renderContext->quoteKinds lastObject] boolValue]);
    if (quoteLevel > 0 && !inAlert && theme.blockquoteTextColor != nil) {
        [paraAttrs setObject:theme.blockquoteTextColor forKey:NSForegroundColorAttributeName];
    }

    NSUInteger paragraphStart = [output length];
    OMPrepareRawMathSources(node, renderContext);
    OMRenderInlines(node, theme, output, paraAttrs, scale, renderContext);
    [paraAttrs release];
    OMTightenHardLineBreaks(output, NSMakeRange(paragraphStart, [output length] - paragraphStart));

    if (OMIsTightList(listStack)) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static NSString *OMHeadingAnchorSlug(NSString *title)
{
    NSString *lower = [(title != nil ? title : @"") lowercaseString];
    NSMutableCharacterSet *kept = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [kept addCharactersInString:@"_- "];
    NSMutableString *slug = [NSMutableString stringWithCapacity:[lower length]];
    NSUInteger index = 0;
    for (; index < [lower length]; index++) {
        unichar ch = [lower characterAtIndex:index];
        if (ch == ' ') {
            [slug appendString:@"-"];
        } else if ([kept characterIsMember:ch]) {
            [slug appendFormat:@"%C", ch];
        }
    }
    return slug;
}

// GitHub's de-duplication (github-slugger): a repeat of "x" becomes "x-1",
// then "x-2", skipping any slug already taken.
static NSString *OMUniqueHeadingSlug(NSString *title, NSMutableDictionary *counts)
{
    NSString *original = OMHeadingAnchorSlug(title);
    if (counts == nil) {
        return original;
    }
    NSString *slug = original;
    while ([counts objectForKey:slug] != nil) {
        NSUInteger next = [[counts objectForKey:original] unsignedIntegerValue] + 1;
        [counts setObject:[NSNumber numberWithUnsignedInteger:next] forKey:original];
        slug = [NSString stringWithFormat:@"%@-%lu", original, (unsigned long)next];
    }
    [counts setObject:[NSNumber numberWithUnsignedInteger:0] forKey:slug];
    return slug;
}

static void OMRenderHeading(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            NSUInteger quoteLevel,
                            CGFloat scale,
                            CGFloat layoutWidth,
                            const OMRenderContext *renderContext)
{
    int level = cmark_node_get_heading_level(node);
    NSMutableDictionary *headingAttrs = [attributes mutableCopy];
    NSDictionary *headingStyle = OMHeadingAttributes(theme, (NSUInteger)level, scale);
    [headingAttrs addEntriesFromDictionary:headingStyle];

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    NSFont *font = [headingAttrs objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    // GitHub: 24px above a heading, 16px below; H1 and H2 are underlined.
    BOOL underlined = (level <= 2);
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent,
                                                                (underlined ? 6.0 : 12.0) * scale,
                                                                0.0, 1.25, fontSize);
    [style setParagraphSpacingBefore:8.0 * scale];
    [headingAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMPrepareRawMathSources(node, renderContext);
    NSUInteger headingStart = [output length];
    OMRenderInlines(node, theme, output, headingAttrs, scale, renderContext);
    [headingAttrs release];
    NSRange headingRange = NSMakeRange(headingStart, [output length] - headingStart);
    if (renderContext != NULL && renderContext->headings != nil) {
        NSString *title = OMInlinePlainText(node);
        NSString *anchor = OMUniqueHeadingSlug(title, renderContext->headingSlugCounts);
        if (headingRange.length > 0) {
            [output addAttribute:OMMarkdownRendererHeadingAnchorAttributeName value:anchor range:headingRange];
        }
        [renderContext->headings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:level], OMMarkdownRendererHeadingLevelKey,
            (title != nil ? title : @""), OMMarkdownRendererHeadingTitleKey,
            anchor, OMMarkdownRendererHeadingAnchorKey,
            [NSValue valueWithRange:headingRange], OMMarkdownRendererHeadingRangeKey,
            [NSNumber numberWithInt:cmark_node_get_start_line(node)], OMMarkdownRendererHeadingSourceLineKey,
            nil]];
    }
    OMAppendString(output, @"\n", attributes);

    if (underlined && theme.hrColor != nil) {
        CGFloat availableWidth = layoutWidth > 0.0 ? (layoutWidth - indent) : 0.0;
        OMAppendRule(output, attributes, theme.hrColor, availableWidth, MAX(1.0, floor(scale + 0.5)), indent, 12.0 * scale);
    }
    OMAppendString(output, @"\n", attributes);
}


static void OMRenderCodeBlock(cmark_node *node,
                              OMTheme *theme,
                              NSMutableAttributedString *output,
                              NSMutableDictionary *attributes,
                              NSUInteger quoteLevel,
                              CGFloat scale,
                              NSMutableArray *codeRanges,
                              const OMRenderContext *renderContext)
{
    const char *literal = cmark_node_get_literal(node);
    NSString *code = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
    NSString *mermaidDiagnostic = nil;
    if (OMTryRenderMermaidDiagram(node,
                                  code,
                                  theme,
                                  output,
                                  attributes,
                                  quoteLevel,
                                  scale,
                                  renderContext,
                                  &mermaidDiagnostic)) {
        return;
    }

    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    CGFloat blockCodeFontSize = size * 0.92;
    if (blockCodeFontSize < 11.0 * scale) {
        blockCodeFontSize = 11.0 * scale;
    }
    NSDictionary *codeAttrs = [theme codeAttributesForSize:blockCodeFontSize];

    NSMutableDictionary *blockAttrs = [attributes mutableCopy];
    [blockAttrs addEntriesFromDictionary:codeAttrs];
    NSColor *codeBackgroundColor = [blockAttrs objectForKey:NSBackgroundColorAttributeName];
    if (codeBackgroundColor != nil) {
        // Block code container background is drawn by OMDTextView; keep inline code background separate.
        [blockAttrs removeObjectForKey:NSBackgroundColorAttributeName];
    }

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    CGFloat padding = 20.0 * scale;
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent + padding,
                                                                indent + padding,
                                                                14.0 * scale,
                                                                0.0,
                                                                1.45,
                                                                blockCodeFontSize);
    [style setParagraphSpacingBefore:10.0 * scale];
    [style setTailIndent:-padding];
    [blockAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    NSUInteger startLocation = [output length];
    NSMutableAttributedString *codeSegment = [[[NSMutableAttributedString alloc] initWithString:code
                                                                                      attributes:blockAttrs] autorelease];
    OMApplyCodeSyntaxHighlighting(node, codeSegment, codeBackgroundColor, renderContext);
    OMAppendAttributedSegment(output, codeSegment);
    if ([code length] > 0) {
        [codeRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, [code length])]];
    }
    if (![code hasSuffix:@"\n"]) {
        OMAppendString(output, @"\n", blockAttrs);
    }
    OMAppendMermaidDiagnostic(mermaidDiagnostic,
                              theme,
                              output,
                              blockAttrs,
                              indent + padding,
                              blockCodeFontSize,
                              scale);
    OMAppendString(output, @"\n", attributes);
    [blockAttrs release];
}

static void OMRenderThematicBreak(OMTheme *theme,
                                  NSMutableAttributedString *output,
                                  NSMutableDictionary *attributes,
                                  CGFloat layoutWidth)
{
    // GitHub draws <hr> as a bar a quarter of the text size tall.
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : 14.0;
    NSColor *color = theme.hrColor != nil ? theme.hrColor : [NSColor lightGrayColor];
    OMAppendRule(output, attributes, color, layoutWidth, MAX(2.0, floor(size * 0.25 + 0.5)), 0.0, 12.0);
    OMAppendString(output, @"\n", attributes);
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
                         CGFloat layoutWidth,
                         const OMRenderContext *renderContext)
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
        OMRenderBlocks(child,
                       theme,
                       output,
                       attributes,
                       codeRanges,
                       blockquoteRanges,
                       listStack,
                       quoteLevel,
                       scale,
                       layoutWidth,
                       renderContext);
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
        // Loose items already end in a blank line; top it up to one.
        NSString *text = [output string];
        NSUInteger trailing = 0;
        while (trailing < 2 && trailing < [text length] &&
               [text characterAtIndex:([text length] - 1 - trailing)] == '\n') {
            trailing += 1;
        }
        for (; trailing < 2; trailing++) {
            OMAppendString(output, @"\n", attributes);
        }
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
                             CGFloat layoutWidth,
                             const OMRenderContext *renderContext)
{
    NSUInteger startLocation = [output length];
    NSString *prefix = OMListPrefix(listStack);
    if (OMGFMNodeIsTaskItem(node)) {
        NSString *box = cmark_gfm_extensions_get_tasklist_item_checked(node) ? @"\u2611 " : @"\u2610 ";
        BOOL bullet = ((cmark_list_type)[[OMListContext(listStack) objectForKey:@"type"] intValue] == CMARK_BULLET_LIST);
        prefix = bullet ? box : [prefix stringByAppendingString:box];
    }
    OMAppendString(output, prefix, attributes);

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child,
                       theme,
                       output,
                       attributes,
                       codeRanges,
                       blockquoteRanges,
                       listStack,
                       quoteLevel,
                       scale,
                       layoutWidth,
                       renderContext);
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
                                                        1.5,
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

// GitHub alerts: a block quote whose first line is exactly "[!NOTE]",
// "[!TIP]", "[!IMPORTANT]", "[!WARNING]" or "[!CAUTION]".
static NSString *OMAlertKindForBlockquote(cmark_node *node, const OMRenderContext *renderContext)
{
    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    int line = cmark_node_get_start_line(node);
    if (sourceLines == nil || line < 1 || (NSUInteger)line > [sourceLines count]) {
        return nil;
    }
    // The marker line carries one ">" per enclosing quote.
    NSUInteger depth = 0;
    cmark_node *ancestor = node;
    for (; ancestor != NULL; ancestor = cmark_node_parent(ancestor)) {
        if (cmark_node_get_type(ancestor) == CMARK_NODE_BLOCK_QUOTE) {
            depth += 1;
        }
    }
    NSString *text = [sourceLines objectAtIndex:(NSUInteger)line - 1];
    NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
    NSUInteger index = 0;
    NSUInteger markers = 0;
    while (index < [text length]) {
        unichar ch = [text characterAtIndex:index];
        if (ch == '>') {
            markers += 1;
        } else if (![spaces characterIsMember:ch]) {
            break;
        }
        index += 1;
    }
    if (markers != depth) {
        return nil;
    }
    NSString *rest = [[[text substringFromIndex:index] stringByTrimmingCharactersInSet:spaces] uppercaseString];
    NSArray *kinds = [NSArray arrayWithObjects:@"NOTE", @"TIP", @"IMPORTANT", @"WARNING", @"CAUTION", nil];
    for (NSString *kind in kinds) {
        if ([rest isEqualToString:[NSString stringWithFormat:@"[!%@]", kind]]) {
            return kind;
        }
    }
    return nil;
}

// Drops the marker line from the quote's first paragraph (the paragraph
// itself when the marker was all it held).
static void OMStripAlertMarker(cmark_node *quote)
{
    cmark_node *paragraph = cmark_node_first_child(quote);
    if (paragraph == NULL || cmark_node_get_type(paragraph) != CMARK_NODE_PARAGRAPH) {
        return;
    }
    cmark_node *child = cmark_node_first_child(paragraph);
    while (child != NULL) {
        cmark_node *next = cmark_node_next(child);
        cmark_node_type type = cmark_node_get_type(child);
        cmark_node_free(child);
        child = next;
        if (type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK) {
            break;
        }
    }
    if (cmark_node_first_child(paragraph) == NULL) {
        cmark_node_free(paragraph);
    }
}

// GitHub's alert colours (light and dark palettes) and titles.
static NSColor *OMAlertColor(NSString *kind, OMTheme *theme)
{
    BOOL dark = [theme isDark];
    NSDictionary *light = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"#0969da", @"NOTE", @"#1a7f37", @"TIP", @"#8250df", @"IMPORTANT",
                           @"#9a6700", @"WARNING", @"#d1242f", @"CAUTION", nil];
    NSDictionary *darkColors = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"#4493f8", @"NOTE", @"#3fb950", @"TIP", @"#ab7df8", @"IMPORTANT",
                                @"#d29922", @"WARNING", @"#f85149", @"CAUTION", nil];
    NSString *hex = [(dark ? darkColors : light) objectForKey:kind];
    unsigned int value = 0;
    if (hex == nil || ![[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&value]) {
        return theme.linkColor;
    }
    return [NSColor colorWithCalibratedRed:((value >> 16) & 0xff) / 255.0
                                     green:((value >> 8) & 0xff) / 255.0
                                      blue:(value & 0xff) / 255.0
                                     alpha:1.0];
}

static void OMAppendAlertTitle(NSString *kind,
                               NSColor *color,
                               OMTheme *theme,
                               NSMutableAttributedString *output,
                               NSMutableDictionary *attributes,
                               NSUInteger quoteLevel,
                               CGFloat scale,
                               const OMRenderContext *renderContext)
{
    NSString *title = [[kind substringToIndex:1] stringByAppendingString:[[kind substringFromIndex:1] lowercaseString]];
    NSMutableDictionary *titleAttrs = [attributes mutableCopy];
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : 14.0 * scale;
    NSFont *bold = font != nil ? OMFontWithTraits(font, NSBoldFontMask) : [NSFont boldSystemFontOfSize:fontSize];
    if (bold != nil) {
        [titleAttrs setObject:bold forKey:NSFontAttributeName];
    }
    if (color != nil) {
        [titleAttrs setObject:color forKey:NSForegroundColorAttributeName];
    }
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    [titleAttrs setObject:OMParagraphStyleWithIndent(indent, indent, 4.0 * scale, 0.0, 1.5, fontSize)
                   forKey:NSParagraphStyleAttributeName];
    OMAppendString(output, title, titleAttrs);
    OMAppendString(output, @"\n", titleAttrs);
    [titleAttrs release];
}

// Footnotes come last in the document (cmark-gfm moves them there, in order
// of first reference): a rule, then each note as a numbered item.
static void OMRenderFootnoteDefinition(cmark_node *node,
                                       OMTheme *theme,
                                       NSMutableAttributedString *output,
                                       NSMutableDictionary *attributes,
                                       NSMutableArray *codeRanges,
                                       NSMutableArray *blockquoteRanges,
                                       NSMutableArray *listStack,
                                       NSUInteger quoteLevel,
                                       CGFloat scale,
                                       CGFloat layoutWidth,
                                       const OMRenderContext *renderContext)
{
    NSUInteger number = 1;
    cmark_node *previous = cmark_node_previous(node);
    for (; previous != NULL; previous = cmark_node_previous(previous)) {
        if (cmark_node_get_type(previous) == CMARK_NODE_FOOTNOTE_DEFINITION) {
            number += 1;
        }
    }
    if (number == 1) {
        OMRenderThematicBreak(theme, output, attributes, layoutWidth);
    }
    NSMutableDictionary *listInfo = [NSMutableDictionary dictionary];
    [listInfo setObject:[NSNumber numberWithInt:CMARK_ORDERED_LIST] forKey:@"type"];
    [listInfo setObject:[NSNumber numberWithUnsignedInteger:number] forKey:@"index"];
    [listInfo setObject:[NSNumber numberWithBool:YES] forKey:@"tight"];
    [listStack addObject:listInfo];
    OMRenderListItem(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth, renderContext);
    [listStack removeLastObject];
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
                           CGFloat layoutWidth,
                           const OMRenderContext *renderContext)
{
    NSUInteger startLocation = [output length];
    cmark_node_type type = cmark_node_get_type(node);
    NSUInteger sourceStartLine = 0;
    BOOL hasSourceLineBounds = OMNodeLineBounds(node, &sourceStartLine, NULL);
    if (hasSourceLineBounds && OMDisplayMathLineAlreadyConsumed(sourceStartLine, renderContext)) {
        return;
    }
    if (OMTryRenderRawDisplayMathBlock(node,
                                       theme,
                                       output,
                                       attributes,
                                       listStack,
                                       scale,
                                       renderContext)) {
        return;
    }
    if (type == CMARK_NODE_BLOCK_QUOTE) {
        NSString *alertKind = OMAlertKindForBlockquote(node, renderContext);
        NSColor *alertColor = nil;
        if (alertKind != nil) {
            OMStripAlertMarker(node);
            alertColor = OMAlertColor(alertKind, theme);
            OMAppendAlertTitle(alertKind, alertColor, theme, output, attributes, quoteLevel + 1, scale, renderContext);
        }
        if (renderContext != NULL) {
            [renderContext->quoteKinds addObject:[NSNumber numberWithBool:(alertKind != nil)]];
        }
        cmark_node *child = cmark_node_first_child(node);
        while (child != NULL) {
            OMRenderBlocks(child,
                           theme,
                           output,
                           attributes,
                           codeRanges,
                           blockquoteRanges,
                           listStack,
                           quoteLevel + 1,
                           scale,
                           layoutWidth,
                           renderContext);
            child = cmark_node_next(child);
        }
        NSUInteger endLocation = [output length];
        if (endLocation > startLocation) {
            // The bar stops at the quote's last line, not in the gap after it.
            NSUInteger barEnd = endLocation;
            NSString *text = [output string];
            while (barEnd > startLocation + 1 && [text characterAtIndex:barEnd - 1] == '\n' &&
                   [text characterAtIndex:barEnd - 2] == '\n') {
                barEnd -= 1;
            }
            [blockquoteRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, barEnd - startLocation)]];
            if (alertColor != nil) {
                [output addAttribute:OMMarkdownRendererBlockquoteColorAttributeName
                               value:alertColor
                               range:NSMakeRange(startLocation, barEnd - startLocation)];
            }
            OMRecordBlockAnchor(node, startLocation, endLocation, renderContext);
        }
        if (renderContext != NULL) {
            [renderContext->quoteKinds removeLastObject];
        }
        return;
    }
    // Extension node types are assigned at run time, so they can't be cases.
    if (type == CMARK_NODE_TABLE) {
        OMRenderGFMTable(node, theme, output, attributes, listStack, quoteLevel, scale, layoutWidth, renderContext);
        OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
        return;
    }
    if (type == CMARK_NODE_FOOTNOTE_DEFINITION) {
        OMRenderFootnoteDefinition(node, theme, output, attributes, codeRanges, blockquoteRanges,
                                   listStack, quoteLevel, scale, layoutWidth, renderContext);
        OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
        return;
    }
    switch (type) {
        case CMARK_NODE_DOCUMENT:
            break;
        case CMARK_NODE_PARAGRAPH:
            OMRenderParagraph(node, theme, output, attributes, listStack, quoteLevel, scale, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_HEADING:
            OMRenderHeading(node, theme, output, attributes, quoteLevel, scale, layoutWidth, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_CODE_BLOCK:
            OMRenderCodeBlock(node, theme, output, attributes, quoteLevel, scale, codeRanges, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_THEMATIC_BREAK:
            OMRenderThematicBreak(theme, output, attributes, layoutWidth);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_BLOCK_QUOTE:
            quoteLevel += 1;
            break;
        case CMARK_NODE_LIST:
            OMRenderList(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_ITEM:
            OMRenderListItem(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_HTML_BLOCK: {
            const char *literal = cmark_node_get_literal(node);
            OMAppendHTMLLiteral(literal, output, attributes, YES, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        }
        case CMARK_NODE_CUSTOM_BLOCK: {
            const char *literal = cmark_node_get_literal(node);
            OMAppendHTMLLiteral(literal, output, attributes, YES, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        }
        default:
            break;
    }

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child,
                       theme,
                       output,
                       attributes,
                       codeRanges,
                       blockquoteRanges,
                       listStack,
                       quoteLevel,
                       scale,
                       layoutWidth,
                       renderContext);
        child = cmark_node_next(child);
    }
}

void OMRenderInlines(cmark_node *node,
                     OMTheme *theme,
                     NSMutableAttributedString *output,
                     NSMutableDictionary *attributes,
                     CGFloat scale,
                     const OMRenderContext *renderContext)
{
    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        if (type == CMARK_NODE_STRIKETHROUGH) {
            NSMutableDictionary *struckAttrs = [attributes mutableCopy];
            [struckAttrs setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
                            forKey:NSStrikethroughStyleAttributeName];
            OMRenderInlines(child, theme, output, struckAttrs, scale, renderContext);
            [struckAttrs release];
            child = cmark_node_next(child);
            continue;
        }
        switch (type) {
            case CMARK_NODE_TEXT: {
                BOOL renderedDisplayMath = NO;
                cmark_node *nextAfterDisplayMath = OMTryAppendMultiNodeDisplayMath(child,
                                                                                    theme,
                                                                                    output,
                                                                                    attributes,
                                                                                    scale,
                                                                                    &renderedDisplayMath,
                                                                                    renderContext);
                if (renderedDisplayMath) {
                    child = nextAfterDisplayMath;
                    continue;
                }
                const char *literal = cmark_node_get_literal(child);
                NSString *text = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                OMAppendTextWithMathSpans(text, theme, output, attributes, scale, renderContext);
                break;
            }
            case CMARK_NODE_FOOTNOTE_REFERENCE: {
                // The literal is the footnote's number.
                const char *literal = cmark_node_get_literal(child);
                NSString *number = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                NSMutableDictionary *refAttrs = [attributes mutableCopy];
                NSFont *font = [attributes objectForKey:NSFontAttributeName];
                CGFloat size = font != nil ? [font pointSize] : 14.0 * scale;
                NSFont *smaller = font != nil ? [NSFont fontWithName:[font fontName] size:size * 0.72] : nil;
                if (smaller != nil) {
                    [refAttrs setObject:smaller forKey:NSFontAttributeName];
                }
                // GNUstep applies NSBaselineOffsetAttributeName upside down; superscript
                // is raised correctly on both GNUstep and macOS.
                [refAttrs setObject:[NSNumber numberWithInt:1] forKey:NSSuperscriptAttributeName];
                if (theme.linkColor != nil) {
                    [refAttrs setObject:theme.linkColor forKey:NSForegroundColorAttributeName];
                }
                OMAppendString(output, number, refAttrs);
                [refAttrs release];
                break;
            }
            case CMARK_NODE_SOFTBREAK:
                OMAppendString(output, @" ", attributes);
                break;
            case CMARK_NODE_LINEBREAK: {
                NSMutableDictionary *breakAttrs = [attributes mutableCopy];
                [breakAttrs setObject:[NSNumber numberWithBool:YES] forKey:OMHardLineBreakAttributeName];
                OMAppendString(output, @"\n", breakAttrs);
                [breakAttrs release];
                break;
            }
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
                OMApplyItalicFallbackIfNeeded(emphAttrs, font, newFont);
                OMRenderInlines(child, theme, output, emphAttrs, scale, renderContext);
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
                OMRenderInlines(child, theme, output, strongAttrs, scale, renderContext);
                [strongAttrs release];
                break;
            }
            case CMARK_NODE_LINK: {
                const char *url = cmark_node_get_url(child);
                NSString *urlString = url != NULL ? [NSString stringWithUTF8String:url] : @"";
                NSMutableDictionary *linkAttrs = [attributes mutableCopy];
                BOOL hasValidLinkURL = NO;
                if ([urlString length] > 0) {
                    NSURL *linkURL = OMResolvedLinkURL(urlString, renderContext);
                    if (linkURL != nil) {
                        [linkAttrs setObject:linkURL forKey:NSLinkAttributeName];
                        hasValidLinkURL = YES;
                    }
                }
                if (hasValidLinkURL && theme.linkColor != nil) {
                    [linkAttrs setObject:theme.linkColor forKey:NSForegroundColorAttributeName];
                }
                // The link's title, else where it goes (the viewer has no status bar).
                const char *linkTitle = cmark_node_get_title(child);
                NSString *toolTip = (linkTitle != NULL && linkTitle[0] != '\0')
                    ? [NSString stringWithUTF8String:linkTitle]
                    : urlString;
                if ([toolTip length] > 0 && hasValidLinkURL) {
                    [linkAttrs setObject:toolTip forKey:NSToolTipAttributeName];
                }
                OMRenderInlines(child, theme, output, linkAttrs, scale, renderContext);
                [linkAttrs release];
                break;
            }
            case CMARK_NODE_IMAGE: {
                if (!OMShouldRenderImages(renderContext)) {
                    OMAppendString(output, OMFallbackImageTextForNode(child), attributes);
                } else {
                    NSAttributedString *attachment = OMImageAttachmentAttributedString(child,
                                                                                       attributes,
                                                                                       scale,
                                                                                       renderContext);
                    if (attachment != nil) {
                        NSUInteger objectStart = [output length];
                        OMAppendAttributedSegment(output, attachment);
                        const char *imageTitle = cmark_node_get_title(child);
                        if (imageTitle != NULL && imageTitle[0] != '\0' && [output length] > objectStart) {
                            [output addAttribute:NSToolTipAttributeName
                                           value:[NSString stringWithUTF8String:imageTitle]
                                           range:NSMakeRange(objectStart, [output length] - objectStart)];
                        }
                        OMTagAppendedObject(output,
                                            objectStart,
                                            OMRenderedObjectKindImage,
                                            OMImageMarkdownForNode(child),
                                            nil);
                    } else {
                        OMAppendString(output, OMFallbackImageTextForNode(child), attributes);
                    }
                }
                break;
            }
            case CMARK_NODE_HTML_INLINE: {
                const char *literal = cmark_node_get_literal(child);
                OMAppendHTMLLiteral(literal, output, attributes, NO, renderContext);
                break;
            }
            case CMARK_NODE_CUSTOM_INLINE: {
                const char *literal = cmark_node_get_literal(child);
                if (literal != NULL) {
                    OMAppendHTMLLiteral(literal, output, attributes, NO, renderContext);
                } else {
                    OMRenderInlines(child, theme, output, attributes, scale, renderContext);
                }
                break;
            }
            default:
                OMRenderInlines(child, theme, output, attributes, scale, renderContext);
                break;
        }
        child = cmark_node_next(child);
    }
}

@end
