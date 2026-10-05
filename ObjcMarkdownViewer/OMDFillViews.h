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

@interface OMDRoundedCardView : OMDFlippedFillView
{
    NSColor *_borderColor;
    CGFloat _cornerRadius;
}
@property (nonatomic, retain) NSColor *borderColor;
@property (nonatomic, assign) CGFloat cornerRadius;
@end
