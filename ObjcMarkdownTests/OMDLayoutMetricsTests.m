// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDLayoutMetrics.h"

@interface OMDLayoutMetricsTests : XCTestCase
@end

@implementation OMDLayoutMetricsTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

// Chrome text is the theme's size (#74), so in every density the rows and
// bars it sits in are at least as tall as that text needs.
- (void)testControlHeightsFitTheThemesText
{
    CGFloat text = OMDChromeLineHeight(OMDChromeFont());
    CGFloat smallText = OMDChromeLineHeight(OMDChromeSmallFont());
    OMDLayoutDensityMode modes[3] = {
        OMDLayoutDensityModeCompact, OMDLayoutDensityModeBalanced, OMDLayoutDensityModeAdwaita
    };
    NSUInteger i = 0;

    XCTAssertTrue(text > 0.0);
    for (i = 0; i < 3; i++) {
        OMDLayoutMetrics metrics = OMDLayoutMetricsForMode(modes[i]);
        XCTAssertTrue(metrics.explorerControlHeight >= text + 8.0);
        XCTAssertTrue(metrics.explorerMinorControlHeight >= smallText + 4.0);
        XCTAssertTrue(metrics.tabStripHeight >= text + 14.0);
        XCTAssertTrue(metrics.formattingBarControlHeight >= text + 8.0);
        XCTAssertTrue(metrics.formattingBarHeight > metrics.formattingBarControlHeight);
    }
}

- (void)testChromeFontsAreTheThemes
{
    XCTAssertEqualWithAccuracy([OMDChromeFont() pointSize], [NSFont systemFontSize], 0.01);
    XCTAssertEqualWithAccuracy([OMDChromeSmallFont() pointSize], [NSFont smallSystemFontSize], 0.01);
}

@end
