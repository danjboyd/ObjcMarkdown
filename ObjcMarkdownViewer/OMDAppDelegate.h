// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#include <sys/types.h>
#if defined(_WIN32) && !defined(_MODE_T_)
#define _MODE_T_
typedef unsigned short mode_t;
#endif
#import <AppKit/AppKit.h>
#import "OMDSourceTextView.h"

@class OMMarkdownRenderer;
@class OMDDocumentConverter;
@class OMDLineNumberRulerView;
@class OMDFormattingBarController;
@class GSVVimBindingController;
@class OMDDocumentTabsController;
@class OMDExplorerController;
@class OMDPreferencesController;
@class OMDOutlineController;

@interface OMDAppDelegate : NSObject <NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate, NSTextViewDelegate, NSMenuValidation, NSSplitViewDelegate, NSControlTextEditingDelegate, OMDSourceTextViewVimEventHandling>
{
    NSWindow *_window;
    NSSplitView *_workspaceSplitView;
    NSView *_workspaceMainContainer;
    NSView *_sidebarContainer;
    NSView *_documentContainer;
    NSSplitView *_splitView;
    NSScrollView *_previewScrollView;
    NSView *_previewCanvasView;
    NSScrollView *_sourceScrollView;
    NSView *_sourceEditorContainer;
    OMDFormattingBarController *_formattingBarController;
    NSTextView *_textView;
    NSTextView *_sourceTextView;
    OMDLineNumberRulerView *_sourceLineNumberRuler;
    OMMarkdownRenderer *_renderer;
    BOOL _openedFileOnLaunch;
    NSString *_currentMarkdown;
    NSString *_currentPath;
    NSString *_currentDisplayTitle;
    NSString *_currentLoadedDiskFingerprint;
    NSString *_currentObservedDiskFingerprint;
    NSString *_currentSuppressedDiskFingerprint;
    NSInteger _currentDocumentRenderMode;
    NSString *_currentDocumentSyntaxLanguage;
    BOOL _currentDocumentReadOnly;
    OMDDocumentTabsController *_documentTabsController;
    OMDExplorerController *_explorerController;
    OMDPreferencesController *_preferencesController;
    id _updaterController;
    NSMenu *_fileOpenRecentMenu;
    NSMenuItem *_viewShowExplorerMenuItem;
    NSMenuItem *_viewShowOutlineMenuItem;
    BOOL _explorerSidebarVisible;
    BOOL _outlineVisible;
    OMDOutlineController *_outlineController;
    // Heading anchor to scroll to once a newly opened document has rendered.
    NSString *_pendingLinkFragment;
    CGFloat _explorerSidebarLastVisibleWidth;
    NSView *_toolbarPrimaryActionsContainer;
    NSView *_toolbarActionGlyphOverlay;
    NSSegmentedControl *_toolbarFileActionsControl;
    NSSegmentedControl *_toolbarUtilityActionsControl;
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
    NSTimer *_linkedScrollDriverResetTimer;
    NSTimer *_sourceSyntaxHighlightTimer;
    NSTimer *_recoveryAutosaveTimer;
    NSTimer *_externalFileMonitorTimer;
    NSTimer *_copyFeedbackTimer;
    NSMutableArray *_codeBlockButtons;
    NSButton *_copyFeedbackButton;
    NSView *_copyFeedbackHUDView;
    NSView *_launchOverlayView;
    NSTextField *_launchOverlayTitleLabel;
    NSTextField *_launchOverlayDetailLabel;
    NSString *_pendingLaunchOpenPath;
    BOOL _launchWorkScheduled;
    BOOL _postPresentationSetupScheduled;
    BOOL _postPresentationSetupComplete;
    BOOL _isSecondaryWindow;
    OMDDocumentConverter *_documentConverter;
    GSVVimBindingController *_sourceVimBindingController;
    NSView *_modeContainer;
    NSSegmentedControl *_modeControl;
    NSTextField *_modeLabel;
    NSTextField *_previewStatusLabel;
    NSMenuItem *_viewShowFormattingBarMenuItem;
    NSInteger _viewerMode;
    CGFloat _splitRatio;
    CGFloat _lastObservedSplitAvailableWidth;
    BOOL _isProgrammaticSourceUpdate;
    BOOL _isProgrammaticSourceHighlightUpdate;
    BOOL _isProgrammaticSelectionSync;
    BOOL _isProgrammaticPreviewUpdate;
    BOOL _isProgrammaticScrollSync;
    BOOL _isApplyingSplitViewRatio;
    BOOL _previewStatusUpdatingVisible;
    BOOL _previewStatusShowsUpdated;
    BOOL _previewIsUpdating;
    BOOL _sourceHighlightNeedsFullPass;
    BOOL _showFormattingBar;
    BOOL _zoomUsesDebouncedRendering;
    BOOL _sourceIsDirty;
    BOOL _sourceVimForceClose;
    BOOL _lastToolbarHadDocument;
    BOOL _lastToolbarCanSaveDocument;
    BOOL _lastToolbarExplorerSidebarVisible;
    BOOL _hasLastToolbarActionState;
    NSUInteger _sourceRevision;
    NSUInteger _lastRenderedSourceRevision;
    NSUInteger _zoomFastRenderStreak;
    NSTimeInterval _lastZoomSliderEventTime;
    CGFloat _lastRenderedLayoutWidth;
    NSInteger _activeLinkedScrollDriver;
    NSString *_sourceVimCommandLine;
    BOOL _externalReloadPromptVisible;
}

@end
