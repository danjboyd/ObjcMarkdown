/* GSSharingNotice.m

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingNotice.h"
#import "GSSharingPickerPanel.h"

#ifndef GS_HAS_SHARING_SERVICES

static GSSharingNotice *current = nil;

@interface GSSharingNoticePanel : NSPanel
@end

@implementation GSSharingNoticePanel
- (BOOL) canBecomeKeyWindow
{
  return YES;
}
- (void) cancelOperation: (id)sender
{
  [self performClose: nil];
}
@end

@interface GSSharingNotice (Private)
- (id) initWithMessage: (NSString *)message
                detail: (NSString *)detail
                  file: (NSURL *)fileURL;
- (void) show;
- (void) close;
@end

static NSTextField *
GSSharingNoticeLabel(NSString *text, NSRect frame, NSFont *font, NSColor *color)
{
  NSTextField *label = AUTORELEASE([[NSTextField alloc] initWithFrame: frame]);

  [label setStringValue: text];
  [label setEditable: NO];
  [label setSelectable: NO];
  [label setBezeled: NO];
  [label setBordered: NO];
  [label setDrawsBackground: NO];
  [label setFont: font];
  [label setTextColor: color];
  [[label cell] setWraps: YES];
  return label;
}

/* The height text wraps to in width: GNUstep's text field cell measures
   one line whatever it wraps to. Each line is given room for a word that
   didn't fit at its end. */
static CGFloat
GSSharingNoticeTextHeight(NSString *text, NSFont *font, CGFloat width)
{
  NSDictionary *attributes = [NSDictionary dictionaryWithObject: font
                                                         forKey: NSFontAttributeName];
  CGFloat textWidth = [text sizeWithAttributes: attributes].width;
  CGFloat lineHeight = ceil([font ascender] - [font descender] + [font leading]) + 1.0;
  CGFloat lines = ceil(textWidth / (width * 0.9));

  if (lines < 1.0)
    {
      lines = 1.0;
    }
  return lines * lineHeight + 4.0;
}

@implementation GSSharingNotice

+ (void) showMessage: (NSString *)message
              detail: (NSString *)detail
                file: (NSURL *)fileURL
{
  [self dismiss];
  current = [[GSSharingNotice alloc] initWithMessage: message
                                              detail: detail
                                                file: fileURL];
  [current show];
}

+ (void) dismiss
{
  [current close];
}

