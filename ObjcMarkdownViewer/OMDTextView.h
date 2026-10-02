// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDTextView;
@class OMRenderedObject;

// Optional delegate methods for rendered objects (math, diagrams, tables,
// images) in the preview.
@protocol OMDTextViewRenderedObjectDelegate <NSObject>
@optional
// lineRange holds 1-based source lines (location = first line).
- (void)textView:(OMDTextView *)textView revealSourceLineRange:(NSRange)lineRange;
@end

@interface OMDTextView : NSTextView

// The rendered object drawn at a point in view coordinates, or nil.
- (OMRenderedObject *)renderedObjectAtPoint:(NSPoint)point characterIndex:(NSUInteger *)characterIndex;
// An image of the attachment at a character index, as drawn in the preview.
- (NSImage *)imageForRenderedObjectAtIndex:(NSUInteger)characterIndex;

@property (nonatomic, retain) NSColor *documentBackgroundColor;
@property (nonatomic, retain) NSColor *documentBorderColor;
@property (nonatomic, assign) CGFloat documentCornerRadius;
@property (nonatomic, assign) CGFloat documentBorderWidth;
@property (nonatomic, retain) NSArray *codeBlockRanges;
@property (nonatomic, retain) NSColor *codeBlockBackgroundColor;
@property (nonatomic, retain) NSColor *codeBlockBorderColor;
@property (nonatomic, assign) NSSize codeBlockPadding;
@property (nonatomic, assign) CGFloat codeBlockCornerRadius;
@property (nonatomic, assign) CGFloat codeBlockBorderWidth;
@property (nonatomic, retain) NSArray *blockquoteRanges;
@property (nonatomic, retain) NSColor *blockquoteLineColor;
@property (nonatomic, assign) CGFloat blockquoteLineWidth;

@end
