// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMSlackMrkdwn.h"
#include <string.h>
#include "OMGFMParser.h"
#include "cmark-gfm-core-extensions.h"
#include "strikethrough.h"
#include "table.h"

typedef struct {
    OMSlackMrkdwnOptions options;
    // Nesting of lists, for the bullet character and the indent.
    NSUInteger listDepth;
} OMSlackContext;

static NSString *OMSlackBlocks(cmark_node *parent, OMSlackContext *context, NSString *separator);

static NSString *OMSlackLiteral(cmark_node *node)
{
    const char *literal = cmark_node_get_literal(node);
    return literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
}

static NSString *OMSlackEscaped(NSString *text, OMSlackContext *context)
{
    if ((context->options & OMSlackMrkdwnOptionsAPI) == 0) {
        return text;
    }
    NSMutableString *escaped = [NSMutableString stringWithString:text];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [escaped length])];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [escaped length])];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [escaped length])];
    return escaped;
}

// The text of the inlines under parent. Plain leaves out the markers
// (inside a heading, which is bold already, and in a table, which is a code
// block where Slack shows them as they are).
static NSString *OMSlackInlines(cmark_node *parent, OMSlackContext *context, BOOL plain);

static NSString *OMSlackWrapped(NSString *inner, NSString *marker)
{
    // Slack shows "**" as it is, and markers around spaces don't format.
    NSString *trimmed = [inner stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed length] == 0) {
        return inner;
    }
    return [NSString stringWithFormat:@"%@%@%@", marker, trimmed, marker];
}

static NSString *OMSlackLink(NSString *url, NSString *text, OMSlackContext *context)
{
    if ([url length] == 0) {
        return text;
    }
    BOOL sameText = ([text length] == 0 ||
                     [text isEqualToString:url] ||
                     [[@"mailto:" stringByAppendingString:text] isEqualToString:url]);
    if ((context->options & OMSlackMrkdwnOptionsAPI) != 0) {
        NSString *escapedURL = OMSlackEscaped(url, context);
        return sameText ? [NSString stringWithFormat:@"<%@>", escapedURL]
                        : [NSString stringWithFormat:@"<%@|%@>", escapedURL, text];
    }
    return sameText ? url : [NSString stringWithFormat:@"%@ (%@)", text, url];
}

static NSString *OMSlackInline(cmark_node *node, OMSlackContext *context, BOOL plain)
{
    cmark_node_type type = cmark_node_get_type(node);
    if (type == CMARK_NODE_TEXT) {
        return OMSlackEscaped(OMSlackLiteral(node), context);
    }
    if (type == CMARK_NODE_SOFTBREAK) {
        return @" ";
    }
    if (type == CMARK_NODE_LINEBREAK) {
        return @"\n";
    }
    if (type == CMARK_NODE_CODE) {
        NSString *code = OMSlackEscaped(OMSlackLiteral(node), context);
        return plain ? code : [NSString stringWithFormat:@"`%@`", code];
    }
    if (type == CMARK_NODE_HTML_INLINE) {
        return @"";
    }
    if (type == CMARK_NODE_FOOTNOTE_REFERENCE) {
        return [NSString stringWithFormat:@"[%@]", OMSlackLiteral(node)];
    }
    NSString *inner = OMSlackInlines(node, context, plain);
    if (type == CMARK_NODE_EMPH) {
        return plain ? inner : OMSlackWrapped(inner, @"_");
    }
    if (type == CMARK_NODE_STRONG) {
        return plain ? inner : OMSlackWrapped(inner, @"*");
    }
    if (type == CMARK_NODE_STRIKETHROUGH) {
        return plain ? inner : OMSlackWrapped(inner, @"~");
    }
    if (type == CMARK_NODE_LINK || type == CMARK_NODE_IMAGE) {
        const char *url = cmark_node_get_url(node);
        NSString *link = (url != NULL ? [NSString stringWithUTF8String:url] : @"");
        return plain ? inner : OMSlackLink(link, inner, context);
    }
    return inner;
}

