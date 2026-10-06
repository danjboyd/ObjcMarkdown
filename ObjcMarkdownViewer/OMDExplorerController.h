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
    NSTextField *_explorerLocalRootLabel;
    NSButton *_explorerShowHiddenFilesButton;
    NSButton *_explorerNavigateUpButton;
    NSTextField *_explorerPathLabel;
    NSScrollView *_explorerScrollView;
    NSTableView *_explorerTableView;
    NSMutableArray *_explorerEntries;
    NSString *_explorerLocalRootPath;
    NSString *_explorerLocalCurrentPath;
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

- (NSString *)explorerLocalRootPathPreference;
- (void)setExplorerLocalRootPathPreference:(NSString *)path;
- (NSUInteger)explorerMaxOpenFileSizeBytes;
- (void)setExplorerMaxOpenFileSizeMBPreference:(NSUInteger)megabytes;
- (CGFloat)explorerListFontSizePreference;
- (void)setExplorerListFontSizePreference:(CGFloat)fontSize;

@end
