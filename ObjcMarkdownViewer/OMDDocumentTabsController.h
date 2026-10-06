// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDLayoutMetrics.h"

// Keys of a tab record: the state of one open document while another tab
// is showing.
extern NSString * const OMDTabMarkdownKey;
extern NSString * const OMDTabSourcePathKey;
extern NSString * const OMDTabDisplayTitleKey;
extern NSString * const OMDTabDirtyKey;
extern NSString * const OMDTabReadOnlyKey;
extern NSString * const OMDTabRenderModeKey;
extern NSString * const OMDTabSyntaxLanguageKey;
extern NSString * const OMDTabLoadedDiskFingerprintKey;
extern NSString * const OMDTabObservedDiskFingerprintKey;
extern NSString * const OMDTabSuppressedDiskFingerprintKey;
extern NSString * const OMDTabImageFingerprintsKey;
extern NSString * const OMDTabSuppressedImageFingerprintsKey;
extern NSString * const OMDTabImageMarkdownKey;
extern NSString * const OMDTabImageSourcePathKey;
// A document opened from the web: its raw address (an OMDRemoteDocument's rawURL).
extern NSString * const OMDTabRemoteURLKey;

@protocol OMDDocumentTabsControllerDelegate <NSObject>
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (void)selectDocumentTabAtIndex:(NSInteger)index;
- (void)closeDocumentTabAtIndex:(NSInteger)index;
@end

// The open documents as tab records (mutable dictionaries keyed by the
// OMDTab keys), which one is selected, and the strip of tab buttons.
@interface OMDDocumentTabsController : NSObject
{
    id<OMDDocumentTabsControllerDelegate> _delegate;
    NSMutableArray *_tabs;
    NSInteger _selectedIndex;
    NSView *_stripView;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDDocumentTabsControllerDelegate>)delegate;

- (NSUInteger)count;
- (NSMutableDictionary *)tabAtIndex:(NSInteger)index;
- (void)addTab:(NSMutableDictionary *)tab;
- (void)replaceTabAtIndex:(NSInteger)index withTab:(NSMutableDictionary *)tab;
- (void)removeTabAtIndex:(NSInteger)index;
// -1 when no tab is selected.
- (NSInteger)selectedIndex;
- (void)setSelectedIndex:(NSInteger)index;
// The selected tab's record, or nil.
- (NSMutableDictionary *)selectedTab;

// -1 when no tab shows the document.
- (NSInteger)documentTabIndexForLocalPath:(NSString *)sourcePath;
- (NSInteger)documentTabIndexForRemoteURL:(NSString *)rawURL;

// The strip of tab buttons, shown only with two or more tabs.
- (NSView *)stripView;
- (CGFloat)currentTabStripHeight;
- (void)updateTabStrip;

@end
