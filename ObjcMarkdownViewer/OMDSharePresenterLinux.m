// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"

#if defined(GNUSTEP) && !defined(_WIN32)
#import "OMDShareMail.h"
#import "GSSharing.h"

#include <gio/gio.h>

// Linux and the BSDs (#174, #196). The share sheet and the services are
// libs-sharing's (third_party/libs-sharing): Email through the portals or
// the mail app (the document portal for a Flatpak one), Copy, Show in
// Folder. This presenter hands the file to them by name.
@interface OMDSharePresenterLinux : OMDShareBasicPresenter
@end

static BOOL OMDPerformSharingService(NSString *name, OMDShareItem *item)
{
    NSURL *file = [item fileURL];
    NSSharingService *service = [NSSharingService sharingServiceNamed:name];
    if (service == nil || file == nil) {
        return NO;
    }
    [service setSubject:[item title]];
    [service performWithItems:[NSArray arrayWithObject:file]];
    return YES;
}

@implementation OMDSharePresenterLinux

- (void)presentShareItem:(OMDShareItem *)item fromView:(NSView *)view
{
    // The share controller shows the sheet with its format switcher; this
    // is the sheet for a file alone.
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc]
                                         initWithItems:[NSArray arrayWithObject:[item fileURL]]];
    [picker showRelativeToRect:[view bounds] ofView:view preferredEdge:NSMinYEdge];
    [picker autorelease];
}

- (void)emailShareItem:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    if (!OMDPerformSharingService(NSSharingServiceNameComposeEmail, item)) {
        [super emailShareItem:item forWindow:window];
    }
}

- (void)showShareItemInFolder:(OMDShareItem *)item
{
    if (!OMDPerformSharingService(GSSharingServiceNameShowInFolder, item)) {
        [super showShareItemInFolder:item];
    }
}

- (void)copyFileOfShareItem:(OMDShareItem *)item
{
    if (!OMDPerformSharingService(GSSharingServiceNameCopy, item)) {
        [super copyFileOfShareItem:item];
    }
}

// The default mail app for a mailto: link, as GIO finds it (GNUstep's
// NSWorkspace has no mailto: handler and says so in an alert).
- (BOOL)openEmailDraftWithSubject:(NSString *)subject
{
    const char *uri = [[OMDMailtoURLWithSubject(subject) absoluteString] UTF8String];
    GError *error = NULL;
    gboolean launched = (uri != NULL) && g_app_info_launch_default_for_uri(uri, NULL, &error);
    g_clear_error(&error);
    return launched ? YES : NO;
}

@end

id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void)
{
    return [[OMDSharePresenterLinux alloc] init];
}
#endif
