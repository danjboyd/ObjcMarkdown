// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// What the toolbar shows and does for the window that hosts it.
@protocol OMDToolbarControllerDelegate <NSObject>
- (BOOL)hasLoadedDocument;
- (BOOL)canSaveCurrentDocument;
- (BOOL)isExplorerSidebarVisible;
- (CGFloat)previewZoomScale;
- (NSColor *)modeLabelTextColor;
- (void)updateModeControlSelection;
- (void)updatePreviewStatusIndicator;
- (void)updateZoomLabel;
- (void)toggleExplorerSidebar:(id)sender;
- (void)openDocument:(id)sender;
- (void)saveDocument:(id)sender;
- (void)exportDocumentAsPDF:(id)sender;
- (void)printDocument:(id)sender;
- (void)showPreferences:(id)sender;
@end

// The window's toolbar: in the GNOME header bar the explorer, open and
// save buttons and the Read/Edit/Split switcher; on Windows the action
// groups, the switcher and the zoom controls. The controls' actions go to
// the delegate, which also validates the toolbar items.
@interface OMDToolbarController : NSObject <NSToolbarDelegate>
{
    id<OMDToolbarControllerDelegate> _delegate;
    NSView *_toolbarPrimaryActionsContainer;
    NSView *_toolbarActionGlyphOverlay;
    NSSegmentedControl *_toolbarFileActionsControl;
    NSSegmentedControl *_toolbarUtilityActionsControl;
    NSSlider *_zoomSlider;
    NSTextField *_zoomLabel;
    NSButton *_zoomResetButton;
    NSView *_zoomContainer;
    NSView *_modeContainer;
    NSSegmentedControl *_modeControl;
    NSTextField *_modeLabel;
    NSTextField *_previewStatusLabel;
    BOOL _lastToolbarHadDocument;
    BOOL _lastToolbarCanSaveDocument;
    BOOL _lastToolbarExplorerSidebarVisible;
    BOOL _hasLastToolbarActionState;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDToolbarControllerDelegate>)delegate;

- (void)installInWindow:(NSWindow *)window;
// Refreshes the action buttons' enabled state, icons and tooltips.
- (void)updateToolbarActionControlsState;

// The switcher and status views, nil until the toolbar builds them.
- (NSSegmentedControl *)modeControl;
- (NSTextField *)modeLabel;
- (NSTextField *)previewStatusLabel;
- (NSSlider *)zoomSlider;
- (NSTextField *)zoomLabel;

@end
