// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>

FOUNDATION_EXPORT NSString * const OMDSourceHighlighterOptionHighContrast;
FOUNDATION_EXPORT NSString * const OMDSourceHighlighterOptionAccentColor;

@interface OMDSourceHighlighter : NSObject

+ (void)highlightTextStorage:(NSTextStorage *)textStorage
               baseTextColor:(NSColor *)baseTextColor
             backgroundColor:(NSColor *)backgroundColor;

+ (void)highlightTextStorage:(NSTextStorage *)textStorage
               baseTextColor:(NSColor *)baseTextColor
             backgroundColor:(NSColor *)backgroundColor
                     options:(NSDictionary *)options
                 targetRange:(NSRange)targetRange;

+ (void)highlightAttributedString:(NSMutableAttributedString *)attributedString
                    baseTextColor:(NSColor *)baseTextColor
                  backgroundColor:(NSColor *)backgroundColor;

+ (void)highlightAttributedString:(NSMutableAttributedString *)attributedString
                    baseTextColor:(NSColor *)baseTextColor
                  backgroundColor:(NSColor *)backgroundColor
                          options:(NSDictionary *)options
                      targetRange:(NSRange)targetRange;

@end
