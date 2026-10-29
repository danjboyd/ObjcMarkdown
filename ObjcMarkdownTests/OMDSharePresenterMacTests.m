// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

// The macOS share presenter without its UI: what it adds to Apple's
// picker (rclone links, from a stand-in rclone), its toolbar item (which
// exports nothing until a share loads the file: #236) and the email paths
// that answer without opening anything. Built only by macos/Makefile.

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#if !defined(GNUSTEP)
#import "OMDSharePresenter.h"
#import "OMDShareController.h"
#import "GSSharingRclone.h"

// A document for the share controller that counts its PDF exports.
@interface OMDShareCountingSource : NSObject <OMDShareSource>
{
@public
    NSString *_text;
    NSUInteger _pdfWrites;
}
@end

@implementation OMDShareCountingSource
- (NSString *)shareBaseName { return @"Q3 Plan"; }
- (NSString *)shareSourceText { return _text; }
- (NSString *)shareSourceExtension { return @"md"; }
- (NSString *)shareMarkdownText { return _text; }
- (NSString *)shareResourceDirectory { return nil; }
- (NSAttributedString *)shareRenderedText { return nil; }
- (OMDDocumentConverter *)documentConverter { return nil; }
- (BOOL)shareWritePDFToPath:(NSString *)path
{
    _pdfWrites++;
    return [@"%PDF-1.4\n" writeToFile:path atomically:YES encoding:NSASCIIStringEncoding error:NULL];
}
@end

// A toolbar of the share controller's item alone, as the window's.
@interface OMDShareToolbarDelegate : NSObject <NSToolbarDelegate>
{
@public
    OMDShareController *_controller;
}
@end

@implementation OMDShareToolbarDelegate
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)identifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
    (void)toolbar;
    (void)flag;
    return [_controller toolbarItemWithIdentifier:identifier target:nil];
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    (void)toolbar;
    return [NSArray arrayWithObject:@"ShareDocument"];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [self toolbarDefaultItemIdentifiers:toolbar];
}
@end

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

// The file a picker item gives when a share loads it.
- (NSURL *)loadedFileFromItems:(NSArray *)items
{
    XCTAssertEqual([items count], (NSUInteger)1);
    NSItemProvider *provider = [items lastObject];
    XCTAssertTrue([provider isKindOfClass:[NSItemProvider class]]);
    XCTAssertTrue([provider canLoadObjectOfClass:[NSURL class]]);
    __block NSURL *loaded = nil;
    XCTestExpectation *done = [self expectationWithDescription:@"loaded"];
    [provider loadObjectOfClass:[NSURL class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        (void)error;
        loaded = [(NSURL *)object retain];
        [done fulfill];
    }];
    [self waitForExpectations:[NSArray arrayWithObject:done] timeout:10.0];
    return [loaded autorelease];
}

// AppKit asks for the items when the item is made and validated, not only
// on a click: they're a provider, and the export waits for the share.
- (void)testTheToolbarItemExportsOnlyWhenAShareLoadsTheFile
{
    [self useRcloneListing:@"Personal: drive\\n" failure:nil];
    id<OMDSharePresenter> presenter = [self presenterAfterItsLook];
    OMDShareItem *item = [[[OMDShareItem alloc] initWithTitle:@"Q3 Plan" format:OMDShareFormatPDF
                                                      fileURL:_file renderedText:nil] autorelease];
    __block NSUInteger exports = 0;
    NSToolbarItem *toolbarItem = [presenter shareToolbarItemWithIdentifier:@"ShareDocument"
                                                                  canShare:^BOOL (void) { return YES; }
                                                              itemProvider:^OMDShareItem *(void) {
        exports++;
        return item;
    }];
    XCTAssertTrue([toolbarItem isKindOfClass:[NSSharingServicePickerToolbarItem class]]);
    NSSharingServicePickerToolbarItem *picker = (NSSharingServicePickerToolbarItem *)toolbarItem;
    [[picker delegate] itemsForSharingServicePickerToolbarItem:picker];
    NSArray *items = [[picker delegate] itemsForSharingServicePickerToolbarItem:picker];
    XCTAssertEqual(exports, (NSUInteger)0);

    XCTAssertEqualObjects([self loadedFileFromItems:items], _file);
    XCTAssertEqual(exports, (NSUInteger)1);
    // The picker gets the provider; rclone's links are for the file it gave.
    XCTAssertEqualObjects([self pickerTitlesFrom:presenter items:items proposed:[NSArray array]],
                          [NSArray arrayWithObject:@"Link on Personal (Google Drive)"]);
}

- (void)testWithoutADocumentTheToolbarItemHasNothingToShare
{
    id<OMDSharePresenter> presenter = [OMDCreatePlatformSharePresenter() autorelease];
    __block NSUInteger exports = 0;
    NSSharingServicePickerToolbarItem *picker = (NSSharingServicePickerToolbarItem *)
        [presenter shareToolbarItemWithIdentifier:@"ShareDocument"
                                         canShare:^BOOL (void) { return NO; }
                                     itemProvider:^OMDShareItem *(void) {
            exports++;
            return nil;
        }];
    XCTAssertEqual([[[picker delegate] itemsForSharingServicePickerToolbarItem:picker] count], (NSUInteger)0);
    XCTAssertEqual(exports, (NSUInteger)0);
}

// #236: the share controller's item in a window's toolbar, shown and
// validated, with a document and with none: no export, so no alert.
- (void)testAWindowsToolbarExportsNothing
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setVolatileDomain:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:OMDShareFormatPDF]
                                                            forKey:@"OMDShareLastFormat"]
                        forName:NSArgumentDomain];
    OMDShareCountingSource *source = [[[OMDShareCountingSource alloc] init] autorelease];
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                    styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO] autorelease];
    [window setReleasedWhenClosed:NO];
    OMDShareController *controller = [[[OMDShareController alloc] initWithSource:source window:window] autorelease];
    OMDShareToolbarDelegate *delegate = [[[OMDShareToolbarDelegate alloc] init] autorelease];
    delegate->_controller = controller;
    // The document first: an export there fails the test before the
    // empty window's alert could block it.
    [self setContinueAfterFailure:NO];
    NSArray *texts = [NSArray arrayWithObjects:@"# Q3 Plan\n", [NSNull null], nil];
    for (id text in texts) {
        source->_text = (text != [NSNull null] ? text : nil);
        // A new toolbar each time: AppKit makes the item, as for a window.
        NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:[[NSProcessInfo processInfo] globallyUniqueString]] autorelease];
        [toolbar setDelegate:delegate];
        [window setToolbar:toolbar];
        [window orderFront:nil];
        [toolbar validateVisibleItems];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        NSSharingServicePickerToolbarItem *picker = (NSSharingServicePickerToolbarItem *)[[toolbar items] lastObject];
        XCTAssertTrue([picker isKindOfClass:[NSSharingServicePickerToolbarItem class]]);
        NSArray *items = [[picker delegate] itemsForSharingServicePickerToolbarItem:picker];
        [window orderOut:nil];
        [window setToolbar:nil];
        XCTAssertEqual(source->_pdfWrites, (NSUInteger)0);
        XCTAssertEqual([items count], (NSUInteger)(text != [NSNull null] ? 1 : 0));
    }
    [defaults removeVolatileDomainForName:NSArgumentDomain];
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

@end
#endif
