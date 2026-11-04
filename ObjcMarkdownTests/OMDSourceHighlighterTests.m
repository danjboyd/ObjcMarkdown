// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDSourceHighlighter.h"

@interface OMDSourceHighlighterTests : XCTestCase
@end

@implementation OMDSourceHighlighterTests

static NSColor *OMDColorAt(NSMutableAttributedString *string, NSString *needle)
{
    NSRange range = [[string string] rangeOfString:needle];
    if (range.location == NSNotFound) {
        return nil;
    }
    return [string attribute:NSForegroundColorAttributeName
                     atIndex:range.location
              effectiveRange:NULL];
}

- (void)testHighlightsPrimaryMarkdownTokens
{
    NSString *markdown = @"# Heading\n\nplain text\n- item one\nOpen [Link](https://example.com) and `code` plus $x+y$.\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.84 green:0.84 blue:0.84 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.17 green:0.18 blue:0.20 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSColor *headingColor = OMDColorAt(styled, @"Heading");
    NSColor *plainColor = OMDColorAt(styled, @"plain text");
    NSColor *listColor = OMDColorAt(styled, @"- item one");
    NSColor *linkColor = OMDColorAt(styled, @"[Link](https://example.com)");
    NSColor *codeColor = OMDColorAt(styled, @"`code`");
    NSColor *mathColor = OMDColorAt(styled, @"$x+y$");

    XCTAssertNotNil(headingColor);
    XCTAssertNotNil(plainColor);
    XCTAssertNotNil(listColor);
    XCTAssertNotNil(linkColor);
    XCTAssertNotNil(codeColor);
    XCTAssertNotNil(mathColor);

    XCTAssertTrue([plainColor isEqual:base]);
    XCTAssertFalse([headingColor isEqual:base]);
    XCTAssertFalse([listColor isEqual:base]);
    XCTAssertFalse([linkColor isEqual:base]);
    XCTAssertFalse([codeColor isEqual:base]);
    XCTAssertFalse([mathColor isEqual:base]);
}

// Source text gets no ligatures (#125): GNUstep would draw "fi" as U+FB01,
// one cell in a monospaced font, and shift the columns after it.
- (void)testHighlightTurnsOffLigatures
{
    NSString *markdown = @"# first\n\n    fifty | fish\n`final` and plain fi text\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSUInteger index = 0;
    while (index < [styled length]) {
        NSRange effective = NSMakeRange(0, 0);
        NSNumber *ligature = [styled attribute:NSLigatureAttributeName
                                       atIndex:index
                                effectiveRange:&effective];
        XCTAssertNotNil(ligature, @"no ligature attribute at %lu", (unsigned long)index);
        XCTAssertEqual([ligature intValue], 0, @"ligatures on at %lu", (unsigned long)index);
        index = NSMaxRange(effective);
    }
}

- (void)testFencedCodeWinsOverLinkHighlighting
{
    NSString *markdown = @"```md\n[not-a-link](x)\n```\n\n[real-link](y)\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.10 green:0.10 blue:0.10 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.96 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSRange fencedRange = [[styled string] rangeOfString:@"[not-a-link](x)"];
    NSRange normalRange = [[styled string] rangeOfString:@"[real-link](y)"];
    XCTAssertTrue(fencedRange.location != NSNotFound);
    XCTAssertTrue(normalRange.location != NSNotFound);

    NSColor *fencedColor = [styled attribute:NSForegroundColorAttributeName
                                     atIndex:fencedRange.location
                              effectiveRange:NULL];
    NSColor *normalLinkColor = [styled attribute:NSForegroundColorAttributeName
                                         atIndex:normalRange.location
                                  effectiveRange:NULL];
    XCTAssertNotNil(fencedColor);
    XCTAssertNotNil(normalLinkColor);
    XCTAssertFalse([fencedColor isEqual:base]);
    XCTAssertFalse([normalLinkColor isEqual:base]);
    XCTAssertFalse([fencedColor isEqual:normalLinkColor]);
}

