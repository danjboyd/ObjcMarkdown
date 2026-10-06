// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDDocumentTabsController.h"
#import "OMTestPaths.h"

@interface OMDDocumentTabsControllerTests : XCTestCase <OMDDocumentTabsControllerDelegate>
{
    NSInteger _selectedIndex;
    NSInteger _closedIndex;
}
@end

@implementation OMDDocumentTabsControllerTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
    _selectedIndex = -1;
    _closedIndex = -1;
}

- (OMDLayoutDensityMode)effectiveLayoutDensityMode
{
    return OMDLayoutDensityModeAdwaita;
}

- (void)selectDocumentTabAtIndex:(NSInteger)index
{
    _selectedIndex = index;
}

- (void)closeDocumentTabAtIndex:(NSInteger)index
{
    _closedIndex = index;
}

- (NSMutableDictionary *)tabWithPath:(NSString *)path
{
    return [NSMutableDictionary dictionaryWithObject:path forKey:OMDTabSourcePathKey];
}

// The tab buttons in the strip, in order (each tab is a container holding
// its title button and its close button).
- (NSArray *)buttonsInStrip:(NSView *)strip closeButtons:(BOOL)closeButtons
{
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSView *container in [strip subviews]) {
        for (NSView *view in [container subviews]) {
            if (![view isKindOfClass:[NSButton class]]) {
                continue;
            }
            BOOL isClose = [[(NSButton *)view title] isEqualToString:@"x"];
            if (isClose == closeButtons) {
                [buttons addObject:view];
            }
        }
    }
    return buttons;
}

- (void)testSelectionStartsEmptyAndFollowsTheIndex
{
    OMDDocumentTabsController *tabs = [[[OMDDocumentTabsController alloc] initWithDelegate:self] autorelease];
    XCTAssertEqual([tabs selectedIndex], (NSInteger)-1);
    XCTAssertNil([tabs selectedTab]);

    [tabs addTab:[self tabWithPath:@"/tmp/a.md"]];
    [tabs addTab:[self tabWithPath:@"/tmp/b.md"]];
    [tabs setSelectedIndex:1];
    XCTAssertEqualObjects([[tabs selectedTab] objectForKey:OMDTabSourcePathKey], @"/tmp/b.md");

    [tabs replaceTabAtIndex:1 withTab:[self tabWithPath:@"/tmp/c.md"]];
    XCTAssertEqualObjects([[tabs selectedTab] objectForKey:OMDTabSourcePathKey], @"/tmp/c.md");

    [tabs removeTabAtIndex:1];
    XCTAssertEqual([tabs count], (NSUInteger)1);
    XCTAssertNil([tabs selectedTab]);
}

- (void)testLocalPathLookupStandardizesPaths
{
    OMDDocumentTabsController *tabs = [[[OMDDocumentTabsController alloc] initWithDelegate:self] autorelease];
    [tabs addTab:[self tabWithPath:OMTestAbsolutePath(@"/tmp/docs/a.md")]];
    [tabs addTab:[self tabWithPath:OMTestAbsolutePath(@"/tmp/docs/b.md")]];
    XCTAssertEqual([tabs documentTabIndexForLocalPath:OMTestAbsolutePath(@"/tmp/docs/../docs/b.md")], (NSInteger)1);
    XCTAssertEqual([tabs documentTabIndexForLocalPath:OMTestAbsolutePath(@"/tmp/docs/c.md")], (NSInteger)-1);
    XCTAssertEqual([tabs documentTabIndexForLocalPath:@" "], (NSInteger)-1);
}

- (void)testStripShowsOnlyWithTwoOrMoreTabs
{
    OMDDocumentTabsController *tabs = [[[OMDDocumentTabsController alloc] initWithDelegate:self] autorelease];
    [tabs addTab:[self tabWithPath:@"/tmp/a.md"]];
    XCTAssertEqual([tabs currentTabStripHeight], (CGFloat)0.0);
    [tabs addTab:[self tabWithPath:@"/tmp/b.md"]];
    CGFloat expected = OMDLayoutMetricsForMode(OMDLayoutDensityModeAdwaita).tabStripHeight;
    XCTAssertEqual([tabs currentTabStripHeight], expected);
}

- (void)testStripButtonsShowStateAndReportToTheDelegate
{
    OMDDocumentTabsController *tabs = [[[OMDDocumentTabsController alloc] initWithDelegate:self] autorelease];
    NSMutableDictionary *dirty = [self tabWithPath:@"/tmp/b.md"];
    [dirty setObject:[NSNumber numberWithBool:YES] forKey:OMDTabDirtyKey];
    NSMutableDictionary *readOnly = [self tabWithPath:@"/tmp/c.md"];
    [readOnly setObject:@"Notes" forKey:OMDTabDisplayTitleKey];
    [readOnly setObject:[NSNumber numberWithBool:YES] forKey:OMDTabReadOnlyKey];
    [tabs addTab:[self tabWithPath:@"/tmp/a.md"]];
    [tabs addTab:dirty];
    [tabs addTab:readOnly];
    [tabs setSelectedIndex:1];

    [[tabs stripView] setFrame:NSMakeRect(0.0, 0.0, 900.0, [tabs currentTabStripHeight])];
    [tabs updateTabStrip];

    NSArray *titleButtons = [self buttonsInStrip:[tabs stripView] closeButtons:NO];
    NSArray *closeButtons = [self buttonsInStrip:[tabs stripView] closeButtons:YES];
    XCTAssertEqual([titleButtons count], (NSUInteger)3);
    XCTAssertEqual([closeButtons count], (NSUInteger)3);
    if ([titleButtons count] != 3 || [closeButtons count] != 3) {
        return;
    }
    XCTAssertEqualObjects([[titleButtons objectAtIndex:0] title], @"a.md");
    XCTAssertEqualObjects([[titleButtons objectAtIndex:1] title], @"b.md *");
    XCTAssertEqualObjects([[titleButtons objectAtIndex:2] title], @"Notes [RO]");
    XCTAssertEqual([[titleButtons objectAtIndex:1] state], (NSInteger)NSOnState);
    XCTAssertEqual([[titleButtons objectAtIndex:0] state], (NSInteger)NSOffState);

    [[titleButtons objectAtIndex:2] performClick:nil];
    XCTAssertEqual(_selectedIndex, (NSInteger)2);
    [[closeButtons objectAtIndex:0] performClick:nil];
    XCTAssertEqual(_closedIndex, (NSInteger)0);
}

@end
