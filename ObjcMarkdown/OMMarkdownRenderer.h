// ObjcMarkdown
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class OMTheme;

@interface OMMarkdownRenderer : NSObject

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown;
- (instancetype)initWithTheme:(OMTheme *)theme;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, assign) CGFloat layoutWidth;
- (NSColor *)backgroundColor;
@property (nonatomic, readonly) NSArray *codeBlockRanges;
@property (nonatomic, readonly) NSArray *blockquoteRanges;

@end
