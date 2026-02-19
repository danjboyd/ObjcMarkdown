// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDSourceTextView;

@protocol OMDSourceTextViewVimEventHandling <NSObject>
- (BOOL)sourceTextView:(OMDSourceTextView *)textView handleVimKeyEvent:(NSEvent *)event;
@end

@interface OMDSourceTextView : NSTextView

@end
