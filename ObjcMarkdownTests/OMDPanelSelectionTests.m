// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDPanelSelection.h"

@interface OMDStubOpenPanel : NSObject
{
    NSArray *_filenames;
    NSArray *_URLs;
    NSString *_filename;
    NSURL *_URL;
}
- (NSArray *)filenames;
- (void)setFilenames:(NSArray *)filenames;
- (NSArray *)URLs;
- (void)setURLs:(NSArray *)urls;
- (NSString *)filename;
- (void)setFilename:(NSString *)filename;
- (NSURL *)URL;
- (void)setURL:(NSURL *)url;
@end

@implementation OMDStubOpenPanel

- (void)dealloc
{
    [_filenames release];
    [_URLs release];
    [_filename release];
    [_URL release];
    [super dealloc];
}

- (NSArray *)filenames
{
    return _filenames;
}

- (void)setFilenames:(NSArray *)filenames
{
    if (_filenames != filenames) {
        [_filenames release];
        _filenames = [filenames retain];
    }
}

- (NSArray *)URLs
{
    return _URLs;
}

- (void)setURLs:(NSArray *)urls
{
    if (_URLs != urls) {
        [_URLs release];
        _URLs = [urls retain];
    }
}

- (NSString *)filename
{
    return _filename;
}

- (void)setFilename:(NSString *)filename
{
    if (_filename != filename) {
        [_filename release];
        _filename = [filename retain];
    }
}

- (NSURL *)URL
{
    return _URL;
}

- (void)setURL:(NSURL *)url
{
    if (_URL != url) {
        [_URL release];
        _URL = [url retain];
    }
}

@end

@interface OMDStubSavePanel : NSObject
{
    NSString *_filename;
    NSURL *_URL;
}
- (NSString *)filename;
- (void)setFilename:(NSString *)filename;
- (NSURL *)URL;
- (void)setURL:(NSURL *)url;
@end

@implementation OMDStubSavePanel

- (void)dealloc
{
    [_filename release];
    [_URL release];
    [super dealloc];
}

- (NSString *)filename
{
    return _filename;
}

- (void)setFilename:(NSString *)filename
{
    if (_filename != filename) {
        [_filename release];
        _filename = [filename retain];
    }
}

- (NSURL *)URL
{
    return _URL;
}

- (void)setURL:(NSURL *)url
{
    if (_URL != url) {
        [_URL release];
        _URL = [url retain];
    }
}

@end

@interface OMDPanelSelectionTests : XCTestCase
@end

@implementation OMDPanelSelectionTests

- (void)testOpenPanelReturnsFilenameArrayWhenAvailable
{
    OMDStubOpenPanel *panel = [[[OMDStubOpenPanel alloc] init] autorelease];
    [panel setFilenames:[NSArray arrayWithObjects:@"C:/tmp/alpha.md", @"C:/tmp/beta.md", nil]];

    NSArray *paths = OMDSelectedPathsFromOpenPanel((NSOpenPanel *)panel);
    XCTAssertEqualObjects(paths,
                          [NSArray arrayWithObjects:@"C:/tmp/alpha.md", @"C:/tmp/beta.md", nil]);
}

- (void)testOpenPanelFallsBackToSingleURL
{
    OMDStubOpenPanel *panel = [[[OMDStubOpenPanel alloc] init] autorelease];
    [panel setURL:[NSURL fileURLWithPath:@"/tmp/fallback.md"]];

    NSArray *paths = OMDSelectedPathsFromOpenPanel((NSOpenPanel *)panel);
    XCTAssertEqualObjects(paths, [NSArray arrayWithObject:@"/tmp/fallback.md"]);
}

- (void)testSavePanelPrefersFileURLPath
{
    OMDStubSavePanel *panel = [[[OMDStubSavePanel alloc] init] autorelease];
    [panel setURL:[NSURL fileURLWithPath:@"/tmp/output.md"]];
    [panel setFilename:@"/tmp/older.md"];

    XCTAssertEqualObjects(OMDSelectedPathFromSavePanel((NSSavePanel *)panel),
                          @"/tmp/output.md");
}

- (void)testSavePanelFallsBackToFilename
{
    OMDStubSavePanel *panel = [[[OMDStubSavePanel alloc] init] autorelease];
    [panel setFilename:@"/tmp/fallback.md"];

    XCTAssertEqualObjects(OMDSelectedPathFromSavePanel((NSSavePanel *)panel),
                          @"/tmp/fallback.md");
}

@end
