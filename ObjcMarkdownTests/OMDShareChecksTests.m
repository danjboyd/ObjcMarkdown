// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDShareChecks.h"
#import "OMDShareBundle.h"
#import "OMTestPaths.h"

@interface OMDShareChecksTests : XCTestCase
{
    NSString *_folder;
}
@end

@implementation OMDShareChecksTests

- (void)setUp
{
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"OMDShareChecksTests-%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    _folder = [[NSTemporaryDirectory() stringByAppendingPathComponent:name] retain];
    NSFileManager *files = [NSFileManager defaultManager];
    [files createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"doc/images"]
     withIntermediateDirectories:YES attributes:nil error:NULL];
    [files createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"other"]
     withIntermediateDirectories:YES attributes:nil error:NULL];
    [self writeFile:@"doc/images/chart.png" text:@"chart"];
    [self writeFile:@"doc/notes.txt" text:@"notes"];
    [self writeFile:@"other/chart.png" text:@"other chart"];
    [self writeFile:@"other/b c.png" text:@"spaced"];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [_folder release];
    _folder = nil;
    [super tearDown];
}

- (void)writeFile:(NSString *)relative text:(NSString *)text
{
    [text writeToFile:[_folder stringByAppendingPathComponent:relative]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (NSString *)documentFolder
{
    return [_folder stringByAppendingPathComponent:@"doc"];
}

- (OMDShareWarning *)warningOfKind:(OMDShareWarningKind)kind in:(NSArray *)warnings
{
    for (OMDShareWarning *warning in warnings) {
        if ([warning kind] == kind) {
            return warning;
        }
    }
    return nil;
}

- (NSArray *)warnings:(NSString *)markdown
{
    return OMDShareWarnings(markdown, [self documentFolder]);
}

#pragma mark References

- (void)testRemoteReferencesAndAnchorsAreNotLocal
{
    XCTAssertNil(OMDShareResolvedLocalPath(@"https://example.com/a.png", @"/tmp"));
    XCTAssertNil(OMDShareResolvedLocalPath(@"mailto:a@example.com", @"/tmp"));
    XCTAssertNil(OMDShareResolvedLocalPath(@"data:image/png;base64,AAAA", @"/tmp"));
    XCTAssertNil(OMDShareResolvedLocalPath(@"//cdn.example.com/a.png", @"/tmp"));
    XCTAssertNil(OMDShareResolvedLocalPath(@"#section", @"/tmp"));
}

- (void)testRelativePathsResolveAgainstTheFolderWithoutQueryOrFragment
{
    NSString *base = OMTestAbsolutePath(@"/docs/plan");
    XCTAssertEqualObjects(OMDShareResolvedLocalPath(@"images/a%20b.png?v=2#x", base),
                          [[base stringByAppendingPathComponent:@"images/a b.png"] stringByStandardizingPath]);
    XCTAssertNil(OMDShareResolvedLocalPath(@"images/a.png", nil));
}

- (void)testAbsolutePathsDriveLettersAndFileURLs
{
    NSString *absolute = OMTestAbsolutePath(@"/pictures/a.png");
    XCTAssertEqualObjects(OMDShareResolvedLocalPath(absolute, nil), absolute);
    XCTAssertEqualObjects(OMDShareResolvedLocalPath(@"C:/pictures/a.png", nil), @"C:/pictures/a.png");
    NSString *path = [_folder stringByAppendingPathComponent:@"other/b c.png"];
    NSString *url = [[NSURL fileURLWithPath:path] absoluteString];
    XCTAssertEqualObjects([OMDShareResolvedLocalPath(url, nil) stringByStandardizingPath],
                          [path stringByStandardizingPath]);
}

#pragma mark Warnings

- (void)testNothingToSayAboutAPlainDocument
{
    XCTAssertEqual([[self warnings:@"# Plan\n\nText with [a link](https://example.com) and ![x](https://example.com/x.png)."] count],
                   (NSUInteger)0);
    XCTAssertEqual([OMDShareWarnings(nil, nil) count], (NSUInteger)0);
}

- (void)testLocalImagesAndMissingImages
{
    NSArray *warnings = [self warnings:@"![a](images/chart.png) ![b](../other/chart.png) ![a again](images/chart.png) ![gone](images/gone.png)"];
    OMDShareWarning *local = [self warningOfKind:OMDShareWarningLocalImages in:warnings];
    XCTAssertEqualObjects([local references], ([NSArray arrayWithObjects:@"images/chart.png", @"../other/chart.png", nil]));
    XCTAssertEqual([[local resolvedPaths] count], (NSUInteger)2);
    XCTAssertEqualObjects([local messageForFormat:OMDShareFormatMarkdown],
                          @"2 images are only on this computer; the reader won't see them.");
    XCTAssertTrue([local suggestsPDF]);
    XCTAssertTrue([local offersBundle]);
    OMDShareWarning *missing = [self warningOfKind:OMDShareWarningMissingImages in:warnings];
    XCTAssertEqualObjects([missing references], [NSArray arrayWithObject:@"images/gone.png"]);
    XCTAssertEqualObjects([missing messageForFormat:OMDShareFormatPDF], @"1 image can't be found, even on this computer.");
}

- (void)testImagesWrittenAsHTMLCount
{
    NSArray *warnings = [self warnings:@"<img src=\"images/chart.png\" width=\"40\">\n\nText <img src='../other/chart.png'>"];
    OMDShareWarning *local = [self warningOfKind:OMDShareWarningLocalImages in:warnings];
    XCTAssertEqual([[local references] count], (NSUInteger)2);
    XCTAssertEqual([[local htmlReferences] count], (NSUInteger)2);
}

- (void)testLocalImagesMatterForMarkdownAndHTMLAndWordOnlyForHTMLImages
{
    OMDShareWarning *markdownImages = [self warningOfKind:OMDShareWarningLocalImages
                                                       in:[self warnings:@"![a](images/chart.png)"]];
    XCTAssertTrue([markdownImages appliesToFormat:OMDShareFormatMarkdown]);
    XCTAssertTrue([markdownImages appliesToFormat:OMDShareFormatHTML]);
    XCTAssertFalse([markdownImages appliesToFormat:OMDShareFormatWord]);
    XCTAssertFalse([markdownImages appliesToFormat:OMDShareFormatPDF]);

    OMDShareWarning *htmlImages = [self warningOfKind:OMDShareWarningLocalImages
                                                   in:[self warnings:@"![a](images/chart.png)\n\n<img src=\"../other/chart.png\">"]];
    XCTAssertTrue([htmlImages appliesToFormat:OMDShareFormatWord]);
    XCTAssertEqualObjects([htmlImages messageForFormat:OMDShareFormatWord],
                          @"1 image written as HTML won't be in the Word file.");
}

- (void)testLocalLinks
{
    NSString *fileURL = [[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"other/chart.png"]] absoluteString];
    NSString *markdown = [NSString stringWithFormat:
        @"[notes](notes.txt), [file](%@), [gone file](file:///nowhere/x.txt), [repo doc](docs/README.md), [web](https://example.com), [here](#top)",
        fileURL];
    OMDShareWarning *links = [self warningOfKind:OMDShareWarningLocalLinks in:[self warnings:markdown]];
    // A relative path that isn't there is likely a link where the document
    // is published; a file: URL is local either way.
    XCTAssertEqualObjects([links references], ([NSArray arrayWithObjects:@"notes.txt", fileURL, @"file:///nowhere/x.txt", nil]));
    XCTAssertEqual([[links resolvedPaths] count], (NSUInteger)2);
    XCTAssertTrue([links appliesToFormat:OMDShareFormatPDF]);
    XCTAssertFalse([links suggestsPDF]);
    XCTAssertEqualObjects([links messageForFormat:OMDShareFormatPDF],
                          @"3 links point to files on this computer; they won't open for the reader.");
}

- (void)testMathByTheRenderersRules
{
    XCTAssertNotNil([self warningOfKind:OMDShareWarningMath in:[self warnings:@"Energy is $E = mc^2$."]]);
    XCTAssertNotNil([self warningOfKind:OMDShareWarningMath in:[self warnings:@"$$\n\\int_0^1 f\n$$"]]);
    XCTAssertNotNil([self warningOfKind:OMDShareWarningMath in:[self warnings:@"- item with $x^2$"]]);
    XCTAssertNotNil([self warningOfKind:OMDShareWarningMath in:[self warnings:@"| a |\n|---|\n| $x$ |"]]);
    XCTAssertNil([self warningOfKind:OMDShareWarningMath in:[self warnings:@"It costs $5 or $10."]]);
    XCTAssertNil([self warningOfKind:OMDShareWarningMath in:[self warnings:@"Run `echo $HOME$` now."]]);
    XCTAssertNil([self warningOfKind:OMDShareWarningMath in:[self warnings:@"```sh\necho $a$b\n```"]]);
}

- (void)testMathMattersForMarkdownAndHTML
{
    OMDShareWarning *math = [self warningOfKind:OMDShareWarningMath in:[self warnings:@"$x^2$"]];
    XCTAssertTrue([math appliesToFormat:OMDShareFormatMarkdown]);
    XCTAssertTrue([math appliesToFormat:OMDShareFormatHTML]);
    XCTAssertFalse([math appliesToFormat:OMDShareFormatWord]);
    XCTAssertFalse([math appliesToFormat:OMDShareFormatPDF]);
    XCTAssertTrue([math suggestsPDF]);
    XCTAssertFalse([math offersBundle]);
}

- (void)testMermaidMattersEverywhereButPDF
{
    OMDShareWarning *mermaid = [self warningOfKind:OMDShareWarningMermaid
                                                in:[self warnings:@"```mermaid\ngraph TD; A-->B\n```"]];
    XCTAssertNotNil(mermaid);
    XCTAssertTrue([mermaid appliesToFormat:OMDShareFormatWord]);
    XCTAssertFalse([mermaid appliesToFormat:OMDShareFormatPDF]);
    XCTAssertNil([self warningOfKind:OMDShareWarningMermaid in:[self warnings:@"```js\nmermaid()\n```"]]);
}

- (void)testWarningsForAFormat
{
    NSArray *warnings = [self warnings:@"![a](images/chart.png) $x^2$\n\n```mermaid\ngraph TD; A-->B\n```"];
    XCTAssertEqual([warnings count], (NSUInteger)3);
    XCTAssertEqual([OMDShareWarningsForFormat(warnings, OMDShareFormatPDF) count], (NSUInteger)0);
    XCTAssertEqual([OMDShareWarningsForFormat(warnings, OMDShareFormatWord) count], (NSUInteger)1);
    XCTAssertEqual([OMDShareWarningsForFormat(warnings, OMDShareFormatMarkdown) count], (NSUInteger)3);
}

#pragma mark Bundle

- (void)testCRC32MatchesTheCheckValue
{
    XCTAssertEqual(OMDShareCRC32([@"123456789" dataUsingEncoding:NSASCIIStringEncoding]), (uint32_t)0xCBF43926u);
    XCTAssertEqual(OMDShareCRC32([NSData data]), (uint32_t)0);
}

- (void)testZipHasItsEntriesAndEndRecord
{
    NSString *path = [_folder stringByAppendingPathComponent:@"t.zip"];
    NSArray *names = [NSArray arrayWithObjects:@"Doc/Doc.md", @"Doc/images/a.png", nil];
    NSArray *contents = [NSArray arrayWithObjects:[@"# Doc\n" dataUsingEncoding:NSUTF8StringEncoding],
                                                  [@"png" dataUsingEncoding:NSUTF8StringEncoding], nil];
    XCTAssertTrue(OMDShareWriteZip(path, names, contents));
    NSData *zip = [NSData dataWithContentsOfFile:path];
    const uint8_t *bytes = (const uint8_t *)[zip bytes];
    XCTAssertTrue([zip length] > 22);
    XCTAssertEqual(bytes[0], (uint8_t)'P');
    XCTAssertEqual(bytes[1], (uint8_t)'K');
    XCTAssertEqual(bytes[2], (uint8_t)3);
    XCTAssertEqual(bytes[3], (uint8_t)4);
    const uint8_t *end = bytes + [zip length] - 22;
    XCTAssertEqual(end[0], (uint8_t)'P');
    XCTAssertEqual(end[3], (uint8_t)6);
    XCTAssertEqual(end[10] | (end[11] << 8), 2);
    NSString *text = [[[NSString alloc] initWithData:zip encoding:NSISOLatin1StringEncoding] autorelease];
    XCTAssertTrue([text rangeOfString:@"Doc/images/a.png"].location != NSNotFound);

#if !defined(GNUSTEP)
    // The system's unzip agrees.
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:@"/usr/bin/unzip"];
    [task setArguments:[NSArray arrayWithObjects:@"-tq", path, nil]];
    [task setStandardOutput:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];
    XCTAssertEqual([task terminationStatus], 0);
#endif
}

