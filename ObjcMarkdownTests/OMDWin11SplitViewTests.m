// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDWin11SplitView.h"

#include <math.h>

@interface OMDWin11SplitViewTests : XCTestCase
@end

// Records, for each resize the split view reports, whether it was a drag.
@interface OMDSplitResizeRecorder : NSObject
{
@public
    NSUInteger _resizes;
    NSUInteger _drags;
}
@end

@implementation OMDSplitResizeRecorder
- (void)splitViewDidResize:(NSNotification *)notification
{
    _resizes++;
    if ([(OMDWin11SplitView *)[notification object] omdIsTrackingDivider]) {
        _drags++;
    }
}
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

// The window controller keeps the split as the user's ratio only on a drag.
// Entering Split in a new tab sized the split view from its first, narrower
// frame with the panes another mode left, and that resize was kept: the
// next Split gave the preview 15% of the width.
- (void)testLayoutResizesAreNotDividerDrags
{
    NSView *leading = nil;
    NSView *trailing = nil;
    OMDWin11SplitView *splitView = [self newSplitViewWithLeading:&leading trailing:&trailing];
    OMDSplitResizeRecorder *recorder = [[OMDSplitResizeRecorder alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:recorder
                                             selector:@selector(splitViewDidResize:)
                                                 name:NSSplitViewDidResizeSubviewsNotification
                                               object:splitView];

    [leading setFrame:NSMakeRect(0, 0, 900, 760)];
    [splitView setFrameSize:NSMakeSize(1200, 760)];
    [splitView adjustSubviews];
    [splitView setPosition:600.0 ofDividerAtIndex:0];
    [splitView setFrameSize:NSMakeSize(1200, 732)];

    XCTAssertTrue(recorder->_resizes > 0);
    XCTAssertEqual(recorder->_drags, (NSUInteger)0);
    XCTAssertFalse([splitView omdIsTrackingDivider]);
    [[NSNotificationCenter defaultCenter] removeObserver:recorder];
    [recorder release];
    [splitView release];
}

#if !defined(GNUSTEP)
// A drag of the divider (the events queued, -mouseDown: tracks them).
// Cocoa only: libs-gui's tracking loop needs a window on a display.
- (void)testDividerDragIsTracked
{
    NSView *leading = nil;
    NSView *trailing = nil;
    OMDWin11SplitView *splitView = [self newSplitViewWithLeading:&leading trailing:&trailing];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1036, 760)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setReleasedWhenClosed:NO];
    [[window contentView] addSubview:splitView];
    [splitView setPosition:500.0 ofDividerAtIndex:0];
    OMDSplitResizeRecorder *recorder = [[OMDSplitResizeRecorder alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:recorder
                                             selector:@selector(splitViewDidResize:)
                                                 name:NSSplitViewDidResizeSubviewsNotification
                                               object:splitView];

    NSPoint down = [splitView convertPoint:NSMakePoint(500.5, 380.0) toView:nil];
    NSPoint up = NSMakePoint(down.x - 100.0, down.y);
    NSEventType types[3] = { NSEventTypeLeftMouseDown, NSEventTypeLeftMouseDragged, NSEventTypeLeftMouseUp };
    NSEvent *events[3];
    NSUInteger i = 0;
    for (i = 0; i < 3; i++) {
        events[i] = [NSEvent mouseEventWithType:types[i]
                                       location:(i == 0 ? down : up)
                                  modifierFlags:0
                                      timestamp:[[NSProcessInfo processInfo] systemUptime]
                                   windowNumber:[window windowNumber]
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1.0];
    }
    [NSApp postEvent:events[1] atStart:NO];
    [NSApp postEvent:events[2] atStart:NO];
    [splitView mouseDown:events[0]];

    XCTAssertTrue(recorder->_drags > 0);
    XCTAssertTrue(NSWidth([leading frame]) < 500.0);
    XCTAssertFalse([splitView omdIsTrackingDivider]);
    [[NSNotificationCenter defaultCenter] removeObserver:recorder];
    [recorder release];
    [splitView removeFromSuperview];
    [window close];
    [window release];
    [splitView release];
}
#endif

@end
