// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>

#import "OMSlackMrkdwn.h"

@interface OMSlackMrkdwnTests : XCTestCase
@end

@implementation OMSlackMrkdwnTests

- (NSString *)slack:(NSString *)markdown
{
    return OMSlackMrkdwnFromMarkdown(markdown, OMSlackMrkdwnOptionsNone);
}

- (NSString *)slackAPI:(NSString *)markdown
{
    return OMSlackMrkdwnFromMarkdown(markdown, OMSlackMrkdwnOptionsAPI);
}

- (void)testNilAndEmpty
{
    XCTAssertNil(OMSlackMrkdwnFromMarkdown(nil, OMSlackMrkdwnOptionsNone));
    XCTAssertEqualObjects([self slack:@""], @"");
}

- (void)testInlineFormatting
{
    XCTAssertEqualObjects([self slack:@"**bold**, *italic*, _also_, ~~gone~~ and `code`"],
                          @"*bold*, _italic_, _also_, ~gone~ and `code`");
    XCTAssertEqualObjects([self slack:@"***both***"], @"_*both*_");
}

- (void)testSoftBreaksJoinAndHardBreaksStay
{
    XCTAssertEqualObjects([self slack:@"one\ntwo"], @"one two");
    XCTAssertEqualObjects([self slack:@"one  \ntwo"], @"one\ntwo");
}

- (void)testParagraphsAreSeparatedByABlankLine
{
    XCTAssertEqualObjects([self slack:@"one\n\ntwo"], @"one\n\ntwo");
}

- (void)testHeadingsAreBoldLinesWithoutInnerMarkers
{
    XCTAssertEqualObjects([self slack:@"# Q3 **Plan**\n\nText"], @"*Q3 Plan*\n\nText");
}

- (void)testLinksForPasting
{
    XCTAssertEqualObjects([self slack:@"[the site](https://example.com)"], @"the site (https://example.com)");
    XCTAssertEqualObjects([self slack:@"<https://example.com>"], @"https://example.com");
    XCTAssertEqualObjects([self slack:@"www.example.com"], @"www.example.com (http://www.example.com)");
}

- (void)testLinksAndEscapingForTheAPI
{
    XCTAssertEqualObjects([self slackAPI:@"[the site](https://example.com/?a=1&b=2)"],
                          @"<https://example.com/?a=1&amp;b=2|the site>");
    XCTAssertEqualObjects([self slackAPI:@"<https://example.com>"], @"<https://example.com>");
    XCTAssertEqualObjects([self slackAPI:@"a < b & c"], @"a &lt; b &amp; c");
    XCTAssertEqualObjects([self slack:@"a < b & c"], @"a < b & c");
}

- (void)testImagesBecomeLinks
{
    XCTAssertEqualObjects([self slack:@"![Chart](https://example.com/c.png)"], @"Chart (https://example.com/c.png)");
}

- (void)testBulletListsNestWithIndentAndBullets
{
    NSString *markdown = @"- one\n- two\n  - inner\n    - deepest\n- three";
    XCTAssertEqualObjects([self slack:markdown],
                          @"\u2022 one\n\u2022 two\n    \u25E6 inner\n        \u25AA deepest\n\u2022 three");
}

- (void)testOrderedListsKeepTheirNumbers
{
    XCTAssertEqualObjects([self slack:@"3. three\n4. four"], @"3. three\n4. four");
    XCTAssertEqualObjects([self slack:@"1) one\n2) two"], @"1) one\n2) two");
}

- (void)testLooseListsKeepBlankLines
{
    XCTAssertEqualObjects([self slack:@"- one\n\n- two"], @"\u2022 one\n\n\u2022 two");
}

- (void)testTaskItemsGetBallotBoxes
{
    XCTAssertEqualObjects([self slack:@"- [x] done\n- [ ] open"], @"\u2611 done\n\u2610 open");
    XCTAssertEqualObjects([self slack:@"1. [x] done"], @"1. \u2611 done");
}

- (void)testCodeBlocksDropTheLanguage
{
    XCTAssertEqualObjects([self slack:@"```objc\nNSLog(@\"*hi*\");\n```"],
                          @"```\nNSLog(@\"*hi*\");\n```");
}

- (void)testQuotesPrefixEveryLine
{
    XCTAssertEqualObjects([self slack:@"> one\n>\n> **two**"], @"> one\n>\n> *two*");
}

- (void)testTablesBecomeAlignedTextInACodeBlock
{
    NSString *markdown = @"| Name | N |\n|:-----|--:|\n| *macOS* | 1 |\n| Linux | 22 |";
    XCTAssertEqualObjects([self slack:markdown],
                          @"```\nName  |  N\n------+---\nmacOS |  1\nLinux | 22\n```");
}

- (void)testFootnotesAreNumberedNotes
{
    XCTAssertEqualObjects([self slack:@"Text.[^1]\n\n[^1]: The **note**."],
                          @"Text.[1]\n\n[1] The *note*.");
}

- (void)testThematicBreakAndRawHTML
{
    XCTAssertEqualObjects([self slack:@"a\n\n---\n\n<div>x</div>\n\nb <b>c</b>"],
                          @"a\n\n\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\nb c");
}

@end
