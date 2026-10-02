// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

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
@property (nonatomic, readonly) NSColor *hrColor;
@property (nonatomic, readonly) NSColor *codeBorderColor;
@property (nonatomic, readonly) NSColor *blockquoteBorderColor;
@property (nonatomic, readonly) NSColor *blockquoteTextColor;

+ (instancetype)defaultTheme;
// The GitHub light theme, or GitHub's dark theme (theme-github-dark.toml).
+ (instancetype)defaultThemeForDarkAppearance:(BOOL)dark;
+ (instancetype)themeWithContentsOfFile:(NSString *)path error:(NSError **)error;

// YES when the background is dark (luminance below one half).
- (BOOL)isDark;

- (NSDictionary *)baseAttributes;
- (NSDictionary *)headingAttributesForSize:(CGFloat)size;
- (NSDictionary *)codeAttributesForSize:(CGFloat)size;

@end
