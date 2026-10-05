// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Sizing and resetting the segmented controls in the toolbar and the
// formatting bar.
CGFloat OMDControlWidthForTitle(NSString *title,
                                       NSFont *font,
                                       CGFloat minWidth,
                                       CGFloat horizontalPadding);
void OMDClearSegmentedControlSelection(NSSegmentedControl *control);
