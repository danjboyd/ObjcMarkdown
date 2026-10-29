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
/* shlobj.h (SHOpenWithDialog) brings in COM headers that declare with the
   interface macro, which GNUstep's headers undefine: it would turn every
   @interface into @struct. Defined only around the include. */
#  if !defined(interface)
#    define interface struct
#    define GSSHARING_UNDEF_INTERFACE
#  endif
#  include <shlobj.h>
#  if defined(GSSHARING_UNDEF_INTERFACE)
#    undef interface
#    undef GSSHARING_UNDEF_INTERFACE
#  endif
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
+ (void) openWith: (NSArray *)items service: (NSSharingService *)service;
#if defined(_WIN32)
+ (void) sendMAPIMail: (NSDictionary *)job;
+ (void) emailDraftWithNotice: (NSDictionary *)job;
#endif
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

/* Where a copy was last saved (#15). */
static NSString * const GSSharingSaveCopyDirectoryKey = @"GSSharingSaveCopyDirectory";

static BOOL
GSSharingIsDirectory(NSString *path)
{
  BOOL isDirectory = NO;

  return path != nil
    && [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDirectory]
    && isDirectory;
}

/* The folder Save a Copy opens in: the app's (the picker's saveDirectory),
   else where a copy was last saved, else the file's own unless it is a
   temporary one (an export), else home. */
static NSString *
GSSharingSaveCopyDirectory(NSSharingService *service, NSURL *file)
{
  NSString *suggested = GSSharingStateForService(service, YES)->saveDirectory;
  NSString *last = [[NSUserDefaults standardUserDefaults]
                     stringForKey: GSSharingSaveCopyDirectoryKey];
  NSString *own = [[[file path] stringByDeletingLastPathComponent]
                    stringByStandardizingPath];
  NSString *temporary = [NSTemporaryDirectory() stringByStandardizingPath];

  if (GSSharingIsDirectory(suggested))
    {
      return suggested;
    }
  if (GSSharingIsDirectory(last))
    {
      return last;
    }
  if (GSSharingIsDirectory(own) && [own hasPrefix: temporary] == NO
    && [own isEqual: @"/tmp"] == NO && [own hasPrefix: @"/tmp/"] == NO)
    {
      return own;
    }
  return NSHomeDirectory();
}

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

BOOL
GSSharingIsImageFile(id item)
{
  NSString *extension;

  if (GSSharingKindOfItem(item) != GSSharingItemFile)
    {
      return NO;
    }
  /* Pictures, not documents: NSImage reads PDF and EPS too, which should
     go as the files they are. */
  extension = [[[item path] pathExtension] lowercaseString];
  return [[NSArray arrayWithObjects: @"png", @"jpg", @"jpeg", @"gif", @"bmp",
                   @"tif", @"tiff", @"webp", nil] containsObject: extension];
}

/* An image as PNG, from its bitmap when it has one. */
static NSData *
GSSharingPNGOfImage(NSImage *image)
{
  NSEnumerator *e = [[image representations] objectEnumerator];
  NSImageRep *rep;
  NSBitmapImageRep *bitmap = nil;

  while ((rep = [e nextObject]) != nil)
    {
      if ([rep isKindOfClass: [NSBitmapImageRep class]])
        {
          bitmap = (NSBitmapImageRep *)rep;
          break;
        }
    }
  if (bitmap == nil)
    {
      NSData *tiff = [image TIFFRepresentation];

      bitmap = (tiff != nil) ? [NSBitmapImageRep imageRepWithData: tiff] : nil;
    }
  return [bitmap representationUsingType: NSPNGFileType
                              properties: [NSDictionary dictionary]];
}

/* The image types put on the pasteboard for an image (PNG first: chat
   apps and browsers paste that), with their data, in two arrays. A PNG
   file is put as it is; any other image is converted. */
