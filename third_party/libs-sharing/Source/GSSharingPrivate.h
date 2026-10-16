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
}
@end

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

/* The built-in services for items, in the sheet's order. */
NSArray *GSSharingBuiltinServicesForItems(NSArray *items);

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
