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

// Reveal in Source (#293): the source lines of the blocks under a preview
// position or selection.
- (NSRange)linesAtPreviewText:(NSString *)text inMarkdown:(NSString *)markdown length:(BOOL)whole
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *rendered = [[renderer attributedStringFromMarkdown:markdown] string];
    NSRange found = [rendered rangeOfString:text];
    XCTAssertTrue(found.location != NSNotFound, @"%@ not in the preview", text);
    NSRange range = whole ? found : NSMakeRange(found.location, 0);
    return OMDSourceLineRangeForPreviewRange(range, [renderer blockAnchors]);
}

- (void)testAPositionTakesItsInnermostBlockLines
{
    NSString *doc = OMDSelectionDocument;
    XCTAssertTrue(NSEqualRanges([self linesAtPreviewText:@"Plan" inMarkdown:doc length:NO], NSMakeRange(1, 1)));
    XCTAssertTrue(NSEqualRanges([self linesAtPreviewText:@"paragraph." inMarkdown:doc length:NO], NSMakeRange(3, 1)));
    XCTAssertTrue(NSEqualRanges([self linesAtPreviewText:@"pears" inMarkdown:doc length:NO], NSMakeRange(6, 1)));
    XCTAssertTrue(NSEqualRanges([self linesAtPreviewText:@"green" inMarkdown:doc length:NO], NSMakeRange(7, 1)));
    XCTAssertTrue(NSEqualRanges([self linesAtPreviewText:@"Quoted" inMarkdown:doc length:NO], NSMakeRange(9, 1)));
    XCTAssertTrue(NSEqualRanges([self linesAtPreviewText:@"Last" inMarkdown:doc length:NO], NSMakeRange(11, 1)));
}

- (void)testASelectionTakesTheLinesOfEveryBlockItTouches
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *rendered = [[renderer attributedStringFromMarkdown:OMDSelectionDocument] string];
    NSUInteger from = [rendered rangeOfString:@"Plan"].location;
    NSUInteger to = NSMaxRange([rendered rangeOfString:@"apples"]);
    NSRange lines = OMDSourceLineRangeForPreviewRange(NSMakeRange(from, to - from), [renderer blockAnchors]);
    XCTAssertTrue(NSEqualRanges(lines, NSMakeRange(1, 5)), @"%@", NSStringFromRange(lines));
}

- (void)testCodeBlocksAndTablesRevealAllTheirLines
{
    NSString *markdown = @"Intro.\n\n```\none\ntwo\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n";
    XCTAssertTrue(NSEqualRanges([self linesAtPreviewText:@"two" inMarkdown:markdown length:NO], NSMakeRange(3, 4)));
    NSRange table = [self linesAtPreviewText:@"2" inMarkdown:markdown length:NO];
    XCTAssertEqual(table.location, (NSUInteger)8, @"%@", NSStringFromRange(table));
    XCTAssertEqual(NSMaxRange(table), (NSUInteger)11, @"%@", NSStringFromRange(table));
}

// A position in the blank space between two blocks takes the one before.
- (void)testAPositionBetweenBlocksTakesTheBlockBefore
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *rendered = [[renderer attributedStringFromMarkdown:OMDSelectionDocument] string];
    NSUInteger end = NSMaxRange([rendered rangeOfString:@"First paragraph."]);
    NSUInteger last = NSMaxRange([rendered rangeOfString:@"Last paragraph."]);
    NSArray *anchors = [renderer blockAnchors];
    NSRange lines = OMDSourceLineRangeForPreviewRange(NSMakeRange(end + 1, 0), anchors);
    XCTAssertTrue(NSEqualRanges(lines, NSMakeRange(3, 1)) || NSEqualRanges(lines, NSMakeRange(5, 1)),
                  @"%@", NSStringFromRange(lines));
    lines = OMDSourceLineRangeForPreviewRange(NSMakeRange([rendered length], 0), anchors);
    XCTAssertTrue(NSEqualRanges(lines, NSMakeRange(11, 1)), @"after %lu: %@", (unsigned long)last,
                  NSStringFromRange(lines));
    XCTAssertEqual(OMDSourceLineRangeForPreviewRange(NSMakeRange(0, 0), nil).location, (NSUInteger)NSNotFound);
}

- (void)testDedentKeepsRelativeIndentAndBlankLines
{
    NSArray *lines = [NSArray arrayWithObjects:@"    - a", @"", @"      - b", nil];
    XCTAssertEqualObjects(OMDShareDedentedLines(lines), @"- a\n\n  - b");
}

@end
