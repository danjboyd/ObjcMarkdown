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

- (void)testDecodeFallsBackToWindows1252ThenLatin1
{
    NSStringEncoding used = 0;
    // Even and odd lengths: neither may be taken for UTF-16.
    const unsigned char latin1[] = { 'c', 'a', 'f', 0xE9 };
    NSString *decoded = OMDDecodeTextFromData([NSData dataWithBytes:latin1 length:sizeof(latin1)], &used);
    XCTAssertEqualObjects(decoded, @"café");
    XCTAssertEqual(used, NSWindowsCP1252StringEncoding);

    const unsigned char quotes[] = { 0x93, 'h', 'i', 0x94, ' ', 0x80 };
    decoded = OMDDecodeTextFromData([NSData dataWithBytes:quotes length:sizeof(quotes)], &used);
    XCTAssertEqualObjects(decoded, @"“hi” €");

    // 0x81 is undefined in Windows-1252.
    const unsigned char undefined[] = { 'a', 0x81, 'b' };
    decoded = OMDDecodeTextFromData([NSData dataWithBytes:undefined length:sizeof(undefined)], &used);
    XCTAssertEqual([decoded length], (NSUInteger)3);
    XCTAssertEqual(used, NSISOLatin1StringEncoding);
}

- (void)testDecodeHonoursByteOrderMarks
{
    NSStringEncoding used = 0;
    const unsigned char utf8[] = { 0xEF, 0xBB, 0xBF, '#', ' ', 'x' };
    NSString *decoded = OMDDecodeTextFromData([NSData dataWithBytes:utf8 length:sizeof(utf8)], &used);
    XCTAssertEqualObjects(decoded, @"# x");
    XCTAssertEqual(used, NSUTF8StringEncoding);

    const unsigned char utf16le[] = { 0xFF, 0xFE, '#', 0, ' ', 0, 0xE9, 0 };
    decoded = OMDDecodeTextFromData([NSData dataWithBytes:utf16le length:sizeof(utf16le)], &used);
    XCTAssertEqualObjects(decoded, @"# é");
    XCTAssertEqual(used, NSUTF16LittleEndianStringEncoding);

    const unsigned char utf16be[] = { 0xFE, 0xFF, 0, '#', 0, 'x' };
    decoded = OMDDecodeTextFromData([NSData dataWithBytes:utf16be length:sizeof(utf16be)], &used);
    XCTAssertEqualObjects(decoded, @"#x");
    XCTAssertEqual(used, NSUTF16BigEndianStringEncoding);

    const unsigned char utf32le[] = { 0xFF, 0xFE, 0, 0, 'x', 0, 0, 0 };
    decoded = OMDDecodeTextFromData([NSData dataWithBytes:utf32le length:sizeof(utf32le)], &used);
    XCTAssertEqualObjects(decoded, @"x");
    XCTAssertEqual(used, NSUTF32LittleEndianStringEncoding);
}

- (void)testUnicodeTextWithAByteOrderMarkIsNotBinary
{
    const unsigned char utf16le[] = { 0xFF, 0xFE, '#', 0, ' ', 0, 'x', 0 };
    const unsigned char utf32be[] = { 0, 0, 0xFE, 0xFF, 0, 0, 0, 'x' };
    const unsigned char utf8WithNul[] = { 0xEF, 0xBB, 0xBF, 'a', 0, 'b' };
    XCTAssertFalse(OMDDataAppearsBinary([NSData dataWithBytes:utf16le length:sizeof(utf16le)]));
    XCTAssertFalse(OMDDataAppearsBinary([NSData dataWithBytes:utf32be length:sizeof(utf32be)]));
    XCTAssertTrue(OMDDataAppearsBinary([NSData dataWithBytes:utf8WithNul length:sizeof(utf8WithNul)]));
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
