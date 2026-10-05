// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Finds what changed between the preview's text and a new render: the
// ranges left once their common prefix and suffix are removed, comparing
// characters and attributes. Each render allocates new attachments,
// rendered objects and text tables, so those compare by value; after the
// change, objects that only moved in the source count as unchanged.
// Paragraph styles compare by paragraph, as a text storage applies them.
// Anything unsure counts as changed. Returns NO when the two are the same.
BOOL OMDChangedRangesForRender(NSAttributedString *current,
                               NSAttributedString *rendered,
                               NSRange *currentRangeOut,
                               NSRange *renderedRangeOut);

// Brings storage up to date with rendered by replacing only the changed
// range, so the layout manager lays out as little as it can. The storage
// ends up holding rendered with its attributes fixed (as any text storage
// fixes them). Returns the range now holding the new text, or
// {NSNotFound, 0} if nothing changed.
NSRange OMDApplyRenderedString(NSTextStorage *storage, NSAttributedString *rendered);
