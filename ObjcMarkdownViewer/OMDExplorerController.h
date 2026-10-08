// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDLayoutMetrics.h"

@class OMDExplorerController;

// The file list's font size unless the user sets one: the theme's (#90).
static inline CGFloat OMDExplorerListDefaultFontSize(void)
{
    return [OMDChromeFont() pointSize];
}

// What the explorer needs from the window that hosts it.
@protocol OMDExplorerControllerDelegate <NSObject>
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (void)applyScrollSpeedPreference;
- (void)openLocalPath:(NSString *)path inNewTab:(BOOL)inNewTab;
@end

@class OMDExplorerNode;

// The explorer sidebar: a local folder's files and folders as a tree. It is
// also the outline view's data source and delegate, without declaring those
// protocols, all of whose methods GNUstep declares required.
@interface OMDExplorerController : NSObject <NSTextFieldDelegate>
{
    id<OMDExplorerControllerDelegate> _delegate;
    NSView *_containerView;
    NSPopUpButton *_explorerRootPopup;
    NSSearchField *_explorerFilterField;
    NSButton *_explorerMarkdownOnlyButton;
    NSButton *_explorerShowHiddenFilesButton;
    NSTextField *_explorerFilterStatusLabel;
    NSScrollView *_explorerScrollView;
    NSOutlineView *_explorerOutlineView;
    OMDExplorerNode *_explorerRootNode;
    NSString *_explorerLocalRootPath;
    NSString *_explorerDocumentPath;
    // Set when the user picks a root other than the document's; the
    // explorer then stays there while documents change.
    BOOL _explorerRootChosenByHand;
    // While filtering (a filter text or Markdown only), the paths shown:
    // matching files and the folders above them. nil shows everything.
    NSSet *_explorerVisiblePaths;
    // Bumped by each search, so a stale background result is dropped.
    NSUInteger _explorerFilterGeneration;
    BOOL _explorerTextFilterActive;
    // Return in the filter: open the first match once the search is done.
    BOOL _explorerOpenFirstMatchWhenShown;
    // The folders open before a filter text opened the matches' folders.
    NSArray *_explorerExpandedBeforeFilter;
    // A file's single click waits out the double-click interval (#40).
    OMDExplorerNode *_explorerPendingClickNode;
    BOOL _explorerIgnoreDoubleClick;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDExplorerControllerDelegate>)delegate;

// Builds the explorer's controls in the container (not retained).
- (void)setupInContainer:(NSView *)container;
- (NSScrollView *)scrollView;
- (void)applyLayoutDensity;
- (void)reloadExplorerEntries;

// The open document's path (nil for none or an untitled one). The explorer
// shows the document's repository or folder, keeping its place while the
// document stays under the same root; with no document it shows the
// default folder from Preferences. A root picked in the explorer's root
// menu stays until another is picked.
- (void)setDocumentPath:(NSString *)path;
// A new tab's explorer starts at its opener's root (picked by hand or not)
// instead of the default folder; its document can move it from there.
- (void)startAtRootOfExplorer:(OMDExplorerController *)opener;

// Puts the keyboard in the explorer's filter field.
- (void)focusFilterField;

- (NSString *)explorerLocalRootPathPreference;
- (void)setExplorerLocalRootPathPreference:(NSString *)path;
- (NSUInteger)explorerMaxOpenFileSizeBytes;
- (void)setExplorerMaxOpenFileSizeMBPreference:(NSUInteger)megabytes;
- (CGFloat)explorerListFontSizePreference;
- (void)setExplorerListFontSizePreference:(CGFloat)fontSize;

@end
