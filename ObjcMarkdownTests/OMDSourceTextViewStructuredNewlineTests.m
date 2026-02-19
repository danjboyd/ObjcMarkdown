// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDSourceTextView.h"

@interface OMDSourceTextViewStructuredNewlineTests : XCTestCase
@end

@implementation OMDSourceTextViewStructuredNewlineTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (OMDSourceTextView *)newSourceView
{
    OMDSourceTextView *view = [[OMDSourceTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    [view setEditable:YES];
    [view setSelectable:YES];
    [view setRichText:NO];
    return view;
}

- (void)testEnterContinuesTaskListItemWithUncheckedContinuation
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"  - [x] done"];
    [view setSelectedRange:NSMakeRange([[view string] length], 0)];

    [view insertNewline:nil];

    XCTAssertEqualObjects([view string], @"  - [x] done\n  - [ ] ");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)[[view string] length]);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

- (void)testEnterOnEmptyTaskListItemExitsStructure
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"  - [ ] "];
    [view setSelectedRange:NSMakeRange([[view string] length], 0)];

    [view insertNewline:nil];

    XCTAssertEqualObjects([view string], @"");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)0);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

- (void)testEnterContinuesOrderedListWithIncrementedNumber
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"9. item"];
    [view setSelectedRange:NSMakeRange([[view string] length], 0)];

    [view insertNewline:nil];

    XCTAssertEqualObjects([view string], @"9. item\n10. ");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)[[view string] length]);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

- (void)testEnterOnEmptyBlockquoteLineExitsStructure
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"> "];
    [view setSelectedRange:NSMakeRange([[view string] length], 0)];

    [view insertNewline:nil];

    XCTAssertEqualObjects([view string], @"");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)0);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

@end
