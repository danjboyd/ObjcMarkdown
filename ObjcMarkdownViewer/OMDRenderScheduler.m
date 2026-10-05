// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRenderScheduler.h"

static const NSTimeInterval OMDZoomAdaptiveSlowRenderThresholdMs = 85.0;
static const NSTimeInterval OMDZoomAdaptiveFastRenderThresholdMs = 42.0;
static const NSUInteger OMDZoomAdaptiveFastRenderStreakRequired = 4;
static const NSTimeInterval OMDMathArtifactRefreshDebounceInterval = 0.10;
static const NSTimeInterval OMDLivePreviewDebounceInterval = 0.12;

@interface OMDRenderScheduler ()
- (void)interactiveRenderTimerFired:(NSTimer *)timer;
- (void)livePreviewRenderTimerFired:(NSTimer *)timer;
- (void)mathArtifactRenderTimerFired:(NSTimer *)timer;
@end

@implementation OMDRenderScheduler

- (instancetype)initWithDelegate:(id<OMDRenderSchedulerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        _zoomUsesDebouncedRendering = NO;
        _zoomFastRenderStreak = 0;
    }
    return self;
}

- (void)dealloc
{
    [self cancelPendingInteractiveRender];
    [self cancelPendingLivePreviewRender];
    [self cancelPendingMathArtifactRender];
    [super dealloc];
}

- (BOOL)zoomUsesDebouncedRendering
{
    return _zoomUsesDebouncedRendering;
}

- (void)updateAdaptiveZoomDebounceWithRenderDurationMs:(NSTimeInterval)durationMs
                                     sampledAsZoomRender:(BOOL)isZoomRender
{
    if (!isZoomRender) {
        _zoomFastRenderStreak = 0;
        return;
    }

    if (durationMs >= OMDZoomAdaptiveSlowRenderThresholdMs) {
        _zoomUsesDebouncedRendering = YES;
        _zoomFastRenderStreak = 0;
        return;
    }

    if (!_zoomUsesDebouncedRendering) {
        return;
    }

    if (durationMs <= OMDZoomAdaptiveFastRenderThresholdMs) {
        _zoomFastRenderStreak += 1;
        if (_zoomFastRenderStreak >= OMDZoomAdaptiveFastRenderStreakRequired) {
            _zoomUsesDebouncedRendering = NO;
            _zoomFastRenderStreak = 0;
        }
        return;
    }

    _zoomFastRenderStreak = 0;
}

- (void)scheduleInteractiveRenderAfterDelay:(NSTimeInterval)delay
{
    if (delay < 0.01) {
        delay = 0.01;
    }

    if (_interactiveRenderTimer != nil) {
        [_interactiveRenderTimer invalidate];
        [_interactiveRenderTimer release];
        _interactiveRenderTimer = nil;
    }

    _interactiveRenderTimer = [[NSTimer scheduledTimerWithTimeInterval:delay
                                                                 target:self
                                                               selector:@selector(interactiveRenderTimerFired:)
                                                               userInfo:nil
                                                                repeats:NO] retain];
    [_delegate setPreviewUpdating:YES];
}

- (void)interactiveRenderTimerFired:(NSTimer *)timer
{
    if (timer != _interactiveRenderTimer) {
        return;
    }
    [_interactiveRenderTimer invalidate];
    [_interactiveRenderTimer release];
    _interactiveRenderTimer = nil;
    [_delegate renderCurrentMarkdown];
}

- (void)cancelPendingInteractiveRender
{
    if (_interactiveRenderTimer != nil) {
        [_interactiveRenderTimer invalidate];
        [_interactiveRenderTimer release];
        _interactiveRenderTimer = nil;
    }
}

- (void)scheduleMathArtifactRefresh
{
    if (_mathArtifactRenderTimer != nil) {
        [_mathArtifactRenderTimer invalidate];
        [_mathArtifactRenderTimer release];
        _mathArtifactRenderTimer = nil;
    }
    _mathArtifactRenderTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDMathArtifactRefreshDebounceInterval
                                                                  target:self
                                                                selector:@selector(mathArtifactRenderTimerFired:)
                                                                userInfo:nil
                                                                 repeats:NO] retain];
    [_delegate setPreviewUpdating:YES];
}

- (void)mathArtifactRenderTimerFired:(NSTimer *)timer
{
    if (timer != _mathArtifactRenderTimer) {
        return;
    }
    [_mathArtifactRenderTimer invalidate];
    [_mathArtifactRenderTimer release];
    _mathArtifactRenderTimer = nil;
    [_delegate renderCurrentMarkdown];
}

- (void)cancelPendingMathArtifactRender
{
    if (_mathArtifactRenderTimer != nil) {
        [_mathArtifactRenderTimer invalidate];
        [_mathArtifactRenderTimer release];
        _mathArtifactRenderTimer = nil;
    }
}

- (void)scheduleLivePreviewRender
{
    if (![_delegate canRenderPreview]) {
        [_delegate setPreviewUpdating:NO];
        return;
    }

    if (_livePreviewRenderTimer != nil) {
        [_livePreviewRenderTimer invalidate];
        [_livePreviewRenderTimer release];
        _livePreviewRenderTimer = nil;
    }
    _livePreviewRenderTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDLivePreviewDebounceInterval
                                                                 target:self
                                                               selector:@selector(livePreviewRenderTimerFired:)
                                                               userInfo:nil
                                                                repeats:NO] retain];
    [_delegate setPreviewUpdating:YES];
}

- (void)livePreviewRenderTimerFired:(NSTimer *)timer
{
    if (timer != _livePreviewRenderTimer) {
        return;
    }
    [_livePreviewRenderTimer invalidate];
    [_livePreviewRenderTimer release];
    _livePreviewRenderTimer = nil;
    [_delegate renderCurrentMarkdown];
}

- (void)cancelPendingLivePreviewRender
{
    if (_livePreviewRenderTimer != nil) {
        [_livePreviewRenderTimer invalidate];
        [_livePreviewRenderTimer release];
        _livePreviewRenderTimer = nil;
    }
}

@end
