// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import "OMMarkdownRenderer.h"

static NSArray *OMDTestExecutableCandidateNames(NSString *name)
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

static NSString *OMDTestExecutablePathInDirectory(NSString *directory,
                                                  NSString *name,
                                                  NSFileManager *fileManager)
{
    if (directory == nil || [directory length] == 0 || name == nil || [name length] == 0) {
        return nil;
    }

    for (NSString *candidateName in OMDTestExecutableCandidateNames(name)) {
        NSString *candidate = [directory stringByAppendingPathComponent:candidateName];
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

static NSString *OMDTestExecutablePathNamed(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([name rangeOfString:@"/"].location != NSNotFound ||
        [name rangeOfString:@"\\"].location != NSNotFound) {
        for (NSString *candidateName in OMDTestExecutableCandidateNames(name)) {
            if ([fileManager isExecutableFileAtPath:candidateName]) {
                return candidateName;
            }
        }
    }

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
            NSString *resolved = OMDTestExecutablePathInDirectory(searchPath, name, fileManager);
            if (resolved != nil) {
                return resolved;
            }
        }
    }

    NSString *fallback = OMDTestExecutablePathInDirectory(@"/usr/bin", name, fileManager);
    if (fallback != nil) {
        return fallback;
    }
    return nil;
}

static BOOL OMDMathToolchainAvailable(void)
{
    return OMDTestExecutablePathNamed(@"dvisvgm") != nil &&
           (OMDTestExecutablePathNamed(@"latex") != nil ||
            OMDTestExecutablePathNamed(@"tex") != nil);
}

@interface OMMarkdownRendererTests : XCTestCase
@end

@implementation OMMarkdownRendererTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (NSString *)temporaryImagePathWithExtension:(NSString *)extension
{
    NSString *directory = NSTemporaryDirectory();
    if (directory == nil || [directory length] == 0) {
        directory = @"/tmp";
    }
    NSString *fileName = [NSString stringWithFormat:@"objcmarkdown-image-%@.%@",
                          [[NSProcessInfo processInfo] globallyUniqueString],
                          extension];
    return [directory stringByAppendingPathComponent:fileName];
}

- (NSString *)writeTemporaryImage
{
    NSString *path = [self temporaryImagePathWithExtension:@"png"];
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(8.0, 8.0)] autorelease];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.15 green:0.45 blue:0.85 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 8.0, 8.0));
    [image unlockFocus];

    NSData *tiff = [image TIFFRepresentation];
    NSBitmapImageRep *bitmap = tiff != nil ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
    NSData *png = bitmap != nil ? [bitmap representationUsingType:NSPNGFileType
                                                       properties:[NSDictionary dictionary]] : nil;
    NSData *data = png != nil ? png : tiff;
    if (data != nil) {
        [data writeToFile:path atomically:YES];
    }
    return path;
}

- (void)removeFileIfPresent:(NSString *)path
{
    if (path == nil) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (NSString *)uniqueRemoteImageURLString
{
    return [NSString stringWithFormat:@"https://example.invalid/%@.png",
            [[NSProcessInfo processInfo] globallyUniqueString]];
}

- (NSURL *)linkURLInRenderedString:(NSAttributedString *)rendered
                    forVisibleText:(NSString *)visibleText
{
    if (rendered == nil || visibleText == nil || [visibleText length] == 0) {
        return nil;
    }

    NSString *text = [rendered string];
    NSRange range = [text rangeOfString:visibleText];
    if (range.location == NSNotFound) {
        return nil;
    }
    NSDictionary *attrs = [rendered attributesAtIndex:range.location effectiveRange:NULL];
    id linkValue = [attrs objectForKey:NSLinkAttributeName];
    if ([linkValue isKindOfClass:[NSURL class]]) {
        return (NSURL *)linkValue;
    }
    return nil;
}

- (NSUInteger)attachmentCharacterCountInRenderedString:(NSAttributedString *)rendered
{
    if (rendered == nil) {
        return 0;
    }
    NSString *text = [rendered string];
    NSUInteger length = [text length];
    NSUInteger count = 0;
    NSUInteger index = 0;
    for (; index < length; index++) {
        if ([text characterAtIndex:index] == NSAttachmentCharacter) {
            count += 1;
        }
    }
    return count;
}

- (NSTextAttachment *)firstAttachmentInRenderedString:(NSAttributedString *)rendered
{
    if (rendered == nil || [rendered length] == 0) {
        return nil;
    }

    NSString *text = [rendered string];
    NSUInteger index = 0;
    for (; index < [text length]; index++) {
        if ([text characterAtIndex:index] != NSAttachmentCharacter) {
            continue;
        }
        NSDictionary *attrs = [rendered attributesAtIndex:index effectiveRange:NULL];
        NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];
        if ([attachment isKindOfClass:[NSTextAttachment class]]) {
            return attachment;
        }
    }
    return nil;
}

