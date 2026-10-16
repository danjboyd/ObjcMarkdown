// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"

#if defined(GNUSTEP) && !defined(_WIN32)
#import "OMDExternalTools.h"
#import "OMDShareNotice.h"
#import "OMDShareMail.h"

#include <fcntl.h>
#include <unistd.h>
#include <gio/gio.h>
#include <gio/gunixfdlist.h>

// Linux and the BSDs (#174). There is no system share sheet, so Share
// shows our picker; email goes to the default mail app with the file
// attached where that app can take one; Show in Folder asks the file
// manager. Inside the Flatpak sandbox, email and Show in Folder go through
// the desktop portals.
@interface OMDSharePresenterLinux : OMDShareBasicPresenter
@end

static BOOL OMDRunningInFlatpak(void)
{
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/.flatpak-info"];
}

// The default mailto: handler's desktop file ID ("org.gnome.Evolution.desktop"),
// or nil when there is none.
static NSString *OMDDefaultMailAppID(void)
{
    GAppInfo *app = g_app_info_get_default_for_uri_scheme("mailto");
    if (app == NULL) {
        return nil;
    }
    const char *identifier = g_app_info_get_id(app);
    const char *executable = g_app_info_get_executable(app);
    NSString *result = nil;
    if (identifier != NULL) {
        result = [NSString stringWithUTF8String:identifier];
    } else if (executable != NULL) {
        result = [[NSString stringWithUTF8String:executable] lastPathComponent];
    }
    g_object_unref(app);
    return result;
}

// Calls a desktop portal method that takes the file as a descriptor (the
// sandbox can't hand over paths). Returns NO if the portal isn't there.
static BOOL OMDCallPortalWithFile(const char *interface,
                                  const char *method,
                                  NSString *path,
                                  GVariant *(^parameters)(gint32 handle))
{
    GError *error = NULL;
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (bus == NULL) {
        g_clear_error(&error);
        return NO;
    }
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        g_object_unref(bus);
        return NO;
    }
    GUnixFDList *fds = g_unix_fd_list_new();
    gint32 handle = g_unix_fd_list_append(fds, fd, &error);
    close(fd);
    BOOL called = NO;
    if (handle >= 0) {
        GVariant *reply = g_dbus_connection_call_with_unix_fd_list_sync(bus,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            interface, method,
            parameters(handle),
            NULL, G_DBUS_CALL_FLAGS_NONE, -1, fds, NULL, NULL, &error);
        if (reply != NULL) {
            called = YES;
            g_variant_unref(reply);
        }
    }
    g_clear_error(&error);
    g_object_unref(fds);
    g_object_unref(bus);
    return called;
}

@implementation OMDSharePresenterLinux

- (void)presentShareItem:(OMDShareItem *)item fromView:(NSView *)view
{
    [OMDShareNotice showPickerForShareItem:item presenter:self forWindow:[view window]];
}

- (void)emailShareItem:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    NSString *path = [[item fileURL] path];
    NSString *subject = [item title];

    if (OMDRunningInFlatpak()) {
        // The portal hands the file to the mail app as best it can.
        BOOL sent = OMDCallPortalWithFile("org.freedesktop.portal.Email", "ComposeEmail", path,
            ^GVariant *(gint32 handle) {
                GVariantBuilder options;
                g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
                g_variant_builder_add(&options, "{sv}", "subject",
                                      g_variant_new_string([subject UTF8String]));
                GVariantBuilder handles;
                g_variant_builder_init(&handles, G_VARIANT_TYPE("ah"));
                g_variant_builder_add(&handles, "h", handle);
                g_variant_builder_add(&options, "{sv}", "attachment_fds",
                                      g_variant_builder_end(&handles));
                return g_variant_new("(sa{sv})", "", &options);
            });
        if (!sent) {
            [self emailShareItemWithMailtoDraft:item forWindow:window];
        }
        return;
    }

    NSString *appID = OMDDefaultMailAppID();
    NSString *xdgEmail = OMDExecutablePathNamed(@"xdg-email");
    if (xdgEmail != nil && OMDMailAppTakesAttachments(appID)) {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:xdgEmail];
        [task setArguments:[NSArray arrayWithObjects:@"--subject", subject, @"--attach", path, nil]];
        @try {
            [task launch];
            return;
        } @catch (NSException *exception) {
            (void)exception;
        }
    }
    if (appID == nil) {
        NSString *message = [NSString stringWithFormat:@"There's no email app set up. \u201C%@\u201D is ready to attach.",
                                                       [item fileName]];
        [OMDShareNotice showNoticeWithMessage:message shareItem:item presenter:self forWindow:window];
        return;
    }
    // A webmail tab or another app that can't take the file: the draft,
    // and the file to drag into it.
    OMDOpenURL(OMDMailtoURLWithSubject(subject));
    NSString *message = [NSString stringWithFormat:@"Your email app can't receive attachments directly. Attach \u201C%@\u201D to the email.",
                                                   [item fileName]];
    [OMDShareNotice showNoticeWithMessage:message shareItem:item presenter:self forWindow:window];
}

- (void)showShareItemInFolder:(OMDShareItem *)item
{
    NSString *path = [[item fileURL] path];
    if (OMDRunningInFlatpak() &&
        OMDCallPortalWithFile("org.freedesktop.portal.OpenURI", "OpenDirectory", path,
            ^GVariant *(gint32 handle) {
                GVariantBuilder options;
                g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
                return g_variant_new("(sha{sv})", "", handle, &options);
            })) {
        return;
    }
    [super showShareItemInFolder:item];
}

@end

id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void)
{
    return [[OMDSharePresenterLinux alloc] init];
}
#endif
