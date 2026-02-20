// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMarkdownRenderer.h"
#import "OMTheme.h"

#import <dispatch/dispatch.h>

#include <cmark.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif
#include <math.h>
#include <stdlib.h>
#include <string.h>

NSString * const OMMarkdownRendererMathArtifactsDidWarmNotification = @"OMMarkdownRendererMathArtifactsDidWarmNotification";
NSString * const OMMarkdownRendererRemoteImagesDidWarmNotification = @"OMMarkdownRendererRemoteImagesDidWarmNotification";
NSString * const OMMarkdownRendererAnchorSourceStartLineKey = @"sourceStartLine";
NSString * const OMMarkdownRendererAnchorSourceEndLineKey = @"sourceEndLine";
NSString * const OMMarkdownRendererAnchorTargetStartKey = @"targetStart";
NSString * const OMMarkdownRendererAnchorTargetLengthKey = @"targetLength";
NSString * const OMMarkdownRendererAnchorBlockIDKey = @"blockID";

typedef struct {
    NSUInteger mathRequests;
    NSUInteger mathCacheHits;
    NSUInteger mathCacheMisses;
    NSUInteger mathAssetCacheHits;
    NSUInteger mathAssetCacheMisses;
    NSUInteger mathRendered;
    NSUInteger mathFailures;
    NSUInteger latexRuns;
    NSUInteger dvisvgmRuns;
    NSTimeInterval latexSeconds;
    NSTimeInterval dvisvgmSeconds;
    NSTimeInterval svgDecodeSeconds;
    NSTimeInterval mathTotalSeconds;
} OMMathPerfStats;

typedef struct {
    OMMarkdownParsingOptions *parsingOptions;
    NSArray *sourceLines;
    NSMutableArray *blockAnchors;
    OMMathPerfStats *mathPerfStats;
    CGFloat layoutWidth;
    BOOL allowTableHorizontalOverflow;
    BOOL asynchronousMathGenerationEnabled;
} OMRenderContext;

static NSString *OMExecutablePathNamed(NSString *name);
static BOOL OMURLUsesRemoteScheme(NSURL *url);

static NSTimeInterval OMNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

static BOOL OMTruthyFlagValue(NSString *value)
{
    if (value == nil) {
        return NO;
    }
    NSString *lower = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [lower isEqualToString:@"1"] ||
           [lower isEqualToString:@"true"] ||
           [lower isEqualToString:@"yes"] ||
           [lower isEqualToString:@"on"];
}

static BOOL OMPerformanceLoggingEnabled(void)
{
    static BOOL resolved = NO;
    static BOOL enabled = NO;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_PERF_LOG"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_PERF_LOG"];
        }
        if (flag != nil && [flag length] > 0) {
            enabled = OMTruthyFlagValue(flag);
        } else {
            enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownPerfLog"];
        }
        resolved = YES;
    }
    return enabled;
}

static OMMarkdownParsingOptions *OMRenderContextParsingOptions(const OMRenderContext *renderContext)
{
    if (renderContext == NULL) {
        return nil;
    }
    return renderContext->parsingOptions;
}

static BOOL OMShouldParseMathSpans(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return YES;
    }
    return [options mathRenderingPolicy] != OMMarkdownMathRenderingPolicyDisabled;
}

static BOOL OMExternalMathRenderingEnabled(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return NO;
    }
    return [options mathRenderingPolicy] == OMMarkdownMathRenderingPolicyExternalTools;
}

static NSUInteger OMMathMaximumFormulaLength(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil || [options maximumMathFormulaLength] == 0) {
        return 2048;
    }
    return [options maximumMathFormulaLength];
}

static NSTimeInterval OMExternalToolTimeout(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return 4.0;
    }
    NSTimeInterval timeout = [options externalToolTimeout];
    if (timeout <= 0.0) {
        return 4.0;
    }
    return timeout;
}

static BOOL OMShouldRenderImages(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return YES;
    }
    return [options renderImages];
}

static BOOL OMShouldAllowRemoteImages(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return NO;
    }
    return [options allowRemoteImages];
}

static NSSet *OMAllowedImageSchemes(void)
{
    static NSSet *schemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        schemes = [[NSSet alloc] initWithObjects:@"file", @"http", @"https", nil];
    });
    return schemes;
}

static NSSet *OMAllowedLinkSchemes(void)
{
    static NSSet *schemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        schemes = [[NSSet alloc] initWithObjects:@"file", @"http", @"https", @"mailto", nil];
    });
    return schemes;
}

static BOOL OMURLUsesAllowedScheme(NSURL *url, NSSet *allowedSchemes)
{
    if (url == nil || allowedSchemes == nil) {
        return NO;
    }
    NSString *scheme = [[url scheme] lowercaseString];
    if (scheme == nil || [scheme length] == 0) {
        return NO;
    }
    return [allowedSchemes containsObject:scheme];
}

static BOOL OMURLUsesAllowedImageScheme(NSURL *url)
{
    return OMURLUsesAllowedScheme(url, OMAllowedImageSchemes());
}

static BOOL OMURLUsesAllowedLinkScheme(NSURL *url)
{
    return OMURLUsesAllowedScheme(url, OMAllowedLinkSchemes());
}

static BOOL OMTreeSitterRuntimeAvailable(void)
{
    static BOOL resolved = NO;
    static BOOL available = NO;
    if (!resolved) {
        available = NO;

        const char *libraryCandidates[] = {
            "libtree-sitter.so",
            "libtree-sitter.so.0",
            "libtree-sitter.so.0.22",
            "libtree-sitter.dylib",
#if defined(_WIN32)
            "tree-sitter.dll",
            "libtree-sitter.dll",
#endif
            NULL
        };
        const char **cursor = libraryCandidates;
        for (; *cursor != NULL; cursor++) {
#if defined(_WIN32)
            HMODULE handle = LoadLibraryA(*cursor);
            if (handle != NULL) {
                available = YES;
                FreeLibrary(handle);
                break;
            }
#else
            void *handle = dlopen(*cursor, RTLD_LAZY | RTLD_LOCAL);
            if (handle != NULL) {
                available = YES;
                dlclose(handle);
                break;
            }
#endif
        }

        if (!available) {
            available = (OMExecutablePathNamed(@"tree-sitter") != nil);
        }

        resolved = YES;
    }
    return available;
}

static BOOL OMShouldApplyCodeSyntaxHighlighting(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options != nil && ![options codeSyntaxHighlightingEnabled]) {
        return NO;
    }
    return OMTreeSitterRuntimeAvailable();
}

static OMMarkdownHTMLPolicy OMHTMLPolicyForBlockNode(const OMRenderContext *renderContext,
                                                     BOOL blockNode)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return OMMarkdownHTMLPolicyRenderAsText;
    }
    return blockNode ? [options blockHTMLPolicy] : [options inlineHTMLPolicy];
}

static CGFloat OMMathRasterOversampleFactor(void)
{
    static BOOL resolved = NO;
    static CGFloat factor = 2.0;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *value = [environment objectForKey:@"OMD_MATH_OVERSAMPLE"];
        if (value == nil || [value length] == 0) {
            value = [environment objectForKey:@"OBJCMARKDOWN_MATH_OVERSAMPLE"];
        }
        if (value != nil && [value length] > 0) {
            factor = (CGFloat)[value doubleValue];
        } else {
            id defaultsValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownMathOversample"];
            if ([defaultsValue respondsToSelector:@selector(doubleValue)]) {
                factor = (CGFloat)[defaultsValue doubleValue];
            }
        }

        if (factor < 1.0) {
            factor = 1.0;
        } else if (factor > 4.0) {
            factor = 4.0;
        }
        resolved = YES;
    }
    return factor;
}

static NSString *OMMathAssetCacheKey(NSString *formula, BOOL displayMath, CGFloat renderZoom)
{
    return [NSString stringWithFormat:@"%@|%.2f|%@",
            displayMath ? @"display" : @"inline",
            renderZoom,
            formula];
}

static NSString *OMMathFormulaCacheKey(NSString *formula, BOOL displayMath)
{
    return [NSString stringWithFormat:@"%@|%@",
            displayMath ? @"display" : @"inline",
            formula];
}

static CGFloat OMMathQuantizedRenderZoom(CGFloat zoom, CGFloat oversample)
{
    CGFloat target = zoom;
    if (target < oversample) {
        target = oversample;
    }

    // Quantize upward to limit cache cardinality while avoiding upscale blur.
    CGFloat quantized = (CGFloat)(ceil(target * 4.0) / 4.0);
    if (quantized < 0.5) {
        quantized = 0.5;
    } else if (quantized > 10.0) {
        quantized = 10.0;
    }
    return quantized;
}

static NSFont *OMFontWithTraits(NSFont *font, NSFontTraitMask traits)
{
    if (font == nil) {
        return nil;
    }
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *converted = [manager convertFont:font toHaveTrait:traits];
    return converted != nil ? converted : font;
}

typedef struct {
    NSColor *keywordColor;
    NSColor *commentColor;
    NSColor *stringColor;
    NSColor *numberColor;
    NSColor *directiveColor;
} OMCodeSyntaxPalette;

typedef NS_ENUM(NSUInteger, OMCodeLanguage) {
    OMCodeLanguageUnknown = 0,
    OMCodeLanguageCFamily = 1,
    OMCodeLanguagePython = 2,
    OMCodeLanguageJavaScript = 3,
    OMCodeLanguageTypeScript = 4,
    OMCodeLanguageJSON = 5,
    OMCodeLanguageBash = 6,
    OMCodeLanguageMarkdown = 7,
    OMCodeLanguageYAML = 8,
    OMCodeLanguageTOML = 9,
    OMCodeLanguageSQL = 10,
    OMCodeLanguageRuby = 11,
    OMCodeLanguageMarkup = 12
};

static BOOL OMColorRGBA(NSColor *color, CGFloat *red, CGFloat *green, CGFloat *blue, CGFloat *alpha)
{
    if (color == nil) {
        return NO;
    }
    @try {
        NSColor *rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (rgbColor == nil) {
            return NO;
        }
        if (red != NULL) {
            *red = [rgbColor redComponent];
        }
        if (green != NULL) {
            *green = [rgbColor greenComponent];
        }
        if (blue != NULL) {
            *blue = [rgbColor blueComponent];
        }
        if (alpha != NULL) {
            *alpha = [rgbColor alphaComponent];
        }
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

static OMCodeSyntaxPalette OMCodePaletteForBackground(NSColor *backgroundColor)
{
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    BOOL hasRGB = OMColorRGBA(backgroundColor, &red, &green, &blue, NULL);
    CGFloat luminance = hasRGB ? ((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) : 1.0;
    BOOL darkBackground = luminance < 0.5;

    OMCodeSyntaxPalette palette;
    if (darkBackground) {
        palette.keywordColor = [NSColor colorWithCalibratedRed:0.52 green:0.72 blue:0.98 alpha:1.0];
        palette.commentColor = [NSColor colorWithCalibratedRed:0.49 green:0.66 blue:0.50 alpha:1.0];
        palette.stringColor = [NSColor colorWithCalibratedRed:0.93 green:0.73 blue:0.45 alpha:1.0];
        palette.numberColor = [NSColor colorWithCalibratedRed:0.42 green:0.78 blue:0.78 alpha:1.0];
        palette.directiveColor = [NSColor colorWithCalibratedRed:0.80 green:0.58 blue:0.94 alpha:1.0];
        return palette;
    }

    palette.keywordColor = [NSColor colorWithCalibratedRed:0.11 green:0.31 blue:0.67 alpha:1.0];
    palette.commentColor = [NSColor colorWithCalibratedRed:0.40 green:0.46 blue:0.43 alpha:1.0];
    palette.stringColor = [NSColor colorWithCalibratedRed:0.67 green:0.34 blue:0.03 alpha:1.0];
    palette.numberColor = [NSColor colorWithCalibratedRed:0.00 green:0.45 blue:0.45 alpha:1.0];
    palette.directiveColor = [NSColor colorWithCalibratedRed:0.46 green:0.28 blue:0.65 alpha:1.0];
    return palette;
}

static NSMutableDictionary *OMCodeRegexCache(void)
{
    static NSMutableDictionary *cache = nil;
    if (cache == nil) {
        cache = [[NSMutableDictionary alloc] init];
    }
    return cache;
}

static NSRegularExpression *OMCachedRegex(NSString *pattern, NSRegularExpressionOptions options)
{
    if (pattern == nil || [pattern length] == 0) {
        return nil;
    }

    NSMutableDictionary *cache = OMCodeRegexCache();
    NSString *key = [NSString stringWithFormat:@"%lu|%@",
                     (unsigned long)options,
                     pattern];
    @synchronized (cache) {
        NSRegularExpression *regex = [cache objectForKey:key];
        if (regex != nil) {
            return regex;
        }
        NSRegularExpression *created = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                  options:options
                                                                                    error:NULL];
        if (created != nil) {
            [cache setObject:created forKey:key];
        }
        return created;
    }
}

static NSString *OMPrimaryFenceTokenFromFenceInfo(NSString *fenceInfo)
{
    if (fenceInfo == nil || [fenceInfo length] == 0) {
        return nil;
    }

    NSString *trimmed = [fenceInfo stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed == nil || [trimmed length] == 0) {
        return nil;
    }

    NSRange separator = [trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *token = separator.location == NSNotFound ? trimmed : [trimmed substringToIndex:separator.location];
    if (token == nil || [token length] == 0) {
        return nil;
    }
    return [token lowercaseString];
}

static NSString *OMPrimaryFenceToken(cmark_node *codeBlockNode)
{
    if (codeBlockNode == NULL) {
        return nil;
    }

    const char *info = cmark_node_get_fence_info(codeBlockNode);
    if (info == NULL) {
        return nil;
    }
    NSString *fenceInfo = [NSString stringWithUTF8String:info];
    if (fenceInfo == nil || [fenceInfo length] == 0) {
        return nil;
    }
    return OMPrimaryFenceTokenFromFenceInfo(fenceInfo);
}

static OMCodeLanguage OMLanguageForFenceToken(NSString *token)
{
    if (token == nil || [token length] == 0) {
        return OMCodeLanguageUnknown;
    }

    if ([token isEqualToString:@"objc"] ||
        [token isEqualToString:@"objective-c"] ||
        [token isEqualToString:@"objectivec"] ||
        [token isEqualToString:@"obj-c"] ||
        [token isEqualToString:@"m"] ||
        [token isEqualToString:@"mm"] ||
        [token isEqualToString:@"c"] ||
        [token isEqualToString:@"h"] ||
        [token isEqualToString:@"cc"] ||
        [token isEqualToString:@"cpp"] ||
        [token isEqualToString:@"c++"] ||
        [token isEqualToString:@"hpp"] ||
        [token isEqualToString:@"java"] ||
        [token isEqualToString:@"kotlin"] ||
        [token isEqualToString:@"kt"] ||
        [token isEqualToString:@"kts"] ||
        [token isEqualToString:@"swift"] ||
        [token isEqualToString:@"go"] ||
        [token isEqualToString:@"golang"] ||
        [token isEqualToString:@"rust"] ||
        [token isEqualToString:@"rs"] ||
        [token isEqualToString:@"csharp"] ||
        [token isEqualToString:@"cs"] ||
        [token isEqualToString:@"php"]) {
        return OMCodeLanguageCFamily;
    }
    if ([token isEqualToString:@"python"] ||
        [token isEqualToString:@"py"] ||
        [token isEqualToString:@"py3"]) {
        return OMCodeLanguagePython;
    }
    if ([token isEqualToString:@"javascript"] ||
        [token isEqualToString:@"js"] ||
        [token isEqualToString:@"jsx"] ||
        [token isEqualToString:@"node"] ||
        [token isEqualToString:@"nodejs"]) {
        return OMCodeLanguageJavaScript;
    }
    if ([token isEqualToString:@"typescript"] ||
        [token isEqualToString:@"ts"] ||
        [token isEqualToString:@"tsx"]) {
        return OMCodeLanguageTypeScript;
    }
    if ([token isEqualToString:@"json"] ||
        [token isEqualToString:@"jsonc"]) {
        return OMCodeLanguageJSON;
    }
    if ([token isEqualToString:@"yaml"] ||
        [token isEqualToString:@"yml"]) {
        return OMCodeLanguageYAML;
    }
    if ([token isEqualToString:@"toml"]) {
        return OMCodeLanguageTOML;
    }
    if ([token isEqualToString:@"sql"] ||
        [token isEqualToString:@"mysql"] ||
        [token isEqualToString:@"postgresql"] ||
        [token isEqualToString:@"sqlite"]) {
        return OMCodeLanguageSQL;
    }
    if ([token isEqualToString:@"ruby"] ||
        [token isEqualToString:@"rb"]) {
        return OMCodeLanguageRuby;
    }
    if ([token isEqualToString:@"html"] ||
        [token isEqualToString:@"xml"] ||
        [token isEqualToString:@"svg"] ||
        [token isEqualToString:@"css"]) {
        return OMCodeLanguageMarkup;
    }
    if ([token isEqualToString:@"bash"] ||
        [token isEqualToString:@"sh"] ||
        [token isEqualToString:@"shell"] ||
        [token isEqualToString:@"zsh"]) {
        return OMCodeLanguageBash;
    }
    if ([token isEqualToString:@"markdown"] ||
        [token isEqualToString:@"md"] ||
        [token isEqualToString:@"mdown"] ||
        [token isEqualToString:@"mkd"]) {
        return OMCodeLanguageMarkdown;
    }
    return OMCodeLanguageUnknown;
}

static void OMApplyRegexColor(NSMutableAttributedString *text,
                              NSString *pattern,
                              NSRegularExpressionOptions options,
                              NSColor *color)
{
    if (text == nil || color == nil || [text length] == 0) {
        return;
    }
    NSRegularExpression *regex = OMCachedRegex(pattern, options);
    if (regex == nil) {
        return;
    }
    NSRange fullRange = NSMakeRange(0, [text length]);
    NSArray *matches = [regex matchesInString:[text string] options:0 range:fullRange];
    for (NSTextCheckingResult *match in matches) {
        NSRange range = [match range];
        if (range.length == 0) {
            continue;
        }
        [text addAttribute:NSForegroundColorAttributeName value:color range:range];
    }
}

static void OMApplyCFamilySyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                             OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*#\\s*[A-Za-z_][A-Za-z0-9_]*.*$",
                      0,
                      palette.directiveColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:@interface|@implementation|@end|@property|@synthesize|@dynamic|@protocol|@class|@selector|@autoreleasepool|id|instancetype|self|super|nil|YES|NO|if|else|for|while|switch|case|break|continue|return|typedef|struct|enum|static|const|void|int|float|double|char|long|short|unsigned|signed|BOOL|SEL|Class|namespace|template|typename|using|public|private|protected|virtual|override|constexpr|auto|new|delete|this|nullptr|try|catch|throw|package|import|func|defer|select|go|chan|map|interface|impl|trait|where|match|let|mut|pub|crate|mod|fn|impl|enum|protocol|extension|guard|deinit|class|actor|async|await|yield|throws|throw|nil|true|false|var|val)\\b",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
    OMApplyRegexColor(codeSegment,
                      @"@?\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)//.*$|/\\*[\\s\\S]*?\\*/",
                      0,
                      palette.commentColor);
}

static void OMApplyPythonSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                            OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*@\\w+",
                      0,
                      palette.directiveColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\\b",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
    OMApplyRegexColor(codeSegment,
                      @"(?s)(?:'''[\\s\\S]*?'''|\"\"\"[\\s\\S]*?\"\"\"|'(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)#.*$",
                      0,
                      palette.commentColor);
}

