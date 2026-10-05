// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDPreviewTextUpdate.h"
#import "OMMarkdownRenderer.h"
#import "OMRenderedObject.h"
#import "OMTextTable.h"

static NSString * const OMDUpdateTestDocument =
    @"# Title\n\nFirst paragraph with *emphasis*.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n"
    @"```\ncode\n```\n\nSecond paragraph.\n\n- one\n- two\n\nLast paragraph.\n";

@interface OMDPreviewTextUpdateTests : XCTestCase
@end

@implementation OMDPreviewTextUpdateTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (NSAttributedString *)render:(NSString *)markdown
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    return [renderer attributedStringFromMarkdown:markdown];
}

// Applies after to storage holding before, as the preview does after a
// full first render; the result must match after, fixed as storage fixes it.
- (NSRange)applyFrom:(NSAttributedString *)before to:(NSAttributedString *)after
{
    NSTextStorage *storage = [[[NSTextStorage alloc] init] autorelease];
    [storage setAttributedString:before];
    NSRange inserted = OMDApplyRenderedString(storage, after);
    NSMutableAttributedString *fixed = [[after mutableCopy] autorelease];
    [fixed fixAttributesInRange:NSMakeRange(0, [fixed length])];
    XCTAssertEqualObjects([storage string], [after string]);
    XCTAssertFalse(OMDChangedRangesForRender(storage, fixed, NULL, NULL));
    // Applying the same render again changes nothing.
    XCTAssertEqual(OMDApplyRenderedString(storage, after).location, (NSUInteger)NSNotFound);
    return inserted;
}

- (void)testTheSameDocumentRenderedTwiceIsUnchanged
{
    NSAttributedString *first = [self render:OMDUpdateTestDocument];
    NSAttributedString *second = [self render:OMDUpdateTestDocument];
    XCTAssertFalse(OMDChangedRangesForRender(first, second, NULL, NULL));
    NSRange inserted = [self applyFrom:first to:second];
    XCTAssertEqual(inserted.location, (NSUInteger)NSNotFound);
}

- (void)testAnEditReplacesOnlyItsParagraph
{
    NSAttributedString *before = [self render:OMDUpdateTestDocument];
    NSString *edited = [OMDUpdateTestDocument stringByReplacingOccurrencesOfString:@"Second paragraph."
                                                                        withString:@"Second, edited paragraph."];
    NSAttributedString *after = [self render:edited];
    NSRange currentRange = NSMakeRange(0, 0);
    NSRange renderedRange = NSMakeRange(0, 0);
    XCTAssertTrue(OMDChangedRangesForRender(before, after, &currentRange, &renderedRange));
    NSRange paragraph = [[after string] rangeOfString:@"Second, edited paragraph."];
    XCTAssertTrue(renderedRange.location >= paragraph.location);
    XCTAssertTrue(NSMaxRange(renderedRange) <= NSMaxRange(paragraph));
    [self applyFrom:before to:after];
}

// The rendered object of the text table holding the first text in string.
static OMRenderedObject *OMDObjectNearText(NSAttributedString *string, NSString *text)
{
    NSRange range = [[string string] rangeOfString:text];
    if (range.location == NSNotFound) {
        return nil;
    }
    OMTextTable *table = [string attribute:OMTextTableAttributeName atIndex:range.location effectiveRange:NULL];
    return [table renderedObject];
}

- (void)testObjectsBelowAnEditKeepTheirTextAndTakeTheirNewPositions
{
    NSString *document = @"Intro.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nEnd.\n";
    NSAttributedString *before = [self render:document];
    NSAttributedString *after = [self render:[@"New line.\n\n" stringByAppendingString:document]];
    NSTextStorage *storage = [[[NSTextStorage alloc] init] autorelease];
    [storage setAttributedString:before];
    OMRenderedObject *table = OMDObjectNearText(storage, @"a");
    XCTAssertNotNil(table);
    NSRange inserted = OMDApplyRenderedString(storage, after);
    XCTAssertEqualObjects([storage string], [after string]);
    // Only the new paragraph was inserted: the table kept its text and object.
    XCTAssertTrue(NSMaxRange(inserted) <= [[after string] rangeOfString:@"Intro."].location + 1);
    XCTAssertTrue(OMDObjectNearText(storage, @"a") == table);
    OMRenderedObject *expected = OMDObjectNearText(after, @"a");
    XCTAssertTrue(NSEqualRanges([table sourceLineRange], [expected sourceLineRange]));
    XCTAssertTrue(NSEqualRanges([table sourceRange], [expected sourceRange]));
}

- (void)testAttributeOnlyChangesAreReplaced
{
    // A setext underline turns the paragraph into a heading: same
    // characters, different attributes.
    NSAttributedString *before = [self render:@"Intro\n\nTitle\n\nEnd.\n"];
    NSAttributedString *after = [self render:@"Intro\n\nTitle\n=====\n\nEnd.\n"];
    NSRange currentRange = NSMakeRange(0, 0);
    NSRange renderedRange = NSMakeRange(0, 0);
    XCTAssertTrue(OMDChangedRangesForRender(before, after, &currentRange, &renderedRange));
    NSRange title = [[after string] rangeOfString:@"Title"];
    XCTAssertTrue(NSLocationInRange(title.location, renderedRange));
    [self applyFrom:before to:after];
}

- (void)testEditsAtTheEdgesAndEmptyDocuments
{
    NSAttributedString *document = [self render:OMDUpdateTestDocument];
    NSAttributedString *empty = [[[NSAttributedString alloc] initWithString:@""] autorelease];
    [self applyFrom:document to:[self render:[@"Lead.\n\n" stringByAppendingString:OMDUpdateTestDocument]]];
    [self applyFrom:document to:[self render:[OMDUpdateTestDocument stringByAppendingString:@"\nTail.\n"]]];
    [self applyFrom:empty to:document];
    [self applyFrom:document to:empty];
}

@end
