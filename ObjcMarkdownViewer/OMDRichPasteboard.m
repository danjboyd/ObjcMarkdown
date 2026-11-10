// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRichPasteboard.h"
#import "OMGFMParser.h"
#import "OMDWindowsClipboard.h"
#import "OMMarkdownRenderer.h"

#include <stdlib.h>
#include <string.h>

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

// cmark-gfm's HTML for already-prepared Markdown, with task boxes as
// characters and the inline styles. Nil if cmark fails.
static NSMutableString *OMDHTMLFragmentFromSource(NSString *source)
{
    NSData *utf8 = [source dataUsingEncoding:NSUTF8StringEncoding];
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
    return fragment;
}

NSString *OMDClipboardHTMLFromMarkdown(NSString *markdown)
{
    if (markdown == nil) {
        return nil;
    }
    // Mail and chats show TeX as it is, and cmark would drop its backslashes
    // before punctuation ("\," became ","): formulas as readable text.
    NSMutableString *fragment = OMDHTMLFragmentFromSource(OMMarkdownWithReadableMath(markdown));
    if (fragment == nil) {
        return nil;
    }
    return [NSString stringWithFormat:@"<meta charset=\"utf-8\">%@", fragment];
}

static NSString *OMDHTMLEscapedText(NSString *text)
{
    NSMutableString *escaped = [NSMutableString stringWithString:(text != nil ? text : @"")];
    OMDReplaceAll(escaped, @"&", @"&amp;");
    OMDReplaceAll(escaped, @"<", @"&lt;");
    OMDReplaceAll(escaped, @">", @"&gt;");
    OMDReplaceAll(escaped, @"\"", @"&quot;");
    return escaped;
}

// A PNG's size in pixels, from its IHDR chunk. NO if it isn't a PNG.
static BOOL OMDPNGPixelSize(NSData *png, NSUInteger *width, NSUInteger *height)
{
    static const unsigned char signature[8] = { 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
    if ([png length] < 24) {
        return NO;
    }
    const unsigned char *bytes = (const unsigned char *)[png bytes];
    if (memcmp(bytes, signature, 8) != 0 || memcmp(bytes + 12, "IHDR", 4) != 0) {
        return NO;
    }
    *width = ((NSUInteger)bytes[16] << 24) | ((NSUInteger)bytes[17] << 16) |
             ((NSUInteger)bytes[18] << 8) | (NSUInteger)bytes[19];
    *height = ((NSUInteger)bytes[20] << 24) | ((NSUInteger)bytes[21] << 16) |
              ((NSUInteger)bytes[22] << 8) | (NSUInteger)bytes[23];
    return (*width > 0 && *height > 0);
}

NSString *OMDPrintHTMLFromMarkdown(NSString *markdown, OMDMathImageProvider provider)
{
    if (markdown == nil) {
        return nil;
    }
    NSMutableArray *formulas = [NSMutableArray array];
    // The tokens avoid the document's own text and the HTML it renders to
    // (where an entity can spell a token), so only formulas are replaced.
    NSString *plain = OMDHTMLFragmentFromSource(markdown);
    NSString *source = OMMarkdownWithMathPlaceholders(markdown, plain, formulas);
    NSMutableString *fragment = OMDHTMLFragmentFromSource(source);
    if (fragment == nil) {
        return nil;
    }
    NSUInteger i = [formulas count];
    while (i > 0) {
        i -= 1;
        NSArray *entry = [formulas objectAtIndex:i];
        NSString *formula = [entry objectAtIndex:0];
        BOOL display = [[entry objectAtIndex:1] boolValue];
        NSString *readable = OMDHTMLEscapedText([OMMarkdownWithReadableMath(
            [NSString stringWithFormat:(display ? @"$$%@$$" : @"$%@$"), formula])
            stringByReplacingOccurrencesOfString:@"\\" withString:@""]);
        NSString *replacement = readable;
        NSData *png = provider != NULL ? provider(formula, display) : nil;
        NSUInteger width = 0;
        NSUInteger height = 0;
        if (png != nil && OMDPNGPixelSize(png, &width, &height)) {
            // Rendered at OMDPrintMathDPI for 10 pt TeX; the page's text is
            // 12 pt, so 1.2 times the image's size at that resolution.
            CGFloat scale = 96.0 * 1.2 / (CGFloat)OMDPrintMathDPI;
            NSString *img = [NSString stringWithFormat:
                @"<img class=\"math\" alt=\"%@\" src=\"data:image/png;base64,%@\" "
                @"style=\"width:%.1fpx;height:%.1fpx;vertical-align:middle\">",
                readable,
                [png base64EncodedStringWithOptions:0],
                width * scale, height * scale];
            replacement = display
                ? [NSString stringWithFormat:@"<span style=\"display:block;text-align:center;margin:0.4em 0\">%@</span>", img]
                : img;
        }
        OMDReplaceAll(fragment, [entry objectAtIndex:2], replacement);
    }
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
        // Without the attachments (rules, images, math): RTF can't carry
        // them, and GNUstep writes each as "__unnamed_file__" text.
        NSMutableAttributedString *text = [[rendered mutableCopy] autorelease];
        NSUInteger index = [text length];
        while (index > 0) {
            index -= 1;
            if ([[text string] characterAtIndex:index] == NSAttachmentCharacter) {
                [text deleteCharactersInRange:NSMakeRange(index, 1)];
            }
        }
        rtf = [text RTFFromRange:NSMakeRange(0, [text length])
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
