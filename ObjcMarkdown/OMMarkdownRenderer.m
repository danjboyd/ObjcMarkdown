// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMarkdownRenderer.h"
#import "OMAppKitSerialization.h"
#import "OMMermaidERDiagram.h"
#import "OMMermaidERDrawing.h"
#import "OMRenderedObject.h"
#import "OMBlockSignatureIndex.h"
#import "OMTheme.h"

#import <dispatch/dispatch.h>

#include "cmark-gfm.h"
#include "cmark-gfm-core-extensions.h"
#include "strikethrough.h"
#include "table.h"
#include "OMGFMParser.h"
#import "OMStrikethroughLayoutManager.h"
#include "OMEmojiShortcodes.inc"
#include <ctype.h>
#if defined(_WIN32)
#include <windows.h>
#include <gdiplus/gdiplus.h>
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
NSString * const OMMarkdownRendererHeadingLevelKey = @"OMMarkdownRendererHeadingLevel";
NSString * const OMMarkdownRendererHeadingTitleKey = @"OMMarkdownRendererHeadingTitle";
NSString * const OMMarkdownRendererHeadingAnchorKey = @"OMMarkdownRendererHeadingAnchor";
NSString * const OMMarkdownRendererHeadingRangeKey = @"OMMarkdownRendererHeadingRange";
NSString * const OMMarkdownRendererHeadingSourceLineKey = @"OMMarkdownRendererHeadingSourceLine";
NSString * const OMMarkdownRendererHeadingAnchorAttributeName = @"OMMarkdownRendererHeadingAnchor";
NSString * const OMMarkdownRendererBlockquoteColorAttributeName = @"OMMarkdownRendererBlockquoteColor";
NSString * const OMMarkdownRendererDiagramRangeKey = @"OMMarkdownRendererDiagramRange";
NSString * const OMMarkdownRendererDiagramSourceKey = @"OMMarkdownRendererDiagramSource";

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
    NSMutableArray *diagramBlocks;
    NSMutableArray *headings;
    // Slugs handed out so far in this document, for GitHub's de-duplication.
    NSMutableDictionary *headingSlugCounts;
    // The list contexts enclosing the block being rendered (see OMRenderList).
    NSMutableArray *listStack;
    // Hashed source lines for block IDs (see OMBlockSignatureIndex).
    OMBlockSignatureIndex *blockSignatures;
    // One entry per enclosing block quote: YES for a GitHub alert, whose
    // text keeps the normal colour instead of the muted quote colour.
    NSMutableArray *quoteKinds;
    NSMutableArray *consumedDisplayMathLineRanges;
    // Raw source of the current block's formulas, keyed by their unescaped
    // form; see OMPrepareRawMathSources.
    NSMutableDictionary *rawMathSources;
    OMMathPerfStats *mathPerfStats;
    CGFloat layoutWidth;
    BOOL allowTableHorizontalOverflow;
    BOOL asynchronousMathGenerationEnabled;
} OMRenderContext;

// Indent of a list item's content, so every block in an item (not only its
// first line) lines up under the item's text. Zero outside lists.
static CGFloat OMListContentIndent(const OMRenderContext *renderContext, CGFloat scale)
{
    NSUInteger depth = (renderContext != NULL && renderContext->listStack != nil) ? [renderContext->listStack count] : 0;
    return depth > 0 ? ((CGFloat)depth * 18.0 + 20.0) * scale : 0.0;
}

static NSString *OMExecutablePathNamed(NSString *name);
static BOOL OMURLUsesRemoteScheme(NSURL *url);
static NSString *OMLaTeXExecutablePath(void);
static NSString *OMPlainTexExecutablePath(void);
static NSString *OMDviPngExecutablePath(void);

static NSTimeInterval OMNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

#if defined(_WIN32)
static NSString *OMWindowsNormalizedPath(NSString *value)
{
    if (value == nil) {
        return nil;
    }
    return [value stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
}

static NSString *OMWindowsQuoteCommandArgument(NSString *value)
{
    if (value == nil) {
        return @"\"\"";
    }

    NSMutableString *quoted = [NSMutableString stringWithString:@"\""];
    NSUInteger length = [value length];
    NSUInteger index = 0;
    while (index < length) {
        unichar character = [value characterAtIndex:index];
        if (character == '\\') {
            NSUInteger slashStart = index;
            while (index < length && [value characterAtIndex:index] == '\\') {
                index += 1;
            }
            NSUInteger slashCount = index - slashStart;
            BOOL beforeQuoteOrEnd = (index == length || [value characterAtIndex:index] == '"');
            NSUInteger copies = beforeQuoteOrEnd ? (slashCount * 2) : slashCount;
            while (copies-- > 0) {
                [quoted appendString:@"\\"];
            }
            if (index < length && [value characterAtIndex:index] == '"') {
                [quoted appendString:@"\\\""];
                index += 1;
            }
            continue;
        }
        if (character == '"') {
            [quoted appendString:@"\\\""];
        } else {
            [quoted appendFormat:@"%C", character];
        }
        index += 1;
    }
    [quoted appendString:@"\""];
    return quoted;
}

static NSString *OMWindowsTaskScriptPath(NSString *workingDirectory)
{
    if (workingDirectory == nil || [workingDirectory length] == 0) {
        return nil;
    }
    return [workingDirectory stringByAppendingPathComponent:@"omd-run-task.cmd"];
}
#endif

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
    static dispatch_once_t onceToken;
    static BOOL enabled = NO;
    dispatch_once(&onceToken, ^{
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
    });
    return enabled;
}

#if defined(_WIN32)
static void OMMathDebugLog(NSString *message)
{
    if (message == nil || [message length] == 0) {
        return;
    }

    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ObjcMarkdown-math.log"];
    NSData *existing = [NSData dataWithContentsOfFile:logPath];
    if (existing == nil) {
        [[NSData data] writeToFile:logPath atomically:YES];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (handle == nil) {
        return;
    }

    [handle seekToEndOfFile];
    NSString *line = [NSString stringWithFormat:@"%@\r\n", message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data != nil) {
        [handle writeData:data];
    }
    [handle closeFile];
}

static NSString *OMMathLogSnippet(NSString *value)
{
    if (value == nil) {
        return @"<nil>";
    }

    NSString *sanitized = [[value stringByReplacingOccurrencesOfString:@"\r" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if ([sanitized length] > 160) {
        return [[sanitized substringToIndex:160] stringByAppendingString:@"..."];
    }
    return sanitized;
}

static NSString *OMMathDebugStringFromData(NSData *data)
{
    if (data == nil || [data length] == 0) {
        return @"";
    }

    NSString *decoded = [[[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding] autorelease];
    if (decoded == nil) {
        decoded = [[[NSString alloc] initWithData:data
                                         encoding:NSISOLatin1StringEncoding] autorelease];
    }
    return OMMathLogSnippet(decoded);
}

static void OMLogMathBackendStateIfNeeded(void)
{
    static BOOL logged = NO;
    if (logged) {
        return;
    }
    logged = YES;

    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *pathValue = [environment objectForKey:@"PATH"];
    OMMathDebugLog([NSString stringWithFormat:@"backend: latex=%@ tex=%@ dvipng=%@ path=%@",
                    OMMathLogSnippet(OMLaTeXExecutablePath()),
                    OMMathLogSnippet(OMPlainTexExecutablePath()),
                    OMMathLogSnippet(OMDviPngExecutablePath()),
                    OMMathLogSnippet(pathValue)]);
}
#else
static void OMLogMathBackendStateIfNeeded(void)
{
}
#endif

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

static BOOL OMNativeDiagramRenderingEnabled(const OMRenderContext *renderContext)
{
    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    if (options == nil) {
        return YES;
    }
    return [options diagramRenderingPolicy] == OMMarkdownDiagramRenderingPolicyNative;
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
    static dispatch_once_t onceToken;
    static BOOL available = NO;
    dispatch_once(&onceToken, ^{
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

    });
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
    static dispatch_once_t onceToken;
    static CGFloat factor =
#if defined(_WIN32)
        3.0;
#else
        2.0;
#endif
    dispatch_once(&onceToken, ^{
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
    });
    return factor;
}

// Re-rendering a formula bumps its generation, which changes every cache key
// built from it; the stale NSCache entries are evicted in time.
static NSMutableDictionary *OMMathFormulaGenerations(void)
{
    static NSMutableDictionary *generations = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        generations = [[NSMutableDictionary alloc] init];
    });
    return generations;
}

static NSString *OMMathVersionedFormula(NSString *formula)
{
    NSMutableDictionary *generations = OMMathFormulaGenerations();
    NSNumber *generation = nil;
    @synchronized (generations) {
        generation = [[[generations objectForKey:formula] retain] autorelease];
    }
    if (generation == nil) {
        return formula;
    }
    return [NSString stringWithFormat:@"%@\x1F%lu", formula, (unsigned long)[generation unsignedIntegerValue]];
}

static NSString *OMMathAssetCacheKey(NSString *formula, BOOL displayMath, CGFloat renderZoom)
{
    return [NSString stringWithFormat:@"%@|%.2f|%@",
            displayMath ? @"display" : @"inline",
            renderZoom,
            OMMathVersionedFormula(formula)];
}

static NSString *OMMathFormulaCacheKey(NSString *formula, BOOL displayMath)
{
    return [NSString stringWithFormat:@"%@|%@",
            displayMath ? @"display" : @"inline",
            OMMathVersionedFormula(formula)];
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

static void OMApplyItalicFallbackIfNeeded(NSMutableDictionary *attributes, NSFont *originalFont, NSFont *resolvedFont)
{
    if (attributes == nil) {
        return;
    }

    if (resolvedFont != nil && originalFont != nil && resolvedFont != originalFont) {
        return;
    }

    if ([attributes objectForKey:NSObliquenessAttributeName] == nil) {
        [attributes setObject:[NSNumber numberWithDouble:0.2]
                       forKey:NSObliquenessAttributeName];
    }
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
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSMutableDictionary alloc] init];
    });
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

// Marks the newline of a Markdown hard break while a paragraph renders.
static NSString * const OMHardLineBreakAttributeName = @"OMHardLineBreak";

// GNUstep lays out only '\n' as a line break (not U+2028), so a hard break
// starts a new text paragraph. Drop the paragraph spacing at those breaks so
// the Markdown paragraph keeps its normal line rhythm.
static void OMTightenHardLineBreaks(NSMutableAttributedString *output, NSRange range)
{
    NSUInteger segmentStart = range.location;
    NSUInteger index = range.location;
    NSUInteger end = NSMaxRange(range);
    while (index < end) {
        NSRange effective;
        id marker = [output attribute:OMHardLineBreakAttributeName atIndex:index effectiveRange:&effective];
        if (marker == nil) {
            index = MIN(NSMaxRange(effective), end);
            continue;
        }
        NSParagraphStyle *style = [output attribute:NSParagraphStyleAttributeName atIndex:segmentStart effectiveRange:NULL];
        if (style != nil && [style paragraphSpacing] > 0.0) {
            NSMutableParagraphStyle *tight = [[style mutableCopy] autorelease];
            [tight setParagraphSpacing:0.0];
            [output addAttribute:NSParagraphStyleAttributeName
                           value:tight
                           range:NSMakeRange(segmentStart, index + 1 - segmentStart)];
        }
        [output removeAttribute:OMHardLineBreakAttributeName range:NSMakeRange(index, 1)];
        segmentStart = index + 1;
        index += 1;
    }
}

// Kind, source and Markdown of an object while the document renders; the
// final pass turns it into an OMRenderedObject once block anchors are known.
static NSString * const OMPendingRenderedObjectAttributeName = @"OMPendingRenderedObject";
static NSString * const OMPendingObjectKindKey = @"kind";
static NSString * const OMPendingObjectSourceKey = @"source";
static NSString * const OMPendingObjectMarkdownKey = @"markdown";

// Tags the attachment characters appended to output since start.
static void OMTagAppendedObject(NSMutableAttributedString *output,
                                NSUInteger start,
                                OMRenderedObjectKind kind,
                                NSString *source,
                                NSString *markdown)
{
    if (output == nil || start >= [output length] || source == nil) {
        return;
    }
    NSDictionary *pending = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithInteger:kind], OMPendingObjectKindKey,
                             source, OMPendingObjectSourceKey,
                             (markdown != nil ? markdown : source), OMPendingObjectMarkdownKey,
                             nil];
    NSString *text = [output string];
    NSUInteger index = start;
    for (; index < [output length]; index++) {
        if ([text characterAtIndex:index] == NSAttachmentCharacter &&
            [output attribute:NSAttachmentAttributeName atIndex:index effectiveRange:NULL] != nil) {
            [output addAttribute:OMPendingRenderedObjectAttributeName value:pending range:NSMakeRange(index, 1)];
        }
    }
}

static void OMAppendInlineTextFromNode(cmark_node *node, NSMutableString *buffer);

