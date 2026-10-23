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

static BOOL OMDPerformSharingServiceOnFile(NSString *name, OMDShareItem *item, NSURL *file)
{
    NSSharingService *service = [NSSharingService sharingServiceNamed:name];
    if (service == nil || file == nil) {
        return NO;
    }
    [service setSubject:[item title]];
    [service performWithItems:[NSArray arrayWithObject:file]];
    return YES;
}

static BOOL OMDPerformSharingService(NSString *name, OMDShareItem *item)
{
    return OMDPerformSharingServiceOnFile(name, item, [item fileURL]);
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
    if (!OMDPerformSharingServiceOnFile(GSSharingServiceNameShowInFolder, item, [item folderURL])) {
        [super showShareItemInFolder:item];
    }
}

- (void)copyFileOfShareItem:(OMDShareItem *)item
{
    if (!OMDPerformSharingService(GSSharingServiceNameCopy, item)) {
        [super copyFileOfShareItem:item];
    }
}

// In the Message with Thunderbird as the mail app: the draft opens with the
// HTML file as its body (-compose message=), so nothing needs pasting. Not
// for a Flatpak Thunderbird, which can't read the file (the paste route).
- (BOOL)emailRenderedDocument:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    (void)window;
    NSString *path = [[item fileURL] path];
    if (path == nil) {
        return NO;
    }
    GAppInfo *app = g_app_info_get_default_for_uri_scheme("mailto");
    if (app == NULL) {
        return NO;
    }
    NSString *appID = g_app_info_get_id(app) != NULL
        ? [NSString stringWithUTF8String:g_app_info_get_id(app)] : nil;
    NSString *executable = g_app_info_get_executable(app) != NULL
        ? [NSString stringWithUTF8String:g_app_info_get_executable(app)] : nil;
    g_object_unref(app);
    NSString *argument = OMDThunderbirdComposeArgument([item title], path);
    if (!OMDMailAppIsThunderbird(appID) || argument == nil ||
        [[executable lastPathComponent] isEqualToString:@"flatpak"]) {
        return NO;
    }
    NSString *launchPath = [executable isAbsolutePath] ? executable : nil;
    if (launchPath == nil) {
        NSArray *paths = [[[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"]
                             componentsSeparatedByString:@":"];
        for (NSString *directory in paths) {
            NSString *candidate = [directory stringByAppendingPathComponent:executable];
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
                launchPath = candidate;
                break;
            }
        }
    }
    if (launchPath == nil) {
        return NO;
    }
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:launchPath];
    [task setArguments:[NSArray arrayWithObjects:@"-compose", argument, nil]];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
    return YES;
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
