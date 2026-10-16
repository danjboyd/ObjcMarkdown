/* GSSharingBuiltins.m: the services every GNUstep app has: Email, Copy,
   Save a Copy, Show in Folder; and the providers (plug-ins and the app's
   own).

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPrivate.h"
#import "GSSharingNotice.h"

#ifndef GS_HAS_SHARING_SERVICES

#if defined(_WIN32)
#  include <windows.h>
#  include <shellapi.h>
#elif defined(GSSHARING_HAVE_GIO)
#  include <fcntl.h>
#  include <unistd.h>
#  include <gio/gio.h>
#  include <gio/gunixfdlist.h>
#  include <gio/gdesktopappinfo.h>
/* The document portal takes O_PATH descriptors, which glibc declares only
   with _GNU_SOURCE (Linux's value; elsewhere there is no document portal). */
#  if defined(__linux__) && !defined(O_PATH)
#    define O_PATH 010000000
#  endif
#  if !defined(O_PATH)
#    define O_PATH O_RDONLY
#  endif
#endif

/* The selectors the built-in services perform: each takes the items and
   the service. */
@interface GSSharingBuiltins : NSObject
+ (void) email: (NSArray *)items service: (NSSharingService *)service;
+ (void) copy: (NSArray *)items service: (NSSharingService *)service;
+ (void) saveCopy: (NSArray *)items service: (NSSharingService *)service;
+ (void) showInFolder: (NSArray *)items service: (NSSharingService *)service;
@end


/* Images. */

NSImage *
GSSharingImageNamed(NSString *name)
{
  NSString *symbolic = [name stringByAppendingString: @"-symbolic"];
  NSImage *image = [NSImage imageNamed: symbolic];

  if (image == nil)
    {
      NSBundle *bundle = [NSBundle bundleForClass: [GSSharingBuiltins class]];
      NSString *path = [bundle pathForResource: symbolic ofType: @"png"];

      if (path == nil)
        {
          path = [[NSBundle mainBundle] pathForResource: symbolic ofType: @"png"];
        }
      if (path != nil)
        {
          image = AUTORELEASE([[NSImage alloc] initWithContentsOfFile: path]);
          /* The name themes look for to tint it. */
          [image setName: symbolic];
        }
    }
  return image;
}


/* Small helpers. */

static NSArray *
GSSharingFilesOfItems(NSArray *items)
{
  NSMutableArray *files = [NSMutableArray array];
  NSEnumerator *e = [items objectEnumerator];
  id item;

  while ((item = [e nextObject]) != nil)
    {
      if (GSSharingKindOfItem(item) == GSSharingItemFile)
        {
          [files addObject: item];
        }
    }
  return files;
}

static NSString *
GSSharingSubject(NSArray *items, NSSharingService *service)
{
  NSString *subject = [service subject];
  id first;

  if ([subject length] > 0)
    {
      return subject;
    }
  first = [items count] > 0 ? [items objectAtIndex: 0] : nil;
  if (GSSharingKindOfItem(first) == GSSharingItemFile)
    {
      return [[[first path] lastPathComponent] stringByDeletingPathExtension];
    }
  return @"";
}

static NSURL *
GSSharingMailtoURL(NSString *subject, NSArray *recipients)
{
  NSMutableCharacterSet *allowed
    = AUTORELEASE([[NSCharacterSet alphanumericCharacterSet] mutableCopy]);
  NSString *to;
  NSString *encoded;

  [allowed addCharactersInString: @"-._~"];
  encoded = [subject stringByAddingPercentEncodingWithAllowedCharacters: allowed];
  to = [[recipients componentsJoinedByString: @","]
         stringByAddingPercentEncodingWithAllowedCharacters: allowed];
  return [NSURL URLWithString:
    [NSString stringWithFormat: @"mailto:%@?subject=%@",
              (to != nil ? to : @""), (encoded != nil ? encoded : @"")]];
}

/* Puts text (rich or plain) on the pasteboard: RTF and plain text, and
   HTML when an attributed string carries it as GSSharingHTMLAttribute's
   document (apps that render HTML themselves set it). */
