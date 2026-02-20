// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@interface OMDLineNumberRulerView : NSRulerView

- (instancetype)initWithScrollView:(NSScrollView *)scrollView textView:(NSTextView *)textView;
- (void)invalidateLineNumbers;

@end
