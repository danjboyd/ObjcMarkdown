// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDLayoutMetrics.h"

@class OMDExplorerController;

static const CGFloat OMDExplorerListDefaultFontSize = 14.0;

// What the explorer needs from the window that hosts it.
@protocol OMDExplorerControllerDelegate <NSObject>
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (void)applyScrollSpeedPreference;
- (void)openLocalPath:(NSString *)path inNewTab:(BOOL)inNewTab;
@end

// The explorer sidebar: the files of a local folder.
@interface OMDExplorerController : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
    id<OMDExplorerControllerDelegate> _delegate;
    NSView *_containerView;
    NSButton *_explorerShowHiddenFilesButton;
    NSButton *_explorerNavigateUpButton;
    NSTextField *_explorerPathLabel;
    NSScrollView *_explorerScrollView;
    NSTableView *_explorerTableView;
    NSMutableArray *_explorerEntries;
    NSString *_explorerLocalRootPath;
    NSString *_explorerLocalCurrentPath;
    NSString *_explorerDocumentPath;
    // A file's single click waits out the double-click interval (#40).
    NSDictionary *_explorerPendingClickEntry;
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
// default folder from Preferences.
- (void)setDocumentPath:(NSString *)path;

- (NSString *)explorerLocalRootPathPreference;
- (void)setExplorerLocalRootPathPreference:(NSString *)path;
- (NSUInteger)explorerMaxOpenFileSizeBytes;
- (void)setExplorerMaxOpenFileSizeMBPreference:(NSUInteger)megabytes;
- (CGFloat)explorerListFontSizePreference;
- (void)setExplorerListFontSizePreference:(CGFloat)fontSize;

@end
