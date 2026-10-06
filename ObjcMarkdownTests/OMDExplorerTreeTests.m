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

@end
