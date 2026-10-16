// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRichPasteboard.h"
#import "OMGFMParser.h"
#import "OMDWindowsClipboard.h"

#include <stdlib.h>

#if defined(GNUSTEP)
#define OMDPasteboardTypeHTML NSHTMLPboardType
#define OMDPasteboardTypeRTF NSRTFPboardType
#define OMDPasteboardTypeString NSStringPboardType
#else
#define OMDPasteboardTypeHTML NSPasteboardTypeHTML
#define OMDPasteboardTypeRTF NSPasteboardTypeRTF
#define OMDPasteboardTypeString NSPasteboardTypeString
#endif

static void OMDReplaceAll(NSMutableString *string, NSString *target, NSString *replacement)
{
    [string replaceOccurrencesOfString:target
                            withString:replacement
                               options:0
                                 range:NSMakeRange(0, [string length])];
}

// Mail clients ignore <style> blocks, so tables, code and quotes carry
// their look inline (GitHub's light colours); chats restyle what they keep.
// Anything with a background sets its text colour too, or a dark-mode
// reader draws light text on it.
static void OMDAddInlineStyles(NSMutableString *html)
{
    NSString *cell = @"border:1px solid #d0d7de;padding:4px 8px";
    // Cells with an align attribute first, so plain ones aren't styled twice.
    OMDReplaceAll(html, @"<table>", @"<table style=\"border-collapse:collapse\">");
    OMDReplaceAll(html, @"<th ", [NSString stringWithFormat:@"<th style=\"%@\" ", cell]);
    OMDReplaceAll(html, @"<th>", [NSString stringWithFormat:@"<th style=\"%@\">", cell]);
    OMDReplaceAll(html, @"<td ", [NSString stringWithFormat:@"<td style=\"%@\" ", cell]);
    OMDReplaceAll(html, @"<td>", [NSString stringWithFormat:@"<td style=\"%@\">", cell]);
    // Inline code first, then code blocks (whose <code> follows <pre>).
    OMDReplaceAll(html, @"<code>", @"<code style=\"background:#eff1f3;color:#1f2328;padding:1px 4px;border-radius:4px\">");
    OMDReplaceAll(html, @"<pre><code style=\"background:#eff1f3;color:#1f2328;padding:1px 4px;border-radius:4px\">", @"<pre><code>");
    OMDReplaceAll(html, @"<pre>", @"<pre style=\"background:#f6f8fa;color:#1f2328;padding:8px 12px;border-radius:6px\">");
    OMDReplaceAll(html, @"<blockquote>", @"<blockquote style=\"margin:0;padding:0 12px;border-left:3px solid #d0d7de;color:#59636e\">");
}

NSString *OMDClipboardHTMLFromMarkdown(NSString *markdown)
{
    if (markdown == nil) {
        return nil;
    }
    NSData *utf8 = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    cmark_node *document = OMGFMParseDocument((const char *)[utf8 bytes],
                                              (size_t)[utf8 length],
                                              CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return nil;
    }
    char *html = cmark_render_html(document, CMARK_OPT_DEFAULT, NULL);
    cmark_node_free(document);
    if (html == NULL) {
        return nil;
    }
    NSMutableString *fragment = [NSMutableString stringWithUTF8String:html];
    free(html);
    // Chats and mail drop <input>; ballot boxes survive.
    [fragment replaceOccurrencesOfString:@"<input type=\"checkbox\" checked=\"\" disabled=\"\" /> "
                              withString:@"&#9745; "
                                 options:0
                                   range:NSMakeRange(0, [fragment length])];
    [fragment replaceOccurrencesOfString:@"<input type=\"checkbox\" disabled=\"\" /> "
                              withString:@"&#9744; "
                                 options:0
                                   range:NSMakeRange(0, [fragment length])];
    OMDAddInlineStyles(fragment);
    return [NSString stringWithFormat:@"<meta charset=\"utf-8\">%@", fragment];
}

BOOL OMDWriteRenderedDocumentToPasteboard(NSPasteboard *pasteboard,
                                          NSString *markdown,
                                          NSAttributedString *rendered)
{
    NSString *html = OMDClipboardHTMLFromMarkdown(markdown);
    if (html == nil) {
        return NO;
    }
    NSData *rtf = nil;
    if (rendered != nil && [rendered length] > 0) {
        rtf = [rendered RTFFromRange:NSMakeRange(0, [rendered length])
                 documentAttributes:[NSDictionary dictionary]];
    }
    NSString *plain = markdown;
    if (rendered != nil && [rendered length] > 0) {
        // Without the attachment characters (rules, images, math).
        plain = [[rendered string] stringByReplacingOccurrencesOfString:@"\uFFFC" withString:@""];
    }

#if defined(_WIN32)
    // GNUstep's win32 pasteboard server hands Windows only the text, so the
    // general pasteboard is written as the Windows clipboard itself (#179).
    // Writing both would race: the server empties the clipboard as it takes
    // it over. It still offers the text to GNUstep apps from there.
    if (pasteboard == [NSPasteboard generalPasteboard]) {
        NSString *fragment = html;
        if ([fragment hasPrefix:@"<meta charset=\"utf-8\">"]) {
            fragment = [fragment substringFromIndex:[@"<meta charset=\"utf-8\">" length]];
        }
        if (OMDWindowsClipboardWriteRichText(plain, fragment, rtf)) {
            return YES;
        }
    }
#endif

    NSMutableArray *types = [NSMutableArray arrayWithObject:OMDPasteboardTypeHTML];
    if (rtf != nil) {
        [types addObject:OMDPasteboardTypeRTF];
    }
    [types addObject:OMDPasteboardTypeString];
    [pasteboard declareTypes:types owner:nil];
    // As UTF-8 bytes: GNUstep keeps a string set for another type than
    // NSStringPboardType serialized, and its X11 server hands that over as
    // it is, header and all.
    [pasteboard setData:[html dataUsingEncoding:NSUTF8StringEncoding] forType:OMDPasteboardTypeHTML];
    if (rtf != nil) {
        [pasteboard setData:rtf forType:OMDPasteboardTypeRTF];
    }
    [pasteboard setString:plain forType:OMDPasteboardTypeString];
    return YES;
}
