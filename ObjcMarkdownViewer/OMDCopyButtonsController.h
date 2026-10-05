// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMMarkdownRenderer;

@protocol OMDCopyButtonsControllerDelegate <NSObject>
- (NSTextView *)previewTextView;
- (OMMarkdownRenderer *)previewRenderer;
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
    NSButton *_copyFeedbackButton;
    NSView *_copyFeedbackHUDView;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDCopyButtonsControllerDelegate>)delegate;

// Places buttons for the current render (after refreshing the delegate).
- (void)updateCodeBlockButtons;
- (void)removeCopyButtons;
- (void)hideCopyFeedback;

@end
