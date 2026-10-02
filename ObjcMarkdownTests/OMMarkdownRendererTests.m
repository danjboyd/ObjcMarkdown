// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import "OMMarkdownRenderer.h"
#import "OMRenderedObject.h"
#import "OMTheme.h"
#import "OMAppKitSerialization.h"
#import "OMMermaidERDrawing.h"
#import "OMMermaidERLayout.h"

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

- (NSString *)writeTemporaryImageWithSize:(NSSize)size
{
    NSString *path = [self temporaryImagePathWithExtension:@"png"];
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.15 green:0.45 blue:0.85 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
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

- (NSString *)writeTemporaryImage
{
    return [self writeTemporaryImageWithSize:NSMakeSize(8.0, 8.0)];
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

- (BOOL)isStruckText:(NSString *)needle inRenderedString:(NSAttributedString *)rendered
{
    NSRange range = [[rendered string] rangeOfString:needle];
    if (range.location == NSNotFound) {
        return NO;
    }
    NSNumber *style = [rendered attribute:NSStrikethroughStyleAttributeName atIndex:range.location effectiveRange:NULL];
    return style != nil && [style integerValue] != 0;
}

- (void)testStrikethroughLeavesTildeFencedCodeIntact
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"~~~python\nx = 1 ~~y~~\n~~~\n\nAfter ~~gone~~ text."];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"x = 1 ~~y~~"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"<del>"].location == NSNotFound);
    XCTAssertFalse([self isStruckText:@"x = 1" inRenderedString:rendered]);
    XCTAssertTrue([self isStruckText:@"gone" inRenderedString:rendered]);
}

- (void)testStrikethroughLeavesIndentedCodeIntact
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Para\n\n    code ~~x~~\n"];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"code ~~x~~"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"<del>"].location == NSNotFound);
}

- (void)testStrikethroughDoesNotPairAcrossParagraphs
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"a ~~b\n\nc~~ d"];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"a ~~b"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"c~~ d"].location != NSNotFound);
    XCTAssertFalse([self isStruckText:@"b" inRenderedString:rendered]);
}

- (void)testStrikethroughFollowsFlankingRules
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"a ~~ b ~~z~~ end"];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"a ~~ b z end"].location != NSNotFound);
    XCTAssertFalse([self isStruckText:@" b " inRenderedString:rendered]);
    XCTAssertTrue([self isStruckText:@"z" inRenderedString:rendered]);
}

- (void)testStrikethroughAppliesWhenInlineHTMLIsIgnored
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setInlineHTMLPolicy:OMMarkdownHTMLPolicyIgnore];
    [options setBlockHTMLPolicy:OMMarkdownHTMLPolicyIgnore];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Keep ~~remove~~ text."];
    XCTAssertTrue([[rendered string] rangeOfString:@"Keep remove text."].location != NSNotFound);
    XCTAssertTrue([self isStruckText:@"remove" inRenderedString:rendered]);
}

- (void)testStrikeTagOnItsOwnLineDoesNotStrikeFollowingText
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"<del>\n\nAfter text."];
    XCTAssertFalse([self isStruckText:@"After" inRenderedString:rendered]);
}

- (void)testFrontMatterIsHiddenAndKeepsSourceLines
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"---\ntitle: Sample\ntags: [a]\n---\n\n# Heading\n"];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"title:"].location == NSNotFound);
    XCTAssertTrue([text hasPrefix:@"Heading"]);
    NSDictionary *anchor = [[renderer blockAnchors] firstObject];
    XCTAssertNotNil(anchor);
    XCTAssertEqual([[anchor objectForKey:OMMarkdownRendererAnchorSourceStartLineKey] integerValue], (NSInteger)6);
}

- (void)testLeadingThematicBreakIsNotFrontMatter
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"---\nIntro text\n---\n"];
    XCTAssertTrue([[rendered string] rangeOfString:@"Intro text"].location != NSNotFound);
}

- (void)testHardBreakDoesNotAddParagraphSpacing
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"line one  \nline two\n\nnext"];
    NSString *text = [rendered string];
    NSRange first = [text rangeOfString:@"line one"];
    NSRange second = [text rangeOfString:@"line two"];
    XCTAssertTrue(first.location != NSNotFound && second.location != NSNotFound);
    if (first.location == NSNotFound || second.location == NSNotFound) {
        return;
    }
    NSParagraphStyle *firstStyle = [rendered attribute:NSParagraphStyleAttributeName atIndex:first.location effectiveRange:NULL];
    NSParagraphStyle *secondStyle = [rendered attribute:NSParagraphStyleAttributeName atIndex:second.location effectiveRange:NULL];
    XCTAssertEqualWithAccuracy([firstStyle paragraphSpacing], 0.0, 0.01);
    XCTAssertTrue([secondStyle paragraphSpacing] > 0.0);
    XCTAssertNil([rendered attribute:@"OMHardLineBreak" atIndex:NSMaxRange(first) effectiveRange:NULL]);
}

- (void)testLooseListEndsWithOneBlankLine
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *text = [[renderer attributedStringFromMarkdown:@"- a\n\n- b\n\nAfter"] string];
    XCTAssertTrue([text rangeOfString:@"b\n\nAfter"].location != NSNotFound);
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

- (void)testPipeTableAcceptsSingleDashSeparators
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"| a | b |\n|:-|-:|\n| 1 | 2 |"];
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

- (void)testImageAttachmentScalesWithDocumentZoom
{
    NSString *path = [self writeTemporaryImage];
    NSString *markdown = [NSString stringWithFormat:@"![tiny-square](%@)", path];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:420.0];

    NSArray *zoomValues = [NSArray arrayWithObjects:
        [NSNumber numberWithDouble:0.5],
        [NSNumber numberWithDouble:1.0],
        [NSNumber numberWithDouble:2.0],
        nil];
    NSArray *expectedSizes = [NSArray arrayWithObjects:
        [NSValue valueWithSize:NSMakeSize(4.0, 4.0)],
        [NSValue valueWithSize:NSMakeSize(8.0, 8.0)],
        [NSValue valueWithSize:NSMakeSize(16.0, 16.0)],
        nil];

    NSUInteger index = 0;
    for (; index < [zoomValues count]; index++) {
        [renderer setZoomScale:[[zoomValues objectAtIndex:index] doubleValue]];
        NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
        NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
        XCTAssertNotNil(attachment);
        id cell = [attachment attachmentCell];
        XCTAssertNotNil(cell);
        if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
            NSSize actualSize = [cell cellSize];
            NSSize expectedSize = [[expectedSizes objectAtIndex:index] sizeValue];
            XCTAssertEqualWithAccuracy(actualSize.width, expectedSize.width, 0.01);
            XCTAssertEqualWithAccuracy(actualSize.height, expectedSize.height, 0.01);
        }
    }
    [self removeFileIfPresent:path];
}

- (void)testZoomedImageAttachmentFitsPreviewWidthAndPreservesAspectRatio
{
    NSString *path = [self writeTemporaryImageWithSize:NSMakeSize(200.0, 100.0)];
    NSString *markdown = [NSString stringWithFormat:@"![wide-image](%@)", path];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:100.0];
    [renderer setZoomScale:2.0];

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment);
    id cell = [attachment attachmentCell];
    XCTAssertNotNil(cell);
    if (cell != nil && [cell respondsToSelector:@selector(cellSize)]) {
        NSSize size = [cell cellSize];
        XCTAssertEqualWithAccuracy(size.width, 52.0, 0.01);
        XCTAssertEqualWithAccuracy(size.height, 26.0, 0.01);
        XCTAssertEqualWithAccuracy(size.width / size.height, 2.0, 0.01);
    }
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

