// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDMenuButtonDetection.h"

#if defined(GNUSTEP)
@interface OMDMenuButtonDetectionTests : XCTestCase
@end

@implementation OMDMenuButtonDetectionTests

- (NSView *)frameViewWithMenuViewOfHeight:(CGFloat)height horizontal:(BOOL)horizontal
{
    NSView *frameView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)] autorelease];
    NSMenuView *menuView = [[[NSMenuView alloc] initWithFrame:NSZeroRect] autorelease];
    [menuView setHorizontal:horizontal];
    [frameView addSubview:menuView];
    [menuView setFrame:NSMakeRect(0, 280, 400, height)];
    return frameView;
}

- (void)testNoMenuViewIsNotAButton
{
    NSView *frameView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)] autorelease];
    XCTAssertFalse(OMDFrameViewShowsMenuButton(frameView));
    XCTAssertFalse(OMDFrameViewShowsMenuButton(nil));
}

- (void)testBarOfTitlesIsNotAButton
{
    XCTAssertFalse(OMDFrameViewShowsMenuButton([self frameViewWithMenuViewOfHeight:20.0 horizontal:YES]));
}

- (void)testVerticalMenuIsNotAButton
{
    XCTAssertFalse(OMDFrameViewShowsMenuButton([self frameViewWithMenuViewOfHeight:0.0 horizontal:NO]));
}

- (void)testMenuViewWithNoHeightIsAButton
{
    XCTAssertTrue(OMDFrameViewShowsMenuButton([self frameViewWithMenuViewOfHeight:0.0 horizontal:YES]));
}

- (void)testMenuViewHoldingAControlIsAButton
{
    NSView *frameView = [self frameViewWithMenuViewOfHeight:20.0 horizontal:YES];
    NSView *menuView = [[frameView subviews] objectAtIndex:0];
    [menuView addSubview:[[[NSView alloc] initWithFrame:[menuView bounds]] autorelease]];
    XCTAssertTrue(OMDFrameViewShowsMenuButton(frameView));
}

@end
#endif