- (void)testLargeDocumentHighlightingPerformanceGuardrail
{
    NSMutableString *markdown = [NSMutableString string];
    NSUInteger i = 0;
    for (; i < 1800; i++) {
        [markdown appendFormat:@"# Heading %lu\n", (unsigned long)i];
        [markdown appendString:@"- item alpha beta gamma\n"];
        [markdown appendString:@"Inline `code` with [link](https://example.com) and $x+y$.\n"];
        [markdown appendString:@"```swift\nlet n = 42\nprint(n)\n```\n\n"];
    }

    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.12 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.97 green:0.97 blue:0.97 alpha:1.0];

    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;

    XCTAssertTrue(elapsed < 6.0);
    XCTAssertTrue([styled length] == [markdown length]);
}

- (void)testIndentedCodeBlockUsesCodeColorViaParserStyles
{
    NSString *markdown = @"    int value = 42;\n\nplain text\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.15 green:0.15 blue:0.15 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.96 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSColor *codeLineColor = OMDColorAt(styled, @"int value = 42");
    NSColor *plainColor = OMDColorAt(styled, @"plain text");
    XCTAssertNotNil(codeLineColor);
    XCTAssertNotNil(plainColor);
    XCTAssertFalse([codeLineColor isEqual:base]);
    XCTAssertTrue([plainColor isEqual:base]);
}

- (void)testHighlightOptionsAllowHighContrastAndAccentOverride
{
    NSString *markdown = @"# Heading\n[link](x)\n";
    NSMutableAttributedString *normal = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSMutableAttributedString *accented = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.85 green:0.85 blue:0.85 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.18 green:0.18 blue:0.20 alpha:1.0];
    NSColor *accent = [NSColor colorWithCalibratedRed:0.92 green:0.30 blue:0.22 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:normal
                                      baseTextColor:base
                                    backgroundColor:background
                                            options:@{ OMDSourceHighlighterOptionHighContrast: @NO }
                                        targetRange:NSMakeRange(NSNotFound, 0)];
    [OMDSourceHighlighter highlightAttributedString:accented
                                      baseTextColor:base
                                    backgroundColor:background
                                            options:@{
                                                OMDSourceHighlighterOptionHighContrast: @YES,
                                                OMDSourceHighlighterOptionAccentColor: accent
                                            }
                                        targetRange:NSMakeRange(NSNotFound, 0)];

    NSColor *normalHeading = OMDColorAt(normal, @"Heading");
    NSColor *accentHeading = OMDColorAt(accented, @"Heading");
    NSColor *accentLink = OMDColorAt(accented, @"[link](x)");
    XCTAssertNotNil(normalHeading);
    XCTAssertNotNil(accentHeading);
    XCTAssertNotNil(accentLink);
    XCTAssertFalse([normalHeading isEqual:accentHeading]);
    XCTAssertTrue([accentHeading isEqual:accentLink]);
}

- (void)testTargetRangeHighlightOnlyTouchesRequestedSegment
{
    NSString *markdown = @"# first\n\n# second\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.14 green:0.14 blue:0.14 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.96 alpha:1.0];

    [styled addAttribute:NSForegroundColorAttributeName value:base range:NSMakeRange(0, [styled length])];

    NSRange firstLine = [[styled string] lineRangeForRange:NSMakeRange(0, 0)];
    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background
                                            options:nil
                                        targetRange:firstLine];

    NSColor *firstHeadingColor = OMDColorAt(styled, @"first");
    NSColor *secondHeadingColor = OMDColorAt(styled, @"second");
    XCTAssertNotNil(firstHeadingColor);
    XCTAssertNotNil(secondHeadingColor);
    XCTAssertFalse([firstHeadingColor isEqual:base]);
    XCTAssertTrue([secondHeadingColor isEqual:base]);
}

// The ranges the storage reports as edited, one per edit.
static NSMutableArray *OMDObserveStorageEdits(NSTextStorage *storage, id *observer)
{
    NSMutableArray *edits = [NSMutableArray array];
    *observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSTextStorageWillProcessEditingNotification
                    object:storage
                     queue:nil
                usingBlock:^(NSNotification *note) {
                    (void)note;
                    [edits addObject:[NSValue valueWithRange:[storage editedRange]]];
                }];
    return edits;
}

