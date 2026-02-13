// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@interface OMDLineNumberRulerView : NSRulerView

- (instancetype)initWithScrollView:(NSScrollView *)scrollView textView:(NSTextView *)textView;
- (void)invalidateLineNumbers;

@end