static void OMApplyJSSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                        OMCodeSyntaxPalette palette,
                                        BOOL includeTypeScriptKeywords)
{
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:if|else|for|while|do|switch|case|break|continue|return|function|const|let|var|class|extends|new|try|catch|finally|throw|import|export|default|from|as|this|null|undefined|true|false)\\b",
                      0,
                      palette.keywordColor);
    if (includeTypeScriptKeywords) {
        OMApplyRegexColor(codeSegment,
                          @"\\b(?:interface|type|implements|enum|namespace|readonly|public|private|protected|abstract|declare|keyof|infer|unknown|never|any)\\b",
                          0,
                          palette.keywordColor);
    }
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
    OMApplyRegexColor(codeSegment,
                      @"`(?:[^`\\\\]|\\\\.)*`|\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)//.*$|/\\*[\\s\\S]*?\\*/",
                      0,
                      palette.commentColor);
}

static void OMApplyJSONSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                          OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"\"(?:[^\"\\\\]|\\\\.)*\"",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:true|false|null)\\b",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\"(?:[^\"\\\\]|\\\\.)*\"\\s*:",
                      0,
                      palette.directiveColor);
}

static void OMApplyBashSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                          OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:if|then|else|elif|fi|for|while|do|done|case|esac|function|in|select|until|time)\\b",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?",
                      0,
                      palette.directiveColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
    OMApplyRegexColor(codeSegment,
                      @"\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)#.*$",
                      0,
                      palette.commentColor);
}

static void OMApplyMarkdownSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                              OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s{0,3}#{1,6}\\s+.*$",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\[[^\\]\\n]+\\]\\([^\\)\\n]+\\)",
                      0,
                      palette.directiveColor);
    OMApplyRegexColor(codeSegment,
                      @"(?:\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__)",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"(?<!\\*)\\*[^*\\n]+\\*(?!\\*)|(?<!_)_[^_\\n]+_(?!_)",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"`[^`\\n]+`",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"\\$\\$[\\s\\S]*?\\$\\$|\\$[^$\\n]+\\$",
                      0,
                      palette.numberColor);
}

static void OMApplyYAMLSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                          OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*#.*$",
                      0,
                      palette.commentColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*-\\s+",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*[A-Za-z0-9_\\-\"']+\\s*:",
                      0,
                      palette.directiveColor);
    OMApplyRegexColor(codeSegment,
                      @"\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:true|false|null|yes|no|on|off)\\b",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|-?\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
}

static void OMApplyTOMLSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                          OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*#.*$",
                      0,
                      palette.commentColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*\\[[^\\]\\n]+\\]",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)^\\s*[A-Za-z0-9_\\.-]+\\s*=",
                      0,
                      palette.directiveColor);
    OMApplyRegexColor(codeSegment,
                      @"\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:true|false)\\b",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|-?\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
}

static void OMApplySQLSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                         OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:SELECT|FROM|WHERE|ORDER|BY|GROUP|HAVING|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AS|DISTINCT|LIMIT|OFFSET|UNION|ALL|AND|OR|NOT|NULL|IS|IN|LIKE|CASE|WHEN|THEN|ELSE|END)\\b",
                      NSRegularExpressionCaseInsensitive,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|-?\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
    OMApplyRegexColor(codeSegment,
                      @"'(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\"",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)--.*$|/\\*[\\s\\S]*?\\*/",
                      0,
                      palette.commentColor);
}

static void OMApplyRubySyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                          OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:def|class|module|end|if|elsif|else|unless|case|when|while|until|for|in|do|break|next|redo|retry|return|yield|super|self|nil|true|false|and|or|not|begin|rescue|ensure|require|include|extend|attr_reader|attr_writer|attr_accessor)\\b",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|-?\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
    OMApplyRegexColor(codeSegment,
                      @"\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"(?m)#.*$",
                      0,
                      palette.commentColor);
    OMApplyRegexColor(codeSegment,
                      @"\\:[A-Za-z_][A-Za-z0-9_]*",
                      0,
                      palette.directiveColor);
}

static void OMApplyMarkupSyntaxHighlighting(NSMutableAttributedString *codeSegment,
                                            OMCodeSyntaxPalette palette)
{
    OMApplyRegexColor(codeSegment,
                      @"(?m)<!--.*?-->|/\\*[\\s\\S]*?\\*/",
                      NSRegularExpressionDotMatchesLineSeparators,
                      palette.commentColor);
    OMApplyRegexColor(codeSegment,
                      @"</?[A-Za-z][A-Za-z0-9:_-]*",
                      0,
                      palette.keywordColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b[A-Za-z_:][A-Za-z0-9_:\\-]*\\s*=",
                      0,
                      palette.directiveColor);
    OMApplyRegexColor(codeSegment,
                      @"\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
                      0,
                      palette.stringColor);
    OMApplyRegexColor(codeSegment,
                      @"\\b(?:0x[0-9A-Fa-f]+|-?\\d+(?:\\.\\d+)?)\\b",
                      0,
                      palette.numberColor);
}

static void OMApplyCodeSyntaxHighlighting(cmark_node *codeBlockNode,
                                          NSMutableAttributedString *codeSegment,
                                          NSColor *backgroundColor,
                                          const OMRenderContext *renderContext)
{
    if (!OMShouldApplyCodeSyntaxHighlighting(renderContext)) {
        return;
    }

    NSString *token = OMPrimaryFenceToken(codeBlockNode);
    OMCodeLanguage language = OMLanguageForFenceToken(token);
    if (language == OMCodeLanguageUnknown) {
        return;
    }

    OMCodeSyntaxPalette palette = OMCodePaletteForBackground(backgroundColor);

    [codeSegment beginEditing];
    switch (language) {
        case OMCodeLanguageCFamily:
            OMApplyCFamilySyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguagePython:
            OMApplyPythonSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageJavaScript:
            OMApplyJSSyntaxHighlighting(codeSegment, palette, NO);
            break;
        case OMCodeLanguageTypeScript:
            OMApplyJSSyntaxHighlighting(codeSegment, palette, YES);
            break;
        case OMCodeLanguageJSON:
            OMApplyJSONSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageBash:
            OMApplyBashSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageMarkdown:
            OMApplyMarkdownSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageYAML:
            OMApplyYAMLSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageTOML:
            OMApplyTOMLSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageSQL:
            OMApplySQLSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageRuby:
            OMApplyRubySyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageMarkup:
            OMApplyMarkupSyntaxHighlighting(codeSegment, palette);
            break;
        case OMCodeLanguageUnknown:
        default:
            break;
    }
    [codeSegment endEditing];
}

static void OMAppendString(NSMutableAttributedString *output,
                           NSString *string,
                           NSDictionary *attributes)
{
    if (string == nil || [string length] == 0) {
        return;
    }
    NSAttributedString *segment = [[[NSAttributedString alloc] initWithString:string
                                                                    attributes:attributes] autorelease];
    [output appendAttributedString:segment];
}

static void OMAppendAttributedSegment(NSMutableAttributedString *output,
                                      NSAttributedString *segment)
{
    if (segment == nil || [segment length] == 0) {
        return;
    }
    [output appendAttributedString:segment];
}

static NSMutableParagraphStyle *OMParagraphStyleWithIndent(CGFloat firstIndent,
                                                           CGFloat headIndent,
                                                           CGFloat spacingAfter,
                                                           CGFloat lineSpacing,
                                                           CGFloat lineHeightMultiple,
                                                           CGFloat fontSize)
{
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setFirstLineHeadIndent:firstIndent];
    [style setHeadIndent:headIndent];
    [style setParagraphSpacing:spacingAfter];
    [style setLineSpacing:lineSpacing];
    [style setLineHeightMultiple:lineHeightMultiple];
    if (fontSize > 0.0 && lineHeightMultiple > 0.0) {
        CGFloat lineHeight = fontSize * lineHeightMultiple;
        [style setMinimumLineHeight:lineHeight];
    }
    return style;
}

static void OMTrimTrailingNewlines(NSMutableAttributedString *output)
{
    while ([output length] > 0) {
        unichar ch = [[output string] characterAtIndex:[output length] - 1];
        if (ch == '\n') {
            [output deleteCharactersInRange:NSMakeRange([output length] - 1, 1)];
        } else {
            break;
        }
    }
}

static NSArray *OMSourceLinesForMarkdown(NSString *markdown)
{
    NSMutableArray *lines = [NSMutableArray array];
    if (markdown == nil || [markdown length] == 0) {
        return lines;
    }

    NSUInteger totalLength = [markdown length];
    NSUInteger cursor = 0;
    while (cursor < totalLength) {
        NSRange lineRange = [markdown lineRangeForRange:NSMakeRange(cursor, 0)];
        NSUInteger lineStart = lineRange.location;
        NSUInteger contentLength = lineRange.length;

        while (contentLength > 0) {
            unichar ch = [markdown characterAtIndex:lineStart + contentLength - 1];
            if (ch == '\n' || ch == '\r') {
                contentLength -= 1;
                continue;
            }
            break;
        }

        NSString *line = [markdown substringWithRange:NSMakeRange(lineStart, contentLength)];
        [lines addObject:line];
        cursor = NSMaxRange(lineRange);
    }
    return lines;
}

static NSString *OMNormalizedBlockIDText(NSString *text)
{
    if (text == nil || [text length] == 0) {
        return @"";
    }

    NSMutableString *normalized = [NSMutableString stringWithCapacity:[text length]];
    NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];
    BOOL previousWasSpace = YES;
    NSUInteger length = [text length];
    NSUInteger i = 0;
    for (; i < length; i++) {
        unichar ch = [text characterAtIndex:i];
        if ([alphanumeric characterIsMember:ch]) {
            NSString *s = [[NSString stringWithCharacters:&ch length:1] lowercaseString];
            [normalized appendString:s];
            previousWasSpace = NO;
        } else if (!previousWasSpace) {
            [normalized appendString:@" "];
            previousWasSpace = YES;
        }
    }

    while ([normalized hasSuffix:@" "]) {
        [normalized deleteCharactersInRange:NSMakeRange([normalized length] - 1, 1)];
    }
    return normalized;
}

static BOOL OMNodeLineBounds(cmark_node *node, NSUInteger *startLineOut, NSUInteger *endLineOut)
{
    if (node == NULL) {
        return NO;
    }

    int startLine = cmark_node_get_start_line(node);
    int endLine = cmark_node_get_end_line(node);
    if (startLine <= 0) {
        return NO;
    }
    if (endLine < startLine) {
        endLine = startLine;
    }

    if (startLineOut != NULL) {
        *startLineOut = (NSUInteger)startLine;
    }
    if (endLineOut != NULL) {
        *endLineOut = (NSUInteger)endLine;
    }
    return YES;
}

static NSString *OMBlockSignatureForLineRange(NSArray *sourceLines,
                                              NSUInteger startLine,
                                              NSUInteger endLine)
{
    NSUInteger count = [sourceLines count];
    if (count == 0 || startLine == 0) {
        return @"";
    }
    if (startLine > count) {
        return @"";
    }
    if (endLine < startLine) {
        endLine = startLine;
    }
    if (endLine > count) {
        endLine = count;
    }

    NSMutableString *joined = [NSMutableString string];
    NSUInteger line = startLine;
    for (; line <= endLine; line++) {
        NSString *lineText = [sourceLines objectAtIndex:line - 1];
        NSString *trimmed = [lineText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([joined length] > 0) {
            [joined appendString:@"\n"];
        }
        [joined appendString:trimmed];
    }
    return OMNormalizedBlockIDText(joined);
}

static NSString *OMStableBlockIDForNode(cmark_node *node,
                                        const OMRenderContext *renderContext)
{
    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    if (node == NULL || sourceLines == nil) {
        return nil;
    }

    NSUInteger startLine = 0;
    NSUInteger endLine = 0;
    if (!OMNodeLineBounds(node, &startLine, &endLine)) {
        return nil;
    }

    NSString *signature = OMBlockSignatureForLineRange(sourceLines, startLine, endLine);
    if (signature == nil || [signature length] == 0) {
        signature = @"_";
    }
    return [NSString stringWithFormat:@"%d|%@", (int)cmark_node_get_type(node), signature];
}

static void OMRecordBlockAnchor(cmark_node *node,
                                NSUInteger targetStart,
                                NSUInteger targetEnd,
                                const OMRenderContext *renderContext)
{
    NSMutableArray *blockAnchors = renderContext != NULL ? renderContext->blockAnchors : nil;
    if (blockAnchors == nil || node == NULL) {
        return;
    }
    if (targetEnd <= targetStart) {
        return;
    }

    NSUInteger sourceStartLine = 0;
    NSUInteger sourceEndLine = 0;
    if (!OMNodeLineBounds(node, &sourceStartLine, &sourceEndLine)) {
        return;
    }

    NSMutableDictionary *anchor = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedInteger:sourceStartLine], OMMarkdownRendererAnchorSourceStartLineKey,
                                   [NSNumber numberWithUnsignedInteger:sourceEndLine], OMMarkdownRendererAnchorSourceEndLineKey,
                                   [NSNumber numberWithUnsignedInteger:targetStart], OMMarkdownRendererAnchorTargetStartKey,
                                   [NSNumber numberWithUnsignedInteger:(targetEnd - targetStart)], OMMarkdownRendererAnchorTargetLengthKey,
                                   nil];
    NSString *blockID = OMStableBlockIDForNode(node, renderContext);
    if (blockID != nil && [blockID length] > 0) {
        [anchor setObject:blockID forKey:OMMarkdownRendererAnchorBlockIDKey];
    }
    [blockAnchors addObject:anchor];
}

static void OMRenderInlines(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            CGFloat scale,
                            const OMRenderContext *renderContext);

static void OMRenderBlocks(cmark_node *node,
                           OMTheme *theme,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *attributes,
                           NSMutableArray *codeRanges,
                           NSMutableArray *blockquoteRanges,
                           NSMutableArray *listStack,
                           NSUInteger quoteLevel,
                           CGFloat scale,
                           CGFloat layoutWidth,
                           const OMRenderContext *renderContext);

static NSMutableDictionary *OMListContext(NSMutableArray *listStack)
{
    return [listStack count] > 0 ? [listStack lastObject] : nil;
}

static BOOL OMIsTightList(NSMutableArray *listStack)
{
    NSMutableDictionary *list = OMListContext(listStack);
    if (list == nil) {
        return NO;
    }
    return [[list objectForKey:@"tight"] boolValue];
}

static NSString *OMListPrefix(NSMutableArray *listStack)
{
    NSMutableDictionary *list = OMListContext(listStack);
    if (list == nil) {
        return @"";
    }

    cmark_list_type type = (cmark_list_type)[[list objectForKey:@"type"] intValue];
    if (type == CMARK_BULLET_LIST) {
        return @"- ";
    }

    NSNumber *index = [list objectForKey:@"index"];
    if (index == nil) {
        return @"1. ";
    }
    return [NSString stringWithFormat:@"%@. ", index];
}

static void OMIncrementListIndex(NSMutableArray *listStack)
{
    NSMutableDictionary *list = OMListContext(listStack);
    if (list == nil) {
        return;
    }
    NSNumber *index = [list objectForKey:@"index"];
    if (index == nil) {
        return;
    }
    [list setObject:[NSNumber numberWithInteger:[index integerValue] + 1] forKey:@"index"];
}

static NSDictionary *OMHeadingAttributes(OMTheme *theme, NSUInteger level, CGFloat scale)
{
    static const CGFloat scales[6] = { 1.6, 1.4, 1.2, 1.1, 1.0, 0.95 };
    CGFloat baseSize = theme.baseFont != nil ? [theme.baseFont pointSize] : 14.0;
    NSUInteger idx = level > 0 ? level - 1 : 0;
    if (idx > 5) {
        idx = 5;
    }
    return [theme headingAttributesForSize:(baseSize * scales[idx] * scale)];
}

static NSString *OMRuleLineString(NSFont *font, CGFloat width)
{
    if (font == nil || width <= 0.0) {
        return @"────────────────────────────────────────────────────────";
    }

    NSDictionary *attrs = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    NSSize charSize = [@"─" sizeWithAttributes:attrs];
    CGFloat charWidth = charSize.width > 0.0 ? charSize.width : 6.0;
    NSInteger count = (NSInteger)floor(width / charWidth);
    if (count < 8) {
        count = 8;
    }

    NSMutableString *rule = [NSMutableString stringWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) {
        [rule appendString:@"─"];
    }
    return rule;
}

static NSCache *OMImageAttachmentCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    });
    return cache;
}

static dispatch_queue_t OMRemoteImageQueue(void)
{
    static dispatch_queue_t queue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.objcmarkdown.remote-images", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSMutableSet *OMPendingRemoteImageCacheKeys(void)
{
    static NSMutableSet *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [[NSMutableSet alloc] init];
    });
    return keys;
}

static NSString *OMImageAttachmentCacheKey(NSString *urlKey,
                                           CGFloat scale,
                                           CGFloat layoutWidth,
                                           BOOL allowRemoteImages)
{
    return [NSString stringWithFormat:@"%@|%.2f|%.1f|allowRemote:%d",
            urlKey,
            scale,
            layoutWidth,
            (int)(allowRemoteImages ? 1 : 0)];
}

static NSImage *OMPreparedImageForAttachment(NSImage *image,
                                             CGFloat scale,
                                             CGFloat layoutWidth)
{
    if (image == nil) {
        return nil;
    }

    NSImage *preparedImage = [[image copy] autorelease];
    NSSize imageSize = [preparedImage size];
    CGFloat maxWidth = 0.0;
    if (layoutWidth > 0.0) {
        maxWidth = floor(layoutWidth - (24.0 * scale));
    }
    if (maxWidth > 0.0 && imageSize.width > maxWidth && imageSize.width > 0.0) {
        CGFloat ratio = maxWidth / imageSize.width;
        if (ratio > 0.0) {
            CGFloat height = floor(imageSize.height * ratio);
            if (height < 1.0) {
                height = 1.0;
            }
            [preparedImage setScalesWhenResized:YES];
            [preparedImage setSize:NSMakeSize(maxWidth, height)];
        }
    }
    return preparedImage;
}

