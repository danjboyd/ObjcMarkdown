// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDLayoutMetrics.h"

@class OMDMarkdownDocument;

@protocol OMDDocumentTabsControllerDelegate <NSObject>
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (void)selectDocumentTabAtIndex:(NSInteger)index;
- (void)closeDocumentTabAtIndex:(NSInteger)index;
@end

// The open documents, which one is selected, and the strip of tab buttons.
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
- (OMDMarkdownDocument *)tabAtIndex:(NSInteger)index;
- (void)addTab:(OMDMarkdownDocument *)tab;
- (void)replaceTabAtIndex:(NSInteger)index withTab:(OMDMarkdownDocument *)tab;
- (void)removeTabAtIndex:(NSInteger)index;
// -1 when no tab is selected.
- (NSInteger)selectedIndex;
- (void)setSelectedIndex:(NSInteger)index;
// The selected tab's document, or nil.
- (OMDMarkdownDocument *)selectedTab;

// -1 when no tab shows the document.
- (NSInteger)documentTabIndexForLocalPath:(NSString *)sourcePath;
- (NSInteger)documentTabIndexForRemoteURL:(NSString *)rawURL;

// The strip of tab buttons, shown only with two or more tabs.
- (NSView *)stripView;
- (CGFloat)currentTabStripHeight;
- (void)updateTabStrip;

@end
