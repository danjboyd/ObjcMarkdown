// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDTextView;
@class OMRenderedObject;

// Optional delegate methods for rendered objects (math, diagrams, tables,
// images) in the preview.
@protocol OMDTextViewRenderedObjectDelegate <NSObject>
@optional
// Show the object's Markdown source in the editor.
- (void)textView:(OMDTextView *)textView revealSourceOfRenderedObject:(OMRenderedObject *)object;
// Render a math object again with its caches dropped.
- (void)textView:(OMDTextView *)textView rerenderRenderedObject:(OMRenderedObject *)object;
@end

@interface OMDTextView : NSTextView

// The rendered object drawn at a point in view coordinates, or nil.
- (OMRenderedObject *)renderedObjectAtPoint:(NSPoint)point characterIndex:(NSUInteger *)characterIndex;
// An image of the attachment at a character index, as drawn in the preview.
- (NSImage *)imageForRenderedObjectAtIndex:(NSUInteger)characterIndex;
// An object's box in view coordinates, or NSZeroRect.
- (NSRect)viewRectForRenderedObjectAtIndex:(NSUInteger)characterIndex;
// Rebuilds the source tool tips; call after the text is laid out.
- (void)updateRenderedObjectToolTips;
// Character index of an object to mark as linked to the editor caret (a
// dashed outline), or NSNotFound.
@property (nonatomic, assign) NSUInteger linkedObjectIndex;
// Character index of the object whose sourceRange contains location (an
// insertion point just after the object counts), or NSNotFound.
- (NSUInteger)renderedObjectIndexContainingSourceLocation:(NSUInteger)location;

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
