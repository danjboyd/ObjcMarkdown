// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMTheme.h"

#ifndef OBJCMARKDOWN_ENABLE_TOML_THEME
#define OBJCMARKDOWN_ENABLE_TOML_THEME 1
#endif

#if OBJCMARKDOWN_ENABLE_TOML_THEME
#include <toml.h>
#endif
#include <stdlib.h>
#include <string.h>

@interface OMTheme ()
@property (nonatomic, retain) NSFont *baseFont;
@property (nonatomic, retain) NSColor *baseTextColor;
@property (nonatomic, retain) NSColor *baseBackgroundColor;
@property (nonatomic, retain) NSFont *headingFont;
@property (nonatomic, retain) NSColor *headingColor;
@property (nonatomic, retain) NSFont *codeFont;
@property (nonatomic, retain) NSColor *codeTextColor;
@property (nonatomic, retain) NSColor *codeBackgroundColor;
@property (nonatomic, retain) NSColor *linkColor;
@property (nonatomic, retain) NSColor *hrColor;
@end

@implementation OMTheme

+ (instancetype)defaultTheme
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:@"theme-github" ofType:@"toml"];
    if (path == nil) {
        path = @"Resources/theme-github.toml";
    }

    NSError *error = nil;
    OMTheme *theme = [self themeWithContentsOfFile:path error:&error];
    if (theme != nil) {
        return theme;
    }

    return [[[OMTheme alloc] initWithDefaultValues] autorelease];
}

+ (instancetype)themeWithContentsOfFile:(NSString *)path error:(NSError **)error
{
#if !OBJCMARKDOWN_ENABLE_TOML_THEME
    (void)path;
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"ObjcMarkdownTheme"
                                     code:4
                                 userInfo:@{ NSLocalizedDescriptionKey: @"TOML theme parsing is disabled in this build." }];
    }
    return nil;
