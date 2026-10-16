// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"

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
    OMDShareItem *(^_toolbarItemProvider)(void);
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

- (void)dealloc
{
    [_picker setDelegate:nil];
    [_picker release];
    [_service setDelegate:nil];
    [_service release];
    if (_toolbarItemProvider != NULL) {
        Block_release(_toolbarItemProvider);
    }
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
    [_picker setDelegate:nil];
    [_picker release];
    _picker = [[NSSharingServicePicker alloc] initWithItems:items];
    [_picker setDelegate:self];
    [_picker showRelativeToRect:[view bounds] ofView:view preferredEdge:NSRectEdgeMinY];
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
    NSSharingService *mail = [NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail];
    if (OMDMailIsDefaultMailApp() && mail != nil && [items count] > 0 && [mail canPerformWithItems:items]) {
        [mail setSubject:([item title] != nil ? [item title] : @"")];
        [self setService:mail];
        [mail performWithItems:items];
        return;
    }
    [self emailShareItemWithMailtoDraft:item forWindow:window];
}

- (NSToolbarItem *)shareToolbarItemWithIdentifier:(NSString *)identifier
                                     itemProvider:(OMDShareItem *(^)(void))provider
{
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

// Asked when the item is clicked: exports in the last-used format.
- (NSArray *)itemsForSharingServicePickerToolbarItem:(NSSharingServicePickerToolbarItem *)pickerToolbarItem
{
    (void)pickerToolbarItem;
    OMDShareItem *item = (_toolbarItemProvider != NULL ? _toolbarItemProvider() : nil);
    return OMDPickerItems(item);
}

#pragma mark NSSharingServicePickerDelegate

- (id<NSSharingServiceDelegate>)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker
                           delegateForSharingService:(NSSharingService *)sharingService
{
    (void)sharingServicePicker;
    (void)sharingService;
    return self;
}

- (void)sharingServicePicker:(NSSharingServicePicker *)sharingServicePicker
     didChooseSharingService:(NSSharingService *)service
{
    (void)service;
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