- (void)testBundleKeepsRelativeImagesAndMovesOthersIntoImages
{
    NSString *absolute = [_folder stringByAppendingPathComponent:@"other/b c.png"];
    NSString *markdown = [NSString stringWithFormat:
        @"![a](images/chart.png \"Chart\")\n![b](../other/chart.png)\n![c](<%@>)\n<img src=\"../other/chart.png\">\n![gone](gone.png)\n",
        absolute];
    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *contents = [NSMutableArray array];
    OMDShareBundleEntries(markdown, [self documentFolder], @"Plan", names, contents);

    XCTAssertEqualObjects(names, ([NSArray arrayWithObjects:@"Plan/Plan.md", @"Plan/images/chart.png",
                                                            @"Plan/images/chart-2.png", @"Plan/images/b c.png", nil]));
    NSString *bundled = [[[NSString alloc] initWithData:[contents objectAtIndex:0] encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertEqualObjects(bundled,
                          @"![a](images/chart.png \"Chart\")\n![b](images/chart-2.png)\n![c](<images/b c.png>)\n<img src=\"images/chart-2.png\">\n![gone](gone.png)\n");
    XCTAssertEqualObjects([[[NSString alloc] initWithData:[contents objectAtIndex:2] encoding:NSUTF8StringEncoding] autorelease],
                          @"other chart");
}

- (void)testBundleRewriteLeavesLongerReferencesAlone
{
    NSString *markdown = @"![b](../other/chart.png) [x](../other/chart.png.txt)";
    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *contents = [NSMutableArray array];
    OMDShareBundleEntries(markdown, [self documentFolder], @"Plan", names, contents);
    NSString *bundled = [[[NSString alloc] initWithData:[contents objectAtIndex:0] encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertEqualObjects(bundled, @"![b](images/chart.png) [x](../other/chart.png.txt)");
}

@end