static void OMScheduleAsyncRemoteImageWarm(NSURL *url,
                                           NSString *cacheKey,
                                           CGFloat scale,
                                           CGFloat layoutWidth,
                                           BOOL allowRemoteImages)
{
    if (url == nil || cacheKey == nil || [cacheKey length] == 0) {
        return;
    }
    if (!OMURLUsesRemoteScheme(url) || !allowRemoteImages) {
        return;
    }

    NSCache *cache = OMImageAttachmentCache();
    @synchronized (cache) {
        if ([cache objectForKey:cacheKey] != nil) {
            return;
        }
    }

    NSMutableSet *pending = OMPendingRemoteImageCacheKeys();
    BOOL shouldSchedule = NO;
    @synchronized (pending) {
        if (![pending containsObject:cacheKey]) {
            [pending addObject:cacheKey];
            shouldSchedule = YES;
        }
    }
    if (!shouldSchedule) {
        return;
    }

    NSString *urlStringCopy = [[url absoluteString] copy];
    NSString *cacheKeyCopy = [cacheKey copy];
    dispatch_async(OMRemoteImageQueue(), ^{
        @autoreleasepool {
            NSURL *remoteURL = urlStringCopy != nil ? [NSURL URLWithString:urlStringCopy] : nil;
            NSData *data = nil;
            if (remoteURL != nil) {
                data = [NSData dataWithContentsOfURL:remoteURL];
            }
            NSData *dataCopy = [data retain];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (dataCopy != nil && [dataCopy length] > 0) {
                    NSImage *loaded = [[[NSImage alloc] initWithData:dataCopy] autorelease];
                    NSImage *prepared = OMPreparedImageForAttachment(loaded, scale, layoutWidth);
                    if (prepared != nil) {
                        @synchronized (cache) {
                            [cache setObject:prepared forKey:cacheKeyCopy];
                        }
                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:OMMarkdownRendererRemoteImagesDidWarmNotification
                                          object:nil];
                    }
                }
                [dataCopy release];
                @synchronized (pending) {
                    [pending removeObject:cacheKeyCopy];
                }
                [urlStringCopy release];
                [cacheKeyCopy release];
            });
        }
    });
}

static void OMAppendInlineTextFromNode(cmark_node *node, NSMutableString *buffer)
{
    if (node == NULL || buffer == nil) {
        return;
    }

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        switch (type) {
            case CMARK_NODE_TEXT:
            case CMARK_NODE_CODE:
            case CMARK_NODE_HTML_INLINE:
            case CMARK_NODE_CUSTOM_INLINE: {
                const char *literal = cmark_node_get_literal(child);
                if (literal != NULL) {
                    NSString *text = [NSString stringWithUTF8String:literal];
                    if (text != nil) {
                        [buffer appendString:text];
                    }
                }
                break;
            }
            case CMARK_NODE_SOFTBREAK:
            case CMARK_NODE_LINEBREAK:
                [buffer appendString:@" "];
                break;
            default:
                OMAppendInlineTextFromNode(child, buffer);
                break;
        }
        child = cmark_node_next(child);
    }
}