- (void)testBasicMarkdownRenders
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"# Title\n\nSome *italic* and **bold** text.";

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);
    XCTAssertTrue([rendered length] > 0);
}

- (void)testBaseThemeAttributesApplied
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"Plain text";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);
    XCTAssertTrue([rendered length] > 0);

    NSDictionary *attrs = [rendered attributesAtIndex:0 effectiveRange:NULL];
    NSFont *font = [attrs objectForKey:NSFontAttributeName];
    NSColor *color = [attrs objectForKey:NSForegroundColorAttributeName];

    XCTAssertNotNil(font);
    XCTAssertNotNil(color);
}

- (void)testStrikethroughAppliesInlineStyle
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Keep ~~remove~~ text."];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange range = [text rangeOfString:@"remove"];
    XCTAssertTrue(range.location != NSNotFound);
    if (range.location == NSNotFound) {
        return;
    }

    NSDictionary *attrs = [rendered attributesAtIndex:range.location effectiveRange:NULL];
    NSNumber *style = [attrs objectForKey:NSStrikethroughStyleAttributeName];
    XCTAssertNotNil(style);
    XCTAssertEqual([style integerValue], (NSInteger)NSUnderlineStyleSingle);
}

- (void)testItalicAppliesFontOrObliquenessStyle
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Some *italic* text."];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange range = [text rangeOfString:@"italic"];
    XCTAssertTrue(range.location != NSNotFound);
    if (range.location == NSNotFound) {
        return;
    }

    NSDictionary *attrs = [rendered attributesAtIndex:range.location effectiveRange:NULL];
    NSNumber *obliqueness = [attrs objectForKey:NSObliquenessAttributeName];
    NSFont *font = [attrs objectForKey:NSFontAttributeName];
    BOOL hasVisibleItalicStyle = (obliqueness != nil && [obliqueness doubleValue] != 0.0);
    if (!hasVisibleItalicStyle && font != nil) {
        NSFontManager *manager = [NSFontManager sharedFontManager];
        hasVisibleItalicStyle = (([manager traitsOfFont:font] & NSItalicFontMask) != 0);
    }
    XCTAssertTrue(hasVisibleItalicStyle);
}

- (void)testPipeTableRendersAsStructuredMultilineContent
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"| Name | Value |\n| ---- | ----: |\n| alpha | 1 |\n| beta | 23 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    XCTAssertTrue([rendered containsAttachments]);
    XCTAssertEqual([self attachmentCharacterCountInRenderedString:rendered], (NSUInteger)1);
}

- (void)testPipeTableRendersAlignedGridRows
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:1200.0];
    NSString *markdown = @"| Name | Value |\n| ---- | ----: |\n| alpha | 1 |\n| beta | 23 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment);
    if (attachment != nil) {
        id cell = [attachment attachmentCell];
        XCTAssertNotNil(cell);
        if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
            NSSize size = [cell cellSize];
            XCTAssertTrue(size.width > 80.0);
            XCTAssertTrue(size.height > 40.0);
        }
    }
}

- (void)testPipeTableCellFontIsReadable
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:1200.0];
    NSString *markdown = @"Paragraph.\n\n| Name | Value |\n| ---- | ----: |\n| alpha | 1 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange paragraphRange = [text rangeOfString:@"Paragraph"];
    XCTAssertTrue(paragraphRange.location != NSNotFound);
    if (paragraphRange.location == NSNotFound) {
        return;
    }

    NSDictionary *paragraphAttrs = [rendered attributesAtIndex:paragraphRange.location effectiveRange:NULL];
    NSFont *paragraphFont = [paragraphAttrs objectForKey:NSFontAttributeName];
    XCTAssertNotNil(paragraphFont);
    XCTAssertTrue([rendered containsAttachments]);

    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment);
    if (attachment != nil) {
        id cell = [attachment attachmentCell];
        if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
            NSSize size = [cell cellSize];
            XCTAssertTrue(size.width > 120.0);
            XCTAssertTrue(size.height > [paragraphFont pointSize]);
        }
    }
}

- (void)testPipeTableWrapsToNarrowPreviewWidth
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:200.0];
    NSString *markdown = @"| Area | Notes |\n| --- | --- |\n| Parsing | Handles standard pipe table delimiter row and alignment markers. |\n| Rendering | Output should stay column-aligned and legible on dark theme. |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([rendered containsAttachments]);
    XCTAssertEqual([self attachmentCharacterCountInRenderedString:rendered], (NSUInteger)1);
    XCTAssertTrue([text rangeOfString:@"Row 1"].location == NSNotFound);

    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment);
    if (attachment != nil) {
        id cell = [attachment attachmentCell];
        if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
            NSSize size = [cell cellSize];
            XCTAssertTrue(size.width <= 200.0);
            XCTAssertTrue(size.height > 90.0);
        }
    }
}

