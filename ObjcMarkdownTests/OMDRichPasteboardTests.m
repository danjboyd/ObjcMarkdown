// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDRichPasteboard.h"
#import "OMDWindowsClipboard.h"

@interface OMDRichPasteboardTests : XCTestCase
@end

@implementation OMDRichPasteboardTests

- (void)assertHTML:(NSString *)html contains:(NSString *)part
{
    XCTAssertTrue([html rangeOfString:part].location != NSNotFound, @"%@ lacks %@", html, part);
}

- (void)testHeadingsListsAndCodeBecomeHTML
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"# Plan\n\n- one\n- **two**\n\n```\na < b\n```\n");
    XCTAssertTrue([html hasPrefix:@"<meta charset=\"utf-8\">"]);
    [self assertHTML:html contains:@"<h1>Plan</h1>"];
    [self assertHTML:html contains:@"<li><strong>two</strong></li>"];
    [self assertHTML:html contains:@"<pre style=\"background:#f6f8fa;color:#1f2328;padding:8px 12px;border-radius:6px\"><code>a &lt; b\n</code></pre>"];
}

- (void)testGitHubExtensionsRender
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"| a | b |\n|---|---|\n| 1 | 2 |\n\n~~gone~~\n");
    [self assertHTML:html contains:@"<table style=\"border-collapse:collapse\">"];
    [self assertHTML:html contains:@"<td style=\"border:1px solid #d0d7de;padding:4px 8px\">2</td>"];
    XCTAssertTrue([html rangeOfString:@"<thead style"].location == NSNotFound);
    [self assertHTML:html contains:@"<del>gone</del>"];
}

- (void)testInlineCodeAndQuotesAreStyledInline
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"> said `x`\n\n| a |\n|:-:|\n| 1 |\n");
    [self assertHTML:html contains:@"<blockquote style=\"margin:0;padding:0 12px;border-left:3px solid #d0d7de;color:#59636e\">"];
    [self assertHTML:html contains:@"<code style=\"background:#eff1f3;color:#1f2328;padding:1px 4px;border-radius:4px\">x</code>"];
    [self assertHTML:html contains:@"<th style=\"border:1px solid #d0d7de;padding:4px 8px\" align=\"center\">a</th>"];
}

- (void)testTaskBoxesBecomeBallotBoxes
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"- [x] done\n- [ ] todo\n");
    [self assertHTML:html contains:@"&#9745; done"];
    [self assertHTML:html contains:@"&#9744; todo"];
    XCTAssertTrue([html rangeOfString:@"<input"].location == NSNotFound);
}

- (void)testRawHTMLIsDropped
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"<script>alert(1)</script>\n\nText <b onclick=\"x()\">b</b>\n");
    XCTAssertTrue([html rangeOfString:@"<script"].location == NSNotFound);
    XCTAssertTrue([html rangeOfString:@"onclick"].location == NSNotFound);
    [self assertHTML:html contains:@"Text"];
}

- (void)testNilMarkdownGivesNil
{
    XCTAssertNil(OMDClipboardHTMLFromMarkdown(nil));
}

- (void)testPasteboardGetsHTMLRTFAndText
{
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    NSAttributedString *rendered = [[[NSAttributedString alloc] initWithString:@"Plan\uFFFC\none"] autorelease];
    XCTAssertTrue(OMDWriteRenderedDocumentToPasteboard(pasteboard, @"# Plan\n\n- one\n", rendered));
    NSArray *types = [pasteboard types];
    XCTAssertTrue([types containsObject:NSHTMLPboardType]);
    XCTAssertTrue([types containsObject:NSRTFPboardType]);
    XCTAssertTrue([types containsObject:NSStringPboardType]);
    XCTAssertEqualObjects([pasteboard stringForType:NSStringPboardType], @"Plan\none");
    NSData *htmlData = [pasteboard dataForType:NSHTMLPboardType];
    NSString *html = [[[NSString alloc] initWithData:htmlData encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertTrue([html hasPrefix:@"<meta charset=\"utf-8\"><h1>Plan</h1>"], @"%@", html);
    [pasteboard releaseGlobally];
}

- (void)testPasteboardWithoutAPreviewCopiesTheMarkdownAsText
{
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    XCTAssertTrue(OMDWriteRenderedDocumentToPasteboard(pasteboard, @"# Plan\n", nil));
    XCTAssertFalse([[pasteboard types] containsObject:NSRTFPboardType]);
    XCTAssertEqualObjects([pasteboard stringForType:NSStringPboardType], @"# Plan\n");
    [pasteboard releaseGlobally];
}

// Windows' "HTML Format" (#179): the header's offsets count UTF-8 bytes and
// point at the document and at the fragment between its comments.
- (void)testWindowsHTMLFormatOffsetsPointAtTheFragment
{
    NSString *fragment = @"<p>caf\u00E9 \u2014 na\u00EFve</p>";
    NSData *data = OMDWindowsClipboardHTMLData(fragment);
    const char *bytes = (const char *)[data bytes];
    XCTAssertEqual(bytes[[data length] - 1], (char)0);
    NSString *text = [[[NSString alloc] initWithBytes:bytes length:[data length] - 1 encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertTrue([text hasPrefix:@"Version:0.9\r\nStartHTML:"]);

    NSInteger (^offset)(NSString *) = ^NSInteger(NSString *key) {
        NSRange range = [text rangeOfString:[key stringByAppendingString:@":"]];
        return [[text substringWithRange:NSMakeRange(NSMaxRange(range), 10)] integerValue];
    };
    NSInteger startHTML = offset(@"StartHTML");
    NSInteger endHTML = offset(@"EndHTML");
    NSInteger startFragment = offset(@"StartFragment");
    NSInteger endFragment = offset(@"EndFragment");
    XCTAssertEqual(endHTML, (NSInteger)[data length] - 1);
    NSString *document = [[[NSString alloc] initWithBytes:bytes + startHTML length:endHTML - startHTML encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertTrue([document hasPrefix:@"<html><body>"]);
    NSString *copied = [[[NSString alloc] initWithBytes:bytes + startFragment length:endFragment - startFragment encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertEqualObjects(copied, fragment);
}

@end