static NSString *OMInlinePlainText(cmark_node *node)
{
    NSMutableString *buffer = [NSMutableString string];
    OMAppendInlineTextFromNode(node, buffer);
    return [buffer stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

typedef NS_ENUM(NSUInteger, OMPipeTableAlignment) {
    OMPipeTableAlignmentLeft = 0,
    OMPipeTableAlignmentCenter = 1,
    OMPipeTableAlignmentRight = 2
};

static NSString *OMTrimmedCellText(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray *OMPipeTableCellsFromLine(NSString *line)
{
    NSString *trimmed = OMTrimmedCellText(line);
    if ([trimmed length] == 0) {
        return nil;
    }

    BOOL hasPipe = NO;
    NSUInteger i = 0;
    NSUInteger length = [trimmed length];
    for (; i < length; i++) {
        unichar ch = [trimmed characterAtIndex:i];
        if (ch == '\\' && (i + 1) < length && [trimmed characterAtIndex:(i + 1)] == '|') {
            i += 1;
            continue;
        }
        if (ch == '|') {
            hasPipe = YES;
            break;
        }
    }
    if (!hasPipe) {
        return nil;
    }

    BOOL startsWithPipe = ([trimmed characterAtIndex:0] == '|');
    BOOL endsWithPipe = ([trimmed characterAtIndex:(length - 1)] == '|');
    NSMutableArray *rawCells = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];

    i = 0;
    for (; i < length; i++) {
        unichar ch = [trimmed characterAtIndex:i];
        if (ch == '\\' && (i + 1) < length && [trimmed characterAtIndex:(i + 1)] == '|') {
            [current appendString:@"|"];
            i += 1;
            continue;
        }
        if (ch == '|') {
            [rawCells addObject:[NSString stringWithString:current]];
            [current setString:@""];
            continue;
        }
        [current appendFormat:@"%C", ch];
    }
    [rawCells addObject:[NSString stringWithString:current]];

    if (startsWithPipe && [rawCells count] > 0) {
        NSString *first = OMTrimmedCellText([rawCells objectAtIndex:0]);
        if ([first length] == 0) {
            [rawCells removeObjectAtIndex:0];
        }
    }
    if (endsWithPipe && [rawCells count] > 0) {
        NSString *last = OMTrimmedCellText([rawCells lastObject]);
        if ([last length] == 0) {
            [rawCells removeLastObject];
        }
    }
    if ([rawCells count] == 0) {
        return nil;
    }

    NSMutableArray *cells = [NSMutableArray arrayWithCapacity:[rawCells count]];
    for (NSString *raw in rawCells) {
        [cells addObject:OMTrimmedCellText(raw)];
    }
    return cells;
}

static BOOL OMPipeTableAlignmentFromSeparatorCell(NSString *cell, OMPipeTableAlignment *alignmentOut)
{
    NSString *trimmed = OMTrimmedCellText(cell);
    if ([trimmed length] == 0) {
        return NO;
    }

    BOOL hasLeadingColon = [trimmed hasPrefix:@":"];
    BOOL hasTrailingColon = [trimmed hasSuffix:@":"];
    NSUInteger start = hasLeadingColon ? 1 : 0;
    NSUInteger end = [trimmed length] - (hasTrailingColon ? 1 : 0);
    if (end <= start) {
        return NO;
    }

    NSString *core = [trimmed substringWithRange:NSMakeRange(start, end - start)];
    if ([core length] < 3) {
        return NO;
    }
    NSUInteger index = 0;
    for (; index < [core length]; index++) {
        if ([core characterAtIndex:index] != '-') {
            return NO;
        }
    }

    OMPipeTableAlignment alignment = OMPipeTableAlignmentLeft;
    if (hasLeadingColon && hasTrailingColon) {
        alignment = OMPipeTableAlignmentCenter;
    } else if (hasTrailingColon) {
        alignment = OMPipeTableAlignmentRight;
    }
    if (alignmentOut != NULL) {
        *alignmentOut = alignment;
    }
    return YES;
}

static BOOL OMPipeTableParseFromLines(NSArray *candidateLines,
                                      NSArray **rowsOut,
                                      NSArray **alignmentsOut)
{
    if (candidateLines == nil || [candidateLines count] < 2) {
        return NO;
    }

    NSMutableArray *lines = [NSMutableArray arrayWithArray:candidateLines];
    while ([lines count] > 0 && [OMTrimmedCellText([lines objectAtIndex:0]) length] == 0) {
        [lines removeObjectAtIndex:0];
    }
    while ([lines count] > 0 && [OMTrimmedCellText([lines lastObject]) length] == 0) {
        [lines removeLastObject];
    }
    if ([lines count] < 2) {
        return NO;
    }

    NSArray *headerCells = OMPipeTableCellsFromLine([lines objectAtIndex:0]);
    NSArray *separatorCells = OMPipeTableCellsFromLine([lines objectAtIndex:1]);
    if (headerCells == nil || separatorCells == nil) {
        return NO;
    }

    NSUInteger columnCount = [headerCells count];
    if (columnCount == 0 || [separatorCells count] != columnCount) {
        return NO;
    }

    NSMutableArray *alignments = [NSMutableArray arrayWithCapacity:columnCount];
    for (NSString *separatorCell in separatorCells) {
        OMPipeTableAlignment alignment = OMPipeTableAlignmentLeft;
        if (!OMPipeTableAlignmentFromSeparatorCell(separatorCell, &alignment)) {
            return NO;
        }
        [alignments addObject:[NSNumber numberWithUnsignedInteger:alignment]];
    }

    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:headerCells];
    NSUInteger lineIndex = 2;
    for (; lineIndex < [lines count]; lineIndex++) {
        NSString *line = [lines objectAtIndex:lineIndex];
        if ([OMTrimmedCellText(line) length] == 0) {
            continue;
        }

        NSArray *parsedCells = OMPipeTableCellsFromLine(line);
        if (parsedCells == nil) {
            return NO;
        }
        NSMutableArray *cells = [NSMutableArray arrayWithArray:parsedCells];
        while ([cells count] < columnCount) {
            [cells addObject:@""];
        }
        if ([cells count] > columnCount) {
            NSMutableArray *normalized = [NSMutableArray arrayWithCapacity:columnCount];
            NSUInteger colIndex = 0;
            for (; colIndex + 1 < columnCount; colIndex++) {
                [normalized addObject:[cells objectAtIndex:colIndex]];
            }
            NSArray *overflow = [cells subarrayWithRange:NSMakeRange(columnCount - 1, [cells count] - (columnCount - 1))];
            [normalized addObject:[overflow componentsJoinedByString:@" | "]];
            cells = normalized;
        }
        [rows addObject:cells];
    }

    if (rowsOut != NULL) {
        *rowsOut = rows;
    }
    if (alignmentsOut != NULL) {
        *alignmentsOut = alignments;
    }
    return YES;
}

static BOOL OMPipeTableDataForParagraphNode(cmark_node *node,
                                            const OMRenderContext *renderContext,
                                            NSArray **rowsOut,
                                            NSArray **alignmentsOut)
{
    if (node == NULL || renderContext == NULL || renderContext->sourceLines == nil) {
        return NO;
    }

    NSUInteger startLine = 0;
    NSUInteger endLine = 0;
    if (!OMNodeLineBounds(node, &startLine, &endLine)) {
        return NO;
    }

    NSArray *sourceLines = renderContext->sourceLines;
    if (startLine == 0 || startLine > [sourceLines count]) {
        return NO;
    }
    if (endLine < startLine) {
        endLine = startLine;
    }
    if (endLine > [sourceLines count]) {
        endLine = [sourceLines count];
    }

    NSRange range = NSMakeRange(startLine - 1, endLine - startLine + 1);
    NSArray *candidateLines = [sourceLines subarrayWithRange:range];
    return OMPipeTableParseFromLines(candidateLines, rowsOut, alignmentsOut);
}

static CGFloat OMPipeTableHorizontalPadding(CGFloat scale)
{
    CGFloat padding = 10.0 * scale;
    if (padding < 6.0) {
        padding = 6.0;
    }
    return padding;
}

static CGFloat OMPipeTableAverageCharacterWidth(NSFont *font)
{
    if (font == nil) {
        return 7.0;
    }

    NSDictionary *attrs = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    NSString *sample = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSSize sampleSize = [sample sizeWithAttributes:attrs];
    CGFloat width = [sample length] > 0 ? (sampleSize.width / (CGFloat)[sample length]) : 0.0;
    if (width <= 0.0) {
        width = [font pointSize] * 0.52;
    }
    if (width <= 0.0) {
        width = 7.0;
    }
    return width;
}

static CGFloat OMPipeTableEstimatedGridWidth(NSArray *columnWidths,
                                             NSFont *tableFont,
                                             CGFloat cellHorizontalPadding,
                                             CGFloat scale)
{
    if (columnWidths == nil || [columnWidths count] == 0) {
        return 0.0;
    }
    CGFloat charWidth = 0.0;
    if (tableFont != nil) {
        NSDictionary *attrs = [NSDictionary dictionaryWithObject:tableFont forKey:NSFontAttributeName];
        charWidth = [@" " sizeWithAttributes:attrs].width;
    }
    if (charWidth <= 0.0) {
        charWidth = OMPipeTableAverageCharacterWidth(tableFont);
    }
    CGFloat total = 0.0;
    for (NSNumber *value in columnWidths) {
        NSUInteger width = [value unsignedIntegerValue];
        if (width < 3) {
            width = 3;
        }
        total += ((CGFloat)width * charWidth) + (cellHorizontalPadding * 2.0);
    }
    total += 2.0 * scale;
    return total;
}

static CGFloat OMPipeTableMinimumReadableGridWidth(NSUInteger columnCount,
                                                   CGFloat cellHorizontalPadding,
                                                   CGFloat scale)
{
    if (columnCount == 0) {
        return 0.0;
    }

    CGFloat minColumnTextWidth = 72.0 * scale;
    if (columnCount >= 4) {
        minColumnTextWidth = 64.0 * scale;
    }
    return ((CGFloat)columnCount * (minColumnTextWidth + (cellHorizontalPadding * 2.0))) + (2.0 * scale);
}

static BOOL OMPipeTableNeedsStackedFallback(NSArray *columnWidths,
                                            CGFloat layoutWidth,
                                            CGFloat indent,
                                            NSFont *tableFont,
                                            CGFloat cellHorizontalPadding,
                                            CGFloat scale)
{
    if (columnWidths == nil || [columnWidths count] == 0) {
        return NO;
    }
    if (layoutWidth <= 0.0) {
        return NO;
    }

    CGFloat availableWidth = layoutWidth - indent - (16.0 * scale);
    if (availableWidth <= 0.0) {
        return YES;
    }
    CGFloat minimumReadableWidth = OMPipeTableMinimumReadableGridWidth([columnWidths count],
                                                                        cellHorizontalPadding,
                                                                        scale);
    if (availableWidth < minimumReadableWidth) {
        return YES;
    }

    CGFloat estimatedWidth = OMPipeTableEstimatedGridWidth(columnWidths,
                                                           tableFont,
                                                           cellHorizontalPadding,
                                                           scale);
    if (estimatedWidth <= 0.0) {
        return NO;
    }
    return estimatedWidth > (availableWidth * 1.03);
}

static CGFloat OMPipeTableTextWidth(NSString *text, NSFont *font)
{
    if (text == nil || [text length] == 0) {
        return 0.0;
    }
    if (font == nil) {
        return (CGFloat)[text length] * 7.0;
    }
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    NSSize size = [text sizeWithAttributes:attrs];
    return size.width;
}

static NSUInteger OMPipeTableWidthUnitsForText(NSString *text,
                                               NSFont *font,
                                               CGFloat spaceWidth)
{
    CGFloat width = OMPipeTableTextWidth(text, font);
    if (width <= 0.0) {
        return 0;
    }
    if (spaceWidth <= 0.0) {
        spaceWidth = 4.0;
    }
    return (NSUInteger)ceil(width / spaceWidth);
}

static NSString *OMPipeTableColumnLabel(NSArray *headers, NSUInteger columnIndex)
{
    if (headers != nil && columnIndex < [headers count]) {
        NSString *header = OMTrimmedCellText([headers objectAtIndex:columnIndex]);
        if ([header length] > 0) {
            return header;
        }
    }
    return [NSString stringWithFormat:@"Column %lu", (unsigned long)(columnIndex + 1)];
}

static NSString *OMPipeTableStackedText(NSArray *rows)
{
    if (rows == nil || [rows count] == 0) {
        return @"";
    }

    NSArray *headers = [rows objectAtIndex:0];
    NSUInteger columnCount = [headers count];
    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger rowIndex = 1;
    for (; rowIndex < [rows count]; rowIndex++) {
        NSArray *row = [rows objectAtIndex:rowIndex];
        [lines addObject:[NSString stringWithFormat:@"Row %lu", (unsigned long)rowIndex]];
        NSUInteger columnIndex = 0;
        for (; columnIndex < columnCount; columnIndex++) {
            NSString *label = OMPipeTableColumnLabel(headers, columnIndex);
            NSString *value = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : @"");
            [lines addObject:[NSString stringWithFormat:@"  %@: %@", label, value]];
        }
        if (rowIndex + 1 < [rows count]) {
            [lines addObject:@""];
        }
    }

    if ([lines count] == 0) {
        [lines addObject:[headers componentsJoinedByString:@" | "]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *OMPipeTableVisibleCellText(NSString *cellMarkdown)
{
    NSString *normalized = (cellMarkdown != nil ? cellMarkdown : @"");
    if ([normalized length] == 0) {
        return @"";
    }

    NSData *data = [normalized dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return OMTrimmedCellText(normalized);
    }

    const char *bytes = (const char *)[data bytes];
    NSUInteger length = [data length];
    cmark_node *document = cmark_parse_document(bytes, length, (int)CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return OMTrimmedCellText(normalized);
    }

    NSMutableArray *parts = [NSMutableArray array];
    cmark_node *child = cmark_node_first_child(document);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        if (type == CMARK_NODE_PARAGRAPH) {
            NSString *plain = OMInlinePlainText(child);
            if (plain != nil && [plain length] > 0) {
                [parts addObject:plain];
            }
        }
        child = cmark_node_next(child);
    }
    cmark_node_free(document);

    if ([parts count] == 0) {
        return OMTrimmedCellText(normalized);
    }
    return [[parts componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray *OMPipeTableVisibleRows(NSArray *rows)
{
    if (rows == nil || [rows count] == 0) {
        return [NSArray array];
    }

    NSMutableArray *visibleRows = [NSMutableArray arrayWithCapacity:[rows count]];
    for (NSArray *row in rows) {
        NSMutableArray *visibleCells = [NSMutableArray arrayWithCapacity:[row count]];
        for (NSString *cell in row) {
            NSString *plain = OMPipeTableVisibleCellText(cell);
            [visibleCells addObject:(plain != nil ? plain : @"")];
        }
        [visibleRows addObject:visibleCells];
    }
    return visibleRows;
}

static BOOL OMThemeBackgroundIsDark(OMTheme *theme)
{
    if (theme == nil || theme.baseBackgroundColor == nil) {
        return NO;
    }
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!OMColorRGBA(theme.baseBackgroundColor, &red, &green, &blue, NULL)) {
        return NO;
    }
    CGFloat luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
    return luminance < 0.5;
}

static NSColor *OMPipeTableBorderColorForTheme(OMTheme *theme)
{
    if (OMThemeBackgroundIsDark(theme)) {
        return [NSColor colorWithCalibratedRed:(61.0 / 255.0)
                                         green:(68.0 / 255.0)
                                          blue:(77.0 / 255.0)
                                         alpha:1.0];
    }
    return [NSColor colorWithCalibratedRed:(208.0 / 255.0)
                                     green:(215.0 / 255.0)
                                      blue:(222.0 / 255.0)
                                     alpha:1.0];
}

static NSColor *OMPipeTableHeaderBackgroundColorForTheme(OMTheme *theme)
{
    if (OMThemeBackgroundIsDark(theme)) {
        return [NSColor colorWithCalibratedRed:(22.0 / 255.0)
                                         green:(27.0 / 255.0)
                                          blue:(34.0 / 255.0)
                                         alpha:1.0];
    }
    return [NSColor colorWithCalibratedRed:(246.0 / 255.0)
                                     green:(248.0 / 255.0)
                                      blue:(250.0 / 255.0)
                                     alpha:1.0];
}

static NSColor *OMPipeTableBodyBackgroundColorForTheme(OMTheme *theme)
{
    if (OMThemeBackgroundIsDark(theme)) {
        return [NSColor colorWithCalibratedRed:(13.0 / 255.0)
                                         green:(17.0 / 255.0)
                                          blue:(23.0 / 255.0)
                                         alpha:1.0];
    }
    if (theme != nil && theme.baseBackgroundColor != nil) {
        return theme.baseBackgroundColor;
    }
    return [NSColor whiteColor];
}

static NSMutableAttributedString *OMPipeTableAttributedCellContent(NSString *cellMarkdown,
                                                                   OMTheme *theme,
                                                                   NSDictionary *cellAttributes,
                                                                   CGFloat scale,
                                                                   const OMRenderContext *renderContext)
{
    NSString *normalized = (cellMarkdown != nil ? cellMarkdown : @"");
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    if ([normalized length] == 0) {
        return result;
    }

    NSData *data = [normalized dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        OMAppendString(result, normalized, cellAttributes);
        return result;
    }

    const char *bytes = (const char *)[data bytes];
    NSUInteger length = [data length];
    NSUInteger cmarkOptions = (renderContext != NULL && renderContext->parsingOptions != nil)
                              ? [renderContext->parsingOptions cmarkOptions]
                              : (NSUInteger)CMARK_OPT_DEFAULT;
    cmark_node *document = cmark_parse_document(bytes, length, (int)cmarkOptions);
    if (document == NULL) {
        OMAppendString(result, normalized, cellAttributes);
        return result;
    }

    NSMutableDictionary *inlineAttributes = [NSMutableDictionary dictionaryWithDictionary:cellAttributes];
    BOOL rendered = NO;
    cmark_node *child = cmark_node_first_child(document);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        if (type == CMARK_NODE_PARAGRAPH) {
            OMRenderInlines(child, theme, result, inlineAttributes, scale, renderContext);
            rendered = YES;
        }
        child = cmark_node_next(child);
    }
    if (!rendered) {
        OMAppendString(result, normalized, cellAttributes);
    }
    cmark_node_free(document);
    return result;
}

static NSFont *OMPipeTableGridFont(NSFont *fallbackFont, CGFloat size)
{
    CGFloat resolvedSize = size;
    if (resolvedSize <= 0.0 && fallbackFont != nil) {
        resolvedSize = [fallbackFont pointSize];
    }
    if (resolvedSize <= 0.0) {
        resolvedSize = 14.0;
    }

    if (fallbackFont != nil) {
        NSFont *resized = [NSFont fontWithName:[fallbackFont fontName] size:resolvedSize];
        if (resized != nil) {
            return resized;
        }
    }

    NSArray *fallbackNames = [NSArray arrayWithObjects:
                              @"Helvetica Neue",
                              @"Helvetica",
                              @"Arial",
                              @"Liberation Sans",
                              @"DejaVu Sans",
                              @"Sans",
                              nil];
    for (NSString *fontName in fallbackNames) {
        NSFont *candidate = [NSFont fontWithName:fontName size:resolvedSize];
        if (candidate != nil) {
            return candidate;
        }
    }
    return [NSFont systemFontOfSize:resolvedSize];
}

static void OMPipeTableNormalizeCellSegment(NSMutableAttributedString *segment)
{
    if (segment == nil || [segment length] == 0) {
        return;
    }

    NSInteger index = (NSInteger)[segment length] - 1;
    for (; index >= 0; index--) {
        unichar ch = [[segment string] characterAtIndex:(NSUInteger)index];
        if (ch == '\n' || ch == '\r' || ch == '\t') {
            [segment replaceCharactersInRange:NSMakeRange((NSUInteger)index, 1) withString:@" "];
        }
    }
}

static NSTextAlignment OMPipeTableTextAlignment(OMPipeTableAlignment alignment)
{
    switch (alignment) {
        case OMPipeTableAlignmentCenter:
            return NSCenterTextAlignment;
        case OMPipeTableAlignmentRight:
            return NSRightTextAlignment;
        case OMPipeTableAlignmentLeft:
        default:
            return NSLeftTextAlignment;
    }
}

static NSMutableArray *OMPipeTableColumnWidthsInPoints(NSArray *visibleRows,
                                                       NSUInteger columnCount,
                                                       NSFont *tableFont,
                                                       NSFont *headerFont,
                                                       CGFloat scale)
{
    NSMutableArray *widths = [NSMutableArray arrayWithCapacity:columnCount];
    CGFloat minimumWidth = 44.0 * scale;
    if (minimumWidth < 28.0) {
        minimumWidth = 28.0;
    }
    NSUInteger columnIndex = 0;
    for (; columnIndex < columnCount; columnIndex++) {
        [widths addObject:[NSNumber numberWithDouble:minimumWidth]];
    }

    NSUInteger rowIndex = 0;
    for (; rowIndex < [visibleRows count]; rowIndex++) {
        NSArray *row = [visibleRows objectAtIndex:rowIndex];
        NSFont *rowFont = (rowIndex == 0 && headerFont != nil) ? headerFont : tableFont;
        NSDictionary *measureAttrs = nil;
        if (rowFont != nil) {
            measureAttrs = [NSDictionary dictionaryWithObject:rowFont forKey:NSFontAttributeName];
        }

        columnIndex = 0;
        for (; columnIndex < columnCount; columnIndex++) {
            NSString *text = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : @"");
            if (text == nil) {
                text = @"";
            }
            NSSize textSize = [text sizeWithAttributes:measureAttrs];
            CGFloat measured = ceil(textSize.width);
            if (measured < minimumWidth) {
                measured = minimumWidth;
            }
            CGFloat existing = [[widths objectAtIndex:columnIndex] doubleValue];
            if (measured > existing) {
                [widths replaceObjectAtIndex:columnIndex
                                  withObject:[NSNumber numberWithDouble:measured]];
            }
        }
    }
    return widths;
}

static NSMutableArray *OMPipeTableAttributedColumnWidthsInPoints(NSArray *attributedRows,
                                                                 NSUInteger columnCount,
                                                                 CGFloat scale)
{
    NSMutableArray *widths = [NSMutableArray arrayWithCapacity:columnCount];
    CGFloat minimumWidth = 44.0 * scale;
    if (minimumWidth < 28.0) {
        minimumWidth = 28.0;
    }
    NSUInteger columnIndex = 0;
    for (; columnIndex < columnCount; columnIndex++) {
        [widths addObject:[NSNumber numberWithDouble:minimumWidth]];
    }

    NSUInteger rowIndex = 0;
    for (; rowIndex < [attributedRows count]; rowIndex++) {
        NSArray *row = [attributedRows objectAtIndex:rowIndex];
        columnIndex = 0;
        for (; columnIndex < columnCount; columnIndex++) {
            NSAttributedString *segment = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : nil);
            CGFloat measured = 0.0;
            if (segment != nil && [segment length] > 0) {
                NSSize textSize = [segment size];
                // Small guard band prevents edge clipping from font metric rounding.
                measured = ceil(textSize.width + (1.0 * scale));
            }
            if (measured < minimumWidth) {
                measured = minimumWidth;
            }
            CGFloat existing = [[widths objectAtIndex:columnIndex] doubleValue];
            if (measured > existing) {
                [widths replaceObjectAtIndex:columnIndex
                                  withObject:[NSNumber numberWithDouble:measured]];
            }
        }
    }
    return widths;
}

static void OMPipeTableConstrainColumnWidths(NSMutableArray *columnWidths,
                                             CGFloat maxContentWidth,
                                             CGFloat minimumColumnWidth)
{
    if (columnWidths == nil || [columnWidths count] == 0 || maxContentWidth <= 0.0) {
        return;
    }
    if (minimumColumnWidth < 24.0) {
        minimumColumnWidth = 24.0;
    }

    CGFloat total = 0.0;
    for (NSNumber *value in columnWidths) {
        total += [value doubleValue];
    }
    if (total <= maxContentWidth) {
        return;
    }

    while (total > maxContentWidth) {
        NSUInteger widestIndex = NSNotFound;
        CGFloat widestWidth = 0.0;
        NSUInteger index = 0;
        for (; index < [columnWidths count]; index++) {
            CGFloat width = [[columnWidths objectAtIndex:index] doubleValue];
            if (width > minimumColumnWidth && width > widestWidth) {
                widestWidth = width;
                widestIndex = index;
            }
        }
        if (widestIndex == NSNotFound) {
            break;
        }
        CGFloat reduced = widestWidth - 1.0;
        if (reduced < minimumColumnWidth) {
            reduced = minimumColumnWidth;
        }
        [columnWidths replaceObjectAtIndex:widestIndex
                                withObject:[NSNumber numberWithDouble:reduced]];
        total -= (widestWidth - reduced);
        if ((widestWidth - reduced) <= 0.0) {
            break;
        }
    }
}

static CGFloat OMPipeTableRoundToPixel(CGFloat value)
{
    return floor(value + 0.5);
}

static NSRect OMPipeTableIntegralRect(NSRect rect)
{
    CGFloat minX = floor(rect.origin.x);
    CGFloat minY = floor(rect.origin.y);
    CGFloat maxX = ceil(rect.origin.x + rect.size.width);
    CGFloat maxY = ceil(rect.origin.y + rect.size.height);
    return NSMakeRect(minX, minY, maxX - minX, maxY - minY);
}

static BOOL OMPipeTableComputeLayout(NSArray *visibleRows,
                                     NSArray *attributedRows,
                                     NSUInteger rowCount,
                                     NSUInteger columnCount,
                                     NSFont *tableFont,
                                     NSFont *headerFont,
                                     CGFloat scale,
                                     CGFloat maxWidth,
                                     NSMutableArray **columnWidthsOut,
                                     NSMutableArray **rowHeightsOut,
                                     CGFloat *borderWidthOut,
                                     CGFloat *horizontalPaddingOut,
                                     CGFloat *verticalPaddingOut,
                                     CGFloat *totalWidthOut,
                                     CGFloat *totalHeightOut)
{
    if (visibleRows == nil || rowCount == 0 || columnCount == 0) {
        return NO;
    }

    CGFloat borderWidth = (scale >= 1.0 ? 1.0 : scale);
    if (borderWidth < 1.0) {
        borderWidth = 1.0;
    }
    CGFloat horizontalPadding = OMPipeTableRoundToPixel(12.0 * scale);
    if (horizontalPadding < 8.0) {
        horizontalPadding = 8.0;
    }
    CGFloat verticalPadding = OMPipeTableRoundToPixel(6.0 * scale);
    if (verticalPadding < 4.0) {
        verticalPadding = 4.0;
    }

    NSMutableArray *columnWidths = nil;
    if (attributedRows != nil && [attributedRows count] == rowCount) {
        columnWidths = OMPipeTableAttributedColumnWidthsInPoints(attributedRows,
                                                                 columnCount,
                                                                 scale);
    } else {
        columnWidths = OMPipeTableColumnWidthsInPoints(visibleRows,
                                                       columnCount,
                                                       tableFont,
                                                       headerFont,
                                                       scale);
    }
    CGFloat chromeWidth = ((CGFloat)columnCount * (horizontalPadding * 2.0)) +
                          ((CGFloat)(columnCount + 1) * borderWidth);
    if (maxWidth > 0.0) {
        CGFloat maxContentWidth = maxWidth - chromeWidth;
        OMPipeTableConstrainColumnWidths(columnWidths, maxContentWidth, 44.0 * scale);
    }

    CGFloat bodyLineHeight = tableFont != nil
                             ? ceil([tableFont ascender] - [tableFont descender] + [tableFont leading])
                             : ceil(16.0 * scale);
    if (bodyLineHeight < (12.0 * scale)) {
        bodyLineHeight = 12.0 * scale;
    }
    CGFloat headerLineHeight = headerFont != nil
                               ? ceil([headerFont ascender] - [headerFont descender] + [headerFont leading])
                               : bodyLineHeight;
    if (headerLineHeight < bodyLineHeight) {
        headerLineHeight = bodyLineHeight;
    }

    NSMutableArray *rowHeights = [NSMutableArray arrayWithCapacity:rowCount];
    NSUInteger rowIndex = 0;
    for (; rowIndex < rowCount; rowIndex++) {
        CGFloat lineHeight = (rowIndex == 0 ? headerLineHeight : bodyLineHeight);
        CGFloat rowHeight = ceil(lineHeight + (verticalPadding * 2.0));
        [rowHeights addObject:[NSNumber numberWithDouble:rowHeight]];
    }

    CGFloat totalContentWidth = 0.0;
    for (NSNumber *value in columnWidths) {
        totalContentWidth += [value doubleValue];
    }
    CGFloat totalWidth = ceil(totalContentWidth + chromeWidth);

    CGFloat totalRowsHeight = 0.0;
    for (NSNumber *value in rowHeights) {
        totalRowsHeight += [value doubleValue];
    }
    CGFloat totalHeight = ceil(totalRowsHeight + ((CGFloat)(rowCount + 1) * borderWidth));

    if (totalWidth <= 0.0 || totalHeight <= 0.0) {
        return NO;
    }

    if (columnWidthsOut != NULL) {
        *columnWidthsOut = columnWidths;
    }
    if (rowHeightsOut != NULL) {
        *rowHeightsOut = rowHeights;
    }
    if (borderWidthOut != NULL) {
        *borderWidthOut = borderWidth;
    }
    if (horizontalPaddingOut != NULL) {
        *horizontalPaddingOut = horizontalPadding;
    }
    if (verticalPaddingOut != NULL) {
        *verticalPaddingOut = verticalPadding;
    }
    if (totalWidthOut != NULL) {
        *totalWidthOut = totalWidth;
    }
    if (totalHeightOut != NULL) {
        *totalHeightOut = totalHeight;
    }
    return YES;
}

static NSImage *OMPipeTableImageFromRows(NSArray *attributedRows,
                                         NSArray *visibleRows,
                                         NSArray *alignments,
                                         NSFont *tableFont,
                                         NSFont *headerFont,
                                         NSColor *borderColor,
                                         NSColor *headerBackgroundColor,
                                         NSColor *bodyBackgroundColor,
                                         CGFloat scale,
                                         CGFloat maxWidth)
{
    if (attributedRows == nil || [attributedRows count] == 0 ||
        alignments == nil || [alignments count] == 0) {
        return nil;
    }

    NSUInteger rowCount = [attributedRows count];
    NSUInteger columnCount = [alignments count];

    NSMutableArray *columnWidths = nil;
    NSMutableArray *rowHeights = nil;
    CGFloat borderWidth = 0.0;
    CGFloat horizontalPadding = 0.0;
    CGFloat verticalPadding = 0.0;
    CGFloat totalWidth = 0.0;
    CGFloat totalHeight = 0.0;
    if (!OMPipeTableComputeLayout(visibleRows,
                                  attributedRows,
                                  rowCount,
                                  columnCount,
                                  tableFont,
                                  headerFont,
                                  scale,
                                  maxWidth,
                                  &columnWidths,
                                  &rowHeights,
                                  &borderWidth,
                                  &horizontalPadding,
                                  &verticalPadding,
                                  &totalWidth,
                                  &totalHeight)) {
        return nil;
    }

    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(totalWidth, totalHeight)] autorelease];
    [image lockFocus];

    NSColor *resolvedBorderColor = (borderColor != nil ? borderColor : [NSColor lightGrayColor]);
    [resolvedBorderColor setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, totalWidth, totalHeight));

    CGFloat y = totalHeight - borderWidth;
    NSUInteger rowIndex = 0;
    for (; rowIndex < rowCount; rowIndex++) {
        CGFloat rowHeight = [[rowHeights objectAtIndex:rowIndex] doubleValue];
        y -= rowHeight;

        NSColor *rowBackground = (rowIndex == 0 ? headerBackgroundColor : bodyBackgroundColor);
        if (rowBackground == nil) {
            rowBackground = [NSColor whiteColor];
        }

        CGFloat x = borderWidth;
        NSUInteger colIndex = 0;
        for (; colIndex < columnCount; colIndex++) {
            CGFloat contentWidth = [[columnWidths objectAtIndex:colIndex] doubleValue];
            CGFloat cellWidth = contentWidth + (horizontalPadding * 2.0);
            NSRect cellRect = NSMakeRect(x, y, cellWidth, rowHeight);
            [rowBackground setFill];
            NSRectFill(cellRect);

            NSArray *rowSegments = [attributedRows objectAtIndex:rowIndex];
            NSAttributedString *segment = (colIndex < [rowSegments count] ? [rowSegments objectAtIndex:colIndex] : nil);
            if (segment != nil && [segment length] > 0) {
                NSMutableAttributedString *drawSegment = [[segment mutableCopy] autorelease];
                NSMutableParagraphStyle *drawStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
                OMPipeTableAlignment alignment = (OMPipeTableAlignment)[[alignments objectAtIndex:colIndex] unsignedIntegerValue];
                [drawStyle setAlignment:OMPipeTableTextAlignment(alignment)];
                [drawStyle setLineBreakMode:NSLineBreakByTruncatingTail];
                [drawSegment addAttribute:NSParagraphStyleAttributeName
                                    value:drawStyle
                                    range:NSMakeRange(0, [drawSegment length])];

                NSRect textRect = NSInsetRect(cellRect, horizontalPadding, verticalPadding);
                [drawSegment drawInRect:textRect];
            }

            x += cellWidth + borderWidth;
        }

        y -= borderWidth;
    }

    [image unlockFocus];
    return image;
}

