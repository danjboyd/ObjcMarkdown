/* GSSharingPickerPanel.m: the share sheet.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPickerPanel.h"

#ifndef GS_HAS_SHARING_SERVICES

static const CGFloat GSSharingMargin = 16.0;
static const CGFloat GSSharingIconSize = 48.0;
static const CGFloat GSSharingButtonWidth = 112.0;
static const CGFloat GSSharingButtonHeight = 72.0;
static const CGFloat GSSharingButtonGap = 8.0;
static const NSUInteger GSSharingColumns = 4;

@implementation GSSharingFileDragView

- (void) dealloc
{
  RELEASE(_fileURL);
  [super dealloc];
}

- (void) setFileURL: (NSURL *)fileURL
{
  ASSIGNCOPY(_fileURL, fileURL);
}

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

- (void) mouseDown: (NSEvent *)event
{
  if (_fileURL == nil)
    {
      return;
    }
  [self dragFile: [_fileURL path]
        fromRect: [self bounds]
       slideBack: YES
           event: event];
}

- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL)isLocal
{
  return NSDragOperationCopy;
}

@end

/* Escape closes the panel; it can be key though it is a utility panel. */
@interface GSSharingPanelWindow : NSPanel
@end

@implementation GSSharingPanelWindow
- (BOOL) canBecomeKeyWindow
{
  return YES;
}
- (void) cancelOperation: (id)sender
{
  [self performClose: nil];
}
@end

static NSTextField *
GSSharingLabel(NSRect frame, NSFont *font, NSColor *color)
{
  NSTextField *label = AUTORELEASE([[NSTextField alloc] initWithFrame: frame]);

  [label setEditable: NO];
  [label setSelectable: NO];
  [label setBezeled: NO];
  [label setBordered: NO];
  [label setDrawsBackground: NO];
  [label setFont: font];
  [label setTextColor: color];
  [[label cell] setLineBreakMode: NSLineBreakByTruncatingMiddle];
  return label;
}

/* "Q3 Plan.pdf", "63 KB" for a file; a count for several items. */
static NSString *
GSSharingDetailOfItems(NSArray *items)
{
  id item;
  unsigned kind;

  if ([items count] != 1)
    {
      return [NSString stringWithFormat: @"%lu items",
                       (unsigned long)[items count]];
    }
  item = [items objectAtIndex: 0];
  kind = GSSharingKindOfItem(item);
  if (kind == GSSharingItemFile)
    {
      NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath: [item path] error: NULL];
      unsigned long long size = [attributes fileSize];

      if (attributes == nil)
        {
          return @"File";
        }
      if (size < 1024)
        {
          return [NSString stringWithFormat: @"%llu bytes", size];
        }
      if (size < 1024 * 1024)
        {
          return [NSString stringWithFormat: @"%llu KB", (size + 512) / 1024];
        }
      return [NSString stringWithFormat: @"%.1f MB",
                       (double)size / (1024.0 * 1024.0)];
    }
  if (kind == GSSharingItemText || kind == GSSharingItemRichText)
    {
      NSUInteger length = [item length];

      return [NSString stringWithFormat: @"Text, %lu characters",
                       (unsigned long)length];
    }
  if (kind == GSSharingItemImage)
    {
      NSSize size = [item size];

      return [NSString stringWithFormat: @"Image, %.0f x %.0f",
                       size.width, size.height];
    }
  return @"";
}

@implementation GSSharingPickerPanel

- (id) initWithPicker: (NSSharingServicePicker *)picker
{
  if ((self = [super init]) != nil)
    {
      _picker = picker;
    }
  return self;
}

- (void) dealloc
{
  [_panel setDelegate: nil];
  RELEASE(_panel);
  RELEASE(_services);
  [super dealloc];
}

- (NSArray *) services
{
  NSArray *items = [_picker items];
  NSArray *proposed = [NSSharingService sharingServicesForItems: items];
  NSMutableArray *usable = [NSMutableArray array];
  NSEnumerator *e = [proposed objectEnumerator];
  NSSharingService *service;
  id delegate = [_picker delegate];

  while ((service = [e nextObject]) != nil)
    {
      if ([service canPerformWithItems: items])
        {
          [usable addObject: service];
        }
    }
  if ([delegate respondsToSelector:
         @selector(sharingServicePicker:sharingServicesForItems:proposedSharingServices:)])
    {
      NSArray *chosen = [delegate sharingServicePicker: _picker
                               sharingServicesForItems: items
                               proposedSharingServices: usable];

      if (chosen != nil)
        {
          return chosen;
        }
    }
  return usable;
}

