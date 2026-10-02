// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMBlockSignatureIndex.h"

@interface OMBlockSignatureIndexTests : XCTestCase
@end

@implementation OMBlockSignatureIndexTests

- (void)testEqualContentMatchesWhereverItSits
{
    NSArray *lines = [NSArray arrayWithObjects:@"intro", @"- Alpha, beta!", @"  gamma", @"other", @"- alpha beta", @"gamma", nil];
    OMBlockSignatureIndex *index = [[[OMBlockSignatureIndex alloc] initWithSourceLines:lines] autorelease];
    // Normalisation ignores case, punctuation and indentation, as before.
    XCTAssertEqualObjects([index signatureForStartLine:2 endLine:3], [index signatureForStartLine:5 endLine:6]);
    XCTAssertFalse([[index signatureForStartLine:1 endLine:2] isEqualToString:[index signatureForStartLine:4 endLine:5]]);
    XCTAssertFalse([[index signatureForStartLine:2 endLine:3] isEqualToString:[index signatureForStartLine:2 endLine:4]]);
}

- (void)testBlockIDsIncludeTheNodeTypeAndClampRanges
{
    NSArray *lines = [NSArray arrayWithObjects:@"one", @"two", nil];
    OMBlockSignatureIndex *index = [[[OMBlockSignatureIndex alloc] initWithSourceLines:lines] autorelease];
    NSString *paragraph = [index blockIDForNodeType:5 startLine:1 endLine:2];
    NSString *heading = [index blockIDForNodeType:6 startLine:1 endLine:2];
    XCTAssertTrue([paragraph hasPrefix:@"5|"]);
    XCTAssertFalse([paragraph isEqualToString:heading]);
    XCTAssertEqualObjects([index signatureForStartLine:1 endLine:99], [index signatureForStartLine:1 endLine:2]);
    XCTAssertEqualObjects([index signatureForStartLine:0 endLine:2], @"_");
    XCTAssertEqualObjects([index signatureForStartLine:3 endLine:4], @"_");
}

- (void)testDeepNestingStaysFast
{
    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger depth = 0;
    for (; depth < 2000; depth++) {
        [lines addObject:[[@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0]
                             stringByAppendingFormat:@"- level %lu", (unsigned long)depth]];
    }
    NSDate *start = [NSDate date];
    OMBlockSignatureIndex *index = [[[OMBlockSignatureIndex alloc] initWithSourceLines:lines] autorelease];
    for (depth = 1; depth <= 2000; depth++) {
        [index signatureForStartLine:depth endLine:2000];
    }
    XCTAssertTrue(-[start timeIntervalSinceNow] < 2.0, @"each container's signature is constant time");
}

@end