- (void)testLocalImageDependenciesUseCommonMarkResolution
{
    NSURL *base = [NSURL fileURLWithPath:@"/tmp/markdown-images" isDirectory:YES];
    NSString *markdown = @"![inline](images/a%20b.png)\n![reference][pic]\n"
                          @"![duplicate](images/a%20b.png)\n![remote](https://example.com/image.png)\n"
                          @"`![code](ignored.png)`\n\n```\n![fenced](ignored-too.png)\n```\n\n"
                          @"[pic]: ../missing.png\n";
    NSArray *urls = [OMMarkdownRenderer localImageURLsInMarkdown:markdown baseURL:base];
    XCTAssertEqual([urls count], (NSUInteger)2);
    XCTAssertEqualObjects([[[urls objectAtIndex:0] path] stringByStandardizingPath], @"/tmp/markdown-images/images/a b.png");
    XCTAssertEqualObjects([[[urls objectAtIndex:1] path] stringByStandardizingPath], @"/tmp/missing.png");
}

- (void)testLocalImageReplacementAndDeletionAreVisibleOnRerender
{
    NSString *path = [self writeTemporaryImage];
    NSString *replacement = [self writeTemporaryImageWithSize:NSMakeSize(32.0, 16.0)];
    NSString *markdown = [NSString stringWithFormat:@"![changing](%@)", path];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:420.0];
    NSTextAttachment *original = [self firstAttachmentInRenderedString:[renderer attributedStringFromMarkdown:markdown]];
    XCTAssertNotNil(original);
    XCTAssertTrue([[NSData dataWithContentsOfFile:replacement] writeToFile:path atomically:YES]);
    NSTextAttachment *updated = [self firstAttachmentInRenderedString:[renderer attributedStringFromMarkdown:markdown]];
    XCTAssertNotNil(updated);
    NSSize size = [[updated attachmentCell] cellSize];
    XCTAssertEqualWithAccuracy(size.width, 32.0, 0.01);
    XCTAssertEqualWithAccuracy(size.height, 16.0, 0.01);
    [self removeFileIfPresent:path];
    NSAttributedString *missing = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNil([self firstAttachmentInRenderedString:missing]);
    XCTAssertTrue([[missing string] rangeOfString:@"[image: changing]"].location != NSNotFound);
    [self removeFileIfPresent:replacement];
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

- (void)assertRenderState:(NSAttributedString *)rendered
                  variant:(NSString *)variant
                  failures:(NSMutableArray *)failures
{
    NSString *text = rendered != nil ? [rendered string] : @"";
    NSURL *linkURL = [self linkURLInRenderedString:rendered forVisibleText:@"rel"];
    BOOL isVariantA = [variant isEqualToString:@"A"];

    BOOL htmlCorrect = isVariantA
        ? ([text rangeOfString:@"<span class=\"hot\">inline</span>"].location == NSNotFound)
        : ([text rangeOfString:@"<span class=\"hot\">inline</span>"].location != NSNotFound);
    BOOL mathCorrect = isVariantA
        ? ([text rangeOfString:@"$a+b=c$"].location != NSNotFound)
        : ([text rangeOfString:@"$a+b=c$"].location == NSNotFound);
    NSString *expectedSuffix = isVariantA
        ? @"/tmp/objcmarkdown-phase1-a/note.md"
        : @"/tmp/objcmarkdown-phase1-b/note.md";
    BOOL linkUsesBase = (linkURL != nil && [[linkURL absoluteString] hasSuffix:expectedSuffix]);

    if (rendered == nil || !htmlCorrect || !mathCorrect || !linkUsesBase) {
        @synchronized (failures) {
            [failures addObject:[NSString stringWithFormat:@"renderer-%@ mismatch", variant]];
        }
    }
}

- (OMMarkdownRenderer *)rendererForVariant:(NSString *)variant baseURL:(NSURL *)baseURL
{
    BOOL isVariantA = [variant isEqualToString:@"A"];
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setInlineHTMLPolicy:isVariantA ? OMMarkdownHTMLPolicyIgnore : OMMarkdownHTMLPolicyRenderAsText];
    [options setBlockHTMLPolicy:isVariantA ? OMMarkdownHTMLPolicyIgnore : OMMarkdownHTMLPolicyRenderAsText];
    [options setMathRenderingPolicy:isVariantA
        ? OMMarkdownMathRenderingPolicyDisabled
        : OMMarkdownMathRenderingPolicyStyledText];
    [options setBaseURL:baseURL];
    return [[[OMMarkdownRenderer alloc] initWithTheme:nil parsingOptions:options] autorelease];
}

- (NSString *)crossContaminationMarkdown
{
    return @"# Header\n\nBefore <span class=\"hot\">inline</span> after.\n\nSee [rel](note.md).\n\n```objc\nint value = 42;\n```\n\nInline math: $a+b=c$.\n";
}

- (void)testInterleavedRenderersDoNotCrossContaminateRenderState
{
    NSString *markdown = [self crossContaminationMarkdown];
    NSURL *baseA = [NSURL fileURLWithPath:@"/tmp/objcmarkdown-phase1-a" isDirectory:YES];
    NSURL *baseB = [NSURL fileURLWithPath:@"/tmp/objcmarkdown-phase1-b" isDirectory:YES];
    NSMutableArray *failures = [NSMutableArray array];

    NSUInteger i = 0;
    for (; i < 80; i++) {
        @autoreleasepool {
            OMMarkdownRenderer *rendererA = [self rendererForVariant:@"A" baseURL:baseA];
            OMMarkdownRenderer *rendererB = [self rendererForVariant:@"B" baseURL:baseB];

            // Alternate which renderer goes first so that leaked state from
            // either ordering shows up.
            if ((i % 2) == 0) {
                [self assertRenderState:[rendererA attributedStringFromMarkdown:markdown]
                                variant:@"A"
                               failures:failures];
                [self assertRenderState:[rendererB attributedStringFromMarkdown:markdown]
                                variant:@"B"
                               failures:failures];
            } else {
                [self assertRenderState:[rendererB attributedStringFromMarkdown:markdown]
                                variant:@"B"
                               failures:failures];
                [self assertRenderState:[rendererA attributedStringFromMarkdown:markdown]
                                variant:@"A"
                               failures:failures];
            }

            XCTAssertTrue([[rendererA blockAnchors] count] > 0);
            XCTAssertTrue([[rendererA codeBlockRanges] count] > 0);
            XCTAssertTrue([[rendererB blockAnchors] count] > 0);
            XCTAssertTrue([[rendererB codeBlockRanges] count] > 0);
        }
    }

    XCTAssertEqual([failures count], (NSUInteger)0, @"%@", [failures componentsJoinedByString:@"\n"]);
}