/* The preview: the first item's icon (a file's drags it), name, detail. */
- (void) updatePreview
{
  NSArray *items = [_picker items];
  id first = [items count] > 0 ? [items objectAtIndex: 0] : nil;
  unsigned kind = GSSharingKindOfItem(first);
  NSImage *image = nil;

  if (kind == GSSharingItemImage)
    {
      image = first;
    }
  else if (kind == GSSharingItemFile)
    {
      image = GSSharingImageNamed(@"GSSharing-file");
    }
  else
    {
      image = GSSharingImageNamed(@"GSSharing-text");
    }
  [_icon setImage: image];
  [(GSSharingFileDragView *)_icon setFileURL:
    (kind == GSSharingItemFile ? first : nil)];
  [_icon setToolTip: (kind == GSSharingItemFile
                      ? @"Drag the file into an email, a chat or a folder"
                      : nil)];
  [_nameLabel setStringValue: (first != nil
                               ? GSSharingDisplayNameOfItem(first) : @"")];
  [_detailLabel setStringValue: GSSharingDetailOfItems(items)];
}

/* The services, as buttons with their images above their titles, in rows
   of four. Returns the height they take. */
- (CGFloat) layoutServicesInWidth: (CGFloat)width
{
  NSArray *subviews = [[[_servicesView subviews] copy] autorelease];
  NSUInteger count;
  NSUInteger rows;
  NSUInteger i;
  CGFloat height;

  [subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
  ASSIGN(_services, [self services]);
  count = [_services count];
  rows = (count + GSSharingColumns - 1) / GSSharingColumns;
  if (rows == 0)
    {
      rows = 1;
    }
  height = rows * GSSharingButtonHeight + (rows - 1) * GSSharingButtonGap;
  [_servicesView setFrameSize: NSMakeSize(width, height)];
  if (count == 0)
    {
      NSTextField *none = GSSharingLabel(NSMakeRect(0, 0, width, 20),
        [NSFont systemFontOfSize: 0], [NSColor secondaryLabelColor]);

      [none setStringValue: @"Nothing can share this."];
      [_servicesView addSubview: none];
      return height;
    }
  for (i = 0; i < count; i++)
    {
      NSSharingService *service = [_services objectAtIndex: i];
      NSUInteger row = i / GSSharingColumns;
      NSUInteger column = i % GSSharingColumns;
      NSRect frame = NSMakeRect(column * (GSSharingButtonWidth + GSSharingButtonGap),
                                height - (row + 1) * GSSharingButtonHeight
                                - row * GSSharingButtonGap,
                                GSSharingButtonWidth, GSSharingButtonHeight);
      NSButton *button = AUTORELEASE([[NSButton alloc] initWithFrame: frame]);

      [button setButtonType: NSMomentaryPushInButton];
      [button setBezelStyle: NSRegularSquareBezelStyle];
      [button setTitle: [service menuItemTitle]];
      [button setImage: [service image]];
      [button setImagePosition: NSImageAbove];
      [button setTag: i];
      [button setTarget: self];
      [button setAction: @selector(serviceClicked:)];
      [button setToolTip: [service title]];
      [button setEnabled: [_picker servicesEnabled]];
      [_servicesView addSubview: button];
      if (i == 0)
        {
          [button setKeyEquivalent: @"\r"];
        }
    }
  return height;
}

- (void) layoutPanel
{
  NSView *content = [_panel contentView];
  NSView *accessory = [_picker accessoryView];
  CGFloat width = GSSharingColumns * GSSharingButtonWidth
    + (GSSharingColumns - 1) * GSSharingButtonGap;
  CGFloat servicesHeight = [self layoutServicesInWidth: width];
  CGFloat accessoryHeight = accessory != nil ? NSHeight([accessory frame]) + 12.0 : 0.0;
  CGFloat height = GSSharingMargin + GSSharingIconSize + 16.0
    + accessoryHeight + servicesHeight + GSSharingMargin;
  CGFloat y = height - GSSharingMargin - GSSharingIconSize;
  NSRect frame = [_panel frame];
  NSRect contentRect = NSMakeRect(0, 0, width + 2 * GSSharingMargin, height);
  NSRect newFrame = [_panel frameRectForContentRect: contentRect];

  /* Keep the top left corner where it is. */
  newFrame.origin.x = NSMinX(frame);
  newFrame.origin.y = NSMaxY(frame) - NSHeight(newFrame);
  [_panel setFrame: newFrame display: NO];
  [_icon setFrame: NSMakeRect(GSSharingMargin, y,
                              GSSharingIconSize, GSSharingIconSize)];
  [_nameLabel setFrame: NSMakeRect(GSSharingMargin + GSSharingIconSize + 12, y + 24,
                                   width - GSSharingIconSize - 12, 20)];
  [_detailLabel setFrame: NSMakeRect(GSSharingMargin + GSSharingIconSize + 12, y + 4,
                                     width - GSSharingIconSize - 12, 18)];
  y -= 16.0;
  if (accessory != nil)
    {
      NSRect a = [accessory frame];

      y -= NSHeight(a);
      [accessory setFrameOrigin:
        NSMakePoint(GSSharingMargin + floor((width - NSWidth(a)) / 2.0), y)];
      if ([accessory superview] != content)
        {
          [content addSubview: accessory];
        }
      y -= 12.0;
    }
  [_servicesView setFrameOrigin: NSMakePoint(GSSharingMargin, y - servicesHeight)];
  [content setNeedsDisplay: YES];
}

- (void) showRelativeToRect: (NSRect)rect
                     ofView: (NSView *)view
              preferredEdge: (NSRectEdge)edge
{
  NSView *content;
  NSWindow *window = [view window];
  NSRect screenRect;

  _panel = [[GSSharingPanelWindow alloc]
    initWithContentRect: NSMakeRect(0, 0, 400, 200)
              styleMask: (NSTitledWindowMask | NSClosableWindowMask
                          | NSUtilityWindowMask)
                backing: NSBackingStoreBuffered
                  defer: YES];
  [_panel setTitle: @"Share"];
  [_panel setReleasedWhenClosed: NO];
  [_panel setHidesOnDeactivate: NO];
  [_panel setDelegate: (id)self];
  content = [_panel contentView];

  _icon = AUTORELEASE([[GSSharingFileDragView alloc]
    initWithFrame: NSMakeRect(0, 0, GSSharingIconSize, GSSharingIconSize)]);
  [_icon setImageScaling: NSImageScaleProportionallyUpOrDown];
  [_icon setEditable: NO];
  [content addSubview: _icon];
  _nameLabel = GSSharingLabel(NSZeroRect, [NSFont boldSystemFontOfSize: 0],
                              [NSColor labelColor]);
  [content addSubview: _nameLabel];
  _detailLabel = GSSharingLabel(NSZeroRect,
    [NSFont systemFontOfSize: [NSFont smallSystemFontSize]],
    [NSColor secondaryLabelColor]);
  [content addSubview: _detailLabel];
  _servicesView = AUTORELEASE([[NSView alloc] initWithFrame: NSZeroRect]);
  [content addSubview: _servicesView];

  [self updatePreview];
  [self layoutPanel];

  /* Under the rect, its left edge on the rect's, kept on the screen. */
  if (window != nil)
    {
      NSRect inWindow = [view convertRect: rect toView: nil];
      NSRect frame = [_panel frame];
      NSRect visible = [[window screen] visibleFrame];

      screenRect.origin = [window convertBaseToScreen: inWindow.origin];
      screenRect.size = inWindow.size;
      frame.origin.x = NSMinX(screenRect);
      frame.origin.y = NSMinY(screenRect) - NSHeight(frame) - 4.0;
      if (edge == NSMaxYEdge)
        {
          frame.origin.y = NSMaxY(screenRect) + 4.0;
        }
      if (NSIsEmptyRect(visible) == NO)
        {
          frame.origin.x = MAX(NSMinX(visible),
                               MIN(NSMinX(frame), NSMaxX(visible) - NSWidth(frame)));
          frame.origin.y = MAX(NSMinY(visible),
                               MIN(NSMinY(frame), NSMaxY(visible) - NSHeight(frame)));
        }
      [_panel setFrameOrigin: frame.origin];
    }
  else
    {
      [_panel center];
    }
  [_panel makeKeyAndOrderFront: nil];
}

- (void) pickerItemsDidChange
{
  if (_panel == nil || _closed)
    {
      return;
    }
  [self updatePreview];
  [self layoutPanel];
}

- (void) finishWithService: (NSSharingService *)service
{
  id delegate = [_picker delegate];

  if (_closed)
    {
      return;
    }
  _closed = YES;
  RETAIN(self);
  [_panel orderOut: nil];
  if ([delegate respondsToSelector:
         @selector(sharingServicePicker:didChooseSharingService:)])
    {
      [delegate sharingServicePicker: _picker didChooseSharingService: service];
    }
  AUTORELEASE(self);
}

- (void) closeWithoutChoice
{
  [self finishWithService: nil];
}

- (void) windowWillClose: (NSNotification *)notification
{
  [self finishWithService: nil];
}

- (void) serviceClicked: (id)sender
{
  NSInteger index = [sender tag];
  NSSharingService *service;
  NSArray *items = [_picker items];
  id delegate = [_picker delegate];

  if (index < 0 || (NSUInteger)index >= [_services count])
    {
      return;
    }
  service = AUTORELEASE(RETAIN([_services objectAtIndex: index]));
  RETAIN(items);
  if ([delegate respondsToSelector:
         @selector(sharingServicePicker:delegateForSharingService:)])
    {
      id serviceDelegate = [delegate sharingServicePicker: _picker
                                delegateForSharingService: service];

      if (serviceDelegate != nil)
        {
          [service setDelegate: serviceDelegate];
        }
    }
  [self finishWithService: service];
  [service performWithItems: items];
  RELEASE(items);
}

@end

#endif /* GS_HAS_SHARING_SERVICES */
