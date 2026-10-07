// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// What the status bar shows and does for the window that hosts it.
@protocol OMDStatusBarControllerDelegate <NSObject>
- (CGFloat)previewZoomScale;
- (void)zoomSliderChanged:(id)sender;
- (void)zoomReset:(id)sender;
- (void)updatePreviewStatusIndicator;
- (void)updateZoomLabel;
@end

// The status bar along the bottom of the window, on every platform: Vim's
// mode or command line and the preview's state on the left, the zoom (a
// slider and a button showing the percentage, which resets it to 100%)
// on the right. Standard controls in the theme's fonts; the theme draws
// them.
@interface OMDStatusBarController : NSObject
{
    id<OMDStatusBarControllerDelegate> _delegate;
    NSView *_view;
    NSTextField *_statusLabel;
    NSSlider *_zoomSlider;
    NSButton *_zoomButton;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDStatusBarControllerDelegate>)delegate;

// The bar, width-sizable and pinned to the bottom of its superview, as
// tall as -height. Built on first use.
- (NSView *)viewWithWidth:(CGFloat)width;
- (CGFloat)height;

- (NSTextField *)statusLabel;
- (NSSlider *)zoomSlider;
// Shows the zoom ("135%"); pressing it resets the zoom to 100%.
- (NSButton *)zoomButton;

@end

// The width the status bar needs for its status text and zoom controls.
extern const CGFloat OMDStatusBarMinimumWidth;
