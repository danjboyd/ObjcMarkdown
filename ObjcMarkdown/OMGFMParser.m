// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <string.h>
#include "OMGFMParser.h"
#include "cmark-gfm-core-extensions.h"
#include "table.h"

static void OMGFMRegisterExtensions(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cmark_gfm_core_extensions_ensure_registered();
    });
}

cmark_node *OMGFMParseDocument(const char *bytes, size_t length, int options)
{
    OMGFMRegisterExtensions();
    cmark_parser *parser = cmark_parser_new(options | CMARK_OPT_FOOTNOTES);
    if (parser == NULL) {
        return NULL;
    }
    static const char *extensionNames[] = { "table", "strikethrough", "autolink", "tasklist" };
    size_t index = 0;
    for (; index < sizeof(extensionNames) / sizeof(extensionNames[0]); index++) {
        cmark_syntax_extension *extension = cmark_find_syntax_extension(extensionNames[index]);
        if (extension != NULL) {
            cmark_parser_attach_syntax_extension(parser, extension);
        }
    }
    cmark_parser_feed(parser, bytes != NULL ? bytes : "", bytes != NULL ? length : 0);
    cmark_node *document = cmark_parser_finish(parser);
    cmark_parser_free(parser);
    return document;
}

int OMGFMNodeIsTaskItem(cmark_node *node)
{
    if (node == NULL || cmark_node_get_type(node) != CMARK_NODE_ITEM) {
        return 0;
    }
    const char *typeString = cmark_node_get_type_string(node);
    return typeString != NULL && strcmp(typeString, "tasklist") == 0;
}

int OMGFMNodeIsTable(cmark_node *node)
{
    return node != NULL && cmark_node_get_type(node) == CMARK_NODE_TABLE;
}
