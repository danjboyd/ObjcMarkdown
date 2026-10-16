// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRichPasteboard.h"
#import "OMGFMParser.h"

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
        rtf = [rendered RTFFromRange:NSMakeRange(0, [rendered length]) documentAttributes:nil];
    }
    NSString *plain = markdown;
    if (rendered != nil && [rendered length] > 0) {
        // Without the attachment characters (rules, images, math).
        plain = [[rendered string] stringByReplacingOccurrencesOfString:@"\uFFFC" withString:@""];
    }

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
