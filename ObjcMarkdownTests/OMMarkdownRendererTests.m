// ObjcMarkdownTests
// SPDX-License-Identifier: Apache-2.0

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import "OMMarkdownRenderer.h"

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

- (NSTextTableBlock *)tableBlockInRenderedString:(NSAttributedString *)rendered
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
    NSParagraphStyle *style = [attrs objectForKey:NSParagraphStyleAttributeName];
    if (style == nil || ![style respondsToSelector:@selector(textBlocks)]) {
        return nil;
    }
    NSArray *blocks = [(id)style textBlocks];
    if ([blocks count] == 0) {
        return nil;
    }
    id block = [blocks objectAtIndex:0];
    if ([block isKindOfClass:[NSTextTableBlock class]]) {
        return (NSTextTableBlock *)block;
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

- (void)testPipeTableRendersAsStructuredMultilineContent
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    NSString *markdown = @"| Name | Value |\n| ---- | ----: |\n| alpha | 1 |\n| beta | 23 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"Name"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"Value"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"alpha"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"23"].location != NSNotFound);
}

- (void)testPipeTableUsesTextTableBlocksForHeaderAndBodyCells
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:1200.0];
    NSString *markdown = @"| Name | Value |\n| ---- | ----: |\n| alpha | 1 |\n| beta | 23 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSTextTableBlock *headerBlock = [self tableBlockInRenderedString:rendered forVisibleText:@"Name"];
    XCTAssertNotNil(headerBlock);
    if (headerBlock != nil) {
        XCTAssertEqual([headerBlock startingRow], (int)0);
        XCTAssertEqual([headerBlock startingColumn], (int)0);
    }

    NSTextTableBlock *bodyBlock = [self tableBlockInRenderedString:rendered forVisibleText:@"beta"];
    XCTAssertNotNil(bodyBlock);
    if (bodyBlock != nil) {
        XCTAssertTrue([bodyBlock startingRow] > [headerBlock startingRow]);
        XCTAssertEqual([bodyBlock startingColumn], (int)0);
    }
}

- (void)testPipeTableKeepsBaseBodyFontFamily
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:1200.0];
    NSString *markdown = @"Paragraph.\n\n| Name | Value |\n| ---- | ----: |\n| alpha | 1 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange paragraphRange = [text rangeOfString:@"Paragraph"];
    NSRange cellRange = [text rangeOfString:@"alpha"];
    XCTAssertTrue(paragraphRange.location != NSNotFound);
    XCTAssertTrue(cellRange.location != NSNotFound);
    if (paragraphRange.location == NSNotFound || cellRange.location == NSNotFound) {
        return;
    }

    NSDictionary *paragraphAttrs = [rendered attributesAtIndex:paragraphRange.location effectiveRange:NULL];
    NSDictionary *cellAttrs = [rendered attributesAtIndex:cellRange.location effectiveRange:NULL];
    NSFont *paragraphFont = [paragraphAttrs objectForKey:NSFontAttributeName];
    NSFont *cellFont = [cellAttrs objectForKey:NSFontAttributeName];
    XCTAssertNotNil(paragraphFont);
    XCTAssertNotNil(cellFont);
    if (paragraphFont != nil && cellFont != nil) {
        XCTAssertEqualObjects([cellFont familyName], [paragraphFont familyName]);
    }
}

- (void)testPipeTableFallsBackToStackedLayoutInNarrowPreview
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:200.0];
    NSString *markdown = @"| Area | Notes |\n| --- | --- |\n| Parsing | Handles standard pipe table delimiter row and alignment markers. |\n| Rendering | Output should stay column-aligned and legible on dark theme. |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    XCTAssertTrue([text rangeOfString:@"Row 1"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"Area: Parsing"].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:@"Notes: Handles standard pipe table delimiter row"].location != NSNotFound);
}

- (void)testPipeTableKeepsGridLayoutAtComfortablePreviewWidth
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:900.0];
    NSString *markdown = @"| Area | Notes | Status |\n| :--- | :---- | ----: |\n| Parsing | Handles delimiter rows. | 100 |\n| Rendering | Should remain structured. | 95 |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSTextTableBlock *block = [self tableBlockInRenderedString:rendered forVisibleText:@"Parsing"];
    XCTAssertNotNil(block);
    if (block != nil) {
        XCTAssertEqual([block startingRow], (int)1);
    }
}

- (void)testPipeTableCellInlineLinkRendersAsLinkAttribute
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:1200.0];
    NSString *markdown = @"| Label | Link |\n| --- | --- |\n| Repo | [ObjcMarkdown](https://github.com/) |";
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    XCTAssertNotNil(rendered);

    NSString *text = [rendered string];
    NSRange linkRange = [text rangeOfString:@"ObjcMarkdown"];
    XCTAssertTrue(linkRange.location != NSNotFound);
    if (linkRange.location != NSNotFound) {
        NSDictionary *attrs = [rendered attributesAtIndex:linkRange.location effectiveRange:NULL];
        NSURL *linkURL = [attrs objectForKey:NSLinkAttributeName];
        XCTAssertNotNil(linkURL);
        if (linkURL != nil) {
            XCTAssertEqualObjects([[linkURL scheme] lowercaseString], @"https");
        }
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
        NSRange formulaRange = [text rangeOfString:@"\\int_0^1 x^2 dx"];
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
        NSRange formulaRange = [text rangeOfString:@"\\int_0^1 x^2 dx"];
        XCTAssertTrue(formulaRange.location != NSNotFound);
        if (formulaRange.location != NSNotFound) {
            NSDictionary *formulaAttrs = [rendered attributesAtIndex:formulaRange.location effectiveRange:NULL];
            NSColor *background = [formulaAttrs objectForKey:NSBackgroundColorAttributeName];
            XCTAssertNotNil(background);
        }
    }
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