- (void)testPipeTableAllowsHorizontalOverflowInsteadOfStackedFallback
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:220.0];
    [renderer setAllowTableHorizontalOverflow:YES];
    NSString *markdown = @"| Area | Notes | Status |\n| :--- | :---- | ----: |\n| Parsing | Handles standard pipe table delimiter row and alignment markers. | 100 |\n| Rendering | Output should stay column-aligned and legible on dark theme. | 95 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([rendered containsAttachments]);
    XCTAssertTrue([text rangeOfString:@"Row 1"].location == NSNotFound);

    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment);
    if (attachment != nil) {
        id cell = [attachment attachmentCell];
        if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
            NSSize size = [cell cellSize];
            XCTAssertTrue(size.width > 220.0);
        }
    }
}

- (void)testPipeTableKeepsGridLayoutAtComfortablePreviewWidth
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:900.0];
    NSString *markdown = @"| Area | Notes | Status |\n| :--- | :---- | ----: |\n| Parsing | Handles delimiter rows. | 100 |\n| Rendering | Should remain structured. | 95 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([rendered containsAttachments]);
    XCTAssertEqual([self attachmentCharacterCountInRenderedString:rendered], (NSUInteger)1);
    XCTAssertTrue([text rangeOfString:@"Row 1"].location == NSNotFound);
}

- (void)testPipeTableWrapsLouisianaStrategyStyleProseRows
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:900.0];
    NSString *markdown = @"| category | assessment |\n|---|---|\n| Strengths | Louisiana has public official sources that may expose unit, order, notice, owner-address, well, and production context. Invito already has underwriting discipline, Oklahoma Phase I process patterns, and a state-specific research framework. The strategy aligns with a differentiated non-operated asset pipeline rather than generic leasing. |\n| Threats | Legal, title, and reputational risk are material if Invito contacts owners without enough evidence or if owner rights are misunderstood. Competitors, operators, or brokers may move faster once matters are public. Packet gaps, timing delays, and title ambiguity could erase the timing edge. |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);
    XCTAssertTrue([rendered containsAttachments]);

    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment);
    if (attachment != nil) {
        id cell = [attachment attachmentCell];
        if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
            NSSize size = [cell cellSize];
            XCTAssertTrue(size.width <= 900.0);
            XCTAssertTrue(size.height > 120.0);
        }
    }
}

- (void)testPipeTableCellInlineLinkRendersAsLinkAttribute
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:1200.0];
    NSString *markdown = @"| Label | Link |\n| --- | --- |\n| Repo | [ObjcMarkdown](https://github.com/) |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment);
    if (attachment != nil) {
        id cell = [attachment attachmentCell];
        XCTAssertNotNil(cell);
    }
}

- (void)testInlineMathDollarsAreStyled
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"Inline math: $a^2+b^2=c^2$.";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"$a^2+b^2=c^2$"].location == NSNotFound);

    if ([rendered containsAttachments]) {
        NSString *attachmentMarker = [NSString stringWithCharacters:(unichar[]){NSAttachmentCharacter} length:1];
        NSRange attachmentRange = [text rangeOfString:attachmentMarker];
        XCTAssertTrue(attachmentRange.location != NSNotFound);
        if (attachmentRange.location != NSNotFound) {
            NSDictionary *attrs = [rendered attributesAtIndex:attachmentRange.location effectiveRange:NULL];
            NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];
            XCTAssertNotNil(attachment);
            if (attachment != nil) {
                id cell = [attachment attachmentCell];
                if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
                    NSSize cellSize = [cell cellSize];
                    XCTAssertTrue(cellSize.width > 0.0);
                    XCTAssertTrue(cellSize.height > 0.0);
                }
            }
        }
    } else {
        NSRange formulaRange = [text rangeOfString:@"a^2+b^2=c^2"];
        XCTAssertTrue(formulaRange.location != NSNotFound);
        if (formulaRange.location != NSNotFound) {
            NSDictionary *formulaAttrs = [rendered attributesAtIndex:formulaRange.location effectiveRange:NULL];
            NSColor *background = [formulaAttrs objectForKey:NSBackgroundColorAttributeName];
            XCTAssertNotNil(background);
        }
    }
}

