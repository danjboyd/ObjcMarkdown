/* GSSharingPickerPanel.m: the share sheet.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPickerPanel.h"
#import "GSSharingRclone.h"

#ifndef GS_HAS_SHARING_SERVICES

static const CGFloat GSSharingMargin = 16.0;
static const CGFloat GSSharingIconSize = 48.0;
static const CGFloat GSSharingButtonWidth = 112.0;
/* The widest a tile grows so a title stays on one line (#21). */
static const CGFloat GSSharingButtonMaxWidth = 136.0;
static const CGFloat GSSharingButtonHeight = 72.0;
/* Room kept between a tile's title and the edges the button cell draws in. */
static const CGFloat GSSharingButtonTitlePadding = 2.0;
static const CGFloat GSSharingButtonGap = 8.0;
static const NSUInteger GSSharingColumns = 4;

/* The sheet on screen, if any: an app shows one at a time, as AppKit's
   picker does. Not retained; it clears itself when it closes. */
static GSSharingPickerPanel *GSSharingShowingPanel = nil;

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

/* A symbolic image (the file and text icons) is drawn by a borderless
   button cell, which themes tint as they tint the tiles' images; an image
   view isn't tinted, so in a dark theme the icon was dark on dark. A
   picture (a screenshot, a photo) is drawn as it is. */
- (void) drawRect: (NSRect)rect
{
  NSImage *image = [self image];
  NSString *name = [image name];
  NSButtonCell *cell;

  if (image == nil
    || ([name hasSuffix: @"-symbolic"] == NO && [name hasSuffix: @"Template"] == NO))
    {
      [super drawRect: rect];
      return;
    }
  cell = [[NSButtonCell alloc] initImageCell: image];
  [cell setBordered: NO];
  [cell setImagePosition: NSImageOnly];
  [cell setHighlightsBy: NSNoCellMask];
  [cell drawWithFrame: [self bounds] inView: self];
  RELEASE(cell);
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

static CGFloat
GSSharingWidthOfString(NSString *string, NSFont *font)
{
  NSDictionary *attributes = [NSDictionary dictionaryWithObject: font
                                                         forKey: NSFontAttributeName];

  return [string sizeWithAttributes: attributes].width;
}

/* "..." as one character; sources stay ASCII. */
static NSString *
GSSharingEllipsis(void)
{
  return [NSString stringWithFormat: @"%C", (unichar)0x2026];
}

/* string with its middle replaced by an ellipsis to fit width, cut between
   composed characters. */
static NSString *
GSSharingTruncateMiddle(NSString *string, NSFont *font, CGFloat width)
{
  NSUInteger length = [string length];
  NSUInteger low = 0;
  NSUInteger high = length;
  NSString *best = GSSharingEllipsis();

  if (GSSharingWidthOfString(string, font) <= width)
    {
      return string;
    }
  /* The most characters kept, half from each end, that fit. */
  while (low < high)
    {
      NSUInteger kept = (low + high + 1) / 2;
      NSRange head = [string rangeOfComposedCharacterSequencesForRange:
                               NSMakeRange(0, (kept + 1) / 2)];
      NSRange tail = [string rangeOfComposedCharacterSequencesForRange:
                               NSMakeRange(length - kept / 2, kept / 2)];
      NSString *candidate;

      if (NSMaxRange(head) > tail.location)
        {
          high = kept - 1;
          continue;
        }
      candidate = [NSString stringWithFormat: @"%@%@%@",
                            [string substringWithRange: head],
                            GSSharingEllipsis(),
                            [string substringWithRange: tail]];
      if (GSSharingWidthOfString(candidate, font) <= width)
        {
          best = candidate;
          low = kept;
        }
      else
        {
          high = kept - 1;
        }
    }
  return best;
}

NSString *
GSSharingTileTitle(NSString *title, NSFont *font, CGFloat width)
{
  NSArray *words;
  NSUInteger count;
  NSUInteger fitting = 0;
  NSString *rest;

  if (title == nil || GSSharingWidthOfString(title, font) <= width)
    {
      return title;
    }
  /* The most words that fit on the first line; the rest go on the second. */
  words = [title componentsSeparatedByString: @" "];
  count = [words count];
  while (fitting + 1 < count
    && GSSharingWidthOfString([[words subarrayWithRange: NSMakeRange(0, fitting + 1)]
                                componentsJoinedByString: @" "], font) <= width)
    {
      fitting++;
    }
  /* A line doesn't end with a lone dash: "Send to Test" over "- home",
     not "Send to Test -" over "home". */
  if (fitting > 1 && fitting < count)
    {
      NSString *last = [words objectAtIndex: fitting - 1];

      if ([last length] == 1
        && ([last characterAtIndex: 0] == '-'
          || [last characterAtIndex: 0] == 0x2013
          || [last characterAtIndex: 0] == 0x2014))
        {
          fitting--;
        }
    }
  if (fitting == 0)
    {
      return GSSharingTruncateMiddle(title, font, width);
    }
  rest = [[words subarrayWithRange: NSMakeRange(fitting, count - fitting)]
           componentsJoinedByString: @" "];
  return [NSString stringWithFormat: @"%@\n%@",
                   [[words subarrayWithRange: NSMakeRange(0, fitting)]
                     componentsJoinedByString: @" "],
                   GSSharingTruncateMiddle(rest, font, width)];
}

/* A service's tile: a square button with its image above its title. */
static NSButton *
GSSharingServiceButton(NSRect frame)
{
  NSButton *button = AUTORELEASE([[NSButton alloc] initWithFrame: frame]);

  [button setButtonType: NSMomentaryPushInButton];
  [button setBezelStyle: NSRegularSquareBezelStyle];
  [button setImagePosition: NSImageAbove];
  return button;
}

/* "Q3 Plan.pdf", "63 KB" for a file; a count for several items. */
NSString *
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
      /* Words, not characters: an app's text is often markup (Markdown,
         HTML), whose length means nothing to the reader (#18). */
      NSString *text = (kind == GSSharingItemText ? item : [item string]);
      NSScanner *scanner = [NSScanner scannerWithString: text];
      NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
      NSUInteger words = 0;

      [scanner setCharactersToBeSkipped: space];
      while ([scanner scanUpToCharactersFromSet: space intoString: NULL])
        {
          words++;
        }
      if (words == 1)
        {
          return @"Text, 1 word";
        }
      return [NSString stringWithFormat: @"Text, about %lu words",
                       (unsigned long)words];
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
      /* rclone's remotes come in the background: the sheet shows them
         when they are there. */
      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(rcloneRemotesDidChange:)
               name: GSSharingRcloneRemotesDidChangeNotification
             object: nil];
    }
  return self;
}

