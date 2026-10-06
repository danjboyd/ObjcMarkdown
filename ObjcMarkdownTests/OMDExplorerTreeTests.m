// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDExplorerTree.h"

@interface OMDExplorerTreeTests : XCTestCase
{
    NSString *_base;
}
@end

@implementation OMDExplorerTreeTests

- (void)setUp
{
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"omd-explorer-tree-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    _base = [[[NSTemporaryDirectory() stringByAppendingPathComponent:name] stringByStandardizingPath] retain];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *folder in [NSArray arrayWithObjects:@"docs/guide", @"Assets", @".github", nil]) {
        [fileManager createDirectoryAtPath:[_base stringByAppendingPathComponent:folder]
               withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    for (NSString *file in [NSArray arrayWithObjects:@"README.md", @"b.txt", @"Notes.docx", @"a.MD",
                                                     @".hidden.md", @"docs/guide/intro.md", nil]) {
        [@"x" writeToFile:[_base stringByAppendingPathComponent:file]
               atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:_base error:NULL];
    [_base release];
    _base = nil;
    [super tearDown];
}

- (OMDExplorerNode *)root
{
    return [[[OMDExplorerNode alloc] initWithPath:_base isDirectory:YES parent:nil] autorelease];
}

- (NSArray *)names:(NSArray *)nodes
{
    NSMutableArray *names = [NSMutableArray array];
    for (OMDExplorerNode *node in nodes) {
        [names addObject:[node name]];
    }
    return names;
}

- (void)testFoldersComeFirstThenFilesInCaseInsensitiveOrder
{
    NSArray *expected = [NSArray arrayWithObjects:@"Assets", @"docs", @"a.MD", @"b.txt", @"Notes.docx", @"README.md", nil];
    XCTAssertEqualObjects([self names:[[self root] childrenShowingHidden:NO]], expected);
}

- (void)testHiddenEntriesShowOnlyWhenAsked
{
    OMDExplorerNode *root = [self root];
    NSArray *shown = [self names:[root childrenShowingHidden:YES]];
    XCTAssertTrue([shown containsObject:@".github"]);
    XCTAssertTrue([shown containsObject:@".hidden.md"]);
    XCTAssertFalse([[self names:[root childrenShowingHidden:NO]] containsObject:@".hidden.md"]);
    // The same nodes either way.
    OMDExplorerNode *assets = [[root childrenShowingHidden:NO] objectAtIndex:0];
    XCTAssertEqualObjects([assets name], @"Assets");
    XCTAssertTrue([[root childrenShowingHidden:YES] indexOfObjectIdenticalTo:assets] != NSNotFound);
}

- (void)testFileKinds
{
    XCTAssertEqual(OMDExplorerFileKindForPath(@"/x/docs", YES), OMDExplorerFileKindFolder);
    XCTAssertEqual(OMDExplorerFileKindForPath(@"/x/a.MD", NO), OMDExplorerFileKindMarkdown);
    XCTAssertEqual(OMDExplorerFileKindForPath(@"/x/Notes.docx", NO), OMDExplorerFileKindImportable);
    XCTAssertEqual(OMDExplorerFileKindForPath(@"/x/b.txt", NO), OMDExplorerFileKindOther);
}

- (void)testChildrenAreReadOnceAndOnlyForFolders
{
    OMDExplorerNode *root = [self root];
    XCTAssertFalse([root hasLoadedChildren]);
    NSArray *first = [root childrenShowingHidden:NO];
    XCTAssertTrue([root hasLoadedChildren]);
    [@"x" writeToFile:[_base stringByAppendingPathComponent:@"later.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertEqualObjects([root childrenShowingHidden:NO], first);

    OMDExplorerNode *readme = [root descendantForPath:[_base stringByAppendingPathComponent:@"README.md"]];
    XCTAssertEqual([[readme childrenShowingHidden:YES] count], (NSUInteger)0);
}

- (void)testReloadFindsChangesAndKeepsTheNodesStillThere
{
    OMDExplorerNode *root = [self root];
    OMDExplorerNode *docs = [root descendantForPath:[_base stringByAppendingPathComponent:@"docs"]];
    OMDExplorerNode *guide = [docs descendantForPath:[_base stringByAppendingPathComponent:@"docs/guide"]];
    [guide childrenShowingHidden:NO];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:[_base stringByAppendingPathComponent:@"b.txt"] error:NULL];
    [@"x" writeToFile:[_base stringByAppendingPathComponent:@"docs/guide/next.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [root reloadChildren];

    XCTAssertFalse([[self names:[root childrenShowingHidden:NO]] containsObject:@"b.txt"]);
    XCTAssertTrue([root descendantForPath:[_base stringByAppendingPathComponent:@"docs"]] == docs);
    XCTAssertTrue([[self names:[guide childrenShowingHidden:NO]] containsObject:@"next.md"]);
}

- (void)testDescendantForPath
{
    OMDExplorerNode *root = [self root];
    OMDExplorerNode *intro = [root descendantForPath:[_base stringByAppendingPathComponent:@"docs/guide/intro.md"]];
    XCTAssertEqualObjects([intro name], @"intro.md");
    XCTAssertEqualObjects([[[intro parent] parent] name], @"docs");
    XCTAssertTrue([root descendantForPath:_base] == root);
    XCTAssertNotNil([root descendantForPath:[_base stringByAppendingPathComponent:@".hidden.md"]]);
    XCTAssertNil([root descendantForPath:[_base stringByAppendingPathComponent:@"missing.md"]]);
    XCTAssertNil([root descendantForPath:@"/elsewhere/README.md"]);
    XCTAssertNil([root descendantForPath:[_base stringByAppendingString:@"-sibling/a.md"]]);
}

- (void)testNamesMatchIgnoringCase
{
    XCTAssertTrue(OMDExplorerNameMatchesFilter(@"README.md", @"read"));
    XCTAssertTrue(OMDExplorerNameMatchesFilter(@"README.md", @""));
    XCTAssertFalse(OMDExplorerNameMatchesFilter(@"README.md", @"guide"));
}

- (NSArray *)relative:(NSArray *)paths
{
    NSMutableArray *relative = [NSMutableArray array];
    for (NSString *path in paths) {
        [relative addObject:[path substringFromIndex:[_base length] + 1]];
    }
    return relative;
}

- (void)testFindFilesByNameAcrossFolders
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[_base stringByAppendingPathComponent:@".git/refs"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"x" writeToFile:[_base stringByAppendingPathComponent:@".git/intro.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    BOOL complete = NO;
    NSArray *found = OMDExplorerFindFiles(_base, @"INTRO", YES, NO, 1000, 1000, &complete);
    XCTAssertTrue(complete);
    // .git is never searched, even with hidden files shown.
    XCTAssertEqualObjects([self relative:found], [NSArray arrayWithObject:@"docs/guide/intro.md"]);
}

- (void)testFindFilesMarkdownOnlyAndHidden
{
    BOOL complete = NO;
    NSArray *visible = OMDExplorerFindFiles(_base, @"", NO, YES, 1000, 1000, &complete);
    XCTAssertEqualObjects([self relative:visible],
                          ([NSArray arrayWithObjects:@"a.MD", @"README.md", @"docs/guide/intro.md", nil]));
    NSArray *withHidden = OMDExplorerFindFiles(_base, @".hidden", YES, YES, 1000, 1000, &complete);
    XCTAssertEqualObjects([self relative:withHidden], [NSArray arrayWithObject:@".hidden.md"]);
    XCTAssertEqual([OMDExplorerFindFiles(_base, @"docx", NO, YES, 1000, 1000, &complete) count], (NSUInteger)0);
}

- (void)testFindFilesStopsAtItsLimits
{
    BOOL complete = YES;
    NSArray *found = OMDExplorerFindFiles(_base, @"", NO, NO, 1000, 2, &complete);
    XCTAssertEqual([found count], (NSUInteger)2);
    XCTAssertFalse(complete);
    complete = YES;
    OMDExplorerFindFiles(_base, @"intro", NO, NO, 3, 1000, &complete);
    XCTAssertFalse(complete);
}

- (void)testVisiblePathsAreTheFilesAndTheFoldersAboveThem
{
    NSArray *files = [NSArray arrayWithObjects:[_base stringByAppendingPathComponent:@"docs/guide/intro.md"],
                                               [_base stringByAppendingPathComponent:@"README.md"],
                                               @"/elsewhere/x.md", nil];
    NSSet *visible = OMDExplorerVisiblePathsForFiles(files, _base);
    NSSet *expected = [NSSet setWithObjects:[_base stringByAppendingPathComponent:@"docs/guide/intro.md"],
                                            [_base stringByAppendingPathComponent:@"docs/guide"],
                                            [_base stringByAppendingPathComponent:@"docs"],
                                            [_base stringByAppendingPathComponent:@"README.md"], nil];
    XCTAssertEqualObjects(visible, expected);
}

@end
