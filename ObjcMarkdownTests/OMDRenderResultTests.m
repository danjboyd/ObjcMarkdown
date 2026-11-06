// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDRenderResult.h"
#import "OMMarkdownRenderer.h"

@interface OMDRenderResultTests : XCTestCase
@end

@implementation OMDRenderResultTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (NSArray *)documents
{
    NSMutableArray *documents = [NSMutableArray array];
    NSString *specDir = [NSString stringWithUTF8String:OM_SPEC_DIR];
    for (NSString *name in [NSArray arrayWithObjects:@"spec.txt", @"extensions.txt", nil]) {
        NSString *text = [NSString stringWithContentsOfFile:[specDir stringByAppendingPathComponent:name]
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
        XCTAssertNotNil(text, @"%@ not found under %@", name, specDir);
        if (text != nil) {
            [documents addObject:text];
        }
    }
    NSMutableString *sections = [NSMutableString stringWithString:@"# Title\n\n- [ ] open task\n- [x] done task\n\n"
                                  "> [!NOTE]\n> An alert.\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\n"];
    NSUInteger index = 1;
    for (; index <= 40; index++) {
        [sections appendFormat:@"## Section %lu\n\nA paragraph with **bold**, _emphasis_, `code` and a [link](#section-1).\n\n"
                                "| Item | Value |\n|---|---|\n| Alpha | %lu |\n\n```objc\nNSLog(@\"%lu\");\n```\n\n> A quote.\n\n",
                                (unsigned long)index, (unsigned long)index, (unsigned long)index];
    }
    [documents addObject:sections];
    return documents;
}

// A result holds exactly what the renderer's last render produced (#346),
// so the viewer reading it instead of the renderer changes nothing.
- (void)testResultHoldsTheRenderersOutputs
{
    for (NSString *markdown in [self documents]) {
        OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
        [renderer setLayoutWidth:640.0];
        [renderer setZoomScale:1.25];
        [renderer setInteractiveTaskItems:YES];
        [renderer attributedStringFromMarkdown:markdown];
        OMDRenderResult *result = [OMDRenderResult resultOfRenderer:renderer markdown:markdown sourceRevision:7];

        XCTAssertEqualObjects([result blockAnchors], [renderer blockAnchors]);
        XCTAssertEqualObjects([result codeBlockRanges], [renderer codeBlockRanges]);
        XCTAssertEqualObjects([result blockquoteRanges], [renderer blockquoteRanges]);
        XCTAssertEqualObjects([result diagramBlocks], [renderer diagramBlocks]);
        XCTAssertEqualObjects([result headings], [renderer headings]);
        XCTAssertEqualObjects([result taskItems], [renderer taskItems]);
        if ([renderer respondsToSelector:@selector(sourceBlockDescriptors)]) {
            XCTAssertEqualObjects([result sourceBlockDescriptors],
                                  [renderer performSelector:@selector(sourceBlockDescriptors)]);
        }
        XCTAssertEqual([result zoomScale], 1.25);
        XCTAssertEqual([result layoutWidth], 640.0);
        XCTAssertEqual([result sourceRevision], (NSUInteger)7);
        XCTAssertEqualObjects([result markdown], markdown);
        XCTAssertTrue([[result blockAnchors] count] > 10);
        XCTAssertTrue([[result headings] count] > 0);
    }
}

// The last of these has task items, a diagram and an alert: check they
// came through, so the comparison above covers them.
- (void)testResultCoversEveryKindOfOutput
{
    NSString *markdown = [[self documents] lastObject];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer attributedStringFromMarkdown:markdown];
    OMDRenderResult *result = [OMDRenderResult resultOfRenderer:renderer markdown:markdown sourceRevision:0];
    XCTAssertEqual([[result taskItems] count], (NSUInteger)2);
    XCTAssertEqual([[result codeBlockRanges] count], (NSUInteger)40);
    XCTAssertTrue([[result blockquoteRanges] count] >= 40);
    XCTAssertEqual([[result headings] count], (NSUInteger)41);
#if !defined(GNUSTEP)
    XCTAssertEqual([[result diagramBlocks] count], (NSUInteger)1);
#endif
}

// A result doesn't change when its renderer renders something else.
- (void)testResultOutlivesTheNextRender
{
    NSArray *documents = [self documents];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer attributedStringFromMarkdown:[documents lastObject]];
    OMDRenderResult *result = [OMDRenderResult resultOfRenderer:renderer markdown:[documents lastObject] sourceRevision:1];
    NSArray *anchors = [[[result blockAnchors] copy] autorelease];
    NSArray *headings = [[[result headings] copy] autorelease];
    NSArray *tasks = [[[result taskItems] copy] autorelease];

    [renderer attributedStringFromMarkdown:@"# Something else\n\nEntirely.\n"];
    XCTAssertFalse([[renderer blockAnchors] isEqual:anchors]);
    XCTAssertEqualObjects([result blockAnchors], anchors);
    XCTAssertEqualObjects([result headings], headings);
    XCTAssertEqualObjects([result taskItems], tasks);
}

@end
