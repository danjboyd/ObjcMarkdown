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

@end