// GNUstep AppKit text objects cannot be built, inspected, or released on several
// threads at once, so a caller doing concurrent work holds OMAppKitGlobalLock
// across everything that touches the rendered string. This checks that the
// documented pattern keeps renderer state isolated.
- (void)testConcurrentRenderersUnderTheSharedLockStayIsolated
{
    NSString *markdown = [self crossContaminationMarkdown];
    NSURL *baseA = [NSURL fileURLWithPath:@"/tmp/objcmarkdown-phase1-a" isDirectory:YES];
    NSURL *baseB = [NSURL fileURLWithPath:@"/tmp/objcmarkdown-phase1-b" isDirectory:YES];
    NSMutableArray *failures = [NSMutableArray array];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSUInteger iterations = 40;
    NSUInteger i = 0;
    for (; i < iterations; i++) {
        NSUInteger which = 0;
        for (; which < 2; which++) {
            NSString *variant = (which == 0) ? @"A" : @"B";
            NSURL *baseURL = (which == 0) ? baseA : baseB;
            dispatch_group_async(group, queue, ^{
                NSRecursiveLock *lock = OMAppKitGlobalLock();
                [lock lock];
                @try {
                    @autoreleasepool {
                        OMMarkdownRenderer *renderer = [self rendererForVariant:variant baseURL:baseURL];
                        NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
                        [self assertRenderState:rendered variant:variant failures:failures];
                        if ([[renderer blockAnchors] count] == 0 ||
                            [[renderer codeBlockRanges] count] == 0) {
                            @synchronized (failures) {
                                [failures addObject:@"missing anchors or code ranges"];
                            }
                        }
                    }
                } @finally {
                    [lock unlock];
                }
            });
        }
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

- (NSString *)sampleMermaidMarkdown
{
    return @"```mermaid\n"
            "erDiagram\n"
            "    CUSTOMER ||--o{ ORDER : places\n"
            "    ORDER ||--|{ ORDER_ITEM : contains\n"
            "    CUSTOMER {\n"
            "        uuid id PK\n"
            "        text email UK\n"
            "    }\n"
            "```\n";
}

- (void)testMermaidERDiagramRendersAsDrawnAttachment
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];

    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    XCTAssertNotNil(attachment, @"an erDiagram should render as an attachment");
    XCTAssertTrue([[attachment attachmentCell] isKindOfClass:[OMMermaidERDiagramAttachmentCell class]]);

    NSSize cellSize = [[attachment attachmentCell] cellSize];
    XCTAssertTrue(cellSize.width > 0.0 && cellSize.height > 0.0);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"CUSTOMER ||--o{ ORDER"].location == NSNotFound,
                  @"diagram source should not also appear as code");
    XCTAssertTrue([text rangeOfString:@"mermaid erDiagram"].location == NSNotFound,
                  @"a diagram that draws should produce no diagnostic");
}

- (void)testDrawnMermaidDiagramIsNotRecordedAsACodeBlock
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    XCTAssertNotNil(rendered);
    XCTAssertEqual([[renderer codeBlockRanges] count], (NSUInteger)0,
                   @"a drawn diagram must not get the code-block background or copy button");
}

- (void)testDrawnMermaidDiagramExposesEveryEntityAndRelationship
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    OMMermaidERDiagramAttachmentCell *cell =
        (OMMermaidERDiagramAttachmentCell *)[[self firstAttachmentInRenderedString:rendered] attachmentCell];

    OMMermaidERDiagramLayout *layout = [cell layout];
    XCTAssertEqual([[layout entityLayouts] count], (NSUInteger)3);
    XCTAssertEqual([[layout edgeLayouts] count], (NSUInteger)2);
    XCTAssertEqual([[[layout layoutForEntityNamed:@"CUSTOMER"] attributeRows] count], (NSUInteger)2);
}

- (void)testMermaidDiagramShrinksToFitANarrowPreviewWidth
{
    OMMarkdownRenderer *wideRenderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [wideRenderer setLayoutWidth:1400.0];
    NSAttributedString *wide = [wideRenderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    OMMermaidERDiagramAttachmentCell *wideCell =
        (OMMermaidERDiagramAttachmentCell *)[[self firstAttachmentInRenderedString:wide] attachmentCell];

    OMMarkdownRenderer *narrowRenderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [narrowRenderer setLayoutWidth:240.0];
    NSAttributedString *narrow = [narrowRenderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    OMMermaidERDiagramAttachmentCell *narrowCell =
        (OMMermaidERDiagramAttachmentCell *)[[self firstAttachmentInRenderedString:narrow] attachmentCell];

    XCTAssertEqualWithAccuracy([wideCell drawScale], 1.0, 0.001,
                               @"a wide column should not shrink the diagram");
    XCTAssertTrue([narrowCell drawScale] < 1.0, @"a narrow column should shrink the diagram");
    XCTAssertTrue([narrowCell cellSize].width < [wideCell cellSize].width);
    XCTAssertTrue([narrowCell cellSize].height < [wideCell cellSize].height);
    XCTAssertTrue([narrowCell drawScale] >= 0.5,
                  @"shrinking stops at the legibility floor rather than continuing");
}

- (void)testMermaidDiagramGrowsWithDocumentZoom
{
    OMMarkdownRenderer *plain = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *plainRendered = [plain attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    NSSize plainSize = [[[self firstAttachmentInRenderedString:plainRendered] attachmentCell] cellSize];

    OMMarkdownRenderer *zoomed = [[[OMMarkdownRenderer alloc] init] autorelease];
    [zoomed setZoomScale:2.0];
    NSAttributedString *zoomedRendered = [zoomed attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    NSSize zoomedSize = [[[self firstAttachmentInRenderedString:zoomedRendered] attachmentCell] cellSize];

    XCTAssertTrue(zoomedSize.width > plainSize.width);
    XCTAssertTrue(zoomedSize.height > plainSize.height);
}

- (void)testMermaidDiagramDrawsIntoAnImageContextWithoutFailing
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    OMMermaidERDiagramAttachmentCell *cell =
        (OMMermaidERDiagramAttachmentCell *)[[self firstAttachmentInRenderedString:rendered] attachmentCell];
    NSSize size = [cell cellSize];

    NSImage *canvas = [[[NSImage alloc] initWithSize:size] autorelease];
    BOOL drew = NO;
    @try {
        [canvas lockFocus];
        [cell drawWithFrame:NSMakeRect(0.0, 0.0, size.width, size.height) inView:nil];
        [canvas unlockFocus];
        drew = YES;
    } @catch (NSException *exception) {
        XCTFail(@"drawing raised %@: %@", [exception name], [exception reason]);
    }
    XCTAssertTrue(drew);
}

- (void)testMalformedMermaidERDiagramAppendsDiagnosticWithSourceLine
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"```mermaid\n"
                          "erDiagram\n"
                          "    A {\n"
                          "        lonely\n"
                          "    }\n"
                          "```\n";

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"lonely"].location != NSNotFound,
                  @"diagram source should still render as a code block");
    XCTAssertTrue([text rangeOfString:@"mermaid erDiagram, line 4:"].location != NSNotFound,
                  @"expected a diagnostic naming the failing line, got: %@", text);
    XCTAssertNil([self firstAttachmentInRenderedString:rendered]);
}

- (void)testOversizedMermaidDiagramFallsBackToCodeWithAnExplanation
{
    NSMutableString *markdown = [NSMutableString stringWithString:@"```mermaid\nerDiagram\n"];
    NSUInteger index = 0;
    for (; index <= OMMermaidERLayoutMaximumEntities; index++) {
        [markdown appendFormat:@"    E%lu\n", (unsigned long)index];
    }
    [markdown appendString:@"```\n"];

    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSString *text = [rendered string];

    XCTAssertNil([self firstAttachmentInRenderedString:rendered]);
    XCTAssertTrue([text rangeOfString:@"too large to draw"].location != NSNotFound,
                  @"expected an explanation, got: %@", text);
    XCTAssertTrue([[renderer codeBlockRanges] count] > 0,
                  @"the fallback keeps the code block");
}

- (void)testNonERMermaidDiagramRendersAsCodeWithoutDiagnostic
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"```mermaid\n"
                          "flowchart LR\n"
                          "    A --> B\n"
                          "```\n";

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"flowchart LR"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"mermaid erDiagram"].location == NSNotFound);
    XCTAssertNil([self firstAttachmentInRenderedString:rendered]);
}

