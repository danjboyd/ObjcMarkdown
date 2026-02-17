// ObjcMarkdownTests
// SPDX-License-Identifier: Apache-2.0

#import <XCTest/XCTest.h>
#import "OMDPreviewSync.h"
#import "OMMarkdownRenderer.h"

@interface OMDPreviewSyncTests : XCTestCase
@end

@implementation OMDPreviewSyncTests

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

@end
