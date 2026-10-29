// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"
#import "OMDShareChecks.h"
#import "OMDShareRcloneMac.h"

#if !defined(GNUSTEP)

static NSString * const OMDAppleMailBundleIdentifier = @"com.apple.mail";

// macOS: the system's sharing picker (Mail, Messages, AirDrop and the
// installed apps' share extensions) and its toolbar item. Email goes to
// Mail with the rendered document as the body; when the default mail app is
// another one, the basic presenter's mailto: draft and notice. Show in
// Folder and Copy File are the basic presenter's.
@interface OMDSharePresenterMac : OMDShareBasicPresenter <NSSharingServicePickerDelegate,
                                                          NSSharingServicePickerToolbarItemDelegate,
                                                          NSSharingServiceDelegate>
{
    // Kept while shown: the picker and a service at work.
    NSSharingServicePicker *_picker;
    NSSharingService *_service;
    BOOL (^_toolbarCanShare)(void);
    OMDShareItem *(^_toolbarItemProvider)(void);
    // The file the toolbar item's last share exported, for rclone's links
    // (its picker is handed a provider, not the file).
    NSURL *_toolbarFile;
    // While the confirm sheet is up: its .zip button, which Selection only
    // turns off (not retained; the alert holds it).
    NSButton *_bundleButton;
    // Links through rclone, in the picker.
    OMDShareRcloneMac *_rclone;
    // The window of the last share (not retained), for rclone's sheets.
    NSWindow *_shareWindow;
}
@end

id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void)
{
    return [[OMDSharePresenterMac alloc] init];
}

// Whether Mail opens mailto: links. Mail's compose service opens Mail
// whatever the default is, so it's used only then.
static BOOL OMDMailIsDefaultMailApp(void)
{
    NSURL *app = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:[NSURL URLWithString:@"mailto:"]];
    NSString *identifier = (app != nil ? [[NSBundle bundleWithURL:app] bundleIdentifier] : nil);
    return identifier == nil ||
           [identifier caseInsensitiveCompare:OMDAppleMailBundleIdentifier] == NSOrderedSame;
}

// What the picker shares: the exported file. (The rendered text goes only
// to Mail, as the body; Messages and others would paste it beside the file.)
static NSArray *OMDPickerItems(OMDShareItem *item)
{
    return ([item fileURL] != nil ? [NSArray arrayWithObject:[item fileURL]] : [NSArray array]);
}

@implementation OMDSharePresenterMac

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _rclone = [[OMDShareRcloneMac alloc] init];
        [OMDShareRcloneMac refreshRemotes];
    }
    return self;
}

- (void)dealloc
{
    [_rclone release];
    [_picker setDelegate:nil];
    [_picker release];
    [_service setDelegate:nil];
    [_service release];
    if (_toolbarCanShare != NULL) {
        Block_release(_toolbarCanShare);
    }
    if (_toolbarItemProvider != NULL) {
        Block_release(_toolbarItemProvider);
    }
    [_toolbarFile release];
    [super dealloc];
}

- (void)setService:(NSSharingService *)service
{
    if (service == _service) {
        return;
    }
    [_service setDelegate:nil];
    [_service release];
    _service = [service retain];
    [_service setDelegate:self];
}

#pragma mark OMDSharePresenter

- (void)presentShareItem:(OMDShareItem *)item fromView:(NSView *)view
{
    NSArray *items = OMDPickerItems(item);
    if ([items count] == 0 || view == nil) {
        [super presentShareItem:item fromView:view];
        return;
    }
    _shareWindow = [view window];
    [_picker setDelegate:nil];
    [_picker release];
    _picker = [[NSSharingServicePicker alloc] initWithItems:items];
    [_picker setDelegate:self];
    [_picker showRelativeToRect:[view bounds] ofView:view preferredEdge:NSRectEdgeMinY];
}

// A Mail draft with the items (the rendered body, the file) and the title
// as the subject; NO when Mail isn't the default mail app or can't take
// them.
- (BOOL)composeMailWithItems:(NSArray *)items title:(NSString *)title
{
    NSSharingService *mail = [NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail];
    if (!OMDMailIsDefaultMailApp() || mail == nil || [items count] == 0 || ![mail canPerformWithItems:items]) {
        return NO;
    }
    [mail setSubject:(title != nil ? title : @"")];
    [self setService:mail];
    [mail performWithItems:items];
    return YES;
}

- (void)emailShareItem:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    NSMutableArray *items = [NSMutableArray array];
    if ([item renderedText] != nil) {
        [items addObject:[item renderedText]];
    }
    if ([item fileURL] != nil) {
        [items addObject:[item fileURL]];
    }
    if (![self composeMailWithItems:items title:[item title]]) {
        [self emailShareItemWithMailtoDraft:item forWindow:window];
    }
}

