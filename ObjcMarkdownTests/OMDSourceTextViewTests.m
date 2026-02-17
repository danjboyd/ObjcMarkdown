// ObjcMarkdownTests
// SPDX-License-Identifier: Apache-2.0

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDSourceTextView.h"

@interface OMDSourceTextViewTests : XCTestCase
@end

@implementation OMDSourceTextViewTests

- (OMDSourceTextView *)newSourceView
{
    OMDSourceTextView *view = [[OMDSourceTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    [view setEditable:YES];
    [view setSelectable:YES];
    [view setRichText:NO];
    return view;
}

- (void)testTabIndentsBulletListLine
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"- item"];
    [view setSelectedRange:NSMakeRange(2, 0)];

    [view insertTab:nil];

    XCTAssertEqualObjects([view string], @"    - item");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)6);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

- (void)testBacktabOutdentsBulletListLine
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"    - item"];
    [view setSelectedRange:NSMakeRange(6, 0)];

    [view insertBacktab:nil];

    XCTAssertEqualObjects([view string], @"- item");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

- (void)testTabIndentsEachSelectedListLine
{
    OMDSourceTextView *view = [self newSourceView];
    NSString *source = @"- one\n1. two\nplain\n- three";
    [view setString:source];
    [view setSelectedRange:NSMakeRange(0, [source length])];

    [view insertTab:nil];

    XCTAssertEqualObjects([view string], @"    - one\n    1. two\nplain\n    - three");
    [view release];
}

- (void)testBacktabOutdentsEachSelectedListLine
{
    OMDSourceTextView *view = [self newSourceView];
    NSString *source = @"    - one\n    1. two\nplain\n    - three";
    [view setString:source];
    [view setSelectedRange:NSMakeRange(0, [source length])];

    [view insertBacktab:nil];

    XCTAssertEqualObjects([view string], @"- one\n1. two\nplain\n- three");
    [view release];
}

@end
