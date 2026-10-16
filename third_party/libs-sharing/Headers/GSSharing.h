/** <title>GSSharing</title>

   <abstract>Apple's NSSharingService and NSSharingServicePicker API for
   GNUstep: share items (files, text, images) through services the user
   picks in a share sheet.</abstract>

   Copyright (C) 2026 Daniel Boyd

   Author: Daniel Boyd <danieljboyd@icloud.com>
   Date: 2026

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

/* libs-gui declares NSSharingService, NSSharingServicePicker and
   NSSharingServicePickerToolbarItem with no methods (their classes exist
   and do nothing). This library gives them Apple's API: the methods are
   declared here as categories and installed into libs-gui's classes when
   the library loads (GSSharingInstall()). Upstream, the declarations go to
   AppKit/NSSharingService.h and the code into libs-gui; the GSSharing...
   names below stay GNUstep extensions. */

#ifndef _GNUstep_H_GSSharing
#define _GNUstep_H_GSSharing

#import <AppKit/AppKit.h>
#import <AppKit/NSSharingService.h>
#import <AppKit/NSSharingServicePickerToolbarItem.h>

#ifndef GSSHARING_EXPORT
#  define GSSHARING_EXPORT extern
#endif

/* libs-gui defines GS_HAS_SHARING_SERVICES once it implements the API
   itself; this code then declares and installs nothing. */
#ifndef GS_HAS_SHARING_SERVICES

#if defined(__has_feature)
#  if __has_feature(blocks)
#    define GSSHARING_HAS_BLOCKS 1
#  endif
#endif

typedef NSString *NSSharingServiceName;

/* Apple's service names. On GNUstep a name is offered when a service
   (built in, or from a plug-in) answers to it. */
GSSHARING_EXPORT NSSharingServiceName const NSSharingServiceNameComposeEmail;
GSSHARING_EXPORT NSSharingServiceName const NSSharingServiceNameComposeMessage;
GSSHARING_EXPORT NSSharingServiceName const NSSharingServiceNameSendViaAirDrop;
GSSHARING_EXPORT NSSharingServiceName const NSSharingServiceNameAddToSafariReadingList;
GSSHARING_EXPORT NSSharingServiceName const NSSharingServiceNameCloudSharing;

/* GNUstep's built-in services. */
GSSHARING_EXPORT NSSharingServiceName const GSSharingServiceNameCopy;
GSSHARING_EXPORT NSSharingServiceName const GSSharingServiceNameSaveCopy;
GSSHARING_EXPORT NSSharingServiceName const GSSharingServiceNameShowInFolder;
GSSHARING_EXPORT NSSharingServiceName const GSSharingServiceNameOpenWith;

@interface NSSharingService (GSSharing)

/** The service of this name that can be used now, or nil. */
+ (NSSharingService *) sharingServiceNamed: (NSSharingServiceName)serviceName;

/** The services that can share all of items, in the order the share sheet
    lists them: built-in services first, then plug-ins'. */
+ (NSArray *) sharingServicesForItems: (NSArray *)items;

#ifdef GSSHARING_HAS_BLOCKS
/** A service of the app's own: block is run with the items to share. */
- (id) initWithTitle: (NSString *)title
               image: (NSImage *)image
      alternateImage: (NSImage *)alternateImage
             handler: (void (^)(void))block;
#endif

/** A service that sends -performWithItems: to target with action (the
    items as its argument). The equivalent of the block initializer for
    code that can't use blocks (GCC). */
- (id) initWithTitle: (NSString *)title
               image: (NSImage *)image
      alternateImage: (NSImage *)alternateImage
              target: (id)target
              action: (SEL)action;

- (NSString *) title;
- (NSImage *) image;
- (NSImage *) alternateImage;
- (NSString *) menuItemTitle;
- (void) setMenuItemTitle: (NSString *)title;
- (id) delegate;
- (void) setDelegate: (id)delegate;
- (NSString *) subject;
- (void) setSubject: (NSString *)subject;
- (NSArray *) recipients;
- (void) setRecipients: (NSArray *)recipients;

/** Whether the service can share items (NSURL file URLs, NSString,
    NSAttributedString, NSImage). */
- (BOOL) canPerformWithItems: (NSArray *)items;
/** Shares items, telling the delegate before and after. */
- (void) performWithItems: (NSArray *)items;

@end

/** What a service's delegate may implement (Apple's
    NSSharingServiceDelegate; libs-gui's protocol of that name has no
    methods, so they are declared here informally). */
@interface NSObject (GSSharingServiceDelegate)
- (void) sharingService: (NSSharingService *)sharingService
         willShareItems: (NSArray *)items;
- (void) sharingService: (NSSharingService *)sharingService
    didFailToShareItems: (NSArray *)items
                  error: (NSError *)error;
- (void) sharingService: (NSSharingService *)sharingService
          didShareItems: (NSArray *)items;
@end

@interface NSSharingServicePicker (GSSharing)

- (id) initWithItems: (NSArray *)items;
- (id) delegate;
- (void) setDelegate: (id)delegate;
/** Shows the share sheet next to rect in view. On GNUstep it is a small
    panel by the view's window; edge is a preference. */
- (void) showRelativeToRect: (NSRect)rect
                     ofView: (NSView *)view
              preferredEdge: (NSRectEdge)preferredEdge;
/** Closes the share sheet if it is showing. */
- (void) close;

/* GNUstep extensions. */
/** The items, which may change while the sheet shows (an app's format
    switcher re-exporting the document): the sheet updates its preview and
    its services. */
- (NSArray *) items;
- (void) setItems: (NSArray *)items;
/** A view the app adds to the sheet under its preview (a format switcher,
    say), or nil. */
- (NSView *) accessoryView;
- (void) setAccessoryView: (NSView *)view;
/** Whether the services can be chosen (YES by default): NO while the app
    prepares new items, say a document still exporting. */
- (BOOL) servicesEnabled;
- (void) setServicesEnabled: (BOOL)flag;

@end

/** What a picker's delegate may implement (Apple's
    NSSharingServicePickerDelegate, declared informally as above). */
@interface NSObject (GSSharingServicePickerDelegate)
/** The services to list: proposedServices with the app's own added or
    some removed. */
- (NSArray *) sharingServicePicker: (NSSharingServicePicker *)picker
           sharingServicesForItems: (NSArray *)items
           proposedSharingServices: (NSArray *)proposedServices;
/** The delegate for the chosen service (nil leaves its own). */
- (id) sharingServicePicker: (NSSharingServicePicker *)picker
  delegateForSharingService: (NSSharingService *)sharingService;
/** service is nil when the sheet was closed without a choice. */
- (void) sharingServicePicker: (NSSharingServicePicker *)picker
      didChooseSharingService: (NSSharingService *)service;
@end

/** A provider of services: the principal class of a plug-in bundle in a
    Library/SharingServices directory (extension .sharingservice), or a
    class the app registers. */
@protocol GSSharingServiceProvider
/** The services this provider offers for items, or an empty array. */
+ (NSArray *) sharingServicesForItems: (NSArray *)items;
@end

/** Installs the API into libs-gui's classes, once; the library calls it
    when it loads, so apps needn't. Returns NO where libs-gui implements
    the API itself. */
GSSHARING_EXPORT BOOL GSSharingInstall(void);

/** Adds a provider (a class conforming to GSSharingServiceProvider) after
    the built-in ones and the plug-ins. */
GSSHARING_EXPORT void GSSharingRegisterProvider(Class provider);

#endif /* GS_HAS_SHARING_SERVICES */

#endif /* _GNUstep_H_GSSharing */