// The node's raw source lines, joined with newlines.
static NSString *OMSourceTextForNodeLines(cmark_node *node, const OMRenderContext *renderContext)
{
    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    int firstLine = cmark_node_get_start_line(node);
    int lastLine = cmark_node_get_end_line(node);
    if (sourceLines == nil || firstLine < 1 || lastLine < firstLine || (NSUInteger)lastLine > [sourceLines count]) {
        return nil;
    }
    NSArray *lines = [sourceLines subarrayWithRange:NSMakeRange((NSUInteger)firstLine - 1,
                                                                (NSUInteger)(lastLine - firstLine + 1))];
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *OMImageMarkdownForNode(cmark_node *imageNode)
{
    const char *url = cmark_node_get_url(imageNode);
    const char *title = cmark_node_get_title(imageNode);
    NSString *urlString = url != NULL ? [NSString stringWithUTF8String:url] : @"";
    NSString *titleString = title != NULL ? [NSString stringWithUTF8String:title] : @"";
    NSMutableString *alt = [NSMutableString string];
    OMAppendInlineTextFromNode(imageNode, alt);
    if ([urlString rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound) {
        urlString = [NSString stringWithFormat:@"<%@>", urlString];
    }
    if ([titleString length] > 0) {
        return [NSString stringWithFormat:@"![%@](%@ \"%@\")", alt, urlString,
                [titleString stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    }
    return [NSString stringWithFormat:@"![%@](%@)", alt, urlString];
}

// The smallest block anchor containing location gives the object's source lines.
static NSRange OMSourceLineRangeForTargetLocation(NSArray *blockAnchors, NSUInteger location)
{
    NSRange best = NSMakeRange(NSNotFound, 0);
    NSUInteger bestLength = NSUIntegerMax;
    for (NSDictionary *anchor in blockAnchors) {
        NSUInteger targetStart = [[anchor objectForKey:OMMarkdownRendererAnchorTargetStartKey] unsignedIntegerValue];
        NSUInteger targetLength = [[anchor objectForKey:OMMarkdownRendererAnchorTargetLengthKey] unsignedIntegerValue];
        if (location < targetStart || location >= targetStart + targetLength || targetLength >= bestLength) {
            continue;
        }
        NSUInteger startLine = [[anchor objectForKey:OMMarkdownRendererAnchorSourceStartLineKey] unsignedIntegerValue];
        NSUInteger endLine = [[anchor objectForKey:OMMarkdownRendererAnchorSourceEndLineKey] unsignedIntegerValue];
        if (startLine == 0 || endLine < startLine) {
            continue;
        }
        best = NSMakeRange(startLine, endLine - startLine + 1);
        bestLength = targetLength;
    }
    return best;
}

// CommonMark drops a backslash before ASCII punctuation in text, so a formula
// from a cmark text node is compared with its source in that form too.
static NSString *OMCommonMarkUnescaped(NSString *text)
{
    if ([text rangeOfString:@"\\"].location == NSNotFound) {
        return text;
    }
    NSMutableString *result = [NSMutableString stringWithCapacity:[text length]];
    NSUInteger length = [text length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [text characterAtIndex:index];
        if (ch == '\\' && index + 1 < length) {
            unichar next = [text characterAtIndex:index + 1];
            if (next < 128 && ispunct((int)next)) {
                [result appendFormat:@"%C", next];
                index += 2;
                continue;
            }
        }
        [result appendFormat:@"%C", ch];
        index += 1;
    }
    return result;
}

static BOOL OMMathSourceMatchesFormula(NSString *content, NSString *formula)
{
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *target = [formula stringByTrimmingCharactersInSet:space];
    return [[content stringByTrimmingCharactersInSet:space] isEqualToString:target] ||
           [[OMCommonMarkUnescaped(content) stringByTrimmingCharactersInSet:space] isEqualToString:target];
}

// The occurrence-th "$formula$" (or "$$formula$$") inside span, delimiters included.
static NSRange OMFindMathSource(NSString *markdown,
                                NSRange span,
                                NSString *formula,
                                BOOL display,
                                NSUInteger occurrence)
{
    NSUInteger end = NSMaxRange(span);
    NSUInteger delimiterLength = display ? 2 : 1;
    NSUInteger matches = 0;
    NSUInteger index = span.location;
    while (index < end) {
        unichar ch = [markdown characterAtIndex:index];
        if (ch == '\\') {
            index += 2;
            continue;
        }
        if (ch != '$') {
            index += 1;
            continue;
        }
        BOOL doubled = (index + 1 < end && [markdown characterAtIndex:index + 1] == '$');
        if (doubled != display) {
            index += doubled ? 2 : 1;
            continue;
        }
        NSUInteger contentStart = index + delimiterLength;
        NSUInteger close = contentStart;
        while (close < end) {
            unichar c = [markdown characterAtIndex:close];
            if (c == '\\') {
                close += 2;
                continue;
            }
            if (c == '$') {
                BOOL closeDoubled = (close + 1 < end && [markdown characterAtIndex:close + 1] == '$');
                if (closeDoubled == display) {
                    break;
                }
            }
            close += 1;
        }
        if (close >= end) {
            break;
        }
        NSString *content = [markdown substringWithRange:NSMakeRange(contentStart, close - contentStart)];
        if (OMMathSourceMatchesFormula(content, formula)) {
            if (matches == occurrence) {
                return NSMakeRange(index, close + delimiterLength - index);
            }
            matches += 1;
        }
        index = close + delimiterLength;
    }
    return NSMakeRange(NSNotFound, 0);
}

// The destination of the image syntax starting at index ("![alt](dest ...)"),
// and the syntax's full range; NSNotFound if it isn't an inline image.
static NSRange OMImageSyntaxRange(NSString *text, NSUInteger index, NSUInteger end, NSString **destination)
{
    NSRange notFound = NSMakeRange(NSNotFound, 0);
    if (index + 1 >= end || [text characterAtIndex:index] != '!' || [text characterAtIndex:index + 1] != '[') {
        return notFound;
    }
    NSRange bracket = [text rangeOfString:@"](" options:0 range:NSMakeRange(index, end - index)];
    if (bracket.location == NSNotFound) {
        return notFound;
    }
    NSUInteger cursor = NSMaxRange(bracket);
    NSUInteger destStart = cursor;
    NSUInteger destEnd = cursor;
    if (cursor < end && [text characterAtIndex:cursor] == '<') {
        NSRange close = [text rangeOfString:@">" options:0 range:NSMakeRange(cursor, end - cursor)];
        if (close.location == NSNotFound) {
            return notFound;
        }
        destStart = cursor + 1;
        destEnd = close.location;
        cursor = close.location + 1;
    } else {
        while (destEnd < end) {
            unichar c = [text characterAtIndex:destEnd];
            if (c == ')' || c == ' ' || c == '\t' || c == '\n') {
                break;
            }
            destEnd += 1;
        }
        cursor = destEnd;
    }
    NSRange closeParen = [text rangeOfString:@")" options:0 range:NSMakeRange(cursor, end - cursor)];
    if (closeParen.location == NSNotFound) {
        return notFound;
    }
    if (destination != NULL) {
        *destination = [text substringWithRange:NSMakeRange(destStart, destEnd - destStart)];
    }
    return NSMakeRange(index, NSMaxRange(closeParen) - index);
}

// The occurrence-th inline image in span whose destination matches the
// object's reconstructed Markdown.
static NSRange OMFindImageSource(NSString *markdown, NSRange span, NSString *imageMarkdown, NSUInteger occurrence)
{
    NSString *target = nil;
    if (OMImageSyntaxRange(imageMarkdown, 0, [imageMarkdown length], &target).location == NSNotFound || target == nil) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger end = NSMaxRange(span);
    NSUInteger matches = 0;
    NSUInteger index = span.location;
    while (index + 1 < end) {
        NSRange bang = [markdown rangeOfString:@"![" options:0 range:NSMakeRange(index, end - index)];
        if (bang.location == NSNotFound) {
            break;
        }
        NSString *destination = nil;
        NSRange syntax = OMImageSyntaxRange(markdown, bang.location, end, &destination);
        if (syntax.location != NSNotFound && [destination isEqualToString:target]) {
            if (matches == occurrence) {
                return syntax;
            }
            matches += 1;
        }
        index = bang.location + 2;
    }
    return NSMakeRange(NSNotFound, 0);
}

// Character span of 1-based source lines, without the final line break.
static NSRange OMCharacterSpanForLines(NSString *markdown, NSArray *lineStarts, NSRange lineRange)
{
    if (lineRange.location == NSNotFound || lineRange.location == 0 ||
        lineRange.location > [lineStarts count]) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger lastLine = NSMaxRange(lineRange) - 1;
    NSUInteger start = [[lineStarts objectAtIndex:lineRange.location - 1] unsignedIntegerValue];
    NSUInteger end = (lastLine < [lineStarts count])
        ? [[lineStarts objectAtIndex:lastLine] unsignedIntegerValue]
        : [markdown length];
    while (end > start && ([markdown characterAtIndex:end - 1] == '\n' || [markdown characterAtIndex:end - 1] == '\r')) {
        end -= 1;
    }
    return NSMakeRange(start, end - start);
}

static NSRange OMSourceRangeForPendingObject(NSString *markdown,
                                             NSRange span,
                                             OMRenderedObjectKind kind,
                                             NSString *source,
                                             NSUInteger occurrence)
{
    NSRange found = NSMakeRange(NSNotFound, 0);
    if (span.location == NSNotFound) {
        return found;
    }
    if (kind == OMRenderedObjectKindInlineMath || kind == OMRenderedObjectKindDisplayMath) {
        found = OMFindMathSource(markdown, span, source, kind == OMRenderedObjectKindDisplayMath, occurrence);
    } else if (kind == OMRenderedObjectKindImage) {
        found = OMFindImageSource(markdown, span, source, occurrence);
    }
    return found.location != NSNotFound ? found : span;
}

static void OMResolvePendingRenderedObjects(NSMutableAttributedString *output,
                                            NSArray *blockAnchors,
                                            NSString *markdown)
{
    NSMutableArray *lineStarts = [NSMutableArray arrayWithObject:[NSNumber numberWithUnsignedInteger:0]];
    NSUInteger scan = 0;
    for (; scan < [markdown length]; scan++) {
        if ([markdown characterAtIndex:scan] == '\n') {
            [lineStarts addObject:[NSNumber numberWithUnsignedInteger:scan + 1]];
        }
    }
    // Repeats of the same object in one block resolve in document order.
    NSMutableDictionary *occurrences = [NSMutableDictionary dictionary];

    NSUInteger index = 0;
    while (index < [output length]) {
        NSRange effective;
        NSDictionary *pending = [output attribute:OMPendingRenderedObjectAttributeName
                                          atIndex:index
                                   effectiveRange:&effective];
        if (pending != nil) {
            NSUInteger location = effective.location;
            for (; location < NSMaxRange(effective); location++) {
                OMRenderedObjectKind kind = (OMRenderedObjectKind)[[pending objectForKey:OMPendingObjectKindKey] integerValue];
                NSString *source = [pending objectForKey:OMPendingObjectSourceKey];
                NSRange lineRange = OMSourceLineRangeForTargetLocation(blockAnchors, location);
                NSRange span = OMCharacterSpanForLines(markdown, lineStarts, lineRange);
                // Count repeats by what the search matches on: images by destination.
                NSString *matchText = source;
                if (kind == OMRenderedObjectKindImage) {
                    NSString *destination = nil;
                    OMImageSyntaxRange(source, 0, [source length], &destination);
                    matchText = destination != nil ? destination : source;
                }
                NSString *occurrenceKey = [NSString stringWithFormat:@"%lu|%ld|%@",
                                           (unsigned long)span.location, (long)kind, matchText];
                NSUInteger occurrence = [[occurrences objectForKey:occurrenceKey] unsignedIntegerValue];
                [occurrences setObject:[NSNumber numberWithUnsignedInteger:occurrence + 1] forKey:occurrenceKey];
                OMRenderedObject *object = [[OMRenderedObject alloc]
                    initWithKind:kind
                          source:source
                        markdown:[pending objectForKey:OMPendingObjectMarkdownKey]
                 sourceLineRange:lineRange
                     sourceRange:OMSourceRangeForPendingObject(markdown, span, kind, source, occurrence)];
                [output addAttribute:OMRenderedObjectAttributeName value:object range:NSMakeRange(location, 1)];
                [object release];
            }
            [output removeAttribute:OMPendingRenderedObjectAttributeName range:effective];
        }
        index = NSMaxRange(effective);
    }
}

// GNUstep's typesetter ignores paragraph spacing and honours only minimum
// line heights, so the empty line between blocks is what spaces them. Size it
// like GitHub: 1em between blocks, 1.5em before a heading, plus the code
// background's padding next to a code block. Blank lines inside code blocks
// keep their height.
static void OMSizeBlockGaps(NSMutableAttributedString *output,
                            NSArray *codeRanges,
                            CGFloat baseSize,
                            CGFloat scale)
{
    NSString *text = [output string];
    NSUInteger length = [text length];
    if (length < 2) {
        return;
    }
    NSMutableIndexSet *code = [NSMutableIndexSet indexSet];
    for (NSValue *value in codeRanges) {
        [code addIndexesInRange:[value rangeValue]];
    }
    CGFloat codePadding = 14.0 * scale;
    NSMutableDictionary *styles = [NSMutableDictionary dictionary];
    NSUInteger index = 1;
    for (; index < length; index++) {
        if ([text characterAtIndex:index] != '\n' || [text characterAtIndex:index - 1] != '\n' ||
            [code containsIndex:index]) {
            continue;
        }
        BOOL beforeHeading = (index + 1 < length &&
                              [output attribute:OMMarkdownRendererHeadingAnchorAttributeName
                                        atIndex:index + 1
                                 effectiveRange:NULL] != nil);
        CGFloat gap = baseSize * (beforeHeading ? 1.5 : 1.0);
        if ([code containsIndex:index - 1]) {
            gap += codePadding;
        }
        if (index + 1 < length && [code containsIndex:index + 1]) {
            gap += codePadding;
        }
        gap = floor(gap + 0.5);
        NSNumber *key = [NSNumber numberWithDouble:gap];
        NSMutableParagraphStyle *style = [styles objectForKey:key];
        if (style == nil) {
            style = [[[NSMutableParagraphStyle alloc] init] autorelease];
            [style setMinimumLineHeight:gap];
            [style setMaximumLineHeight:gap];
            [styles setObject:style forKey:key];
        }
        [output addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(index, 1)];
    }
}

// Ranges recorded before the trailing newlines were trimmed, cut to the text
// that remains (a quote or code block ending the document ran past it).
static NSArray *OMRangesClampedToLength(NSArray *ranges, NSUInteger length)
{
    NSMutableArray *clamped = [NSMutableArray arrayWithCapacity:[ranges count]];
    for (NSValue *value in ranges) {
        NSRange range = [value rangeValue];
        if (range.location >= length) {
            continue;
        }
        if (NSMaxRange(range) > length) {
            range.length = length - range.location;
        }
        [clamped addObject:[NSValue valueWithRange:range]];
    }
    return clamped;
}

static NSCharacterSet *OMEmojiCharacterSet(void);

// Fonts chosen for emoji by default are colour fonts GNUstep can't draw
// (they show as "?"); draw the table's emoji with Symbola instead.
static void OMApplyEmojiFont(NSMutableAttributedString *output, NSArray *codeRanges)
{
    static NSString *emojiFontName = @"Symbola";
    NSString *text = [output string];
    NSCharacterSet *emoji = OMEmojiCharacterSet();
    NSRange found = [text rangeOfCharacterFromSet:emoji];
    if (found.location == NSNotFound || [NSFont fontWithName:emojiFontName size:12.0] == nil) {
        return;
    }
    NSMutableIndexSet *code = [NSMutableIndexSet indexSet];
    for (NSValue *value in codeRanges) {
        [code addIndexesInRange:[value rangeValue]];
    }
    while (found.location != NSNotFound) {
        if (![code containsIndex:found.location]) {
            NSFont *font = [output attribute:NSFontAttributeName atIndex:found.location effectiveRange:NULL];
            NSFont *emojiFont = [NSFont fontWithName:emojiFontName size:(font != nil ? [font pointSize] : 14.0)];
            if (emojiFont != nil) {
                [output addAttribute:NSFontAttributeName value:emojiFont range:found];
            }
        }
        NSUInteger next = NSMaxRange(found);
        found = next < [text length]
            ? [text rangeOfCharacterFromSet:emoji options:0 range:NSMakeRange(next, [text length] - next)]
            : NSMakeRange(NSNotFound, 0);
    }
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

static BOOL OMIsFrontMatterFence(NSString *line, BOOL closing)
{
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (closing && [trimmed isEqualToString:@"..."]) {
        return YES;
    }
    return [trimmed isEqualToString:@"---"] && [line hasPrefix:@"---"];
}

// Hides a leading YAML front matter block. Its lines become empty rather than
// removed, so cmark's line numbers still match the editor's.
static NSString *OMMarkdownByBlankingFrontMatter(NSString *markdown)
{
    if (![markdown hasPrefix:@"---"]) {
        return markdown;
    }
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    if ([lines count] < 3 || !OMIsFrontMatterFence([lines objectAtIndex:0], NO)) {
        return markdown;
    }
    // Require YAML-looking content ("key:") so a leading thematic break
    // followed by a setext heading is not mistaken for metadata.
    NSString *firstContent = [[lines objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSRange colon = [firstContent rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0 ||
        [firstContent rangeOfString:@" "].location < colon.location) {
        return markdown;
    }
    NSUInteger closingIndex = 1;
    for (; closingIndex < [lines count]; closingIndex++) {
        if (OMIsFrontMatterFence([lines objectAtIndex:closingIndex], YES)) {
            break;
        }
    }
    if (closingIndex >= [lines count]) {
        return markdown;
    }
    NSMutableArray *blanked = [[lines mutableCopy] autorelease];
    NSUInteger index = 0;
    for (; index <= closingIndex; index++) {
        [blanked replaceObjectAtIndex:index withObject:@""];
    }
    return [blanked componentsJoinedByString:@"\n"];
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

static NSString *OMSourceFragmentForNode(cmark_node *node, NSArray *sourceLines)
{
    if (node == NULL || sourceLines == nil) {
        return nil;
    }

    NSUInteger startLine = 0;
    NSUInteger endLine = 0;
    if (!OMNodeLineBounds(node, &startLine, &endLine)) {
        return nil;
    }

    int startColumnValue = cmark_node_get_start_column(node);
    int endColumnValue = cmark_node_get_end_column(node);
    if (startColumnValue <= 0 || endColumnValue <= 0) {
        return nil;
    }

    NSUInteger lineCount = [sourceLines count];
    if (startLine == 0 || startLine > lineCount) {
        return nil;
    }
    if (endLine < startLine) {
        endLine = startLine;
    }
    if (endLine > lineCount) {
        endLine = lineCount;
    }

    NSMutableString *fragment = [NSMutableString string];
    NSUInteger line = startLine;
    for (; line <= endLine; line++) {
        NSString *sourceLine = [sourceLines objectAtIndex:line - 1];
        NSUInteger lineLength = [sourceLine length];
        NSUInteger lineStartColumn = (line == startLine) ? (NSUInteger)startColumnValue : 1;
        NSUInteger lineEndColumn = (line == endLine) ? (NSUInteger)endColumnValue : lineLength;

        if (lineStartColumn == 0 || lineStartColumn > lineLength + 1) {
            return nil;
        }
        if (lineEndColumn > lineLength) {
            lineEndColumn = lineLength;
        }

        if (lineStartColumn <= lineEndColumn && lineLength > 0) {
            NSRange range = NSMakeRange(lineStartColumn - 1,
                                        lineEndColumn - lineStartColumn + 1);
            [fragment appendString:[sourceLine substringWithRange:range]];
        }

        if (line < endLine) {
            [fragment appendString:@"\n"];
        }
    }

    return fragment;
}

static BOOL OMSourceLineMatchesDisplayMathFence(NSArray *sourceLines, NSUInteger lineNumber)
{
    if (sourceLines == nil || lineNumber == 0 || lineNumber > [sourceLines count]) {
        return NO;
    }

    NSString *line = [sourceLines objectAtIndex:lineNumber - 1];
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed isEqualToString:@"$$"];
}

static BOOL OMLineNumberFallsWithinRanges(NSUInteger lineNumber, NSArray *ranges)
{
    if (lineNumber == 0 || ranges == nil) {
        return NO;
    }

    for (NSValue *value in ranges) {
        NSRange range = [value rangeValue];
        if (range.length == 0) {
            continue;
        }
        if (lineNumber >= range.location && lineNumber < (range.location + range.length)) {
            return YES;
        }
    }
    return NO;
}

static BOOL OMDisplayMathLineAlreadyConsumed(NSUInteger lineNumber,
                                             const OMRenderContext *renderContext)
{
    NSArray *ranges = renderContext != NULL ? renderContext->consumedDisplayMathLineRanges : nil;
    return OMLineNumberFallsWithinRanges(lineNumber, ranges);
}

static void OMConsumeDisplayMathLineRange(NSUInteger startLine,
                                          NSUInteger endLine,
                                          const OMRenderContext *renderContext)
{
    NSMutableArray *ranges = renderContext != NULL ? renderContext->consumedDisplayMathLineRanges : nil;
    if (ranges == nil || startLine == 0 || endLine < startLine) {
        return;
    }

    [ranges addObject:[NSValue valueWithRange:NSMakeRange(startLine, endLine - startLine + 1)]];
}

static NSString *OMRawDisplayMathFormulaForFenceRange(NSArray *sourceLines,
                                                      NSUInteger startFenceLine,
                                                      NSUInteger endFenceLine)
{
    if (sourceLines == nil || startFenceLine == 0 || endFenceLine <= startFenceLine) {
        return nil;
    }

    NSMutableString *formula = [NSMutableString string];
    NSUInteger line = startFenceLine + 1;
    for (; line < endFenceLine; line++) {
        if ([formula length] > 0) {
            [formula appendString:@"\n"];
        }
        [formula appendString:[sourceLines objectAtIndex:line - 1]];
    }

    return [formula stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL OMDisplayMathFenceRangeStartingAtLine(NSArray *sourceLines,
                                                  NSUInteger startFenceLine,
                                                  NSUInteger *endFenceLineOut,
                                                  NSString **formulaOut)
{
    if (!OMSourceLineMatchesDisplayMathFence(sourceLines, startFenceLine)) {
        return NO;
    }

    NSUInteger count = [sourceLines count];
    NSUInteger line = startFenceLine + 1;
    for (; line <= count; line++) {
        if (!OMSourceLineMatchesDisplayMathFence(sourceLines, line)) {
            continue;
        }

        NSString *formula = OMRawDisplayMathFormulaForFenceRange(sourceLines,
                                                                 startFenceLine,
                                                                 line);
        if (formula == nil || [formula length] == 0) {
            return NO;
        }

        if (endFenceLineOut != NULL) {
            *endFenceLineOut = line;
        }
        if (formulaOut != NULL) {
            *formulaOut = formula;
        }
        return YES;
    }

    return NO;
}

static NSString *OMStableBlockIDForTypeAndLineRange(cmark_node_type nodeType,
                                                    NSUInteger startLine,
                                                    NSUInteger endLine,
                                                    const OMRenderContext *renderContext)
{
    OMBlockSignatureIndex *signatures = renderContext != NULL ? renderContext->blockSignatures : nil;
    if (signatures == nil) {
        return nil;
    }
    return [signatures blockIDForNodeType:(int)nodeType startLine:startLine endLine:endLine];
}

static void OMRecordBlockAnchorForSourceRange(cmark_node *node,
                                              NSUInteger sourceStartLine,
                                              NSUInteger sourceEndLine,
                                              NSUInteger targetStart,
                                              NSUInteger targetEnd,
                                              const OMRenderContext *renderContext)
{
    NSMutableArray *blockAnchors = renderContext != NULL ? renderContext->blockAnchors : nil;
    if (blockAnchors == nil || node == NULL) {
        return;
    }
    if (sourceStartLine == 0 || sourceEndLine < sourceStartLine) {
        return;
    }
    if (targetEnd <= targetStart) {
        return;
    }

    NSMutableDictionary *anchor = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedInteger:sourceStartLine], OMMarkdownRendererAnchorSourceStartLineKey,
                                   [NSNumber numberWithUnsignedInteger:sourceEndLine], OMMarkdownRendererAnchorSourceEndLineKey,
                                   [NSNumber numberWithUnsignedInteger:targetStart], OMMarkdownRendererAnchorTargetStartKey,
                                   [NSNumber numberWithUnsignedInteger:(targetEnd - targetStart)], OMMarkdownRendererAnchorTargetLengthKey,
                                   nil];
    NSString *blockID = OMStableBlockIDForTypeAndLineRange(cmark_node_get_type(node),
                                                           sourceStartLine,
                                                           sourceEndLine,
                                                           renderContext);
    if (blockID != nil && [blockID length] > 0) {
        [anchor setObject:blockID forKey:OMMarkdownRendererAnchorBlockIDKey];
    }
    [blockAnchors addObject:anchor];
}

static void OMRecordBlockAnchor(cmark_node *node,
                                NSUInteger targetStart,
                                NSUInteger targetEnd,
                                const OMRenderContext *renderContext)
{
    NSUInteger sourceStartLine = 0;
    NSUInteger sourceEndLine = 0;
    if (!OMNodeLineBounds(node, &sourceStartLine, &sourceEndLine)) {
        return;
    }
    OMRecordBlockAnchorForSourceRange(node,
                                      sourceStartLine,
                                      sourceEndLine,
                                      targetStart,
                                      targetEnd,
                                      renderContext);
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

static void OMAppendDisplayMathFormula(NSString *formula,
                                       OMTheme *theme,
                                       NSMutableAttributedString *output,
                                       NSMutableDictionary *attributes,
                                       CGFloat scale,
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
        // Disc, circle, then square with nesting, as GitHub does.
        NSUInteger depth = [listStack count];
        return depth <= 1 ? @"\u2022 " : (depth == 2 ? @"\u25E6 " : @"\u25AA ");
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
    // GitHub's heading sizes, relative to body text.
    static const CGFloat scales[6] = { 2.0, 1.5, 1.25, 1.0, 0.875, 0.85 };
    CGFloat baseSize = theme.baseFont != nil ? [theme.baseFont pointSize] : 14.0;
    NSUInteger idx = level > 0 ? level - 1 : 0;
    if (idx > 5) {
        idx = 5;
    }
    return [theme headingAttributesForSize:(baseSize * scales[idx] * scale)];
}

// A horizontal rule drawn as a line, replacing rows of box-drawing glyphs
// (which reflowed badly and were copied as text).
@interface OMRuleAttachmentCell : NSTextAttachmentCell
{
    NSColor *_color;
    NSSize _size;
    CGFloat _thickness;
}
- (instancetype)initWithColor:(NSColor *)color width:(CGFloat)width thickness:(CGFloat)thickness height:(CGFloat)height;
@end

@implementation OMRuleAttachmentCell

- (instancetype)initWithColor:(NSColor *)color width:(CGFloat)width thickness:(CGFloat)thickness height:(CGFloat)height
{
    self = [super initTextCell:@""];
    if (self != nil) {
        _color = [(color != nil ? color : [NSColor lightGrayColor]) retain];
        _thickness = MAX(1.0, thickness);
        _size = NSMakeSize(MAX(1.0, width), MAX(_thickness, height));
    }
    return self;
}

- (void)dealloc
{
    [_color release];
    [super dealloc];
}

- (NSSize)cellSize
{
    return _size;
}

- (NSPoint)cellBaselineOffset
{
    return NSZeroPoint;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSRect line = NSMakeRect(NSMinX(cellFrame),
                             floor(NSMidY(cellFrame) - _thickness * 0.5),
                             NSWidth(cellFrame),
                             _thickness);
    [_color set];
    NSRectFill(line);
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
{
    [self drawWithFrame:cellFrame inView:controlView];
}

- (void)drawWithFrame:(NSRect)cellFrame
               inView:(NSView *)controlView
       characterIndex:(NSUInteger)charIndex
        layoutManager:(NSLayoutManager *)layoutManager
{
    [self drawWithFrame:cellFrame inView:controlView];
}

@end

// Appends a rule paragraph: one attachment line, thickness tall plus padding.
static void OMAppendRule(NSMutableAttributedString *output,
                         NSDictionary *attributes,
                         NSColor *color,
                         CGFloat width,
                         CGFloat thickness,
                         CGFloat indent,
                         CGFloat spacingAfter)
{
    if (width <= 0.0) {
        width = 400.0;
    }
    CGFloat height = thickness + 2.0;
    OMRuleAttachmentCell *cell = [[[OMRuleAttachmentCell alloc] initWithColor:color
                                                                       width:width
                                                                   thickness:thickness
                                                                      height:height] autorelease];
    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    [attachment setAttachmentCell:cell];
    [cell setAttachment:attachment];

    NSMutableDictionary *ruleAttrs = [NSMutableDictionary dictionaryWithDictionary:attributes];
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setFirstLineHeadIndent:indent];
    [style setHeadIndent:indent];
    [style setMinimumLineHeight:height];
    [style setMaximumLineHeight:height];
    [style setParagraphSpacing:spacingAfter];
    [ruleAttrs setObject:style forKey:NSParagraphStyleAttributeName];
    [ruleAttrs setObject:[NSFont systemFontOfSize:1.0] forKey:NSFontAttributeName];
    [ruleAttrs setObject:attachment forKey:NSAttachmentAttributeName];
    unichar attachmentCharacter = NSAttachmentCharacter;
    OMAppendString(output, [NSString stringWithCharacters:&attachmentCharacter length:1], ruleAttrs);
    [ruleAttrs removeObjectForKey:NSAttachmentAttributeName];
    OMAppendString(output, @"\n", ruleAttrs);
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
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return preparedImage;
    }

    CGFloat effectiveScale = scale > 0.01 ? scale : 1.0;
    NSSize preparedSize = NSMakeSize(imageSize.width * effectiveScale,
                                     imageSize.height * effectiveScale);
    CGFloat maxWidth = 0.0;
    if (layoutWidth > 0.0) {
        maxWidth = floor(layoutWidth - (24.0 * effectiveScale));
    }
    if (maxWidth > 0.0 && preparedSize.width > maxWidth) {
        CGFloat ratio = maxWidth / preparedSize.width;
        if (ratio > 0.0) {
            CGFloat height = floor(preparedSize.height * ratio);
            if (height < 1.0) {
                height = 1.0;
            }
            preparedSize = NSMakeSize(maxWidth, height);
        }
    }
    if (!NSEqualSizes(preparedSize, imageSize)) {
        [preparedImage setScalesWhenResized:YES];
        [preparedImage setSize:preparedSize];
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

static BOOL OMMarkerIsEscaped(NSString *text, NSUInteger location)
{
    if (text == nil || [text length] == 0 || location == 0 || location > [text length]) {
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

static CGFloat OMPipeTableHorizontalPadding(CGFloat scale)
{
    CGFloat padding = 10.0 * scale;
    if (padding < 6.0) {
        padding = 6.0;
    }
    return padding;
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
    CGFloat minimumColumnTextWidth = 44.0 * scale;
    if (minimumColumnTextWidth < 28.0) {
        minimumColumnTextWidth = 28.0;
    }
    CGFloat minimumGridWidth = ((CGFloat)[columnWidths count] *
                                (minimumColumnTextWidth + (cellHorizontalPadding * 2.0))) +
                               (2.0 * scale);
    if (availableWidth < minimumGridWidth) {
        return YES;
    }
    return NO;
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
    cmark_node *document = OMGFMParseDocument(bytes, length, (int)CMARK_OPT_DEFAULT);
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
    cmark_node *document = OMGFMParseDocument(bytes, length, (int)cmarkOptions);
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

static NSMutableAttributedString *OMPipeTableDrawableSegment(NSAttributedString *segment,
                                                             OMPipeTableAlignment alignment,
                                                             NSLineBreakMode lineBreakMode)
{
    if (segment == nil) {
        return nil;
    }

    NSMutableAttributedString *drawSegment = [[segment mutableCopy] autorelease];
    if ([drawSegment length] == 0) {
        return drawSegment;
    }

    NSMutableParagraphStyle *drawStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [drawStyle setAlignment:OMPipeTableTextAlignment(alignment)];
    [drawStyle setLineBreakMode:lineBreakMode];
    [drawSegment addAttribute:NSParagraphStyleAttributeName
                        value:drawStyle
                        range:NSMakeRange(0, [drawSegment length])];
    return drawSegment;
}

static CGFloat OMPipeTableMeasuredTextHeight(NSAttributedString *segment,
                                             CGFloat width,
                                             CGFloat fallbackLineHeight)
{
    if (segment == nil || [segment length] == 0 || width <= 0.0) {
        return fallbackLineHeight;
    }

    NSTextStorage *storage = [[[NSTextStorage alloc] initWithAttributedString:segment] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, FLT_MAX)] autorelease];
    [container setLineFragmentPadding:0.0];
    [layoutManager addTextContainer:container];
    [storage addLayoutManager:layoutManager];
    [layoutManager ensureLayoutForTextContainer:container];

    NSRect usedRect = [layoutManager usedRectForTextContainer:container];
    CGFloat height = ceil(usedRect.size.height);
    if (height < fallbackLineHeight) {
        height = fallbackLineHeight;
    }
    return height;
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
        CGFloat contentHeight = lineHeight;
        if (attributedRows != nil && [attributedRows count] == rowCount) {
            NSArray *row = [attributedRows objectAtIndex:rowIndex];
            NSUInteger columnIndex = 0;
            for (; columnIndex < columnCount; columnIndex++) {
                NSAttributedString *segment = (columnIndex < [row count] ? [row objectAtIndex:columnIndex] : nil);
                OMPipeTableAlignment alignment = OMPipeTableAlignmentLeft;
                NSMutableAttributedString *measureSegment = OMPipeTableDrawableSegment(segment,
                                                                                       alignment,
                                                                                       NSLineBreakByWordWrapping);
                CGFloat contentWidth = [[columnWidths objectAtIndex:columnIndex] doubleValue];
                CGFloat measured = OMPipeTableMeasuredTextHeight(measureSegment,
                                                                 contentWidth,
                                                                 lineHeight);
                if (measured > contentHeight) {
                    contentHeight = measured;
                }
            }
        }
        CGFloat rowHeight = ceil(contentHeight + (verticalPadding * 2.0));
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
                OMPipeTableAlignment alignment = (OMPipeTableAlignment)[[alignments objectAtIndex:colIndex] unsignedIntegerValue];
                NSMutableAttributedString *drawSegment = OMPipeTableDrawableSegment(segment,
                                                                                    alignment,
                                                                                    NSLineBreakByWordWrapping);

                NSRect textRect = NSInsetRect(cellRect, horizontalPadding, verticalPadding);
                [drawSegment drawInRect:textRect];
                OMDrawStrikethroughForAttributedString(drawSegment, textRect, NO);
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
                OMPipeTableAlignment alignment = (OMPipeTableAlignment)[[_alignments objectAtIndex:colIndex] unsignedIntegerValue];
                NSMutableAttributedString *drawSegment = OMPipeTableDrawableSegment(segment,
                                                                                    alignment,
                                                                                    NSLineBreakByWordWrapping);

                NSRect textRect = OMPipeTableIntegralRect(NSInsetRect(cellRect,
                                                                      _horizontalPadding,
                                                                      _verticalPadding));
                [drawSegment drawInRect:textRect];
                OMDrawStrikethroughForAttributedString(drawSegment, textRect, flipped);
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

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
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

    // "#slug" points into this document: keep it relative, so the viewer can
    // match it against heading anchors instead of resolving it to a folder.
    if ([urlString hasPrefix:@"#"]) {
        NSURL *fragmentURL = [NSURL URLWithString:urlString];
        if (fragmentURL == nil) {
            NSString *escaped = [[urlString substringFromIndex:1]
                stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
            fragmentURL = [NSURL URLWithString:[@"#" stringByAppendingString:(escaped != nil ? escaped : @"")]];
        }
        return fragmentURL;
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
        // Local files must be read again on refresh, even at the same URL.
        cachedImage = [url isFileURL] ? nil : [cache objectForKey:cacheKey];
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
    NSString *html = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
    if (html == nil || [html length] == 0) {
        return;
    }

    // Strike tags are applied under every HTML policy: GFM "~~" reaches cmark
    // as <del> through OMNormalizeGFMStrikethroughMarkdown.
    NSString *trimmed = [html stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lower = [trimmed lowercaseString];
    if (!blockNode && ([lower isEqualToString:@"<del>"] ||
        [lower isEqualToString:@"<s>"] ||
        [lower isEqualToString:@"<strike>"])) {
        [attributes setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
                       forKey:NSStrikethroughStyleAttributeName];
        return;
    }
    if (!blockNode && ([lower isEqualToString:@"</del>"] ||
        [lower isEqualToString:@"</s>"] ||
        [lower isEqualToString:@"</strike>"])) {
        [attributes removeObjectForKey:NSStrikethroughStyleAttributeName];
        return;
    }

    if (OMHTMLPolicyForBlockNode(renderContext, blockNode) == OMMarkdownHTMLPolicyIgnore) {
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

static BOOL OMMathIsCommandCharacter(unichar ch)
{
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
}

static BOOL OMMathExtractGroupedContent(NSString *text,
                                        NSUInteger startIndex,
                                        unichar openChar,
                                        unichar closeChar,
                                        NSString **contentOut,
                                        NSUInteger *nextIndexOut)
{
    if (text == nil || startIndex >= [text length] || [text characterAtIndex:startIndex] != openChar) {
        return NO;
    }

    NSUInteger depth = 1;
    NSUInteger cursor = startIndex + 1;
    while (cursor < [text length]) {
        unichar ch = [text characterAtIndex:cursor];
        if (ch == openChar && !OMMarkerIsEscaped(text, cursor)) {
            depth += 1;
        } else if (ch == closeChar && !OMMarkerIsEscaped(text, cursor)) {
            depth -= 1;
            if (depth == 0) {
                if (contentOut != NULL) {
                    *contentOut = [text substringWithRange:NSMakeRange(startIndex + 1,
                                                                      cursor - (startIndex + 1))];
                }
                if (nextIndexOut != NULL) {
                    *nextIndexOut = cursor + 1;
                }
                return YES;
            }
        }
        cursor += 1;
    }

    return NO;
}

static NSString *OMMathUnicodeReplacementForCommand(NSString *command)
{
    if (command == nil || [command length] == 0) {
        return nil;
    }

    if ([command isEqualToString:@"alpha"]) return @"\u03b1";
    if ([command isEqualToString:@"beta"]) return @"\u03b2";
    if ([command isEqualToString:@"gamma"]) return @"\u03b3";
    if ([command isEqualToString:@"delta"]) return @"\u03b4";
    if ([command isEqualToString:@"Delta"]) return @"\u0394";
    if ([command isEqualToString:@"pi"]) return @"\u03c0";
    if ([command isEqualToString:@"theta"]) return @"\u03b8";
    if ([command isEqualToString:@"lambda"]) return @"\u03bb";
    if ([command isEqualToString:@"mu"]) return @"\u03bc";
    if ([command isEqualToString:@"sigma"]) return @"\u03c3";
    if ([command isEqualToString:@"Sigma"]) return @"\u03a3";
    if ([command isEqualToString:@"sum"]) return @"\u03a3";
    if ([command isEqualToString:@"int"]) return @"\u222b";
    if ([command isEqualToString:@"infty"]) return @"\u221e";
    if ([command isEqualToString:@"times"]) return @"\u00d7";
    if ([command isEqualToString:@"cdot"]) return @"\u00b7";
    if ([command isEqualToString:@"leq"]) return @"\u2264";
    if ([command isEqualToString:@"geq"]) return @"\u2265";
    if ([command isEqualToString:@"neq"]) return @"\u2260";
    if ([command isEqualToString:@"approx"]) return @"\u2248";
    if ([command isEqualToString:@"to"]) return @"\u2192";
    if ([command isEqualToString:@"rightarrow"]) return @"\u2192";
    if ([command isEqualToString:@"leftarrow"]) return @"\u2190";
    if ([command isEqualToString:@"mid"]) return @"|";
    if ([command isEqualToString:@"cap"]) return @"\u2229";
    if ([command isEqualToString:@"cup"]) return @"\u222a";
    return nil;
}

static NSString *OMReadableMathFallbackString(NSString *formula)
{
    if (formula == nil || [formula length] == 0) {
        return formula;
    }

    NSMutableString *normalized = [NSMutableString string];
    NSUInteger length = [formula length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [formula characterAtIndex:index];
        if (ch == '{' || ch == '}') {
            index += 1;
            continue;
        }

        if (ch != '\\') {
            [normalized appendFormat:@"%C", ch];
            index += 1;
            continue;
        }

        if (index + 1 >= length) {
            [normalized appendString:@"\\"];
            break;
        }

        NSUInteger commandStart = index + 1;
        NSUInteger commandEnd = commandStart;
        while (commandEnd < length && OMMathIsCommandCharacter([formula characterAtIndex:commandEnd])) {
            commandEnd += 1;
        }

        if (commandEnd > commandStart) {
            NSString *command = [formula substringWithRange:NSMakeRange(commandStart, commandEnd - commandStart)];
            if ([command isEqualToString:@"left"] || [command isEqualToString:@"right"]) {
                index = commandEnd;
                continue;
            }

            if ([command isEqualToString:@"frac"]) {
                NSString *numerator = nil;
                NSString *denominator = nil;
                NSUInteger numeratorEnd = 0;
                NSUInteger denominatorEnd = 0;
                if (OMMathExtractGroupedContent(formula, commandEnd, '{', '}', &numerator, &numeratorEnd) &&
                    OMMathExtractGroupedContent(formula, numeratorEnd, '{', '}', &denominator, &denominatorEnd)) {
                    [normalized appendFormat:@"(%@)/(%@)",
                     OMReadableMathFallbackString(numerator),
                     OMReadableMathFallbackString(denominator)];
                    index = denominatorEnd;
                    continue;
                }
            }

            if ([command isEqualToString:@"sqrt"]) {
                NSUInteger contentStart = commandEnd;
                NSString *rootDegree = nil;
                if (contentStart < length && [formula characterAtIndex:contentStart] == '[') {
                    NSUInteger degreeEnd = 0;
                    if (OMMathExtractGroupedContent(formula, contentStart, '[', ']', &rootDegree, &degreeEnd)) {
                        contentStart = degreeEnd;
                    }
                }

                NSString *radicand = nil;
                NSUInteger radicandEnd = 0;
                if (OMMathExtractGroupedContent(formula, contentStart, '{', '}', &radicand, &radicandEnd)) {
                    if ([rootDegree length] > 0) {
                        [normalized appendFormat:@"\u221a[%@](%@)",
                         OMReadableMathFallbackString(rootDegree),
                         OMReadableMathFallbackString(radicand)];
                    } else {
                        [normalized appendFormat:@"\u221a(%@)", OMReadableMathFallbackString(radicand)];
                    }
                    index = radicandEnd;
                    continue;
                }
            }

            if ([command isEqualToString:@"text"] ||
                [command isEqualToString:@"mathrm"] ||
                [command isEqualToString:@"operatorname"]) {
                NSString *content = nil;
                NSUInteger nextIndex = 0;
                if (OMMathExtractGroupedContent(formula, commandEnd, '{', '}', &content, &nextIndex)) {
                    [normalized appendString:OMReadableMathFallbackString(content)];
                    index = nextIndex;
                    continue;
                }
            }

            NSString *replacement = OMMathUnicodeReplacementForCommand(command);
            if (replacement != nil) {
                [normalized appendString:replacement];
            } else {
                [normalized appendString:command];
            }
            index = commandEnd;
            continue;
        }

        unichar escaped = [formula characterAtIndex:index + 1];
        switch (escaped) {
            case ',':
            case ';':
            case ':':
            case '!':
            case ' ':
                [normalized appendString:@" "];
                break;
            default:
                [normalized appendFormat:@"%C", escaped];
                break;
        }
        index += 2;
    }

    return normalized;
}

static NSArray *OMExecutableCandidateNames(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return [NSArray array];
    }

    NSMutableArray *candidates = [NSMutableArray arrayWithObject:name];
#if defined(_WIN32)
    NSString *lowercase = [name lowercaseString];
    if (![lowercase hasSuffix:@".exe"] &&
        ![lowercase hasSuffix:@".cmd"] &&
        ![lowercase hasSuffix:@".bat"] &&
        ![lowercase hasSuffix:@".com"]) {
        [candidates addObject:[name stringByAppendingString:@".exe"]];
        [candidates addObject:[name stringByAppendingString:@".cmd"]];
        [candidates addObject:[name stringByAppendingString:@".bat"]];
        [candidates addObject:[name stringByAppendingString:@".com"]];
    }
#endif
    return candidates;
}

static NSString *OMExecutablePathInDirectory(NSString *directory,
                                             NSString *name,
                                             NSFileManager *fileManager)
{
    if (directory == nil || [directory length] == 0 || name == nil || [name length] == 0) {
        return nil;
    }

    for (NSString *candidateName in OMExecutableCandidateNames(name)) {
        NSString *candidate = [directory stringByAppendingPathComponent:candidateName];
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

#if defined(_WIN32)
static NSString *OMWindowsBundledExecutablePath(NSString *relativePath)
{
    if (relativePath == nil || [relativePath length] == 0) {
        return nil;
    }

    NSString *executablePath = [[NSBundle mainBundle] executablePath];
    if (executablePath == nil || [executablePath length] == 0) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *searchRoot = [executablePath stringByDeletingLastPathComponent];
    for (NSUInteger depth = 0; depth < 4 && searchRoot != nil && [searchRoot length] > 0; depth++) {
        NSString *candidate = [searchRoot stringByAppendingPathComponent:relativePath];
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }

        NSString *parent = [searchRoot stringByDeletingLastPathComponent];
        if (parent == nil || [parent isEqualToString:searchRoot]) {
            break;
        }
        searchRoot = parent;
    }

    return nil;
}

static NSString *OMWindowsKnownExecutablePathNamed(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return nil;
    }

    NSString *lowercase = [[name stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSArray *candidatePaths = nil;

    if ([lowercase isEqualToString:@"latex"] || [lowercase isEqualToString:@"latex.exe"]) {
        candidatePaths = [NSArray arrayWithObjects:
            @"runtime\\texlive\\TinyTeX\\bin\\windows\\latex.exe",
            @"clang64\\texlive\\TinyTeX\\bin\\windows\\latex.exe",
            @"C:\\clang64\\texlive\\TinyTeX\\bin\\windows\\latex.exe",
            nil];
    } else if ([lowercase isEqualToString:@"tex"] || [lowercase isEqualToString:@"tex.exe"]) {
        candidatePaths = [NSArray arrayWithObjects:
            @"runtime\\texlive\\TinyTeX\\bin\\windows\\tex.exe",
            @"clang64\\texlive\\TinyTeX\\bin\\windows\\tex.exe",
            @"C:\\clang64\\texlive\\TinyTeX\\bin\\windows\\tex.exe",
            nil];
    } else if ([lowercase isEqualToString:@"dvipng"] || [lowercase isEqualToString:@"dvipng.exe"]) {
        candidatePaths = [NSArray arrayWithObjects:
            @"runtime\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe",
            @"clang64\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe",
            @"C:\\clang64\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe",
            nil];
    } else if ([lowercase isEqualToString:@"dvisvgm"] || [lowercase isEqualToString:@"dvisvgm.exe"]) {
        candidatePaths = [NSArray arrayWithObjects:
            @"runtime\\texlive\\TinyTeX\\bin\\windows\\dvisvgm.exe",
            @"clang64\\texlive\\TinyTeX\\bin\\windows\\dvisvgm.exe",
            @"C:\\clang64\\texlive\\TinyTeX\\bin\\windows\\dvisvgm.exe",
            nil];
    }

    if (candidatePaths == nil) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *candidatePath in candidatePaths) {
        NSString *resolved = nil;
        if ([candidatePath hasPrefix:@"C:\\"]) {
            resolved = candidatePath;
        } else {
            resolved = OMWindowsBundledExecutablePath(candidatePath);
        }
        if (resolved != nil && [fileManager isExecutableFileAtPath:resolved]) {
            return resolved;
        }
    }

    return nil;
}
#endif

static NSString *OMExecutablePathNamed(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([name rangeOfString:@"/"].location != NSNotFound ||
        [name rangeOfString:@"\\"].location != NSNotFound) {
        for (NSString *candidateName in OMExecutableCandidateNames(name)) {
            if ([fileManager isExecutableFileAtPath:candidateName]) {
                return candidateName;
            }
        }
    }

#if defined(_WIN32)
    NSString *bundled = OMWindowsKnownExecutablePathNamed(name);
    if (bundled != nil) {
        return bundled;
    }
#endif

    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *pathValue = [environment objectForKey:@"PATH"];
    if (pathValue != nil && [pathValue length] > 0) {
#if defined(_WIN32)
        NSString *separator = ([pathValue rangeOfString:@";"].location != NSNotFound) ? @";" : @":";
#else
        NSString *separator = @":";
#endif
        NSArray *searchPaths = [pathValue componentsSeparatedByString:separator];
        for (NSString *searchPath in searchPaths) {
            NSString *resolved = OMExecutablePathInDirectory(searchPath, name, fileManager);
            if (resolved != nil) {
                return resolved;
            }
        }
    }

    NSString *fallback = OMExecutablePathInDirectory(@"/usr/bin", name, fileManager);
    if (fallback != nil) {
        return fallback;
    }
    return nil;
}

static NSString *OMLaTeXExecutablePath(void)
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = [OMExecutablePathNamed(@"latex") retain];
    });
    return path;
}

static NSString *OMPlainTexExecutablePath(void)
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = [OMExecutablePathNamed(@"tex") retain];
    });
    return path;
}

static NSString *OMDviPngExecutablePath(void)
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = [OMExecutablePathNamed(@"dvipng") retain];
    });
    return path;
}

static NSString *OMDviSvgmExecutablePath(void)
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = [OMExecutablePathNamed(@"dvisvgm") retain];
    });
    return path;
}

static BOOL OMMathBackendAvailable(void)
{
#if defined(_WIN32)
    return OMDviPngExecutablePath() != nil &&
           (OMLaTeXExecutablePath() != nil || OMPlainTexExecutablePath() != nil);
#else
    return OMDviSvgmExecutablePath() != nil &&
           (OMLaTeXExecutablePath() != nil || OMPlainTexExecutablePath() != nil);
#endif
}

static NSCache *OMMathAttachmentCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    });
    return cache;
}