static NSString *OMSlackInlines(cmark_node *parent, OMSlackContext *context, BOOL plain)
{
    NSMutableString *text = [NSMutableString string];
    cmark_node *child = cmark_node_first_child(parent);
    for (; child != NULL; child = cmark_node_next(child)) {
        [text appendString:OMSlackInline(child, context, plain)];
    }
    return text;
}

// Each line of text after the first with prefix before it; the first with
// firstPrefix.
static NSString *OMSlackPrefixedLines(NSString *text, NSString *firstPrefix, NSString *prefix)
{
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableArray *prefixed = [NSMutableArray arrayWithCapacity:[lines count]];
    NSUInteger index = 0;
    for (index = 0; index < [lines count]; index++) {
        NSString *line = [lines objectAtIndex:index];
        NSString *before = (index == 0 ? firstPrefix : prefix);
        if ([line length] == 0) {
            before = [before stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        [prefixed addObject:[before stringByAppendingString:line]];
    }
    return [prefixed componentsJoinedByString:@"\n"];
}

static NSString *OMSlackList(cmark_node *list, OMSlackContext *context)
{
    static NSString * const bullets[] = { @"\u2022", @"\u25E6", @"\u25AA" };
    BOOL ordered = (cmark_node_get_list_type(list) == CMARK_ORDERED_LIST);
    NSString *delimiter = (cmark_node_get_list_delim(list) == CMARK_PAREN_DELIM ? @")" : @".");
    int number = cmark_node_get_list_start(list);
    NSString *bullet = bullets[context->listDepth % 3];
    NSMutableArray *items = [NSMutableArray array];

    context->listDepth++;
    cmark_node *item = cmark_node_first_child(list);
    for (; item != NULL; item = cmark_node_next(item), number++) {
        NSString *marker = ordered ? [NSString stringWithFormat:@"%d%@", number, delimiter] : bullet;
        if (OMGFMNodeIsTaskItem(item)) {
            NSString *box = cmark_gfm_extensions_get_tasklist_item_checked(item) ? @"\u2611" : @"\u2610";
            // A task's box stands for its bullet.
            marker = ordered ? [NSString stringWithFormat:@"%@ %@", marker, box] : box;
        }
        NSString *content = OMSlackBlocks(item, context, @"\n");
        [items addObject:OMSlackPrefixedLines(content,
                                              [marker stringByAppendingString:@" "],
                                              @"    ")];
    }
    context->listDepth--;
    return [items componentsJoinedByString:(cmark_node_get_list_tight(list) ? @"\n" : @"\n\n")];
}

static NSString *OMSlackPadded(NSString *text, NSUInteger width, uint8_t alignment)
{
    NSUInteger length = [text length];
    if (length >= width) {
        return text;
    }
    NSUInteger space = width - length;
    NSUInteger before = 0;
    if (alignment == 'r') {
        before = space;
    } else if (alignment == 'c') {
        before = space / 2;
    }
    NSString *left = [@"" stringByPaddingToLength:before withString:@" " startingAtIndex:0];
    NSString *right = [@"" stringByPaddingToLength:space - before withString:@" " startingAtIndex:0];
    return [NSString stringWithFormat:@"%@%@%@", left, text, right];
}

// A table as aligned columns in a code block: Slack has no tables.
static NSString *OMSlackTable(cmark_node *table, OMSlackContext *context)
{
    NSUInteger columns = cmark_gfm_extensions_get_table_columns(table);
    uint8_t *alignments = cmark_gfm_extensions_get_table_alignments(table);
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *widths = [NSMutableArray array];
    NSUInteger column = 0;
    for (column = 0; column < columns; column++) {
        [widths addObject:[NSNumber numberWithUnsignedInteger:0]];
    }
    BOOL hasHeader = NO;
    cmark_node *row = cmark_node_first_child(table);
    for (; row != NULL; row = cmark_node_next(row)) {
        if (cmark_gfm_extensions_get_table_row_is_header(row)) {
            hasHeader = YES;
        }
        NSMutableArray *cells = [NSMutableArray array];
        cmark_node *cell = cmark_node_first_child(row);
        for (column = 0; cell != NULL && column < columns; cell = cmark_node_next(cell), column++) {
            NSString *text = [OMSlackInlines(cell, context, YES)
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [cells addObject:text];
            if ([text length] > [[widths objectAtIndex:column] unsignedIntegerValue]) {
                [widths replaceObjectAtIndex:column withObject:[NSNumber numberWithUnsignedInteger:[text length]]];
            }
        }
        for (; column < columns; column++) {
            [cells addObject:@""];
        }
        [rows addObject:cells];
    }

    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger index = 0;
    for (index = 0; index < [rows count]; index++) {
        NSArray *cells = [rows objectAtIndex:index];
        NSMutableArray *padded = [NSMutableArray array];
        for (column = 0; column < columns; column++) {
            uint8_t alignment = (alignments != NULL ? alignments[column] : 0);
            [padded addObject:OMSlackPadded([cells objectAtIndex:column],
                                            [[widths objectAtIndex:column] unsignedIntegerValue],
                                            alignment)];
        }
        NSString *line = [[padded componentsJoinedByString:@" | "]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [lines addObject:line];
        if (index == 0 && hasHeader) {
            NSMutableArray *rules = [NSMutableArray array];
            for (column = 0; column < columns; column++) {
                NSUInteger width = MAX((NSUInteger)1, [[widths objectAtIndex:column] unsignedIntegerValue]);
                [rules addObject:[@"" stringByPaddingToLength:width withString:@"-" startingAtIndex:0]];
            }
            [lines addObject:[rules componentsJoinedByString:@"-+-"]];
        }
    }
    return [NSString stringWithFormat:@"```\n%@\n```", [lines componentsJoinedByString:@"\n"]];
}

static NSString *OMSlackBlock(cmark_node *node, OMSlackContext *context)
{
    cmark_node_type type = cmark_node_get_type(node);
    if (type == CMARK_NODE_PARAGRAPH) {
        return OMSlackInlines(node, context, NO);
    }
    if (type == CMARK_NODE_HEADING) {
        return OMSlackWrapped(OMSlackInlines(node, context, YES), @"*");
    }
    if (type == CMARK_NODE_CODE_BLOCK) {
        NSString *code = OMSlackEscaped(OMSlackLiteral(node), context);
        while ([code hasSuffix:@"\n"]) {
            code = [code substringToIndex:[code length] - 1];
        }
        return [NSString stringWithFormat:@"```\n%@\n```", code];
    }
    if (type == CMARK_NODE_THEMATIC_BREAK) {
        return @"\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500";
    }
    if (type == CMARK_NODE_BLOCK_QUOTE) {
        return OMSlackPrefixedLines(OMSlackBlocks(node, context, @"\n\n"), @"> ", @"> ");
    }
    if (type == CMARK_NODE_LIST) {
        return OMSlackList(node, context);
    }
    if (type == CMARK_NODE_TABLE) {
        return OMSlackTable(node, context);
    }
    if (type == CMARK_NODE_FOOTNOTE_DEFINITION) {
        NSString *content = OMSlackBlocks(node, context, @"\n");
        return [NSString stringWithFormat:@"[%@] %@", OMSlackLiteral(node), content];
    }
    // Raw HTML is dropped, as the renderer's safe mode does.
    return @"";
}

static NSString *OMSlackBlocks(cmark_node *parent, OMSlackContext *context, NSString *separator)
{
    NSMutableArray *blocks = [NSMutableArray array];
    cmark_node *child = cmark_node_first_child(parent);
    for (; child != NULL; child = cmark_node_next(child)) {
        NSString *block = OMSlackBlock(child, context);
        if ([block length] > 0) {
            [blocks addObject:block];
        }
    }
    return [blocks componentsJoinedByString:separator];
}

NSString *OMSlackMrkdwnFromMarkdown(NSString *markdown, OMSlackMrkdwnOptions options)
{
    if (markdown == nil) {
        return nil;
    }
    NSData *utf8 = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    cmark_node *document = OMGFMParseDocument((const char *)[utf8 bytes], (size_t)[utf8 length],
                                              CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return nil;
    }
    OMSlackContext context;
    context.options = options;
    context.listDepth = 0;
    NSString *text = OMSlackBlocks(document, &context, @"\n\n");
    cmark_node_free(document);
    return text;
}