- (void)testMermaidDiagnosticIsNotPartOfAnyCodeBlockRange
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"```mermaid\n"
                          "erDiagram\n"
                          "    A {\n"
                          "        lonely\n"
                          "    }\n"
                          "```\n";

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSRange diagnosticRange = [[rendered string] rangeOfString:@"mermaid erDiagram, line 4:"];
    XCTAssertTrue(diagnosticRange.location != NSNotFound);

    for (NSValue *value in [renderer codeBlockRanges]) {
        NSRange codeRange = [value rangeValue];
        XCTAssertTrue(NSIntersectionRange(codeRange, diagnosticRange).length == 0,
                      @"diagnostic must sit outside the code-block background range");
    }
}

- (void)testDrawnDiagramIsExposedWithItsSourceForCopying
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];

    NSArray *blocks = [renderer diagramBlocks];
    XCTAssertEqual([blocks count], (NSUInteger)1);

    NSDictionary *block = [blocks objectAtIndex:0];
    NSRange range = [[block objectForKey:OMMarkdownRendererDiagramRangeKey] rangeValue];
    XCTAssertEqual(range.length, (NSUInteger)1, @"a drawn diagram is one attachment character");
    XCTAssertTrue(NSMaxRange(range) <= [rendered length]);
    XCTAssertEqual([[rendered string] characterAtIndex:range.location], (unichar)NSAttachmentCharacter);

    NSString *source = [block objectForKey:OMMarkdownRendererDiagramSourceKey];
    XCTAssertTrue([source rangeOfString:@"CUSTOMER ||--o{ ORDER : places"].location != NSNotFound,
                  @"the copy button needs the original mermaid source");
}

- (void)testSourceCodeDiagramPolicyRendersTheFenceAsCode
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    XCTAssertEqual([options diagramRenderingPolicy], OMMarkdownDiagramRenderingPolicyNative,
                   @"drawing is the default");
    [options setDiagramRenderingPolicy:OMMarkdownDiagramRenderingPolicySourceCode];

    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                              parsingOptions:options] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];

    XCTAssertNil([self firstAttachmentInRenderedString:rendered]);
    XCTAssertEqual([[renderer diagramBlocks] count], (NSUInteger)0);
    XCTAssertTrue([[rendered string] rangeOfString:@"CUSTOMER ||--o{ ORDER"].location != NSNotFound);
    XCTAssertTrue([[renderer codeBlockRanges] count] > 0);
}

- (void)testSourceCodeDiagramPolicyStaysSilentOnMalformedDiagrams
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setDiagramRenderingPolicy:OMMarkdownDiagramRenderingPolicySourceCode];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                              parsingOptions:options] autorelease];

    NSString *markdown = @"```mermaid\nerDiagram\n    A {\n        lonely\n    }\n```\n";
    NSString *text = [[renderer attributedStringFromMarkdown:markdown] string];
    XCTAssertTrue([text rangeOfString:@"mermaid erDiagram"].location == NSNotFound,
                  @"asking for source should not also produce diagnostics");
}

- (void)testDiagramPolicySurvivesParsingOptionsCopy
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setDiagramRenderingPolicy:OMMarkdownDiagramRenderingPolicySourceCode];
    OMMarkdownParsingOptions *copy = [[options copy] autorelease];
    XCTAssertEqual([copy diagramRenderingPolicy], OMMarkdownDiagramRenderingPolicySourceCode);
}

- (void)testDiagramBlocksAreClearedWhenARenderHasNoDiagram
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer attributedStringFromMarkdown:[self sampleMermaidMarkdown]];
    XCTAssertEqual([[renderer diagramBlocks] count], (NSUInteger)1);

    [renderer attributedStringFromMarkdown:@"# Just a heading\n"];
    XCTAssertEqual([[renderer diagramBlocks] count], (NSUInteger)0,
                   @"stale diagram ranges would misplace copy buttons");
}

- (NSArray *)renderedObjectsInString:(NSAttributedString *)rendered
{
    NSMutableArray *objects = [NSMutableArray array];
    NSString *text = [rendered string];
    NSUInteger index = 0;
    for (; index < [text length]; index++) {
        OMRenderedObject *object = [rendered attribute:OMRenderedObjectAttributeName atIndex:index effectiveRange:NULL];
        if (object != nil) {
            XCTAssertEqual([text characterAtIndex:index], (unichar)NSAttachmentCharacter);
            [objects addObject:object];
        }
    }
    return objects;
}

- (void)testPipeTableCarriesItsMarkdownAsRenderedObject
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"Intro\n\n| a | b |\n|---|---|\n| 1 | 2 |\n";
    NSArray *objects = [self renderedObjectsInString:[renderer attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)1);
    OMRenderedObject *table = [objects firstObject];
    XCTAssertEqual([table kind], OMRenderedObjectKindTable);
    XCTAssertEqualObjects([table source], @"| a | b |\n|---|---|\n| 1 | 2 |");
    XCTAssertEqualObjects([table markdown], [table source]);
    XCTAssertEqual([table sourceLineRange].location, (NSUInteger)3);
    XCTAssertEqual([table sourceLineRange].length, (NSUInteger)3);
    XCTAssertEqualObjects([table kindDisplayName], @"Table");
}

- (void)testMermaidDiagramCarriesItsSourceAsRenderedObject
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"# Model\n\n```mermaid\nerDiagram\n    CUSTOMER ||--o{ ORDER : places\n```\n";
    NSArray *objects = [self renderedObjectsInString:[renderer attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)1);
    OMRenderedObject *diagram = [objects firstObject];
    XCTAssertEqual([diagram kind], OMRenderedObjectKindDiagram);
    XCTAssertEqualObjects([diagram source], @"erDiagram\n    CUSTOMER ||--o{ ORDER : places\n");
    XCTAssertEqualObjects([diagram markdown], @"```mermaid\nerDiagram\n    CUSTOMER ||--o{ ORDER : places\n```");
    XCTAssertEqual([diagram sourceLineRange].location, (NSUInteger)3);
    XCTAssertEqual([diagram sourceLineRange].length, (NSUInteger)4);
}

- (void)testImageCarriesItsMarkdownAsRenderedObject
{
    NSString *path = [self writeTemporaryImage];
    NSString *markdown = [NSString stringWithFormat:@"Text\n\nSee ![a *small* icon](%@ \"Icon\") here.", path];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSArray *objects = [self renderedObjectsInString:[renderer attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)1);
    OMRenderedObject *image = [objects firstObject];
    XCTAssertEqual([image kind], OMRenderedObjectKindImage);
    NSString *expected = [NSString stringWithFormat:@"![a small icon](%@ \"Icon\")", path];
    XCTAssertEqualObjects([image source], expected);
    XCTAssertEqual([image sourceLineRange].location, (NSUInteger)3);
    [self removeFileIfPresent:path];
}

- (void)testMathCarriesItsLaTeXAsRenderedObject
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    NSString *markdown = @"Inline $a^2$ here.\n\n$$\n\\frac{1}{2}\n$$\n";
    NSArray *objects = [self renderedObjectsInString:[renderer attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)2);
    if ([objects count] != 2) {
        return;
    }
    OMRenderedObject *inlineMath = [objects objectAtIndex:0];
    XCTAssertEqual([inlineMath kind], OMRenderedObjectKindInlineMath);
    XCTAssertEqualObjects([inlineMath source], @"a^2");
    XCTAssertEqualObjects([inlineMath markdown], @"$a^2$");
    XCTAssertEqual([inlineMath sourceLineRange].location, (NSUInteger)1);
    OMRenderedObject *displayMath = [objects objectAtIndex:1];
    XCTAssertEqual([displayMath kind], OMRenderedObjectKindDisplayMath);
    XCTAssertTrue([[displayMath source] rangeOfString:@"\\frac{1}{2}"].location != NSNotFound);
    XCTAssertEqualObjects([displayMath markdown], @"$$\n\\frac{1}{2}\n$$");
    XCTAssertEqual([displayMath sourceLineRange].location, (NSUInteger)3);
    XCTAssertEqual([displayMath sourceLineRange].length, (NSUInteger)3);
}

