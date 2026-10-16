// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDShareSelection.h"
#import "OMMarkdownRenderer.h"

@interface OMDShareSelectionTests : XCTestCase
@end

@implementation OMDShareSelectionTests

static NSString * const OMDSelectionDocument =
    @"# Plan\n"
    @"\n"
    @"First paragraph.\n"
    @"\n"
    @"- apples\n"
    @"- pears\n"
    @"  - green pears\n"
    @"\n"
    @"> Quoted words.\n"
    @"\n"
    @"Last paragraph.\n";

// The Markdown for the preview range of the first occurrence of from
// through the end of the first occurrence of to after it.
- (NSString *)markdownSelectingFrom:(NSString *)from to:(NSString *)to
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *rendered = [[renderer attributedStringFromMarkdown:OMDSelectionDocument] string];
    NSRange start = [rendered rangeOfString:from];
    XCTAssertTrue(start.location != NSNotFound, @"%@ not in the preview", from);
    NSRange end = [rendered rangeOfString:to options:0
                                    range:NSMakeRange(start.location, [rendered length] - start.location)];
    XCTAssertTrue(end.location != NSNotFound, @"%@ not in the preview", to);
    NSRange selection = NSMakeRange(start.location, NSMaxRange(end) - start.location);
    return OMDShareMarkdownForPreviewRange(OMDSelectionDocument, selection, [renderer blockAnchors]);
}

- (void)testAWordGrowsToItsParagraph
{
    XCTAssertEqualObjects([self markdownSelectingFrom:@"paragraph" to:@"paragraph"], @"First paragraph.");
}

- (void)testASelectionAcrossBlocksTakesTheirLines
{
    XCTAssertEqualObjects([self markdownSelectingFrom:@"First" to:@"apples"], @"First paragraph.\n\n- apples");
}

- (void)testANestedItemLosesItsIndentAndStaysAList
{
    XCTAssertEqualObjects([self markdownSelectingFrom:@"green" to:@"green"], @"- green pears");
}

- (void)testAQuoteKeepsItsMarker
{
    XCTAssertEqualObjects([self markdownSelectingFrom:@"Quoted" to:@"words"], @"> Quoted words.");
}

- (void)testNoAnchorsNoSelection
{
    XCTAssertNil(OMDShareMarkdownForPreviewRange(OMDSelectionDocument, NSMakeRange(0, 3), [NSArray array]));
    XCTAssertNil(OMDShareMarkdownForPreviewRange(nil, NSMakeRange(0, 3), [NSArray array]));
}

- (void)testDedentKeepsRelativeIndentAndBlankLines
{
    NSArray *lines = [NSArray arrayWithObjects:@"    - a", @"", @"      - b", nil];
    XCTAssertEqualObjects(OMDShareDedentedLines(lines), @"- a\n\n  - b");
}

@end
