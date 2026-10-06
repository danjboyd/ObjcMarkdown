// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDRemoteDocument.h"

@interface OMDRemoteDocumentTests : XCTestCase
@end

@implementation OMDRemoteDocumentTests

- (void)testGitHubPageMapsToItsRawFile
{
    OMDRemoteDocument *document = [OMDRemoteDocument documentWithURLString:
        @"https://github.com/danjboyd/Arlen/blob/main/docs/guide/Intro.md"];
    XCTAssertEqualObjects([[document rawURL] absoluteString],
                          @"https://raw.githubusercontent.com/danjboyd/Arlen/main/docs/guide/Intro.md");
    XCTAssertEqualObjects([[document pageURL] absoluteString],
                          @"https://github.com/danjboyd/Arlen/blob/main/docs/guide/Intro.md");
    XCTAssertEqualObjects([[document baseURL] absoluteString],
                          @"https://raw.githubusercontent.com/danjboyd/Arlen/main/docs/guide/");
    XCTAssertEqualObjects([document fileName], @"Intro.md");
    XCTAssertEqualObjects([document owner], @"danjboyd");
    XCTAssertEqualObjects([document repository], @"Arlen");
    XCTAssertEqualObjects([document ref], @"main");
    XCTAssertTrue([document isOnGitHub]);
}

- (void)testRefsWithSlashesGiveTheSameRawAddress
{
    // "feature/x" and "feature" + "x/README.md" read alike; both are the
    // same raw address, so nothing has to be resolved.
    OMDRemoteDocument *document = [OMDRemoteDocument documentWithURLString:
        @"github.com/owner/repo/blob/feature/x/README.md?plain=1#usage"];
    XCTAssertEqualObjects([[document rawURL] absoluteString],
                          @"https://raw.githubusercontent.com/owner/repo/feature/x/README.md");
    XCTAssertEqualObjects([document ref], @"feature");
}

- (void)testRawAddressesMapBackToTheirPage
{
    OMDRemoteDocument *document = [OMDRemoteDocument documentWithURLString:
        @"https://raw.githubusercontent.com/owner/repo/refs/heads/main/README.md"];
    XCTAssertEqualObjects([[document rawURL] absoluteString],
                          @"https://raw.githubusercontent.com/owner/repo/refs/heads/main/README.md");
    XCTAssertEqualObjects([[document pageURL] absoluteString],
                          @"https://github.com/owner/repo/blob/main/README.md");
    XCTAssertEqualObjects([document ref], @"main");
    XCTAssertEqualObjects([document summary], @"owner/repo · main");
}

- (void)testSpacesAreEscaped
{
    OMDRemoteDocument *document = [OMDRemoteDocument documentWithURLString:
        @"https://github.com/owner/repo/blob/main/My%20Notes/a%20b.md"];
    XCTAssertEqualObjects([[document rawURL] absoluteString],
                          @"https://raw.githubusercontent.com/owner/repo/main/My%20Notes/a%20b.md");
    XCTAssertEqualObjects([document fileName], @"a b.md");
}

- (void)testOtherHostsNeedAMarkdownFile
{
    OMDRemoteDocument *document = [OMDRemoteDocument documentWithURLString:@"https://example.org/docs/notes.markdown?v=2#top"];
    XCTAssertEqualObjects([[document rawURL] absoluteString], @"https://example.org/docs/notes.markdown?v=2");
    XCTAssertEqualObjects([document pageURL], [document rawURL]);
    XCTAssertFalse([document isOnGitHub]);
    XCTAssertEqualObjects([document summary], @"example.org");
}

- (void)testUnsupportedAddresses
{
    XCTAssertNil([OMDRemoteDocument documentWithURLString:@""]);
    XCTAssertNil([OMDRemoteDocument documentWithURLString:@"https://example.org/page.html"]);
    XCTAssertNil([OMDRemoteDocument documentWithURLString:@"https://github.com/owner/repo"]);
    XCTAssertNil([OMDRemoteDocument documentWithURLString:@"https://github.com/owner/repo/tree/main/docs"]);
    XCTAssertNil([OMDRemoteDocument documentWithURLString:@"https://github.com/owner/repo/blob/main/src/main.c"]);
    XCTAssertNil([OMDRemoteDocument documentWithURLString:@"file:///tmp/a.md"]);
    XCTAssertNil([OMDRemoteDocument documentWithURLString:@"ftp://example.org/a.md"]);
}

- (void)testDotSegmentsAreResolved
{
    OMDRemoteDocument *document = [OMDRemoteDocument documentWithURLString:
        @"https://raw.githubusercontent.com/owner/repo/main/docs/internal/../../Roadmap.md"];
    XCTAssertEqualObjects([[document rawURL] absoluteString],
                          @"https://raw.githubusercontent.com/owner/repo/main/Roadmap.md");
    OMDRemoteDocument *other = [OMDRemoteDocument documentWithURLString:@"https://example.org/a/./b/../c.md"];
    XCTAssertEqualObjects([[other rawURL] absoluteString], @"https://example.org/a/c.md");
}

@end