- (void) rcloneRemotesDidChange: (NSNotification *)notification
{
  [self pickerItemsDidChange];
}

- (void) dealloc
{
  if (GSSharingShowingPanel == self)
    {
      GSSharingShowingPanel = nil;
    }
  [[NSNotificationCenter defaultCenter] removeObserver: self];
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
      /* An image file shows itself (a screenshot, a photo); others the
         file icon. */
      if (GSSharingIsImageFile(first))
        {
          image = AUTORELEASE([[NSImage alloc] initWithContentsOfFile: [first path]]);
        }
      if (image == nil)
        {
          image = GSSharingImageNamed(@"GSSharing-file");
        }
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
   of up to four (_columns). Returns the height they take; the services
   view is as wide as its tiles. */
- (CGFloat) layoutServices
{
  NSArray *subviews = [[[_servicesView subviews] copy] autorelease];
  NSUInteger count;
  NSUInteger rows;
  NSUInteger i;
  CGFloat height;
  CGFloat width;
  CGFloat buttonHeight = GSSharingButtonHeight;
  NSButton *probe;
  NSFont *font;
  CGFloat titleWidth;
  NSMutableArray *titles = [NSMutableArray array];

  [subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
  ASSIGN(_services, [self services]);
  count = [_services count];
  /* Titles are fitted with the font the theme gives a tile's cell, to the
     width the cell draws in. */
  probe = GSSharingServiceButton(NSMakeRect(0, 0, GSSharingButtonWidth,
                                            GSSharingButtonHeight));
  font = [[probe cell] font];
  titleWidth = NSWidth([[probe cell] drawingRectForBounds: [probe bounds]])
    - 2 * GSSharingButtonTitlePadding;
  /* Tiles grow, up to GSSharingButtonMaxWidth, before a title wraps: a
     theme with wide insets (WinUITheme leaves 90 pt of a 112 pt tile)
     otherwise put "Show in Folder" on two lines and made every tile taller
     (#21). They don't narrow while the sheet shows. */
  {
    CGFloat insets = GSSharingButtonWidth - titleWidth;
    CGFloat widest = 0.0;

    for (i = 0; i < count; i++)
      {
        NSString *title = [[_services objectAtIndex: i] menuItemTitle];

        CGFloat titleSize = (title != nil ? GSSharingWidthOfString(title, font) : 0.0);

        /* A title too long even for the widest tile wraps anyway: it
           doesn't widen the others. */
        if (titleSize + insets <= GSSharingButtonMaxWidth)
          {
            widest = MAX(widest, titleSize);
          }
      }
    _tileWidth = MAX(_tileWidth, MIN(MAX(GSSharingButtonWidth, ceil(widest + insets)),
                                     GSSharingButtonMaxWidth));
    titleWidth = _tileWidth - insets;
  }
  /* Every tile is a line taller when a title takes two. */
  for (i = 0; i < count; i++)
    {
      NSString *title = GSSharingTileTitle([[_services objectAtIndex: i] menuItemTitle],
                                           font, titleWidth);

      [titles addObject: (title != nil ? title : @"")];
      if ([title rangeOfString: @"\n"].location != NSNotFound)
        {
          buttonHeight = GSSharingButtonHeight + ceil([font defaultLineHeightForFont]);
        }
    }
  _columns = MAX(MIN(count, GSSharingColumns), 1);
  rows = (count + _columns - 1) / _columns;
  if (rows == 0)
    {
      rows = 1;
    }
  height = rows * buttonHeight + (rows - 1) * GSSharingButtonGap;
  width = (count == 0 ? 3 * _tileWidth + 2 * GSSharingButtonGap
           : _columns * _tileWidth + (_columns - 1) * GSSharingButtonGap);
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
      NSUInteger row = i / _columns;
      NSUInteger column = i % _columns;
      NSRect frame = NSMakeRect(column * (_tileWidth + GSSharingButtonGap),
                                height - (row + 1) * buttonHeight
                                - row * GSSharingButtonGap,
                                _tileWidth, buttonHeight);
      NSButton *button = GSSharingServiceButton(frame);
      NSImage *image = [service image];

      [button setTitle: [titles objectAtIndex: i]];
      /* A service without an image (an app's own) gets the share symbol,
         so its tile is laid out as the others are. */
      [button setImage: (image != nil ? image : GSSharingImageNamed(@"GSSharing-share"))];
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
  CGFloat servicesHeight = [self layoutServices];
  CGFloat gridWidth = _columns * _tileWidth
    + (_columns - 1) * GSSharingButtonGap;
  /* As wide as the tiles or the accessory, and at least three tiles, for
     the name above them (#17); the tiles start at the left margin, under
     the accessory's text. It doesn't narrow while the sheet shows, so it
     doesn't jump as the items change. */
  CGFloat width = MAX(MAX(gridWidth, 3 * _tileWidth + 2 * GSSharingButtonGap),
                      accessory != nil ? NSWidth([accessory frame]) : 0.0);
  CGFloat accessoryHeight = accessory != nil ? NSHeight([accessory frame]) + 12.0 : 0.0;
  CGFloat height = GSSharingMargin + GSSharingIconSize + 16.0
    + accessoryHeight + servicesHeight + GSSharingMargin;
  CGFloat y = height - GSSharingMargin - GSSharingIconSize;
  NSRect frame = [_panel frame];

  width = MAX(width, _width);
  _width = width;
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
      [accessory setFrameOrigin: NSMakePoint(GSSharingMargin, y)];
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
  _parentWindow = window;
  /* Each Share click makes a new picker, whose sheet would open over the
     last one's: a click on Share while the sheet shows takes the focus
     straight to the new sheet, so the old one never sees its window come
     back to close for (ScreenshotTool #316). */
  if (GSSharingShowingPanel != nil && GSSharingShowingPanel != self)
    {
      [GSSharingShowingPanel closeWithoutChoice];
    }
  GSSharingShowingPanel = self;
  _shownAt = [NSDate timeIntervalSinceReferenceDate];
  [[NSNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(panelDidResignKey:)
           name: NSWindowDidResignKeyNotification
         object: _panel];
  [_panel makeKeyAndOrderFront: nil];
}

/* Like a popover, the sheet closes when the user goes back to the window
   it was shown for (#14): its contents were made when it opened, and
   would be stale after more editing. Not while a service it started runs
   its dialog, nor just after it (re)opens, while the window manager is
   still moving focus. Another window (an alert, another app) leaves it. */
- (void) panelDidResignKey: (NSNotification *)notification
{
  if (_closed || _performing
    || [NSDate timeIntervalSinceReferenceDate] - _shownAt < 0.75)
    {
      return;
    }
  [self performSelector: @selector(closeIfParentIsKey:)
             withObject: nil
             afterDelay: 0.1];
}

- (void) closeIfParentIsKey: (id)sender
{
  if (_closed == NO && _performing == NO && _parentWindow != nil
    && [NSApp keyWindow] == _parentWindow && [_panel isKeyWindow] == NO)
    {
      [self closeWithoutChoice];
    }
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
  if (GSSharingShowingPanel == self)
    {
      GSSharingShowingPanel = nil;
    }
  RETAIN(self);
  /* A tooltip showing would stay on screen after the panel (#10). */
  [_icon removeAllToolTips];
  [[_servicesView subviews] makeObjectsPerformSelector: @selector(removeAllToolTips)];
  [_panel orderOut: nil];
  if ([delegate respondsToSelector:
         @selector(sharingServicePicker:didChooseSharingService:)])
    {
      [delegate sharingServicePicker: _picker didChooseSharingService: service];
    }
  GSSharingPickerDidFinish(_picker);
  AUTORELEASE(self);
}

- (void) serviceDidFinish: (NSNotification *)notification
{
  NSError *error = [[notification userInfo] objectForKey: @"error"];

  if ([[error domain] isEqual: NSCocoaErrorDomain]
    && [error code] == NSUserCancelledError)
    {
      _cancelled = YES;
    }
}

- (void) reopen
{
  GSSharingPickerState *state = GSSharingStateForPicker(_picker, NO);

  /* Not if the app has shown another sheet or closed this one since. */
  if (_closed == NO || state == nil || state->panel != self)
    {
      return;
    }
  GSSharingPickerKeepShowing(_picker);
  _closed = NO;
  if (GSSharingShowingPanel != nil && GSSharingShowingPanel != self)
    {
      [GSSharingShowingPanel closeWithoutChoice];
    }
  GSSharingShowingPanel = self;
  [self pickerItemsDidChange];
  _shownAt = [NSDate timeIntervalSinceReferenceDate];
  [_panel makeKeyAndOrderFront: nil];
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
  /* Save a Copy opens where the app says (#15). */
  ASSIGNCOPY(GSSharingStateForService(service, YES)->saveDirectory,
             [_picker saveDirectory]);
  /* A dialog the service runs while performing (Save a Copy, Open With)
     and the user cancels brings the sheet back, rather than leaving
     nothing (#16). A cancel reported later (an upload stopped) doesn't. */
  _cancelled = NO;
  _performing = YES;
  [[NSNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(serviceDidFinish:)
           name: GSSharingServiceDidFinishNotification
         object: service];
  RETAIN(self);
  [self finishWithService: service];
  [service performWithItems: items];
  [[NSNotificationCenter defaultCenter]
    removeObserver: self
              name: GSSharingServiceDidFinishNotification
            object: service];
  _performing = NO;
  if (_cancelled)
    {
      [self reopen];
    }
  RELEASE(self);
  RELEASE(items);
}

@end

#endif /* GS_HAS_SHARING_SERVICES */