static void
GSSharingWriteText(NSPasteboard *pasteboard, id text)
{
  NSMutableArray *types = [NSMutableArray array];
  NSData *rtf = nil;
  NSString *plain;

  if ([text isKindOfClass: [NSAttributedString class]])
    {
      rtf = [text RTFFromRange: NSMakeRange(0, [text length])
            documentAttributes: [NSDictionary dictionary]];
      plain = [[text string] stringByReplacingOccurrencesOfString: @"￼"
                                                      withString: @""];
    }
  else
    {
      plain = text;
    }
  if (rtf != nil)
    {
      [types addObject: NSRTFPboardType];
    }
  [types addObject: NSStringPboardType];
  [pasteboard declareTypes: types owner: nil];
  if (rtf != nil)
    {
      [pasteboard setData: rtf forType: NSRTFPboardType];
    }
  [pasteboard setString: plain forType: NSStringPboardType];
}

static void
GSSharingWriteFiles(NSPasteboard *pasteboard, NSArray *files)
{
  NSMutableArray *paths = [NSMutableArray array];
  NSMutableString *uriList = [NSMutableString string];
  NSEnumerator *e = [files objectEnumerator];
  NSURL *file;

  while ((file = [e nextObject]) != nil)
    {
      [paths addObject: [file path]];
      [uriList appendFormat: @"%@\r\n", [file absoluteString]];
    }
  [pasteboard declareTypes: [NSArray arrayWithObjects: NSFilenamesPboardType,
                                     NSURLPboardType, NSStringPboardType, nil]
                     owner: nil];
  [pasteboard setPropertyList: paths forType: NSFilenamesPboardType];
  /* As text/uri-list bytes: GNUstep keeps a string set for a type other
     than NSStringPboardType serialized, and its X11 server would hand that
     over header and all. */
  [pasteboard setData: [uriList dataUsingEncoding: NSUTF8StringEncoding]
              forType: NSURLPboardType];
  [pasteboard setString: [paths componentsJoinedByString: @"\n"]
                forType: NSStringPboardType];
}


/* The desktop: opening a URL, the file manager, the mail app. */

#if defined(GSSHARING_HAVE_GIO)

static BOOL
GSSharingInFlatpak(void)
{
  return [[NSFileManager defaultManager] fileExistsAtPath: @"/.flatpak-info"];
}

static BOOL
GSSharingLaunchDefault(NSURL *url)
{
  GError *error = NULL;
  gboolean launched = g_app_info_launch_default_for_uri(
    [[url absoluteString] UTF8String], NULL, &error);

  g_clear_error(&error);
  return launched ? YES : NO;
}

/* Calls a desktop portal method that takes a file as a descriptor; NO if
   the portal isn't there. parameters builds the call's arguments around
   the descriptor's handle (no blocks: GCC). */
typedef GVariant *(*GSSharingPortalParameters)(gint32 handle, void *context);

static BOOL
GSSharingCallPortalWithFile(const char *interface, const char *method,
                            NSString *path, GSSharingPortalParameters parameters,
                            void *context)
{
  GError *error = NULL;
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
  GUnixFDList *fds;
  gint32 handle;
  int fd;
  BOOL called = NO;

  if (bus == NULL)
    {
      g_clear_error(&error);
      return NO;
    }
  fd = open([path fileSystemRepresentation], O_RDONLY | O_CLOEXEC);
  if (fd < 0)
    {
      g_object_unref(bus);
      return NO;
    }
  fds = g_unix_fd_list_new();
  handle = g_unix_fd_list_append(fds, fd, &error);
  close(fd);
  if (handle >= 0)
    {
      GVariant *reply = g_dbus_connection_call_with_unix_fd_list_sync(bus,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        interface, method, parameters(handle, context),
        NULL, G_DBUS_CALL_FLAGS_NONE, -1, fds, NULL, NULL, &error);

      if (reply != NULL)
        {
          called = YES;
          g_variant_unref(reply);
        }
    }
  g_clear_error(&error);
  g_object_unref(fds);
  g_object_unref(bus);
  return called;
}

static GVariant *
GSSharingOpenDirectoryParameters(gint32 handle, void *context)
{
  GVariantBuilder options;

  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  return g_variant_new("(sha{sv})", "", handle, &options);
}

static GVariant *
GSSharingComposeEmailParameters(gint32 handle, void *context)
{
  GVariantBuilder options;
  GVariantBuilder handles;

  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "subject",
                        g_variant_new_string((const char *)context));
  g_variant_builder_init(&handles, G_VARIANT_TYPE("ah"));
  g_variant_builder_add(&handles, "h", handle);
  g_variant_builder_add(&options, "{sv}", "attachment_fds",
                        g_variant_builder_end(&handles));
  return g_variant_new("(sa{sv})", "", &options);
}

