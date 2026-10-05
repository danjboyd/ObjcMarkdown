// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDTextFileSupport.h"

@interface OMDTextFileSupportTests : XCTestCase
@end

@implementation OMDTextFileSupportTests

- (void)testTrimmedStringTrimsWhitespaceAndTreatsNilAsEmpty
{
    XCTAssertEqualObjects(OMDTrimmedString(@"  a b \n"), @"a b");
    XCTAssertEqualObjects(OMDTrimmedString(nil), @"");
}

- (void)testMarkdownExtensionsIgnoreCase
{
    XCTAssertTrue(OMDIsMarkdownExtension(@"md"));
    XCTAssertTrue(OMDIsMarkdownExtension(@"MarkDown"));
    XCTAssertTrue(OMDIsMarkdownExtension(@"mdown"));
    XCTAssertFalse(OMDIsMarkdownExtension(@"txt"));
    XCTAssertFalse(OMDIsMarkdownExtension(nil));
}

- (void)testVerbatimSyntaxTokenMapsAliasesAndSkipsPlainText
{
    XCTAssertEqualObjects(OMDVerbatimSyntaxTokenForExtension(@"YML"), @"yaml");
    XCTAssertEqualObjects(OMDVerbatimSyntaxTokenForExtension(@"py"), @"python");
    XCTAssertEqualObjects(OMDVerbatimSyntaxTokenForExtension(@"zsh"), @"bash");
    XCTAssertEqualObjects(OMDVerbatimSyntaxTokenForExtension(@"htm"), @"html");
    XCTAssertEqualObjects(OMDVerbatimSyntaxTokenForExtension(@"c"), @"c");
    XCTAssertNil(OMDVerbatimSyntaxTokenForExtension(@"txt"));
    XCTAssertNil(OMDVerbatimSyntaxTokenForExtension(@"log"));
    XCTAssertNil(OMDVerbatimSyntaxTokenForExtension(@" "));
}

- (void)testCodeFenceIsLongerThanAnyBacktickRunInTheText
{
    XCTAssertEqualObjects(OMDMarkdownCodeFenceWrappedText(@"x = 1", @"python"),
                          @"```python\nx = 1\n```");
    XCTAssertEqualObjects(OMDMarkdownCodeFenceWrappedText(@"a ```` b\n", nil),
                          @"`````\na ```` b\n`````");
    XCTAssertEqualObjects(OMDMarkdownCodeFenceWrappedText(nil, @" "), @"```\n\n```");
}

- (void)testBinaryDetection
{
    const char text[] = "# Title\n\tindented\r\n";
    const unsigned char withNul[] = { 'a', 'b', 0, 'c' };
    const unsigned char controls[] = { 1, 2, 3, 4, 5, 'a' };
    XCTAssertFalse(OMDDataAppearsBinary([NSData dataWithBytes:text length:strlen(text)]));
    XCTAssertTrue(OMDDataAppearsBinary([NSData dataWithBytes:withNul length:sizeof(withNul)]));
    XCTAssertTrue(OMDDataAppearsBinary([NSData dataWithBytes:controls length:sizeof(controls)]));
    XCTAssertFalse(OMDDataAppearsBinary([NSData data]));
}

- (void)testDecodePrefersUTF8
{
    NSStringEncoding used = 0;
    NSData *utf8 = [@"café" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(OMDDecodeTextFromData(utf8, &used), @"café");
    XCTAssertEqual(used, NSUTF8StringEncoding);

    XCTAssertEqualObjects(OMDDecodeTextFromData([NSData data], &used), @"");
    XCTAssertNil(OMDDecodeTextFromData(nil, NULL));
}

- (void)testNormalizedRelativePathResolvesDotsAndDropsTheRoot
{
    XCTAssertEqualObjects(OMDNormalizedRelativePath(@"/docs/./guide/../intro.md"), @"docs/intro.md");
    XCTAssertEqualObjects(OMDNormalizedRelativePath(@"../../a"), @"a");
    XCTAssertEqualObjects(OMDNormalizedRelativePath(@"  "), @"");
}

- (void)testDiskFingerprintCombinesDateSizeAndInode
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDate dateWithTimeIntervalSinceReferenceDate:12.5], NSFileModificationDate,
        [NSNumber numberWithUnsignedLongLong:42], NSFileSize,
        [NSNumber numberWithUnsignedLongLong:7], NSFileSystemFileNumber,
        nil];
    XCTAssertEqualObjects(OMDDiskFingerprintForFileAttributes(attributes), @"12.500000:42:7");
    XCTAssertNil(OMDDiskFingerprintForFileAttributes([NSDictionary dictionary]));
    XCTAssertNil(OMDDiskFingerprintForFileAttributes(nil));
}

@end
