// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>

#import "OMDWindowTabbing.h"

#if defined(GNUSTEP)

// What OMDWindowIsOpen() asks of a window, without a display.
@interface OMDStubWindow : NSObject
{
@public
    BOOL _visible;
    BOOL _miniaturized;
    NSArray *_tabs;
}
- (BOOL)isVisible;
- (BOOL)isMiniaturized;
- (NSArray *)tabbedWindows;
@end

@implementation OMDStubWindow
- (BOOL)isVisible { return _visible; }
- (BOOL)isMiniaturized { return _miniaturized; }
- (NSArray *)tabbedWindows { return _tabs; }
@end

// No tabbing API: GNUstep without a theme that adds it.
@interface OMDStubPlainWindow : NSObject
- (BOOL)isVisible;
- (BOOL)isMiniaturized;
@end

@implementation OMDStubPlainWindow
- (BOOL)isVisible { return NO; }
- (BOOL)isMiniaturized { return NO; }
@end

@interface OMDWindowTabbingTests : XCTestCase
@end

@implementation OMDWindowTabbingTests

- (void)testAWindowOnScreenOrMinimizedIsOpen
{
    OMDStubWindow *window = [[[OMDStubWindow alloc] init] autorelease];
    window->_visible = YES;
    XCTAssertTrue(OMDWindowIsOpen(window));
    window->_visible = NO;
    window->_miniaturized = YES;
    XCTAssertTrue(OMDWindowIsOpen(window));
}

// A tab behind the selected one isn't visible, but its documents are open.
- (void)testATabBehindAnotherIsOpen
{
    OMDStubWindow *window = [[[OMDStubWindow alloc] init] autorelease];
    OMDStubWindow *other = [[[OMDStubWindow alloc] init] autorelease];
    window->_tabs = [NSArray arrayWithObjects:window, other, nil];
    XCTAssertTrue(OMDWindowIsOpen(window));
}

// The first window's controller outlives its window: closed, that window
// has left its group, and opening its document again must not show it (#323).
- (void)testAClosedWindowIsNotOpen
{
    OMDStubWindow *window = [[[OMDStubWindow alloc] init] autorelease];
    XCTAssertFalse(OMDWindowIsOpen(window));
    window->_tabs = [NSArray arrayWithObject:window];
    XCTAssertFalse(OMDWindowIsOpen(window));
    XCTAssertFalse(OMDWindowIsOpen([[[OMDStubPlainWindow alloc] init] autorelease]));
}

@end

#endif
