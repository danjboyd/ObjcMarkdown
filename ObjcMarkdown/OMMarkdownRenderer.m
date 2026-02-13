// ObjcMarkdown
// SPDX-License-Identifier: Apache-2.0

#import "OMMarkdownRenderer.h"
#import "OMTheme.h"

#import <dispatch/dispatch.h>

#include <cmark.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

NSString * const OMMarkdownRendererMathArtifactsDidWarmNotification = @"OMMarkdownRendererMathArtifactsDidWarmNotification";

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

static OMMathPerfStats *OMCurrentMathPerfStats = NULL;
static BOOL OMCurrentAsyncMathGenerationEnabled = NO;

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
        [style setMaximumLineHeight:lineHeight];
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

static void OMRenderInlines(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            CGFloat scale);

static void OMRenderBlocks(cmark_node *node,
                           OMTheme *theme,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *attributes,
                           NSMutableArray *codeRanges,
                           NSMutableArray *blockquoteRanges,
                           NSMutableArray *listStack,
                           NSUInteger quoteLevel,
                           CGFloat scale,
                           CGFloat layoutWidth);

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
                      int *terminationStatus)
{
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:launchPath];
    [task setArguments:arguments];

    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    [task setStandardError:errorPipe];

    BOOL launched = YES;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
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
        *terminationStatus = launched ? [task terminationStatus] : -1;
    }

    return launched && [task terminationStatus] == 0;
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
                                       CGFloat renderZoom)
{
    if (!OMMathBackendAvailable()) {
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
    BOOL texOK = OMRunTask(texExecutable, texArguments, NULL, NULL, &texStatus);
    if (OMCurrentMathPerfStats != NULL) {
        OMCurrentMathPerfStats->latexRuns += 1;
        OMCurrentMathPerfStats->latexSeconds += (OMNow() - texStart);
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
    BOOL svgOK = OMRunTask(OMDviSvgmExecutablePath(), svgArguments, &svgData, NULL, &svgStatus);
    if (OMCurrentMathPerfStats != NULL) {
        OMCurrentMathPerfStats->dvisvgmRuns += 1;
        OMCurrentMathPerfStats->dvisvgmSeconds += (OMNow() - svgStart);
    }
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];

    if (!svgOK || svgData == nil || [svgData length] == 0) {
        return nil;
    }
    return svgData;
}

static void OMScheduleAsyncMathAssetGeneration(NSString *formula,
                                               BOOL displayMath,
                                               CGFloat renderZoom)
{
    if (!OMMathBackendAvailable() || formula == nil || [formula length] == 0) {
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
            NSData *svgData = OMSVGDataForMathFormula(formulaCopy, displayMath, renderZoom);
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
                                                            BOOL displayMath)
{
    if (OMCurrentMathPerfStats != NULL) {
        OMCurrentMathPerfStats->mathRequests += 1;
    }
    if (!OMMathBackendAvailable() || formula == nil || [formula length] == 0) {
        if (OMCurrentMathPerfStats != NULL) {
            OMCurrentMathPerfStats->mathFailures += 1;
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
        if (OMCurrentMathPerfStats != NULL) {
            OMCurrentMathPerfStats->mathCacheHits += 1;
        }
        return cached;
    }
    if (OMCurrentMathPerfStats != NULL) {
        OMCurrentMathPerfStats->mathCacheMisses += 1;
    }

    NSTimeInterval mathStart = OMNow();
    NSString *assetKey = OMMathAssetCacheKey(formula, displayMath, renderZoom);
    NSImage *baseImage = [OMMathBaseImageCache() objectForKey:assetKey];
    NSData *svgData = nil;
    CGFloat imageRenderZoom = renderZoom;
    BOOL usedFallbackImage = NO;
    if (baseImage != nil) {
        if (OMCurrentMathPerfStats != NULL) {
            OMCurrentMathPerfStats->mathAssetCacheHits += 1;
        }
        OMRecordBestAvailableMathImage(formula, displayMath, renderZoom, baseImage);
    } else {
        svgData = [OMMathBaseSVGDataCache() objectForKey:assetKey];
        if (svgData != nil) {
            if (OMCurrentMathPerfStats != NULL) {
                OMCurrentMathPerfStats->mathAssetCacheHits += 1;
            }
        } else {
            if (OMCurrentMathPerfStats != NULL) {
                OMCurrentMathPerfStats->mathAssetCacheMisses += 1;
            }

            if (OMCurrentAsyncMathGenerationEnabled) {
                OMScheduleAsyncMathAssetGeneration(formula, displayMath, renderZoom);
                CGFloat fallbackRenderZoom = 0.0;
                NSImage *fallbackImage = OMBestAvailableMathImage(formula, displayMath, &fallbackRenderZoom);
                if (fallbackImage != nil) {
                    baseImage = fallbackImage;
                    usedFallbackImage = YES;
                    imageRenderZoom = fallbackRenderZoom > 0.0 ? fallbackRenderZoom : oversample;
                    if (OMCurrentMathPerfStats != NULL) {
                        OMCurrentMathPerfStats->mathAssetCacheHits += 1;
                    }
                } else {
                    return nil;
                }
            }

            if (!usedFallbackImage) {
                svgData = OMSVGDataForMathFormula(formula, displayMath, renderZoom);
                if (svgData == nil) {
                    if (OMCurrentMathPerfStats != NULL) {
                        OMCurrentMathPerfStats->mathFailures += 1;
                        OMCurrentMathPerfStats->mathTotalSeconds += (OMNow() - mathStart);
                    }
                    return nil;
                }
                [OMMathBaseSVGDataCache() setObject:svgData forKey:assetKey];
            }
        }

        if (baseImage == nil) {
            NSTimeInterval decodeStart = OMNow();
            NSImage *decodedImage = [[[NSImage alloc] initWithData:svgData] autorelease];
            if (OMCurrentMathPerfStats != NULL) {
                OMCurrentMathPerfStats->svgDecodeSeconds += (OMNow() - decodeStart);
            }
            if (decodedImage == nil) {
                if (OMCurrentMathPerfStats != NULL) {
                    OMCurrentMathPerfStats->mathFailures += 1;
                    OMCurrentMathPerfStats->mathTotalSeconds += (OMNow() - mathStart);
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
        if (OMCurrentMathPerfStats != NULL) {
            OMCurrentMathPerfStats->mathFailures += 1;
            OMCurrentMathPerfStats->mathTotalSeconds += (OMNow() - mathStart);
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
    if (OMCurrentMathPerfStats != NULL) {
        OMCurrentMathPerfStats->mathRendered += 1;
        OMCurrentMathPerfStats->mathTotalSeconds += (OMNow() - mathStart);
    }
    return immutable;
}

static void OMAppendTextWithMathSpans(NSString *text,
                                      OMTheme *theme,
                                      NSMutableAttributedString *output,
                                      NSMutableDictionary *attributes,
                                      CGFloat scale)
{
    if (text == nil || [text length] == 0) {
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
                        NSAttributedString *attachment = OMMathAttachmentAttributedString(formula, theme, attributes, scale, YES);
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
                            NSAttributedString *attachment = OMMathAttachmentAttributedString(formula, theme, attributes, scale, NO);
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
                                                    BOOL *didRender)
{
    if (didRender != NULL) {
        *didRender = NO;
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

                NSAttributedString *attachment = OMMathAttachmentAttributedString(normalized, theme, attributes, scale, YES);
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
@end

@implementation OMMarkdownRenderer

@synthesize zoomScale = _zoomScale;
@synthesize layoutWidth = _layoutWidth;
@synthesize asynchronousMathGenerationEnabled = _asynchronousMathGenerationEnabled;
@synthesize codeBlockRanges = _codeBlockRanges;
@synthesize blockquoteRanges = _blockquoteRanges;

- (instancetype)init
{
    return [self initWithTheme:[OMTheme defaultTheme]];
}

- (instancetype)initWithTheme:(OMTheme *)theme
{
    self = [super init];
    if (self) {
        if (theme == nil) {
            theme = [OMTheme defaultTheme];
        }
        _theme = [theme retain];
        _zoomScale = 1.0;
        _layoutWidth = 0.0;
        _asynchronousMathGenerationEnabled = NO;
    }
    return self;
}

- (void)dealloc
{
    [_codeBlockRanges release];
    [_blockquoteRanges release];
    [_theme release];
    [super dealloc];
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
    NSTimeInterval parseStart = perfLogging ? OMNow() : 0.0;
    cmark_node *document = cmark_parse_document(bytes, length, CMARK_OPT_DEFAULT);
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
    OMMathPerfStats stats = {0};
    OMMathPerfStats *previousStats = OMCurrentMathPerfStats;
    BOOL previousAsyncMathEnabled = OMCurrentAsyncMathGenerationEnabled;
    OMCurrentAsyncMathGenerationEnabled = self.asynchronousMathGenerationEnabled;
    OMCurrentMathPerfStats = &stats;
    NSTimeInterval renderStart = perfLogging ? OMNow() : 0.0;
    OMRenderBlocks(document, self.theme, output, attributes, codeRanges, blockquoteRanges, listStack, 0, scale, self.layoutWidth);
    NSTimeInterval renderMs = perfLogging ? ((OMNow() - renderStart) * 1000.0) : 0.0;
    OMCurrentAsyncMathGenerationEnabled = previousAsyncMathEnabled;
    OMCurrentMathPerfStats = previousStats;
    [self setCodeBlockRanges:codeRanges];
    [self setBlockquoteRanges:blockquoteRanges];
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
                              CGFloat scale)
{
    NSMutableDictionary *paraAttrs = [attributes mutableCopy];
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale);
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat fontSize = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 16.0 * scale);
    NSParagraphStyle *style = OMParagraphStyleWithIndent(indent, indent, 12.0 * scale, 0.0, 1.725, fontSize);
    [paraAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMRenderInlines(node, theme, output, paraAttrs, scale);
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
                            CGFloat layoutWidth)
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

    OMRenderInlines(node, theme, output, headingAttrs, scale);
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
                              NSMutableArray *codeRanges)
{
    const char *literal = cmark_node_get_literal(node);
    NSString *code = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";

    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    CGFloat size = font != nil ? [font pointSize] : (theme.baseFont != nil ? [theme.baseFont pointSize] * scale : 14.0 * scale);
    NSDictionary *codeAttrs = [theme codeAttributesForSize:size];

    NSMutableDictionary *blockAttrs = [attributes mutableCopy];
    [blockAttrs addEntriesFromDictionary:codeAttrs];

    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + 20.0 * scale;
    CGFloat padding = 16.0 * scale;
    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent + padding,
                                                                indent + padding,
                                                                14.0 * scale,
                                                                0.0,
                                                                1.5,
                                                                size);
    [style setParagraphSpacingBefore:10.0 * scale];
    [style setTailIndent:-padding];
    [blockAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    NSUInteger startLocation = [output length];
    OMAppendString(output, code, blockAttrs);
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
                         CGFloat layoutWidth)
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
        OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
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
                             CGFloat layoutWidth)
{
    NSUInteger startLocation = [output length];
    NSString *prefix = OMListPrefix(listStack);
    OMAppendString(output, prefix, attributes);

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
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
                           CGFloat layoutWidth)
{
    cmark_node_type type = cmark_node_get_type(node);
    if (type == CMARK_NODE_BLOCK_QUOTE) {
        NSUInteger startLocation = [output length];
        cmark_node *child = cmark_node_first_child(node);
        while (child != NULL) {
            OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel + 1, scale, layoutWidth);
            child = cmark_node_next(child);
        }
        NSUInteger endLocation = [output length];
        if (endLocation > startLocation) {
            [blockquoteRanges addObject:[NSValue valueWithRange:NSMakeRange(startLocation, endLocation - startLocation)]];
        }
        return;
    }
    switch (type) {
        case CMARK_NODE_DOCUMENT:
            break;
        case CMARK_NODE_PARAGRAPH:
            OMRenderParagraph(node, theme, output, attributes, listStack, quoteLevel, scale);
            return;
        case CMARK_NODE_HEADING:
            OMRenderHeading(node, theme, output, attributes, quoteLevel, scale, layoutWidth);
            return;
        case CMARK_NODE_CODE_BLOCK:
            OMRenderCodeBlock(node, theme, output, attributes, quoteLevel, scale, codeRanges);
            return;
        case CMARK_NODE_THEMATIC_BREAK:
            OMRenderThematicBreak(theme, output, attributes, layoutWidth);
            return;
        case CMARK_NODE_BLOCK_QUOTE:
            quoteLevel += 1;
            break;
        case CMARK_NODE_LIST:
            OMRenderList(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
            return;
        case CMARK_NODE_ITEM:
            OMRenderListItem(node, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
            return;
        case CMARK_NODE_HTML_BLOCK:
        case CMARK_NODE_CUSTOM_BLOCK:
            return;
        default:
            break;
    }

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMRenderBlocks(child, theme, output, attributes, codeRanges, blockquoteRanges, listStack, quoteLevel, scale, layoutWidth);
        child = cmark_node_next(child);
    }
}

static void OMRenderInlines(cmark_node *node,
                            OMTheme *theme,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            CGFloat scale)
{
    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        cmark_node_type type = cmark_node_get_type(child);
        switch (type) {
            case CMARK_NODE_TEXT: {
                BOOL renderedDisplayMath = NO;
                cmark_node *nextAfterDisplayMath = OMTryAppendMultiNodeDisplayMath(child, theme, output, attributes, scale, &renderedDisplayMath);
                if (renderedDisplayMath) {
                    child = nextAfterDisplayMath;
                    continue;
                }
                const char *literal = cmark_node_get_literal(child);
                NSString *text = literal != NULL ? [NSString stringWithUTF8String:literal] : @"";
                OMAppendTextWithMathSpans(text, theme, output, attributes, scale);
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
                OMRenderInlines(child, theme, output, emphAttrs, scale);
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
                OMRenderInlines(child, theme, output, strongAttrs, scale);
                [strongAttrs release];
                break;
            }
            case CMARK_NODE_LINK: {
                const char *url = cmark_node_get_url(child);
                NSString *urlString = url != NULL ? [NSString stringWithUTF8String:url] : @"";
                NSMutableDictionary *linkAttrs = [attributes mutableCopy];
                if ([urlString length] > 0) {
                    NSURL *linkURL = [NSURL URLWithString:urlString];
                    if (linkURL == nil) {
                        linkURL = [NSURL fileURLWithPath:urlString];
                    }
                    if (linkURL != nil) {
                        [linkAttrs setObject:linkURL forKey:NSLinkAttributeName];
                    }
                }
                if (theme.linkColor != nil) {
                    [linkAttrs setObject:theme.linkColor forKey:NSForegroundColorAttributeName];
                }
                OMRenderInlines(child, theme, output, linkAttrs, scale);
                [linkAttrs release];
                break;
            }
            case CMARK_NODE_IMAGE: {
                OMAppendString(output, @"[image]", attributes);
                break;
            }
            case CMARK_NODE_HTML_INLINE:
            case CMARK_NODE_CUSTOM_INLINE:
                break;
            default:
                OMRenderInlines(child, theme, output, attributes, scale);
                break;
        }
        child = cmark_node_next(child);
    }
}

@end
