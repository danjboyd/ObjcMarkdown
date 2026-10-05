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
