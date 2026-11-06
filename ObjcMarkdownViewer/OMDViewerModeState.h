// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

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

extern OMDViewerPaneLayout OMDViewerPaneLayoutForMode(OMDViewerMode mode);
extern NSString *OMDPreviewStatusTextForState(OMDViewerMode mode,
                                               BOOL previewUpdating,
                                               NSUInteger sourceRevision,
                                               NSUInteger renderedRevision);

// Whether the preview already shows what a render would produce, so a mode
// switch needn't render or lay it out again (#346). Stale means a render was
// asked for while it couldn't run, as for a setting changed in Edit.
extern BOOL OMDPreviewRenderIsCurrent(BOOL stale,
                                      NSUInteger renderedRevision, NSUInteger revision,
                                      CGFloat renderedWidth, CGFloat width,
                                      CGFloat renderedZoom, CGFloat zoom);
