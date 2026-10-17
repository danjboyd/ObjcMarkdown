/* GSSharingPrivate.h: what the library's files share.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharing.h"

/* A service's state. libs-gui's NSSharingService has no instance
   variables, so each service's state lives here, kept in a map table by
   the service (upstream: the class's own instance variables). */
@interface GSSharingServiceState : NSObject
{
@public
  NSString *name;
  NSString *title;
  NSImage *image;
  NSString *imageName;  /* a built-in's image, loaded when first asked for */
  NSImage *alternateImage;
  NSString *menuItemTitle;
  id delegate;          /* not retained */
  NSString *subject;
  NSArray *recipients;
  id handler;           /* a copied block, or nil */
  id target;            /* retained */
  SEL action;
  /* Built-in services: which kinds of item they take, as GSSharingItemKind
     bits; 0 for the app's own services, which take anything. */
  unsigned accepts;
  /* -performWithItems: is running the service's work. */
  BOOL performing;
  /* This -performWithItems:'s job reports how it went itself
     (GSSharingServiceWillFinishLater). */
  BOOL performDefers;
  /* Jobs that will report and haven't yet: one per perform that deferred,
     each holding a retain of the service. Jobs that overlap (an upload
     started again before the first ends) report in the order they finish. */
  unsigned pendingJobs;
}
@end

/* A picker's state, kept the same way. */
@interface GSSharingPickerState : NSObject
{
@public
  NSArray *items;
  id delegate;          /* not retained */
  NSView *accessoryView;
  BOOL servicesDisabled;
  id panel;             /* the GSSharingPickerPanel showing, or nil */
  BOOL keptWhileShowing; /* the picker retains itself while its sheet shows */
}
@end

/* The picker's sheet has finished (a service chosen, or none): the picker
   lets go of itself, as AppKit's does once its sheet is gone. */
void GSSharingPickerDidFinish(NSSharingServicePicker *picker);

/* Kinds of item a service can take. */
enum {
  GSSharingItemFile = 1,      /* an NSURL with a file path */
  GSSharingItemURL = 2,       /* any other NSURL */
  GSSharingItemText = 4,      /* NSString */
  GSSharingItemRichText = 8,  /* NSAttributedString */
  GSSharingItemImage = 16     /* NSImage */
};

/* The kind of an item, 0 if it is none of these. */
unsigned GSSharingKindOfItem(id item);

GSSharingServiceState *GSSharingStateForService(NSSharingService *service,
                                                BOOL create);
GSSharingPickerState *GSSharingStateForPicker(NSSharingServicePicker *picker,
                                              BOOL create);

/* A built-in service: name, title, image name, the kinds it takes, and
   the selector of GSSharingBuiltins that performs it. */
NSSharingService *GSSharingMakeBuiltinService(NSString *name,
                                              NSString *title,
                                              NSString *imageName,
                                              unsigned accepts,
                                              SEL action);

/* A service whose work goes on after it returns (an upload), or that can
   fail or be cancelled, says so while it performs, and reports how it went
   with GSSharingServiceFinish: then, or later. The delegate then gets
   -sharingService:didShareItems: (error nil) or
   -sharingService:didFailToShareItems:error:, once per job. A service that
   doesn't is done when it returns, and -performWithItems: reports it
   shared, as before. The service is kept until each job reports.

   The delegate isn't retained (as AppKit's isn't), and a report can now
   come long after the sheet has gone: a delegate that may be deallocated
   first must set the service's delegate to nil in its -dealloc. */
/* Once per job: each call is a job that GSSharingServiceFinish ends. */
void GSSharingServiceWillFinishLater(NSSharingService *service);
void GSSharingServiceFinish(NSSharingService *service, NSArray *items,
                            NSError *error);

/* The error a service reports when the user cancels it (AppKit's:
   NSCocoaErrorDomain, NSUserCancelledError). */
NSError *GSSharingCancelledError(void);

/* The built-in services for items, in the sheet's order. */
NSArray *GSSharingBuiltinServicesForItems(NSArray *items);

/* rclone's services for items: one per remote that makes links, or one
   to unlock an encrypted config; none in a Flatpak or without rclone
   (GSSharingRcloneService.m). */
NSArray *GSSharingRcloneServicesForItems(NSArray *items);

/* The providers registered by the app and found in plug-ins. */
NSArray *GSSharingProviders(void);

/* An image from the library's resources (the main bundle's when the
   library is compiled into an app), named <name>-symbolic so themes tint
   it. */
NSImage *GSSharingImageNamed(NSString *name);

/* YES for a file URL of a picture (PNG, JPEG, GIF, BMP, TIFF, WebP): a
   screenshot or a photo, not a PDF. */
BOOL GSSharingIsImageFile(id item);

/* The file name of an item, for titles and previews. */
NSString *GSSharingDisplayNameOfItem(id item);

#if defined(_WIN32)
/* Windows (GSSharingWin32.m): the clipboard in the formats other Windows
   apps read (GNUstep's win32 pasteboard server passes only text and
   images), Simple MAPI, and Explorer with a file selected. */
BOOL GSSharingWin32WriteText(NSString *plain, NSData *rtf);
BOOL GSSharingWin32WriteFiles(NSArray *paths, NSData *png);
BOOL GSSharingWin32ShowInFolder(NSString *path);
BOOL GSSharingWin32MailClientTakesMAPI(void);
BOOL GSSharingWin32SendMail(NSString *subject, NSArray *paths,
                            NSArray *recipients, void *window);
#endif
