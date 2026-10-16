// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDRichPasteboard.h"

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
    [self assertHTML:html contains:@"<pre><code>a &lt; b\n</code></pre>"];
}

- (void)testGitHubExtensionsRender
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"| a | b |\n|---|---|\n| 1 | 2 |\n\n~~gone~~\n");
    [self assertHTML:html contains:@"<table>"];
    [self assertHTML:html contains:@"<td>2</td>"];
    [self assertHTML:html contains:@"<del>gone</del>"];
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

@end