@interface OMPipeTableAttachmentCell : NSTextAttachmentCell
{
    NSArray *_attributedRows;
    NSArray *_alignments;
    NSArray *_columnWidths;
    NSArray *_rowHeights;
    NSColor *_borderColor;
    NSColor *_headerBackgroundColor;
    NSColor *_bodyBackgroundColor;
    CGFloat _borderWidth;
    CGFloat _horizontalPadding;
    CGFloat _verticalPadding;
    NSSize _tableSize;
}
- (instancetype)initWithAttributedRows:(NSArray *)attributedRows
                            alignments:(NSArray *)alignments
                          columnWidths:(NSArray *)columnWidths
                            rowHeights:(NSArray *)rowHeights
                           borderColor:(NSColor *)borderColor
                 headerBackgroundColor:(NSColor *)headerBackgroundColor
                   bodyBackgroundColor:(NSColor *)bodyBackgroundColor
                           borderWidth:(CGFloat)borderWidth
                     horizontalPadding:(CGFloat)horizontalPadding
                       verticalPadding:(CGFloat)verticalPadding
                             tableSize:(NSSize)tableSize;
@end

@implementation OMPipeTableAttachmentCell

- (instancetype)initWithAttributedRows:(NSArray *)attributedRows
                            alignments:(NSArray *)alignments
                          columnWidths:(NSArray *)columnWidths
                            rowHeights:(NSArray *)rowHeights
                           borderColor:(NSColor *)borderColor
                 headerBackgroundColor:(NSColor *)headerBackgroundColor
                   bodyBackgroundColor:(NSColor *)bodyBackgroundColor
                           borderWidth:(CGFloat)borderWidth
                     horizontalPadding:(CGFloat)horizontalPadding
                       verticalPadding:(CGFloat)verticalPadding
                             tableSize:(NSSize)tableSize
{
    self = [super init];
    if (self != nil) {
        _attributedRows = [attributedRows copy];
        _alignments = [alignments copy];
        _columnWidths = [columnWidths copy];
        _rowHeights = [rowHeights copy];
        _borderColor = [(borderColor != nil ? borderColor : [NSColor lightGrayColor]) retain];
        _headerBackgroundColor = [(headerBackgroundColor != nil ? headerBackgroundColor : [NSColor whiteColor]) retain];
        _bodyBackgroundColor = [(bodyBackgroundColor != nil ? bodyBackgroundColor : [NSColor whiteColor]) retain];
        _borderWidth = borderWidth;
        _horizontalPadding = horizontalPadding;
        _verticalPadding = verticalPadding;
        _tableSize = tableSize;
    }
    return self;
}

- (void)dealloc
{
    [_attributedRows release];
    [_alignments release];
    [_columnWidths release];
    [_rowHeights release];
    [_borderColor release];
    [_headerBackgroundColor release];
    [_bodyBackgroundColor release];
    [super dealloc];
}

- (NSSize)cellSize
{
    return _tableSize;
}

- (void)om_drawTableInFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
    if (_attributedRows == nil || [_attributedRows count] == 0 ||
        _alignments == nil || [_alignments count] == 0 ||
        _columnWidths == nil || [_columnWidths count] == 0 ||
        _rowHeights == nil || [_rowHeights count] == 0) {
        return;
    }

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    NSRect tableRect = OMPipeTableIntegralRect(cellFrame);
    if (tableRect.size.width < _tableSize.width) {
        tableRect.size.width = _tableSize.width;
    }
    if (tableRect.size.height < _tableSize.height) {
        tableRect.size.height = _tableSize.height;
    }

    [_borderColor setFill];
    NSRectFill(tableRect);

    NSUInteger rowCount = [_attributedRows count];
    NSUInteger columnCount = [_alignments count];
    CGFloat y = flipped ? (NSMinY(tableRect) + _borderWidth) : (NSMaxY(tableRect) - _borderWidth);
    NSUInteger rowIndex = 0;
    for (; rowIndex < rowCount; rowIndex++) {
        CGFloat rowHeight = [[_rowHeights objectAtIndex:rowIndex] doubleValue];
        if (!flipped) {
            y -= rowHeight;
        }

        NSColor *rowBackground = (rowIndex == 0 ? _headerBackgroundColor : _bodyBackgroundColor);
        if (rowBackground == nil) {
            rowBackground = [NSColor whiteColor];
        }

        CGFloat x = NSMinX(tableRect) + _borderWidth;
        NSUInteger colIndex = 0;
        for (; colIndex < columnCount; colIndex++) {
            CGFloat contentWidth = [[_columnWidths objectAtIndex:colIndex] doubleValue];
            CGFloat cellWidth = contentWidth + (_horizontalPadding * 2.0);
            NSRect cellRect = OMPipeTableIntegralRect(NSMakeRect(x, y, cellWidth, rowHeight));
            [rowBackground setFill];
            NSRectFill(cellRect);

            NSArray *rowSegments = [_attributedRows objectAtIndex:rowIndex];
            NSAttributedString *segment = (colIndex < [rowSegments count] ? [rowSegments objectAtIndex:colIndex] : nil);
            if (segment != nil && [segment length] > 0) {
                NSMutableAttributedString *drawSegment = [[segment mutableCopy] autorelease];
                NSMutableParagraphStyle *drawStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
                OMPipeTableAlignment alignment = (OMPipeTableAlignment)[[_alignments objectAtIndex:colIndex] unsignedIntegerValue];
                [drawStyle setAlignment:OMPipeTableTextAlignment(alignment)];
                [drawStyle setLineBreakMode:NSLineBreakByTruncatingTail];
                [drawSegment addAttribute:NSParagraphStyleAttributeName
                                    value:drawStyle
                                    range:NSMakeRange(0, [drawSegment length])];

                NSRect textRect = OMPipeTableIntegralRect(NSInsetRect(cellRect,
                                                                      _horizontalPadding,
                                                                      _verticalPadding));
                [drawSegment drawInRect:textRect];
            }
            x += cellWidth + _borderWidth;
        }
        if (flipped) {
            y += rowHeight + _borderWidth;
        } else {
            y -= _borderWidth;
        }
    }
    [context restoreGraphicsState];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawTableInFrame:cellFrame flipped:flipped];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
{
    (void)charIndex;
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawTableInFrame:cellFrame flipped:flipped];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
        layoutManager:(NSLayoutManager *)layoutManager
{
    (void)charIndex;
    (void)layoutManager;
    BOOL flipped = (controlView != nil ? [controlView isFlipped] : NO);
    [self om_drawTableInFrame:cellFrame flipped:flipped];
}

@end

static NSAttributedString *OMPipeTableAttachmentAttributedString(NSArray *attributedRows,
                                                                 NSArray *visibleRows,
                                                                 NSArray *alignments,
                                                                 NSFont *tableFont,
                                                                 NSFont *headerFont,
                                                                 NSColor *borderColor,
                                                                 NSColor *headerBackgroundColor,
                                                                 NSColor *bodyBackgroundColor,
                                                                 CGFloat scale,
                                                                 CGFloat maxWidth,
                                                                 NSDictionary *attributes)
{
    if (attributedRows == nil || [attributedRows count] == 0 ||
        alignments == nil || [alignments count] == 0) {
        return nil;
    }

    NSUInteger rowCount = [attributedRows count];
    NSUInteger columnCount = [alignments count];
    NSMutableArray *columnWidths = nil;
    NSMutableArray *rowHeights = nil;
    CGFloat borderWidth = 0.0;
    CGFloat horizontalPadding = 0.0;
    CGFloat verticalPadding = 0.0;
    CGFloat totalWidth = 0.0;
    CGFloat totalHeight = 0.0;
    BOOL hasLayout = OMPipeTableComputeLayout(visibleRows,
                                              attributedRows,
                                              rowCount,
                                              columnCount,
                                              tableFont,
                                              headerFont,
                                              scale,
                                              maxWidth,
                                              &columnWidths,
                                              &rowHeights,
                                              &borderWidth,
                                              &horizontalPadding,
                                              &verticalPadding,
                                              &totalWidth,
                                              &totalHeight);
    if (!hasLayout) {
        return nil;
    }

    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    OMPipeTableAttachmentCell *cell = [[[OMPipeTableAttachmentCell alloc] initWithAttributedRows:attributedRows
                                                                                        alignments:alignments
                                                                                      columnWidths:columnWidths
                                                                                        rowHeights:rowHeights
                                                                                       borderColor:borderColor
                                                                             headerBackgroundColor:headerBackgroundColor
                                                                               bodyBackgroundColor:bodyBackgroundColor
                                                                                       borderWidth:borderWidth
                                                                                 horizontalPadding:horizontalPadding
                                                                                   verticalPadding:verticalPadding
                                                                                         tableSize:NSMakeSize(totalWidth, totalHeight)] autorelease];
    if (cell != nil) {
        [attachment setAttachmentCell:cell];
    } else {
        NSImage *tableImage = OMPipeTableImageFromRows(attributedRows,
                                                       visibleRows,
                                                       alignments,
                                                       tableFont,
                                                       headerFont,
                                                       borderColor,
                                                       headerBackgroundColor,
                                                       bodyBackgroundColor,
                                                       scale,
                                                       maxWidth);
        if (tableImage == nil) {
            return nil;
        }
        NSTextAttachmentCell *imageCell = [[[NSTextAttachmentCell alloc] initImageCell:tableImage] autorelease];
        [attachment setAttachmentCell:imageCell];
    }

    NSMutableDictionary *attachmentAttributes = [NSMutableDictionary dictionary];
    if (attributes != nil) {
        [attachmentAttributes addEntriesFromDictionary:attributes];
    }
    [attachmentAttributes setObject:attachment forKey:NSAttachmentAttributeName];

    unichar attachmentChar = NSAttachmentCharacter;
    NSString *attachmentString = [NSString stringWithCharacters:&attachmentChar length:1];
    return [[[NSAttributedString alloc] initWithString:attachmentString
                                            attributes:attachmentAttributes] autorelease];
}

