// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDRenderResult;

@protocol OMDCopyButtonsControllerDelegate <NSObject>
- (NSTextView *)previewTextView;
// What the preview shows came from: its code blocks, diagrams and zoom.
- (OMDRenderResult *)previewRenderResult;
// Called once the new render is laid out, before the buttons are placed.
- (void)previewDidLayoutForCopyButtons;
@end

// The copy buttons over the preview's code blocks, diagrams and display
// equations, and the "Copied" feedback after one is pressed.
@interface OMDCopyButtonsController : NSObject
{
    id<OMDCopyButtonsControllerDelegate> _delegate;
    NSTimer *_copyFeedbackTimer;
    NSMutableArray *_codeBlockButtons;
    // Every block that has a copy button, and the buttons made so far for
    // the blocks near the visible rect, by slot index (#346).
    NSMutableArray *_copySlots;
    NSMutableDictionary *_buttonsBySlot;
    NSView *_observedClipView;
    NSButton *_copyFeedbackButton;
    NSView *_copyFeedbackHUDView;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDCopyButtonsControllerDelegate>)delegate;

// Places buttons for the current render (after refreshing the delegate).
- (void)updateCodeBlockButtons;
// Makes buttons for the blocks in or near the visible rect and drops the
// others; called on scroll. Returns the number of buttons shown.
- (NSUInteger)updateVisibleCopyButtons;
- (void)removeCopyButtons;
- (void)hideCopyFeedback;

@end