static BOOL
GSSharingShowItemsInFileManager(NSArray *files)
{
  GError *error = NULL;
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
  GVariantBuilder uris;
  NSEnumerator *e = [files objectEnumerator];
  NSURL *file;
  GVariant *reply;

  if (bus == NULL)
    {
      g_clear_error(&error);
      return NO;
    }
  g_variant_builder_init(&uris, G_VARIANT_TYPE("as"));
  while ((file = [e nextObject]) != nil)
    {
      g_variant_builder_add(&uris, "s", [[file absoluteString] UTF8String]);
    }
  reply = g_dbus_connection_call_sync(bus,
    "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
    "org.freedesktop.FileManager1", "ShowItems",
    g_variant_new("(ass)", &uris, ""),
    NULL, G_DBUS_CALL_FLAGS_NONE, 10000, NULL, &error);
  g_clear_error(&error);
  g_object_unref(bus);
  if (reply != NULL)
    {
      g_variant_unref(reply);
      return YES;
    }
  return NO;
}

/* The default mail app's desktop file ID, and its Flatpak app ID when it
   is a Flatpak. */
static NSString *
GSSharingDefaultMailApp(NSString **flatpakID)
{
  GAppInfo *app = g_app_info_get_default_for_uri_scheme("mailto");
  const char *identifier;
  NSString *result = nil;

  *flatpakID = nil;
  if (app == NULL)
    {
      return nil;
    }
  identifier = g_app_info_get_id(app);
  if (identifier != NULL)
    {
      result = [NSString stringWithUTF8String: identifier];
    }
  else if (g_app_info_get_executable(app) != NULL)
    {
      result = [[NSString stringWithUTF8String:
                  g_app_info_get_executable(app)] lastPathComponent];
    }
  if (G_IS_DESKTOP_APP_INFO(app))
    {
      char *flatpak = g_desktop_app_info_get_string(G_DESKTOP_APP_INFO(app),
                                                    "X-Flatpak");

      if (flatpak != NULL && flatpak[0] != '\0')
        {
          *flatpakID = [NSString stringWithUTF8String: flatpak];
        }
      g_free(flatpak);
    }
  g_object_unref(app);
  return result;
}

/* A path a sandboxed app can read: the file exported through the
   document portal, readable by that app only; nil without the portal. */