static void OMRenderPipeTable(NSArray *rows,
                              NSArray *alignments,
                              OMTheme *theme,
                              NSMutableAttributedString *output,
                              NSMutableDictionary *attributes,
                              NSMutableArray *listStack,
                              NSUInteger quoteLevel,
                              CGFloat scale,
                              CGFloat layoutWidth,
                              const OMRenderContext *renderContext)
{
    if (rows == nil || [rows count] == 0 || alignments == nil || [alignments count] == 0) {
        return;
    }

    NSUInteger columnCount = [alignments count];
    NSArray *visibleRows = OMPipeTableVisibleRows(rows);

    NSMutableDictionary *tableAttrs = [attributes mutableCopy];
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    CGFloat tableFontSize = fontSize;
    if (tableFontSize < 12.0 * scale) {
        tableFontSize = 12.0 * scale;
    }
    NSFont *tableFont = font;
    if (tableFont == nil && theme.baseFont != nil) {
        tableFont = [NSFont fontWithName:[theme.baseFont fontName]
                                    size:[theme.baseFont pointSize] * scale];
    }
    if (tableFont == nil) {
        tableFont = [NSFont systemFontOfSize:tableFontSize];
    }
    tableFont = OMPipeTableGridFont(tableFont, tableFontSize);
    if (tableFont != nil) {
        tableFontSize = [tableFont pointSize];
        [tableAttrs setObject:tableFont forKey:NSFontAttributeName];
    }

    CGFloat spaceWidth = OMPipeTableTextWidth(@" ", tableFont);
    if (spaceWidth <= 0.0) {
        spaceWidth = 4.0;
    }
    NSFont *headerFont = tableFont != nil ? OMFontWithTraits(tableFont, NSBoldFontMask) : nil;
    if (headerFont == nil && tableFont != nil) {
        headerFont = [NSFont boldSystemFontOfSize:[tableFont pointSize]];
    }

    NSMutableArray *columnWidths = [NSMutableArray arrayWithCapacity:columnCount];
    NSUInteger colIndex = 0;
    for (; colIndex < columnCount; colIndex++) {
        [columnWidths addObject:[NSNumber numberWithUnsignedInteger:1]];
    }

    NSUInteger rowIndexForWidths = 0;
    for (; rowIndexForWidths < [visibleRows count]; rowIndexForWidths++) {
        NSArray *row = [visibleRows objectAtIndex:rowIndexForWidths];
        NSFont *rowFont = (rowIndexForWidths == 0 && headerFont != nil) ? headerFont : tableFont;
        NSUInteger column = 0;
        for (; column < columnCount; column++) {
            NSString *cell = (column < [row count] ? [row objectAtIndex:column] : @"");
            NSUInteger widthUnits = OMPipeTableWidthUnitsForText(cell, rowFont, spaceWidth);
            if (widthUnits < 1) {
                widthUnits = 1;
            }
            NSUInteger existing = [[columnWidths objectAtIndex:column] unsignedIntegerValue];
            if (widthUnits > existing) {
                [columnWidths replaceObjectAtIndex:column withObject:[NSNumber numberWithUnsignedInteger:widthUnits]];
            }
        }
    }

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale);
    NSParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 10.0 * scale, 0.0, 1.52, tableFontSize);
    [tableAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    CGFloat cellHorizontalPadding = OMPipeTableHorizontalPadding(scale);
    BOOL allowTableHorizontalOverflow = (renderContext != NULL &&
                                         renderContext->allowTableHorizontalOverflow);
    BOOL useStackedFallback = NO;
    if (!allowTableHorizontalOverflow) {
        useStackedFallback = OMPipeTableNeedsStackedFallback(columnWidths,
                                                             layoutWidth,
                                                             indent,
                                                             tableFont,
                                                             cellHorizontalPadding,
                                                             scale);
    }
    if (useStackedFallback) {
        NSString *tableText = OMPipeTableStackedText(visibleRows);
        if (font != nil) {
            [tableAttrs setObject:font forKey:NSFontAttributeName];
        }
        NSMutableAttributedString *tableSegment = [[[NSMutableAttributedString alloc] initWithString:tableText
                                                                                           attributes:tableAttrs] autorelease];
        OMAppendAttributedSegment(output, tableSegment);
        [tableAttrs release];
        if (OMIsTightList(listStack)) {
            OMAppendString(output, @"\n", attributes);
        } else {
            OMAppendString(output, @"\n\n", attributes);
        }
        return;
    }

    NSColor *borderColor = OMPipeTableBorderColorForTheme(theme);
    NSColor *headerBackgroundColor = OMPipeTableHeaderBackgroundColorForTheme(theme);
    NSColor *bodyBackgroundColor = OMPipeTableBodyBackgroundColorForTheme(theme);
    NSMutableArray *attributedRows = [NSMutableArray arrayWithCapacity:[rows count]];
    NSUInteger rowIndex = 0;
    for (; rowIndex < [rows count]; rowIndex++) {
        NSArray *row = [rows objectAtIndex:rowIndex];
        BOOL headerRow = (rowIndex == 0);
        NSMutableArray *attributedCells = [NSMutableArray arrayWithCapacity:columnCount];

        for (colIndex = 0; colIndex < columnCount; colIndex++) {
            NSString *cellText = (colIndex < [row count] ? [row objectAtIndex:colIndex] : @"");
            NSMutableDictionary *cellAttrs = [tableAttrs mutableCopy];
            if (headerRow && headerFont != nil) {
                [cellAttrs setObject:headerFont forKey:NSFontAttributeName];
            }

            NSMutableAttributedString *cellSegment = OMPipeTableAttributedCellContent(cellText,
                                                                                       theme,
                                                                                       cellAttrs,
                                                                                       scale,
                                                                                       renderContext);
            OMPipeTableNormalizeCellSegment(cellSegment);
            if ([cellSegment length] == 0) {
                OMAppendString(cellSegment, @" ", cellAttrs);
            }
            NSAttributedString *immutableCell = [[[NSAttributedString alloc] initWithAttributedString:cellSegment] autorelease];
            [attributedCells addObject:immutableCell];
            [cellAttrs release];
        }
        [attributedRows addObject:attributedCells];
    }

    CGFloat maxTableWidth = 0.0;
    if (allowTableHorizontalOverflow) {
        if (layoutWidth > 0.0) {
            CGFloat overflowGuardWidth = 4096.0 * scale;
            CGFloat layoutRelativeWidth = layoutWidth * 4.0;
            if (layoutRelativeWidth > overflowGuardWidth) {
                overflowGuardWidth = layoutRelativeWidth;
            }
            maxTableWidth = overflowGuardWidth;
        }
    } else if (layoutWidth > 0.0) {
        maxTableWidth = layoutWidth - indent - (16.0 * scale);
        if (maxTableWidth < 120.0 * scale) {
            maxTableWidth = 120.0 * scale;
        }
    }

    NSAttributedString *tableAttachment = OMPipeTableAttachmentAttributedString(attributedRows,
                                                                                visibleRows,
                                                                                alignments,
                                                                                tableFont,
                                                                                headerFont,
                                                                                borderColor,
                                                                                headerBackgroundColor,
                                                                                bodyBackgroundColor,
                                                                                scale,
                                                                                maxTableWidth,
                                                                                tableAttrs);
    if (tableAttachment != nil) {
        OMAppendAttributedSegment(output, tableAttachment);
    } else {
        NSString *tableText = OMPipeTableStackedText(visibleRows);
        OMAppendString(output, tableText, tableAttrs);
    }
    [tableAttrs release];

    if (OMIsTightList(listStack)) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static NSString *OMFallbackImageTextForNode(cmark_node *imageNode)
{
    NSString *altText = OMInlinePlainText(imageNode);
    if (altText != nil && [altText length] > 0) {
        return [NSString stringWithFormat:@"[image: %@]", altText];
    }
    return @"[image]";
}

static BOOL OMURLUsesRemoteScheme(NSURL *url)
{
    if (url == nil) {
        return NO;
    }
    NSString *scheme = [[url scheme] lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

static NSURL *OMResolvedImageURL(NSString *urlString,
                                 const OMRenderContext *renderContext)
{
    if (urlString == nil || [urlString length] == 0) {
        return nil;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url != nil && [url scheme] != nil) {
        if (!OMURLUsesAllowedImageScheme(url)) {
            return nil;
        }
        if (OMURLUsesRemoteScheme(url) && !OMShouldAllowRemoteImages(renderContext)) {
            return nil;
        }
        return [url absoluteURL];
    }

    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    NSURL *baseURL = options != nil ? [options baseURL] : nil;
    if (baseURL != nil) {
        NSURL *resolved = [NSURL URLWithString:urlString relativeToURL:baseURL];
        if (resolved != nil) {
            return [resolved absoluteURL];
        }
    }

    NSString *path = [urlString stringByRemovingPercentEncoding];
    if (path == nil || [path length] == 0) {
        path = urlString;
    }
    path = [path stringByExpandingTildeInPath];
    if (![path isAbsolutePath]) {
        if ([baseURL isFileURL]) {
            NSString *basePath = [baseURL path];
            if (basePath != nil && [basePath length] > 0) {
                path = [basePath stringByAppendingPathComponent:path];
            }
        } else {
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            path = [cwd stringByAppendingPathComponent:path];
        }
    }
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    if (!OMURLUsesAllowedImageScheme(fileURL)) {
        return nil;
    }
    return fileURL;
}

static NSImage *OMLoadImageFromURL(NSURL *url)
{
    if (url == nil) {
        return nil;
    }

    if ([url isFileURL]) {
        NSString *path = [url path];
        if (path == nil || [path length] == 0) {
            return nil;
        }
        return [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
    }
    return nil;
}

static NSURL *OMResolvedLinkURL(NSString *urlString,
                                const OMRenderContext *renderContext)
{
    if (urlString == nil || [urlString length] == 0) {
        return nil;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url != nil && [url scheme] != nil) {
        if (!OMURLUsesAllowedLinkScheme(url)) {
            return nil;
        }
        return [url absoluteURL];
    }

    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    NSURL *baseURL = options != nil ? [options baseURL] : nil;
    if (baseURL != nil) {
        NSURL *resolved = [NSURL URLWithString:urlString relativeToURL:baseURL];
        if (resolved != nil) {
            return [resolved absoluteURL];
        }
    }

    NSString *path = [urlString stringByRemovingPercentEncoding];
    if (path == nil || [path length] == 0) {
        path = urlString;
    }
    path = [path stringByExpandingTildeInPath];
    if (![path isAbsolutePath]) {
        if ([baseURL isFileURL]) {
            NSString *basePath = [baseURL path];
            if (basePath != nil && [basePath length] > 0) {
                path = [basePath stringByAppendingPathComponent:path];
            }
        } else {
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            path = [cwd stringByAppendingPathComponent:path];
        }
    }
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    if (!OMURLUsesAllowedLinkScheme(fileURL)) {
        return nil;
    }
    return fileURL;
}

static NSAttributedString *OMImageAttachmentAttributedString(cmark_node *imageNode,
                                                             NSMutableDictionary *attributes,
                                                             CGFloat scale,
                                                             const OMRenderContext *renderContext)
{
    if (imageNode == NULL) {
        return nil;
    }

    const char *urlLiteral = cmark_node_get_url(imageNode);
    NSString *urlString = urlLiteral != NULL ? [NSString stringWithUTF8String:urlLiteral] : nil;
    NSURL *url = OMResolvedImageURL(urlString, renderContext);
    if (url == nil) {
        return nil;
    }

    NSString *urlKey = [url absoluteString];
    if (urlKey == nil || [urlKey length] == 0) {
        urlKey = urlString;
    }
    if (urlKey == nil || [urlKey length] == 0) {
        return nil;
    }

    BOOL allowRemoteImages = OMShouldAllowRemoteImages(renderContext);
    CGFloat layoutWidth = renderContext != NULL ? renderContext->layoutWidth : 0.0;
    NSString *cacheKey = OMImageAttachmentCacheKey(urlKey,
                                                   scale,
                                                   layoutWidth,
                                                   allowRemoteImages);
    NSCache *cache = OMImageAttachmentCache();
    NSImage *cachedImage = nil;
    @synchronized (cache) {
        cachedImage = [cache objectForKey:cacheKey];
    }

    NSImage *preparedImage = nil;
    if (cachedImage != nil) {
        preparedImage = [[cachedImage retain] autorelease];
    } else {
        if (OMURLUsesRemoteScheme(url)) {
            OMScheduleAsyncRemoteImageWarm(url, cacheKey, scale, layoutWidth, allowRemoteImages);
            return nil;
        }

        NSImage *loaded = OMLoadImageFromURL(url);
        if (loaded == nil) {
            return nil;
        }

        preparedImage = OMPreparedImageForAttachment(loaded, scale, layoutWidth);
        if (preparedImage == nil) {
            return nil;
        }

        @synchronized (cache) {
            [cache setObject:preparedImage forKey:cacheKey];
        }
    }

    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:preparedImage] autorelease];
    [attachment setAttachmentCell:cell];

    NSMutableDictionary *attachmentAttributes = [NSMutableDictionary dictionary];
    if (attributes != nil) {
        [attachmentAttributes addEntriesFromDictionary:attributes];
    }
    [attachmentAttributes setObject:attachment forKey:NSAttachmentAttributeName];

    unichar attachmentChar = NSAttachmentCharacter;
    NSString *attachmentString = [NSString stringWithCharacters:&attachmentChar length:1];
    return [[[NSAttributedString alloc] initWithString:attachmentString
                                            attributes:attachmentAttributes] autorelease];
}

static void OMAppendHTMLLiteral(const char *literal,
                                NSMutableAttributedString *output,
                                NSMutableDictionary *attributes,
                                BOOL blockNode,
                                const OMRenderContext *renderContext)
{
    if (OMHTMLPolicyForBlockNode(renderContext, blockNode) == OMMarkdownHTMLPolicyIgnore) {
        return;
    }

    NSString *html = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
    if (html == nil || [html length] == 0) {
        return;
    }

    OMAppendString(output, html, attributes);
    if (blockNode) {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static BOOL OMCharacterIsWhitespaceOrNewline(unichar ch)
{
    static NSCharacterSet *whitespaceSet = nil;
    if (whitespaceSet == nil) {
        whitespaceSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
    }
    return [whitespaceSet characterIsMember:ch];
}

static BOOL OMCharacterIsDigit(unichar ch)
{
    return ch >= '0' && ch <= '9';
}

static BOOL OMDollarIsEscaped(NSString *text, NSUInteger location)
{
    if (text == nil || [text length] == 0 || location == 0 || location >= [text length]) {
        return NO;
    }

    NSUInteger backslashCount = 0;
    NSInteger index = (NSInteger)location - 1;
    while (index >= 0) {
        if ([text characterAtIndex:(NSUInteger)index] != '\\') {
            break;
        }
        backslashCount += 1;
        index -= 1;
    }

    return (backslashCount % 2) == 1;
}

static NSDictionary *OMMathAttributes(OMTheme *theme,
                                      NSMutableDictionary *attributes,
                                      CGFloat scale,
                                      BOOL displayMath)
{
    NSMutableDictionary *mathAttrs = [attributes mutableCopy];
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    NSDictionary *codeAttrs = [theme codeAttributesForSize:size];
    [mathAttrs addEntriesFromDictionary:codeAttrs];

    NSFont *mathFont = [mathAttrs objectForKey:NSFontAttributeName];
    NSFont *italicFont = OMFontWithTraits(mathFont, NSItalicFontMask);
    if (italicFont != nil) {
        [mathAttrs setObject:italicFont forKey:NSFontAttributeName];
    }

    if (displayMath) {
        NSParagraphStyle *current = [attributes objectForKey:NSParagraphStyleAttributeName];
        NSMutableParagraphStyle *style = nil;
        if (current != nil) {
            style = [current mutableCopy];
        } else {
            style = [[NSMutableParagraphStyle alloc] init];
        }
        [style setAlignment:NSCenterTextAlignment];
        [style setParagraphSpacingBefore:8.0 * scale];
        [style setParagraphSpacing:8.0 * scale];
        [mathAttrs setObject:style forKey:NSParagraphStyleAttributeName];
        [style release];
    }

    return [mathAttrs autorelease];
}

static NSString *OMExecutablePathNamed(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return nil;
    }

    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *pathValue = [environment objectForKey:@"PATH"];
    if (pathValue != nil && [pathValue length] > 0) {
        NSArray *searchPaths = [pathValue componentsSeparatedByString:@":"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *searchPath in searchPaths) {
            if (searchPath == nil || [searchPath length] == 0) {
                continue;
            }
            NSString *candidate = [searchPath stringByAppendingPathComponent:name];
            if ([fileManager isExecutableFileAtPath:candidate]) {
                return candidate;
            }
        }
    }

    NSString *fallback = [@"/usr/bin" stringByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:fallback]) {
        return fallback;
    }
    return nil;
}

static NSString *OMLaTeXExecutablePath(void)
{
    static NSString *path = nil;
    static BOOL resolved = NO;
    if (!resolved) {
        path = [OMExecutablePathNamed(@"latex") retain];
        resolved = YES;
    }
    return path;
}

static NSString *OMPlainTexExecutablePath(void)
{
    static NSString *path = nil;
    static BOOL resolved = NO;
    if (!resolved) {
        path = [OMExecutablePathNamed(@"tex") retain];
        resolved = YES;
    }
    return path;
}

static NSString *OMDviSvgmExecutablePath(void)
{
    static NSString *path = nil;
    static BOOL resolved = NO;
    if (!resolved) {
        path = [OMExecutablePathNamed(@"dvisvgm") retain];
        resolved = YES;
    }
    return path;
}

static BOOL OMMathBackendAvailable(void)
{
    return OMDviSvgmExecutablePath() != nil &&
           (OMLaTeXExecutablePath() != nil || OMPlainTexExecutablePath() != nil);
}

static NSCache *OMMathAttachmentCache(void)
{
    static NSCache *cache = nil;
    if (cache == nil) {
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    }
    return cache;
}

static NSCache *OMMathBaseImageCache(void)
{
    static NSCache *cache = nil;
    if (cache == nil) {
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    }
    return cache;
}

static NSCache *OMMathBaseSVGDataCache(void)
{
    static NSCache *cache = nil;
    if (cache == nil) {
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    }
    return cache;
}

static NSCache *OMMathBestAvailableImageCache(void)
{
    static NSCache *cache = nil;
    if (cache == nil) {
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    }
    return cache;
}

static NSCache *OMMathBestAvailableZoomCache(void)
{
    static NSCache *cache = nil;
    if (cache == nil) {
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    }
    return cache;
}

static dispatch_queue_t OMMathArtifactQueue(void)
{
    static dispatch_queue_t queue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.objcmarkdown.math-artifacts", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSMutableSet *OMMathPendingAssetKeys(void)
{
    static NSMutableSet *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [[NSMutableSet alloc] init];
    });
    return keys;
}

static void OMRecordBestAvailableMathImage(NSString *formula,
                                           BOOL displayMath,
                                           CGFloat renderZoom,
                                           NSImage *image)
{
    if (formula == nil || [formula length] == 0 || image == nil) {
        return;
    }

    NSString *formulaKey = OMMathFormulaCacheKey(formula, displayMath);
    NSCache *zoomCache = OMMathBestAvailableZoomCache();
    NSCache *imageCache = OMMathBestAvailableImageCache();
    @synchronized (zoomCache) {
        NSNumber *existingZoomNumber = [zoomCache objectForKey:formulaKey];
        CGFloat existingZoom = existingZoomNumber != nil ? [existingZoomNumber doubleValue] : 0.0;
        if (renderZoom >= existingZoom) {
            [zoomCache setObject:[NSNumber numberWithDouble:renderZoom] forKey:formulaKey];
            [imageCache setObject:image forKey:formulaKey];
        } else if ([imageCache objectForKey:formulaKey] == nil) {
            [imageCache setObject:image forKey:formulaKey];
        }
    }
}

static NSImage *OMBestAvailableMathImage(NSString *formula,
                                         BOOL displayMath,
                                         CGFloat *renderZoomOut)
{
    if (formula == nil || [formula length] == 0) {
        return nil;
    }

    NSString *formulaKey = OMMathFormulaCacheKey(formula, displayMath);
    NSCache *zoomCache = OMMathBestAvailableZoomCache();
    NSCache *imageCache = OMMathBestAvailableImageCache();
    NSImage *image = nil;
    NSNumber *zoomNumber = nil;
    @synchronized (zoomCache) {
        image = [imageCache objectForKey:formulaKey];
        zoomNumber = [zoomCache objectForKey:formulaKey];
    }

    if (image != nil && renderZoomOut != NULL) {
        *renderZoomOut = zoomNumber != nil ? [zoomNumber doubleValue] : 0.0;
    }
    return image;
}

static CGFloat OMMathZoomForFontSize(CGFloat fontSize)
{
    CGFloat zoom = fontSize > 0.0 ? (fontSize / 10.0) : 1.0;
    if (zoom < 0.75) {
        zoom = 0.75;
    } else if (zoom > 6.0) {
        zoom = 6.0;
    }
    return zoom;
}

static BOOL OMRunTask(NSString *launchPath,
                      NSArray *arguments,
                      NSData **stdoutData,
                      NSData **stderrData,
                      int *terminationStatus,
                      NSTimeInterval timeoutSeconds)
{
    if (launchPath == nil || [launchPath length] == 0) {
        if (terminationStatus != NULL) {
            *terminationStatus = -1;
        }
        return NO;
    }

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:launchPath];
    [task setArguments:arguments];

    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    [task setStandardError:errorPipe];

    BOOL launched = YES;
    BOOL timedOut = NO;
    @try {
        [task launch];
        if (timeoutSeconds > 0.0) {
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];
            while ([task isRunning] && [deadline timeIntervalSinceNow] > 0.0) {
                [NSThread sleepForTimeInterval:0.02];
            }
            if ([task isRunning]) {
                timedOut = YES;
                [task terminate];
            }
        }
        [task waitUntilExit];
    } @catch (NSException *exception) {
        (void)exception;
        launched = NO;
    }

    NSData *capturedOutput = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSData *capturedError = [[errorPipe fileHandleForReading] readDataToEndOfFile];

    if (stdoutData != NULL) {
        *stdoutData = capturedOutput;
    }
    if (stderrData != NULL) {
        *stderrData = capturedError;
    }
    if (terminationStatus != NULL) {
        *terminationStatus = (launched && !timedOut) ? [task terminationStatus] : -1;
    }

    return launched && !timedOut && [task terminationStatus] == 0;
}

static NSString *OMCreateMathTempDirectory(void)
{
    NSString *base = NSTemporaryDirectory();
    if (base == nil || [base length] == 0) {
        base = @"/tmp";
    }
    NSString *path = [base stringByAppendingPathComponent:
        [NSString stringWithFormat:@"objcmarkdown-math-%@",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                              withIntermediateDirectories:YES
                                                               attributes:nil
                                                                    error:NULL];
    return created ? path : nil;
}

static NSData *OMSVGDataForMathFormula(NSString *formula,
                                       BOOL displayMath,
                                       CGFloat renderZoom,
                                       NSUInteger maximumFormulaLength,
                                       NSTimeInterval externalToolTimeout,
                                       OMMathPerfStats *stats)
{
    if (!OMMathBackendAvailable() ||
        formula == nil ||
        [formula length] == 0 ||
        (maximumFormulaLength > 0 && [formula length] > maximumFormulaLength)) {
        return nil;
    }

    NSString *tempDir = OMCreateMathTempDirectory();
    if (tempDir == nil) {
        return nil;
    }

    NSString *texPath = [tempDir stringByAppendingPathComponent:@"formula.tex"];
    NSString *dviPath = [tempDir stringByAppendingPathComponent:@"formula.dvi"];
    NSString *texExecutable = OMLaTeXExecutablePath();
    BOOL usingLaTeX = texExecutable != nil;
    if (!usingLaTeX) {
        texExecutable = OMPlainTexExecutablePath();
    }
    if (texExecutable == nil) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        return nil;
    }

    NSMutableString *texSource = [NSMutableString string];
    if (usingLaTeX) {
        [texSource appendString:@"\\documentclass{article}\n"];
        [texSource appendString:@"\\usepackage{amsmath}\n"];
        [texSource appendString:@"\\pagestyle{empty}\n"];
        [texSource appendString:@"\\begin{document}\n"];
        if (displayMath) {
            [texSource appendFormat:@"\\[\n%@\n\\]\n", formula];
        } else {
            [texSource appendFormat:@"$%@$ \n", formula];
        }
        [texSource appendString:@"\\end{document}\n"];
    } else {
        [texSource appendString:@"\\hsize=10000pt\n"];
        [texSource appendString:@"\\nopagenumbers\n"];
        if (displayMath) {
            [texSource appendFormat:@"\\setbox0=\\vbox{$$%@$$}\n", formula];
        } else {
            [texSource appendFormat:@"\\setbox0=\\hbox{$%@$}\n", formula];
        }
        [texSource appendString:@"\\shipout\\box0\n"];
        [texSource appendString:@"\\bye\n"];
    }

    BOOL wroteTex = [texSource writeToFile:texPath
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:NULL];
    if (!wroteTex) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        return nil;
    }

    NSArray *texArguments = [NSArray arrayWithObjects:
        @"-interaction=nonstopmode",
        @"-halt-on-error",
        @"-output-directory", tempDir,
        texPath,
        nil];
    int texStatus = 0;
    NSTimeInterval texStart = OMNow();
    BOOL texOK = OMRunTask(texExecutable,
                           texArguments,
                           NULL,
                           NULL,
                           &texStatus,
                           externalToolTimeout);
    if (stats != NULL) {
        stats->latexRuns += 1;
        stats->latexSeconds += (OMNow() - texStart);
    }
    if (!texOK || ![[NSFileManager defaultManager] fileExistsAtPath:dviPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        return nil;
    }

    if (renderZoom < 0.5) {
        renderZoom = 0.5;
    } else if (renderZoom > 10.0) {
        renderZoom = 10.0;
    }
    NSString *zoomArgument = [NSString stringWithFormat:@"--zoom=%.3f", renderZoom];

    NSArray *svgArguments = [NSArray arrayWithObjects:
        @"--no-fonts",
        @"--exact-bbox",
        zoomArgument,
        @"--stdout",
        dviPath,
        nil];
    NSData *svgData = nil;
    int svgStatus = 0;
    NSTimeInterval svgStart = OMNow();
    BOOL svgOK = OMRunTask(OMDviSvgmExecutablePath(),
                           svgArguments,
                           &svgData,
                           NULL,
                           &svgStatus,
                           externalToolTimeout);
    if (stats != NULL) {
        stats->dvisvgmRuns += 1;
        stats->dvisvgmSeconds += (OMNow() - svgStart);
    }
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];

    if (!svgOK || svgData == nil || [svgData length] == 0) {
        return nil;
    }
    return svgData;
}

static void OMScheduleAsyncMathAssetGeneration(NSString *formula,
                                               BOOL displayMath,
                                               CGFloat renderZoom,
                                               NSUInteger maximumFormulaLength,
                                               NSTimeInterval externalToolTimeout)
{
    if (!OMMathBackendAvailable() ||
        formula == nil ||
        [formula length] == 0 ||
        (maximumFormulaLength > 0 && [formula length] > maximumFormulaLength)) {
        return;
    }

    NSString *assetKey = OMMathAssetCacheKey(formula, displayMath, renderZoom);
    if ([OMMathBaseImageCache() objectForKey:assetKey] != nil ||
        [OMMathBaseSVGDataCache() objectForKey:assetKey] != nil) {
        return;
    }

    BOOL shouldSchedule = NO;
    NSMutableSet *pending = OMMathPendingAssetKeys();
    @synchronized (pending) {
        if (![pending containsObject:assetKey]) {
            [pending addObject:assetKey];
            shouldSchedule = YES;
        }
    }
    if (!shouldSchedule) {
        return;
    }

    NSString *formulaCopy = [formula copy];
    NSString *assetKeyCopy = [assetKey copy];
    dispatch_async(OMMathArtifactQueue(), ^{
        @autoreleasepool {
            NSData *svgData = OMSVGDataForMathFormula(formulaCopy,
                                                      displayMath,
                                                      renderZoom,
                                                      maximumFormulaLength,
                                                      externalToolTimeout,
                                                      NULL);
            if (svgData != nil) {
                [OMMathBaseSVGDataCache() setObject:svgData forKey:assetKeyCopy];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:OMMarkdownRendererMathArtifactsDidWarmNotification
                                      object:nil];
                });
            }

            @synchronized (pending) {
                [pending removeObject:assetKeyCopy];
            }
            [formulaCopy release];
            [assetKeyCopy release];
        }
    });
}

