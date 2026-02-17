// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OMDViewerMode) {
    OMDViewerModeRead = 0,
    OMDViewerModeEdit = 1,
    OMDViewerModeSplit = 2
};

typedef struct {
    BOOL previewVisible;
    BOOL sourceVisible;
    BOOL splitVisible;
} OMDViewerPaneLayout;

FOUNDATION_EXPORT OMDViewerPaneLayout OMDViewerPaneLayoutForMode(OMDViewerMode mode);
FOUNDATION_EXPORT NSString *OMDPreviewStatusTextForState(OMDViewerMode mode,
                                                         BOOL previewUpdating,
                                                         NSUInteger sourceRevision,
                                                         NSUInteger renderedRevision);

