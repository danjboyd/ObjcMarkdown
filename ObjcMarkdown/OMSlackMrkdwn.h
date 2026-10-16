// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import "OMExport.h"

typedef NS_OPTIONS(NSUInteger, OMSlackMrkdwnOptions) {
    // For pasting into Slack's message box: links as "text (url)", nothing
    // escaped.
    OMSlackMrkdwnOptionsNone = 0,
    // For Slack's API (a message's mrkdwn text): links as <url|text>, and
    // &, < and > escaped as Slack asks.
    OMSlackMrkdwnOptionsAPI = 1 << 0
};

// The Markdown as Slack mrkdwn, parsed the way the renderer parses it
// (GitHub-flavoured): *bold*, _italics_, ~strike~, `code`, code blocks,
// links, > quotes. Slack has no headings, nested lists, tables or task
// lists, so headings become bold lines, lists get bullet characters and
// indents, task items get ballot boxes and tables become aligned text in a
// code block. Raw HTML is dropped. Nil for nil.
OM_EXPORT NSString *OMSlackMrkdwnFromMarkdown(NSString *markdown, OMSlackMrkdwnOptions options);
