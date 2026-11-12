// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "../third_party/libs-sharing/Source/GSSharingFileDrag.h"

@interface OMDShareDragThresholdTests : XCTestCase
@end

@implementation OMDShareDragThresholdTests

- (void)testPressAndReleaseNeverBeginDragEvenFarFromOrigin
{
    NSPoint start = NSMakePoint(20, 30);
    NSPoint distant = NSMakePoint(120, 130);
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, start, NSLeftMouseDown));
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, distant, NSLeftMouseUp));
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, distant, NSMouseMoved));
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, distant, NSRightMouseDragged));
}

- (void)testSmallJitterDoesNotBeginDrag
{
    NSPoint start = NSMakePoint(20, 30);
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, start, NSLeftMouseDragged));
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, NSMakePoint(23.99, 30), NSLeftMouseDragged));
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, NSMakePoint(22, 32), NSLeftMouseDragged));
}

- (void)testFourPointDistanceBeginsDragInEitherDirection
{
    NSPoint start = NSMakePoint(20, 30);
    XCTAssertTrue(GSSharingFileDragShouldBegin(start, NSMakePoint(24, 30), NSLeftMouseDragged));
    XCTAssertTrue(GSSharingFileDragShouldBegin(start, NSMakePoint(16, 30), NSLeftMouseDragged));
    XCTAssertTrue(GSSharingFileDragShouldBegin(start, NSMakePoint(20, 34), NSLeftMouseDragged));
    XCTAssertTrue(GSSharingFileDragShouldBegin(start, NSMakePoint(20, 26), NSLeftMouseDragged));
}

- (void)testDiagonalDistanceAndTranslatedNegativeCoordinates
{
    NSPoint start = NSMakePoint(-100, -50);
    XCTAssertTrue(GSSharingFileDragShouldBegin(start, NSMakePoint(-97, -47), NSLeftMouseDragged));
    XCTAssertFalse(GSSharingFileDragShouldBegin(start, NSMakePoint(-98, -48), NSLeftMouseDragged));
    XCTAssertTrue(GSSharingFileDragShouldBegin(start, NSMakePoint(-100, -55), NSLeftMouseDragged));
}

@end
