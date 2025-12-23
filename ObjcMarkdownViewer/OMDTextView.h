// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@interface OMDTextView : NSTextView

@property (nonatomic, retain) NSArray *codeBlockRanges;
@property (nonatomic, retain) NSColor *codeBlockBackgroundColor;
@property (nonatomic, assign) NSSize codeBlockPadding;
@property (nonatomic, retain) NSArray *blockquoteRanges;
@property (nonatomic, retain) NSColor *blockquoteLineColor;
@property (nonatomic, assign) CGFloat blockquoteLineWidth;

@end
