/* GSSharingService.m: NSSharingService and NSSharingServicePicker, and
   installing them into libs-gui's classes.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPrivate.h"
#import "GSSharingPickerPanel.h"
#include <objc/runtime.h>
#include <stdlib.h>

#ifndef GS_HAS_SHARING_SERVICES

NSSharingServiceName const NSSharingServiceNameComposeEmail
  = @"com.apple.share.Mail.compose";
NSSharingServiceName const NSSharingServiceNameComposeMessage
  = @"com.apple.messages.ShareExtension";
NSSharingServiceName const NSSharingServiceNameSendViaAirDrop
  = @"com.apple.share.AirDrop.send";
NSSharingServiceName const NSSharingServiceNameAddToSafariReadingList
  = @"com.apple.share.System.add-to-safari-reading-list";
NSSharingServiceName const NSSharingServiceNameCloudSharing
  = @"com.apple.share.CloudSharing";
NSSharingServiceName const GSSharingServiceNameCopy
  = @"org.gnustep.sharing.copy";
NSSharingServiceName const GSSharingServiceNameSaveCopy
  = @"org.gnustep.sharing.save-copy";
NSSharingServiceName const GSSharingServiceNameShowInFolder
  = @"org.gnustep.sharing.show-in-folder";
NSSharingServiceName const GSSharingServiceNameOpenWith
  = @"org.gnustep.sharing.open-with";

static BOOL installed = NO;
static NSMapTable *serviceStates = nil;
static NSMapTable *pickerStates = nil;


@implementation GSSharingServiceState
- (void) dealloc
{
  RELEASE(name);
  RELEASE(title);
  RELEASE(image);
  RELEASE(imageName);
  RELEASE(alternateImage);
  RELEASE(menuItemTitle);
  RELEASE(subject);
  RELEASE(recipients);
  RELEASE(handler);
  RELEASE(target);
  [super dealloc];
}
@end

@implementation GSSharingPickerState
- (void) dealloc
{
  RELEASE(items);
  RELEASE(accessoryView);
  RELEASE(panel);
  [super dealloc];
}
@end

GSSharingServiceState *
GSSharingStateForService(NSSharingService *service, BOOL create)
{
  GSSharingServiceState *state = NSMapGet(serviceStates, service);

  if (state == nil && create)
    {
      state = [GSSharingServiceState new];
      NSMapInsert(serviceStates, service, state);
      RELEASE(state);
    }
  return state;
}

GSSharingPickerState *
GSSharingStateForPicker(NSSharingServicePicker *picker, BOOL create)
{
  GSSharingPickerState *state = NSMapGet(pickerStates, picker);

  if (state == nil && create)
    {
      state = [GSSharingPickerState new];
      NSMapInsert(pickerStates, picker, state);
      RELEASE(state);
    }
  return state;
}

unsigned
GSSharingKindOfItem(id item)
{
  if ([item isKindOfClass: [NSURL class]])
    {
      return [item isFileURL] ? GSSharingItemFile : GSSharingItemURL;
    }
  if ([item isKindOfClass: [NSAttributedString class]])
    {
      return GSSharingItemRichText;
    }
  if ([item isKindOfClass: [NSString class]])
    {
      return GSSharingItemText;
    }
  if ([item isKindOfClass: [NSImage class]])
    {
      return GSSharingItemImage;
    }
  return 0;
}

NSString *
GSSharingDisplayNameOfItem(id item)
{
  unsigned kind = GSSharingKindOfItem(item);

  if (kind == GSSharingItemFile)
    {
      return [[item path] lastPathComponent];
    }
  if (kind == GSSharingItemURL)
    {
      return [item absoluteString];
    }
  if (kind == GSSharingItemImage)
    {
      return [item name] != nil ? [item name] : @"Image";
    }
  if (kind == GSSharingItemText || kind == GSSharingItemRichText)
    {
      /* Its first line, shortened. */
      NSString *string = (kind == GSSharingItemRichText) ? [item string] : item;
      NSString *line = [[string componentsSeparatedByCharactersInSet:
                          [NSCharacterSet newlineCharacterSet]] objectAtIndex: 0];

      line = [line stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
      if ([line length] > 60)
        {
          line = [[line substringToIndex: 59] stringByAppendingString: @"\u2026"];
        }
      return [line length] > 0 ? line : @"Text";
    }
  return @"";
}


/* NSSharingService's methods, written on a subclass that only holds them
   and copied into libs-gui's class by GSSharingInstall(). */
@interface GSSharingServiceDonor : NSSharingService
@end

@implementation GSSharingServiceDonor

+ (NSArray *) sharingServicesForItems: (NSArray *)items
{
  NSMutableArray *services = [NSMutableArray array];
  NSEnumerator *e;
  Class provider;

  [services addObjectsFromArray: GSSharingBuiltinServicesForItems(items)];
  e = [GSSharingProviders() objectEnumerator];
  while ((provider = [e nextObject]) != nil)
    {
      NSArray *more = [provider sharingServicesForItems: items];

      if (more != nil)
        {
          [services addObjectsFromArray: more];
        }
    }
  return services;
}

