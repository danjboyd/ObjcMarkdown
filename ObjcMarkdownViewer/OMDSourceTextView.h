// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@class OMDSourceTextView;

@protocol OMDSourceTextViewVimEventHandling <NSObject>
- (BOOL)sourceTextView:(OMDSourceTextView *)textView handleVimKeyEvent:(NSEvent *)event;
@end

@interface OMDSourceTextView : NSTextView

@end
