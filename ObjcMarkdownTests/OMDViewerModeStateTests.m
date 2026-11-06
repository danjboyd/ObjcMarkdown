// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDViewerModeState.h"

@interface OMDViewerModeStateTests : XCTestCase
@end

@implementation OMDViewerModeStateTests

- (void)testPaneLayoutForReadMode
{
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode(OMDViewerModeRead);
    XCTAssertTrue(layout.previewVisible);
    XCTAssertFalse(layout.sourceVisible);
    XCTAssertFalse(layout.splitVisible);
}

- (void)testPaneLayoutForEditMode
{
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode(OMDViewerModeEdit);
    XCTAssertFalse(layout.previewVisible);
    XCTAssertTrue(layout.sourceVisible);
    XCTAssertFalse(layout.splitVisible);
}

- (void)testPaneLayoutForSplitMode
{
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode(OMDViewerModeSplit);
    XCTAssertTrue(layout.previewVisible);
    XCTAssertTrue(layout.sourceVisible);
    XCTAssertTrue(layout.splitVisible);
}

- (void)testPreviewStatusTextForHiddenAndUpdatingAndStale
{
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeEdit, NO, 0, 0) isEqualToString:@"Preview Hidden"]);
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeRead, YES, 0, 0) isEqualToString:@"Preview Updating"]);
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeSplit, NO, 8, 7) isEqualToString:@"Preview Stale"]);
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeSplit, NO, 8, 8) isEqualToString:@"Preview Live"]);
}

- (void)testPreviewRenderIsCurrentOnlyWhenNothingChanged
{
    XCTAssertTrue(OMDPreviewRenderIsCurrent(NO, 3, 3, 800.0, 800.0, 1.0, 1.0));
    XCTAssertTrue(OMDPreviewRenderIsCurrent(NO, 3, 3, 800.0, 800.2, 1.0, 1.0));
    XCTAssertFalse(OMDPreviewRenderIsCurrent(YES, 3, 3, 800.0, 800.0, 1.0, 1.0));
    XCTAssertFalse(OMDPreviewRenderIsCurrent(NO, 3, 4, 800.0, 800.0, 1.0, 1.0));
    XCTAssertFalse(OMDPreviewRenderIsCurrent(NO, 3, 3, 800.0, 400.0, 1.0, 1.0));
    XCTAssertFalse(OMDPreviewRenderIsCurrent(NO, 3, 3, -1.0, -1.0, 1.0, 1.0));
    XCTAssertFalse(OMDPreviewRenderIsCurrent(NO, 3, 3, 800.0, 800.0, 1.0, 1.25));
}

@end
