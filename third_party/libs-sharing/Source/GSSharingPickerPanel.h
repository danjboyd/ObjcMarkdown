/* GSSharingPickerPanel.h: the share sheet NSSharingServicePicker shows.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPrivate.h"

/* A small panel by the view's window: what is shared (its icon, which
   drags the file, its name and size), the app's accessory view, and the
   services as buttons with their images. Standard controls only, so the
   theme draws it. Choosing a service closes the panel and performs it;
   Escape or the close button closes it without a choice. */
@interface GSSharingPickerPanel : NSObject
{
  NSSharingServicePicker *_picker;   /* not retained: it owns us */
  NSPanel *_panel;
  NSImageView *_icon;
  NSTextField *_nameLabel;
  NSTextField *_detailLabel;
  NSView *_servicesView;
  NSArray *_services;
  BOOL _closed;
}

- (id) initWithPicker: (NSSharingServicePicker *)picker;
- (void) showRelativeToRect: (NSRect)rect
                     ofView: (NSView *)view
              preferredEdge: (NSRectEdge)edge;
/* The items changed: the preview and the services follow. */
- (void) pickerItemsDidChange;
/* Closes the panel, telling the delegate no service was chosen. */
- (void) closeWithoutChoice;
/* The services the panel lists for the picker's items. */
- (NSArray *) services;

@end

/* The file's icon in the panel or a notice: dragging it drags the file. */
@interface GSSharingFileDragView : NSImageView
{
  NSURL *_fileURL;
}
- (void) setFileURL: (NSURL *)fileURL;
@end
