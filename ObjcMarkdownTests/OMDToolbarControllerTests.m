// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDToolbarController.h"

@interface OMDToolbarControllerTestDelegate : NSObject <OMDToolbarControllerDelegate>
@end

@implementation OMDToolbarControllerTestDelegate

- (BOOL)hasLoadedDocument { return YES; }
- (BOOL)canSaveCurrentDocument { return NO; }
- (BOOL)isExplorerSidebarVisible { return NO; }
- (void)updateModeControlSelection {}
- (void)toggleExplorerSidebar:(id)sender { (void)sender; }
- (void)openDocument:(id)sender { (void)sender; }
- (NSMenu *)recentDocumentsMenu { return [[[NSMenu alloc] initWithTitle:@""] autorelease]; }
- (void)saveDocument:(id)sender { (void)sender; }

- (NSToolbarItem *)shareToolbarItemWithIdentifier:(NSString *)identifier
{
    return [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
}

@end

@interface OMDToolbarControllerTests : XCTestCase
@end

@implementation OMDToolbarControllerTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (NSInteger)priorityOf:(NSString *)identifier in:(OMDToolbarController *)controller
{
    NSToolbarItem *item = [controller toolbar:nil
                        itemForItemIdentifier:identifier
                    willBeInsertedIntoToolbar:YES];

    XCTAssertNotNil(item, @"%@", identifier);
    return [item visibilityPriority];
}

// A narrow window sends items into the overflow menu lowest priority first:
// Explorer, then Share, then Save, then Open (#280); Read/Edit/Split stays.
- (void)testItemsLeaveForTheOverflowMenuInOrder
{
    OMDToolbarControllerTestDelegate *delegate = [[[OMDToolbarControllerTestDelegate alloc] init] autorelease];
    OMDToolbarController *controller = [[[OMDToolbarController alloc] initWithDelegate:delegate] autorelease];
    NSInteger explorer = [self priorityOf:@"ToggleExplorer" in:controller];
    NSInteger share = [self priorityOf:@"ShareDocument" in:controller];
    NSInteger save = [self priorityOf:@"SaveDocument" in:controller];
    NSInteger open = [self priorityOf:@"OpenDocument" in:controller];
    NSInteger modes = [self priorityOf:@"ModeControls" in:controller];

    XCTAssertTrue(explorer < share);
    XCTAssertTrue(share < save);
    XCTAssertTrue(save < open);
    XCTAssertTrue(open < modes);
}

@end