static NSCache *OMMathBaseImageCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    });
    return cache;
}

static NSCache *OMMathBaseSVGDataCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    });
    return cache;
}

static NSCache *OMMathBestAvailableImageCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    });
    return cache;
}

static NSCache *OMMathBestAvailableZoomCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    });
    return cache;
}

static NSUInteger OMMathArtifactConcurrencyLimit(void)
{
    static NSUInteger limit = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUInteger resolved = 1;
        NSInteger cpuCount = [[NSProcessInfo processInfo] activeProcessorCount];
        if (cpuCount >= 4) {
            resolved = 4;
        } else if (cpuCount >= 2) {
            resolved = 2;
        }
        limit = resolved;
    });
    return limit;
}

static dispatch_queue_t OMMathArtifactQueue(void)
{
    static dispatch_queue_t queue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.objcmarkdown.math-artifacts", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

static dispatch_semaphore_t OMMathArtifactSemaphore(void)
{
    static dispatch_semaphore_t semaphore = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        semaphore = dispatch_semaphore_create((long)OMMathArtifactConcurrencyLimit());
    });
    return semaphore;
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
                      NSString *currentDirectoryPath,
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
#if defined(_WIN32)
    if (currentDirectoryPath != nil && [currentDirectoryPath length] > 0) {
        NSString *scriptPath = OMWindowsTaskScriptPath(currentDirectoryPath);
        NSMutableArray *commandParts = [NSMutableArray array];
        [commandParts addObject:OMWindowsQuoteCommandArgument(OMWindowsNormalizedPath(launchPath))];
        for (NSString *argument in arguments) {
            [commandParts addObject:OMWindowsQuoteCommandArgument(argument)];
        }
        NSString *scriptContents = [NSString stringWithFormat:@"@echo off\r\ncd /d %@\r\n%@\r\n",
                                    OMWindowsQuoteCommandArgument(OMWindowsNormalizedPath(currentDirectoryPath)),
                                    [commandParts componentsJoinedByString:@" "]];
        if (scriptPath == nil ||
            ![scriptContents writeToFile:scriptPath
                              atomically:YES
                                encoding:NSASCIIStringEncoding
                                   error:NULL]) {
            if (terminationStatus != NULL) {
                *terminationStatus = -1;
            }
            return NO;
        }

        [task setLaunchPath:@"C:\\Windows\\System32\\cmd.exe"];
        [task setArguments:[NSArray arrayWithObjects:@"/d", @"/c", scriptPath, nil]];
    } else {
        [task setLaunchPath:launchPath];
        [task setArguments:arguments];
    }