- (void)testCachedMathAttachmentsDoNotShareObjectsAcrossRenders
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                parsingOptions:options] autorelease];
    NSArray *first = [self renderedObjectsInString:[renderer attributedStringFromMarkdown:@"$x$"]];
    NSArray *second = [self renderedObjectsInString:[renderer attributedStringFromMarkdown:@"Line\n\n$x$"]];
    XCTAssertEqual([first count], (NSUInteger)1);
    XCTAssertEqual([second count], (NSUInteger)1);
    XCTAssertEqual([[first firstObject] sourceLineRange].location, (NSUInteger)1);
    XCTAssertEqual([[second firstObject] sourceLineRange].location, (NSUInteger)3);
}

- (NSString *)sourceTextOfObject:(OMRenderedObject *)object inMarkdown:(NSString *)markdown
{
    NSRange range = [object sourceRange];
    if (range.location == NSNotFound || NSMaxRange(range) > [markdown length]) {
        return nil;
    }
    return [markdown substringWithRange:range];
}

- (OMMarkdownRenderer *)externalMathRenderer
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
    return [[[OMMarkdownRenderer alloc] initWithTheme:nil parsingOptions:options] autorelease];
}

- (void)testInlineMathSourceRangeHandlesEscapesAndRepeats
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    NSString *markdown = @"Intro\n\nArea $x^2\\,dx$ then $a$ and $a$ again.\n";
    NSArray *objects = [self renderedObjectsInString:[[self externalMathRenderer] attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)3);
    if ([objects count] != 3) {
        return;
    }
    XCTAssertEqualObjects([self sourceTextOfObject:[objects objectAtIndex:0] inMarkdown:markdown], @"$x^2\\,dx$");
    NSRange first = [[objects objectAtIndex:1] sourceRange];
    NSRange second = [[objects objectAtIndex:2] sourceRange];
    XCTAssertEqualObjects([self sourceTextOfObject:[objects objectAtIndex:1] inMarkdown:markdown], @"$a$");
    XCTAssertEqualObjects([self sourceTextOfObject:[objects objectAtIndex:2] inMarkdown:markdown], @"$a$");
    XCTAssertTrue(second.location > first.location);
}

- (void)testDisplayMathSourceRangeCoversItsFence
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    NSString *markdown = @"Text\n\n$$\n\\frac{1}{2}\n$$\n\nMore";
    NSArray *objects = [self renderedObjectsInString:[[self externalMathRenderer] attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)1);
    XCTAssertEqualObjects([self sourceTextOfObject:[objects firstObject] inMarkdown:markdown], @"$$\n\\frac{1}{2}\n$$");
}

- (void)testMathCacheInvalidationStillRendersFormula
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    OMMarkdownRenderer *renderer = [self externalMathRenderer];
    NSTextAttachment *first = [self firstAttachmentInRenderedString:[renderer attributedStringFromMarkdown:@"$q^3$"]];
    NSTextAttachment *cached = [self firstAttachmentInRenderedString:[renderer attributedStringFromMarkdown:@"$q^3$"]];
    XCTAssertNotNil(first);
    XCTAssertTrue(first == cached, @"an unchanged formula should come from the cache");
    [OMMarkdownRenderer invalidateCachedMathForFormula:@"q^3"];
    NSTextAttachment *fresh = [self firstAttachmentInRenderedString:[renderer attributedStringFromMarkdown:@"$q^3$"]];
    XCTAssertNotNil(fresh);
    XCTAssertTrue(fresh != first, @"invalidation should force a new render");
}

- (void)testImageAndTableSourceRanges
{
    NSString *path = [self writeTemporaryImage];
    NSString *markdown = [NSString stringWithFormat:@"See ![one](%@) and ![two](%@ \"T\").\n\n| a | b |\n|---|---|\n| 1 | 2 |\n", path, path];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSArray *objects = [self renderedObjectsInString:[renderer attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)3);
    if ([objects count] == 3) {
        XCTAssertEqualObjects([self sourceTextOfObject:[objects objectAtIndex:0] inMarkdown:markdown],
                              ([NSString stringWithFormat:@"![one](%@)", path]));
        XCTAssertEqualObjects([self sourceTextOfObject:[objects objectAtIndex:1] inMarkdown:markdown],
                              ([NSString stringWithFormat:@"![two](%@ \"T\")", path]));
        XCTAssertEqualObjects([self sourceTextOfObject:[objects objectAtIndex:2] inMarkdown:markdown],
                              @"| a | b |\n|---|---|\n| 1 | 2 |");
    }
    [self removeFileIfPresent:path];
}

- (void)testInlineMathKeepsBackslashEscapesFromSource
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    NSString *markdown = @"# Heading $p\;q$\n\nArea $x^2\\,dx$, set $\\{a, b\\}$ and `$c\\,d$` code.\n\nInline display $$u\\!v$$ here.\n";
    NSArray *objects = [self renderedObjectsInString:[[self externalMathRenderer] attributedStringFromMarkdown:markdown]];
    XCTAssertEqual([objects count], (NSUInteger)4);
    if ([objects count] != 4) {
        return;
    }
    XCTAssertEqualObjects([[objects objectAtIndex:0] source], @"p\;q");
    XCTAssertEqualObjects([[objects objectAtIndex:1] source], @"x^2\\,dx");
    XCTAssertEqualObjects([[objects objectAtIndex:1] markdown], @"$x^2\\,dx$");
    XCTAssertEqualObjects([[objects objectAtIndex:2] source], @"\\{a, b\\}");
    XCTAssertEqual([[objects objectAtIndex:3] kind], OMRenderedObjectKindDisplayMath);
    XCTAssertEqualObjects([[objects objectAtIndex:3] source], @"u\\!v");
    XCTAssertEqualObjects([self sourceTextOfObject:[objects objectAtIndex:2] inMarkdown:markdown], @"$\\{a, b\\}$");
}

- (void)testInlineMathWithEntityFallsBackToParsedText
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    NSArray *objects = [self renderedObjectsInString:[[self externalMathRenderer] attributedStringFromMarkdown:@"Compare $a &lt; b$ now."]];
    XCTAssertEqual([objects count], (NSUInteger)1);
    XCTAssertEqualObjects([[objects firstObject] source], @"a < b");
}

