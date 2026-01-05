// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@class OMMarkdownRenderer;

@interface OMDAppDelegate : NSObject <NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate, NSTextViewDelegate>
{
    NSWindow *_window;
    NSTextView *_textView;
    OMMarkdownRenderer *_renderer;
    BOOL _openedFileOnLaunch;
    NSString *_currentMarkdown;
    NSString *_currentPath;
    NSSlider *_zoomSlider;
    NSTextField *_zoomLabel;
    NSButton *_zoomResetButton;
    NSView *_zoomContainer;
    CGFloat _zoomScale;
    NSMutableArray *_codeBlockButtons;
    BOOL _isSecondaryWindow;
}

@end