- (id) initWithMessage: (NSString *)message
                detail: (NSString *)detail
                  file: (NSURL *)fileURL
{
  CGFloat width = 460.0;
  CGFloat height = 140.0;
  CGFloat margin = 16.0;
  CGFloat iconSize = 48.0;
  CGFloat textX = margin;
  NSTextField *detailLabel = nil;
  CGFloat detailHeight = 0.0;
  NSView *content;
  NSArray *titles;
  SEL actions[3];
  CGFloat widths[3] = { 80.0, 100.0, 130.0 };
  NSUInteger count;
  NSUInteger i;
  CGFloat x;

  if ((self = [super init]) == nil)
    {
      return nil;
    }
  ASSIGNCOPY(_fileURL, fileURL);
  /* The detail wraps: the notice grows for a long one. */
  if (fileURL != nil)
    {
      textX = margin + iconSize + 12.0;
    }
  if (detail != nil)
    {
      detailLabel = GSSharingNoticeLabel(detail,
        NSMakeRect(0, 0, width - textX - margin, 32.0),
        [NSFont systemFontOfSize: [NSFont smallSystemFontSize]],
        [NSColor secondaryLabelColor]);
      detailHeight = GSSharingNoticeTextHeight(detail, [detailLabel font],
                                               width - textX - margin);
      if (detailHeight < 32.0)
        {
          detailHeight = 32.0;
        }
      height += detailHeight - 32.0;
    }
  _panel = [[GSSharingNoticePanel alloc]
    initWithContentRect: NSMakeRect(0, 0, width, height)
              styleMask: (NSTitledWindowMask | NSClosableWindowMask
                          | NSUtilityWindowMask)
                backing: NSBackingStoreBuffered
                  defer: NO];
  [_panel setTitle: @"Share"];
  [_panel setReleasedWhenClosed: NO];
  [_panel setHidesOnDeactivate: NO];
  [_panel setDelegate: (id)self];
  content = [_panel contentView];

  if (fileURL != nil)
    {
      GSSharingFileDragView *icon = AUTORELEASE([[GSSharingFileDragView alloc]
        initWithFrame: NSMakeRect(margin, height - margin - iconSize,
                                  iconSize, iconSize)]);

      [icon setImage: GSSharingImageNamed(@"GSSharing-file")];
      [icon setImageScaling: NSImageScaleProportionallyUpOrDown];
      [icon setEditable: NO];
      [icon setFileURL: fileURL];
      [icon setToolTip: @"Drag the file into an email or a chat"];
      [content addSubview: icon];
    }
  [content addSubview: GSSharingNoticeLabel(message,
    NSMakeRect(textX, height - margin - 36.0, width - textX - margin, 36.0),
    [NSFont systemFontOfSize: 0], [NSColor labelColor])];
  if (detailLabel != nil)
    {
      [detailLabel setFrame: NSMakeRect(textX, height - margin - 38.0 - detailHeight,
                                        width - textX - margin, detailHeight)];
      [content addSubview: detailLabel];
    }

  titles = [NSArray arrayWithObjects: @"Close", @"Copy File", @"Show in Folder", nil];
  actions[0] = @selector(closeClicked:);
  actions[1] = @selector(copyFileClicked:);
  actions[2] = @selector(showInFolderClicked:);
  count = fileURL != nil ? 3 : 1;
  x = width - margin;
  for (i = 0; i < count; i++)
    {
      NSButton *button;

      x -= widths[i];
      button = AUTORELEASE([[NSButton alloc]
        initWithFrame: NSMakeRect(x, margin - 4.0, widths[i], 28.0)]);
      [button setTitle: [titles objectAtIndex: i]];
      [button setBezelStyle: NSRoundedBezelStyle];
      [button setTarget: self];
      [button setAction: actions[i]];
      if (i == 0)
        {
          [button setKeyEquivalent: @"\e"];
        }
      [content addSubview: button];
      x -= 8.0;
    }
  return self;
}

- (void) dealloc
{
  [_panel setDelegate: nil];
  RELEASE(_panel);
  RELEASE(_fileURL);
  [super dealloc];
}

- (void) show
{
  NSWindow *key = [NSApp keyWindow];
  NSRect frame = [_panel frame];

  if (key != nil)
    {
      NSRect parent = [key frame];

      frame.origin.x = floor(NSMidX(parent) - NSWidth(frame) / 2.0);
      frame.origin.y = floor(NSMaxY(parent) - NSHeight(frame) - 96.0);
      [_panel setFrameOrigin: frame.origin];
    }
  else
    {
      [_panel center];
    }
  [_panel makeKeyAndOrderFront: nil];
}

- (void) close
{
  [_panel close];
}

- (void) closeClicked: (id)sender
{
  [self close];
}

- (void) copyFileClicked: (id)sender
{
  NSSharingService *copy = [NSSharingService sharingServiceNamed:
                                               GSSharingServiceNameCopy];

  [copy performWithItems: [NSArray arrayWithObject: _fileURL]];
}

- (void) showInFolderClicked: (id)sender
{
  NSSharingService *show = [NSSharingService sharingServiceNamed:
                                               GSSharingServiceNameShowInFolder];

  [show performWithItems: [NSArray arrayWithObject: _fileURL]];
}

- (void) windowWillClose: (NSNotification *)notification
{
  if (current == self)
    {
      current = nil;
      AUTORELEASE(self);
    }
}

@end

#endif /* GS_HAS_SHARING_SERVICES */