- (void)testDisplayMathDollarsAreStyled
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"$$\\int_0^1 x^2 dx$$";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"$$"].location == NSNotFound);

    if ([rendered containsAttachments]) {
        NSString *attachmentMarker = [NSString stringWithCharacters:(unichar[]){NSAttachmentCharacter} length:1];
        NSRange attachmentRange = [text rangeOfString:attachmentMarker];
        XCTAssertTrue(attachmentRange.location != NSNotFound);
        if (attachmentRange.location != NSNotFound) {
            NSDictionary *attrs = [rendered attributesAtIndex:attachmentRange.location effectiveRange:NULL];
            NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];
            XCTAssertNotNil(attachment);
            if (attachment != nil) {
                id cell = [attachment attachmentCell];
                if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
                    NSSize cellSize = [cell cellSize];
                    XCTAssertTrue(cellSize.width > 0.0);
                    XCTAssertTrue(cellSize.height > 0.0);
                }
            }
        }
    } else {
        XCTAssertTrue([text rangeOfString:@"\\int_0^1 x^2 dx"].location == NSNotFound);
        NSRange formulaRange = [text rangeOfString:@"\u222b_0^1 x^2 dx"];
        XCTAssertTrue(formulaRange.location != NSNotFound);
        if (formulaRange.location != NSNotFound) {
            NSDictionary *formulaAttrs = [rendered attributesAtIndex:formulaRange.location effectiveRange:NULL];
            NSColor *background = [formulaAttrs objectForKey:NSBackgroundColorAttributeName];
            XCTAssertNotNil(background);
        }
    }
}

- (void)testCurrencyTextIsNotParsedAsMath
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"Price is $5 and tip is $2.";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"$5 and tip is $2"].location != NSNotFound);
}

- (void)testDisplayMathAcrossLinesIsStyled
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"$$\n\\int_0^1 x^2 dx\n$$";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"$$"].location == NSNotFound);

    if ([rendered containsAttachments]) {
        NSString *attachmentMarker = [NSString stringWithCharacters:(unichar[]){NSAttachmentCharacter} length:1];
        NSRange attachmentRange = [text rangeOfString:attachmentMarker];
        XCTAssertTrue(attachmentRange.location != NSNotFound);
        if (attachmentRange.location != NSNotFound) {
            NSDictionary *attrs = [rendered attributesAtIndex:attachmentRange.location effectiveRange:NULL];
            NSTextAttachment *attachment = [attrs objectForKey:NSAttachmentAttributeName];
            XCTAssertNotNil(attachment);
            if (attachment != nil) {
                id cell = [attachment attachmentCell];
                if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
                    NSSize cellSize = [cell cellSize];
                    XCTAssertTrue(cellSize.width > 0.0);
                    XCTAssertTrue(cellSize.height > 0.0);
                }
            }
        }
    } else {
        XCTAssertTrue([text rangeOfString:@"\\int_0^1 x^2 dx"].location == NSNotFound);
        NSRange formulaRange = [text rangeOfString:@"\u222b_0^1 x^2 dx"];
        XCTAssertTrue(formulaRange.location != NSNotFound);
        if (formulaRange.location != NSNotFound) {
            NSDictionary *formulaAttrs = [rendered attributesAtIndex:formulaRange.location effectiveRange:NULL];
            NSColor *background = [formulaAttrs objectForKey:NSBackgroundColorAttributeName];
            XCTAssertNotNil(background);
        }
    }
}

- (void)testDisplayMathCasesBlockRendersWithExternalTools
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }

    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    NSString *markdown = @"$$\nD_{nom,yr} =\n\\begin{cases}\n-\\ln(1 - D_e), & b \\approx 0 \\\\\n\\dfrac{(1 - D_e)^{-b} - 1}{b}, & \\text{otherwise}\n\\end{cases}\n$$";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([rendered containsAttachments]);
    XCTAssertTrue([text rangeOfString:@"\\begin{cases}"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\text{otherwise}"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"D_{nom,yr} ="].location == NSNotFound);
}

- (void)testDisplayMathBlockSurvivesSetextHeadingInterpretation
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }

    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    NSString *markdown = @"$$\nV_{gas}(m) =\n\\frac{Q_i}{a_i (b - 1)}\n\\left(\n(1 + b a_i (m+1))^{\\frac{b-1}{b}}\n-\n(1 + b a_i m)^{\\frac{b-1}{b}}\n\\right)\n$$";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([rendered containsAttachments]);
    XCTAssertTrue([text rangeOfString:@"$$"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"V_{gas}(m) ="].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\frac{Q_i}{a_i (b - 1)}"].location == NSNotFound);
}

- (void)testDisplayMathBlockSurvivesInlineEmphasisParsing
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }

    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    NSString *markdown = @"$$\nV_{tail} =\n\\int_{t_0}^{t_1} q^* e^{-a_{lim}\\tau}\\,d\\tau\n=\n\\begin{cases}\nq^*(t_1 - t_0), & a_{lim} \\approx 0 \\\\\n-\\dfrac{q^*}{a_{lim}}\\left(e^{-a_{lim} t_1} - e^{-a_{lim} t_0}\\right), & \\text{otherwise}\n\\end{cases}\n$$";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([rendered containsAttachments]);
    XCTAssertTrue([text rangeOfString:@"$$"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"V_{tail} ="].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\begin{cases}"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"q^*"].location == NSNotFound);
}

- (void)testInlineHTMLIsRenderedAsText
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"Before <span class=\"hot\">inline</span> after.";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"<span class=\"hot\">inline</span>"].location != NSNotFound);
}

