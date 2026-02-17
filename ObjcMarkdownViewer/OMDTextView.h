// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@interface OMDTextView : NSTextView

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