+ (NSSharingService *) sharingServiceNamed: (NSSharingServiceName)serviceName
{
  NSEnumerator *e;
  NSSharingService *service;

  /* Any item: a service is named whatever it would be given. */
  e = [[self sharingServicesForItems: nil] objectEnumerator];
  while ((service = [e nextObject]) != nil)
    {
      GSSharingServiceState *state = GSSharingStateForService(service, NO);

      if ([state->name isEqualToString: serviceName])
        {
          return service;
        }
    }
  return nil;
}

#ifdef GSSHARING_HAS_BLOCKS
- (id) initWithTitle: (NSString *)title
               image: (NSImage *)image
      alternateImage: (NSImage *)alternateImage
             handler: (void (^)(void))block
{
  if ((self = [self init]) != nil)
    {
      GSSharingServiceState *state = GSSharingStateForService(self, YES);

      ASSIGNCOPY(state->title, title);
      ASSIGN(state->image, image);
      ASSIGN(state->alternateImage, alternateImage);
      state->handler = [block copy];
    }
  return self;
}
#endif

- (id) initWithTitle: (NSString *)title
               image: (NSImage *)image
      alternateImage: (NSImage *)alternateImage
              target: (id)target
              action: (SEL)action
{
  if ((self = [self init]) != nil)
    {
      GSSharingServiceState *state = GSSharingStateForService(self, YES);

      ASSIGNCOPY(state->title, title);
      ASSIGN(state->image, image);
      ASSIGN(state->alternateImage, alternateImage);
      ASSIGN(state->target, target);
      state->action = action;
    }
  return self;
}

- (NSString *) title
{
  return GSSharingStateForService(self, YES)->title;
}

- (NSImage *) image
{
  GSSharingServiceState *state = GSSharingStateForService(self, YES);

  if (state->image == nil && state->imageName != nil)
    {
      ASSIGN(state->image, GSSharingImageNamed(state->imageName));
    }
  return state->image;
}

- (NSImage *) alternateImage
{
  return GSSharingStateForService(self, YES)->alternateImage;
}

- (NSString *) menuItemTitle
{
  GSSharingServiceState *state = GSSharingStateForService(self, YES);

  return state->menuItemTitle != nil ? state->menuItemTitle : state->title;
}

- (void) setMenuItemTitle: (NSString *)title
{
  ASSIGNCOPY(GSSharingStateForService(self, YES)->menuItemTitle, title);
}

- (id) delegate
{
  return GSSharingStateForService(self, YES)->delegate;
}

- (void) setDelegate: (id)delegate
{
  GSSharingStateForService(self, YES)->delegate = delegate;
}

- (NSString *) subject
{
  return GSSharingStateForService(self, YES)->subject;
}

- (void) setSubject: (NSString *)subject
{
  ASSIGNCOPY(GSSharingStateForService(self, YES)->subject, subject);
}

- (NSArray *) recipients
{
  return GSSharingStateForService(self, YES)->recipients;
}

- (void) setRecipients: (NSArray *)recipients
{
  ASSIGNCOPY(GSSharingStateForService(self, YES)->recipients, recipients);
}

- (BOOL) canPerformWithItems: (NSArray *)items
{
  GSSharingServiceState *state = GSSharingStateForService(self, YES);
  NSEnumerator *e;
  id item;

  if (state->accepts == 0)
    {
      return YES;
    }
  if (items == nil)
    {
      return YES;
    }
  if ([items count] == 0)
    {
      return NO;
    }
  e = [items objectEnumerator];
  while ((item = [e nextObject]) != nil)
    {
      if ((GSSharingKindOfItem(item) & state->accepts) == 0)
        {
          return NO;
        }
    }
  return YES;
}

- (void) performWithItems: (NSArray *)items
{
  GSSharingServiceState *state = GSSharingStateForService(self, YES);
  id delegate = state->delegate;

  if ([delegate respondsToSelector:
         @selector(sharingService:willShareItems:)])
    {
      [delegate sharingService: self willShareItems: items];
    }
#ifdef GSSHARING_HAS_BLOCKS
  if (state->handler != nil)
    {
      ((void (^)(void))state->handler)();
    }
  else
#endif
  if (state->target != nil && state->action != NULL)
    {
      [state->target performSelector: state->action
                          withObject: items
                          withObject: self];
    }
  if ([delegate respondsToSelector:
         @selector(sharingService:didShareItems:)])
    {
      [delegate sharingService: self didShareItems: items];
    }
}

@end


/* NSSharingServicePicker's methods. */
@interface GSSharingServicePickerDonor : NSSharingServicePicker
@end

@implementation GSSharingServicePickerDonor

- (id) initWithItems: (NSArray *)items
{
  if ((self = [self init]) != nil)
    {
      GSSharingPickerState *state = GSSharingStateForPicker(self, YES);

      ASSIGNCOPY(state->items, items);
    }
  return self;
}

- (id) delegate
{
  return GSSharingStateForPicker(self, YES)->delegate;
}