#else
    [task setLaunchPath:launchPath];
    if (currentDirectoryPath != nil && [currentDirectoryPath length] > 0) {
        [task setCurrentDirectoryPath:currentDirectoryPath];
    }
    [task setArguments:arguments];
#endif

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
#if defined(_WIN32)
                OMMathDebugLog([NSString stringWithFormat:@"task-timeout: launch=%@ args=%@ timeout=%.2f",
                                OMMathLogSnippet(launchPath),
                                OMMathLogSnippet([arguments componentsJoinedByString:@" "]),
                                timeoutSeconds]);
#endif
                [task terminate];
            }
        }
        [task waitUntilExit];
    } @catch (NSException *exception) {
        launched = NO;
#if defined(_WIN32)
        OMMathDebugLog([NSString stringWithFormat:@"task-launch-exception: launch=%@ args=%@ class=%@ reason=%@",
                        OMMathLogSnippet(launchPath),
                        OMMathLogSnippet([arguments componentsJoinedByString:@" "]),
                        NSStringFromClass([exception class]),
                        OMMathLogSnippet([exception description])]);
#else
        (void)exception;
#endif
    }

    NSData *capturedOutput = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSData *capturedError = [[errorPipe fileHandleForReading] readDataToEndOfFile];

#if defined(_WIN32)
    if (currentDirectoryPath != nil && [currentDirectoryPath length] > 0) {
        NSString *scriptPath = OMWindowsTaskScriptPath(currentDirectoryPath);
        if (scriptPath != nil) {
            [[NSFileManager defaultManager] removeItemAtPath:scriptPath error:NULL];
        }
    }