// Rows of the first table's cells, read from its drawing cell.
- (NSArray *)tableRowsInRenderedString:(NSAttributedString *)rendered
{
    NSTextAttachment *attachment = [self firstAttachmentInRenderedString:rendered];
    id cell = [attachment attachmentCell];
    if (cell == nil) {
        return nil;
    }
    NSArray *attributedRows = nil;
    @try {
        attributedRows = [cell valueForKey:@"attributedRows"];
    } @catch (NSException *exception) {
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray *row in attributedRows) {
        NSMutableArray *cells = [NSMutableArray array];
        for (NSAttributedString *value in row) {
            [cells addObject:[[value string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }
        [rows addObject:cells];
    }
    return rows;
}

- (void)testTaskListItemsRenderCheckboxes
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *text = [[renderer attributedStringFromMarkdown:@"- [ ] open task\n- [x] done task\n- plain item\n"] string];
    XCTAssertTrue([text rangeOfString:@"☐ open task"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"☑ done task"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"\u2022 plain item"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"[x]"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"[ ]"].location == NSNotFound);
}

- (void)testFootnotesRenderAsSuperscriptAndNumberedNotes
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Claim[^src] and more[^two].\n\n[^two]: Second note.\n[^src]: First note.\n"];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"[^"].location == NSNotFound);
    NSRange reference = [text rangeOfString:@"Claim1"];
    XCTAssertTrue(reference.location != NSNotFound);
    if (reference.location != NSNotFound) {
        NSNumber *superscript = [rendered attribute:NSSuperscriptAttributeName atIndex:NSMaxRange(reference) - 1 effectiveRange:NULL];
        XCTAssertEqual([superscript intValue], 1);
    }
    NSRange first = [text rangeOfString:@"1. First note."];
    NSRange second = [text rangeOfString:@"2. Second note."];
    XCTAssertTrue(first.location != NSNotFound);
    XCTAssertTrue(second.location != NSNotFound);
    XCTAssertTrue(first.location < second.location);
}

- (void)testBareURLsBecomeLinks
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Visit https://commonmark.org/help or www.example.com today."];
    NSString *text = [rendered string];
    NSRange url = [text rangeOfString:@"https://commonmark.org/help"];
    NSRange www = [text rangeOfString:@"www.example.com"];
    XCTAssertTrue(url.location != NSNotFound && www.location != NSNotFound);
    if (url.location != NSNotFound && www.location != NSNotFound) {
        id link = [rendered attribute:NSLinkAttributeName atIndex:url.location effectiveRange:NULL];
        XCTAssertTrue([[link description] hasPrefix:@"https://commonmark.org/help"]);
        id wwwLink = [rendered attribute:NSLinkAttributeName atIndex:www.location effectiveRange:NULL];
        XCTAssertTrue([[wwwLink description] rangeOfString:@"www.example.com"].location != NSNotFound);
    }
}

- (void)testSingleTildeStrikethroughFollowsGFM
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Keep ~gone~ text."];
    XCTAssertTrue([[rendered string] rangeOfString:@"Keep gone text."].location != NSNotFound);
    XCTAssertTrue([self isStruckText:@"gone" inRenderedString:rendered]);
}

- (void)testTablesRenderInsideQuotesListsAndAfterParagraphs
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSArray *documents = [NSArray arrayWithObjects:
                          @"> | a | b |\n> |---|---|\n> | 1 | 2 |\n",
                          @"- item\n\n  | a | b |\n  |---|---|\n  | 1 | 2 |\n",
                          @"Intro line\n| a | b |\n|---|---|\n| 1 | 2 |\n",
                          nil];
    for (NSString *markdown in documents) {
        NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
        XCTAssertEqual([self attachmentCharacterCountInRenderedString:rendered], (NSUInteger)1, @"%@", markdown);
        NSArray *rows = [self tableRowsInRenderedString:rendered];
        XCTAssertEqualObjects(rows, ([NSArray arrayWithObjects:
                                      [NSArray arrayWithObjects:@"a", @"b", nil],
                                      [NSArray arrayWithObjects:@"1", @"2", nil], nil]), @"%@", markdown);
    }
}

- (void)testTableCellsKeepFormattingEscapesAndUnicode
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"| Name | Note |\n|:--|--:|\n| **bold** | a \\| b |\n| café über | 3 | extra |\n| short |\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSArray *rows = [self tableRowsInRenderedString:rendered];
    XCTAssertEqual([rows count], (NSUInteger)4);
    if ([rows count] == 4) {
        XCTAssertEqualObjects([rows objectAtIndex:1], ([NSArray arrayWithObjects:@"bold", @"a | b", nil]));
        XCTAssertEqualObjects([rows objectAtIndex:2], ([NSArray arrayWithObjects:@"café über", @"3", nil]));
        XCTAssertEqualObjects([rows objectAtIndex:3], ([NSArray arrayWithObjects:@"short", @"", nil]));
    }
    NSArray *attributedRows = [[[self firstAttachmentInRenderedString:rendered] attachmentCell] valueForKey:@"attributedRows"];
    NSAttributedString *boldCell = [[attributedRows objectAtIndex:1] objectAtIndex:0];
    NSRange bold = [[boldCell string] rangeOfString:@"bold"];
    NSFont *font = [boldCell attribute:NSFontAttributeName atIndex:bold.location effectiveRange:NULL];
    XCTAssertTrue(([[NSFontManager sharedFontManager] traitsOfFont:font] & NSBoldFontMask) != 0);
}

- (void)testHeadingAnchorsFollowGitHubSlugRules
{
    XCTAssertEqualObjects([OMMarkdownRenderer anchorSlugForHeadingTitle:@"Hello, World!"], @"hello-world");
    XCTAssertEqualObjects([OMMarkdownRenderer anchorSlugForHeadingTitle:@"foo-bar_baz 2.0"], @"foo-bar_baz-20");
    XCTAssertEqualObjects([OMMarkdownRenderer anchorSlugForHeadingTitle:@"Über Café"], @"über-café");
    XCTAssertEqualObjects([OMMarkdownRenderer anchorSlugForHeadingTitle:@"a  b"], @"a--b");
    XCTAssertEqualObjects([OMMarkdownRenderer anchorSlugForHeadingTitle:@"C++ & Objective-C"], @"c--objective-c");
}

- (void)testHeadingsListDeduplicatesAnchorsAndRecordsRanges
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"# Repeat\n\ntext\n\n## Repeat-1\n\n### Repeat\n\nSetext `Code` *em*\n---------\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSArray *headings = [renderer headings];
    XCTAssertEqual([headings count], (NSUInteger)4);
    if ([headings count] != 4) {
        return;
    }
    NSArray *expectedAnchors = [NSArray arrayWithObjects:@"repeat", @"repeat-1", @"repeat-2", @"setext-code-em", nil];
    NSArray *expectedLevels = [NSArray arrayWithObjects:@1, @2, @3, @2, nil];
    NSArray *expectedLines = [NSArray arrayWithObjects:@1, @5, @7, @9, nil];
    NSUInteger index = 0;
    for (; index < 4; index++) {
        NSDictionary *heading = [headings objectAtIndex:index];
        XCTAssertEqualObjects([heading objectForKey:OMMarkdownRendererHeadingAnchorKey], [expectedAnchors objectAtIndex:index]);
        XCTAssertEqualObjects([heading objectForKey:OMMarkdownRendererHeadingLevelKey], [expectedLevels objectAtIndex:index]);
        XCTAssertEqualObjects([heading objectForKey:OMMarkdownRendererHeadingSourceLineKey], [expectedLines objectAtIndex:index]);
        NSRange range = [[heading objectForKey:OMMarkdownRendererHeadingRangeKey] rangeValue];
        XCTAssertEqualObjects([[rendered string] substringWithRange:range], [heading objectForKey:OMMarkdownRendererHeadingTitleKey]);
        XCTAssertEqualObjects([rendered attribute:OMMarkdownRendererHeadingAnchorAttributeName atIndex:range.location effectiveRange:NULL],
                              [expectedAnchors objectAtIndex:index]);
    }
    XCTAssertEqualObjects([[headings lastObject] objectForKey:OMMarkdownRendererHeadingTitleKey], @"Setext Code em");
}