static void
GSSharingImageTypes(NSImage *image, NSData *png, NSMutableArray *types,
                    NSMutableArray *data)
{
  NSData *tiff = [image TIFFRepresentation];

  if (png == nil)
    {
      png = GSSharingPNGOfImage(image);
    }
  if (png != nil)
    {
      [types addObject: NSPasteboardTypePNG];
      [data addObject: png];
    }
  if (tiff != nil)
    {
      [types addObject: NSTIFFPboardType];
      [data addObject: tiff];
    }
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
#if defined(_WIN32)
  if (pasteboard == [NSPasteboard generalPasteboard]
    && GSSharingWin32WriteText(plain, rtf))
    {
      return;
    }
#endif
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

/* Files on the pasteboard. One image file goes as its image too, first,
   so pasting it into a chat or a document gives the picture, and into a
   file manager the file. */
static void
GSSharingWriteFiles(NSPasteboard *pasteboard, NSArray *files)
{
  NSMutableArray *paths = [NSMutableArray array];
  NSMutableString *uriList = [NSMutableString string];
  NSMutableArray *types = [NSMutableArray array];
  NSMutableArray *imageData = [NSMutableArray array];
  NSEnumerator *e = [files objectEnumerator];
  NSURL *file;
  NSUInteger i;

  while ((file = [e nextObject]) != nil)
    {
      [paths addObject: [file path]];
      [uriList appendFormat: @"%@\r\n", [file absoluteString]];
    }
#if defined(_WIN32)
  /* CF_HDROP: Explorer, Outlook and Teams paste it as the file; one
     picture file goes as its PNG too, for chats and documents. */
  if (pasteboard == [NSPasteboard generalPasteboard])
    {
      NSData *png = nil;

      if ([files count] == 1 && GSSharingIsImageFile([files objectAtIndex: 0]))
        {
          NSString *path = [[files objectAtIndex: 0] path];

          if ([[[path pathExtension] lowercaseString] isEqualToString: @"png"])
            {
              png = [NSData dataWithContentsOfFile: path];
            }
          else
            {
              NSImage *image = AUTORELEASE([[NSImage alloc]
                initWithContentsOfFile: path]);
              NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:
                [image TIFFRepresentation]];

              png = [rep representationUsingType: NSPNGFileType
                                      properties: [NSDictionary dictionary]];
            }
        }
      if (GSSharingWin32WriteFiles(paths, png))
        {
          return;
        }
    }
#endif
  if ([files count] == 1 && GSSharingIsImageFile([files objectAtIndex: 0]))
    {
      NSString *path = [[files objectAtIndex: 0] path];
      NSImage *image = AUTORELEASE([[NSImage alloc] initWithContentsOfFile: path]);
      NSData *png = nil;

      if ([[[path pathExtension] lowercaseString] isEqualToString: @"png"])
        {
          png = [NSData dataWithContentsOfFile: path];
        }
      if (image != nil)
        {
          GSSharingImageTypes(image, png, types, imageData);
        }
    }
  [types addObjectsFromArray: [NSArray arrayWithObjects: NSFilenamesPboardType,
                                       NSURLPboardType, NSStringPboardType, nil]];
  [pasteboard declareTypes: types owner: nil];
  for (i = 0; i < [imageData count]; i++)
    {
      [pasteboard setData: [imageData objectAtIndex: i]
                  forType: [types objectAtIndex: i]];
    }
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

/* The portal's Response to a request: -1 until it comes. */
static void
GSSharingPortalResponse(GDBusConnection *bus, const gchar *sender,
                        const gchar *path, const gchar *interface,
                        const gchar *signal, GVariant *parameters,
                        gpointer context)
{
  guint32 response = 2;

  g_variant_get(parameters, "(u@a{sv})", &response, NULL);
  *(gint *)context = (gint)response;
}

/* Calls a desktop portal method that takes a file as a descriptor.
   parameters builds the call's arguments around the descriptor's handle
   (no blocks: GCC). NO when the portal isn't there, or answers at once
   that it can't (it accepts the request first, and then a session
   without its desktop backend answers "failed" and shows nothing): the
   caller falls back. Otherwise the portal's window is up, and its answer
   comes when the user is done with it, so it isn't waited for. */
typedef GVariant *(*GSSharingPortalParameters)(gint32 handle, void *context);

static BOOL
GSSharingCallPortalWithFile(const char *interface, const char *method,
                            NSString *path, GSSharingPortalParameters parameters,
                            void *context)
{
  GError *error = NULL;
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
  gint response = -1;
  guint subscription;
  GUnixFDList *fds;
  GVariant *reply = NULL;
  gint32 handle = -1;
  int fd;
  BOOL called = NO;

  if (bus == NULL)
    {
      g_clear_error(&error);
      return NO;
    }
  /* Subscribed first, so an answer sent at once isn't missed. */
  subscription = g_dbus_connection_signal_subscribe(bus,
    "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
    "Response", NULL, NULL, G_DBUS_SIGNAL_FLAGS_NONE,
    GSSharingPortalResponse, &response, NULL);
  fds = g_unix_fd_list_new();
  fd = open([path fileSystemRepresentation], O_RDONLY | O_CLOEXEC);
  if (fd >= 0)
    {
      handle = g_unix_fd_list_append(fds, fd, &error);
      close(fd);
    }
  if (handle >= 0)
    {
      reply = g_dbus_connection_call_with_unix_fd_list_sync(bus,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        interface, method, parameters(handle, context), G_VARIANT_TYPE("(o)"),
        G_DBUS_CALL_FLAGS_NONE, -1, fds, NULL, NULL, &error);
    }
  if (reply != NULL)
    {
      /* The signal comes through GLib's main context, which GNUstep's run
         loop doesn't turn: turn it here for half a second. */
      gint64 until = g_get_monotonic_time() + 500000;

      while (response < 0 && g_get_monotonic_time() < until)
        {
          if (g_main_context_iteration(NULL, FALSE) == FALSE)
            {
              g_usleep(10000);
            }
        }
      /* 0 done, 1 cancelled: either way the user saw the portal's window. */
      called = (response < 0 || response == 0 || response == 1);
      g_variant_unref(reply);
    }
  g_dbus_connection_signal_unsubscribe(bus, subscription);
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

/* OpenFile with "ask": the desktop's own chooser of the apps that open
   the file (GNOME's "Open With" dialog), the default one selected. */
static GVariant *
GSSharingOpenFileParameters(gint32 handle, void *context)
{
  GVariantBuilder options;

  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "ask", g_variant_new_boolean(TRUE));
  return g_variant_new("(sha{sv})", "", handle, &options);
}

/* Opens the desktop's own chooser of the apps for the file, through the
   portal; NO when it can't, so the caller falls back. */
static BOOL
GSSharingOpenFileWithPortal(NSString *path)
{
  return GSSharingCallPortalWithFile("org.freedesktop.portal.OpenURI",
                                     "OpenFile", path,
                                     GSSharingOpenFileParameters, NULL);
}

/* Without the portal: a menu of the apps that say they open the file's
   type, the default first; choosing one opens the file in it. */
@interface GSSharingOpenWithMenu : NSObject
{
  NSString *path;
}
+ (BOOL) showMenuForPath: (NSString *)aPath;
- (void) openInApp: (NSMenuItem *)sender;
@end

@implementation GSSharingOpenWithMenu

+ (BOOL) showMenuForPath: (NSString *)aPath
{
  char *type = g_content_type_guess([aPath fileSystemRepresentation], NULL, 0, NULL);
  GList *apps = (type != NULL) ? g_app_info_get_all_for_type(type) : NULL;
  GAppInfo *preferred = (type != NULL)
    ? g_app_info_get_default_for_type(type, FALSE) : NULL;
  const char *preferredID = (preferred != NULL) ? g_app_info_get_id(preferred) : NULL;
  GSSharingOpenWithMenu *target;
  NSMenu *menu;
  /* At the pointer, in the app's window: the sheet that was clicked has
     closed by now. */
  NSWindow *window = [NSApp mainWindow];
  NSEvent *event = nil;
  GList *l;
  BOOL shown = NO;

  g_free(type);
  target = AUTORELEASE([GSSharingOpenWithMenu new]);
  ASSIGNCOPY(target->path, aPath);
  menu = AUTORELEASE([[NSMenu alloc] initWithTitle: @"Open With"]);
  for (l = apps; l != NULL; l = l->next)
    {
      GAppInfo *app = l->data;
      const char *identifier = g_app_info_get_id(app);
      NSMenuItem *item;

      if (identifier == NULL || g_app_info_should_show(app) == FALSE)
        {
          continue;
        }
      item = [[NSMenuItem alloc]
               initWithTitle: [NSString stringWithUTF8String:
                                g_app_info_get_display_name(app)]
                      action: @selector(openInApp:)
               keyEquivalent: @""];
      [item setTarget: target];
      [item setRepresentedObject: [NSString stringWithUTF8String: identifier]];
      if (preferredID != NULL && strcmp(identifier, preferredID) == 0)
        {
          [menu insertItem: item atIndex: 0];
        }
      else
        {
          [menu addItem: item];
        }
      RELEASE(item);
    }
  g_list_free_full(apps, g_object_unref);
  if (preferred != NULL)
    {
      g_object_unref(preferred);
    }
  if (window != nil)
    {
      event = [NSEvent mouseEventWithType: NSRightMouseDown
                                 location: [window mouseLocationOutsideOfEventStream]
                            modifierFlags: 0
                                timestamp: 0
                             windowNumber: [window windowNumber]
                                  context: nil
                              eventNumber: 0
                               clickCount: 1
                                 pressure: 1.0];
    }
  if ([menu numberOfItems] > 0 && event != nil)
    {
      /* The menu keeps its items, which keep the target while it shows. */
      [NSMenu popUpContextMenu: menu withEvent: event forView: [window contentView]];
      shown = YES;
    }
  return shown;
}

- (void) dealloc
{
  RELEASE(path);
  [super dealloc];
}

- (void) openInApp: (NSMenuItem *)sender
{
  GDesktopAppInfo *app = g_desktop_app_info_new(
    [[sender representedObject] UTF8String]);
  GFile *file = g_file_new_for_path([path fileSystemRepresentation]);
  GList *files = g_list_append(NULL, file);
  GError *error = NULL;

  if (app == NULL || g_app_info_launch(G_APP_INFO(app), files, NULL, &error) == FALSE)
    {
      [GSSharingNotice showMessage: @"That app didn't open the file."
                            detail: @"Drag it into an app's window instead."
                              file: [NSURL fileURLWithPath: path]];
    }
  g_clear_error(&error);
  g_list_free(files);
  g_object_unref(file);
  if (app != NULL)
    {
      g_object_unref(app);
    }
}

@end

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

#if defined(GSSHARING_HAVE_GIO)
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
#endif

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

/* The mailto: draft, and the notice with the file to attach. */
static void
GSSharingEmailDraftWithNotice(NSURL *draft, NSURL *file)
{
  BOOL opened = GSSharingOpenURL(draft);

  [GSSharingNotice showMessage: (opened
      ? [NSString stringWithFormat: @"Attach “%@” to the email.",
                  [[file path] lastPathComponent]]
      : @"No email app opened. The file is ready to attach.")
#if defined(_WIN32)
                        /* No drags out of a GNUstep window on Windows yet. */
                        detail: @"Copy it, then paste it into the message."
#else
                        detail: @"Drag it into the message, or copy it and paste it there."
#endif
                          file: file];
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
#if defined(_WIN32)
  /* Simple MAPI attaches the file in the default client (Outlook, classic,
     and Thunderbird take it). It blocks until the client is done with the
     draft, so it runs off the main thread; a failure comes back to
     +emailDraftWithNotice:. Without a MAPI client (none, the new Outlook,
     webmail) the mailto: draft and the notice, below. */
  if (GSSharingWin32MailClientTakesMAPI())
    {
      NSMutableArray *paths = [NSMutableArray array];
      NSEnumerator *e = [files objectEnumerator];
      NSURL *file;
      NSDictionary *job;

      while ((file = [e nextObject]) != nil)
        {
          [paths addObject: [file path]];
        }
      job = [NSDictionary dictionaryWithObjectsAndKeys:
        subject, @"subject", paths, @"paths",
        ([service recipients] != nil ? [service recipients] : [NSArray array]),
        @"recipients", draft, @"draft", [files objectAtIndex: 0], @"file", nil];
      [NSThread detachNewThreadSelector: @selector(sendMAPIMail:)
                               toTarget: self
                             withObject: job];
      return;
    }
#endif
  GSSharingEmailDraftWithNotice(draft, [files objectAtIndex: 0]);
}

#if defined(_WIN32)
+ (void) sendMAPIMail: (NSDictionary *)job
{
  CREATE_AUTORELEASE_POOL(pool);

  if (GSSharingWin32SendMail([job objectForKey: @"subject"],
                             [job objectForKey: @"paths"],
                             [job objectForKey: @"recipients"], NULL) == NO)
    {
      [self performSelectorOnMainThread: @selector(emailDraftWithNotice:)
                             withObject: job
                          waitUntilDone: NO];
    }
  RELEASE(pool);
}

+ (void) emailDraftWithNotice: (NSDictionary *)job
{
  GSSharingEmailDraftWithNotice([job objectForKey: @"draft"],
                                [job objectForKey: @"file"]);
}
#endif

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
      NSMutableArray *types = [NSMutableArray array];
      NSMutableArray *data = [NSMutableArray array];
      NSUInteger i;

      GSSharingImageTypes(first, nil, types, data);
      [pasteboard declareTypes: types owner: nil];
      for (i = 0; i < [types count]; i++)
        {
          [pasteboard setData: [data objectAtIndex: i]
                      forType: [types objectAtIndex: i]];
        }
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

  /* It reports a dismissed panel as cancelled, and a copy that failed. */
  GSSharingServiceWillFinishLater(service);
  if (file == nil)
    {
      GSSharingServiceFinish(service, items,
        [NSError errorWithDomain: NSCocoaErrorDomain
                            code: NSFileNoSuchFileError userInfo: nil]);
      return;
    }
  panel = [NSSavePanel savePanel];
  [panel setTitle: @"Save a Copy"];
  [panel setNameFieldStringValue: [[file path] lastPathComponent]];
  /* The copy keeps the file's type: a name typed without the extension
     gets it, as with the app's own Export (#24). */
  if ([[[file path] pathExtension] length] > 0)
    {
      [panel setAllowedFileTypes:
        [NSArray arrayWithObject: [[file path] pathExtension]]];
    }
  [panel setCanCreateDirectories: YES];
  [panel setDirectory: GSSharingSaveCopyDirectory(service, file)];
  if ([panel runModal] != NSFileHandlingPanelOKButton)
    {
      GSSharingServiceFinish(service, items, GSSharingCancelledError());
      return;
    }
  destination = [[panel URL] path];
  if ([destination length] == 0)
    {
      GSSharingServiceFinish(service, items, GSSharingCancelledError());
      return;
    }
  /* The panel has asked about replacing it. */
  [manager removeItemAtPath: destination error: NULL];
  if ([manager copyItemAtPath: [file path] toPath: destination error: &error] == NO)
    {
      NSRunAlertPanel(@"Couldn't save a copy",
                      (error != nil ? [error localizedDescription] : destination),
                      @"OK", nil, nil);
      GSSharingServiceFinish(service, items,
        (error != nil ? error : [NSError errorWithDomain: NSCocoaErrorDomain
                                                    code: NSFileWriteUnknownError
                                                userInfo: nil]));
      return;
    }
  [[NSUserDefaults standardUserDefaults]
    setObject: [destination stringByDeletingLastPathComponent]
       forKey: GSSharingSaveCopyDirectoryKey];
  GSSharingServiceFinish(service, items, nil);
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
  if (GSSharingWin32ShowInFolder(path))
    {
      return;
    }
  {
    NSTask *task = AUTORELEASE([NSTask new]);

    /* Explorer exits with 1 even when it worked. Its /select takes only
       C:\... (#23). */
    [task setLaunchPath: @"explorer.exe"];
    [task setArguments: [NSArray arrayWithObject:
      [NSString stringWithFormat: @"/select,%@",
        [path stringByReplacingOccurrencesOfString: @"/" withString: @"\\"]]]];
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

+ (void) openWith: (NSArray *)items service: (NSSharingService *)service
{
  NSString *path = [[GSSharingFilesOfItems(items) lastObject] path];

  if (path == nil)
    {
      return;
    }
#if defined(_WIN32)
  {
    /* SHOpenWithDialog rejects C:/... (E_INVALIDARG), the form GNUstep's
       paths have, and shows nothing (#23). */
    NSString *windowsPath = [path stringByReplacingOccurrencesOfString: @"/"
                                                            withString: @"\\"];
    NSUInteger length = [windowsPath length];
    unichar *wide;
    OPENASINFO info;
    NSWindow *window = [NSApp mainWindow];
    HWND owner = NULL;
    HRESULT result;

    /* It reports a dismissed chooser as cancelled (the sheet comes back,
       #16), and a chooser Windows wouldn't show. */
    GSSharingServiceWillFinishLater(service);
    wide = malloc((length + 1) * sizeof(unichar));
    if (wide == NULL)
      {
        GSSharingServiceFinish(service, items,
          [NSError errorWithDomain: NSCocoaErrorDomain
                              code: NSFileReadUnknownError userInfo: nil]);
        return;
      }
    [windowsPath getCharacters: wide range: NSMakeRange(0, length)];
    wide[length] = 0;
    memset(&info, 0, sizeof(info));
    info.pcszFile = (const wchar_t *)wide;
    info.oaifInFlags = OAIF_ALLOW_REGISTRATION | OAIF_EXEC;
    /* The document window owns the chooser (#23). */
    if (window == nil)
      {
        window = [NSApp keyWindow];
      }
    if (window != nil)
      {
        owner = (HWND)(intptr_t)[window windowNumber];
      }
    result = SHOpenWithDialog(owner, &info);
    free(wide);
    if (SUCCEEDED(result))
      {
        GSSharingServiceFinish(service, items, nil);
      }
    else if (result == HRESULT_FROM_WIN32(ERROR_CANCELLED))
      {
        GSSharingServiceFinish(service, items, GSSharingCancelledError());
      }
    else
      {
        NSLog(@"Open With: SHOpenWithDialog failed for %@ (HRESULT 0x%08lx)",
              windowsPath, (unsigned long)result);
        [GSSharingNotice showMessage: @"Windows didn't show its list of apps."
                              detail: @"Show the file in its folder and open it from there."
                                file: [NSURL fileURLWithPath: path]];
        GSSharingServiceFinish(service, items,
          [NSError errorWithDomain: NSCocoaErrorDomain
                              code: NSFeatureUnsupportedError userInfo: nil]);
      }
  }
#elif defined(GSSHARING_HAVE_GIO)
  /* The desktop's own chooser through the portal (sandboxed or not); its
     dialog may take a moment, and reports nothing back. */
  if (GSSharingOpenFileWithPortal(path))
    {
      return;
    }
  if ([GSSharingOpenWithMenu showMenuForPath: path])
    {
      return;
    }
  [GSSharingNotice showMessage: @"No app here says it opens this file."
                        detail: @"Drag it into an app's window, or show it in its folder."
                          file: [NSURL fileURLWithPath: path]];
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
#if defined(_WIN32) || defined(GSSHARING_HAVE_GIO)
    GSSharingMakeBuiltinService(GSSharingServiceNameOpenWith, @"Open With…",
                                @"GSSharing-open", files,
                                @selector(openWith:service:)),
#endif
    nil];

  return [all arrayByAddingObjectsFromArray: GSSharingRcloneServicesForItems(items)];
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
