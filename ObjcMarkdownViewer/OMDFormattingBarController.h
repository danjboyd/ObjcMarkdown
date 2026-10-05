// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDLayoutMetrics.h"

@class OMDFormattingBarController;
@class OMDFormattingBarView;

typedef NS_ENUM(NSInteger, OMDFormattingCommandTag) {
    OMDFormattingCommandTagBold = 1001,
    OMDFormattingCommandTagItalic = 1002,
    OMDFormattingCommandTagStrike = 1003,
    OMDFormattingCommandTagInlineCode = 1004,
    OMDFormattingCommandTagLink = 1005,
    OMDFormattingCommandTagImage = 1006,
    OMDFormattingCommandTagListBullet = 1010,
    OMDFormattingCommandTagListNumber = 1011,
    OMDFormattingCommandTagListTask = 1012,
    OMDFormattingCommandTagBlockQuote = 1013,
    OMDFormattingCommandTagCodeFence = 1014,
    OMDFormattingCommandTagTable = 1015,
    OMDFormattingCommandTagHorizontalRule = 1016
};

// The editor the formatting bar edits.
@protocol OMDFormattingBarControllerDelegate <NSObject>
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (void)updateFormattingBarContextState;
// Each is ignored unless the bar is showing on an editable document.
- (void)formattingBarController:(OMDFormattingBarController *)controller applyHeadingLevel:(NSInteger)level;
- (void)formattingBarController:(OMDFormattingBarController *)controller performCommandWithTag:(NSInteger)tag;
@end

// The bar of Markdown formatting controls above the source editor.
@interface OMDFormattingBarController : NSObject
{
    id<OMDFormattingBarControllerDelegate> _delegate;
    NSView *_containerView;
    OMDFormattingBarView *_formattingBarView;
    NSSegmentedControl *_formatHeadingControl;
    NSMutableDictionary *_formatCommandButtons;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDFormattingBarControllerDelegate>)delegate;

// Builds the bar at the top of the container (not retained).
- (void)setupInContainer:(NSView *)container;
// Builds the bar again, for a new layout density.
- (void)rebuildFormattingBar;
// The bar, or nil before it is built.
- (NSView *)barView;
// The bar's height at this width (one row or two), placing the controls
// when applyFrames is YES.
- (CGFloat)layoutFormattingBarControlsForWidth:(CGFloat)containerWidth
                                  applyFrames:(BOOL)applyFrames;
- (void)setControlsEnabled:(BOOL)enabled;
// Selects P (0) or H1-H6 (1-6) in the paragraph style control.
- (void)selectHeadingLevel:(NSInteger)level;

@end