- (void) setDelegate: (id)delegate
{
  GSSharingStateForPicker(self, YES)->delegate = delegate;
}

- (NSArray *) items
{
  return GSSharingStateForPicker(self, YES)->items;
}

- (void) setItems: (NSArray *)items
{
  GSSharingPickerState *state = GSSharingStateForPicker(self, YES);

  ASSIGNCOPY(state->items, items);
  [(GSSharingPickerPanel *)state->panel pickerItemsDidChange];
}

- (NSView *) accessoryView
{
  return GSSharingStateForPicker(self, YES)->accessoryView;
}

- (void) setAccessoryView: (NSView *)view
{
  ASSIGN(GSSharingStateForPicker(self, YES)->accessoryView, view);
}

- (BOOL) servicesEnabled
{
  return GSSharingStateForPicker(self, YES)->servicesDisabled == NO;
}

- (void) setServicesEnabled: (BOOL)flag
{
  GSSharingPickerState *state = GSSharingStateForPicker(self, YES);

  state->servicesDisabled = (flag == NO);
  [(GSSharingPickerPanel *)state->panel pickerItemsDidChange];
}

- (void) showRelativeToRect: (NSRect)rect
                     ofView: (NSView *)view
              preferredEdge: (NSRectEdge)preferredEdge
{
  GSSharingPickerState *state = GSSharingStateForPicker(self, YES);

  [(GSSharingPickerPanel *)state->panel closeWithoutChoice];
  ASSIGN(state->panel, AUTORELEASE([[GSSharingPickerPanel alloc]
                                      initWithPicker: self]));
  [(GSSharingPickerPanel *)state->panel showRelativeToRect: rect
                                                    ofView: view
                                             preferredEdge: preferredEdge];
}

- (void) close
{
  GSSharingPickerState *state = GSSharingStateForPicker(self, NO);

  [(GSSharingPickerPanel *)state->panel closeWithoutChoice];
}

@end


/* Adds donor's methods to target where target has none of that name. */
static void
GSSharingAddMissingMethods(Class donor, Class target)
{
  unsigned int count = 0;
  unsigned int i;
  Method *methods = class_copyMethodList(donor, &count);

  for (i = 0; i < count; i++)
    {
      SEL selector = method_getName(methods[i]);

      if (class_getInstanceMethod(target, selector) == NULL
        || class_getInstanceMethod(target, selector)
           == class_getInstanceMethod([NSObject class], selector))
        {
          class_addMethod(target, selector,
                          method_getImplementation(methods[i]),
                          method_getTypeEncoding(methods[i]));
        }
    }
  free(methods);
}

/* A service or picker leaves the state table when it is deallocated. */
static IMP originalServiceDealloc = NULL;
static IMP originalPickerDealloc = NULL;

static void
GSSharingServiceDealloc(id self, SEL _cmd)
{
  if (serviceStates != nil)
    {
      NSMapRemove(serviceStates, self);
    }
  ((void (*)(id, SEL))originalServiceDealloc)(self, _cmd);
}

static void
GSSharingPickerDealloc(id self, SEL _cmd)
{
  if (pickerStates != nil)
    {
      NSMapRemove(pickerStates, self);
    }
  ((void (*)(id, SEL))originalPickerDealloc)(self, _cmd);
}

static void
GSSharingWrapDealloc(Class cls, IMP imp, IMP *original)
{
  Method method = class_getInstanceMethod(cls, @selector(dealloc));

  *original = method_getImplementation(method);
  if (class_addMethod(cls, @selector(dealloc), imp,
                      method_getTypeEncoding(method)) == NO)
    {
      method_setImplementation(method, imp);
    }
}

BOOL
GSSharingInstall(void)
{
  Class service = [NSSharingService class];
  Class picker = [NSSharingServicePicker class];

  if (installed)
    {
      return YES;
    }
  if ([service instancesRespondToSelector: @selector(performWithItems:)])
    {
      /* libs-gui (or another copy of this code) has the API. */
      return NO;
    }
  installed = YES;
  serviceStates = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks,
                                   NSObjectMapValueCallBacks, 16);
  pickerStates = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks,
                                  NSObjectMapValueCallBacks, 4);
  GSSharingAddMissingMethods([GSSharingServiceDonor class], service);
  GSSharingAddMissingMethods(object_getClass([GSSharingServiceDonor class]),
                             object_getClass(service));
  GSSharingAddMissingMethods([GSSharingServicePickerDonor class], picker);
  GSSharingWrapDealloc(service, (IMP)GSSharingServiceDealloc,
                       &originalServiceDealloc);
  GSSharingWrapDealloc(picker, (IMP)GSSharingPickerDealloc,
                       &originalPickerDealloc);
  return YES;
}

/* Installs when the library is loaded (or the app it is compiled into). */
@interface GSSharingLoader : NSObject
@end

@implementation GSSharingLoader
+ (void) load
{
  GSSharingInstall();
}
@end

#endif /* GS_HAS_SHARING_SERVICES */
