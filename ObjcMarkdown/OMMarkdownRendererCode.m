// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Code block syntax highlighting: language detection and regex colouring.

#import "OMMarkdownRendererInternal.h"

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

BOOL OMColorRGBA(NSColor *color, CGFloat *red, CGFloat *green, CGFloat *blue, CGFloat *alpha)
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

NSString *OMPrimaryFenceToken(cmark_node *codeBlockNode)
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

void OMApplyCodeSyntaxHighlighting(cmark_node *codeBlockNode,
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
