// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDViewerModeState.h"

#include <math.h>

OMDViewerPaneLayout OMDViewerPaneLayoutForMode(OMDViewerMode mode)
{
    OMDViewerPaneLayout layout;
    switch (mode) {
        case OMDViewerModeEdit:
            layout.previewVisible = NO;
            layout.sourceVisible = YES;
            layout.splitVisible = NO;
            break;
        case OMDViewerModeSplit:
            layout.previewVisible = YES;
            layout.sourceVisible = YES;
            layout.splitVisible = YES;
            break;
        case OMDViewerModeRead:
        default:
            layout.previewVisible = YES;
            layout.sourceVisible = NO;
            layout.splitVisible = NO;
            break;
    }
    return layout;
}

NSString *OMDPreviewStatusTextForState(OMDViewerMode mode,
                                       BOOL previewUpdating,
                                       NSUInteger sourceRevision,
                                       NSUInteger renderedRevision)
{
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode(mode);
    if (!layout.previewVisible) {
        return @"Preview Hidden";
    }
    if (previewUpdating) {
        return @"Preview Updating";
    }
    if (mode == OMDViewerModeSplit && sourceRevision > renderedRevision) {
        return @"Preview Stale";
    }
    return @"Preview Live";
}

BOOL OMDPreviewRenderIsCurrent(BOOL stale,
                               NSUInteger renderedRevision, NSUInteger revision,
                               CGFloat renderedWidth, CGFloat width,
                               CGFloat renderedZoom, CGFloat zoom)
{
    return !stale &&
           renderedRevision == revision &&
           renderedWidth >= 0.0 && fabs(renderedWidth - width) < 0.5 &&
           fabs(renderedZoom - zoom) < 0.0001;
}
