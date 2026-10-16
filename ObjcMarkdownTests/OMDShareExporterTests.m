// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDShareExporter.h"

// A document to share, without a window.
@interface OMDShareTestSource : NSObject <OMDShareSource>
{
@public
    NSString *_baseName;
    NSString *_text;
    NSString *_extension;
    BOOL _pdfWritten;
}
@end

@implementation OMDShareTestSource

- (void)dealloc
{
    [_baseName release];
    [_text release];
    [_extension release];
    [super dealloc];
}

- (NSString *)shareBaseName { return _baseName; }
- (NSString *)shareSourceText { return _text; }
- (NSString *)shareSourceExtension { return _extension; }
- (NSString *)shareMarkdownText { return _text; }
- (NSString *)shareResourceDirectory { return nil; }
- (NSAttributedString *)shareRenderedText { return nil; }
- (OMDDocumentConverter *)documentConverter { return nil; }

- (BOOL)shareWritePDFToPath:(NSString *)path
{
    _pdfWritten = YES;
    return [@"%PDF-1.4\n" writeToFile:path atomically:YES encoding:NSASCIIStringEncoding error:NULL];
}

@end

@interface OMDShareExporterTests : XCTestCase
@end

@implementation OMDShareExporterTests

- (OMDShareTestSource *)sourceWithName:(NSString *)name text:(NSString *)text extension:(NSString *)extension
{
    OMDShareTestSource *source = [[[OMDShareTestSource alloc] init] autorelease];
    source->_baseName = [name copy];
    source->_text = [text copy];
    source->_extension = [extension copy];
    return source;
}

- (void)testFormatsHaveExtensionsAndNames
{
    XCTAssertEqualObjects([OMDShareExporter fileExtensionForFormat:OMDShareFormatPDF], @"pdf");
    XCTAssertEqualObjects([OMDShareExporter fileExtensionForFormat:OMDShareFormatWord], @"docx");
    XCTAssertEqualObjects([OMDShareExporter fileExtensionForFormat:OMDShareFormatMarkdown], @"md");
    XCTAssertEqualObjects([OMDShareExporter fileExtensionForFormat:OMDShareFormatHTML], @"html");
    XCTAssertEqualObjects([OMDShareExporter displayNameForFormat:OMDShareFormatWord], @"Word Document");
    XCTAssertTrue([OMDShareExporter formatNeedsConverter:OMDShareFormatWord]);
    XCTAssertTrue([OMDShareExporter formatNeedsConverter:OMDShareFormatHTML]);
    XCTAssertFalse([OMDShareExporter formatNeedsConverter:OMDShareFormatPDF]);
    XCTAssertFalse([OMDShareExporter formatNeedsConverter:OMDShareFormatMarkdown]);
}

- (void)testSafeFileBaseNameReplacesCharactersPlatformsRefuse
{
    XCTAssertEqualObjects([OMDShareExporter safeFileBaseName:@"Q3 Plan"], @"Q3 Plan");
    XCTAssertEqualObjects([OMDShareExporter safeFileBaseName:@"a/b\\c:d*e?f\"g<h>i|j"], @"a-b-c-d-e-f-g-h-i-j");
    XCTAssertEqualObjects([OMDShareExporter safeFileBaseName:@"tab\there"], @"tab-here");
    XCTAssertEqualObjects([OMDShareExporter safeFileBaseName:@" .hidden. "], @"hidden");
    XCTAssertEqualObjects([OMDShareExporter safeFileBaseName:@"..."], @"Document");
    XCTAssertEqualObjects([OMDShareExporter safeFileBaseName:nil], @"Document");
    XCTAssertEqual([[OMDShareExporter safeFileBaseName:[@"" stringByPaddingToLength:300 withString:@"x" startingAtIndex:0]] length], (NSUInteger)120);
}

