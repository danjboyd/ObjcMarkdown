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
@class OMDOpenLocationController;
@class OMDRemoteDocument;
@class OMDRemoteDocumentBar;
@class OMDPreferencesController;
@class OMDToolbarController;
@class OMDStatusBarController;
@class OMDCopyButtonsController;
@class OMDRenderScheduler;
@class OMDOutlineController;

// GNUstep names the menu validation protocol NSMenuValidation; macOS 10.14
// renamed it NSMenuItemValidation.
#if defined(GNUSTEP)
#define OMDMenuItemValidation NSMenuValidation
#else
#define OMDMenuItemValidation NSMenuItemValidation
#endif

@interface OMDAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate, OMDMenuItemValidation, NSSplitViewDelegate, NSControlTextEditingDelegate, OMDSourceTextViewVimEventHandling>
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
    // File > Open Location... and the document opened from the web, if the
    // current one is, with the line shown above it.
    OMDOpenLocationController *_openLocationController;
    OMDRemoteDocument *_currentRemoteDocument;
    OMDRemoteDocumentBar *_remoteDocumentBar;
    OMDPreferencesController *_preferencesController;
    OMDToolbarController *_toolbarController;
    OMDStatusBarController *_statusBarController;
    OMDCopyButtonsController *_copyButtonsController;
    OMDRenderScheduler *_renderScheduler;
    id _updaterController;
    NSMenu *_fileOpenRecentMenu;
    BOOL _explorerSidebarVisible;
    BOOL _outlineVisible;
    OMDOutlineController *_outlineController;
    // Heading anchor to scroll to once a newly opened document has rendered.
    NSString *_pendingLinkFragment;
    CGFloat _explorerSidebarLastVisibleWidth;
    CGFloat _zoomScale;
    NSTimer *_previewStatusUpdatingDelayTimer;
    NSTimer *_previewStatusAutoHideTimer;
    NSTimer *_linkedScrollDriverResetTimer;
    NSTimer *_sourceSyntaxHighlightTimer;
    NSTimer *_recoveryAutosaveTimer;
    NSTimer *_externalFileMonitorTimer;
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
    BOOL _sourceIsDirty;
    BOOL _sourceVimForceClose;
    NSUInteger _sourceRevision;
    NSUInteger _lastRenderedSourceRevision;
    NSTimeInterval _lastZoomSliderEventTime;
    CGFloat _lastRenderedLayoutWidth;
    NSInteger _activeLinkedScrollDriver;
    NSString *_sourceVimCommandLine;
    BOOL _externalReloadPromptVisible;
    BOOL _observingSystemAppearance;
}

@end