// Email as > In the Message: the rendered document as Mail's body. With
// another mail app the share controller puts it on the clipboard instead.
- (BOOL)emailRenderedDocument:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    (void)window;
    if ([item renderedText] == nil) {
        return NO;
    }
    return [self composeMailWithItems:[NSArray arrayWithObject:[item renderedText]] title:[item title]];
}

// Before sharing: what the reader won't get, with PDF or the .zip as
// alternatives, and the selection when text is selected. A sheet on the
// window. Sharing the whole document is the default: a stray selection
// shouldn't quietly cut the share short. Without warnings, the selection is
// its own button; with them, a Selection only checkbox (off).
- (void)confirmShareWithWarnings:(NSArray *)warnings
                          format:(OMDShareFormat)format
                    hasSelection:(BOOL)hasSelection
                       forWindow:(NSWindow *)window
                      completion:(void (^)(OMDShareWarningChoice choice, BOOL selectionOnly))completion
{
    BOOL offersPDF = NO;
    BOOL offersBundle = NO;
    NSMutableArray *messages = [NSMutableArray array];
    for (OMDShareWarning *warning in warnings) {
        [messages addObject:[warning messageForFormat:format]];
        offersPDF = offersPDF || ([warning suggestsPDF] && format != OMDShareFormatPDF);
        offersBundle = offersBundle || ([warning offersBundle] && format == OMDShareFormatMarkdown);
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    // Each button's choice, and whether it shares the selection, in button
    // order (NSAlertFirstButtonReturn onwards).
    NSMutableArray *choices = [NSMutableArray array];
    NSMutableArray *selections = [NSMutableArray array];
    NSButton *selectionOnly = nil;
    if ([messages count] == 0) {
        [alert setMessageText:@"Share the whole document or the selection?"];
        [alert setInformativeText:@"Part of the document is selected."];
        [alert addButtonWithTitle:@"Share Document"];
        [choices addObject:[NSNumber numberWithInteger:OMDShareWarningChoiceContinue]];
        [selections addObject:[NSNumber numberWithBool:NO]];
        [alert addButtonWithTitle:@"Cancel"];
        [choices addObject:[NSNumber numberWithInteger:OMDShareWarningChoiceCancel]];
        [selections addObject:[NSNumber numberWithBool:NO]];
        [alert addButtonWithTitle:@"Share Selection"];
        [choices addObject:[NSNumber numberWithInteger:OMDShareWarningChoiceContinue]];
        [selections addObject:[NSNumber numberWithBool:YES]];
    } else {
        [alert setMessageText:@"The reader may not get all of this document."];
        [alert setInformativeText:[messages componentsJoinedByString:@"\n"]];
        [alert addButtonWithTitle:@"Share"];
        [choices addObject:[NSNumber numberWithInteger:OMDShareWarningChoiceContinue]];
        [alert addButtonWithTitle:@"Cancel"];
        [choices addObject:[NSNumber numberWithInteger:OMDShareWarningChoiceCancel]];
        if (offersPDF) {
            [alert addButtonWithTitle:@"Share as PDF"];
            [choices addObject:[NSNumber numberWithInteger:OMDShareWarningChoicePDF]];
        }
        if (offersBundle) {
            _bundleButton = [alert addButtonWithTitle:@"Share as .zip with Images"];
            [choices addObject:[NSNumber numberWithInteger:OMDShareWarningChoiceBundle]];
        }
        if (hasSelection) {
            selectionOnly = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
            [selectionOnly setButtonType:NSSwitchButton];
            [selectionOnly setTitle:@"Selection only"];
            [selectionOnly setState:NSOffState];
            [selectionOnly setTarget:self];
            [selectionOnly setAction:@selector(selectionOnlyChanged:)];
            [selectionOnly sizeToFit];
            [alert setAccessoryView:selectionOnly];
        }
    }

    void (^done)(OMDShareWarningChoice, BOOL) = Block_copy(completion);
    void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
        NSInteger index = response - NSAlertFirstButtonReturn;
        OMDShareWarningChoice choice = OMDShareWarningChoiceCancel;
        BOOL onlySelection = NO;
        if (index >= 0 && (NSUInteger)index < [choices count]) {
            choice = (OMDShareWarningChoice)[[choices objectAtIndex:index] integerValue];
            onlySelection = ((NSUInteger)index < [selections count])
                ? [[selections objectAtIndex:index] boolValue]
                : (selectionOnly != nil && [selectionOnly state] == NSOnState);
        }
        // The .zip is of the whole document.
        if (choice == OMDShareWarningChoiceBundle) {
            onlySelection = NO;
        }
        _bundleButton = nil;
        done(choice, onlySelection);
        Block_release(done);
    };
    if (window != nil) {
        [alert beginSheetModalForWindow:window completionHandler:handler];
    } else {
        handler([alert runModal]);
    }
}

- (void)selectionOnlyChanged:(id)sender
{
    [_bundleButton setEnabled:([sender state] != NSOnState)];
}

