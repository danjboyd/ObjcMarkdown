// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@class OMMarkdownRenderer;
@class OMDDocumentConverter;
@class OMDLineNumberRulerView;

@interface OMDAppDelegate : NSObject <NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate, NSTextViewDelegate, NSMenuValidation, NSSplitViewDelegate>
{
    NSWindow *_window;
    NSView *_documentContainer;
    NSSplitView *_splitView;
    NSScrollView *_previewScrollView;
    NSScrollView *_sourceScrollView;
    NSTextView *_textView;
    NSTextView *_sourceTextView;
    OMDLineNumberRulerView *_sourceLineNumberRuler;
    OMMarkdownRenderer *_renderer;
    BOOL _openedFileOnLaunch;
    NSString *_currentMarkdown;
    NSString *_currentPath;
    NSSlider *_zoomSlider;
    NSTextField *_zoomLabel;
    NSButton *_zoomResetButton;
    NSView *_zoomContainer;
    CGFloat _zoomScale;
    NSTimer *_interactiveRenderTimer;
    NSTimer *_mathArtifactRenderTimer;
    NSTimer *_livePreviewRenderTimer;
    NSMutableArray *_codeBlockButtons;
    BOOL _isSecondaryWindow;
    OMDDocumentConverter *_documentConverter;
    NSView *_modeContainer;
    NSSegmentedControl *_modeControl;
    NSTextField *_modeLabel;
    NSInteger _viewerMode;
    CGFloat _splitRatio;
    BOOL _isProgrammaticSourceUpdate;
    BOOL _sourceIsDirty;
}

@end
