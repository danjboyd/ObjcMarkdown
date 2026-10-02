// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef OMGFMPARSER_H
#define OMGFMPARSER_H

#include <stddef.h>
#include "cmark-gfm.h"

#ifdef __cplusplus
extern "C" {
#endif

// Parses Markdown with the GitHub-flavoured extensions the renderer uses
// (tables, strikethrough, autolinks, task lists) and footnotes. Every caller
// that maps between source and rendered blocks must parse through this, so
// block structure agrees. Free the result with cmark_node_free().
cmark_node *OMGFMParseDocument(const char *bytes, size_t length, int options);

// YES if node is a list item written as a task ("- [ ]" or "- [x]").
int OMGFMNodeIsTaskItem(cmark_node *node);
// YES if node is a GFM table (its node type is assigned at run time).
int OMGFMNodeIsTable(cmark_node *node);

#ifdef __cplusplus
}
#endif

#endif