- (void)testBlockHTMLIsRenderedAsText
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"<div>Block HTML</div>\n\nTail.";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"<div>Block HTML</div>"].location != NSNotFound);
}

- (void)testImageNodeRendersAttachmentOrDescriptiveFallback
{
    NSString *path = [self writeTemporaryImage];
    NSString *markdown = [NSString stringWithFormat:@"Image: ![tiny-square](%@)", path];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:420.0];

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    if ([rendered containsAttachments]) {
        NSString *attachmentMarker = [NSString stringWithCharacters:(unichar[]){NSAttachmentCharacter} length:1];
        NSRange attachmentRange = [text rangeOfString:attachmentMarker];
        XCTAssertTrue(attachmentRange.location != NSNotFound);
    } else {
        XCTAssertTrue([text rangeOfString:@"[image: tiny-square]"].location != NSNotFound);
    }
    XCTAssertTrue([text rangeOfString:@"[image]"].location == NSNotFound);
    [self removeFileIfPresent:path];
}

- (void)testMathPolicyDisabledPreservesDollarSyntax
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyDisabled];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];

    NSString *markdown = @"Inline math stays literal: $a+b=c$.";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);
    XCTAssertTrue([[rendered string] rangeOfString:@"$a+b=c$"].location != NSNotFound);
}

- (void)testStyledMathFallbackNormalizesCommonTeXCommands
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];

    NSString *markdown = @"Inline math: $\\Delta = \\frac{P(A \\cap B)}{P(B)}$, $\\alpha + \\beta$, $\\sqrt{2}$, and $P(A \\mid B)$.";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"\\Delta"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\frac"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\cap"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\alpha"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\beta"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\sqrt"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\\mid"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\u0394 = (P(A \u2229 B))/(P(B))"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\u03b1 + \u03b2"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\u221a(2)"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"P(A | B)"].location != NSNotFound);
}

- (void)testHTMLPolicyIgnoreDropsInlineAndBlockHTML
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setInlineHTMLPolicy:OMMarkdownHTMLPolicyIgnore];
    [options setBlockHTMLPolicy:OMMarkdownHTMLPolicyIgnore];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];

    NSString *markdown = @"Before <span>inline</span> after.\n\n<div>Block</div>\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"<span>"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"<div>Block</div>"].location == NSNotFound);
}

- (void)testRelativeLinkResolvesAgainstBaseURL
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    NSURL *baseURL = [NSURL fileURLWithPath:@"/tmp/objcmarkdown-link-base" isDirectory:YES];
    [options setBaseURL:baseURL];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Open [notes](notes.md)."];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange notesRange = [text rangeOfString:@"notes"];
    XCTAssertTrue(notesRange.location != NSNotFound);
    if (notesRange.location != NSNotFound) {
        NSDictionary *attrs = [rendered attributesAtIndex:notesRange.location effectiveRange:NULL];
        NSURL *link = [attrs objectForKey:NSLinkAttributeName];
        XCTAssertNotNil(link);
        if (link != nil) {
            XCTAssertTrue([[link absoluteString] hasSuffix:@"/tmp/objcmarkdown-link-base/notes.md"]);
        }
    }
}

- (void)testDisallowedLinkSchemeDoesNotSetLinkAttribute
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Blocked [script](javascript:alert(1))."];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange range = [text rangeOfString:@"script"];
    XCTAssertTrue(range.location != NSNotFound);
    if (range.location != NSNotFound) {
        NSDictionary *attrs = [rendered attributesAtIndex:range.location effectiveRange:NULL];
        id link = [attrs objectForKey:NSLinkAttributeName];
        XCTAssertNil(link);
    }
}

- (void)testAllowedMailtoLinkRetainsLinkAttribute
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Email [me](mailto:test@example.com)."];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange range = [text rangeOfString:@"me"];
    XCTAssertTrue(range.location != NSNotFound);
    if (range.location != NSNotFound) {
        NSDictionary *attrs = [rendered attributesAtIndex:range.location effectiveRange:NULL];
        NSURL *link = [attrs objectForKey:NSLinkAttributeName];
        XCTAssertNotNil(link);
        if (link != nil) {
            XCTAssertEqualObjects([[link scheme] lowercaseString], @"mailto");
        }
    }
}

- (void)testRemoteImageFirstPassUsesFallbackWithoutBlockingRender
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setAllowRemoteImages:YES];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    [renderer setLayoutWidth:420.0];
    NSString *remoteURL = [self uniqueRemoteImageURLString];
    NSString *markdown = [NSString stringWithFormat:@"Remote ![remote-alt](%@)", remoteURL];

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);
    XCTAssertFalse([rendered containsAttachments]);
    XCTAssertTrue([[rendered string] rangeOfString:@"[image: remote-alt]"].location != NSNotFound);
}

