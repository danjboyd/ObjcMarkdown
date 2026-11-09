// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDPreviewSync.h"
#import "OMMarkdownRenderer.h"
#import "OMMarkdownParsingOptions.h"
#include "cmark-gfm.h"
#import <AppKit/AppKit.h>

@interface OMDPreviewSyncTests : XCTestCase
@end

@implementation OMDPreviewSyncTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

static NSDictionary *OMDAnchorWithBlockID(NSUInteger sourceStartLine,
                                          NSUInteger sourceEndLine,
                                          NSUInteger targetStart,
                                          NSUInteger targetLength,
                                          NSString *blockID)
{
    NSMutableDictionary *anchor = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedInteger:sourceStartLine], OMMarkdownRendererAnchorSourceStartLineKey,
                                   [NSNumber numberWithUnsignedInteger:sourceEndLine], OMMarkdownRendererAnchorSourceEndLineKey,
                                   [NSNumber numberWithUnsignedInteger:targetStart], OMMarkdownRendererAnchorTargetStartKey,
                                   [NSNumber numberWithUnsignedInteger:targetLength], OMMarkdownRendererAnchorTargetLengthKey,
                                   nil];
    if (blockID != nil && [blockID length] > 0) {
        [anchor setObject:blockID forKey:OMMarkdownRendererAnchorBlockIDKey];
    }
    return anchor;
}

static NSDictionary *OMDAnchor(NSUInteger sourceStartLine,
                                NSUInteger sourceEndLine,
                                NSUInteger targetStart,
                                NSUInteger targetLength)
{
    return OMDAnchorWithBlockID(sourceStartLine,
                                sourceEndLine,
                                targetStart,
                                targetLength,
                                nil);
}

- (void)testNormalizedRatioHandlesZeroLength
{
    XCTAssertEqualWithAccuracy(OMDNormalizedLocationRatio(0, 0), 0.0, 0.000001);
    XCTAssertEqualWithAccuracy(OMDNormalizedLocationRatio(42, 0), 0.0, 0.000001);
}

- (void)testNormalizedRatioClampsToBounds
{
    XCTAssertEqualWithAccuracy(OMDNormalizedLocationRatio(0, 100), 0.0, 0.000001);
    XCTAssertEqualWithAccuracy(OMDNormalizedLocationRatio(50, 100), 0.5, 0.000001);
    XCTAssertEqualWithAccuracy(OMDNormalizedLocationRatio(150, 100), 1.0, 0.000001);
}

- (void)testLocationMappingScalesBetweenBuffers
{
    XCTAssertEqual(OMDMapLocationBetweenLengths(0, 100, 200), (NSUInteger)0);
    XCTAssertEqual(OMDMapLocationBetweenLengths(50, 100, 200), (NSUInteger)100);
    XCTAssertEqual(OMDMapLocationBetweenLengths(100, 100, 200), (NSUInteger)199);
}

- (void)testLocationMappingHandlesEdgeCases
{
    XCTAssertEqual(OMDMapLocationBetweenLengths(99, 0, 250), (NSUInteger)0);
    XCTAssertEqual(OMDMapLocationBetweenLengths(400, 100, 80), (NSUInteger)79);
    XCTAssertEqual(OMDMapLocationBetweenLengths(10, 100, 0), (NSUInteger)0);
}

- (void)testTextAwareMappingPrefersTokenAnchor
{
    NSString *source = @"# Heading\n\nAlpha beta gamma\n\nTail.\n";
    NSString *target = @"Heading\n\nAlpha beta gamma\n\nTail.\n";

    NSUInteger sourceLocation = [source rangeOfString:@"beta"].location;
    NSUInteger mapped = OMDMapLocationBetweenTexts(source, sourceLocation, target);

    NSRange alphaRange = [target rangeOfString:@"Alpha"];
    NSRange gammaRange = [target rangeOfString:@"gamma"];
    XCTAssertTrue(alphaRange.location != NSNotFound);
    XCTAssertTrue(gammaRange.location != NSNotFound);
    XCTAssertTrue(mapped >= alphaRange.location);
    XCTAssertTrue(mapped <= NSMaxRange(gammaRange));
}