- (NSToolbarItem *)shareToolbarItemWithIdentifier:(NSString *)identifier
                                         canShare:(BOOL (^)(void))canShare
                                     itemProvider:(OMDShareItem *(^)(void))provider
{
    if (_toolbarCanShare != NULL) {
        Block_release(_toolbarCanShare);
    }
    _toolbarCanShare = (canShare != NULL ? Block_copy(canShare) : NULL);
    if (_toolbarItemProvider != NULL) {
        Block_release(_toolbarItemProvider);
    }
    _toolbarItemProvider = (provider != NULL ? Block_copy(provider) : NULL);
    NSSharingServicePickerToolbarItem *item =
        [[[NSSharingServicePickerToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    [item setDelegate:self];
    return item;
}

#pragma mark NSSharingServicePickerToolbarItemDelegate

// The toolbar item's export, when the picker loads the file: the file, or
// nil after the share controller's alert.
- (NSURL *)exportToolbarFile
{
    OMDShareItem *item = (_toolbarItemProvider != NULL ? _toolbarItemProvider() : nil);
    [_toolbarFile release];
    _toolbarFile = [[item fileURL] retain];
    return _toolbarFile;
}

// Asked whenever AppKit likes: when the item is made (-setDelegate:), when
// the toolbar is validated, on a click. So nothing is exported here (#236):
// no document, no items; otherwise a provider of the file's URL, which the
// picker loads when it opens. The picker lists no services for a provider
// of a file representation, and none when the URL comes later, so the
// export is done at once on the main thread, where the picker asks.
- (NSArray *)itemsForSharingServicePickerToolbarItem:(NSSharingServicePickerToolbarItem *)pickerToolbarItem
{
    (void)pickerToolbarItem;
    if (_toolbarItemProvider == NULL || _toolbarCanShare == NULL || !_toolbarCanShare()) {
        return [NSArray array];
    }
    NSItemProvider *provider = [[[NSItemProvider alloc] init] autorelease];
    [provider registerObjectOfClass:[NSURL class]
                         visibility:NSItemProviderRepresentationVisibilityAll
                        loadHandler:^NSProgress *(void (^completion)(id<NSItemProviderWriting>, NSError *)) {
        void (^load)(void) = ^{
            NSURL *file = [self exportToolbarFile];
            completion(file, (file != nil ? nil : [NSError errorWithDomain:NSCocoaErrorDomain
                                                                     code:NSUserCancelledError
                                                                 userInfo:nil]));
        };
        if ([NSThread isMainThread]) {
            load();
        } else {
            dispatch_async(dispatch_get_main_queue(), load);
        }
        return nil;
    }];
    return [NSArray arrayWithObject:provider];
}

#pragma mark NSSharingServicePickerDelegate

- (id<NSSharingServiceDelegate>)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker
                           delegateForSharingService:(NSSharingService *)sharingService
{
    (void)sharingServicePicker;
    (void)sharingService;
    return self;
}

// Apple's services, then a link through each rclone remote.
- (NSArray *)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker
          sharingServicesForItems:(NSArray *)items
          proposedSharingServices:(NSArray *)proposedServices
{
    (void)sharingServicePicker;
    NSURL *file = nil;
    for (id item in items) {
        if ([item isKindOfClass:[NSURL class]] && [item isFileURL]) {
            file = item;
            break;
        }
        // The toolbar item's provider, loaded as the picker opened.
        if ([item isKindOfClass:[NSItemProvider class]] && [_toolbarFile isFileURL]) {
            file = _toolbarFile;
            break;
        }
    }
    NSWindow *window = (_shareWindow != nil ? _shareWindow : [NSApp keyWindow]);
    NSArray *links = [_rclone sharingServicesForFile:file window:window];
    if ([links count] == 0) {
        return proposedServices;
    }
    return [proposedServices arrayByAddingObjectsFromArray:links];
}

- (void)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker
     didChooseSharingService:(NSSharingService *)service
{
    (void)service;
    // rclone's remotes may have changed by the next share.
    [OMDShareRcloneMac refreshRemotes];
    if (sharingServicePicker == _picker) {
        [_picker setDelegate:nil];
        [_picker autorelease];
        _picker = nil;
    }
}

#pragma mark NSSharingServiceDelegate

- (void)sharingService:(NSSharingService *)sharingService didShareItems:(NSArray *)items
{
    (void)items;
    if (sharingService == _service) {
        [self setService:nil];
    }
}

- (void)sharingService:(NSSharingService *)sharingService
   didFailToShareItems:(NSArray *)items
                 error:(NSError *)error
{
    (void)items;
    if (sharingService == _service) {
        [self setService:nil];
    }
    // Cancelling the compose window isn't a failure to report.
    if (!([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code] == NSUserCancelledError)) {
        NSLog(@"Share failed: %@", error);
    }
}

@end

#endif
