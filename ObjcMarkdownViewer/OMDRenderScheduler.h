// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

@protocol OMDRenderSchedulerDelegate <NSObject>
// Whether a live render is worth scheduling: a document is open and the
// preview is showing.
- (BOOL)canRenderPreview;
- (void)setPreviewUpdating:(BOOL)updating;
- (void)renderCurrentMarkdown;
@end

// When the preview re-renders: one debounce timer each for interactive
// changes (resizing, zoom), typing, and refreshed math images, and the
// adaptive switch to debounced rendering while zooming is slow.
@interface OMDRenderScheduler : NSObject
{
    id<OMDRenderSchedulerDelegate> _delegate;
    NSTimer *_interactiveRenderTimer;
    NSTimer *_mathArtifactRenderTimer;
    NSTimer *_livePreviewRenderTimer;
    BOOL _zoomUsesDebouncedRendering;
    NSUInteger _zoomFastRenderStreak;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDRenderSchedulerDelegate>)delegate;

- (void)scheduleInteractiveRenderAfterDelay:(NSTimeInterval)delay;
- (void)cancelPendingInteractiveRender;
- (void)scheduleLivePreviewRender;
- (void)cancelPendingLivePreviewRender;
- (void)scheduleMathArtifactRefresh;
- (void)cancelPendingMathArtifactRender;

// Zoom renders switch to debounced after a slow one, and back after a
// run of fast ones.
- (BOOL)zoomUsesDebouncedRendering;
- (void)updateAdaptiveZoomDebounceWithRenderDurationMs:(NSTimeInterval)durationMs
                                     sampledAsZoomRender:(BOOL)isZoomRender;

@end