- (void)testFragmentLinksStayInTheDocument
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setBaseURL:[NSURL fileURLWithPath:@"/tmp/objcmarkdown-frag/" isDirectory:YES]];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil parsingOptions:options] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:
        @"See [setup](#setup), [café](#café-notes) and [other](other.md#usage).\n\n## Setup\n"];
    NSString *text = [rendered string];

    NSURL *setup = [rendered attribute:NSLinkAttributeName atIndex:[text rangeOfString:@"setup"].location effectiveRange:NULL];
    XCTAssertTrue([setup isKindOfClass:[NSURL class]]);
    XCTAssertNil([setup scheme]);
    XCTAssertEqualObjects([setup fragment], @"setup");
    XCTAssertEqual([[setup path] length], (NSUInteger)0);

    NSURL *cafe = [rendered attribute:NSLinkAttributeName atIndex:[text rangeOfString:@"café"].location effectiveRange:NULL];
    XCTAssertEqualObjects([[cafe fragment] stringByRemovingPercentEncoding], @"café-notes");

    NSURL *other = [rendered attribute:NSLinkAttributeName atIndex:[text rangeOfString:@"other"].location effectiveRange:NULL];
    XCTAssertTrue([other isFileURL]);
    XCTAssertEqualObjects([[other path] lastPathComponent], @"other.md");
    XCTAssertEqualObjects([other fragment], @"usage");
}

- (NSParagraphStyle *)paragraphStyleAtText:(NSString *)needle inRenderedString:(NSAttributedString *)rendered
{
    NSRange range = [[rendered string] rangeOfString:needle];
    if (range.location == NSNotFound) {
        return nil;
    }
    return [rendered attribute:NSParagraphStyleAttributeName atIndex:range.location effectiveRange:NULL];
}

- (void)testBlocksInsideListItemsAlignWithTheItemText
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"- first line  \n  after break\n\n  second paragraph\n\n  ```\n  code line\n  ```\n\n  | a | b |\n  |---|---|\n  | 1 | 2 |\n\nOutside paragraph\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];

    NSParagraphStyle *first = [self paragraphStyleAtText:@"first line" inRenderedString:rendered];
    CGFloat contentIndent = [first headIndent];
    XCTAssertTrue(contentIndent > [first firstLineHeadIndent], @"the bullet hangs left of the item text");

    NSParagraphStyle *afterBreak = [self paragraphStyleAtText:@"after break" inRenderedString:rendered];
    NSParagraphStyle *second = [self paragraphStyleAtText:@"second paragraph" inRenderedString:rendered];
    NSParagraphStyle *code = [self paragraphStyleAtText:@"code line" inRenderedString:rendered];
    XCTAssertEqualWithAccuracy([afterBreak firstLineHeadIndent], contentIndent, 0.5);
    XCTAssertEqualWithAccuracy([second firstLineHeadIndent], contentIndent, 0.5);
    XCTAssertEqualWithAccuracy([second headIndent], contentIndent, 0.5);
    XCTAssertTrue([code firstLineHeadIndent] > contentIndent, @"code sits inside the item, past its text edge");

    NSString *text = [rendered string];
    unichar attachment = NSAttachmentCharacter;
    NSRange table = [text rangeOfString:[NSString stringWithCharacters:&attachment length:1]];
    XCTAssertTrue(table.location != NSNotFound);
    if (table.location != NSNotFound) {
        NSParagraphStyle *tableStyle = [rendered attribute:NSParagraphStyleAttributeName atIndex:table.location effectiveRange:NULL];
        XCTAssertEqualWithAccuracy([tableStyle firstLineHeadIndent], contentIndent, 0.5);
    }

    NSParagraphStyle *outside = [self paragraphStyleAtText:@"Outside paragraph" inRenderedString:rendered];
    XCTAssertEqualWithAccuracy([outside firstLineHeadIndent], 0.0, 0.5);
}

- (void)testMermaidDiagramIsCentredAndFollowedByABlankLine
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"```mermaid\nerDiagram\n    A ||--o{ B : has\n```\n```\nnext block\n```\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSString *text = [rendered string];
    unichar attachmentCharacter = NSAttachmentCharacter;
    NSRange diagram = [text rangeOfString:[NSString stringWithCharacters:&attachmentCharacter length:1]];
    XCTAssertTrue(diagram.location != NSNotFound);
    if (diagram.location == NSNotFound) {
        return;
    }
    NSParagraphStyle *style = [rendered attribute:NSParagraphStyleAttributeName atIndex:diagram.location effectiveRange:NULL];
    XCTAssertEqual([style alignment], NSCenterTextAlignment);
    NSRange next = [text rangeOfString:@"next block"];
    XCTAssertTrue([[text substringWithRange:NSMakeRange(NSMaxRange(diagram), next.location - NSMaxRange(diagram))] hasPrefix:@"\n\n"]);
}

- (CGFloat)luminanceOfColor:(NSColor *)color
{
    NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return 0.2126 * [rgb redComponent] + 0.7152 * [rgb greenComponent] + 0.0722 * [rgb blueComponent];
}

- (void)testDarkThemeUsesGitHubDarkPalette
{
    OMTheme *light = [OMTheme defaultThemeForDarkAppearance:NO];
    OMTheme *dark = [OMTheme defaultThemeForDarkAppearance:YES];
    XCTAssertFalse([light isDark]);
    XCTAssertTrue([dark isDark]);
    XCTAssertTrue([self luminanceOfColor:[dark baseTextColor]] > 0.8);
    XCTAssertTrue([self luminanceOfColor:[dark codeBackgroundColor]] < 0.15);
    XCTAssertNotNil([dark codeBorderColor]);
    XCTAssertNotNil([light blockquoteTextColor]);
    XCTAssertTrue([self luminanceOfColor:[dark linkColor]] > [self luminanceOfColor:[light linkColor]]);
}

- (void)testQuotedTextUsesTheThemesMutedColour
{
    OMTheme *dark = [OMTheme defaultThemeForDarkAppearance:YES];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:dark] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"Plain text.\n\n> Quoted text.\n"];
    NSString *text = [rendered string];
    NSColor *plain = [rendered attribute:NSForegroundColorAttributeName atIndex:[text rangeOfString:@"Plain"].location effectiveRange:NULL];
    NSColor *quoted = [rendered attribute:NSForegroundColorAttributeName atIndex:[text rangeOfString:@"Quoted"].location effectiveRange:NULL];
    XCTAssertEqualObjects(quoted, [dark blockquoteTextColor]);
    XCTAssertFalse([quoted isEqual:plain]);
}

- (void)testDarkThemeMathIsDrawnInLightInkAndCachedApart
{
    if (!OMDMathToolchainAvailable()) {
        return;
    }
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
    OMMarkdownRenderer *light = [[[OMMarkdownRenderer alloc] initWithTheme:[OMTheme defaultThemeForDarkAppearance:NO]
                                                             parsingOptions:options] autorelease];
    OMMarkdownRenderer *dark = [[[OMMarkdownRenderer alloc] initWithTheme:[OMTheme defaultThemeForDarkAppearance:YES]
                                                            parsingOptions:options] autorelease];
    NSTextAttachment *lightMath = [self firstAttachmentInRenderedString:[light attributedStringFromMarkdown:@"$w_9$"]];
    NSTextAttachment *darkMath = [self firstAttachmentInRenderedString:[dark attributedStringFromMarkdown:@"$w_9$"]];
    XCTAssertNotNil(lightMath);
    XCTAssertNotNil(darkMath);
    XCTAssertTrue(lightMath != darkMath, @"light and dark renders must not share a cache entry");

    NSImage *image = [(NSCell *)[darkMath attachmentCell] image];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    CGFloat inkLuminance = 0.0;
    NSUInteger inked = 0;
    NSInteger x = 0;
    for (; x < [bitmap pixelsWide]; x++) {
        NSInteger y = 0;
        for (; y < [bitmap pixelsHigh]; y++) {
            NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if ([pixel alphaComponent] > 0.8) {
                inkLuminance += [self luminanceOfColor:pixel];
                inked += 1;
            }
        }
    }
    XCTAssertTrue(inked > 0);
    if (inked > 0) {
        XCTAssertTrue(inkLuminance / inked > 0.6, @"dark-theme math should be drawn in light ink");
    }
}