- (void)testTextAwareMappingFallsBackWhenNoTokenMatches
{
    NSString *source = @"### ***\n\n....\n";
    NSString *target = @"Simple plain output";
    NSUInteger sourceLocation = 4;

    NSUInteger expected = OMDMapLocationBetweenLengths(sourceLocation,
                                                       [source length],
                                                       [target length]);
    NSUInteger mapped = OMDMapLocationBetweenTexts(source, sourceLocation, target);
    XCTAssertEqual(mapped, expected);
}

- (void)testTextAwareMappingHandlesListMarkers
{
    NSString *source = @"- Alpha beta gamma\n- Delta item\n";
    NSString *target = @"Alpha beta gamma\nDelta item\n";
    NSUInteger sourceLocation = [source rangeOfString:@"beta"].location;
    NSUInteger mapped = OMDMapLocationBetweenTexts(source, sourceLocation, target);

    NSRange betaRange = [target rangeOfString:@"beta"];
    XCTAssertTrue(betaRange.location != NSNotFound);
    NSRange lineRange = [target lineRangeForRange:NSMakeRange(betaRange.location, 0)];
    XCTAssertTrue(mapped >= lineRange.location);
    XCTAssertTrue(mapped < NSMaxRange(lineRange));
}

- (void)testTextAwareMappingHandlesFencedCodeBlocks
{
    NSString *source = @"```objc\nint main(void) {\n  return 0;\n}\n```\nAfter text\n";
    NSString *target = @"int main(void) {\n  return 0;\n}\nAfter text\n";
    NSUInteger sourceLocation = [source rangeOfString:@"return 0"].location;
    NSUInteger mapped = OMDMapLocationBetweenTexts(source, sourceLocation, target);

    NSRange returnRange = [target rangeOfString:@"return 0"];
    XCTAssertTrue(returnRange.location != NSNotFound);
    NSRange lineRange = [target lineRangeForRange:NSMakeRange(returnRange.location, 0)];
    XCTAssertTrue(mapped >= lineRange.location);
    XCTAssertTrue(mapped < NSMaxRange(lineRange));
}

- (void)testTextAwareMappingPrefersExpectedOccurrenceForRepeatedTokens
{
    NSString *source = @"# Heading\n\nSame token\n\nMiddle\n\nSame token\n";
    NSString *target = @"Heading\n\nSame token\n\nMiddle\n\nSame token\n";

    NSRange firstSource = [source rangeOfString:@"Same token"];
    XCTAssertTrue(firstSource.location != NSNotFound);
    NSRange secondSource = [source rangeOfString:@"Same token"
                                         options:0
                                           range:NSMakeRange(NSMaxRange(firstSource),
                                                             [source length] - NSMaxRange(firstSource))];
    XCTAssertTrue(secondSource.location != NSNotFound);
    NSUInteger sourceLocation = secondSource.location + 2;
    NSUInteger mapped = OMDMapLocationBetweenTexts(source, sourceLocation, target);

    NSRange firstTarget = [target rangeOfString:@"Same token"];
    XCTAssertTrue(firstTarget.location != NSNotFound);
    NSRange secondTarget = [target rangeOfString:@"Same token"
                                         options:0
                                           range:NSMakeRange(NSMaxRange(firstTarget),
                                                             [target length] - NSMaxRange(firstTarget))];
    XCTAssertTrue(secondTarget.location != NSNotFound);
    NSRange lineRange = [target lineRangeForRange:NSMakeRange(secondTarget.location, 0)];
    XCTAssertTrue(mapped >= lineRange.location);
    XCTAssertTrue(mapped < NSMaxRange(lineRange));
}