#endif

    if (stdoutData != NULL) {
        *stdoutData = capturedOutput;
    }
    if (stderrData != NULL) {
        *stderrData = capturedError;
    }
    if (terminationStatus != NULL) {
        *terminationStatus = (launched && !timedOut) ? [task terminationStatus] : -1;
    }

#if defined(_WIN32)
    if (launched && !timedOut && [task terminationStatus] != 0) {
        OMMathDebugLog([NSString stringWithFormat:@"task-nonzero-exit: launch=%@ args=%@ status=%d stdout=%@ stderr=%@",
                        OMMathLogSnippet(launchPath),
                        OMMathLogSnippet([arguments componentsJoinedByString:@" "]),
                        [task terminationStatus],
                        OMMathDebugStringFromData(capturedOutput),
                        OMMathDebugStringFromData(capturedError)]);
    }
#endif

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

#if defined(_WIN32)
static BOOL OMEnsureWindowsGDIPlusStarted(void)
{
    static BOOL resolved = NO;
    static BOOL started = NO;
    static ULONG_PTR token = 0;

    if (!resolved) {
        GdiplusStartupInput input;
        memset(&input, 0, sizeof(input));
        input.GdiplusVersion = 1;
        started = (GdiplusStartup(&token, &input, NULL) == Ok);
        resolved = YES;
    }

    return started;
}

static wchar_t *OMCreateWidePathFromNSString(NSString *string)
{
    if (string == nil || [string length] == 0) {
        return NULL;
    }

    NSUInteger length = [string length];
    wchar_t *buffer = (wchar_t *)calloc(length + 1, sizeof(wchar_t));
    if (buffer == NULL) {
        return NULL;
    }

    [string getCharacters:(unichar *)buffer range:NSMakeRange(0, length)];
    buffer[length] = L'\0';
    return buffer;
}

static NSImage *OMWindowsImageFromPNGFile(NSString *path)
{
    if (path == nil || [path length] == 0 || !OMEnsureWindowsGDIPlusStarted()) {
        return nil;
    }

    wchar_t *widePath = OMCreateWidePathFromNSString(path);
    GpBitmap *bitmap = NULL;
    BitmapData locked;
    BOOL hasLock = NO;
    NSImage *image = nil;

    memset(&locked, 0, sizeof(locked));
    if (widePath == NULL) {
        return nil;
    }

    if (GdipCreateBitmapFromFile(widePath, &bitmap) != Ok || bitmap == NULL) {
        free(widePath);
        return nil;
    }

    do {
        UINT width = 0;
        UINT height = 0;
        GpRect rect;
        NSBitmapImageRep *bitmapRep = nil;
        unsigned char *destBase = NULL;
        BYTE *srcBase = NULL;
        INT srcStride = 0;
        NSUInteger destStride = 0;

        if (GdipGetImageWidth((GpImage *)bitmap, &width) != Ok ||
            GdipGetImageHeight((GpImage *)bitmap, &height) != Ok ||
            width == 0 ||
            height == 0) {
            break;
        }

        rect.X = 0;
        rect.Y = 0;
        rect.Width = (INT)width;
        rect.Height = (INT)height;
        if (GdipBitmapLockBits(bitmap,
                               &rect,
                               ImageLockModeRead,
                               PixelFormat32bppARGB,
                               &locked) != Ok) {
            break;
        }
        hasLock = YES;

        bitmapRep = [[[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:(NSInteger)width
                          pixelsHigh:(NSInteger)height
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSCalibratedRGBColorSpace
                         bytesPerRow:(NSInteger)(width * 4)
                        bitsPerPixel:32] autorelease];
        if (bitmapRep == nil) {
            break;
        }

        destBase = [bitmapRep bitmapData];
        if (destBase == NULL) {
            break;
        }

        srcBase = (BYTE *)locked.Scan0;
        srcStride = locked.Stride;
        if (srcBase == NULL || srcStride == 0) {
            break;
        }
        if (srcStride < 0) {
            srcBase += ((NSInteger)height - 1) * ((NSInteger)(-srcStride));
            srcStride = -srcStride;
        }

        destStride = (NSUInteger)(width * 4);
        for (UINT y = 0; y < height; y++) {
            BYTE *srcRow = srcBase + ((NSUInteger)y * (NSUInteger)srcStride);
            unsigned char *destRow = destBase + ((NSUInteger)y * destStride);
            for (UINT x = 0; x < width; x++) {
                BYTE *srcPixel = srcRow + ((NSUInteger)x * 4);
                unsigned char *destPixel = destRow + ((NSUInteger)x * 4);

                destPixel[0] = srcPixel[2];
                destPixel[1] = srcPixel[1];
                destPixel[2] = srcPixel[0];
                destPixel[3] = srcPixel[3];
            }
        }

        image = [[[NSImage alloc] initWithSize:NSMakeSize((CGFloat)width,
                                                          (CGFloat)height)] autorelease];
        if (image != nil) {
            [image addRepresentation:bitmapRep];
        }
    } while (0);

    if (hasLock) {
        GdipBitmapUnlockBits(bitmap, &locked);
    }
    GdipDisposeImage((GpImage *)bitmap);
    free(widePath);
    return image;
}

static NSImage *OMPNGImageForMathFormula(NSString *formula,
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
#if defined(_WIN32)
        OMMathDebugLog([NSString stringWithFormat:@"png-skip: backend=%@ formulaLength=%lu max=%lu display=%@",
                        OMMathBackendAvailable() ? @"yes" : @"no",
                        (unsigned long)(formula != nil ? [formula length] : 0),
                        (unsigned long)maximumFormulaLength,
                        displayMath ? @"yes" : @"no"]);
#endif
        return nil;
    }

    NSString *tempDir = OMCreateMathTempDirectory();
    if (tempDir == nil) {
        return nil;
    }

    NSString *texPath = [tempDir stringByAppendingPathComponent:@"formula.tex"];
    NSString *dviPath = [tempDir stringByAppendingPathComponent:@"formula.dvi"];
    NSString *pngPath = [tempDir stringByAppendingPathComponent:@"formula.png"];
    NSString *texExecutable = OMLaTeXExecutablePath();
    BOOL usingLaTeX = texExecutable != nil;
    if (!usingLaTeX) {
        texExecutable = OMPlainTexExecutablePath();
    }
    if (texExecutable == nil) {
#if defined(_WIN32)
        OMMathDebugLog([NSString stringWithFormat:@"png-no-tex: formula=%@",
                        OMMathLogSnippet(formula)]);
#endif
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

    if (![texSource writeToFile:texPath
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:NULL]) {
#if defined(_WIN32)
        OMMathDebugLog([NSString stringWithFormat:@"png-write-failed: tex=%@ formula=%@",
                        OMMathLogSnippet(texPath),
                        OMMathLogSnippet(formula)]);
#endif
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        return nil;
    }

    NSArray *texArguments = [NSArray arrayWithObjects:
        @"-interaction=nonstopmode",
        @"-halt-on-error",
        @"-output-directory", @".",
        @"formula.tex",
        nil];
    NSTimeInterval texStart = OMNow();
    if (!OMRunTask(texExecutable,
                   tempDir,
                   texArguments,
                   NULL,
                   NULL,
                   NULL,
                   externalToolTimeout) ||
        ![[NSFileManager defaultManager] fileExistsAtPath:dviPath]) {
#if defined(_WIN32)
        OMMathDebugLog([NSString stringWithFormat:@"png-latex-failed: tex=%@ dvi=%@ formula=%@",
                        OMMathLogSnippet(texExecutable),
                        OMMathLogSnippet(dviPath),
                        OMMathLogSnippet(formula)]);
#endif
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        return nil;
    }
    if (stats != NULL) {
        stats->latexRuns += 1;
        stats->latexSeconds += (OMNow() - texStart);
    }

    if (renderZoom < 0.5) {
        renderZoom = 0.5;
    } else if (renderZoom > 10.0) {
        renderZoom = 10.0;
    }

    NSInteger dpi = (NSInteger)lrint(96.0 * renderZoom);
    if (dpi < 72) {
        dpi = 72;
    } else if (dpi > 1200) {
        dpi = 1200;
    }

    NSArray *pngArguments = [NSArray arrayWithObjects:
        @"-T", @"tight",
        @"-bg", @"Transparent",
        @"-D", [NSString stringWithFormat:@"%ld", (long)dpi],
        @"-o", @"formula.png",
        @"formula.dvi",
        nil];
    NSTimeInterval pngStart = OMNow();
    if (!OMRunTask(OMDviPngExecutablePath(),
                   tempDir,
                   pngArguments,
                   NULL,
                   NULL,
                   NULL,
                   externalToolTimeout) ||
        ![[NSFileManager defaultManager] fileExistsAtPath:pngPath]) {
#if defined(_WIN32)
        OMMathDebugLog([NSString stringWithFormat:@"png-dvipng-failed: dvipng=%@ png=%@ formula=%@",
                        OMMathLogSnippet(OMDviPngExecutablePath()),
                        OMMathLogSnippet(pngPath),
                        OMMathLogSnippet(formula)]);
#endif
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        return nil;
    }
    if (stats != NULL) {
        stats->dvisvgmRuns += 1;
        stats->dvisvgmSeconds += (OMNow() - pngStart);
    }

    NSImage *image = OMWindowsImageFromPNGFile(pngPath);
    if (image == nil) {
#if defined(_WIN32)
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:pngPath error:NULL];
        OMMathDebugLog([NSString stringWithFormat:@"png-decode-failed: png=%@ size=%@ formula=%@",
                        OMMathLogSnippet(pngPath),
                        OMMathLogSnippet([[attributes objectForKey:NSFileSize] description]),
                        OMMathLogSnippet(formula)]);
#endif
    }
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
    return image;
}
#endif

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
        @"-output-directory", @".",
        @"formula.tex",
        nil];
    int texStatus = 0;
    NSTimeInterval texStart = OMNow();
    BOOL texOK = OMRunTask(texExecutable,
                           tempDir,
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
        @"formula.dvi",
        nil];
    NSData *svgData = nil;
    int svgStatus = 0;
    NSTimeInterval svgStart = OMNow();
    BOOL svgOK = OMRunTask(OMDviSvgmExecutablePath(),
                           tempDir,
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
        dispatch_semaphore_wait(OMMathArtifactSemaphore(), DISPATCH_TIME_FOREVER);
        @autoreleasepool {
            @try {
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
            } @finally {
                @synchronized (pending) {
                    [pending removeObject:assetKeyCopy];
                }
                [formulaCopy release];
                [assetKeyCopy release];
                dispatch_semaphore_signal(OMMathArtifactSemaphore());
            }
        }
    });
}

// Hex for the ink of math on this theme when it isn't (near) black, else nil.
// LaTeX draws black; light ink is only needed on dark themes.
static NSString *OMMathInkHexForTheme(OMTheme *theme)
{
    NSColor *ink = [theme.baseTextColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (ink == nil) {
        return nil;
    }
    CGFloat luminance = 0.2126 * [ink redComponent] + 0.7152 * [ink greenComponent] + 0.0722 * [ink blueComponent];
    if (luminance < 0.5) {
        return nil;
    }
    return [NSString stringWithFormat:@"#%02x%02x%02x",
            (int)lround([ink redComponent] * 255.0),
            (int)lround([ink greenComponent] * 255.0),
            (int)lround([ink blueComponent] * 255.0)];
}

// dvisvgm leaves glyph fills unset (black); a fill on the root recolours them.
static NSData *OMMathSVGDataWithInk(NSData *svgData, NSString *inkHex)
{
    if (svgData == nil || inkHex == nil) {
        return svgData;
    }
    NSString *svg = [[[NSString alloc] initWithData:svgData encoding:NSUTF8StringEncoding] autorelease];
    NSRange root = [svg rangeOfString:@"<svg "];
    if (svg == nil || root.location == NSNotFound) {
        return svgData;
    }
    NSString *inked = [svg stringByReplacingCharactersInRange:root
                                                   withString:[NSString stringWithFormat:@"<svg fill='%@' ", inkHex]];
    return [inked dataUsingEncoding:NSUTF8StringEncoding];
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

    OMLogMathBackendStateIfNeeded();

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
#if defined(_WIN32)
        OMMathDebugLog([NSString stringWithFormat:@"attachment-unavailable: backend=%@ formulaLength=%lu max=%lu formula=%@",
                        OMMathBackendAvailable() ? @"yes" : @"no",
                        (unsigned long)(formula != nil ? [formula length] : 0),
                        (unsigned long)maxFormulaLength,
                        OMMathLogSnippet(formula)]);
#endif
        return nil;
    }

    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    CGFloat zoom = OMMathZoomForFontSize(fontSize);
    CGFloat oversample = OMMathRasterOversampleFactor();
    CGFloat renderZoom = OMMathQuantizedRenderZoom(zoom, oversample);
#if defined(_WIN32)
    NSString *inkHex = nil;
#else
    NSString *inkHex = OMMathInkHexForTheme(theme);
#endif
    // Ink-coloured renders are cached apart from black ones (printing uses the
    // light theme while the preview may be dark).
    NSString *inkSuffix = inkHex != nil ? [@"|ink=" stringByAppendingString:inkHex] : @"";
    NSString *inkedFormula = [formula stringByAppendingString:inkSuffix];
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.2f|%@%@",
                          displayMath ? @"display" : @"inline",
                          fontSize,
                          OMMathVersionedFormula(formula),
                          inkSuffix];
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
    NSString *imageKey = [assetKey stringByAppendingString:inkSuffix];
    NSImage *baseImage = [OMMathBaseImageCache() objectForKey:imageKey];
#if !defined(_WIN32)
    NSData *svgData = nil;
#endif
    CGFloat imageRenderZoom = renderZoom;
    BOOL usedFallbackImage = NO;
    if (baseImage != nil) {
        if (stats != NULL) {
            stats->mathAssetCacheHits += 1;
        }
        OMRecordBestAvailableMathImage(inkedFormula, displayMath, renderZoom, baseImage);
    } else {
#if defined(_WIN32)
        if (stats != NULL) {
            stats->mathAssetCacheMisses += 1;
        }
        if (asyncMathGenerationEnabled) {
            CGFloat fallbackRenderZoom = 0.0;
            NSImage *fallbackImage = OMBestAvailableMathImage(inkedFormula, displayMath, &fallbackRenderZoom);
            if (fallbackImage != nil) {
                baseImage = fallbackImage;
                usedFallbackImage = YES;
                imageRenderZoom = fallbackRenderZoom > 0.0 ? fallbackRenderZoom : oversample;
                if (stats != NULL) {
                    stats->mathAssetCacheHits += 1;
                }
            }
        }

        if (!usedFallbackImage) {
            baseImage = OMPNGImageForMathFormula(formula,
                                                 displayMath,
                                                 renderZoom,
                                                 maxFormulaLength,
                                                 externalToolTimeout,
                                                 stats);
            if (baseImage == nil) {
                if (stats != NULL) {
                    stats->mathFailures += 1;
                    stats->mathTotalSeconds += (OMNow() - mathStart);
                }
#if defined(_WIN32)
                OMMathDebugLog([NSString stringWithFormat:@"attachment-render-failed: display=%@ formula=%@",
                                displayMath ? @"yes" : @"no",
                                OMMathLogSnippet(formula)]);
#endif
                return nil;
            }
            [OMMathBaseImageCache() setObject:baseImage forKey:imageKey];
            OMRecordBestAvailableMathImage(inkedFormula, displayMath, renderZoom, baseImage);
        }
#else
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
                NSImage *fallbackImage = OMBestAvailableMathImage(inkedFormula, displayMath, &fallbackRenderZoom);
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
            NSImage *decodedImage = [[[NSImage alloc] initWithData:OMMathSVGDataWithInk(svgData, inkHex)] autorelease];
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
            [OMMathBaseImageCache() setObject:decodedImage forKey:imageKey];
            baseImage = decodedImage;
            OMRecordBestAvailableMathImage(inkedFormula, displayMath, renderZoom, baseImage);
        }
#endif
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

static NSString *OMRawMathKey(NSString *unescapedFormula, BOOL display)
{
    return [NSString stringWithFormat:@"%@|%@", display ? @"d" : @"i", unescapedFormula];
}

static void OMQueueRawMath(NSMutableDictionary *queues, NSString *raw, BOOL display)
{
    NSString *key = OMRawMathKey(OMCommonMarkUnescaped(raw), display);
    NSMutableArray *queue = [queues objectForKey:key];
    if (queue == nil) {
        queue = [NSMutableArray array];
        [queues setObject:queue forKey:key];
    }
    [queue addObject:raw];
}

