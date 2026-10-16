/* GSSharingToolbarItem.m: NSSharingServicePickerToolbarItem, a toolbar
   button that asks its delegate for the items and shows the share sheet.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPrivate.h"
#include <objc/runtime.h>

#ifndef GS_HAS_SHARING_SERVICES

/* libs-gui's class has -delegate and -setDelegate: that keep nothing, so
   these replace them; the delegate is kept here by item. */
static NSMapTable *toolbarDelegates = nil;

@interface GSSharingToolbarItemDonor : NSSharingServicePickerToolbarItem
@end

@implementation GSSharingToolbarItemDonor

- (id<NSSharingServicePickerToolbarItemDelegate>) delegate
{
  return toolbarDelegates != nil ? NSMapGet(toolbarDelegates, self) : nil;
}

- (void) setDelegate: (id<NSSharingServicePickerToolbarItemDelegate>)delegate
{
  if (toolbarDelegates == nil)
    {
      toolbarDelegates = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks,
                                          NSNonOwnedPointerMapValueCallBacks, 4);
    }
  if (delegate == nil)
    {
      NSMapRemove(toolbarDelegates, self);
    }
  else
    {
      NSMapInsert(toolbarDelegates, self, delegate);
    }
  /* The button: the share image and label unless the app set its own. */
  if ([self image] == nil)
    {
      [self setImage: GSSharingImageNamed(@"GSSharing-share")];
    }
  if ([[self label] length] == 0)
    {
      [self setLabel: @"Share"];
      [self setPaletteLabel: @"Share"];
    }
  [self setTarget: self];
  [self setAction: @selector(_gsSharingShowPicker:)];
}

- (void) _gsSharingShowPicker: (id)sender
{
  id delegate = [self delegate];
  NSArray *items = nil;
  NSSharingServicePicker *picker;
  NSView *view = [self view];
  NSRect rect;

  if ([delegate respondsToSelector:
         @selector(itemsForSharingServicePickerToolbarItem:)])
    {
      items = [delegate itemsForSharingServicePickerToolbarItem: self];
    }
  if ([items count] == 0)
    {
      NSBeep();
      return;
    }
  picker = AUTORELEASE([[NSSharingServicePicker alloc] initWithItems: items]);
  if ([delegate respondsToSelector:
         @selector(sharingServicePicker:sharingServicesForItems:proposedSharingServices:)])
    {
      [picker setDelegate: delegate];
    }
  if (view == nil)
    {
      view = [[NSApp keyWindow] contentView];
      rect = NSMakeRect(NSMidX([view bounds]), NSMaxY([view bounds]), 1, 1);
    }
  else
    {
      rect = [view bounds];
    }
  /* The picker is kept while it shows: its panel calls back into it. */
  RETAIN(picker);
  [picker showRelativeToRect: rect ofView: view preferredEdge: NSMinYEdge];
  AUTORELEASE(picker);
}

- (void) dealloc
{
  if (toolbarDelegates != nil)
    {
      NSMapRemove(toolbarDelegates, self);
    }
  [super dealloc];
}

@end

/* Replaces or adds each of donor's methods in target. */
static void
GSSharingCopyMethods(Class donor, Class target)
{
  unsigned int count = 0;
  unsigned int i;
  Method *methods = class_copyMethodList(donor, &count);

  for (i = 0; i < count; i++)
    {
      SEL selector = method_getName(methods[i]);

      if (sel_isEqual(selector, @selector(dealloc)))
        {
          continue;
        }
      class_replaceMethod(target, selector,
                          method_getImplementation(methods[i]),
                          method_getTypeEncoding(methods[i]));
    }
  free(methods);
}

@interface GSSharingToolbarLoader : NSObject
@end

@implementation GSSharingToolbarLoader
/* Only the runtime here: a message to NSToolbarItem or a subclass would
   run its +initialize, which needs the backend, not up when +load runs. */
+ (void) load
{
  Class item = objc_getClass("NSSharingServicePickerToolbarItem");
  Class donor = objc_getClass("GSSharingToolbarItemDonor");

  if (item != Nil && donor != Nil
    && class_getInstanceMethod(item, @selector(_gsSharingShowPicker:)) == NULL)
    {
      GSSharingCopyMethods(donor, item);
    }
}
@end

#endif /* GS_HAS_SHARING_SERVICES */
