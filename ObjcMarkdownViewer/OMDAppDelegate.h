// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@class OMMarkdownRenderer;
@class OMDDocumentConverter;
@class OMDLineNumberRulerView;
@class OMDFormattingBarView;

@interface OMDAppDelegate : NSObject <NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate, NSTextViewDelegate, NSMenuValidation, NSSplitViewDelegate>
{
    NSWindow *_window;
    NSView *_documentContainer;
    NSSplitView *_splitView;
    NSScrollView *_previewScrollView;
    NSScrollView *_sourceScrollView;
    NSView *_sourceEditorContainer;
    OMDFormattingBarView *_formattingBarView;
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
    NSTimer *_previewStatusUpdatingDelayTimer;
    NSTimer *_previewStatusAutoHideTimer;
    NSTimer *_sourceSyntaxHighlightTimer;
    NSTimer *_recoveryAutosaveTimer;
    NSTimer *_copyFeedbackTimer;
    NSMutableArray *_codeBlockButtons;
    NSButton *_copyFeedbackButton;
    NSView *_copyFeedbackHUDView;
    BOOL _isSecondaryWindow;
    OMDDocumentConverter *_documentConverter;
    NSView *_modeContainer;
    NSSegmentedControl *_modeControl;
    NSTextField *_modeLabel;
    NSTextField *_previewStatusLabel;
    NSMenuItem *_viewShowFormattingBarMenuItem;
    NSPopUpButton *_formatHeadingPopup;
    NSMutableDictionary *_formatCommandButtons;
    NSPanel *_preferencesPanel;
    NSPopUpButton *_preferencesMathPolicyPopup;
    NSPopUpButton *_preferencesSplitSyncModePopup;
    NSButton *_preferencesAllowRemoteImagesButton;
    NSButton *_preferencesWordSelectionShimButton;
    NSButton *_preferencesSyntaxHighlightingButton;
    NSButton *_preferencesSourceHighContrastButton;
    NSColorWell *_preferencesSourceAccentColorWell;
    NSButton *_preferencesSourceAccentResetButton;
    NSButton *_preferencesRendererSyntaxHighlightingButton;
    NSTextField *_preferencesRendererSyntaxHighlightingNoteLabel;
    NSInteger _viewerMode;
    CGFloat _splitRatio;
    BOOL _isProgrammaticSourceUpdate;
    BOOL _isProgrammaticSourceHighlightUpdate;
    BOOL _isProgrammaticSelectionSync;
    BOOL _isProgrammaticPreviewUpdate;
    BOOL _isProgrammaticScrollSync;
    BOOL _previewStatusUpdatingVisible;
    BOOL _previewStatusShowsUpdated;
    BOOL _previewIsUpdating;
    BOOL _sourceHighlightNeedsFullPass;
    BOOL _showFormattingBar;
    BOOL _zoomUsesDebouncedRendering;
    BOOL _sourceIsDirty;
    NSUInteger _sourceRevision;
    NSUInteger _lastRenderedSourceRevision;
    NSUInteger _zoomFastRenderStreak;
    NSTimeInterval _lastZoomSliderEventTime;
    CGFloat _lastRenderedLayoutWidth;
}

@end