static NSAttributedString *OMMathAttachmentAttributedString(NSString *formula,
                                                            OMTheme *theme,
                                                            NSMutableDictionary *attributes,
                                                            CGFloat scale,
                                                            BOOL displayMath,
                                                            const OMRenderContext *renderContext)
{
    if (!OMExternalMathRenderingEnabled(renderContext)) {
        return nil;
    }

    OMMathPerfStats *stats = renderContext != NULL ? renderContext->mathPerfStats : NULL;
    if (stats != NULL) {
        stats->mathRequests += 1;
    }
    NSUInteger maxFormulaLength = OMMathMaximumFormulaLength(renderContext);
    NSTimeInterval externalToolTimeout = OMExternalToolTimeout(renderContext);
    BOOL asyncMathGenerationEnabled = (renderContext != NULL && renderContext->asynchronousMathGenerationEnabled);
    if (!OMMathBackendAvailable() ||
        formula == nil ||
        [formula length] == 0 ||
        (maxFormulaLength > 0 && [formula length] > maxFormulaLength)) {
        if (stats != NULL) {
            stats->mathFailures += 1;
        }
        return nil;
    }

    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    CGFloat zoom = OMMathZoomForFontSize(fontSize);
    CGFloat oversample = OMMathRasterOversampleFactor();
    CGFloat renderZoom = OMMathQuantizedRenderZoom(zoom, oversample);
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.2f|%@",
                          displayMath ? @"display" : @"inline",
                          fontSize,
                          formula];
    NSAttributedString *cached = [OMMathAttachmentCache() objectForKey:cacheKey];
    if (cached != nil) {
        if (stats != NULL) {
            stats->mathCacheHits += 1;
        }
        return cached;
    }
    if (stats != NULL) {
        stats->mathCacheMisses += 1;
    }

    NSTimeInterval mathStart = OMNow();
    NSString *assetKey = OMMathAssetCacheKey(formula, displayMath, renderZoom);
    NSImage *baseImage = [OMMathBaseImageCache() objectForKey:assetKey];
    NSData *svgData = nil;
    CGFloat imageRenderZoom = renderZoom;
    BOOL usedFallbackImage = NO;
    if (baseImage != nil) {
        if (stats != NULL) {
            stats->mathAssetCacheHits += 1;
        }
        OMRecordBestAvailableMathImage(formula, displayMath, renderZoom, baseImage);
    } else {
        svgData = [OMMathBaseSVGDataCache() objectForKey:assetKey];
        if (svgData != nil) {
            if (stats != NULL) {
                stats->mathAssetCacheHits += 1;
            }
        } else {
            if (stats != NULL) {
                stats->mathAssetCacheMisses += 1;
            }

            if (asyncMathGenerationEnabled) {
                OMScheduleAsyncMathAssetGeneration(formula,
                                                   displayMath,
                                                   renderZoom,
                                                   maxFormulaLength,
                                                   externalToolTimeout);
                CGFloat fallbackRenderZoom = 0.0;
                NSImage *fallbackImage = OMBestAvailableMathImage(formula, displayMath, &fallbackRenderZoom);
                if (fallbackImage != nil) {
                    baseImage = fallbackImage;
                    usedFallbackImage = YES;
                    imageRenderZoom = fallbackRenderZoom > 0.0 ? fallbackRenderZoom : oversample;
                    if (stats != NULL) {
                        stats->mathAssetCacheHits += 1;
                    }
                } else {
                    return nil;
                }
            }

            if (!usedFallbackImage) {
                svgData = OMSVGDataForMathFormula(formula,
                                                  displayMath,
                                                  renderZoom,
                                                  maxFormulaLength,
                                                  externalToolTimeout,
                                                  stats);
                if (svgData == nil) {
                    if (stats != NULL) {
                        stats->mathFailures += 1;
                        stats->mathTotalSeconds += (OMNow() - mathStart);
                    }
                    return nil;
                }
                [OMMathBaseSVGDataCache() setObject:svgData forKey:assetKey];
            }
        }

        if (baseImage == nil) {
            NSTimeInterval decodeStart = OMNow();
            NSImage *decodedImage = [[[NSImage alloc] initWithData:svgData] autorelease];
            if (stats != NULL) {
                stats->svgDecodeSeconds += (OMNow() - decodeStart);
            }
            if (decodedImage == nil) {
                if (stats != NULL) {
                    stats->mathFailures += 1;
                    stats->mathTotalSeconds += (OMNow() - mathStart);
                }
                return nil;
            }
            [OMMathBaseImageCache() setObject:decodedImage forKey:assetKey];
            baseImage = decodedImage;
            OMRecordBestAvailableMathImage(formula, displayMath, renderZoom, baseImage);
        }
    }

    NSImage *image = [[baseImage copy] autorelease];
    if (image == nil) {
        if (stats != NULL) {
            stats->mathFailures += 1;
            stats->mathTotalSeconds += (OMNow() - mathStart);
        }
        return nil;
    }

    NSSize imageSize = [baseImage size];
    if (imageSize.width > 0.0 && imageSize.height > 0.0) {
        CGFloat displayScale = zoom / imageRenderZoom;
        if (displayScale < 0.1) {
            displayScale = 0.1;
        }
        [image setScalesWhenResized:YES];
        [image setSize:NSMakeSize(imageSize.width * displayScale, imageSize.height * displayScale)];
    }

    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
    if (cell != nil) {
        [cell setAttachment:attachment];
        [attachment setAttachmentCell:cell];
    }

    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc]
        initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]] autorelease];
    [result addAttribute:NSBaselineOffsetAttributeName
                   value:[NSNumber numberWithDouble:(displayMath ? 0.0 : (-1.0 * scale))]
                   range:NSMakeRange(0, [result length])];

    NSAttributedString *immutable = [[[NSAttributedString alloc] initWithAttributedString:result] autorelease];
    if (!usedFallbackImage) {
        [OMMathAttachmentCache() setObject:immutable forKey:cacheKey];
    }
    if (stats != NULL) {
        stats->mathRendered += 1;
        stats->mathTotalSeconds += (OMNow() - mathStart);
    }
    return immutable;
}

static void OMAppendTextWithMathSpans(NSString *text,
                                      OMTheme *theme,
                                      NSMutableAttributedString *output,
                                      NSMutableDictionary *attributes,
                                      CGFloat scale,
                                      const OMRenderContext *renderContext)
{
    if (text == nil || [text length] == 0) {
        return;
    }
    if (!OMShouldParseMathSpans(renderContext)) {
        OMAppendString(output, text, attributes);
        return;
    }

    NSUInteger length = [text length];
    NSUInteger cursor = 0;
    while (cursor < length) {
        NSUInteger dollarLocation = NSNotFound;
        for (NSUInteger i = cursor; i < length; i++) {
            if ([text characterAtIndex:i] == '$' && !OMDollarIsEscaped(text, i)) {
                dollarLocation = i;
                break;
            }
        }

        if (dollarLocation == NSNotFound) {
            OMAppendString(output, [text substringWithRange:NSMakeRange(cursor, length - cursor)], attributes);
            break;
        }

        if (dollarLocation > cursor) {
            OMAppendString(output, [text substringWithRange:NSMakeRange(cursor, dollarLocation - cursor)], attributes);
        }

        BOOL renderedMath = NO;
        BOOL isDisplayStart = (dollarLocation + 1 < length &&
                               [text characterAtIndex:dollarLocation + 1] == '$');

        if (isDisplayStart) {
            NSUInteger contentStart = dollarLocation + 2;
            NSUInteger i = contentStart;
            while (i + 1 < length) {
                if ([text characterAtIndex:i] == '$' &&
                    [text characterAtIndex:i + 1] == '$' &&
                    !OMDollarIsEscaped(text, i)) {
                    if (i > contentStart) {
                        NSString *formula = [text substringWithRange:NSMakeRange(contentStart, i - contentStart)];
                        NSAttributedString *attachment = OMMathAttachmentAttributedString(formula,
                                                                                           theme,
                                                                                           attributes,
                                                                                           scale,
                                                                                           YES,
                                                                                           renderContext);
                        if (attachment != nil) {
                            OMAppendAttributedSegment(output, attachment);
                        } else {
                            NSDictionary *mathAttrs = OMMathAttributes(theme, attributes, scale, YES);
                            OMAppendString(output, formula, mathAttrs);
                        }
                        renderedMath = YES;
                        cursor = i + 2;
                    }
                    break;
                }
                i += 1;
            }
        } else if (dollarLocation + 1 < length &&
                   !OMCharacterIsWhitespaceOrNewline([text characterAtIndex:dollarLocation + 1])) {
            NSUInteger i = dollarLocation + 1;
            while (i < length) {
                if ([text characterAtIndex:i] == '$' && !OMDollarIsEscaped(text, i)) {
                    BOOL precededByWhitespace = (i == 0) ? YES : OMCharacterIsWhitespaceOrNewline([text characterAtIndex:i - 1]);
                    BOOL followedByDigit = (i + 1 < length) ? OMCharacterIsDigit([text characterAtIndex:i + 1]) : NO;
                    BOOL adjacentToDollar = (i > 0 && [text characterAtIndex:i - 1] == '$') ||
                                            (i + 1 < length && [text characterAtIndex:i + 1] == '$');
                    if (!precededByWhitespace && !followedByDigit && !adjacentToDollar) {
                        NSString *formula = [text substringWithRange:NSMakeRange(dollarLocation + 1, i - (dollarLocation + 1))];
                        if ([formula length] > 0) {
                            NSAttributedString *attachment = OMMathAttachmentAttributedString(formula,
                                                                                               theme,
                                                                                               attributes,
                                                                                               scale,
                                                                                               NO,
                                                                                               renderContext);
                            if (attachment != nil) {
                                OMAppendAttributedSegment(output, attachment);
                            } else {
                                NSDictionary *mathAttrs = OMMathAttributes(theme, attributes, scale, NO);
                                OMAppendString(output, formula, mathAttrs);
                            }
                            renderedMath = YES;
                            cursor = i + 1;
                        }
                        break;
                    }
                }
                i += 1;
            }
        }

        if (!renderedMath) {
            OMAppendString(output, @"$", attributes);
            cursor = dollarLocation + 1;
        }
    }
}

static BOOL OMTextNodeIsDisplayMathFence(cmark_node *node)
{
    if (node == NULL || cmark_node_get_type(node) != CMARK_NODE_TEXT) {
        return NO;
    }

    const char *literal = cmark_node_get_literal(node);
    if (literal == NULL) {
        return NO;
    }

    NSString *text = [NSString stringWithUTF8String:literal];
    if (text == nil) {
        return NO;
    }
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed isEqualToString:@"$$"];
}

static cmark_node *OMTryAppendMultiNodeDisplayMath(cmark_node *startNode,
                                                    OMTheme *theme,
                                                    NSMutableAttributedString *output,
                                                    NSMutableDictionary *attributes,
                                                    CGFloat scale,
                                                    BOOL *didRender,
                                                    const OMRenderContext *renderContext)
{
    if (didRender != NULL) {
        *didRender = NO;
    }
    if (!OMShouldParseMathSpans(renderContext)) {
        return NULL;
    }
    if (!OMTextNodeIsDisplayMathFence(startNode)) {
        return NULL;
    }

    NSMutableString *formula = [NSMutableString string];
    cmark_node *cursor = cmark_node_next(startNode);
    while (cursor != NULL) {
        cmark_node_type type = cmark_node_get_type(cursor);
        if (type == CMARK_NODE_TEXT) {
            const char *literal = cmark_node_get_literal(cursor);
            NSString *text = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
            NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([trimmed isEqualToString:@"$$"]) {
                NSString *normalized = [formula stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([normalized length] == 0) {
                    return NULL;
                }

                NSAttributedString *attachment = OMMathAttachmentAttributedString(normalized,
                                                                                  theme,
                                                                                  attributes,
                                                                                  scale,
                                                                                  YES,
                                                                                  renderContext);
                if (attachment != nil) {
                    OMAppendAttributedSegment(output, attachment);
                } else {
                    NSDictionary *mathAttrs = OMMathAttributes(theme, attributes, scale, YES);
                    OMAppendString(output, normalized, mathAttrs);
                }
                if (didRender != NULL) {
                    *didRender = YES;
                }
                return cmark_node_next(cursor);
            }
            [formula appendString:text];
        } else if (type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK) {
            [formula appendString:@"\n"];
        } else {
            return NULL;
        }
        cursor = cmark_node_next(cursor);
    }

    return NULL;
}

@interface OMMarkdownRenderer ()
@property (nonatomic, retain) OMTheme *theme;
@property (nonatomic, retain) NSArray *codeBlockRanges;
@property (nonatomic, retain) NSArray *blockquoteRanges;
@property (nonatomic, retain) NSArray *blockAnchors;
@end

@implementation OMMarkdownRenderer

@synthesize zoomScale = _zoomScale;
@synthesize layoutWidth = _layoutWidth;
@synthesize allowTableHorizontalOverflow = _allowTableHorizontalOverflow;
@synthesize asynchronousMathGenerationEnabled = _asynchronousMathGenerationEnabled;
@synthesize parsingOptions = _parsingOptions;
@synthesize codeBlockRanges = _codeBlockRanges;
@synthesize blockquoteRanges = _blockquoteRanges;
@synthesize blockAnchors = _blockAnchors;

+ (BOOL)isTreeSitterAvailable
{
    return OMTreeSitterRuntimeAvailable();
}

- (instancetype)init
{
    return [self initWithTheme:[OMTheme defaultTheme]
                parsingOptions:[OMMarkdownParsingOptions defaultOptions]];
}

- (instancetype)initWithTheme:(OMTheme *)theme
{
    return [self initWithTheme:theme
                parsingOptions:[OMMarkdownParsingOptions defaultOptions]];
}

- (instancetype)initWithTheme:(OMTheme *)theme parsingOptions:(OMMarkdownParsingOptions *)parsingOptions
{
    self = [super init];
    if (self) {
        if (theme == nil) {
            theme = [OMTheme defaultTheme];
        }
        if (parsingOptions == nil) {
            parsingOptions = [OMMarkdownParsingOptions defaultOptions];
        }
        _theme = [theme retain];
        _parsingOptions = [parsingOptions copy];
        _zoomScale = 1.0;
        _layoutWidth = 0.0;
        _allowTableHorizontalOverflow = NO;
        _asynchronousMathGenerationEnabled = NO;
    }
    return self;
}

- (void)dealloc
{
    [_codeBlockRanges release];
    [_blockquoteRanges release];
    [_blockAnchors release];
    [_parsingOptions release];
    [_theme release];
    [super dealloc];
}

- (void)setParsingOptions:(OMMarkdownParsingOptions *)parsingOptions
{
    OMMarkdownParsingOptions *resolved = parsingOptions;
    if (resolved == nil) {
        resolved = [OMMarkdownParsingOptions defaultOptions];
    }
    if (_parsingOptions == resolved) {
        return;
    }
    [_parsingOptions release];
    _parsingOptions = [resolved copy];
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown
{
    if (markdown == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    BOOL perfLogging = OMPerformanceLoggingEnabled();
    NSTimeInterval totalStart = perfLogging ? OMNow() : 0.0;

    NSData *markdownData = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    if (markdownData == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    const char *bytes = (const char *)[markdownData bytes];
    size_t length = (size_t)[markdownData length];
    NSUInteger cmarkOptions = self.parsingOptions != nil ? [self.parsingOptions cmarkOptions] : (NSUInteger)CMARK_OPT_DEFAULT;
    NSTimeInterval parseStart = perfLogging ? OMNow() : 0.0;
    cmark_node *document = cmark_parse_document(bytes, length, (int)cmarkOptions);
    NSTimeInterval parseMs = perfLogging ? ((OMNow() - parseStart) * 1000.0) : 0.0;
    if (document == NULL) {
        if (perfLogging) {
            NSLog(@"[Perf][Renderer] parse failed chars=%lu parse=%.1fms total=%.1fms",
                  (unsigned long)[markdown length],
                  parseMs,
                  (OMNow() - totalStart) * 1000.0);
        }
        return [[[NSAttributedString alloc] initWithString:markdown] autorelease];
    }

    NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] init] autorelease];
    NSMutableDictionary *attributes = [[[self.theme baseAttributes] mutableCopy] autorelease];
    CGFloat scale = self.zoomScale > 0.01 ? self.zoomScale : 1.0;
    if (self.theme.baseFont != nil) {
        NSFont *scaledFont = [NSFont fontWithName:[self.theme.baseFont fontName]
                                             size:[self.theme.baseFont pointSize] * scale];
        if (scaledFont != nil) {
            [attributes setObject:scaledFont forKey:NSFontAttributeName];
        } else {
            [attributes setObject:self.theme.baseFont forKey:NSFontAttributeName];
        }
    }
    if ([attributes objectForKey:NSForegroundColorAttributeName] == nil && self.theme.baseTextColor != nil) {
        [attributes setObject:self.theme.baseTextColor forKey:NSForegroundColorAttributeName];
    }

    NSMutableArray *listStack = [NSMutableArray array];
    NSMutableArray *codeRanges = [NSMutableArray array];
    NSMutableArray *blockquoteRanges = [NSMutableArray array];
    NSMutableArray *blockAnchors = [NSMutableArray array];
    NSArray *sourceLines = OMSourceLinesForMarkdown(markdown);
    OMMathPerfStats stats = {0};
    OMRenderContext renderContext;
    renderContext.parsingOptions = self.parsingOptions;
    renderContext.sourceLines = sourceLines;
    renderContext.blockAnchors = blockAnchors;
    renderContext.mathPerfStats = &stats;
    renderContext.layoutWidth = self.layoutWidth;
    renderContext.allowTableHorizontalOverflow = self.allowTableHorizontalOverflow;
    renderContext.asynchronousMathGenerationEnabled = self.asynchronousMathGenerationEnabled;
    NSTimeInterval renderStart = perfLogging ? OMNow() : 0.0;
    OMRenderBlocks(document,
                   self.theme,
                   output,
                   attributes,
                   codeRanges,
                   blockquoteRanges,
                   listStack,
                   0,
                   scale,
                   self.layoutWidth,
                   &renderContext);
    NSTimeInterval renderMs = perfLogging ? ((OMNow() - renderStart) * 1000.0) : 0.0;
    [self setCodeBlockRanges:codeRanges];
    [self setBlockquoteRanges:blockquoteRanges];
    [self setBlockAnchors:blockAnchors];
    OMTrimTrailingNewlines(output);
    cmark_node_free(document);
    if (perfLogging) {
        NSLog(@"[Perf][Renderer] total=%.1fms parse=%.1fms render=%.1fms charsIn=%lu charsOut=%lu zoom=%.2f width=%.1f math(req=%lu hit=%lu miss=%lu assetHit=%lu assetMiss=%lu ok=%lu fail=%lu total=%.1fms latex=%lums/%lu dvisvgm=%lums/%lu decode=%.1fms)",
              (OMNow() - totalStart) * 1000.0,
              parseMs,
              renderMs,
              (unsigned long)[markdown length],
              (unsigned long)[output length],
              self.zoomScale,
              self.layoutWidth,
              (unsigned long)stats.mathRequests,
              (unsigned long)stats.mathCacheHits,
              (unsigned long)stats.mathCacheMisses,
              (unsigned long)stats.mathAssetCacheHits,
              (unsigned long)stats.mathAssetCacheMisses,
              (unsigned long)stats.mathRendered,
              (unsigned long)stats.mathFailures,
              stats.mathTotalSeconds * 1000.0,
              (unsigned long)(stats.latexSeconds * 1000.0 + 0.5),
              (unsigned long)stats.latexRuns,
              (unsigned long)(stats.dvisvgmSeconds * 1000.0 + 0.5),
              (unsigned long)stats.dvisvgmRuns,
              stats.svgDecodeSeconds * 1000.0);
    }
    return output;
}

- (NSColor *)backgroundColor
{
    return self.theme.baseBackgroundColor;
}

static void OMRenderParagraph(cmark_node *node,
                              OMTheme *theme,
                              NSMutableAttributedString *output,
                              NSMutableDictionary *attributes,
                              NSMutableArray *listStack,
                              NSUInteger quoteLevel,
                              CGFloat scale,
                              const OMRenderContext *renderContext)
{
    NSArray *tableRows = nil;
    NSArray *tableAlignments = nil;
    if (OMPipeTableDataForParagraphNode(node, renderContext, &tableRows, &tableAlignments)) {
        CGFloat layoutWidth = (renderContext != NULL ? renderContext->layoutWidth : 0.0);
        OMRenderPipeTable(tableRows,
                          tableAlignments,
                          theme,
                          output,
                          attributes,
                          listStack,
                          quoteLevel,
                          scale,
                          layoutWidth,
                          renderContext);
        return;
    }

    NSMutableDictionary *paraAttrs = [attributes mutableCopy];
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale);
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    NSParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 12.0 * scale, 0.0, 1.725, fontSize);
    [paraAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMRenderInlines(node, theme, output, paraAttrs, scale, renderContext);
    [paraAttrs release];

    if (OMIsTightList(listStack)) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static void OMRenderHeading(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            NSUInteger quoteLevel,
                            CGFloat scale,
                            CGFloat layoutWidth,
                            const OMRenderContext *renderContext)
{
    int level = cmark_node_get_heading_level(node);
    NSMutableDictionary *headingAttrs = [attributes mutableCopy];
    NSDictionary *headingStyle = OMHeadingAttributes(theme, (NSUInteger)level, scale);
    [headingAttrs addEntriesFromDictionary:headingStyle];

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale);
    NSFont *font = [headingAttrs objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 14.0 * scale, 0.0, 1.38, fontSize);
    CGFloat spacingBefore = (level >= 2 && level <= 3) ? 20.0 * scale : 10.0 * scale;
    [style setParagraphSpacingBefore:spacingBefore];
    [headingAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMRenderInlines(node, theme, output, headingAttrs, scale, renderContext);
    [headingAttrs release];
    OMAppendString(output, @"\n", attributes);

    if (level <= 3 && theme.hrColor != nil) {
        NSMutableDictionary *ruleAttrs = [attributes mutableCopy];
        NSFont *font = [attributes objectForKey:NSFontAttributeName];
        CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
        NSFont *ruleFont = [NSFont systemFontOfSize:MAX(1.0, size * 0.35)];
        if (ruleFont != nil) {
            [ruleAttrs setObject:ruleFont forKey:NSFontAttributeName];
        }
        [ruleAttrs setObject:theme.hrColor forKey:NSForegroundColorAttributeName];
        NSMutableParagraphStyle *ruleStyle = OMParagraphStyleWithIndent(indent, indent, 12.0 * scale, 0.0, 1.15, size);
        [ruleStyle setMinimumLineHeight:MAX(1.0, size * 0.5)];
        [ruleAttrs setObject:ruleStyle forKey:NSParagraphStyleAttributeName];

        CGFloat availableWidth = layoutWidth > 0.0 ? (layoutWidth - indent) : 0.0;
        NSString *rule = OMRuleLineString(ruleFont, availableWidth);
        OMAppendString(output, rule, ruleAttrs);
        OMAppendString(output, @"\n\n", attributes);
        [ruleAttrs release];
    } else {
        OMAppendString(output, @"\n", attributes);
    }
}

static void OMRenderCodeBlock(cmark_node *node,
                              OMTheme *theme,
                              NSMutableAttributedString *output,
                              NSMutableDictionary *attributes,
                              NSUInteger quoteLevel,
                              CGFloat scale,
                              NSMutableArray *codeRanges,
                              const OMRenderContext *renderContext)
{
    const char *literal = cmark_node_get_literal(node);
    NSString *code = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";

    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    CGFloat blockCodeFontSize = size * 0.92;
    if (blockCodeFontSize < 11.0 * scale) {
        blockCodeFontSize = 11.0 * scale;
    }
    NSDictionary *codeAttrs = [theme codeAttributesForSize:blockCodeFontSize];

    NSMutableDictionary *blockAttrs = [attributes mutableCopy];
    [blockAttrs addEntriesFromDictionary:codeAttrs];
    NSColor *codeBackgroundColor = [blockAttrs objectForKey:NSBackgroundColorAttributeName];
    if (codeBackgroundColor != nil) {
        // Block code container background is drawn by OMDTextView; keep inline code background separate.
        [blockAttrs removeObjectForKey:NSBackgroundColorAttributeName];
    }

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + 20.0 * scale;
    CGFloat padding = 20.0 * scale;
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent + padding,
                                                                indent + padding,
                                                                14.0 * scale,
                                                                0.0,
                                                                1.45,
                                                                blockCodeFontSize);
    [style setParagraphSpacingBefore:10.0 * scale];
    [style setTailIndent:-padding];
    [blockAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    NSUInteger startLocation = [output length];
    NSMutableAttributedString *codeSegment = [[[NSMutableAttributedString alloc] initWithString:code
                                                                                      attributes:blockAttrs] autorelease];
    OMApplyCodeSyntaxHighlighting(node, codeSegment, codeBackgroundColor, renderContext);
    OMAppendAttributedSegment(output, codeSegment);
    if ([code length] > 0) {
        [codeRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, [code length])]];
    }
    if (![code hasSuffix:@"\n"]) {
        OMAppendString(output, @"\n", blockAttrs);
    }
    OMAppendString(output, @"\n", attributes);
    [blockAttrs release];
}