- (NSUInteger)countOfAttachmentsBeforeText:(NSString *)needle inRenderedString:(NSAttributedString *)rendered
{
    NSString *text = [rendered string];
    NSRange limit = [text rangeOfString:needle];
    NSUInteger count = 0;
    NSUInteger index = 0;
    for (; index < limit.location; index++) {
        if ([text characterAtIndex:index] == NSAttachmentCharacter) {
            count += 1;
        }
    }
    return count;
}

- (void)testBulletsChangeShapeWithDepth
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *text = [[renderer attributedStringFromMarkdown:@"- one\n  - two\n    - three\n"] string];
    XCTAssertTrue([text rangeOfString:@"• one"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"◦ two"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"▪ three"].location != NSNotFound);
}

- (void)testOnlyH1AndH2GetDrawnUnderlines
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:500.0];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"# One\n\nalpha\n\n## Two\n\nbeta\n\n### Three\n\ngamma\n\n---\n\ndelta\n"];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"─"].location == NSNotFound, @"rules are drawn, not typed");
    XCTAssertEqual([self countOfAttachmentsBeforeText:@"alpha" inRenderedString:rendered], (NSUInteger)1);
    XCTAssertEqual([self countOfAttachmentsBeforeText:@"beta" inRenderedString:rendered], (NSUInteger)2);
    XCTAssertEqual([self countOfAttachmentsBeforeText:@"gamma" inRenderedString:rendered], (NSUInteger)2);
    XCTAssertEqual([self countOfAttachmentsBeforeText:@"delta" inRenderedString:rendered], (NSUInteger)3);
    NSTextAttachment *rule = [self firstAttachmentInRenderedString:rendered];
    NSSize size = [[rule attachmentCell] cellSize];
    XCTAssertTrue(size.width > 400.0 && size.width <= 500.0);
    XCTAssertTrue(size.height <= 4.0);
}

- (void)testHeadingSizesFollowGitHubScale
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"# Big\n\n### Mid\n\nbody text\n"];
    NSString *text = [rendered string];
    CGFloat body = [[rendered attribute:NSFontAttributeName atIndex:[text rangeOfString:@"body"].location effectiveRange:NULL] pointSize];
    CGFloat h1 = [[rendered attribute:NSFontAttributeName atIndex:[text rangeOfString:@"Big"].location effectiveRange:NULL] pointSize];
    CGFloat h3 = [[rendered attribute:NSFontAttributeName atIndex:[text rangeOfString:@"Mid"].location effectiveRange:NULL] pointSize];
    XCTAssertEqualWithAccuracy(h1 / body, 2.0, 0.05);
    XCTAssertEqualWithAccuracy(h3 / body, 1.25, 0.05);
}

- (void)testBlockGapsAreTightButCodeBlankLinesKeepTheirHeight
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"First para.\n\nSecond para.\n\n```\nline one\n\nline three\n```\n"];
    NSString *text = [rendered string];
    NSUInteger gap = NSMaxRange([text rangeOfString:@"First para.\n"]);
    NSParagraphStyle *gapStyle = [rendered attribute:NSParagraphStyleAttributeName atIndex:gap effectiveRange:NULL];
    CGFloat body = [[rendered attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] pointSize];
    XCTAssertEqualWithAccuracy([gapStyle maximumLineHeight], body, 1.0, @"1em between paragraphs");

    NSUInteger beforeCode = NSMaxRange([text rangeOfString:@"Second para.\n"]);
    NSParagraphStyle *beforeCodeStyle = [rendered attribute:NSParagraphStyleAttributeName atIndex:beforeCode effectiveRange:NULL];
    XCTAssertTrue([beforeCodeStyle maximumLineHeight] > [gapStyle maximumLineHeight], @"room for the code background");

    NSUInteger codeBlank = NSMaxRange([text rangeOfString:@"line one\n"]);
    NSParagraphStyle *codeStyle = [rendered attribute:NSParagraphStyleAttributeName atIndex:codeBlank effectiveRange:NULL];
    XCTAssertTrue([codeStyle maximumLineHeight] == 0.0 || [codeStyle maximumLineHeight] > body, @"code keeps its blank line");

    NSParagraphStyle *paragraph = [rendered attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertEqualWithAccuracy([paragraph lineHeightMultiple], 1.5, 0.01);

    NSParagraphStyle *codeLine = [rendered attribute:NSParagraphStyleAttributeName
                                             atIndex:[text rangeOfString:@"line one"].location
                                      effectiveRange:NULL];
    XCTAssertEqualWithAccuracy([codeLine firstLineHeadIndent], 20.0, 0.5, @"code text is padded inside a background flush with body text");
}

- (void)testGitHubAlertsRenderTitleAndColouredBar
{
    OMTheme *theme = [OMTheme defaultThemeForDarkAppearance:NO];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:theme] autorelease];
    NSString *markdown = @"> [!NOTE]\n> Useful information.\n\n> [!warning]\n> Careful here.\n\n> [!TIP] not alone on the line\n\n> Plain quote.\n";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"[!NOTE]"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"[!warning]"].location == NSNotFound);
    XCTAssertTrue([text rangeOfString:@"Note\nUseful information."].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"Warning\nCareful here."].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"[!TIP] not alone on the line"].location != NSNotFound, @"the marker must stand alone");

    NSUInteger body = [text rangeOfString:@"Useful"].location;
    NSUInteger plain = [text rangeOfString:@"Plain quote"].location;
    XCTAssertEqualObjects([rendered attribute:NSForegroundColorAttributeName atIndex:body effectiveRange:NULL], [theme baseTextColor]);
    XCTAssertEqualObjects([rendered attribute:NSForegroundColorAttributeName atIndex:plain effectiveRange:NULL], [theme blockquoteTextColor]);

    NSColor *noteBar = [rendered attribute:OMMarkdownRendererBlockquoteColorAttributeName atIndex:body effectiveRange:NULL];
    NSColor *warningBar = [rendered attribute:OMMarkdownRendererBlockquoteColorAttributeName
                                      atIndex:[text rangeOfString:@"Careful"].location
                               effectiveRange:NULL];
    XCTAssertNotNil(noteBar);
    XCTAssertNotNil(warningBar);
    XCTAssertFalse([noteBar isEqual:warningBar]);
    XCTAssertNil([rendered attribute:OMMarkdownRendererBlockquoteColorAttributeName atIndex:plain effectiveRange:NULL]);

    NSUInteger title = [text rangeOfString:@"Note\n"].location;
    XCTAssertEqualObjects([rendered attribute:NSForegroundColorAttributeName atIndex:title effectiveRange:NULL], noteBar);
}

- (void)testAlertMarkerInsideANestedQuote
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *text = [[renderer attributedStringFromMarkdown:@"> outer\n>\n> > [!CAUTION]\n> > Inner alert.\n"] string];
    XCTAssertTrue([text rangeOfString:@"Caution\nInner alert."].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"outer"].location != NSNotFound);
}

- (void)testRangesOfBlocksEndingTheDocumentStayInsideTheText
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSUInteger length = [[renderer attributedStringFromMarkdown:@"Intro\n\n> Last quote.\n"] length];
    NSArray *quotes = [renderer blockquoteRanges];
    XCTAssertEqual([quotes count], (NSUInteger)1);
    XCTAssertTrue(NSMaxRange([[quotes firstObject] rangeValue]) <= length);

    length = [[renderer attributedStringFromMarkdown:@"Intro\n\n```\ncode\n```\n"] length];
    NSArray *code = [renderer codeBlockRanges];
    XCTAssertEqual([code count], (NSUInteger)1);
    XCTAssertTrue(NSMaxRange([[code firstObject] rangeValue]) <= length);
}

@end