// Highlighting the storage again sets only the colours that changed (#164):
// each storage edit makes GNUstep lay out and redraw the text view.
- (void)testHighlightingTheStorageAgainEditsOnlyWhatChanged
{
    NSString *markdown = @"# Heading\n\nSome text\nSome text\n- item\n`code` and [a](b)\nSome text\n";
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    id observer = nil;
    NSMutableArray *edits = OMDObserveStorageEdits(storage, &observer);

    [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
    XCTAssertEqual([edits count], (NSUInteger)1);
    NSMutableAttributedString *expected = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    [OMDSourceHighlighter highlightAttributedString:expected baseTextColor:base backgroundColor:background];
    XCTAssertEqualObjects(OMDColorAt(storage, @"Heading"), OMDColorAt(expected, @"Heading"));
    XCTAssertEqualObjects(OMDColorAt(storage, @"`code`"), OMDColorAt(expected, @"`code`"));
    XCTAssertEqualObjects(OMDColorAt(storage, @"Some text"), base);
    XCTAssertEqualObjects([storage attribute:NSLigatureAttributeName atIndex:0 effectiveRange:NULL],
                          [NSNumber numberWithInt:0]);

    // Nothing changed: no edit at all, so no layout and no redraw.
    [edits removeAllObjects];
    [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
    XCTAssertEqual([edits count], (NSUInteger)0);

    // A typed letter in plain text: the storage's own edit, then nothing to recolour.
    NSUInteger at = [markdown rangeOfString:@"Some text\n- item"].location + 4;
    [storage replaceCharactersInRange:NSMakeRange(at, 0) withString:@"x"];
    [edits removeAllObjects];
    [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
    XCTAssertTrue([edits count] <= 1);
    for (NSValue *value in edits) {
        XCTAssertTrue([value rangeValue].length <= 1, @"%@", NSStringFromRange([value rangeValue]));
    }

    // A line that becomes a heading: only that line is recoloured.
    NSUInteger lineStart = [[storage string] rangeOfString:@"Somex text\n- item"].location;
    [storage replaceCharactersInRange:NSMakeRange(lineStart, 0) withString:@"# "];
    [edits removeAllObjects];
    [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
    XCTAssertEqual([edits count], (NSUInteger)1);
    NSRange edited = [[edits objectAtIndex:0] rangeValue];
    XCTAssertTrue(edited.location >= lineStart && NSMaxRange(edited) <= lineStart + [@"# Somex text" length],
                  @"%@", NSStringFromRange(edited));
    XCTAssertEqualObjects(OMDColorAt(storage, @"# Somex text"), OMDColorAt(storage, @"# Heading"));

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

// Not a check: with OMD_HIGHLIGHT_TIMING set, prints what one colouring pass
// costs by document size, with no window (#164). Compare builds by these.
- (void)testPrintHighlightTimings
{
    if (getenv("OMD_HIGHLIGHT_TIMING") == NULL) {
        return;
    }
    NSString *block = @"# A heading\n\nA paragraph with **bold**, *italic*, `code` and a [link](https://example.com).\n\n- one\n- two\n\n```c\nint main(void) { return 0; }\n```\n\n";
    NSUInteger sizes[] = { 200, 2000, 20000, 100000 };
    NSUInteger s = 0;
    for (; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
        NSMutableString *text = [NSMutableString string];
        while ([text length] < sizes[s]) {
            [text appendString:block];
        }
        NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:text] autorelease];
        NSColor *base = [NSColor blackColor];
        NSColor *background = [NSColor whiteColor];
        [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
        NSUInteger reps = 15;
        NSDate *start = [NSDate date];
        NSUInteger r = 0;
        for (; r < reps; r++) {
            [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
        }
        double repeat = -[start timeIntervalSinceNow] * 1000.0 / reps;
        start = [NSDate date];
        for (r = 0; r < reps; r++) {
            [storage replaceCharactersInRange:NSMakeRange([storage length] / 2, 0) withString:@"x"];
            [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
        }
        double typed = -[start timeIntervalSinceNow] * 1000.0 / reps;
        NSLog(@"OMDHighlightTiming chars=%lu repeat=%.2fms typed=%.2fms", (unsigned long)[storage length], repeat, typed);
    }
}

@end