- (void)testMarkdownShareKeepsTheTextAndTheDocumentsName
{
    OMDShareTestSource *source = [self sourceWithName:@"Q3 Plan" text:@"# Plan\n\nUnsaved edit\n" extension:@"md"];
    OMDShareExporter *exporter = [[[OMDShareExporter alloc] initWithSource:source] autorelease];
    NSError *error = nil;
    OMDShareItem *item = [exporter shareItemForFormat:OMDShareFormatMarkdown error:&error];
    XCTAssertNotNil(item, @"%@", error);
    XCTAssertEqualObjects([item fileName], @"Q3 Plan.md");
    XCTAssertEqualObjects([item title], @"Q3 Plan");
    XCTAssertEqual([item format], OMDShareFormatMarkdown);
    NSString *written = [NSString stringWithContentsOfFile:[[item fileURL] path] encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertEqualObjects(written, @"# Plan\n\nUnsaved edit\n");
    XCTAssertTrue([[[item fileURL] path] hasPrefix:[OMDShareExporter launchTemporaryDirectory]]);
}

- (void)testMarkdownShareOfATextFileKeepsItsExtension
{
    OMDShareTestSource *source = [self sourceWithName:@"notes" text:@"plain\n" extension:@"txt"];
    OMDShareExporter *exporter = [[[OMDShareExporter alloc] initWithSource:source] autorelease];
    OMDShareItem *item = [exporter shareItemForFormat:OMDShareFormatMarkdown error:NULL];
    XCTAssertEqualObjects([item fileName], @"notes.txt");
}

- (void)testSharingTwiceKeepsTheNameInSeparateDirectories
{
    OMDShareTestSource *source = [self sourceWithName:@"Same" text:@"x\n" extension:@"md"];
    OMDShareExporter *exporter = [[[OMDShareExporter alloc] initWithSource:source] autorelease];
    OMDShareItem *first = [exporter shareItemForFormat:OMDShareFormatMarkdown error:NULL];
    OMDShareItem *second = [exporter shareItemForFormat:OMDShareFormatMarkdown error:NULL];
    XCTAssertEqualObjects([first fileName], @"Same.md");
    XCTAssertEqualObjects([second fileName], @"Same.md");
    XCTAssertNotEqualObjects([[first fileURL] path], [[second fileURL] path]);
    // The first file is still there: a share never deletes its file.
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[[first fileURL] path]]);
}

- (void)testPDFShareUsesTheSourcesPDF
{
    OMDShareTestSource *source = [self sourceWithName:@"Report" text:@"# R\n" extension:@"md"];
    OMDShareExporter *exporter = [[[OMDShareExporter alloc] initWithSource:source] autorelease];
    OMDShareItem *item = [exporter shareItemForFormat:OMDShareFormatPDF error:NULL];
    XCTAssertTrue(source->_pdfWritten);
    XCTAssertEqualObjects([item fileName], @"Report.pdf");
}

- (void)testWordShareWithoutPandocFailsWithAnError
{
    OMDShareTestSource *source = [self sourceWithName:@"Report" text:@"# R\n" extension:@"md"];
    OMDShareExporter *exporter = [[[OMDShareExporter alloc] initWithSource:source] autorelease];
    NSError *error = nil;
    XCTAssertNil([exporter shareItemForFormat:OMDShareFormatWord error:&error]);
    XCTAssertEqualObjects([error domain], OMDShareErrorDomain);
    XCTAssertEqual([error code], (NSInteger)OMDShareErrorConverterUnavailable);
}

- (void)testNoDocumentFailsWithAnError
{
    OMDShareTestSource *source = [self sourceWithName:@"x" text:nil extension:@"md"];
    OMDShareExporter *exporter = [[[OMDShareExporter alloc] initWithSource:source] autorelease];
    NSError *error = nil;
    XCTAssertNil([exporter shareItemForFormat:OMDShareFormatMarkdown error:&error]);
    XCTAssertEqual([error code], (NSInteger)OMDShareErrorNoDocument);
}

- (void)testLaunchDirectoryIsPrivate
{
    NSString *directory = [OMDShareExporter launchTemporaryDirectory];
    XCTAssertNotNil(directory);
#if !defined(_WIN32)
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:directory error:NULL];
    XCTAssertEqual([[attributes objectForKey:NSFilePosixPermissions] shortValue] & 0777, 0700);
#endif
}

- (void)testSweepRemovesFinishedLaunchesButKeepsThisOne
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *current = [OMDShareExporter launchTemporaryDirectory];
    NSString *root = [OMDShareExporter temporaryRootDirectory];
    // A launch whose process is gone (pid 0 never names a process).
    NSString *finished = [root stringByAppendingPathComponent:@"0-12345"];
    // A directory a day and more old.
    NSString *old = [root stringByAppendingPathComponent:@"stale"];
    XCTAssertTrue([manager createDirectoryAtPath:finished withIntermediateDirectories:YES attributes:nil error:NULL]);
    XCTAssertTrue([manager createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSDictionary *oldDate = [NSDictionary dictionaryWithObject:[NSDate dateWithTimeIntervalSinceNow:-2.0 * 24.0 * 60.0 * 60.0]
                                                        forKey:NSFileModificationDate];
    [manager setAttributes:oldDate ofItemAtPath:old error:NULL];

    [OMDShareExporter sweepStaleTemporaryDirectories];

    XCTAssertFalse([manager fileExistsAtPath:finished]);
    XCTAssertFalse([manager fileExistsAtPath:old]);
    XCTAssertTrue([manager fileExistsAtPath:current]);
}

@end
