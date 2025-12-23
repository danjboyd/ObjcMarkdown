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

@end