- (void)testBlockAnchorsExposeSourceLineMapping
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"# Title\n\nalpha\n\nalpha\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange firstAlpha = [text rangeOfString:@"alpha"];
    XCTAssertTrue(firstAlpha.location != NSNotFound);
    NSRange secondAlpha = [text rangeOfString:@"alpha"
                                      options:0
                                        range:NSMakeRange(NSMaxRange(firstAlpha),
                                                          [text length] - NSMaxRange(firstAlpha))];
    XCTAssertTrue(secondAlpha.location != NSNotFound);

    NSArray *anchors = [renderer blockAnchors];
    XCTAssertTrue([anchors count] > 0);

    BOOL mappedFirstAlphaLine = NO;
    BOOL mappedSecondAlphaLine = NO;
    for (NSDictionary *anchor in anchors) {
        NSNumber *sourceStart = [anchor objectForKey:OMMarkdownRendererAnchorSourceStartLineKey];
        NSNumber *sourceEnd = [anchor objectForKey:OMMarkdownRendererAnchorSourceEndLineKey];
        NSNumber *targetStart = [anchor objectForKey:OMMarkdownRendererAnchorTargetStartKey];
        NSNumber *targetLength = [anchor objectForKey:OMMarkdownRendererAnchorTargetLengthKey];
        if (sourceStart == nil || sourceEnd == nil || targetStart == nil || targetLength == nil) {
            continue;
        }
        if ([sourceStart integerValue] != [sourceEnd integerValue]) {
            continue;
        }

        NSUInteger rangeStart = [targetStart unsignedIntegerValue];
        NSUInteger rangeLength = [targetLength unsignedIntegerValue];
        if (rangeLength == 0) {
            continue;
        }
        NSRange range = NSMakeRange(rangeStart, rangeLength);
        NSInteger line = [sourceStart integerValue];
        if (line == 3 && NSLocationInRange(firstAlpha.location, range)) {
            mappedFirstAlphaLine = YES;
        }
        if (line == 5 && NSLocationInRange(secondAlpha.location, range)) {
            mappedSecondAlphaLine = YES;
        }
    }

    XCTAssertTrue(mappedFirstAlphaLine);
    XCTAssertTrue(mappedSecondAlphaLine);
}

- (void)testObjectiveCCodeBlockSyntaxHighlightingAppliesDistinctTokenColors
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"```objc\nint main(void) {\n  // note\n  return 42;\n}\n```";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange plainRange = [text rangeOfString:@"main"];
    NSRange keywordRange = [text rangeOfString:@"return"];
    NSRange commentRange = [text rangeOfString:@"// note"];
    XCTAssertTrue(plainRange.location != NSNotFound);
    XCTAssertTrue(keywordRange.location != NSNotFound);
    XCTAssertTrue(commentRange.location != NSNotFound);

    if (plainRange.location == NSNotFound ||
        keywordRange.location == NSNotFound ||
        commentRange.location == NSNotFound) {
        return;
    }

    NSDictionary *plainAttrs = [rendered attributesAtIndex:plainRange.location effectiveRange:NULL];
    NSDictionary *keywordAttrs = [rendered attributesAtIndex:keywordRange.location effectiveRange:NULL];
    NSDictionary *commentAttrs = [rendered attributesAtIndex:commentRange.location effectiveRange:NULL];

    NSColor *plainColor = [plainAttrs objectForKey:NSForegroundColorAttributeName];
    NSColor *keywordColor = [keywordAttrs objectForKey:NSForegroundColorAttributeName];
    NSColor *commentColor = [commentAttrs objectForKey:NSForegroundColorAttributeName];
    XCTAssertNotNil(plainColor);
    XCTAssertNotNil(keywordColor);
    XCTAssertNotNil(commentColor);
    if ([OMMarkdownRenderer isTreeSitterAvailable]) {
        XCTAssertFalse([plainColor isEqual:keywordColor]);
        XCTAssertFalse([keywordColor isEqual:commentColor]);
    } else {
        XCTAssertTrue([plainColor isEqual:keywordColor]);
        XCTAssertTrue([keywordColor isEqual:commentColor]);
    }
}

