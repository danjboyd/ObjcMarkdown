// ObjcMarkdownTests
// SPDX-License-Identifier: Apache-2.0

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

@end
