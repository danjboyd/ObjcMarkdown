// ObjcMarkdownTests
// SPDX-License-Identifier: Apache-2.0

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
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
