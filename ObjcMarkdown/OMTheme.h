// ObjcMarkdown
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface OMTheme : NSObject

@property (nonatomic, readonly) NSFont *baseFont;
@property (nonatomic, readonly) NSColor *baseTextColor;
@property (nonatomic, readonly) NSColor *baseBackgroundColor;
@property (nonatomic, readonly) NSFont *headingFont;
@property (nonatomic, readonly) NSColor *headingColor;
@property (nonatomic, readonly) NSFont *codeFont;
@property (nonatomic, readonly) NSColor *codeTextColor;
@property (nonatomic, readonly) NSColor *codeBackgroundColor;
@property (nonatomic, readonly) NSColor *linkColor;

+ (instancetype)defaultTheme;
+ (instancetype)themeWithContentsOfFile:(NSString *)path error:(NSError **)error;

- (NSDictionary *)baseAttributes;
- (NSDictionary *)headingAttributesForSize:(CGFloat)size;
- (NSDictionary *)codeAttributesForSize:(CGFloat)size;

@end
