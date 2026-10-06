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

@end
