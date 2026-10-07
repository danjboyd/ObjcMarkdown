// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

static const CGFloat OMDWin11SplitDividerThickness = 1.0;
static const CGFloat OMDWin11SplitDividerHitThickness = 12.0;

@interface OMDWin11SplitView : NSSplitView
- (void)omdInvalidateCursorRects;
- (void)omdSnapSubviewsToPixels;
@end