#else
    if (path == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ObjcMarkdownTheme"
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Theme path is nil." }];
        }
        return nil;
    }

    NSString *resolvedPath = [path stringByExpandingTildeInPath];
    if (![resolvedPath isAbsolutePath]) {
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        resolvedPath = [cwd stringByAppendingPathComponent:resolvedPath];
    }

    FILE *fp = fopen([resolvedPath fileSystemRepresentation], "r");
    if (fp == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ObjcMarkdownTheme"
                                         code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Unable to open theme file." }];
        }
        return nil;
    }

    char errbuf[200];
    toml_table_t *root = toml_parse_file(fp, errbuf, sizeof(errbuf));
    fclose(fp);
    if (root == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ObjcMarkdownTheme"
                                         code:3
                                     userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errbuf] }];
        }
        return nil;
    }

    OMTheme *theme = [[[OMTheme alloc] initWithDefaultValues] autorelease];
    toml_table_t *base = toml_table_in(root, "base");
    if (base != NULL) {
        NSString *fontFamily = [self stringInTable:base key:"font_family"];
        NSNumber *fontSize = [self intInTable:base key:"font_size"];
        NSString *textColor = [self stringInTable:base key:"text_color"];
        NSString *background = [self stringInTable:base key:"background"];

        if (fontFamily != nil || fontSize != nil) {
            NSString *name = fontFamily != nil ? fontFamily : @"Helvetica";
            CGFloat size = fontSize != nil ? [fontSize doubleValue] : 14.0;
            NSFont *font = [NSFont fontWithName:name size:size];
            if (font == nil) {
                font = [NSFont systemFontOfSize:size];
            }
            theme.baseFont = font;
        }

        if (textColor != nil) {
            NSColor *color = [self colorFromHexString:textColor];
            if (color != nil) {
                theme.baseTextColor = color;
            }
        }

        if (background != nil) {
            NSColor *color = [self colorFromHexString:background];
            if (color != nil) {
                theme.baseBackgroundColor = color;
            }
        }
    }

    toml_table_t *heading = toml_table_in(root, "heading");
    if (heading != NULL) {
        NSString *fontFamily = [self stringInTable:heading key:"font_family"];
        NSString *colorValue = [self stringInTable:heading key:"color"];
        if (fontFamily != nil) {
            NSFont *font = [NSFont fontWithName:fontFamily size:theme.baseFont.pointSize];
            if (font == nil) {
                font = [NSFont boldSystemFontOfSize:theme.baseFont.pointSize];
            }
            if (font != nil) {
                theme.headingFont = font;
            }
        }
        if (colorValue != nil) {
            NSColor *color = [self colorFromHexString:colorValue];
            if (color != nil) {
                theme.headingColor = color;
            }
        }
    }

    toml_table_t *code = toml_table_in(root, "code");
    if (code != NULL) {
        NSString *fontFamily = [self stringInTable:code key:"font_family"];
        NSString *colorValue = [self stringInTable:code key:"color"];
        NSString *backgroundValue = [self stringInTable:code key:"background"];
        if (fontFamily != nil) {
            NSFont *font = [NSFont fontWithName:fontFamily size:theme.baseFont.pointSize];
            if (font == nil) {
                font = [NSFont userFixedPitchFontOfSize:theme.baseFont.pointSize];
            }
            if (font != nil) {
                theme.codeFont = font;
            }
        }
        if (colorValue != nil) {
            NSColor *color = [self colorFromHexString:colorValue];
            if (color != nil) {
                theme.codeTextColor = color;
            }
        }
        if (backgroundValue != nil) {
            NSColor *color = [self colorFromHexString:backgroundValue];
            if (color != nil) {
                theme.codeBackgroundColor = color;
            }
        }
    }

    toml_table_t *link = toml_table_in(root, "link");
    if (link != NULL) {
        NSString *colorValue = [self stringInTable:link key:"color"];
        if (colorValue != nil) {
            NSColor *color = [self colorFromHexString:colorValue];
            if (color != nil) {
                theme.linkColor = color;
            }
        }
    }

    toml_table_t *hr = toml_table_in(root, "hr");
    if (hr != NULL) {
        NSString *colorValue = [self stringInTable:hr key:"color"];
        if (colorValue != nil) {
            NSColor *color = [self colorFromHexString:colorValue];
            if (color != nil) {
                theme.hrColor = color;
            }
        }
    }

    toml_free(root);
    return theme;
#endif
}

- (instancetype)initWithDefaultValues
{
    self = [super init];
    if (self) {
        _baseFont = [[NSFont systemFontOfSize:20.0] retain];
        _baseTextColor = [[self class] colorFromHexString:@"#24292f"];
        if (_baseTextColor == nil) {
            _baseTextColor = [[NSColor blackColor] retain];
        } else {
            [_baseTextColor retain];
        }
        _baseBackgroundColor = [[self class] colorFromHexString:@"#ffffff"];
        if (_baseBackgroundColor == nil) {
            _baseBackgroundColor = [[NSColor whiteColor] retain];
        } else {
            [_baseBackgroundColor retain];
        }
        _headingFont = [[NSFont boldSystemFontOfSize:[_baseFont pointSize]] retain];
        _headingColor = [[self class] colorFromHexString:@"#24292f"];
        if (_headingColor == nil) {
            _headingColor = [[NSColor blackColor] retain];
        } else {
            [_headingColor retain];
        }
        _codeFont = [[NSFont userFixedPitchFontOfSize:[_baseFont pointSize]] retain];
        _codeTextColor = [[self class] colorFromHexString:@"#24292f"];
        if (_codeTextColor == nil) {
            _codeTextColor = [[NSColor blackColor] retain];
        } else {
            [_codeTextColor retain];
        }
        _codeBackgroundColor = [[self class] colorFromHexString:@"#f6f8fa"];
        if (_codeBackgroundColor == nil) {
            _codeBackgroundColor = [[NSColor whiteColor] retain];
        } else {
            [_codeBackgroundColor retain];
        }
        _linkColor = [[self class] colorFromHexString:@"#0969da"];
        if (_linkColor == nil) {
            _linkColor = [[NSColor blueColor] retain];
        } else {
            [_linkColor retain];
        }
        _hrColor = [[self class] colorFromHexString:@"#d0d7de"];
        if (_hrColor == nil) {
            _hrColor = [[NSColor lightGrayColor] retain];
        } else {
            [_hrColor retain];
        }
    }
    return self;
}

