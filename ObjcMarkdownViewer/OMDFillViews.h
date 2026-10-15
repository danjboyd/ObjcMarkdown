// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@interface OMDFlippedFillView : NSView
{
    NSColor *_fillColor;
}
@property (nonatomic, retain) NSColor *fillColor;
@end

@interface OMDPreviewCanvasView : OMDFlippedFillView
@end

// A plain view laid out from the top.
@interface OMDFlippedView : NSView
@end

// A scroll view that tiles only when its size changes. GNUstep's
// NSScrollView tiles again on every -setFrame: and -setFrameSize:, also
// when the size stays the same (each layout pass of the split view and the
// editor container does that), and in gnustep-gui 0.32 a tile with
// autohiding scrollers takes the vertical scroller away and puts it back:
// the editor's text view changes width twice and the whole document is
// laid out twice, about a second for a 1.4 MB file (#121).
@interface OMDScrollView : NSScrollView
@end
