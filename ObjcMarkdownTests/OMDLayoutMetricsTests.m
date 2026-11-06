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

// A long document is laid out for the width beside the vertical scroller
// before that scroller shows, so it isn't wider than the view once it does
// (#319; #121 on GNUstep).
- (NSScrollView *)autohidingScrollViewWithWidth:(CGFloat)width
{
    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 300.0)] autorelease];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    return scrollView;
}

- (void)testWidthBesideVerticalScrollerOnlyWhenTheScrollerComesAndGoes
{
    NSScrollView *noScroller = [self autohidingScrollViewWithWidth:400.0];
    [noScroller setHasVerticalScroller:NO];
    XCTAssertEqualWithAccuracy(OMDScrollViewWidthBesideVerticalScroller(noScroller), 0.0, 0.01);

    NSScrollView *alwaysShown = [self autohidingScrollViewWithWidth:400.0];
    [alwaysShown setAutohidesScrollers:NO];
    XCTAssertEqualWithAccuracy(OMDScrollViewWidthBesideVerticalScroller(alwaysShown), 0.0, 0.01);

    XCTAssertEqualWithAccuracy(OMDScrollViewWidthBesideVerticalScroller(nil), 0.0, 0.01);
}

#if defined(GNUSTEP)
- (void)testWidthBesideVerticalScrollerOnGNUstep
{
    NSScrollView *scrollView = [self autohidingScrollViewWithWidth:400.0];
    NSSize content = [NSScrollView contentSizeForFrameSize:NSMakeSize(400.0, 300.0)
                                     hasHorizontalScroller:NO
                                       hasVerticalScroller:NO
                                                borderType:[scrollView borderType]];
    XCTAssertEqualWithAccuracy(OMDScrollViewWidthBesideVerticalScroller(scrollView),
                               content.width - [NSScroller scrollerWidth] - 1.0, 0.01);
}
#else
- (void)testWidthBesideLegacyVerticalScrollerIsTheWidthWhenItShows
{
    NSScrollView *scrollView = [self autohidingScrollViewWithWidth:400.0];
    [scrollView setScrollerStyle:NSScrollerStyleLegacy];
    NSSize shown = [NSScrollView contentSizeForFrameSize:NSMakeSize(400.0, 300.0)
                                 horizontalScrollerClass:Nil
                                   verticalScrollerClass:[NSScroller class]
                                              borderType:[scrollView borderType]
                                             controlSize:NSControlSizeRegular
                                           scrollerStyle:NSScrollerStyleLegacy];
    CGFloat width = OMDScrollViewWidthBesideVerticalScroller(scrollView);
    XCTAssertEqualWithAccuracy(width, shown.width, 0.01);
    XCTAssertTrue(width > 0.0 && width < 400.0);
}

- (void)testOverlayScrollersTakeNoWidth
{
    NSScrollView *scrollView = [self autohidingScrollViewWithWidth:400.0];
    [scrollView setScrollerStyle:NSScrollerStyleOverlay];
    XCTAssertEqualWithAccuracy(OMDScrollViewWidthBesideVerticalScroller(scrollView), 0.0, 0.01);
}
#endif

@end
