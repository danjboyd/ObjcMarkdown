// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDOutlineController.h"
#import "OMMarkdownRenderer.h"

@interface OMDOutlineControllerTests : XCTestCase <OMDOutlineControllerDelegate>
{
    NSDictionary *_chosenHeading;
}
@end

@implementation OMDOutlineControllerTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (void)tearDown
{
    [_chosenHeading release];
    _chosenHeading = nil;
    [super tearDown];
}

- (void)outlineController:(OMDOutlineController *)controller didChooseHeading:(NSDictionary *)heading
{
    [_chosenHeading release];
    _chosenHeading = [heading retain];
}

- (NSArray *)headingsForMarkdown:(NSString *)markdown
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer attributedStringFromMarkdown:markdown];
    return [renderer headings];
}

- (NSString *)sampleMarkdown
{
    return @"Intro\n\n## Setup\n\ntext\n\n### Details\n\nmore\n\n## Usage\n\nend\n";
}

- (void)testSectionLookupUsesLastHeadingAtOrBeforeLocation
{
    NSArray *headings = [self headingsForMarkdown:[self sampleMarkdown]];
    XCTAssertEqual([headings count], (NSUInteger)3);
    NSRange details = [[[headings objectAtIndex:1] objectForKey:OMMarkdownRendererHeadingRangeKey] rangeValue];
    XCTAssertEqual([OMDOutlineController headingIndexForRenderedLocation:0 inHeadings:headings], (NSInteger)-1);
    XCTAssertEqual([OMDOutlineController headingIndexForRenderedLocation:details.location inHeadings:headings], (NSInteger)1);
    XCTAssertEqual([OMDOutlineController headingIndexForRenderedLocation:details.location - 1 inHeadings:headings], (NSInteger)0);
    XCTAssertEqual([OMDOutlineController headingIndexForRenderedLocation:100000 inHeadings:headings], (NSInteger)2);

    XCTAssertEqual([OMDOutlineController headingIndexForSourceLine:1 inHeadings:headings], (NSInteger)-1);
    XCTAssertEqual([OMDOutlineController headingIndexForSourceLine:3 inHeadings:headings], (NSInteger)0);
    XCTAssertEqual([OMDOutlineController headingIndexForSourceLine:9 inHeadings:headings], (NSInteger)1);
    XCTAssertEqual([OMDOutlineController headingIndexForSourceLine:11 inHeadings:headings], (NSInteger)2);
}

- (void)testRowsIndentByLevelRelativeToTheTopLevel
{
    OMDOutlineController *controller = [[[OMDOutlineController alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 300.0)] autorelease];
    [controller setHeadings:[self headingsForMarkdown:[self sampleMarkdown]]];
    NSTableView *table = (NSTableView *)[(NSScrollView *)[[[controller view] subviews] objectAtIndex:1] documentView];
    XCTAssertTrue([table isKindOfClass:[NSTableView class]]);
    XCTAssertEqual([controller numberOfRowsInTableView:table], (NSInteger)3);

    NSAttributedString *setup = [controller tableView:table objectValueForTableColumn:nil row:0];
    NSAttributedString *details = [controller tableView:table objectValueForTableColumn:nil row:1];
    XCTAssertEqualObjects([setup string], @"Setup");
    NSParagraphStyle *setupStyle = [setup attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    NSParagraphStyle *detailsStyle = [details attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertTrue([detailsStyle firstLineHeadIndent] > [setupStyle firstLineHeadIndent]);
    // Top-level rows in the theme's bold system font, others in its regular
    // one. (A theme's bold needn't carry NSBoldFontMask: WinUI's is Semibold.)
    NSFont *setupFont = [setup attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    NSFont *detailsFont = [details attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertEqualObjects([setupFont fontName], [[NSFont boldSystemFontOfSize:[setupFont pointSize]] fontName]);
    XCTAssertEqualObjects([detailsFont fontName], [[NSFont systemFontOfSize:[detailsFont pointSize]] fontName]);
}

- (void)testChoosingARowNotifiesDelegateButSettingCurrentDoesNot
{
    OMDOutlineController *controller = [[[OMDOutlineController alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 300.0)] autorelease];
    [controller setDelegate:self];
    NSArray *headings = [self headingsForMarkdown:[self sampleMarkdown]];
    [controller setHeadings:headings];

    [controller setCurrentHeadingIndex:2];
    XCTAssertEqual([controller currentHeadingIndex], (NSInteger)2);
    XCTAssertNil(_chosenHeading);

    NSTableView *table = (NSTableView *)[(NSScrollView *)[[[controller view] subviews] objectAtIndex:1] documentView];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [controller performSelector:@selector(rowClicked:) withObject:table];
    XCTAssertEqualObjects(_chosenHeading, [headings objectAtIndex:1]);
    XCTAssertEqual([controller currentHeadingIndex], (NSInteger)1);

    [controller setHeadings:[NSArray array]];
    XCTAssertEqual([controller currentHeadingIndex], (NSInteger)-1);
}

@end