- (void)dealloc
{
    [_baseFont release];
    [_baseTextColor release];
    [_baseBackgroundColor release];
    [_headingFont release];
    [_headingColor release];
    [_codeFont release];
    [_codeTextColor release];
    [_codeBackgroundColor release];
    [_linkColor release];
    [_hrColor release];
    [super dealloc];
}

- (NSDictionary *)baseAttributes
{
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (self.baseFont != nil) {
        [attributes setObject:self.baseFont forKey:NSFontAttributeName];
    }
    if (self.baseTextColor != nil) {
        [attributes setObject:self.baseTextColor forKey:NSForegroundColorAttributeName];
    }
    return attributes;
}

- (NSDictionary *)headingAttributesForSize:(CGFloat)size
{
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (self.headingFont != nil) {
        NSFont *font = [NSFont fontWithName:[self.headingFont fontName] size:size];
        if (font == nil) {
            font = [NSFont boldSystemFontOfSize:size];
        }
        if (font != nil) {
            [attributes setObject:font forKey:NSFontAttributeName];
        }
    }
    if (self.headingColor != nil) {
        [attributes setObject:self.headingColor forKey:NSForegroundColorAttributeName];
    }
    return attributes;
}

- (NSDictionary *)codeAttributesForSize:(CGFloat)size
{
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (self.codeFont != nil) {
        NSFont *font = [NSFont fontWithName:[self.codeFont fontName] size:size];
        if (font == nil) {
            font = [NSFont userFixedPitchFontOfSize:size];
        }
        if (font != nil) {
            [attributes setObject:font forKey:NSFontAttributeName];
        }
    }
    if (self.codeTextColor != nil) {
        [attributes setObject:self.codeTextColor forKey:NSForegroundColorAttributeName];
    }
    if (self.codeBackgroundColor != nil) {
        [attributes setObject:self.codeBackgroundColor forKey:NSBackgroundColorAttributeName];
    }
    return attributes;
}

#if OBJCMARKDOWN_ENABLE_TOML_THEME
+ (NSString *)stringInTable:(toml_table_t *)table key:(const char *)key
{
    toml_datum_t value = toml_string_in(table, key);
    if (!value.ok || value.u.s == NULL) {
        return nil;
    }
    NSString *result = [NSString stringWithUTF8String:value.u.s];
    free(value.u.s);
    return result;
}

+ (NSNumber *)intInTable:(toml_table_t *)table key:(const char *)key
{
    toml_datum_t value = toml_int_in(table, key);
    if (!value.ok) {
        return nil;
    }
    return [NSNumber numberWithLongLong:value.u.i];
}
#endif

+ (NSColor *)colorFromHexString:(NSString *)hex
{
    if (hex == nil) {
        return nil;
    }

    const char *cstr = [hex UTF8String];
    if (cstr == NULL || strlen(cstr) != 7 || cstr[0] != '#') {
        return nil;
    }

    char buf[3];
    buf[2] = '\0';

    buf[0] = cstr[1];
    buf[1] = cstr[2];
    long r = strtol(buf, NULL, 16);

    buf[0] = cstr[3];
    buf[1] = cstr[4];
    long g = strtol(buf, NULL, 16);

    buf[0] = cstr[5];
    buf[1] = cstr[6];
    long b = strtol(buf, NULL, 16);

    return [NSColor colorWithCalibratedRed:(r / 255.0)
                                     green:(g / 255.0)
                                      blue:(b / 255.0)
                                     alpha:1.0];
}

@end