- (void)testBlockAnchorMappingSourceToTargetPrefersMappedLine
{
    NSString *source = @"first alpha\nsecond alpha\n";
    NSString *target = @"alpha\nalpha\n";

    NSRange firstTarget = [target rangeOfString:@"alpha"];
    XCTAssertTrue(firstTarget.location != NSNotFound);
    NSRange secondTarget = [target rangeOfString:@"alpha"
                                         options:0
                                           range:NSMakeRange(NSMaxRange(firstTarget),
                                                             [target length] - NSMaxRange(firstTarget))];
    XCTAssertTrue(secondTarget.location != NSNotFound);

    NSArray *anchors = [NSArray arrayWithObjects:
                        OMDAnchor(1, 1, firstTarget.location, firstTarget.length),
                        OMDAnchor(2, 2, secondTarget.location, secondTarget.length),
                        nil];

    NSRange firstBreak = [source rangeOfString:@"\n"];
    XCTAssertTrue(firstBreak.location != NSNotFound);
    NSRange secondSourceAlpha = [source rangeOfString:@"alpha"
                                              options:0
                                                range:NSMakeRange(NSMaxRange(firstBreak),
                                                                  [source length] - NSMaxRange(firstBreak))];
    XCTAssertTrue(secondSourceAlpha.location != NSNotFound);
    NSUInteger mapped = OMDMapSourceLocationWithBlockAnchors(source,
                                                             secondSourceAlpha.location + 1,
                                                             target,
                                                             anchors);

    NSRange secondLine = [target lineRangeForRange:NSMakeRange(secondTarget.location, 0)];
    XCTAssertTrue(mapped >= secondLine.location);
    XCTAssertTrue(mapped < NSMaxRange(secondLine));
}

- (void)testBlockAnchorMappingTargetToSourcePrefersMappedLine
{
    NSString *source = @"first alpha\nsecond alpha\n";
    NSString *target = @"alpha\nalpha\n";

    NSRange firstTarget = [target rangeOfString:@"alpha"];
    XCTAssertTrue(firstTarget.location != NSNotFound);
    NSRange secondTarget = [target rangeOfString:@"alpha"
                                         options:0
                                           range:NSMakeRange(NSMaxRange(firstTarget),
                                                             [target length] - NSMaxRange(firstTarget))];
    XCTAssertTrue(secondTarget.location != NSNotFound);

    NSArray *anchors = [NSArray arrayWithObjects:
                        OMDAnchor(1, 1, firstTarget.location, firstTarget.length),
                        OMDAnchor(2, 2, secondTarget.location, secondTarget.length),
                        nil];

    NSUInteger mapped = OMDMapTargetLocationWithBlockAnchors(source,
                                                             target,
                                                             secondTarget.location + 1,
                                                             anchors);

    NSRange secondWord = [source rangeOfString:@"second"];
    XCTAssertTrue(secondWord.location != NSNotFound);
    NSRange secondSourceLine = [source lineRangeForRange:NSMakeRange(secondWord.location, 0)];
    XCTAssertTrue(mapped >= secondSourceLine.location);
    XCTAssertTrue(mapped < NSMaxRange(secondSourceLine));
}

- (void)testBlockAnchorMappingFallsBackWhenLineHasNoAnchor
{
    NSString *source = @"alpha\nbeta\n";
    NSString *target = @"alpha\nbeta\n";
    NSUInteger sourceLocation = [source rangeOfString:@"beta"].location;

    NSRange alphaTarget = [target rangeOfString:@"alpha"];
    XCTAssertTrue(alphaTarget.location != NSNotFound);
    NSArray *anchors = [NSArray arrayWithObject:OMDAnchor(1, 1, alphaTarget.location, alphaTarget.length)];

    NSUInteger expected = OMDMapLocationBetweenTexts(source, sourceLocation, target);
    NSUInteger mapped = OMDMapSourceLocationWithBlockAnchors(source,
                                                             sourceLocation,
                                                             target,
                                                             anchors);
    XCTAssertEqual(mapped, expected);
}

