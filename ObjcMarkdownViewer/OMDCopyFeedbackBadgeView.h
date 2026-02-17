// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

@interface OMDCopyFeedbackBadgeView : NSView

- (id)initWithFrame:(NSRect)frameRect text:(NSString *)text font:(NSFont *)font;
+ (NSSize)sizeForText:(NSString *)text font:(NSFont *)font;

@end
