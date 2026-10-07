// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDWin11SplitView.h"

#include <math.h>

@interface OMDWin11SplitViewTests : XCTestCase
@end

@implementation OMDWin11SplitViewTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (OMDWin11SplitView *)newSplitViewWithLeading:(NSView **)leadingOut trailing:(NSView **)trailingOut
{
    OMDWin11SplitView *splitView = [[OMDWin11SplitView alloc] initWithFrame:NSMakeRect(0, 0, 1036, 760)];
    [splitView setVertical:YES];
    NSView *leading = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 297.5, 760)] autorelease];
    NSView *trailing = [[[NSView alloc] initWithFrame:NSMakeRect(300.5, 0, 735.5, 760)] autorelease];
    [splitView addSubview:leading];
    [splitView addSubview:trailing];
    *leadingOut = leading;
    *trailingOut = trailing;
    return splitView;
}

static BOOL OMDTestRectIsIntegral(NSRect rect)
{
    return NSEqualRects(rect, NSIntegralRect(rect));
}

// Fractional subview edges made the preview redraw over the overlay
// scroller while it was dragged.
- (void)testAdjustSubviewsPutsEdgesOnWholePixels
{
    NSView *leading = nil;
    NSView *trailing = nil;
    OMDWin11SplitView *splitView = [self newSplitViewWithLeading:&leading trailing:&trailing];

    [splitView setFrameSize:NSMakeSize(1037, 760)];
    [splitView adjustSubviews];

    XCTAssertTrue(OMDTestRectIsIntegral([leading frame]));
    XCTAssertTrue(OMDTestRectIsIntegral([trailing frame]));
    XCTAssertEqualWithAccuracy(NSMinX([trailing frame]),
                               NSMaxX([leading frame]) + [splitView dividerThickness], 0.001);
    XCTAssertEqualWithAccuracy(NSMaxX([trailing frame]), 1037.0, 0.001);
    [splitView release];
}

- (void)testSetPositionRoundsTheDivider
{
    NSView *leading = nil;
    NSView *trailing = nil;
    OMDWin11SplitView *splitView = [self newSplitViewWithLeading:&leading trailing:&trailing];

    [splitView setPosition:250.4 ofDividerAtIndex:0];

    XCTAssertTrue(OMDTestRectIsIntegral([leading frame]));
    XCTAssertTrue(OMDTestRectIsIntegral([trailing frame]));
    XCTAssertEqualWithAccuracy(NSMaxX([trailing frame]), 1036.0, 0.001);
    [splitView release];
}

// The position is where the divider starts, as in Cocoa (libs-gui centres
// the divider on it): a split ratio read back from the leading width must
// give that width again, or it shrinks each time it's applied.
- (void)testSetPositionIsTheLeadingSubviewsWidth
{
    NSView *leading = nil;
    NSView *trailing = nil;
    OMDWin11SplitView *splitView = [self newSplitViewWithLeading:&leading trailing:&trailing];
    NSUInteger i = 0;

    for (i = 0; i < 5; i++) {
        [splitView setPosition:NSWidth([leading frame]) ofDividerAtIndex:0];
    }
    [splitView setPosition:647.0 ofDividerAtIndex:0];

    XCTAssertEqualWithAccuracy(NSWidth([leading frame]), 647.0, 0.001);
    XCTAssertEqualWithAccuracy(NSMinX([trailing frame]), 647.0 + [splitView dividerThickness], 0.001);
    XCTAssertEqualWithAccuracy(NSMaxX([trailing frame]), 1036.0, 0.001);
    [splitView release];
}

// The collapsed explorer: the document takes the whole width from x = 0.
- (void)testHiddenSubviewTakesNoRoom
{
    NSView *leading = nil;
    NSView *trailing = nil;
    OMDWin11SplitView *splitView = [self newSplitViewWithLeading:&leading trailing:&trailing];

    [leading setHidden:YES];
    [splitView adjustSubviews];

    XCTAssertTrue(NSEqualRects([trailing frame], NSMakeRect(0, 0, 1036, 760)));
    [splitView release];
}

// Early in setup the window can be too narrow for the explorer: both panes
// end up 0 wide, and libs-gui's proportional pass divided by their total,
// giving NaN frames (the AppImage smoke launch died on them).
- (void)testAdjustSubviewsWithNoWidthGivesFiniteFrames
{
    OMDWin11SplitView *splitView = [[OMDWin11SplitView alloc] initWithFrame:NSMakeRect(0, 0, 2, 760)];
    [splitView setVertical:YES];
    NSView *leading = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 760)] autorelease];
    NSView *trailing = [[[NSView alloc] initWithFrame:NSMakeRect(3, 0, 0, 760)] autorelease];
    [splitView addSubview:leading];
    [splitView addSubview:trailing];

    [leading setHidden:YES];
    [splitView adjustSubviews];
    [splitView setFrameSize:NSMakeSize(1036, 760)];
    [splitView adjustSubviews];

    XCTAssertTrue(isfinite(NSMinX([trailing frame])) && isfinite(NSWidth([trailing frame])));
    XCTAssertTrue(isfinite(NSWidth([leading frame])));
    XCTAssertTrue(NSEqualRects([trailing frame], NSMakeRect(0, 0, 1036, 760)));
    [splitView release];
}

@end
