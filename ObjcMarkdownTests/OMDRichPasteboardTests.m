// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDRichPasteboard.h"
#import "OMDWindowsClipboard.h"
#import "OMMarkdownRenderer.h"

// A PNG header only: 300 x 60 pixels, enough for the size the page reads.
static NSData *OMDTestMathPNG(NSString *formula, BOOL display)
{
    static const unsigned char header[24] = {
        0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a,
        0, 0, 0, 13, 'I', 'H', 'D', 'R',
        0, 0, 0x01, 0x2c, 0, 0, 0, 0x3c
    };
    (void)formula;
    (void)display;
    return [NSData dataWithBytes:header length:sizeof(header)];
}

static NSData *OMDTestNoMathPNG(NSString *formula, BOOL display)
{
    (void)formula;
    (void)display;
    return nil;
}

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

- (void)testMathBecomesReadableTextNotTeX
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"Area $x^2$ here.\n\n$$\\int_0^1 f(x)\\,dx$$\n");
    XCTAssertTrue([html rangeOfString:@"$"].location == NSNotFound, @"%@", html);
    XCTAssertTrue([html rangeOfString:@"\\int"].location == NSNotFound, @"%@", html);
    XCTAssertTrue([html rangeOfString:@"\\"].location == NSNotFound, @"%@", html);
    [self assertHTML:html contains:@"\u222B"];
    [self assertHTML:html contains:@"Area x"];
}

- (void)testMathInCodeIsKeptAsWritten
{
    NSString *html = OMDClipboardHTMLFromMarkdown(@"Type `$x^2$` for a square.\n");
    [self assertHTML:html contains:@">$x^2$</code>"];
}

- (void)testMathPlaceholdersSkipCodeAndKeepTheFormulas
{
    NSMutableArray *formulas = [NSMutableArray array];
    NSString *source = OMMarkdownWithMathPlaceholders(@"A $x^2$ and `$y$`.\n\n$$\\int_0^1 f$$\n", nil, formulas);
    XCTAssertEqualObjects(source, @"A OMMATH0Q0Z and `$y$`.\n\nOMMATH0Q1Z\n");
    XCTAssertEqual([formulas count], (NSUInteger)2);
    XCTAssertEqualObjects([[formulas objectAtIndex:0] objectAtIndex:0], @"x^2");
    XCTAssertFalse([[[formulas objectAtIndex:0] objectAtIndex:1] boolValue]);
    XCTAssertEqualObjects([[formulas objectAtIndex:0] objectAtIndex:2], @"OMMATH0Q0Z");
    XCTAssertEqualObjects([[formulas objectAtIndex:1] objectAtIndex:0], @"\\int_0^1 f");
    XCTAssertTrue([[[formulas objectAtIndex:1] objectAtIndex:1] boolValue]);
}

- (void)testMathPlaceholdersAvoidTheDocumentsOwnText
{
    NSMutableArray *formulas = [NSMutableArray array];
    NSString *source = OMMarkdownWithMathPlaceholders(@"OMMATH0Q0Z $x$\n", @"OMMATH1Q", formulas);
    XCTAssertEqualObjects(source, @"OMMATH0Q0Z OMMATH2Q0Z\n");
}

// A document that spells a token itself, in prose, in code and through an
// entity, keeps those words: only the formula is replaced (#364 review).
- (void)testPrintHTMLLeavesLiteralTokenTextAlone
{
    NSString *markdown = @"Text OMMATH0Q0Z and `OMMATH0Q0Z` and &#79;MMATH1Q0Z beside $x^2$.\n\n"
                         @"```\nOMMATH0Q0Z\n```\n\nThe old fixed token: OMMATHPH0Z.\n";
    NSString *html = OMDPrintHTMLFromMarkdown(markdown, OMDTestMathPNG);
    [self assertHTML:html contains:@"The old fixed token: OMMATHPH0Z."];
    [self assertHTML:html contains:@"Text OMMATH0Q0Z and "];
    [self assertHTML:html contains:@">OMMATH0Q0Z</code>"];
    [self assertHTML:html contains:@"and OMMATH1Q0Z beside <img class=\"math\""];
    [self assertHTML:html contains:@"OMMATH0Q0Z\n</code></pre>"];
    NSUInteger images = [[html componentsSeparatedByString:@"<img class=\"math\""] count] - 1;
    XCTAssertEqual(images, (NSUInteger)1, @"%@", html);
}

- (void)testPrintHTMLPutsTypesetMathInPlace
{
    NSString *html = OMDPrintHTMLFromMarkdown(@"Area $x^2$ here, `$y$`.\n\n$$\\int_0^1 f(x)\\,dx$$\n", OMDTestMathPNG);
    XCTAssertTrue([html rangeOfString:@"OMMATH"].location == NSNotFound, @"%@", html);
    // 300 x 60 pixels at 300 dpi for 10 pt TeX, shown for 12 pt text.
    [self assertHTML:html contains:@"Area <img class=\"math\" alt=\"x"];
    [self assertHTML:html contains:@"style=\"width:115.2px;height:23.0px;vertical-align:middle\">"];
    [self assertHTML:html contains:@"src=\"data:image/png;base64,iVBORw0KGgo"];
    [self assertHTML:html contains:@"<span style=\"display:block;text-align:center;margin:0.4em 0\"><img class=\"math\""];
    [self assertHTML:html contains:@">$y$</code>"];
}

- (void)testPrintHTMLFallsBackToReadableMath
{
    NSString *markdown = @"Area $x^2$ here.\n\n$$\\int_0^1 f(x)\\,dx$$\n";
    NSString *withoutTeX = OMDPrintHTMLFromMarkdown(markdown, OMDTestNoMathPNG);
    NSString *noProvider = OMDPrintHTMLFromMarkdown(markdown, NULL);
    XCTAssertEqualObjects(withoutTeX, noProvider);
    XCTAssertTrue([noProvider rangeOfString:@"OMMATH"].location == NSNotFound, @"%@", noProvider);
    XCTAssertTrue([noProvider rangeOfString:@"$"].location == NSNotFound, @"%@", noProvider);
    XCTAssertTrue([noProvider rangeOfString:@"<img"].location == NSNotFound, @"%@", noProvider);
    [self assertHTML:noProvider contains:@"\u222B"];
    [self assertHTML:noProvider contains:@"Area x"];
}

- (void)testRTFHasNoAttachmentPlaceholders
{
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    NSMutableAttributedString *rendered = [[[NSMutableAttributedString alloc] initWithString:@"Plan"] autorelease];
    [rendered appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    [rendered appendAttributedString:[[[NSAttributedString alloc] initWithString:@" done"] autorelease]];
    XCTAssertTrue(OMDWriteRenderedDocumentToPasteboard(pasteboard, @"# Plan\n\n---\n\ndone\n", rendered));
    NSString *rtf = [[[NSString alloc] initWithData:[pasteboard dataForType:NSRTFPboardType]
                                           encoding:NSASCIIStringEncoding] autorelease];
    XCTAssertTrue([rtf rangeOfString:@"unnamed_file"].location == NSNotFound, @"%@", rtf);
    XCTAssertTrue([rtf rangeOfString:@"Plan done"].location != NSNotFound, @"%@", rtf);
    [pasteboard releaseGlobally];
}

@end
