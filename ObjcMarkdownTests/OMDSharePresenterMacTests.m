// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

// The macOS share presenter without its UI: what it adds to Apple's
// picker (rclone links, from a stand-in rclone), its toolbar item and the
// email paths that answer without opening anything. Built only by
// macos/Makefile.

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if !defined(GNUSTEP)
#import "OMDSharePresenter.h"
#import "GSSharingRclone.h"

@interface OMDSharePresenterMacTests : XCTestCase
{
    NSString *_folder;
    NSURL *_file;
}
@end

@implementation OMDSharePresenterMacTests

- (void)setUp
{
    [super setUp];
    NSString *name = [NSString stringWithFormat:@"OMDSharePresenterMacTests-%@",
                                                [[NSProcessInfo processInfo] globallyUniqueString]];
    _folder = [[NSTemporaryDirectory() stringByAppendingPathComponent:name] retain];
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    NSString *path = [_folder stringByAppendingPathComponent:@"Q3 Plan.pdf"];
    [@"%PDF-1.4\n" writeToFile:path atomically:YES encoding:NSASCIIStringEncoding error:NULL];
    _file = [[NSURL fileURLWithPath:path] retain];
}

- (void)tearDown
{
    [GSSharingRclone setExecutablePath:nil];
    [GSSharingRclone forgetRemotes];
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [_folder release];
    [_file release];
    [super tearDown];
}

// A stand-in rclone whose listremotes prints listing, or fails with
// failure on stderr.
- (void)useRcloneListing:(NSString *)listing failure:(NSString *)failure
{
    NSString *path = [_folder stringByAppendingPathComponent:@"rclone"];
    NSString *script = (failure != nil)
        ? [NSString stringWithFormat:@"#!/bin/sh\necho '%@' >&2\nexit 1\n", failure]
        : [NSString stringWithFormat:@"#!/bin/sh\nprintf '%@'\n", listing];
    [script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0700]
                                                                              forKey:NSFilePosixPermissions]
                                     ofItemAtPath:path error:NULL];
    [GSSharingRclone setExecutablePath:path];
}

// A presenter, once the look for remotes it starts has finished (the
// picker lists what that look found).
- (id<OMDSharePresenter>)presenterAfterItsLook
{
    XCTNSNotificationExpectation *done =
        [[[XCTNSNotificationExpectation alloc] initWithName:GSSharingRcloneRemotesDidChangeNotification] autorelease];
    id<OMDSharePresenter> presenter = [OMDCreatePlatformSharePresenter() autorelease];
    [self waitForExpectations:[NSArray arrayWithObject:done] timeout:10.0];
    return presenter;
}

- (NSArray *)pickerTitlesFrom:(id<OMDSharePresenter>)presenter items:(NSArray *)items proposed:(NSArray *)proposed
{
    XCTAssertTrue([presenter respondsToSelector:@selector(sharingServicePicker:sharingServicesForItems:proposedSharingServices:)]);
    NSSharingServicePicker *picker = [[[NSSharingServicePicker alloc] initWithItems:items] autorelease];
    NSArray *services = [(id<NSSharingServicePickerDelegate>)presenter sharingServicePicker:picker
                                                                    sharingServicesForItems:items
                                                                    proposedSharingServices:proposed];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSSharingService *service in services) {
        [titles addObject:[service title]];
    }
    return titles;
}

- (NSArray *)pickerTitlesForItems:(NSArray *)items proposed:(NSArray *)proposed
{
    return [self pickerTitlesFrom:[self presenterAfterItsLook] items:items proposed:proposed];
}

- (void)testThePickerGetsALinkPerRemoteThatCanMakeOne
{
    [self useRcloneListing:@"Work Drive: onedrive\\nPhotos:     s3\\nPersonal:   drive\\n" failure:nil];
    NSArray *titles = [self pickerTitlesForItems:[NSArray arrayWithObject:_file] proposed:[NSArray array]];
    XCTAssertEqualObjects(titles, ([NSArray arrayWithObjects:@"Link on Work Drive (OneDrive)",
                                                             @"Link on Personal (Google Drive)", nil]));
}

- (void)testAppleServicesComeFirst
{
    [self useRcloneListing:@"Personal: drive\\n" failure:nil];
    NSSharingService *apple = [[[NSSharingService alloc] initWithTitle:@"Apple" image:[NSImage imageNamed:NSImageNameNetwork]
                                                        alternateImage:nil handler:^{}] autorelease];
    NSArray *titles = [self pickerTitlesForItems:[NSArray arrayWithObject:_file]
                                        proposed:[NSArray arrayWithObject:apple]];
    XCTAssertEqualObjects(titles, ([NSArray arrayWithObjects:@"Apple", @"Link on Personal (Google Drive)", nil]));
}

