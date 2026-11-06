// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDRenderScheduler.h"

@interface OMDRenderSchedulerTestDelegate : NSObject <OMDRenderSchedulerDelegate>
@end

@implementation OMDRenderSchedulerTestDelegate
- (BOOL)canRenderPreview { return YES; }
- (void)setPreviewUpdating:(BOOL)updating { (void)updating; }
- (void)renderCurrentMarkdown {}
@end

@interface OMDRenderSchedulerTests : XCTestCase
@end

@implementation OMDRenderSchedulerTests

// A mode switch drops pending renders, so it has to be able to tell there were
// some: the preview they were for must not count as up to date (#346).
- (void)testPendingRendersAreVisibleUntilCancelled
{
    OMDRenderSchedulerTestDelegate *delegate = [[[OMDRenderSchedulerTestDelegate alloc] init] autorelease];
    OMDRenderScheduler *scheduler = [[[OMDRenderScheduler alloc] initWithDelegate:delegate] autorelease];
    XCTAssertFalse([scheduler hasPendingRender]);

    [scheduler scheduleInteractiveRenderAfterDelay:60.0];
    XCTAssertTrue([scheduler hasPendingRender]);
    [scheduler cancelPendingInteractiveRender];
    XCTAssertFalse([scheduler hasPendingRender]);

    [scheduler scheduleLivePreviewRender];
    XCTAssertTrue([scheduler hasPendingRender]);
    [scheduler cancelPendingLivePreviewRender];
    XCTAssertFalse([scheduler hasPendingRender]);

    [scheduler scheduleMathArtifactRefresh];
    XCTAssertTrue([scheduler hasPendingRender]);
    [scheduler cancelPendingMathArtifactRender];
    XCTAssertFalse([scheduler hasPendingRender]);
}

@end
