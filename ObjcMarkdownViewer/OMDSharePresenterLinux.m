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
#include <gio/gdesktopappinfo.h>

// The document portal takes O_PATH descriptors, which glibc only declares
// with _GNU_SOURCE (Linux's value; the BSDs have no document portal).
#if defined(__linux__) && !defined(O_PATH)
#define O_PATH 010000000
#endif
#if !defined(O_PATH)
#define O_PATH O_RDONLY
#endif

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
// or nil when there is none, and its Flatpak app ID when it is a Flatpak.
static NSString *OMDDefaultMailAppID(NSString **flatpakID)
{
    if (flatpakID != NULL) {
        *flatpakID = nil;
    }
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
    if (flatpakID != NULL && G_IS_DESKTOP_APP_INFO(app)) {
        char *flatpak = g_desktop_app_info_get_string(G_DESKTOP_APP_INFO(app), "X-Flatpak");
        if (flatpak != NULL && flatpak[0] != '\0') {
            *flatpakID = [NSString stringWithUTF8String:flatpak];
        }
        g_free(flatpak);
    }
    g_object_unref(app);
    return result;
}

// A path to the file that a sandboxed (Flatpak) app can read: the file
// exported through the document portal, with read access for that app
// only. A Flatpak mail app can't see our temporary folder, so it would
// drop the attachment. Nil if the portal isn't there.
static NSString *OMDDocumentPortalPathForFile(NSString *path, NSString *appID)
{
    GError *error = NULL;
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (bus == NULL) {
        g_clear_error(&error);
        return nil;
    }
    NSString *result = nil;
    int fd = open([path fileSystemRepresentation], O_PATH | O_CLOEXEC);
    GUnixFDList *fds = g_unix_fd_list_new();
    gint32 handle = fd >= 0 ? g_unix_fd_list_append(fds, fd, &error) : -1;
    if (fd >= 0) {
        close(fd);
    }
    GVariant *added = NULL;
    GVariant *mount = NULL;
    if (handle >= 0) {
        added = g_dbus_connection_call_with_unix_fd_list_sync(bus,
            "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
            "org.freedesktop.portal.Documents", "Add",
            g_variant_new("(hbb)", handle, TRUE, FALSE),
            G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NONE, -1, fds, NULL, NULL, &error);
    }
    if (added != NULL) {
        const char *docID = NULL;
        g_variant_get(added, "(&s)", &docID);
        const char *permissions[] = { "read", NULL };
        GVariant *granted = g_dbus_connection_call_sync(bus,
            "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
            "org.freedesktop.portal.Documents", "GrantPermissions",
            g_variant_new("(ss^as)", docID, [appID UTF8String], permissions),
            NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
        if (granted != NULL) {
            g_variant_unref(granted);
            mount = g_dbus_connection_call_sync(bus,
                "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
                "org.freedesktop.portal.Documents", "GetMountPoint",
                NULL, G_VARIANT_TYPE("(ay)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
        }
        if (mount != NULL) {
            const char *mountPoint = NULL;
            g_variant_get(mount, "(^&ay)", &mountPoint);
            if (mountPoint != NULL) {
                result = [[[NSString stringWithUTF8String:mountPoint]
                    stringByAppendingPathComponent:[NSString stringWithUTF8String:docID]]
                    stringByAppendingPathComponent:[path lastPathComponent]];
            }
            g_variant_unref(mount);
        }
        g_variant_unref(added);
    }
    g_clear_error(&error);
    g_object_unref(fds);
    g_object_unref(bus);
    if (result != nil && ![[NSFileManager defaultManager] fileExistsAtPath:result]) {
        return nil;
    }
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

// Opens a URI with the desktop's default app for it, as GIO finds it
// (GNUstep's NSWorkspace has no handler for mailto: and says so in an
// alert).
static BOOL OMDLaunchDefaultForURL(NSURL *url)
{
    const char *uri = [[url absoluteString] UTF8String];
    if (uri == NULL) {
        return NO;
    }
    GError *error = NULL;
    gboolean launched = g_app_info_launch_default_for_uri(uri, NULL, &error);
    g_clear_error(&error);
    return launched ? YES : NO;
}

@implementation OMDSharePresenterLinux

- (void)emailShareItemWithMailtoDraft:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    BOOL opened = OMDLaunchDefaultForURL(OMDMailtoURLWithSubject([item title]));
    NSString *message = opened
        ? [NSString stringWithFormat:@"Attach \u201C%@\u201D to the email.", [item fileName]]
        : [NSString stringWithFormat:@"No email app opened. \u201C%@\u201D is ready to attach.", [item fileName]];
    [OMDShareNotice showNoticeWithMessage:message shareItem:item presenter:self forWindow:window];
}

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

    NSString *flatpakID = nil;
    NSString *appID = OMDDefaultMailAppID(&flatpakID);
    NSString *xdgEmail = OMDExecutablePathNamed(@"xdg-email");
    NSString *attachPath = path;
    if (flatpakID != nil) {
        // A Flatpak mail app only sees files the document portal gives it.
        attachPath = OMDDocumentPortalPathForFile(path, flatpakID);
    }
    if (xdgEmail != nil && attachPath != nil && OMDMailAppTakesAttachments(appID)) {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath:xdgEmail];
        [task setArguments:[NSArray arrayWithObjects:@"--subject", subject, @"--attach", attachPath, nil]];
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
    OMDLaunchDefaultForURL(OMDMailtoURLWithSubject(subject));
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
