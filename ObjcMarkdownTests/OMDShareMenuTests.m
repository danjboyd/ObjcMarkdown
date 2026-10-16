// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDShareMenu.h"

@interface OMDShareMenuTests : XCTestCase
@end

@implementation OMDShareMenuTests

- (NSMenu *)shareMenu
{
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Share"] autorelease];
    OMDAddShareMenuItems(menu, nil);
    return menu;
}

- (void)testShareAsListsTheFourFormatsByTag
{
    NSMenu *menu = [self shareMenu];
    NSArray *titles = [NSArray arrayWithObjects:@"Share as PDF...", @"Share as Word Document...",
                                                @"Share as Markdown File...", @"Share as HTML...", nil];
    NSUInteger index = 0;
    for (index = 0; index < [titles count]; index++) {
        NSMenuItem *item = (NSMenuItem *)[menu itemAtIndex:index];
        XCTAssertEqualObjects([item title], [titles objectAtIndex:index]);
        XCTAssertEqual([item tag], (NSInteger)index);
        XCTAssertEqual([item action], @selector(shareDocument:));
    }
}

- (void)testEmailAsHasThreeFilesAndInTheMessage
{
    NSMenu *menu = [self shareMenu];
    NSMenuItem *emailItem = (NSMenuItem *)[menu itemWithTitle:@"Email as"];
    XCTAssertNotNil(emailItem);
    NSMenu *email = [emailItem submenu];
    XCTAssertEqual([email numberOfItems], (NSInteger)5);
    XCTAssertEqualObjects([[email itemAtIndex:0] title], @"PDF");
    XCTAssertEqualObjects([[email itemAtIndex:1] title], @"Word Document");
    XCTAssertEqualObjects([[email itemAtIndex:2] title], @"Markdown File");
    XCTAssertTrue([[email itemAtIndex:3] isSeparatorItem]);
    XCTAssertEqualObjects([[email itemAtIndex:4] title], @"In the Message");
    XCTAssertEqual([[email itemAtIndex:0] tag], (NSInteger)OMDShareFormatPDF);
    XCTAssertEqual([[email itemAtIndex:1] tag], (NSInteger)OMDShareFormatWord);
    XCTAssertEqual([[email itemAtIndex:2] tag], (NSInteger)OMDShareFormatMarkdown);
    XCTAssertEqual([[email itemAtIndex:4] tag], (NSInteger)OMDShareEmailInMessageTag);
    XCTAssertEqual([[email itemAtIndex:4] action], @selector(emailDocument:));
    // An HTML file isn't offered as an attachment: HTML goes in the message.
    XCTAssertNil([email itemWithTitle:@"HTML"]);
}

- (void)testCopyForSlackFollowsCopyRendered
{
    NSMenu *menu = [self shareMenu];
    NSInteger rendered = [menu indexOfItemWithTitle:@"Copy Rendered"];
    XCTAssertTrue(rendered >= 0);
    NSMenuItem *slack = (NSMenuItem *)[menu itemAtIndex:rendered + 1];
    XCTAssertEqualObjects([slack title], @"Copy for Slack");
    XCTAssertEqual([slack action], @selector(copyDocumentForSlack:));
}

- (void)testTheMessageTagIsNoFormat
{
    XCTAssertTrue(OMDShareEmailInMessageTag > OMDShareFormatHTML);
}

@end
