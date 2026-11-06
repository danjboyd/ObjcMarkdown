// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

@class OMMarkdownParsingOptions;

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
// switch needn't render or lay it out again (#346). Everything a render reads
// is in the key: the source revision, the layout width, the zoom, the parsing
// options and the theme. Stale covers what the key can't see: a render that
// was asked for, or an artifact that arrived, while the preview was hidden.
extern BOOL OMDPreviewRenderIsCurrent(BOOL stale,
                                      NSUInteger renderedRevision, NSUInteger revision,
                                      CGFloat renderedWidth, CGFloat width,
                                      CGFloat renderedZoom, CGFloat zoom,
                                      OMMarkdownParsingOptions *renderedOptions,
                                      OMMarkdownParsingOptions *options,
                                      id renderedTheme, id theme);
// Whether two sets of parsing options would render the same document alike.
extern BOOL OMDParsingOptionsEquivalent(OMMarkdownParsingOptions *a, OMMarkdownParsingOptions *b);