static NSString *
GSSharingDocumentPortalPath(NSString *path, NSString *appID)
{
  GError *error = NULL;
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
  NSString *result = nil;
  GUnixFDList *fds;
  GVariant *added = NULL;
  gint32 handle = -1;
  int fd;

  if (bus == NULL)
    {
      g_clear_error(&error);
      return nil;
    }
  fds = g_unix_fd_list_new();
  fd = open([path fileSystemRepresentation], O_PATH | O_CLOEXEC);
  if (fd >= 0)
    {
      handle = g_unix_fd_list_append(fds, fd, &error);
      close(fd);
    }
  if (handle >= 0)
    {
      added = g_dbus_connection_call_with_unix_fd_list_sync(bus,
        "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
        "org.freedesktop.portal.Documents", "Add",
        g_variant_new("(hbb)", handle, TRUE, FALSE),
        G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NONE, -1, fds, NULL, NULL,
        &error);
    }
  if (added != NULL)
    {
      const char *docID = NULL;
      const char *permissions[] = { "read", NULL };
      GVariant *granted;
      GVariant *mount = NULL;

      g_variant_get(added, "(&s)", &docID);
      granted = g_dbus_connection_call_sync(bus,
        "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
        "org.freedesktop.portal.Documents", "GrantPermissions",
        g_variant_new("(ss^as)", docID, [appID UTF8String], permissions),
        NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
      if (granted != NULL)
        {
          g_variant_unref(granted);
          mount = g_dbus_connection_call_sync(bus,
            "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
            "org.freedesktop.portal.Documents", "GetMountPoint",
            NULL, G_VARIANT_TYPE("(ay)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL,
            &error);
        }
      if (mount != NULL)
        {
          const char *mountPoint = NULL;

          g_variant_get(mount, "(^&ay)", &mountPoint);
          if (mountPoint != NULL)
            {
              result = [[[NSString stringWithUTF8String: mountPoint]
                stringByAppendingPathComponent: [NSString stringWithUTF8String: docID]]
                stringByAppendingPathComponent: [path lastPathComponent]];
            }
          g_variant_unref(mount);
        }
      g_variant_unref(added);
    }
  g_clear_error(&error);
  g_object_unref(fds);
  g_object_unref(bus);
  if (result != nil && [[NSFileManager defaultManager] fileExistsAtPath: result] == NO)
    {
      return nil;
    }
  return result;
}

#endif /* GSSHARING_HAVE_GIO */

/* Whether a mail app (its desktop file ID or executable) takes an
   attachment from xdg-email: the desktop clients xdg-email knows. */
BOOL
GSSharingMailAppTakesAttachments(NSString *appID)
{
  NSString *lower = [appID lowercaseString];
  NSArray *clients = [NSArray arrayWithObjects: @"evolution", @"thunderbird",
                              @"betterbird", @"kmail", @"claws-mail",
                              @"sylpheed", nil];
  NSEnumerator *e = [clients objectEnumerator];
  NSString *client;

  if ([lower length] == 0)
    {
      return NO;
    }
  while ((client = [e nextObject]) != nil)
    {
      if ([lower rangeOfString: client].location != NSNotFound)
        {
          return YES;
        }
    }
  return NO;
}

static NSString *
GSSharingExecutableNamed(NSString *name)
{
  NSArray *paths = [[[[NSProcessInfo processInfo] environment]
    objectForKey: @"PATH"] componentsSeparatedByString: @":"];
  NSEnumerator *e = [paths objectEnumerator];
  NSString *directory;

  while ((directory = [e nextObject]) != nil)
    {
      NSString *candidate = [directory stringByAppendingPathComponent: name];

      if ([[NSFileManager defaultManager] isExecutableFileAtPath: candidate])
        {
          return candidate;
        }
    }
  return nil;
}

static BOOL
GSSharingOpenURL(NSURL *url)
{
#if defined(_WIN32)
  NSString *s = [url absoluteString];
  NSUInteger length = [s length];
  unichar *wide = malloc((length + 1) * sizeof(unichar));
  HINSTANCE result;

  if (wide == NULL)
    {
      return NO;
    }
  [s getCharacters: wide range: NSMakeRange(0, length)];
  wide[length] = 0;
  result = ShellExecuteW(NULL, L"open", (const wchar_t *)wide, NULL, NULL,
                         SW_SHOWNORMAL);
  free(wide);
  return (INT_PTR)result > 32;
#elif defined(GSSHARING_HAVE_GIO)
  return GSSharingLaunchDefault(url);
#else
  return [[NSWorkspace sharedWorkspace] openURL: url];
#endif
}


@implementation GSSharingBuiltins

/* Email: files attached where the mail app takes them; text as the body,
   put on the clipboard to paste (a mailto: draft carries plain text only). */
+ (void) email: (NSArray *)items service: (NSSharingService *)service
{
  NSArray *files = GSSharingFilesOfItems(items);
  NSString *subject = GSSharingSubject(items, service);
  NSURL *draft = GSSharingMailtoURL(subject, [service recipients]);
  BOOL opened;

  if ([files count] == 0)
    {
      id text = [items count] > 0 ? [items objectAtIndex: 0] : nil;

      GSSharingWriteText([NSPasteboard generalPasteboard], text);
      opened = GSSharingOpenURL(draft);
      [GSSharingNotice showMessage: (opened
          ? @"The text is on the clipboard: paste it into the message."
          : @"No email app opened. The text is on the clipboard, ready to paste.")
                            detail: @"Paste with Ctrl+V; its formatting comes with it."
                              file: nil];
      return;
    }

#if defined(GSSHARING_HAVE_GIO)
  {
    NSString *path = [[files objectAtIndex: 0] path];

    if (GSSharingInFlatpak())
      {
        if (GSSharingCallPortalWithFile("org.freedesktop.portal.Email",
                                        "ComposeEmail", path,
                                        GSSharingComposeEmailParameters,
                                        (void *)[subject UTF8String]))
          {
            return;
          }
      }
    else
      {
        NSString *flatpakID = nil;
        NSString *appID = GSSharingDefaultMailApp(&flatpakID);
        NSString *xdgEmail = GSSharingExecutableNamed(@"xdg-email");
        NSString *attach = path;

        if (flatpakID != nil)
          {
            /* A Flatpak mail app sees only what the document portal gives it. */
            attach = GSSharingDocumentPortalPath(path, flatpakID);
          }
        if (xdgEmail != nil && attach != nil && GSSharingMailAppTakesAttachments(appID))
          {
            NSTask *task = AUTORELEASE([NSTask new]);

            [task setLaunchPath: xdgEmail];
            [task setArguments: [NSArray arrayWithObjects: @"--subject", subject,
                                         @"--attach", attach, nil]];
            NS_DURING
              {
                [task launch];
                NS_VALUERETURN((void)0, void);
              }
            NS_HANDLER
              {
              }
            NS_ENDHANDLER
          }
      }
  }
#endif
  /* The draft, and the file to drag into it. */
  opened = GSSharingOpenURL(draft);
  [GSSharingNotice showMessage: (opened
      ? [NSString stringWithFormat: @"Attach “%@” to the email.",
                  [[[files objectAtIndex: 0] path] lastPathComponent]]
      : @"No email app opened. The file is ready to attach.")
                        detail: @"Drag it into the message, or copy it and paste it there."
                          file: [files objectAtIndex: 0]];
}

+ (void) copy: (NSArray *)items service: (NSSharingService *)service
{
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
  NSArray *files = GSSharingFilesOfItems(items);
  id first = [items count] > 0 ? [items objectAtIndex: 0] : nil;
  unsigned kind = GSSharingKindOfItem(first);

  if ([files count] > 0)
    {
      GSSharingWriteFiles(pasteboard, files);
    }
  else if (kind == GSSharingItemImage)
    {
      [pasteboard declareTypes: [NSArray arrayWithObject: NSTIFFPboardType]
                         owner: nil];
      [pasteboard setData: [first TIFFRepresentation] forType: NSTIFFPboardType];
    }
  else if (kind == GSSharingItemURL)
    {
      [pasteboard declareTypes: [NSArray arrayWithObject: NSStringPboardType]
                         owner: nil];
      [pasteboard setString: [first absoluteString] forType: NSStringPboardType];
    }
  else if (first != nil)
    {
      GSSharingWriteText(pasteboard, first);
    }
}

+ (void) saveCopy: (NSArray *)items service: (NSSharingService *)service
{
  NSURL *file = [GSSharingFilesOfItems(items) lastObject];
  NSSavePanel *panel;
  NSString *destination;
  NSFileManager *manager = [NSFileManager defaultManager];
  NSError *error = nil;

  if (file == nil)
    {
      return;
    }
  panel = [NSSavePanel savePanel];
  [panel setTitle: @"Save a Copy"];
  [panel setNameFieldStringValue: [[file path] lastPathComponent]];
  [panel setCanCreateDirectories: YES];
  [panel setDirectory: NSHomeDirectory()];
  if ([panel runModal] != NSFileHandlingPanelOKButton)
    {
      return;
    }
  destination = [[panel URL] path];
  if ([destination length] == 0)
    {
      return;
    }
  /* The panel has asked about replacing it. */
  [manager removeItemAtPath: destination error: NULL];
  if ([manager copyItemAtPath: [file path] toPath: destination error: &error] == NO)
    {
      NSRunAlertPanel(@"Couldn't save a copy",
                      (error != nil ? [error localizedDescription] : destination),
                      @"OK", nil, nil);
    }
}

+ (void) showInFolder: (NSArray *)items service: (NSSharingService *)service
{
  NSArray *files = GSSharingFilesOfItems(items);
  NSString *path = [[files lastObject] path];

  if (path == nil)
    {
      return;
    }
#if defined(_WIN32)
  {
    NSTask *task = AUTORELEASE([NSTask new]);

    /* Explorer exits with 1 even when it worked. */
    [task setLaunchPath: @"explorer.exe"];
    [task setArguments: [NSArray arrayWithObject:
      [NSString stringWithFormat: @"/select,%@", path]]];
    NS_DURING
      {
        [task launch];
      }
    NS_HANDLER
      {
      }
    NS_ENDHANDLER
  }
#elif defined(GSSHARING_HAVE_GIO)
  if (GSSharingInFlatpak()
    && GSSharingCallPortalWithFile("org.freedesktop.portal.OpenURI",
                                   "OpenDirectory", path,
                                   GSSharingOpenDirectoryParameters, NULL))
    {
      return;
    }
  if (GSSharingShowItemsInFileManager(files))
    {
      return;
    }
  GSSharingLaunchDefault([NSURL fileURLWithPath:
                           [path stringByDeletingLastPathComponent]]);
#else
  [[NSWorkspace sharedWorkspace] selectFile: path inFileViewerRootedAtPath: @""];
#endif
}

@end


NSSharingService *
GSSharingMakeBuiltinService(NSString *name, NSString *title,
                            NSString *imageName, unsigned accepts, SEL action)
{
  NSSharingService *service
    = AUTORELEASE([[NSSharingService alloc]
                    initWithTitle: title
                            image: nil
                   alternateImage: nil
                           target: [GSSharingBuiltins class]
                           action: action]);
  GSSharingServiceState *state = GSSharingStateForService(service, YES);

  ASSIGNCOPY(state->name, name);
  ASSIGNCOPY(state->imageName, imageName);
  state->accepts = accepts;
  return service;
}

NSArray *
GSSharingBuiltinServicesForItems(NSArray *items)
{
  unsigned files = GSSharingItemFile;
  unsigned text = GSSharingItemText | GSSharingItemRichText;
  NSArray *all = [NSArray arrayWithObjects:
    GSSharingMakeBuiltinService(NSSharingServiceNameComposeEmail, @"Email",
                                @"GSSharing-email", files | text,
                                @selector(email:service:)),
    GSSharingMakeBuiltinService(GSSharingServiceNameCopy, @"Copy",
                                @"GSSharing-copy",
                                files | text | GSSharingItemURL | GSSharingItemImage,
                                @selector(copy:service:)),
    GSSharingMakeBuiltinService(GSSharingServiceNameSaveCopy, @"Save a Copy",
                                @"GSSharing-save", files,
                                @selector(saveCopy:service:)),
    GSSharingMakeBuiltinService(GSSharingServiceNameShowInFolder, @"Show in Folder",
                                @"GSSharing-folder", files,
                                @selector(showInFolder:service:)),
    nil];

  return all;
}


/* Providers: plug-ins in Library/SharingServices, then the app's own. */

static NSMutableArray *registeredProviders = nil;
static NSArray *pluginProviders = nil;

static NSArray *
GSSharingLoadPlugins(void)
{
  NSMutableArray *providers = [NSMutableArray array];
  NSArray *libraries = NSSearchPathForDirectoriesInDomains(
    NSLibraryDirectory, NSAllDomainsMask, YES);
  NSEnumerator *e = [libraries objectEnumerator];
  NSString *library;

  while ((library = [e nextObject]) != nil)
    {
      NSString *directory = [library stringByAppendingPathComponent: @"SharingServices"];
      NSArray *names = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath: directory error: NULL];
      NSEnumerator *n = [[names sortedArrayUsingSelector: @selector(compare:)]
                          objectEnumerator];
      NSString *name;

      while ((name = [n nextObject]) != nil)
        {
          NSBundle *bundle;
          Class principal;

          if ([[name pathExtension] isEqualToString: @"sharingservice"] == NO)
            {
              continue;
            }
          bundle = [NSBundle bundleWithPath:
                     [directory stringByAppendingPathComponent: name]];
          principal = [bundle principalClass];
          if (principal != Nil
            && [principal respondsToSelector: @selector(sharingServicesForItems:)])
            {
              [providers addObject: principal];
            }
        }
    }
  return providers;
}

NSArray *
GSSharingProviders(void)
{
  NSMutableArray *all = [NSMutableArray array];

  if (pluginProviders == nil)
    {
      pluginProviders = RETAIN(GSSharingLoadPlugins());
    }
  [all addObjectsFromArray: pluginProviders];
  if (registeredProviders != nil)
    {
      [all addObjectsFromArray: registeredProviders];
    }
  return all;
}

void
GSSharingRegisterProvider(Class provider)
{
  if (provider == Nil)
    {
      return;
    }
  if (registeredProviders == nil)
    {
      registeredProviders = [NSMutableArray new];
    }
  if ([registeredProviders containsObject: provider] == NO)
    {
      [registeredProviders addObject: provider];
    }
}

#endif /* GS_HAS_SHARING_SERVICES */
