// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

static const CGFloat OMDToolbarControlHeight = 28.0;
static const CGFloat OMDToolbarItemHeight = 32.0;
static const CGFloat OMDToolbarActionSegmentWidth = 46.0;
static const CGFloat OMDToolbarActionGroupSpacing = 8.0;

@interface OMDToolbarToolTipView : NSView
{
    NSMutableArray *_toolTipRects;
    NSMutableArray *_toolTipStrings;
}
- (void)setToolTip:(NSString *)toolTip forRect:(NSRect)rect;
@end

@interface OMDToolbarActionGlyphOverlayView : OMDToolbarToolTipView
{
    NSSegmentedControl *_fileActionsControl;
    NSSegmentedControl *_utilityActionsControl;
}
- (void)setFileActionsControl:(NSSegmentedControl *)fileControl
        utilityActionsControl:(NSSegmentedControl *)utilityControl;
@end
