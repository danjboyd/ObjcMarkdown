// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDWin11SplitView.h"

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

@end
