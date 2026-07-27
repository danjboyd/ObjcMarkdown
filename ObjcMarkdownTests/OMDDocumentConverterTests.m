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

- (void)testPandocExportEmbedsRelativeImagesUsingResourceDirectory
{
    OMDDocumentConverter *converter = [OMDDocumentConverter defaultConverter];
    if (converter == nil) {
        NSLog(@"Skipping pandoc smoke checks: %@", [OMDDocumentConverter missingBackendInstallMessage]);
        return;
    }

    NSString *directoryName = [NSString stringWithFormat:@"objcmarkdown-test-resources-%@",
                                                         [[NSProcessInfo processInfo] globallyUniqueString]];
#if !defined(_WIN32)
    // Mimic GVFS network mounts (e.g. "sftp:host=..."), whose colons broke
    // pandoc's colon-separated --resource-path option.
    directoryName = [directoryName stringByAppendingString:@":colon"];
#endif
    NSString *resourceDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:directoryName];
    NSError *directoryError = nil;
    BOOL createdDirectory = [[NSFileManager defaultManager] createDirectoryAtPath:resourceDirectory
                                                      withIntermediateDirectories:YES
                                                                       attributes:nil
                                                                            error:&directoryError];
    XCTAssertTrue(createdDirectory, @"%@", [directoryError localizedDescription]);

    static const unsigned char pixelPNG[] = {
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82
    };
    NSData *pngData = [NSData dataWithBytes:pixelPNG length:sizeof(pixelPNG)];
    NSString *imagePath = [resourceDirectory stringByAppendingPathComponent:@"pixel.png"];
    XCTAssertTrue([pngData writeToFile:imagePath atomically:YES]);

    NSString *markdown = @"# Image Export Test\n\n![pixel](pixel.png)\n";
    NSString *docxPath = [self temporaryPathWithExtension:@"docx"];

    NSError *exportError = nil;
    BOOL exported = [converter exportMarkdown:markdown
                                       toPath:docxPath
                            resourceDirectory:resourceDirectory
                                        error:&exportError];
    XCTAssertTrue(exported, @"%@", [exportError localizedDescription]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:docxPath]);

    NSString *importedMarkdown = nil;
    NSError *importError = nil;
    BOOL imported = [converter importFileAtPath:docxPath markdown:&importedMarkdown error:&importError];
    XCTAssertTrue(imported, @"%@", [importError localizedDescription]);
    XCTAssertNotNil(importedMarkdown);
    BOOL hasMarkdownImage = ([importedMarkdown rangeOfString:@"!["].location != NSNotFound);
    BOOL hasHTMLImage = ([importedMarkdown rangeOfString:@"<img "].location != NSNotFound);
    XCTAssertTrue(hasMarkdownImage || hasHTMLImage,
                  @"Expected an embedded image in the DOCX round trip, got: %@", importedMarkdown);

    [self removeFileIfPresent:docxPath];
    [[NSFileManager defaultManager] removeItemAtPath:resourceDirectory error:NULL];
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
