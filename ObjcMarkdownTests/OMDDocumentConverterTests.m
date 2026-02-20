// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDDocumentConverter.h"

@interface OMDDocumentConverterTests : XCTestCase
@end

@implementation OMDDocumentConverterTests

- (NSString *)temporaryPathWithExtension:(NSString *)extension
{
    NSString *directory = NSTemporaryDirectory();
    if (directory == nil || [directory length] == 0) {
        directory = @"/tmp";
    }
    NSString *fileName = [NSString stringWithFormat:@"objcmarkdown-test-%@.%@",
                          [[NSProcessInfo processInfo] globallyUniqueString],
                          extension];
    return [directory stringByAppendingPathComponent:fileName];
}

- (void)removeFileIfPresent:(NSString *)path
{
    if (path == nil) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void)testSupportedExtensionList
{
    XCTAssertTrue([OMDDocumentConverter isSupportedExtension:@"html"]);
    XCTAssertTrue([OMDDocumentConverter isSupportedExtension:@"htm"]);
    XCTAssertTrue([OMDDocumentConverter isSupportedExtension:@"rtf"]);
    XCTAssertTrue([OMDDocumentConverter isSupportedExtension:@"docx"]);
    XCTAssertTrue([OMDDocumentConverter isSupportedExtension:@"odt"]);
    XCTAssertFalse([OMDDocumentConverter isSupportedExtension:@"pdf"]);
}

- (void)testDefaultConverterDetectsPandocWhenPresent
{
    OMDDocumentConverter *converter = [OMDDocumentConverter defaultConverter];
    if (converter == nil) {
        NSLog(@"Skipping pandoc smoke checks: %@", [OMDDocumentConverter missingBackendInstallMessage]);
        return;
    }
    XCTAssertEqualObjects([converter backendName], @"pandoc");
}

- (void)testPandocExportAndImportRTF
{
    OMDDocumentConverter *converter = [OMDDocumentConverter defaultConverter];
    if (converter == nil) {
        NSLog(@"Skipping pandoc smoke checks: %@", [OMDDocumentConverter missingBackendInstallMessage]);
        return;
    }

    NSString *markdown = @"# Title\n\n- one\n- two\n\nThis is **bold**.";
    NSString *rtfPath = [self temporaryPathWithExtension:@"rtf"];

    NSError *exportError = nil;
    BOOL exported = [converter exportMarkdown:markdown toPath:rtfPath error:&exportError];
    XCTAssertTrue(exported, @"%@", [exportError localizedDescription]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:rtfPath]);

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:rtfPath error:NULL];
    NSNumber *fileSize = [attributes objectForKey:NSFileSize];
    XCTAssertNotNil(fileSize);
    XCTAssertTrue([fileSize unsignedLongLongValue] > 0);

    NSString *importedMarkdown = nil;
    NSError *importError = nil;
    BOOL imported = [converter importFileAtPath:rtfPath markdown:&importedMarkdown error:&importError];
    XCTAssertTrue(imported, @"%@", [importError localizedDescription]);
    XCTAssertNotNil(importedMarkdown);
    XCTAssertTrue([importedMarkdown rangeOfString:@"Title"].location != NSNotFound);

    [self removeFileIfPresent:rtfPath];
}

- (void)testPandocRoundTripsHTMLDOCXAndODT
{
    OMDDocumentConverter *converter = [OMDDocumentConverter defaultConverter];
    if (converter == nil) {
        NSLog(@"Skipping pandoc smoke checks: %@", [OMDDocumentConverter missingBackendInstallMessage]);
        return;
    }

    NSString *markdown = @"# Export Test\n\nParagraph text.";
    NSArray *extensions = [NSArray arrayWithObjects:@"html", @"docx", @"odt", nil];
    for (NSString *extension in extensions) {
        NSString *path = [self temporaryPathWithExtension:extension];
        NSError *error = nil;
        BOOL exported = [converter exportMarkdown:markdown toPath:path error:&error];
        XCTAssertTrue(exported, @"%@", [error localizedDescription]);
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);

        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        NSNumber *fileSize = [attributes objectForKey:NSFileSize];
        XCTAssertNotNil(fileSize);
        XCTAssertTrue([fileSize unsignedLongLongValue] > 0);

        NSString *importedMarkdown = nil;
        NSError *importError = nil;
        BOOL imported = [converter importFileAtPath:path markdown:&importedMarkdown error:&importError];
        XCTAssertTrue(imported, @"%@", [importError localizedDescription]);
        XCTAssertNotNil(importedMarkdown);
        XCTAssertTrue([importedMarkdown rangeOfString:@"Export Test"].location != NSNotFound);

        [self removeFileIfPresent:path];
    }
}

@end
