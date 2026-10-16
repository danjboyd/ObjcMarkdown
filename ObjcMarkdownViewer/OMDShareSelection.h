// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// The Markdown of the blocks a preview selection touches (#192): the
// source lines of the innermost rendered blocks (the renderer's block
// anchors) that range overlaps, with their common indent removed, so a
// nested list item or a quoted paragraph still reads as Markdown. The
// selection grows to whole blocks: a preview position has no exact source
// position inside a paragraph. Nil when no block is touched.
NSString *OMDShareMarkdownForPreviewRange(NSString *markdown, NSRange range, NSArray *blockAnchors);

// Lines with the indent they all share removed (blank lines don't count).
NSString *OMDShareDedentedLines(NSArray *lines);