- (void)testBlockIDMappingSourceToTargetSurvivesLineShift
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *oldSource = @"first alpha\n\nsecond beta\n";
    NSString *newSource = @"intro\n\nfirst alpha\n\nsecond beta\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:oldSource];
    NSString *target = [rendered string];
    NSArray *rendererAnchors = [renderer blockAnchors];

    NSString *firstBlockID = nil;
    for (NSDictionary *anchor in rendererAnchors) {
        NSNumber *startLine = [anchor objectForKey:OMMarkdownRendererAnchorSourceStartLineKey];
        if (startLine != nil && [startLine integerValue] == 1) {
            firstBlockID = [anchor objectForKey:OMMarkdownRendererAnchorBlockIDKey];
            if (firstBlockID != nil && [firstBlockID length] > 0) {
                break;
            }
        }
    }
    XCTAssertNotNil(firstBlockID);

    NSRange firstTarget = [target rangeOfString:@"first alpha"];
    NSRange secondTarget = [target rangeOfString:@"second beta"];
    XCTAssertTrue(firstTarget.location != NSNotFound);
    XCTAssertTrue(secondTarget.location != NSNotFound);

    NSArray *shiftedAnchors = [NSArray arrayWithObjects:
                               OMDAnchorWithBlockID(1, 1, firstTarget.location, firstTarget.length, firstBlockID),
                               OMDAnchor(3, 3, secondTarget.location, secondTarget.length),
                               nil];

    NSRange firstInNew = [newSource rangeOfString:@"first alpha"];
    XCTAssertTrue(firstInNew.location != NSNotFound);
    NSUInteger mapped = OMDMapSourceLocationWithBlockAnchors(newSource,
                                                             firstInNew.location + 2,
                                                             target,
                                                             shiftedAnchors);
    NSRange firstLine = [target lineRangeForRange:NSMakeRange(firstTarget.location, 0)];
    XCTAssertTrue(mapped >= firstLine.location);
    XCTAssertTrue(mapped < NSMaxRange(firstLine));
}

- (void)testBlockIDMappingTargetToSourceSurvivesLineShift
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *oldSource = @"first alpha\n\nsecond beta\n";
    NSString *newSource = @"intro\n\nfirst alpha\n\nsecond beta\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:oldSource];
    NSString *target = [rendered string];
    NSArray *rendererAnchors = [renderer blockAnchors];

    NSString *firstBlockID = nil;
    for (NSDictionary *anchor in rendererAnchors) {
        NSNumber *startLine = [anchor objectForKey:OMMarkdownRendererAnchorSourceStartLineKey];
        if (startLine != nil && [startLine integerValue] == 1) {
            firstBlockID = [anchor objectForKey:OMMarkdownRendererAnchorBlockIDKey];
            if (firstBlockID != nil && [firstBlockID length] > 0) {
                break;
            }
        }
    }
    XCTAssertNotNil(firstBlockID);

    NSRange firstTarget = [target rangeOfString:@"first alpha"];
    NSRange secondTarget = [target rangeOfString:@"second beta"];
    XCTAssertTrue(firstTarget.location != NSNotFound);
    XCTAssertTrue(secondTarget.location != NSNotFound);

    NSArray *shiftedAnchors = [NSArray arrayWithObjects:
                               OMDAnchorWithBlockID(1, 1, firstTarget.location, firstTarget.length, firstBlockID),
                               OMDAnchor(3, 3, secondTarget.location, secondTarget.length),
                               nil];

    NSUInteger mapped = OMDMapTargetLocationWithBlockAnchors(newSource,
                                                             target,
                                                             firstTarget.location + 2,
                                                             shiftedAnchors);
    NSRange firstInNew = [newSource rangeOfString:@"first alpha"];
    XCTAssertTrue(firstInNew.location != NSNotFound);
    NSRange firstLine = [newSource lineRangeForRange:NSMakeRange(firstInNew.location, 0)];
    XCTAssertTrue(mapped >= firstLine.location);
    XCTAssertTrue(mapped < NSMaxRange(firstLine));
}