- (void)testNoLinksWithoutAFile
{
    [self useRcloneListing:@"Personal: drive\\n" failure:nil];
    NSArray *items = [NSArray arrayWithObject:[NSURL URLWithString:@"https://example.com/"]];
    XCTAssertEqual([[self pickerTitlesForItems:items proposed:[NSArray array]] count], (NSUInteger)0);
}

- (void)testAnEncryptedConfigIsOneLockedService
{
    [self useRcloneListing:nil failure:@"Failed to load config file: unable to decrypt configuration"];
    NSArray *titles = [self pickerTitlesForItems:[NSArray arrayWithObject:_file] proposed:[NSArray array]];
    XCTAssertEqual([[GSSharingRclone lastRemotesError] code], (NSInteger)GSSharingRcloneErrorNeedsPassword);
    XCTAssertEqualObjects(titles, [NSArray arrayWithObject:@"Link with rclone (Locked)"]);
}

- (void)testNoRcloneNoLinks
{
    [GSSharingRclone setExecutablePath:[_folder stringByAppendingPathComponent:@"missing-rclone"]];
    if ([GSSharingRclone executablePath] != nil) {
        return;
    }
    id<OMDSharePresenter> presenter = [OMDCreatePlatformSharePresenter() autorelease];
    XCTAssertEqual([[self pickerTitlesFrom:presenter items:[NSArray arrayWithObject:_file] proposed:[NSArray array]] count],
                   (NSUInteger)0);
}

- (void)testTheToolbarItemIsApplesAndSharesTheExportedFile
{
    id<OMDSharePresenter> presenter = [OMDCreatePlatformSharePresenter() autorelease];
    OMDShareItem *item = [[[OMDShareItem alloc] initWithTitle:@"Q3 Plan" format:OMDShareFormatPDF
                                                      fileURL:_file renderedText:nil] autorelease];
    NSToolbarItem *toolbarItem = [presenter shareToolbarItemWithIdentifier:@"ShareDocument"
                                                              itemProvider:^OMDShareItem *(void) { return item; }];
    XCTAssertTrue([toolbarItem isKindOfClass:[NSSharingServicePickerToolbarItem class]]);
    NSSharingServicePickerToolbarItem *picker = (NSSharingServicePickerToolbarItem *)toolbarItem;
    NSArray *items = [[picker delegate] itemsForSharingServicePickerToolbarItem:picker];
    XCTAssertEqualObjects(items, [NSArray arrayWithObject:_file]);
}

- (void)testInTheMessageWithoutRenderedTextLeavesItToTheController
{
    id<OMDSharePresenter> presenter = [OMDCreatePlatformSharePresenter() autorelease];
    OMDShareItem *item = [[[OMDShareItem alloc] initWithTitle:@"Q3 Plan" format:OMDShareFormatPDF
                                                      fileURL:nil renderedText:nil] autorelease];
    XCTAssertFalse([presenter emailRenderedDocument:item forWindow:nil]);
}

- (void)testMailsComposeServiceTakesARichBodyAndAFile
{
    NSSharingService *mail = [NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail];
    // A build machine may have no Mail to compose with.
    XCTSkipIf(mail == nil, @"No Mail compose service here");
    NSAttributedString *body = [[[NSAttributedString alloc] initWithString:@"Plan"] autorelease];
    NSArray *items = [NSArray arrayWithObjects:body, _file, nil];
    XCTAssertTrue([mail canPerformWithItems:items]);
}

// libs-sharing 0b93d2e (#225): a look for remotes keeps the ones found
// before until it's done, so a picker opened meanwhile still lists them.
- (void)testRemotesStayWhileARefreshRuns
{
    [self useRcloneListing:@"Personal: drive\\n" failure:nil];
    [self presenterAfterItsLook];
    // A new window's presenter starts another look; the picker, opened
    // meanwhile, still has the remotes found before.
    id<OMDSharePresenter> presenter = [OMDCreatePlatformSharePresenter() autorelease];
    NSArray *titles = [self pickerTitlesFrom:presenter items:[NSArray arrayWithObject:_file] proposed:[NSArray array]];
    XCTAssertEqualObjects(titles, [NSArray arrayWithObject:@"Link on Personal (Google Drive)"]);
    XCTNSNotificationExpectation *done =
        [[[XCTNSNotificationExpectation alloc] initWithName:GSSharingRcloneRemotesDidChangeNotification] autorelease];
    [self waitForExpectations:[NSArray arrayWithObject:done] timeout:10.0];
}

@end
#endif