// Collects a block's $...$ and $$...$$ formulas from its raw source, using
// the same delimiter rules as OMAppendTextWithMathSpans and skipping code spans.
static void OMCollectRawMathSources(NSString *raw, NSMutableDictionary *queues)
{
    NSUInteger length = [raw length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [raw characterAtIndex:index];
        if (ch == '\\') {
            index += 2;
            continue;
        }
        if (ch == '`') {
            NSUInteger run = 1;
            while (index + run < length && [raw characterAtIndex:index + run] == '`') {
                run += 1;
            }
            NSString *fence = [raw substringWithRange:NSMakeRange(index, run)];
            NSRange close = [raw rangeOfString:fence options:0 range:NSMakeRange(index + run, length - index - run)];
            index = (close.location != NSNotFound) ? NSMaxRange(close) : index + run;
            continue;
        }
        if (ch != '$') {
            index += 1;
            continue;
        }
        BOOL display = (index + 1 < length && [raw characterAtIndex:index + 1] == '$');
        if (display) {
            NSUInteger close = index + 2;
            while (close + 1 < length) {
                unichar c = [raw characterAtIndex:close];
                if (c == '\\') {
                    close += 2;
                    continue;
                }
                if (c == '$' && [raw characterAtIndex:close + 1] == '$') {
                    break;
                }
                close += 1;
            }
            if (close + 1 < length && close > index + 2) {
                OMQueueRawMath(queues, [raw substringWithRange:NSMakeRange(index + 2, close - index - 2)], YES);
                index = close + 2;
            } else {
                index += 2;
            }
            continue;
        }
        if (index + 1 >= length || OMCharacterIsWhitespaceOrNewline([raw characterAtIndex:index + 1])) {
            index += 1;
            continue;
        }
        NSUInteger close = index + 1;
        BOOL found = NO;
        while (close < length) {
            unichar c = [raw characterAtIndex:close];
            if (c == '\\') {
                close += 2;
                continue;
            }
            if (c == '$') {
                BOOL precededByWhitespace = OMCharacterIsWhitespaceOrNewline([raw characterAtIndex:close - 1]);
                BOOL followedByDigit = (close + 1 < length) ? OMCharacterIsDigit([raw characterAtIndex:close + 1]) : NO;
                BOOL adjacentToDollar = ([raw characterAtIndex:close - 1] == '$') ||
                                        (close + 1 < length && [raw characterAtIndex:close + 1] == '$');
                if (!precededByWhitespace && !followedByDigit && !adjacentToDollar) {
                    found = YES;
                    break;
                }
            }
            close += 1;
        }
        if (found) {
            OMQueueRawMath(queues, [raw substringWithRange:NSMakeRange(index + 1, close - index - 1)], NO);
            index = close + 1;
        } else {
            index += 1;
        }
    }
}

// cmark has already dropped backslashes before punctuation in text nodes
// ("\," becomes ","), so formulas are rendered from the block's raw source.
static void OMPrepareRawMathSources(cmark_node *node, const OMRenderContext *renderContext)
{
    if (renderContext == NULL || renderContext->rawMathSources == nil) {
        return;
    }
    [renderContext->rawMathSources removeAllObjects];
    if (!OMShouldParseMathSpans(renderContext)) {
        return;
    }
    NSString *raw = OMSourceTextForNodeLines(node, renderContext);
    if ([raw rangeOfString:@"$"].location != NSNotFound) {
        OMCollectRawMathSources(raw, renderContext->rawMathSources);
    }
}

// The raw source for a formula cut from a cmark text node, or the formula itself.
static NSString *OMRawMathFormula(NSString *formula, BOOL display, const OMRenderContext *renderContext)
{
    if (renderContext == NULL || renderContext->rawMathSources == nil) {
        return formula;
    }
    NSMutableArray *queue = [renderContext->rawMathSources objectForKey:OMRawMathKey(formula, display)];
    if ([queue count] == 0) {
        return formula;
    }
    NSString *raw = [[[queue objectAtIndex:0] retain] autorelease];
    [queue removeObjectAtIndex:0];
    return raw;
}

static NSDictionary *OMEmojiShortcodeTable(void)
{
    static NSDictionary *table = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *built = [NSMutableDictionary dictionary];
        size_t index = 0;
        for (; index < sizeof(OMEmojiShortcodes) / sizeof(OMEmojiShortcodes[0]); index++) {
            unichar character = OMEmojiShortcodes[index].character;
            [built setObject:[NSString stringWithCharacters:&character length:1]
                      forKey:[NSString stringWithUTF8String:OMEmojiShortcodes[index].name]];
        }
        table = [built copy];
    });
    return table;
}

// The emoji characters the shortcode table can produce.
static NSCharacterSet *OMEmojiCharacterSet(void)
{
    static NSCharacterSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *built = [[NSMutableCharacterSet alloc] init];
        size_t index = 0;
        for (; index < sizeof(OMEmojiShortcodes) / sizeof(OMEmojiShortcodes[0]); index++) {
            [built addCharactersInRange:NSMakeRange(OMEmojiShortcodes[index].character, 1)];
        }
        set = built;
    });
    return set;
}