- (void)testBlockIDMappingSourceToTargetPrefersExpectedDuplicateBlock
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *oldSource = @"repeat block\n\nrepeat block\n";
    NSString *newSource = @"intro\n\nrepeat block\n\nrepeat block\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:oldSource];
    NSString *target = [rendered string];
    NSArray *anchors = [renderer blockAnchors];

    NSRange firstTargetRepeat = [target rangeOfString:@"repeat block"];
    XCTAssertTrue(firstTargetRepeat.location != NSNotFound);
    NSRange secondTargetRepeat = [target rangeOfString:@"repeat block"
                                               options:0
                                                 range:NSMakeRange(NSMaxRange(firstTargetRepeat),
                                                                   [target length] - NSMaxRange(firstTargetRepeat))];
    XCTAssertTrue(secondTargetRepeat.location != NSNotFound);

    NSRange firstNewRepeat = [newSource rangeOfString:@"repeat block"];
    XCTAssertTrue(firstNewRepeat.location != NSNotFound);
    NSRange secondNewRepeat = [newSource rangeOfString:@"repeat block"
                                               options:0
                                                 range:NSMakeRange(NSMaxRange(firstNewRepeat),
                                                                   [newSource length] - NSMaxRange(firstNewRepeat))];
    XCTAssertTrue(secondNewRepeat.location != NSNotFound);

    NSUInteger mapped = OMDMapSourceLocationWithBlockAnchors(newSource,
                                                             secondNewRepeat.location + 2,
                                                             target,
                                                             anchors);
    NSRange secondTargetLine = [target lineRangeForRange:NSMakeRange(secondTargetRepeat.location, 0)];
    XCTAssertTrue(mapped >= secondTargetLine.location);
    XCTAssertTrue(mapped < NSMaxRange(secondTargetLine));
}

- (void)testBlockIDMappingTargetToSourcePrefersExpectedDuplicateBlock
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *oldSource = @"repeat block\n\nrepeat block\n";
    NSString *newSource = @"intro\n\nrepeat block\n\nrepeat block\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:oldSource];
    NSString *target = [rendered string];
    NSArray *anchors = [renderer blockAnchors];

    NSRange firstTargetRepeat = [target rangeOfString:@"repeat block"];
    XCTAssertTrue(firstTargetRepeat.location != NSNotFound);
    NSRange secondTargetRepeat = [target rangeOfString:@"repeat block"
                                               options:0
                                                 range:NSMakeRange(NSMaxRange(firstTargetRepeat),
                                                                   [target length] - NSMaxRange(firstTargetRepeat))];
    XCTAssertTrue(secondTargetRepeat.location != NSNotFound);

    NSRange firstNewRepeat = [newSource rangeOfString:@"repeat block"];
    XCTAssertTrue(firstNewRepeat.location != NSNotFound);
    NSRange secondNewRepeat = [newSource rangeOfString:@"repeat block"
                                               options:0
                                                 range:NSMakeRange(NSMaxRange(firstNewRepeat),
                                                                   [newSource length] - NSMaxRange(firstNewRepeat))];
    XCTAssertTrue(secondNewRepeat.location != NSNotFound);

    NSUInteger mapped = OMDMapTargetLocationWithBlockAnchors(newSource,
                                                             target,
                                                             secondTargetRepeat.location + 2,
                                                             anchors);
    NSRange secondNewLine = [newSource lineRangeForRange:NSMakeRange(secondNewRepeat.location, 0)];
    XCTAssertTrue(mapped >= secondNewLine.location);
    XCTAssertTrue(mapped < NSMaxRange(secondNewLine));
}

- (void)testBlockAnchorMappingIgnoresInvalidZeroLengthAnchorRanges
{
    NSString *source = @"alpha\nbeta\n";
    NSString *target = @"alpha\nbeta\n";
    NSUInteger sourceLocation = [source rangeOfString:@"beta"].location;
    NSUInteger targetLocation = [target rangeOfString:@"beta"].location;

    NSArray *anchors = [NSArray arrayWithObject:OMDAnchor(2, 2, targetLocation, 0)];

    NSUInteger expectedToTarget = OMDMapLocationBetweenTexts(source, sourceLocation, target);
    NSUInteger mappedToTarget = OMDMapSourceLocationWithBlockAnchors(source,
                                                                     sourceLocation,
                                                                     target,
                                                                     anchors);
    XCTAssertEqual(mappedToTarget, expectedToTarget);

    NSUInteger expectedToSource = OMDMapLocationBetweenTexts(target, targetLocation, source);
    NSUInteger mappedToSource = OMDMapTargetLocationWithBlockAnchors(source,
                                                                     target,
                                                                     targetLocation,
                                                                     anchors);
    XCTAssertEqual(mappedToSource, expectedToSource);
}