- (void)testCodeBlockSyntaxHighlightingCanBeDisabledByParsingOption
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setCodeSyntaxHighlightingEnabled:NO];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    NSString *markdown = @"```objc\nint main(void) {\n  // note\n  return 42;\n}\n```";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange plainRange = [text rangeOfString:@"main"];
    NSRange keywordRange = [text rangeOfString:@"return"];
    NSRange commentRange = [text rangeOfString:@"// note"];
    XCTAssertTrue(plainRange.location != NSNotFound);
    XCTAssertTrue(keywordRange.location != NSNotFound);
    XCTAssertTrue(commentRange.location != NSNotFound);

    if (plainRange.location == NSNotFound ||
        keywordRange.location == NSNotFound ||
        commentRange.location == NSNotFound) {
        return;
    }

    NSDictionary *plainAttrs = [rendered attributesAtIndex:plainRange.location effectiveRange:NULL];
    NSDictionary *keywordAttrs = [rendered attributesAtIndex:keywordRange.location effectiveRange:NULL];
    NSDictionary *commentAttrs = [rendered attributesAtIndex:commentRange.location effectiveRange:NULL];

    NSColor *plainColor = [plainAttrs objectForKey:NSForegroundColorAttributeName];
    NSColor *keywordColor = [keywordAttrs objectForKey:NSForegroundColorAttributeName];
    NSColor *commentColor = [commentAttrs objectForKey:NSForegroundColorAttributeName];
    XCTAssertNotNil(plainColor);
    XCTAssertNotNil(keywordColor);
    XCTAssertNotNil(commentColor);
    XCTAssertTrue([plainColor isEqual:keywordColor]);
    XCTAssertTrue([keywordColor isEqual:commentColor]);
}

- (void)testSQLCodeBlockSyntaxHighlightingAppliesDistinctTokenColors
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"```sql\nSELECT id FROM users WHERE id = 42;\n-- note\n```";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange keywordRange = [text rangeOfString:@"SELECT"];
    NSRange plainRange = [text rangeOfString:@"users"];
    NSRange commentRange = [text rangeOfString:@"-- note"];
    XCTAssertTrue(keywordRange.location != NSNotFound);
    XCTAssertTrue(plainRange.location != NSNotFound);
    XCTAssertTrue(commentRange.location != NSNotFound);
    if (keywordRange.location == NSNotFound ||
        plainRange.location == NSNotFound ||
        commentRange.location == NSNotFound) {
        return;
    }

    NSColor *keywordColor = [[rendered attributesAtIndex:keywordRange.location effectiveRange:NULL] objectForKey:NSForegroundColorAttributeName];
    NSColor *plainColor = [[rendered attributesAtIndex:plainRange.location effectiveRange:NULL] objectForKey:NSForegroundColorAttributeName];
    NSColor *commentColor = [[rendered attributesAtIndex:commentRange.location effectiveRange:NULL] objectForKey:NSForegroundColorAttributeName];
    XCTAssertNotNil(keywordColor);
    XCTAssertNotNil(plainColor);
    XCTAssertNotNil(commentColor);
    if ([OMMarkdownRenderer isTreeSitterAvailable]) {
        XCTAssertFalse([keywordColor isEqual:plainColor]);
        XCTAssertFalse([keywordColor isEqual:commentColor]);
    }
}

- (void)testYAMLCodeBlockSyntaxHighlightingAppliesDistinctTokenColors
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"```yaml\nname: example\ncount: 42\n# note\n```";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange keyRange = [text rangeOfString:@"name:"];
    NSRange plainRange = [text rangeOfString:@"example"];
    NSRange commentRange = [text rangeOfString:@"# note"];
    XCTAssertTrue(keyRange.location != NSNotFound);
    XCTAssertTrue(plainRange.location != NSNotFound);
    XCTAssertTrue(commentRange.location != NSNotFound);
    if (keyRange.location == NSNotFound ||
        plainRange.location == NSNotFound ||
        commentRange.location == NSNotFound) {
        return;
    }

    NSColor *keyColor = [[rendered attributesAtIndex:keyRange.location effectiveRange:NULL] objectForKey:NSForegroundColorAttributeName];
    NSColor *plainColor = [[rendered attributesAtIndex:plainRange.location effectiveRange:NULL] objectForKey:NSForegroundColorAttributeName];
    NSColor *commentColor = [[rendered attributesAtIndex:commentRange.location effectiveRange:NULL] objectForKey:NSForegroundColorAttributeName];
    XCTAssertNotNil(keyColor);
    XCTAssertNotNil(plainColor);
    XCTAssertNotNil(commentColor);
    if ([OMMarkdownRenderer isTreeSitterAvailable]) {
        XCTAssertFalse([keyColor isEqual:plainColor]);
        XCTAssertFalse([keyColor isEqual:commentColor]);
    }
}

- (void)testMathPolicyTransitionsBetweenStyledAndDisabled
{
    NSString *markdown = @"Transition $a^2+b^2=c^2$ sample.";
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil parsingOptions:options] autorelease];

    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
    [renderer setParsingOptions:options];
    NSAttributedString *styled = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(styled);
    XCTAssertTrue([[styled string] rangeOfString:@"$a^2+b^2=c^2$"].location == NSNotFound);

    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyDisabled];
    [renderer setParsingOptions:options];
    NSAttributedString *disabled = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(disabled);
    XCTAssertTrue([[disabled string] rangeOfString:@"$a^2+b^2=c^2$"].location != NSNotFound);

    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
    [renderer setParsingOptions:options];
    NSAttributedString *styledAgain = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(styledAgain);
    XCTAssertTrue([[styledAgain string] rangeOfString:@"$a^2+b^2=c^2$"].location == NSNotFound);
}

