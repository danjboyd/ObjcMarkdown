// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// The document as an HTML fragment for the clipboard: GitHub-flavoured
// Markdown rendered by cmark-gfm in its safe mode (raw HTML is dropped),
// with task boxes as the characters a chat or mail keeps (inputs are
// stripped there). Nil for nil.
NSString *OMDClipboardHTMLFromMarkdown(NSString *markdown);

// Copy Rendered (#173): puts the rendered document on the pasteboard as
// HTML (from the Markdown), RTF (from the preview's text, when there is
// one) and plain text, so pasting into Teams, Outlook or an email body
// keeps its headings, lists, tables and code. Returns NO when there is
// nothing to copy.
BOOL OMDWriteRenderedDocumentToPasteboard(NSPasteboard *pasteboard,
                                          NSString *markdown,
                                          NSAttributedString *rendered);