// ":name:" -> emoji, for GitHub shortcodes in the table; others stay as typed.
static NSString *OMStringByReplacingEmojiShortcodes(NSString *text)
{
    if (text == nil || [text rangeOfString:@":"].location == NSNotFound) {
        return text;
    }
    NSDictionary *table = OMEmojiShortcodeTable();
    NSMutableString *result = nil;
    NSUInteger length = [text length];
    NSUInteger copied = 0;
    NSUInteger index = 0;
    while (index < length) {
        if ([text characterAtIndex:index] != ':') {
            index += 1;
            continue;
        }
        NSUInteger end = index + 1;
        while (end < length && end - index <= 48) {
            unichar ch = [text characterAtIndex:end];
            BOOL nameCharacter = (ch < 128 && (isalnum((int)ch) || ch == '_' || ch == '+' || ch == '-'));
            if (!nameCharacter) {
                break;
            }
            end += 1;
        }
        if (end < length && [text characterAtIndex:end] == ':' && end > index + 1) {
            NSString *emoji = [table objectForKey:[text substringWithRange:NSMakeRange(index + 1, end - index - 1)]];
            if (emoji != nil) {
                if (result == nil) {
                    result = [NSMutableString stringWithCapacity:length];
                }
                [result appendString:[text substringWithRange:NSMakeRange(copied, index - copied)]];
                [result appendString:emoji];
                copied = end + 1;
                index = end + 1;
                continue;
            }
        }
        index += 1;
    }
    if (result == nil) {
        return text;
    }
    [result appendString:[text substringFromIndex:copied]];
    return result;
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
        OMAppendString(output, OMStringByReplacingEmojiShortcodes(text), attributes);
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
            OMAppendString(output, OMStringByReplacingEmojiShortcodes([text substringWithRange:NSMakeRange(cursor, length - cursor)]), attributes);
            break;
        }

        if (dollarLocation > cursor) {
            OMAppendString(output, OMStringByReplacingEmojiShortcodes([text substringWithRange:NSMakeRange(cursor, dollarLocation - cursor)]), attributes);
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
                        formula = OMRawMathFormula(formula, YES, renderContext);
                        OMAppendDisplayMathFormula(formula,
                                                   theme,
                                                   output,
                                                   attributes,
                                                   scale,
                                                   renderContext);
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
                        formula = OMRawMathFormula(formula, NO, renderContext);
                        if ([formula length] > 0) {
                            NSAttributedString *attachment = OMMathAttachmentAttributedString(formula,
                                                                                               theme,
                                                                                               attributes,
                                                                                               scale,
                                                                                               NO,
                                                                                               renderContext);
                            if (attachment != nil) {
                                NSUInteger objectStart = [output length];
                                OMAppendAttributedSegment(output, attachment);
                                OMTagAppendedObject(output,
                                                    objectStart,
                                                    OMRenderedObjectKindInlineMath,
                                                    formula,
                                                    [NSString stringWithFormat:@"$%@$", formula]);
                            } else {
                                NSDictionary *mathAttrs = OMMathAttributes(theme, attributes, scale, NO);
                                OMAppendString(output, OMReadableMathFallbackString(formula), mathAttrs);
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

static void OMAppendDisplayMathFormula(NSString *formula,
                                       OMTheme *theme,
                                       NSMutableAttributedString *output,
                                       NSMutableDictionary *attributes,
                                       CGFloat scale,
                                       const OMRenderContext *renderContext)
{
    if (formula == nil || [formula length] == 0) {
        return;
    }

    NSDictionary *mathAttrs = OMMathAttributes(theme, attributes, scale, YES);
    NSAttributedString *attachment = OMMathAttachmentAttributedString(formula,
                                                                      theme,
                                                                      attributes,
                                                                      scale,
                                                                      YES,
                                                                      renderContext);
    if (attachment != nil) {
        NSMutableAttributedString *segment = [[[NSMutableAttributedString alloc]
            initWithAttributedString:attachment] autorelease];
        if ([segment length] > 0) {
            [segment addAttributes:mathAttrs range:NSMakeRange(0, [segment length])];
        }
        NSUInteger objectStart = [output length];
        OMAppendAttributedSegment(output, segment);
        OMTagAppendedObject(output,
                            objectStart,
                            OMRenderedObjectKindDisplayMath,
                            formula,
                            [NSString stringWithFormat:@"$$\n%@\n$$", OMTrimmedCellText(formula)]);
    } else {
        OMAppendString(output, OMReadableMathFallbackString(formula), mathAttrs);
    }
}

// Recover fenced display math directly from source lines before cmark can
// reinterpret interior lines as headings, emphasis, or other Markdown.
static BOOL OMTryRenderRawDisplayMathBlock(cmark_node *node,
                                           OMTheme *theme,
                                           NSMutableAttributedString *output,
                                           NSMutableDictionary *attributes,
                                           NSMutableArray *listStack,
                                           CGFloat scale,
                                           const OMRenderContext *renderContext)
{
    if (!OMShouldParseMathSpans(renderContext) || node == NULL) {
        return NO;
    }

    cmark_node_type type = cmark_node_get_type(node);
    if (type == CMARK_NODE_DOCUMENT ||
        type == CMARK_NODE_LIST ||
        type == CMARK_NODE_ITEM ||
        type == CMARK_NODE_BLOCK_QUOTE) {
        return NO;
    }

    NSUInteger startLine = 0;
    if (!OMNodeLineBounds(node, &startLine, NULL)) {
        return NO;
    }
    if (OMDisplayMathLineAlreadyConsumed(startLine, renderContext)) {
        return NO;
    }

    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    NSUInteger endFenceLine = 0;
    NSString *formula = nil;
    if (!OMDisplayMathFenceRangeStartingAtLine(sourceLines,
                                               startLine,
                                               &endFenceLine,
                                               &formula)) {
        return NO;
    }

    NSUInteger targetStart = [output length];
    OMAppendDisplayMathFormula(formula, theme, output, attributes, scale, renderContext);
    if (OMIsTightList(listStack)) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }

    OMConsumeDisplayMathLineRange(startLine, endFenceLine, renderContext);
    OMRecordBlockAnchorForSourceRange(node,
                                      startLine,
                                      endFenceLine,
                                      targetStart,
                                      [output length],
                                      renderContext);
    return YES;
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

// Rebuild display-math blocks from source slices so CommonMark escaping
// does not collapse TeX row separators like `\\` inside `cases`.
static NSString *OMRawDisplayMathFormulaFromNodes(cmark_node *startNode,
                                                  cmark_node *endNode,
                                                  const OMRenderContext *renderContext)
{
    NSArray *sourceLines = (renderContext != NULL) ? renderContext->sourceLines : nil;
    if (startNode == NULL || endNode == NULL || sourceLines == nil) {
        return nil;
    }

    NSMutableString *formula = [NSMutableString string];
    cmark_node *cursor = cmark_node_next(startNode);
    while (cursor != NULL && cursor != endNode) {
        cmark_node_type type = cmark_node_get_type(cursor);
        if (type == CMARK_NODE_TEXT) {
            NSString *fragment = OMSourceFragmentForNode(cursor, sourceLines);
            if (fragment == nil) {
                return nil;
            }
            [formula appendString:fragment];
        } else if (type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK) {
            [formula appendString:@"\n"];
        } else {
            return nil;
        }
        cursor = cmark_node_next(cursor);
    }

    return [formula stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
                NSString *normalized = OMRawDisplayMathFormulaFromNodes(startNode, cursor, renderContext);
                if (normalized == nil) {
                    normalized = [formula stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                }
                if ([normalized length] == 0) {
                    return NULL;
                }

                OMAppendDisplayMathFormula(normalized,
                                           theme,
                                           output,
                                           attributes,
                                           scale,
                                           renderContext);
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
@property (nonatomic, retain) NSArray *codeBlockRanges;
@property (nonatomic, retain) NSArray *blockquoteRanges;
@property (nonatomic, retain) NSArray *blockAnchors;
@property (nonatomic, retain) NSArray *diagramBlocks;
@property (nonatomic, retain) NSArray *headings;
- (NSAttributedString *)om_attributedStringFromMarkdown:(NSString *)markdown;
@end

@implementation OMMarkdownRenderer

+ (NSString *)anchorSlugForHeadingTitle:(NSString *)title
{
    return OMHeadingAnchorSlug(title);
}

+ (void)invalidateCachedMathForFormula:(NSString *)formula
{
    if ([formula length] == 0) {
        return;
    }
    NSMutableDictionary *generations = OMMathFormulaGenerations();
    @synchronized (generations) {
        NSUInteger next = [[generations objectForKey:formula] unsignedIntegerValue] + 1;
        [generations setObject:[NSNumber numberWithUnsignedInteger:next] forKey:formula];
    }
}

+ (NSArray *)localImageURLsInMarkdown:(NSString *)markdown baseURL:(NSURL *)baseURL
{
    NSData *data = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return [NSArray array];
    }
    cmark_node *document = OMGFMParseDocument([data bytes], [data length], CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return [NSArray array];
    }
    OMMarkdownParsingOptions *options = [[[OMMarkdownParsingOptions alloc] init] autorelease];
    [options setBaseURL:baseURL];
    OMRenderContext context = {0};
    context.parsingOptions = options;
    NSMutableArray *urls = [NSMutableArray array];
    cmark_iter *iter = cmark_iter_new(document);
    cmark_event_type event;
    while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        cmark_node *node = cmark_iter_get_node(iter);
        if (event != CMARK_EVENT_ENTER || cmark_node_get_type(node) != CMARK_NODE_IMAGE) {
            continue;
        }
        const char *literal = cmark_node_get_url(node);
        NSURL *url = OMResolvedImageURL(literal ? [NSString stringWithUTF8String:literal] : nil, &context);
        if ([url isFileURL] && ![urls containsObject:url]) {
            [urls addObject:url];
        }
    }
    cmark_iter_free(iter);
    cmark_node_free(document);
    return urls;
}

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
        NSRecursiveLock *lock = OMAppKitGlobalLock();
        [lock lock];
        if (theme == nil) {
            theme = [OMTheme defaultTheme];
        }
        if (parsingOptions == nil) {
            parsingOptions = [OMMarkdownParsingOptions defaultOptions];
        }
        [lock unlock];
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
    [_diagramBlocks release];
    [_headings release];
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
    NSRecursiveLock *lock = OMAppKitGlobalLock();
    [lock lock];
    @try {
        return [self om_attributedStringFromMarkdown:markdown];
    } @finally {
        [lock unlock];
    }
}

- (NSAttributedString *)om_attributedStringFromMarkdown:(NSString *)markdown
{
    if (markdown == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    NSString *markdownForParsing = OMMarkdownByBlankingFrontMatter(markdown);
    if (markdownForParsing == nil) {
        markdownForParsing = markdown;
    }

    BOOL perfLogging = OMPerformanceLoggingEnabled();
    NSTimeInterval totalStart = perfLogging ? OMNow() : 0.0;

    NSData *markdownData = [markdownForParsing dataUsingEncoding:NSUTF8StringEncoding];
    if (markdownData == nil) {
        return [[[NSAttributedString alloc] initWithString:@""] autorelease];
    }

    const char *bytes = (const char *)[markdownData bytes];
    size_t length = (size_t)[markdownData length];
    NSUInteger cmarkOptions = self.parsingOptions != nil ? [self.parsingOptions cmarkOptions] : (NSUInteger)CMARK_OPT_DEFAULT;
    NSTimeInterval parseStart = perfLogging ? OMNow() : 0.0;
    cmark_node *document = OMGFMParseDocument(bytes, length, (int)cmarkOptions);
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
    NSMutableArray *diagramBlocks = [NSMutableArray array];
    NSMutableArray *consumedDisplayMathLineRanges = [NSMutableArray array];
    NSArray *sourceLines = OMSourceLinesForMarkdown(markdown);
    OMMathPerfStats stats = {0};
    OMRenderContext renderContext;
    renderContext.parsingOptions = self.parsingOptions;
    renderContext.sourceLines = sourceLines;
    OMBlockSignatureIndex *blockSignatures = [[[OMBlockSignatureIndex alloc] initWithSourceLines:sourceLines] autorelease];
    renderContext.blockSignatures = blockSignatures;
    renderContext.blockAnchors = blockAnchors;
    renderContext.diagramBlocks = diagramBlocks;
    renderContext.listStack = listStack;
    renderContext.quoteKinds = [NSMutableArray array];
    NSMutableArray *headings = [NSMutableArray array];
    renderContext.headings = headings;
    renderContext.headingSlugCounts = [NSMutableDictionary dictionary];
    renderContext.consumedDisplayMathLineRanges = consumedDisplayMathLineRanges;
    renderContext.rawMathSources = [NSMutableDictionary dictionary];
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
    [self setBlockAnchors:blockAnchors];
    [self setDiagramBlocks:diagramBlocks];
    [self setHeadings:headings];
    OMTrimTrailingNewlines(output);
    [self setCodeBlockRanges:OMRangesClampedToLength(codeRanges, [output length])];
    [self setBlockquoteRanges:OMRangesClampedToLength(blockquoteRanges, [output length])];
    OMApplyEmojiFont(output, codeRanges);
    OMSizeBlockGaps(output,
                    codeRanges,
                    (self.theme.baseFont != nil ? [self.theme.baseFont pointSize] : 14.0) * scale,
                    scale);
    [output removeAttribute:OMHardLineBreakAttributeName range:NSMakeRange(0, [output length])];
    OMResolvePendingRenderedObjects(output, blockAnchors, markdown);
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

// Raw Markdown of a GFM table cell, cut from its source line using the byte
// columns cmark-gfm records (1-based UTF-8 offsets on the whole line, so this
// holds inside block quotes and list items too).
static NSString *OMGFMTableCellMarkdown(cmark_node *cell, const OMRenderContext *renderContext)
{
    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    int line = cmark_node_get_start_line(cell);
    int startColumn = cmark_node_get_start_column(cell);
    int endColumn = cmark_node_get_end_column(cell);
    if (sourceLines != nil && line >= 1 && (NSUInteger)line <= [sourceLines count] &&
        startColumn >= 1 && endColumn >= startColumn) {
        NSData *bytes = [[sourceLines objectAtIndex:(NSUInteger)line - 1] dataUsingEncoding:NSUTF8StringEncoding];
        if ((NSUInteger)endColumn <= [bytes length]) {
            NSData *slice = [bytes subdataWithRange:NSMakeRange((NSUInteger)startColumn - 1,
                                                                (NSUInteger)(endColumn - startColumn + 1))];
            NSString *text = [[[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding] autorelease];
            if (text != nil) {
                return OMTrimmedCellText(text);
            }
        }
    }
    return OMInlinePlainText(cell);
}

static void OMRenderGFMTable(cmark_node *node,
                             OMTheme *theme,
                             NSMutableAttributedString *output,
                             NSMutableDictionary *attributes,
                             NSMutableArray *listStack,
                             NSUInteger quoteLevel,
                             CGFloat scale,
                             CGFloat layoutWidth,
                             const OMRenderContext *renderContext)
{
    NSUInteger columnCount = cmark_gfm_extensions_get_table_columns(node);
    if (columnCount == 0) {
        return;
    }
    uint8_t *alignmentBytes = cmark_gfm_extensions_get_table_alignments(node);
    NSMutableArray *alignments = [NSMutableArray arrayWithCapacity:columnCount];
    NSUInteger column = 0;
    for (; column < columnCount; column++) {
        uint8_t alignment = alignmentBytes != NULL ? alignmentBytes[column] : 0;
        OMPipeTableAlignment value = OMPipeTableAlignmentLeft;
        if (alignment == 'c') {
            value = OMPipeTableAlignmentCenter;
        } else if (alignment == 'r') {
            value = OMPipeTableAlignmentRight;
        }
        [alignments addObject:[NSNumber numberWithUnsignedInteger:value]];
    }

    NSMutableArray *rows = [NSMutableArray array];
    cmark_node *row = cmark_node_first_child(node);
    for (; row != NULL; row = cmark_node_next(row)) {
        if (cmark_node_get_type(row) != CMARK_NODE_TABLE_ROW) {
            continue;
        }
        NSMutableArray *cells = [NSMutableArray arrayWithCapacity:columnCount];
        cmark_node *cell = cmark_node_first_child(row);
        for (; cell != NULL && [cells count] < columnCount; cell = cmark_node_next(cell)) {
            if (cmark_node_get_type(cell) == CMARK_NODE_TABLE_CELL) {
                [cells addObject:OMGFMTableCellMarkdown(cell, renderContext)];
            }
        }
        while ([cells count] < columnCount) {
            [cells addObject:@""];
        }
        [rows addObject:cells];
    }
    if ([rows count] == 0) {
        return;
    }

    NSUInteger objectStart = [output length];
    OMRenderPipeTable(rows,
                      alignments,
                      theme,
                      output,
                      attributes,
                      listStack,
                      quoteLevel,
                      scale,
                      layoutWidth,
                      renderContext);
    NSString *tableMarkdown = OMSourceTextForNodeLines(node, renderContext);
    if (tableMarkdown != nil) {
        OMTagAppendedObject(output, objectStart, OMRenderedObjectKindTable, tableMarkdown, nil);
    }
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
    NSMutableDictionary *paraAttrs = [attributes mutableCopy];
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    NSParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 12.0 * scale, 0.0, 1.5, fontSize);
    [paraAttrs setObject:style forKey:NSParagraphStyleAttributeName];
    BOOL inAlert = (renderContext != NULL && [[renderContext->quoteKinds lastObject] boolValue]);
    if (quoteLevel > 0 && !inAlert && theme.blockquoteTextColor != nil) {
        [paraAttrs setObject:theme.blockquoteTextColor forKey:NSForegroundColorAttributeName];
    }

    NSUInteger paragraphStart = [output length];
    OMPrepareRawMathSources(node, renderContext);
    OMRenderInlines(node, theme, output, paraAttrs, scale, renderContext);
    [paraAttrs release];
    OMTightenHardLineBreaks(output, NSMakeRange(paragraphStart, [output length] - paragraphStart));

    if (OMIsTightList(listStack)) {
        OMAppendString(output, @"\n", attributes);
    } else {
        OMAppendString(output, @"\n\n", attributes);
    }
}

static NSString *OMHeadingAnchorSlug(NSString *title)
{
    NSString *lower = [(title != nil ? title : @"") lowercaseString];
    NSMutableCharacterSet *kept = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [kept addCharactersInString:@"_- "];
    NSMutableString *slug = [NSMutableString stringWithCapacity:[lower length]];
    NSUInteger index = 0;
    for (; index < [lower length]; index++) {
        unichar ch = [lower characterAtIndex:index];
        if (ch == ' ') {
            [slug appendString:@"-"];
        } else if ([kept characterIsMember:ch]) {
            [slug appendFormat:@"%C", ch];
        }
    }
    return slug;
}

// GitHub's de-duplication (github-slugger): a repeat of "x" becomes "x-1",
// then "x-2", skipping any slug already taken.
static NSString *OMUniqueHeadingSlug(NSString *title, NSMutableDictionary *counts)
{
    NSString *original = OMHeadingAnchorSlug(title);
    if (counts == nil) {
        return original;
    }
    NSString *slug = original;
    while ([counts objectForKey:slug] != nil) {
        NSUInteger next = [[counts objectForKey:original] unsignedIntegerValue] + 1;
        [counts setObject:[NSNumber numberWithUnsignedInteger:next] forKey:original];
        slug = [NSString stringWithFormat:@"%@-%lu", original, (unsigned long)next];
    }
    [counts setObject:[NSNumber numberWithUnsignedInteger:0] forKey:slug];
    return slug;
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

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    NSFont *font = [headingAttrs objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    // GitHub: 24px above a heading, 16px below; H1 and H2 are underlined.
    BOOL underlined = (level <= 2);
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent,
                                                                (underlined ? 6.0 : 12.0) * scale,
                                                                0.0, 1.25, fontSize);
    [style setParagraphSpacingBefore:8.0 * scale];
    [headingAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMPrepareRawMathSources(node, renderContext);
    NSUInteger headingStart = [output length];
    OMRenderInlines(node, theme, output, headingAttrs, scale, renderContext);
    [headingAttrs release];
    NSRange headingRange = NSMakeRange(headingStart, [output length] - headingStart);
    if (renderContext != NULL && renderContext->headings != nil) {
        NSString *title = OMInlinePlainText(node);
        NSString *anchor = OMUniqueHeadingSlug(title, renderContext->headingSlugCounts);
        if (headingRange.length > 0) {
            [output addAttribute:OMMarkdownRendererHeadingAnchorAttributeName value:anchor range:headingRange];
        }
        [renderContext->headings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:level], OMMarkdownRendererHeadingLevelKey,
            (title != nil ? title : @""), OMMarkdownRendererHeadingTitleKey,
            anchor, OMMarkdownRendererHeadingAnchorKey,
            [NSValue valueWithRange:headingRange], OMMarkdownRendererHeadingRangeKey,
            [NSNumber numberWithInt:cmark_node_get_start_line(node)], OMMarkdownRendererHeadingSourceLineKey,
            nil]];
    }
    OMAppendString(output, @"\n", attributes);

    if (underlined && theme.hrColor != nil) {
        CGFloat availableWidth = layoutWidth > 0.0 ? (layoutWidth - indent) : 0.0;
        OMAppendRule(output, attributes, theme.hrColor, availableWidth, MAX(1.0, floor(scale + 0.5)), indent, 12.0 * scale);
    }
    OMAppendString(output, @"\n", attributes);
}

static NSColor *OMMermaidDiagnosticColorForTheme(OMTheme *theme)
{
    NSColor *base = theme != nil ? [theme baseTextColor] : nil;
    if (base == nil) {
        return [NSColor grayColor];
    }
    NSColor *muted = [base colorWithAlphaComponent:0.7];
    return muted != nil ? muted : base;
}

// Diagram line numbers are relative to the fenced block, so shift them onto the
// enclosing document, which is the line the reader can actually navigate to.
static NSString *OMMermaidDiagnosticMessageForError(NSError *error, cmark_node *codeBlockNode)
{
    NSString *description = [[error userInfo] objectForKey:NSLocalizedDescriptionKey];
    if (description == nil || [description length] == 0) {
        description = @"Diagram could not be parsed.";
    }

    NSNumber *lineNumber = [[error userInfo] objectForKey:OMMermaidERDiagramErrorLineNumberKey];
    if (lineNumber == nil || [lineNumber unsignedIntegerValue] == 0) {
        return [NSString stringWithFormat:@"mermaid erDiagram: %@", description];
    }

    NSUInteger reportedLine = [lineNumber unsignedIntegerValue];
    NSUInteger fenceLine = 0;
    if (OMNodeLineBounds(codeBlockNode, &fenceLine, NULL)) {
        reportedLine += fenceLine;
    }
    return [NSString stringWithFormat:@"mermaid erDiagram, line %lu: %@",
            (unsigned long)reportedLine,
            description];
}

// Colors follow the pipe-table palette so a diagram sits in the same visual
// family as a table, in both light and dark themes.
static OMMermaidERDrawingStyle *OMMermaidStyleForTheme(OMTheme *theme,
                                                       NSDictionary *attributes,
                                                       CGFloat scale)
{
    NSFont *baseFont = [attributes objectForKey:NSFontAttributeName];
    CGFloat baseSize = baseFont != nil
        ? [baseFont pointSize]
        : ((theme.baseFont != nil ? [theme.baseFont pointSize] : 14.0) * scale);
    CGFloat attributeSize = MAX(baseSize * 0.84, 8.0 * scale);
    CGFloat titleSize = MAX(baseSize * 0.92, 9.0 * scale);
    CGFloat labelSize = MAX(baseSize * 0.76, 7.5 * scale);

    NSFont *attributeFont = baseFont != nil
        ? [NSFont fontWithName:[baseFont fontName] size:attributeSize]
        : [NSFont systemFontOfSize:attributeSize];
    NSFont *titleFont = baseFont != nil
        ? [NSFont fontWithName:[baseFont fontName] size:titleSize]
        : [NSFont systemFontOfSize:titleSize];
    NSFont *boldTitleFont = OMFontWithTraits(titleFont, NSBoldFontMask);
    NSFont *labelFont = baseFont != nil
        ? [NSFont fontWithName:[baseFont fontName] size:labelSize]
        : [NSFont systemFontOfSize:labelSize];

    NSColor *textColor = [attributes objectForKey:NSForegroundColorAttributeName];
    if (textColor == nil) {
        textColor = theme.baseTextColor != nil ? theme.baseTextColor : [NSColor blackColor];
    }
    NSColor *mutedColor = [textColor colorWithAlphaComponent:0.68];
    if (mutedColor == nil) {
        mutedColor = textColor;
    }
    NSColor *edgeColor = [textColor colorWithAlphaComponent:0.55];
    if (edgeColor == nil) {
        edgeColor = textColor;
    }

    OMMermaidERDrawingStyle *style = [[[OMMermaidERDrawingStyle alloc] init] autorelease];
    [style setTitleFont:(boldTitleFont != nil ? boldTitleFont : titleFont)];
    [style setAttributeFont:attributeFont];
    [style setLabelFont:labelFont];
    [style setBorderColor:OMPipeTableBorderColorForTheme(theme)];
    [style setTitleBackgroundColor:OMPipeTableHeaderBackgroundColorForTheme(theme)];
    [style setBodyBackgroundColor:OMPipeTableBodyBackgroundColorForTheme(theme)];
    [style setTextColor:textColor];
    [style setKeyColor:(theme.linkColor != nil ? theme.linkColor : mutedColor)];
    [style setCommentColor:mutedColor];
    [style setEdgeColor:edgeColor];
    [style setBorderWidth:MAX(1.0, scale)];
    return style;
}

// Draws a parsed erDiagram as a block attachment. Returns NO when the diagram
// cannot be laid out, which leaves the caller on the code-block path.
static BOOL OMAppendMermaidDiagram(OMMermaidERDiagram *diagram,
                                   NSString *source,
                                   OMTheme *theme,
                                   NSMutableAttributedString *output,
                                   NSMutableDictionary *attributes,
                                   NSUInteger quoteLevel,
                                   CGFloat scale,
                                   const OMRenderContext *renderContext)
{
    OMMermaidERDrawingStyle *style = OMMermaidStyleForTheme(theme, attributes, scale);
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale) + 20.0 * scale;
    CGFloat layoutWidth = renderContext != NULL ? renderContext->layoutWidth : 0.0;
    CGFloat maximumWidth = 0.0;
    if (layoutWidth > 0.0) {
        maximumWidth = layoutWidth - indent - (16.0 * scale);
        if (maximumWidth < 120.0 * scale) {
            maximumWidth = 120.0 * scale;
        }
    }

    NSMutableDictionary *diagramAttributes = [attributes mutableCopy];
    [diagramAttributes removeObjectForKey:NSBackgroundColorAttributeName];
    NSMutableParagraphStyle *paragraphStyle = OMParagraphStyleWithIndent(indent,
                                                                        indent,
                                                                        14.0 * scale,
                                                                        0.0,
                                                                        1.0,
                                                                        0.0);
    [paragraphStyle setParagraphSpacingBefore:10.0 * scale];
    // Centred like display math, as GitHub shows diagrams.
    [paragraphStyle setAlignment:NSCenterTextAlignment];
    [diagramAttributes setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];

    NSAttributedString *attachment = OMMermaidERAttachmentAttributedString(diagram,
                                                                          style,
                                                                          maximumWidth,
                                                                          diagramAttributes);
    if (attachment == nil) {
        [diagramAttributes release];
        return NO;
    }

    NSUInteger diagramStart = [output length];
    OMAppendAttributedSegment(output, attachment);
    NSString *diagramSource = (source != nil ? source : @"");
    OMTagAppendedObject(output,
                        diagramStart,
                        OMRenderedObjectKindDiagram,
                        diagramSource,
                        [NSString stringWithFormat:@"```mermaid\n%@%@```",
                         diagramSource,
                         ([diagramSource hasSuffix:@"\n"] ? @"" : @"\n")]);
    if (renderContext != NULL && renderContext->diagramBlocks != nil) {
        NSRange diagramRange = NSMakeRange(diagramStart, [output length] - diagramStart);
        [renderContext->diagramBlocks addObject:
            [NSDictionary dictionaryWithObjectsAndKeys:
                [NSValue valueWithRange:diagramRange], OMMarkdownRendererDiagramRangeKey,
                (source != nil ? source : @""), OMMarkdownRendererDiagramSourceKey,
                nil]];
    }
    OMAppendString(output, @"\n", diagramAttributes);
    // A blank line after the diagram, as after code blocks and paragraphs.
    OMAppendString(output, @"\n", attributes);
    [diagramAttributes release];
    return YES;
}

// Mermaid fences are recognized here. An erDiagram that parses and fits is drawn
// as an attachment; everything else -- other mermaid diagram types, malformed
// source, and diagrams too large to draw -- falls back to the code block, with a
// diagnostic line when the block claimed to be an erDiagram.
static BOOL OMTryRenderMermaidDiagram(cmark_node *node,
                                      NSString *code,
                                      OMTheme *theme,
                                      NSMutableAttributedString *output,
                                      NSMutableDictionary *attributes,
                                      NSUInteger quoteLevel,
                                      CGFloat scale,
                                      const OMRenderContext *renderContext,
                                      NSString **diagnosticOut)
{
    if (diagnosticOut != NULL) {
        *diagnosticOut = nil;
    }

    NSString *fenceToken = OMPrimaryFenceToken(node);
    if (fenceToken == nil || ![fenceToken isEqualToString:@"mermaid"]) {
        return NO;
    }
    if (!OMNativeDiagramRenderingEnabled(renderContext)) {
        return NO;
    }
    if (![OMMermaidERDiagram sourceDeclaresERDiagram:code]) {
        return NO;
    }

    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:code error:&error];
    if (diagram == nil) {
        if (diagnosticOut != NULL) {
            *diagnosticOut = OMMermaidDiagnosticMessageForError(error, node);
        }
        return NO;
    }

    if (OMAppendMermaidDiagram(diagram, code, theme, output, attributes, quoteLevel, scale, renderContext)) {
        return YES;
    }

    if (diagnosticOut != NULL) {
        *diagnosticOut = [NSString stringWithFormat:
            @"mermaid erDiagram: too large to draw (%lu entities, %lu relationships).",
            (unsigned long)[[diagram entities] count],
            (unsigned long)[[diagram relationships] count]];
    }
    return NO;
}

static void OMAppendMermaidDiagnostic(NSString *diagnostic,
                                      OMTheme *theme,
                                      NSMutableAttributedString *output,
                                      NSDictionary *blockAttributes,
                                      CGFloat indent,
                                      CGFloat codeFontSize,
                                      CGFloat scale)
{
    if (diagnostic == nil || [diagnostic length] == 0) {
        return;
    }

    NSMutableDictionary *diagnosticAttrs = [blockAttributes mutableCopy];
    NSFont *blockFont = [diagnosticAttrs objectForKey:NSFontAttributeName];
    CGFloat diagnosticSize = codeFontSize * 0.92;
    NSFont *sizedFont = blockFont != nil ? [NSFont fontWithName:[blockFont fontName] size:diagnosticSize] : nil;
    if (sizedFont == nil) {
        sizedFont = blockFont;
    }
    NSFont *italicFont = OMFontWithTraits(sizedFont, NSItalicFontMask);
    if (italicFont != nil) {
        [diagnosticAttrs setObject:italicFont forKey:NSFontAttributeName];
    } else if (sizedFont != nil) {
        [diagnosticAttrs setObject:sizedFont forKey:NSFontAttributeName];
    }
    [diagnosticAttrs setObject:OMMermaidDiagnosticColorForTheme(theme)
                        forKey:NSForegroundColorAttributeName];
    [diagnosticAttrs removeObjectForKey:NSBackgroundColorAttributeName];

    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent,
                                                                indent,
                                                                8.0 * scale,
                                                                0.0,
                                                                1.3,
                                                                diagnosticSize);
    [style setParagraphSpacingBefore:4.0 * scale];
    [diagnosticAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMAppendString(output, diagnostic, diagnosticAttrs);
    OMAppendString(output, @"\n", diagnosticAttrs);
    [diagnosticAttrs release];
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
    NSString *mermaidDiagnostic = nil;
    if (OMTryRenderMermaidDiagram(node,
                                  code,
                                  theme,
                                  output,
                                  attributes,
                                  quoteLevel,
                                  scale,
                                  renderContext,
                                  &mermaidDiagnostic)) {
        return;
    }

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

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
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
    OMAppendMermaidDiagnostic(mermaidDiagnostic,
                              theme,
                              output,
                              blockAttrs,
                              indent + padding,
                              blockCodeFontSize,
                              scale);
    OMAppendString(output, @"\n", attributes);
    [blockAttrs release];
}

static void OMRenderThematicBreak(OMTheme *theme,
                                  NSMutableAttributedString *output,
                                  NSMutableDictionary *attributes,
                                  CGFloat layoutWidth)
{
    // GitHub draws <hr> as a bar a quarter of the text size tall.
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : 14.0;
    NSColor *color = theme.hrColor != nil ? theme.hrColor : [NSColor lightGrayColor];
    OMAppendRule(output, attributes, color, layoutWidth, MAX(2.0, floor(size * 0.25 + 0.5)), 0.0, 12.0);
    OMAppendString(output, @"\n", attributes);
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
        // Loose items already end in a blank line; top it up to one.
        NSString *text = [output string];
        NSUInteger trailing = 0;
        while (trailing < 2 && trailing < [text length] &&
               [text characterAtIndex:([text length] - 1 - trailing)] == '\n') {
            trailing += 1;
        }
        for (; trailing < 2; trailing++) {
            OMAppendString(output, @"\n", attributes);
        }
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
    if (OMGFMNodeIsTaskItem(node)) {
        NSString *box = cmark_gfm_extensions_get_tasklist_item_checked(node) ? @"\u2611 " : @"\u2610 ";
        BOOL bullet = ((cmark_list_type)[[OMListContext(listStack) objectForKey:@"type"] intValue] == CMARK_BULLET_LIST);
        prefix = bullet ? box : [prefix stringByAppendingString:box];
    }
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
                                                        1.5,
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

// GitHub alerts: a block quote whose first line is exactly "[!NOTE]",
// "[!TIP]", "[!IMPORTANT]", "[!WARNING]" or "[!CAUTION]".
static NSString *OMAlertKindForBlockquote(cmark_node *node, const OMRenderContext *renderContext)
{
    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    int line = cmark_node_get_start_line(node);
    if (sourceLines == nil || line < 1 || (NSUInteger)line > [sourceLines count]) {
        return nil;
    }
    // The marker line carries one ">" per enclosing quote.
    NSUInteger depth = 0;
    cmark_node *ancestor = node;
    for (; ancestor != NULL; ancestor = cmark_node_parent(ancestor)) {
        if (cmark_node_get_type(ancestor) == CMARK_NODE_BLOCK_QUOTE) {
            depth += 1;
        }
    }
    NSString *text = [sourceLines objectAtIndex:(NSUInteger)line - 1];
    NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
    NSUInteger index = 0;
    NSUInteger markers = 0;
    while (index < [text length]) {
        unichar ch = [text characterAtIndex:index];
        if (ch == '>') {
            markers += 1;
        } else if (![spaces characterIsMember:ch]) {
            break;
        }
        index += 1;
    }
    if (markers != depth) {
        return nil;
    }
    NSString *rest = [[[text substringFromIndex:index] stringByTrimmingCharactersInSet:spaces] uppercaseString];
    NSArray *kinds = [NSArray arrayWithObjects:@"NOTE", @"TIP", @"IMPORTANT", @"WARNING", @"CAUTION", nil];
    for (NSString *kind in kinds) {
        if ([rest isEqualToString:[NSString stringWithFormat:@"[!%@]", kind]]) {
            return kind;
        }
    }
    return nil;
}

// Drops the marker line from the quote's first paragraph (the paragraph
// itself when the marker was all it held).
static void OMStripAlertMarker(cmark_node *quote)
{
    cmark_node *paragraph = cmark_node_first_child(quote);
    if (paragraph == NULL || cmark_node_get_type(paragraph) != CMARK_NODE_PARAGRAPH) {
        return;
    }
    cmark_node *child = cmark_node_first_child(paragraph);
    while (child != NULL) {
        cmark_node *next = cmark_node_next(child);
        cmark_node_type type = cmark_node_get_type(child);
        cmark_node_free(child);
        child = next;
        if (type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK) {
            break;
        }
    }
    if (cmark_node_first_child(paragraph) == NULL) {
        cmark_node_free(paragraph);
    }
}

// GitHub's alert colours (light and dark palettes) and titles.
static NSColor *OMAlertColor(NSString *kind, OMTheme *theme)
{
    BOOL dark = [theme isDark];
    NSDictionary *light = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"#0969da", @"NOTE", @"#1a7f37", @"TIP", @"#8250df", @"IMPORTANT",
                           @"#9a6700", @"WARNING", @"#d1242f", @"CAUTION", nil];
    NSDictionary *darkColors = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"#4493f8", @"NOTE", @"#3fb950", @"TIP", @"#ab7df8", @"IMPORTANT",
                                @"#d29922", @"WARNING", @"#f85149", @"CAUTION", nil];
    NSString *hex = [(dark ? darkColors : light) objectForKey:kind];
    unsigned int value = 0;
    if (hex == nil || ![[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&value]) {
        return theme.linkColor;
    }
    return [NSColor colorWithCalibratedRed:((value >> 16) & 0xff) / 255.0
                                     green:((value >> 8) & 0xff) / 255.0
                                      blue:(value & 0xff) / 255.0
                                     alpha:1.0];
}

static void OMAppendAlertTitle(NSString *kind,
                               NSColor *color,
                               OMTheme *theme,
                               NSMutableAttributedString *output,
                               NSMutableDictionary *attributes,
                               NSUInteger quoteLevel,
                               CGFloat scale,
                               const OMRenderContext *renderContext)
{
    NSString *title = [[kind substringToIndex:1] stringByAppendingString:[[kind substringFromIndex:1] lowercaseString]];
    NSMutableDictionary *titleAttrs = [attributes mutableCopy];
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : 14.0 * scale;
    NSFont *bold = font != nil ? OMFontWithTraits(font, NSBoldFontMask) : [NSFont boldSystemFontOfSize:fontSize];
    if (bold != nil) {
        [titleAttrs setObject:bold forKey:NSFontAttributeName];
    }
    if (color != nil) {
        [titleAttrs setObject:color forKey:NSForegroundColorAttributeName];
    }
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale);
    [titleAttrs setObject:OMParagraphStyleWithIndent(indent, indent, 4.0 * scale, 0.0, 1.5, fontSize)
                   forKey:NSParagraphStyleAttributeName];
    OMAppendString(output, title, titleAttrs);
    OMAppendString(output, @"\n", titleAttrs);
    [titleAttrs release];
}

// Footnotes come last in the document (cmark-gfm moves them there, in order
// of first reference): a rule, then each note as a numbered item.
static void OMRenderFootnoteDefinition(cmark_node *node,
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
    NSUInteger number = 1;
    cmark_node *previous = cmark_node_previous(node);
    for (; previous != NULL; previous = cmark_node_previous(previous)) {
        if (cmark_node_get_type(previous) == CMARK_NODE_FOOTNOTE_DEFINITION) {
            number += 1;
        }
    }
    if (number == 1) {
        OMRenderThematicBreak(theme, output, attributes, layoutWidth);
    }
    NSMutableDictionary *listInfo = [NSMutableDictionary dictionary];
    [listInfo setObject:[NSNumber numberWithInt:CMARK_ORDERED_LIST] forKey:@"type"];
    [listInfo setObject:[NSNumber numberWithUnsignedInteger:number] forKey:@"index"];
    [listInfo setObject:[NSNumber numberWithBool:YES] forKey:@"tight"];
    [listStack addObject:listInfo];
    OMRenderListItem(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth, renderContext);
    [listStack removeLastObject];
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
    NSUInteger sourceStartLine = 0;
    BOOL hasSourceLineBounds = OMNodeLineBounds(node, &sourceStartLine, NULL);
    if (hasSourceLineBounds && OMDisplayMathLineAlreadyConsumed(sourceStartLine, renderContext)) {
        return;
    }
    if (OMTryRenderRawDisplayMathBlock(node,
                                       theme,
                                       output,
                                       attributes,
                                       listStack,
                                       scale,
                                       renderContext)) {
        return;
    }
    if (type == CMARK_NODE_BLOCK_QUOTE) {
        NSString *alertKind = OMAlertKindForBlockquote(node, renderContext);
        NSColor *alertColor = nil;
        if (alertKind != nil) {
            OMStripAlertMarker(node);
            alertColor = OMAlertColor(alertKind, theme);
            OMAppendAlertTitle(alertKind, alertColor, theme, output, attributes, quoteLevel + 1, scale, renderContext);
        }
        if (renderContext != NULL) {
            [renderContext->quoteKinds addObject:[NSNumber numberWithBool:(alertKind != nil)]];
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
                           quoteLevel + 1,
                           scale,
                           layoutWidth,
                           renderContext);
            child = cmark_node_next(child);
        }
        NSUInteger endLocation = [output length];
        if (endLocation > startLocation) {
            // The bar stops at the quote's last line, not in the gap after it.
            NSUInteger barEnd = endLocation;
            NSString *text = [output string];
            while (barEnd > startLocation + 1 && [text characterAtIndex:barEnd - 1] == '\n' &&
                   [text characterAtIndex:barEnd - 2] == '\n') {
                barEnd -= 1;
            }
            [blockquoteRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, barEnd - startLocation)]];
            if (alertColor != nil) {
                [output addAttribute:OMMarkdownRendererBlockquoteColorAttributeName
                               value:alertColor
                               range:NSMakeRange(startLocation, barEnd - startLocation)];
            }
            OMRecordBlockAnchor(node, startLocation, endLocation, renderContext);
        }
        if (renderContext != NULL) {
            [renderContext->quoteKinds removeLastObject];
        }
        return;
    }
    // Extension node types are assigned at run time, so they can't be cases.
    if (type == CMARK_NODE_TABLE) {
        OMRenderGFMTable(node, theme, output, attributes, listStack, quoteLevel, scale, layoutWidth, renderContext);
        OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
        return;
    }
    if (type == CMARK_NODE_FOOTNOTE_DEFINITION) {
        OMRenderFootnoteDefinition(node, theme, output, attributes, codeRanges, blockquoteRanges,
                                   listStack, quoteLevel, scale, layoutWidth, renderContext);
        OMRecordBlockAnchor(node, startLocation, [output length], renderContext);
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
        if (type == CMARK_NODE_STRIKETHROUGH) {
            NSMutableDictionary *struckAttrs = [attributes mutableCopy];
            [struckAttrs setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
                            forKey:NSStrikethroughStyleAttributeName];
            OMRenderInlines(child, theme, output, struckAttrs, scale, renderContext);
            [struckAttrs release];
            child = cmark_node_next(child);
            continue;
        }
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
            case CMARK_NODE_FOOTNOTE_REFERENCE: {
                // The literal is the footnote's number.
                const char *literal = cmark_node_get_literal(child);
                NSString *number = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                NSMutableDictionary *refAttrs = [attributes mutableCopy];
                NSFont *font = [attributes objectForKey:NSFontAttributeName];
                CGFloat size = font != nil ? [font pointSize] : 14.0 * scale;
                NSFont *smaller = font != nil ? [NSFont fontWithName:[font fontName] size:size * 0.72] : nil;
                if (smaller != nil) {
                    [refAttrs setObject:smaller forKey:NSFontAttributeName];
                }
                // GNUstep applies NSBaselineOffsetAttributeName upside down; superscript
                // is raised correctly on both GNUstep and macOS.
                [refAttrs setObject:[NSNumber numberWithInt:1] forKey:NSSuperscriptAttributeName];
                if (theme.linkColor != nil) {
                    [refAttrs setObject:theme.linkColor forKey:NSForegroundColorAttributeName];
                }
                OMAppendString(output, number, refAttrs);
                [refAttrs release];
                break;
            }
            case CMARK_NODE_SOFTBREAK:
                OMAppendString(output, @" ", attributes);
                break;
            case CMARK_NODE_LINEBREAK: {
                NSMutableDictionary *breakAttrs = [attributes mutableCopy];
                [breakAttrs setObject:[NSNumber numberWithBool:YES] forKey:OMHardLineBreakAttributeName];
                OMAppendString(output, @"\n", breakAttrs);
                [breakAttrs release];
                break;
            }
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
                OMApplyItalicFallbackIfNeeded(emphAttrs, font, newFont);
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
                // The link's title, else where it goes (the viewer has no status bar).
                const char *linkTitle = cmark_node_get_title(child);
                NSString *toolTip = (linkTitle != NULL && linkTitle[0] != '\0')
                    ? [NSString stringWithUTF8String:linkTitle]
                    : urlString;
                if ([toolTip length] > 0 && hasValidLinkURL) {
                    [linkAttrs setObject:toolTip forKey:NSToolTipAttributeName];
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
                        NSUInteger objectStart = [output length];
                        OMAppendAttributedSegment(output, attachment);
                        const char *imageTitle = cmark_node_get_title(child);
                        if (imageTitle != NULL && imageTitle[0] != '\0' && [output length] > objectStart) {
                            [output addAttribute:NSToolTipAttributeName
                                           value:[NSString stringWithUTF8String:imageTitle]
                                           range:NSMakeRange(objectStart, [output length] - objectStart)];
                        }
                        OMTagAppendedObject(output,
                                            objectStart,
                                            OMRenderedObjectKindImage,
                                            OMImageMarkdownForNode(child),
                                            nil);
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
