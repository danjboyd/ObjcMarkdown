// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDExplorerRoot.h"

@interface OMDExplorerRootTests : XCTestCase
{
    NSString *_base;
}
@end

@implementation OMDExplorerRootTests

- (void)setUp
{
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"omd-explorer-root-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    _base = [[[NSTemporaryDirectory() stringByAppendingPathComponent:name] stringByStandardizingPath] retain];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // repo/.git is a folder, worktree/.git a file (as in git worktrees and
    // submodules), plain/ is in no repository.
    [fileManager createDirectoryAtPath:[_base stringByAppendingPathComponent:@"repo/.git"]
           withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtPath:[_base stringByAppendingPathComponent:@"repo/docs/guide"]
           withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtPath:[_base stringByAppendingPathComponent:@"worktree/notes"]
           withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"gitdir: /elsewhere\n" writeToFile:[_base stringByAppendingPathComponent:@"worktree/.git"]
                               atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [fileManager createDirectoryAtPath:[_base stringByAppendingPathComponent:@"plain"]
           withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:_base error:NULL];
    [_base release];
    _base = nil;
    [super tearDown];
}

- (NSString *)path:(NSString *)relative
{
    return [_base stringByAppendingPathComponent:relative];
}

- (void)testDocumentAtTheRepositoryTopUsesTheRepository
{
    XCTAssertEqualObjects(OMDExplorerRootForDocumentPath([self path:@"repo/README.md"]), [self path:@"repo"]);
}

- (void)testDocumentInASubfolderUsesTheRepository
{
    XCTAssertEqualObjects(OMDExplorerRootForDocumentPath([self path:@"repo/docs/guide/a.md"]), [self path:@"repo"]);
    XCTAssertEqualObjects(OMDExplorerRootForDocumentPath([self path:@"repo/docs/../docs/b.md"]), [self path:@"repo"]);
}

- (void)testGitFileMarksAWorkTree
{
    XCTAssertEqualObjects(OMDExplorerRootForDocumentPath([self path:@"worktree/notes/c.md"]), [self path:@"worktree"]);
}

- (void)testDocumentOutsideAnyRepositoryUsesItsFolder
{
    XCTAssertNil(OMDGitWorkTreeForDirectory([self path:@"plain"]));
    XCTAssertEqualObjects(OMDExplorerRootForDocumentPath([self path:@"plain/d.md"]), [self path:@"plain"]);
}

- (void)testUntitledMissingOrRelativePathsHaveNoRoot
{
    XCTAssertNil(OMDExplorerRootForDocumentPath(nil));
    XCTAssertNil(OMDExplorerRootForDocumentPath(@""));
    XCTAssertNil(OMDExplorerRootForDocumentPath(@"docs/a.md"));
    XCTAssertNil(OMDExplorerRootForDocumentPath([self path:@"missing/e.md"]));
}

- (void)testRecentRootsMoveToTheFrontWithoutDuplicatesUpToTheLimit
{
    NSArray *recent = [NSArray arrayWithObjects:@"/a", @"/b", @"/c", nil];
    XCTAssertEqualObjects(OMDExplorerRecentRootsAdding(recent, @"/b/", 8),
                          ([NSArray arrayWithObjects:@"/b", @"/a", @"/c", nil]));
    XCTAssertEqualObjects(OMDExplorerRecentRootsAdding(recent, @"/d", 3),
                          ([NSArray arrayWithObjects:@"/d", @"/a", @"/b", nil]));
    XCTAssertEqualObjects(OMDExplorerRecentRootsAdding(nil, @"/a/../e", 8), [NSArray arrayWithObject:@"/e"]);
    XCTAssertEqualObjects(OMDExplorerRecentRootsAdding(recent, nil, 2),
                          ([NSArray arrayWithObjects:@"/a", @"/b", nil]));
}

- (void)testMenuTitlesNameTheParentOnlyForRepeatedNames
{
    NSString *home = NSHomeDirectory();
    NSArray *roots = [NSArray arrayWithObjects:[home stringByAppendingPathComponent:@"git/app/docs"],
                                               @"/srv/site/docs",
                                               [home stringByAppendingPathComponent:@"git/ObjcMarkdown"],
                                               nil];
    NSArray *expected = [NSArray arrayWithObjects:@"docs (~/git/app)", @"docs (/srv/site)", @"ObjcMarkdown", nil];
    XCTAssertEqualObjects(OMDExplorerRootMenuTitles(roots), expected);
}

- (void)testRelativePathsAreBelowTheRoot
{
    XCTAssertEqualObjects(OMDExplorerRelativePath(@"/home/a/repo/docs/guide.md", @"/home/a/repo"), @"docs/guide.md");
    XCTAssertEqualObjects(OMDExplorerRelativePath(@"/home/a/repo/docs/../README.md", @"/home/a/repo/"), @"README.md");
    XCTAssertEqualObjects(OMDExplorerRelativePath(@"/home/a/repo-old/x.md", @"/home/a/repo"), @"/home/a/repo-old/x.md");
    XCTAssertEqualObjects(OMDExplorerRelativePath(@"/home/a/repo", @"/home/a/repo"), @"/home/a/repo");
}

@end
