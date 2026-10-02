// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Math: inline and display spans, the LaTeX toolchain, cached formula images.

#import "OMMarkdownRendererInternal.h"

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
NSMutableDictionary *OMMathFormulaGenerations(void)
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

BOOL OMDisplayMathLineAlreadyConsumed(NSUInteger lineNumber,
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

BOOL OMCharacterIsWhitespaceOrNewline(unichar ch)
{
    static NSCharacterSet *whitespaceSet = nil;
    if (whitespaceSet == nil) {
        whitespaceSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
    }
    return [whitespaceSet characterIsMember:ch];
}

BOOL OMCharacterIsDigit(unichar ch)
{
    return ch >= '0' && ch <= '9';
}

BOOL OMDollarIsEscaped(NSString *text, NSUInteger location)
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

NSDictionary *OMMathAttributes(OMTheme *theme,
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

NSString *OMReadableMathFallbackString(NSString *formula)
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

NSString *OMExecutablePathNamed(NSString *name)
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

NSString *OMLaTeXExecutablePath(void)
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = [OMExecutablePathNamed(@"latex") retain];
    });
    return path;
}

NSString *OMPlainTexExecutablePath(void)
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = [OMExecutablePathNamed(@"tex") retain];
    });
    return path;
}

NSString *OMDviPngExecutablePath(void)
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

NSAttributedString *OMMathAttachmentAttributedString(NSString *formula,
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
void OMPrepareRawMathSources(cmark_node *node, const OMRenderContext *renderContext)
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
NSString *OMRawMathFormula(NSString *formula, BOOL display, const OMRenderContext *renderContext)
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

void OMAppendDisplayMathFormula(NSString *formula,
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
BOOL OMTryRenderRawDisplayMathBlock(cmark_node *node,
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

cmark_node *OMTryAppendMultiNodeDisplayMath(cmark_node *startNode,
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