- (void)testConcurrentRenderersDoNotCrossContaminateRenderState
{
    NSString *markdown = @"# Header\n\nBefore <span class=\"hot\">inline</span> after.\n\nSee [rel](note.md).\n\n```objc\nint value = 42;\n```\n\nInline math: $a+b=c$.\n";
    NSURL *baseA = [NSURL fileURLWithPath:@"/tmp/objcmarkdown-phase1-a" isDirectory:YES];
    NSURL *baseB = [NSURL fileURLWithPath:@"/tmp/objcmarkdown-phase1-b" isDirectory:YES];
    NSMutableArray *failures = [NSMutableArray array];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSUInteger iterations = 80;
    NSUInteger i = 0;
    for (; i < iterations; i++) {
        dispatch_group_async(group, queue, ^{
            @autoreleasepool {
                OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
                [options setInlineHTMLPolicy:OMMarkdownHTMLPolicyIgnore];
                [options setBlockHTMLPolicy:OMMarkdownHTMLPolicyIgnore];
                [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyDisabled];
                [options setBaseURL:baseA];
                OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                            parsingOptions:options] autorelease];
                NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
                NSString *text = rendered != nil ? [rendered string] : @"";
                NSURL *linkURL = [self linkURLInRenderedString:rendered forVisibleText:@"rel"];
                NSArray *anchors = [renderer blockAnchors];
                NSArray *codeRanges = [renderer codeBlockRanges];

                BOOL htmlSuppressed = [text rangeOfString:@"<span class=\"hot\">inline</span>"].location == NSNotFound;
                BOOL mathLiteral = [text rangeOfString:@"$a+b=c$"].location != NSNotFound;
                BOOL linkUsesBase = (linkURL != nil &&
                                     [[linkURL absoluteString] hasSuffix:@"/tmp/objcmarkdown-phase1-a/note.md"]);
                BOOL hasAnchors = [anchors count] > 0;
                BOOL hasCodeRanges = [codeRanges count] > 0;
                if (rendered == nil || !htmlSuppressed || !mathLiteral || !linkUsesBase || !hasAnchors || !hasCodeRanges) {
                    @synchronized (failures) {
                        [failures addObject:@"renderer-A mismatch under concurrent load"];
                    }
                }
            }
        });

        dispatch_group_async(group, queue, ^{
            @autoreleasepool {
                OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
                [options setInlineHTMLPolicy:OMMarkdownHTMLPolicyRenderAsText];
                [options setBlockHTMLPolicy:OMMarkdownHTMLPolicyRenderAsText];
                [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
                [options setBaseURL:baseB];
                OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                            parsingOptions:options] autorelease];
                NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
                NSString *text = rendered != nil ? [rendered string] : @"";
                NSURL *linkURL = [self linkURLInRenderedString:rendered forVisibleText:@"rel"];
                NSArray *anchors = [renderer blockAnchors];
                NSArray *codeRanges = [renderer codeBlockRanges];

                BOOL htmlVisible = [text rangeOfString:@"<span class=\"hot\">inline</span>"].location != NSNotFound;
                BOOL mathStyled = [text rangeOfString:@"$a+b=c$"].location == NSNotFound;
                BOOL linkUsesBase = (linkURL != nil &&
                                     [[linkURL absoluteString] hasSuffix:@"/tmp/objcmarkdown-phase1-b/note.md"]);
                BOOL hasAnchors = [anchors count] > 0;
                BOOL hasCodeRanges = [codeRanges count] > 0;
                if (rendered == nil || !htmlVisible || !mathStyled || !linkUsesBase || !hasAnchors || !hasCodeRanges) {
                    @synchronized (failures) {
                        [failures addObject:@"renderer-B mismatch under concurrent load"];
                    }
                }
            }
        });
    }

    long waitResult = dispatch_group_wait(group,
                                          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)));
    XCTAssertEqual(waitResult, 0L);
    XCTAssertEqual([failures count], (NSUInteger)0, @"%@", [failures componentsJoinedByString:@"\n"]);
}

- (void)testMathHeavyStyledTextRenderPerformanceGuardrail
{
    NSMutableString *markdown = [NSMutableString string];
    NSUInteger i = 0;
    for (; i < 500; i++) {
        [markdown appendFormat:@"Inline %lu: $x_%lu^2 + y_%lu^2 = z_%lu^2$.\n\n",
                               (unsigned long)i,
                               (unsigned long)i,
                               (unsigned long)i,
                               (unsigned long)i];
        [markdown appendFormat:@"$$\\\\int_0^1 x^%lu dx$$\n\n", (unsigned long)((i % 5) + 1)];
    }

    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil parsingOptions:options] autorelease];

    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;

    XCTAssertNotNil(rendered);
    XCTAssertTrue([rendered length] > 0);
    XCTAssertTrue(elapsed < 15.0);
}

@end
