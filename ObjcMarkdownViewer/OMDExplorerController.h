// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDLayoutMetrics.h"

@class OMDGitHubClient;
@class OMDExplorerController;

static const CGFloat OMDExplorerListDefaultFontSize = 14.0;

// What the explorer needs from the window that hosts it.
@protocol OMDExplorerControllerDelegate <NSObject>
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (void)applyScrollSpeedPreference;
- (void)openLocalPath:(NSString *)path inNewTab:(BOOL)inNewTab;
// Selects the tab already showing this GitHub file; returns NO if none is.
- (BOOL)selectDocumentTabForGitHubUser:(NSString *)user repo:(NSString *)repo path:(NSString *)path;
// Opens a file from the local cache of a GitHub repository.
- (void)openGitHubFileAtCachePath:(NSString *)fullPath
                             user:(NSString *)user
                             repo:(NSString *)repo
                     relativePath:(NSString *)relativePath
                       descriptor:(NSString *)descriptor
                         inNewTab:(BOOL)inNewTab;
@end

// The explorer sidebar: a local folder or a cached GitHub repository listed
// in a table, with the controls to choose between them.
@interface OMDExplorerController : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDelegate, NSControlTextEditingDelegate>
{
    id<OMDExplorerControllerDelegate> _delegate;
    NSView *_containerView;
    OMDGitHubClient *_gitHubClient;
    NSControl *_explorerSourceModeControl;
    NSTextField *_explorerLocalRootLabel;
    NSTextField *_explorerGitHubUserLabel;
    NSComboBox *_explorerGitHubUserComboBox;
    NSComboBox *_explorerGitHubRepoComboBox;
    NSButton *_explorerGitHubIncludeForkArchivedButton;
    NSButton *_explorerShowHiddenFilesButton;
    NSButton *_explorerNavigateUpButton;
    NSTextField *_explorerPathLabel;
    NSScrollView *_explorerScrollView;
    NSTableView *_explorerTableView;
    NSMutableArray *_explorerEntries;
    NSArray *_explorerGitHubRepos;
    NSString *_explorerLocalRootPath;
    NSString *_explorerLocalCurrentPath;
    NSString *_explorerGitHubUser;
    NSString *_explorerGitHubRepo;
    NSString *_explorerGitHubCurrentPath;
    NSString *_explorerGitHubRepoCachePath;
    NSInteger _explorerSourceMode;
    NSUInteger _explorerRequestToken;
    BOOL _explorerIsLoading;
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
- (NSString *)explorerGitHubTokenPreference;
- (void)setExplorerGitHubTokenPreference:(NSString *)token;

@end