// Documents with every kind of block the sync anchors, and the ways a
// renderer's parse could differ from the sync's.
- (NSArray *)syncCorpus346
{
    NSMutableArray *documents = [NSMutableArray array];
    NSString *specDir = [NSString stringWithUTF8String:OM_SPEC_DIR];
    for (NSString *name in [NSArray arrayWithObjects:@"spec.txt", @"extensions.txt", nil]) {
        NSString *text = [NSString stringWithContentsOfFile:[specDir stringByAppendingPathComponent:name]
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
        XCTAssertNotNil(text, @"%@ not found under %@", name, specDir);
        // Without their front matter, which the renderer blanks (tested below).
        if ([text hasPrefix:@"---"]) {
            NSRange end = [text rangeOfString:@"\n...\n" options:0 range:NSMakeRange(3, [text length] - 3)];
            if (end.location == NSNotFound) {
                end = [text rangeOfString:@"\n---\n" options:0 range:NSMakeRange(3, [text length] - 3)];
            }
            text = end.location != NSNotFound ? [text substringFromIndex:NSMaxRange(end)] : nil;
        }
        if (text != nil) {
            [documents addObject:text];
        }
    }
    NSMutableString *mixed = [NSMutableString stringWithString:
        @"# Title\n\nPara with a footnote[^a] and another[^b].\n\n"
         "Setext\n------\n\n- one\n  - nested\n    1. ordered\n- [ ] task\n\n> quote\n>\n> > nested quote\n\n"
         "```objc\ncode\n```\n\n    indented code\n\n***\n\n<div>\nhtml block\n</div>\n\n"
         "| a | b |\n|---|---|\n| 1 | 2 |\n\n$$\nx^2\n$$\n\n[^a]: Note a.\n[^b]: Note b,\n    on two lines.\n\n"
         "[ref]: https://example.org\n\nSame paragraph.\n\nSame paragraph.\n"];
    [documents addObject:mixed];
    [documents addObject:[mixed stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"]];
    return documents;
}

// The renderer's own parse describes the blocks exactly as the sync's
// parse does (#346), or not at all.
- (void)testRendererSourceBlockDescriptorsEqualTheSyncsOwn
{
    for (NSString *markdown in [self syncCorpus346]) {
        OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
        [renderer setCollectsSourceBlockDescriptors:YES];
        [renderer attributedStringFromMarkdown:markdown];
        NSArray *expected = OMDPreviewSyncSourceBlockDescriptors(markdown);
        XCTAssertTrue([expected count] > 5);
        XCTAssertEqualObjects([renderer sourceBlockDescriptors], expected);
    }

    // Front matter is blanked for the render but not for the sync: none.
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setCollectsSourceBlockDescriptors:YES];
    [renderer attributedStringFromMarkdown:@"---\ntitle: x\n---\n\n# Heading\n\nText.\n"];
    XCTAssertNil([renderer sourceBlockDescriptors]);
    // Other cmark options: none.
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setCmarkOptions:(CMARK_OPT_DEFAULT | CMARK_OPT_SMART)];
    [renderer setParsingOptions:options];
    [renderer attributedStringFromMarkdown:@"# Heading\n\nText.\n"];
    XCTAssertNil([renderer sourceBlockDescriptors]);
    // Not asked for: none.
    OMMarkdownRenderer *plain = [[[OMMarkdownRenderer alloc] init] autorelease];
    [plain attributedStringFromMarkdown:@"# Heading\n\nText.\n"];
    XCTAssertNil([plain sourceBlockDescriptors]);
}

// Mapping with the render's descriptors gives what mapping with the sync's
// own parse gave, both ways, all through each document.
- (void)testSyncWithTheRenderersDescriptorsMapsTheSame
{
    for (NSString *markdown in [self syncCorpus346]) {
        OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
        [renderer setCollectsSourceBlockDescriptors:YES];
        NSString *preview = [[renderer attributedStringFromMarkdown:markdown] string];
        NSArray *anchors = [renderer blockAnchors];
        NSUInteger step = MAX((NSUInteger)1, [markdown length] / 300);

        // The sync's own parse: prime it with another text's blocks first.
        OMDPreviewSyncUseSourceBlockDescriptors(@"other", [NSArray array]);
        NSMutableArray *ownToPreview = [NSMutableArray array];
        NSMutableArray *ownToSource = [NSMutableArray array];
        NSUInteger location = 0;
        for (; location < [markdown length]; location += step) {
            [ownToPreview addObject:[NSNumber numberWithUnsignedInteger:
                OMDMapSourceLocationWithBlockAnchors(markdown, location, preview, anchors)]];
        }
        for (location = 0; location < [preview length]; location += step) {
            [ownToSource addObject:[NSNumber numberWithUnsignedInteger:
                OMDMapTargetLocationWithBlockAnchors(markdown, preview, location, anchors)]];
        }

        OMDPreviewSyncUseSourceBlockDescriptors([[markdown mutableCopy] autorelease], [renderer sourceBlockDescriptors]);
        NSMutableArray *primedToPreview = [NSMutableArray array];
        NSMutableArray *primedToSource = [NSMutableArray array];
        for (location = 0; location < [markdown length]; location += step) {
            [primedToPreview addObject:[NSNumber numberWithUnsignedInteger:
                OMDMapSourceLocationWithBlockAnchors(markdown, location, preview, anchors)]];
        }
        for (location = 0; location < [preview length]; location += step) {
            [primedToSource addObject:[NSNumber numberWithUnsignedInteger:
                OMDMapTargetLocationWithBlockAnchors(markdown, preview, location, anchors)]];
        }
        XCTAssertEqualObjects(primedToPreview, ownToPreview);
        XCTAssertEqualObjects(primedToSource, ownToSource);
    }
}

// The visible character found laying out only as far as it is the one a
// full layout finds (#346), after edits, all down a long source.
- (void)testVisibleCharacterIndexNeedsNoFullLayout
{
    NSMutableString *source = [NSMutableString string];
    NSUInteger line = 0;
    for (; line < 4000; line++) {
        [source appendFormat:@"Line %lu of a long source, long enough to wrap now and then %@.\n",
                             (unsigned long)line, (line % 7 == 0 ? @"with some more words added to it here" : @"")];
    }
    NSTextView *textView = [[[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 600.0)] autorelease];
    [textView setVerticallyResizable:YES];
    [textView setMaxSize:NSMakeSize(400.0, 1.0e8)];
    [[textView textStorage] setAttributedString:[[[NSAttributedString alloc] initWithString:source] autorelease]];
    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 600.0)] autorelease];
    [scrollView setDocumentView:textView];
    [[textView layoutManager] ensureLayoutForTextContainer:[textView textContainer]];
    [textView sizeToFit];

    CGFloat positions[] = { 0.0, 0.1, 0.5, 0.9, 1.0 };
    CGFloat anchors[] = { 0.0, 0.35, 1.0 };
    NSUInteger p = 0;
    for (; p < 5; p++) {
        // An edit above invalidates the layout below it, as typing does.
        [[textView textStorage] replaceCharactersInRange:NSMakeRange(10, 0) withString:@"x"];
        CGFloat maxY = MAX(0.0, NSHeight([textView frame]) - 600.0);
        [[scrollView contentView] scrollToPoint:NSMakePoint(0.0, floor(maxY * positions[p]))];
        [scrollView reflectScrolledClipView:[scrollView contentView]];
        NSUInteger a = 0;
        for (; a < 3; a++) {
            NSUInteger bounded = OMDVisibleCharacterIndexInTextView(textView, anchors[a], NO);
            NSUInteger full = OMDVisibleCharacterIndexInTextView(textView, anchors[a], YES);
            XCTAssertEqual(bounded, full, @"position %.1f anchor %.2f", positions[p], anchors[a]);
        }
    }
}

@end