static void OMRenderThematicBreak(OMTheme *theme,
                                  NSMutableAttributedString *output,
                                  NSMutableDictionary *attributes,
                                  CGFloat layoutWidth)
{
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    NSString *rule = OMRuleLineString(font, layoutWidth);
    OMAppendString(output, rule, attributes);
    OMAppendString(output, @"\n\n", attributes);
}

static void OMRenderList(cmark_node *node,
                         OMTheme *theme,
                         NSMutableAttributedString *output,
                         NSMutableDictionary *attributes,
                         NSMutableArray *codeRanges,
                         NSMutableArray *blockquoteRanges,
                         NSMutableArray *listStack,
                         NSUInteger quoteLevel,
                         CGFloat scale,
                         CGFloat layoutWidth,
                         const OMRenderContext *renderContext)
{
    cmark_list_type type = cmark_node_get_list_type(node);
    int start = cmark_node_get_list_start(node);
    BOOL tight = cmark_node_get_list_tight(node) ? YES : NO;

    NSMutableDictionary *listInfo = [NSMutableDictionary dictionary];
    [listInfo setObject:[NSNumber numberWithInt:type] forKey:@"type"];
    [listInfo setObject:[NSNumber numberWithInt:start > 0 ? start : 1] forKey:@"index"];
    [listInfo setObject:[NSNumber numberWithBool:tight] forKey:@"tight"];
    [listStack addObject:listInfo];

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child,
                       theme,
                       output,
                       attributes,
                       codeRanges,
                       blockquoteRanges,
                       listStack,
                       quoteLevel,
                       scale,
                       layoutWidth,
                       renderContext);
        child = cmark_node_next(child);
    }

    [listStack removeLastObject];
    BOOL nested = [listStack count] > 0;
    BOOL parentIsItem = NO;
    cmark_node *parent = cmark_node_parent(node);
    if (parent != NULL && cmark_node_get_type(parent) == CMARK_NODE_ITEM) {
        parentIsItem = YES;
    }
    if (parentIsItem) {
        return;
    }
    if (nested || tight) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static void OMRenderListItem(cmark_node *node,
                             OMTheme *theme,
                             NSMutableAttributedString *output,
                             NSMutableDictionary *attributes,
                             NSMutableArray *codeRanges,
                             NSMutableArray *blockquoteRanges,
                             NSMutableArray *listStack,
                             NSUInteger quoteLevel,
                             CGFloat scale,
                             CGFloat layoutWidth,
                             const OMRenderContext *renderContext)
{
    NSUInteger startLocation = [output length];
    NSString *prefix = OMListPrefix(listStack);
    OMAppendString(output, prefix, attributes);

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child,
                       theme,
                       output,
                       attributes,
                       codeRanges,
                       blockquoteRanges,
                       listStack,
                       quoteLevel,
                       scale,
                       layoutWidth,
                       renderContext);
        child = cmark_node_next(child);
    }

    NSUInteger endLocation = [output length];
    CGFloat baseIndent = (CGFloat)(quoteLevel * 20.0 * scale);
    CGFloat listIndent = (CGFloat)([listStack count] * 18.0 * scale);
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    BOOL hasNestedList = NO;
    cmark_node *scan = cmark_node_first_child(node);
    while (scan != NULL) {
        if (cmark_node_get_type(scan) == CMARK_NODE_LIST) {
            hasNestedList = YES;
            break;
        }
        scan = cmark_node_next(scan);
    }
    CGFloat spacingAfter = [listStack count] > 1 ? 2.0 * scale : 8.0 * scale;
    if (hasNestedList) {
        spacingAfter = 2.0 * scale;
    }
    NSParagraphStyle *style = OMParagraphStyleWithIndent(baseIndent + listIndent,
                                                        baseIndent + listIndent + 20.0 * scale,
                                                        spacingAfter,
                                                        0.0,
                                                        1.61,
                                                        fontSize);
    if (endLocation > startLocation) {
        NSString *text = [output string];
        NSRange searchRange = NSMakeRange(startLocation, endLocation - startLocation);
        NSRange newlineRange = [text rangeOfString:@"\n" options:0 range:searchRange];
        NSUInteger lineEnd = newlineRange.location != NSNotFound ? newlineRange.location : endLocation;
        if (lineEnd > startLocation) {
            [output addAttribute:NSParagraphStyleAttributeName
                           value:style
                           range:NSMakeRange(startLocation, lineEnd - startLocation)];
        }
    }
    OMIncrementListIndex(listStack);
}

static void OMRenderBlocks(cmark_node *node,
                           OMTheme *theme,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *attributes,
                           NSMutableArray *codeRanges,
                           NSMutableArray *blockquoteRanges,
                           NSMutableArray *listStack,
                           NSUInteger quoteLevel,
                           CGFloat scale,
                           CGFloat layoutWidth,
                           const OMRenderContext *renderContext)
{
    NSUInteger startLocation = [output length];
    cmark_node_type type = cmark_node_get_type(node);
    if (type == CMARK_NODE_BLOCK_QUOTE) {
        cmark_node *child = cmark_node_first_child(node);
        while (child != NULL) {
            OMRenderBlocks(child,
                           theme,
                           output,
                           attributes,
                           codeRanges,
                           blockquoteRanges,
                           listStack,
                           quoteLevel + 1,
                           scale,
                           layoutWidth,
                           renderContext);
            child = cmark_node_next(child);
        }
        NSUInteger endLocation = [output length];
        if (endLocation > startLocation) {
            [blockquoteRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, endLocation - startLocation)]];
            OMRecordBlockAnchor(node, startLocation, endLocation, renderContext);
        }
        return;
    }
    switch (type) {
        case CMARK_NODE_DOCUMENT:
            break;
        case CMARK_NODE_PARAGRAPH:
            OMRenderParagraph(node, theme, output, attributes, listStack, quoteLevel, scale, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_HEADING:
            OMRenderHeading(node, theme, output, attributes, quoteLevel, scale, layoutWidth, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_CODE_BLOCK:
            OMRenderCodeBlock(node, theme, output, attributes, quoteLevel, scale, codeRanges, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_THEMATIC_BREAK:
            OMRenderThematicBreak(theme, output, attributes, layoutWidth);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_BLOCK_QUOTE:
            quoteLevel += 1;
            break;
        case CMARK_NODE_LIST:
            OMRenderList(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_ITEM:
            OMRenderListItem(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        case CMARK_NODE_HTML_BLOCK: {
            const char *literal = cmark_node_get_literal(node);
            OMAppendHTMLLiteral(literal, output, attributes, YES, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        }
        case CMARK_NODE_CUSTOM_BLOCK: {
            const char *literal = cmark_node_get_literal(node);
            OMAppendHTMLLiteral(literal, output, attributes, YES, renderContext);
            OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
            return;
        }
        default:
            break;
    }

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child,
                       theme,
                       output,
                       attributes,
                       codeRanges,
                       blockquoteRanges,
                       listStack,
                       quoteLevel,
                       scale,
                       layoutWidth,
                       renderContext);
        child = cmark_node_next(child);
    }
}

static void OMRenderInlines(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            CGFloat scale,
                            const OMRenderContext *renderContext)
{
    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        switch (type) {
            case CMARK_NODE_TEXT: {
                BOOL renderedDisplayMath = NO;
                cmark_node *nextAfterDisplayMath = OMTryAppendMultiNodeDisplayMath(child,
                                                                                    theme,
                                                                                    output,
                                                                                    attributes,
                                                                                    scale,
                                                                                    &renderedDisplayMath,
                                                                                    renderContext);
                if (renderedDisplayMath) {
                    child = nextAfterDisplayMath;
                    continue;
                }
                const char *literal = cmark_node_get_literal(child);
                NSString *text = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                OMAppendTextWithMathSpans(text, theme, output, attributes, scale, renderContext);
                break;
            }
            case CMARK_NODE_SOFTBREAK:
                OMAppendString(output, @" ", attributes);
                break;
            case CMARK_NODE_LINEBREAK:
                OMAppendString(output, @"\n", attributes);
                break;
            case CMARK_NODE_CODE: {
                const char *literal = cmark_node_get_literal(child);
                NSString *text = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                NSFont *font = [attributes objectForKey:NSFontAttributeName];
                CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
                NSDictionary *codeAttrs = [theme codeAttributesForSize:size];
                NSMutableDictionary *inlineAttrs = [attributes mutableCopy];
                [inlineAttrs addEntriesFromDictionary:codeAttrs];
                OMAppendString(output, text, inlineAttrs);
                [inlineAttrs release];
                break;
            }
            case CMARK_NODE_EMPH: {
                NSMutableDictionary *emphAttrs = [attributes mutableCopy];
                NSFont *font = [emphAttrs objectForKey:NSFontAttributeName];
                NSFont *newFont = OMFontWithTraits(font, NSItalicFontMask);
                if (newFont != nil) {
                    [emphAttrs setObject:newFont forKey:NSFontAttributeName];
                }
                OMRenderInlines(child, theme, output, emphAttrs, scale, renderContext);
                [emphAttrs release];
                break;
            }
            case CMARK_NODE_STRONG: {
                NSMutableDictionary *strongAttrs = [attributes mutableCopy];
                NSFont *font = [strongAttrs objectForKey:NSFontAttributeName];
                NSFont *newFont = OMFontWithTraits(font, NSBoldFontMask);
                if (newFont != nil) {
                    [strongAttrs setObject:newFont forKey:NSFontAttributeName];
                }
                OMRenderInlines(child, theme, output, strongAttrs, scale, renderContext);
                [strongAttrs release];
                break;
            }
            case CMARK_NODE_LINK: {
                const char *url = cmark_node_get_url(child);
                NSString *urlString = url != NULL ? [NSString stringWithUTF8String:url] : @"";
                NSMutableDictionary *linkAttrs = [attributes mutableCopy];
                BOOL hasValidLinkURL = NO;
                if ([urlString length] > 0) {
                    NSURL *linkURL = OMResolvedLinkURL(urlString, renderContext);
                    if (linkURL != nil) {
                        [linkAttrs setObject:linkURL forKey:NSLinkAttributeName];
                        hasValidLinkURL = YES;
                    }
                }
                if (hasValidLinkURL && theme.linkColor != nil) {
                    [linkAttrs setObject:theme.linkColor forKey:NSForegroundColorAttributeName];
                }
                OMRenderInlines(child, theme, output, linkAttrs, scale, renderContext);
                [linkAttrs release];
                break;
            }
            case CMARK_NODE_IMAGE: {
                if (!OMShouldRenderImages(renderContext)) {
                    OMAppendString(output, OMFallbackImageTextForNode(child), attributes);
                } else {
                    NSAttributedString *attachment = OMImageAttachmentAttributedString(child,
                                                                                       attributes,
                                                                                       scale,
                                                                                       renderContext);
                    if (attachment != nil) {
                        OMAppendAttributedSegment(output, attachment);
                    } else {
                        OMAppendString(output, OMFallbackImageTextForNode(child), attributes);
                    }
                }
                break;
            }
            case CMARK_NODE_HTML_INLINE: {
                const char *literal = cmark_node_get_literal(child);
                OMAppendHTMLLiteral(literal, output, attributes, NO, renderContext);
                break;
            }
            case CMARK_NODE_CUSTOM_INLINE: {
                const char *literal = cmark_node_get_literal(child);
                if (literal != NULL) {
                    OMAppendHTMLLiteral(literal, output, attributes, NO, renderContext);
                } else {
                    OMRenderInlines(child, theme, output, attributes, scale, renderContext);
                }
                break;
            }
            default:
                OMRenderInlines(child, theme, output, attributes, scale, renderContext);
                break;
        }
        child = cmark_node_next(child);
    }
}

@end
