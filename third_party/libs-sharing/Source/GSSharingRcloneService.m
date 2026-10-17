/* GSSharingRcloneService.m: the sheet's rclone services, one per remote
   that makes links: the file is uploaded with a progress panel and Cancel,
   and the link goes on the clipboard, with who can open it.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPrivate.h"
#import "GSSharingNotice.h"
#import "GSSharingRclone.h"

#ifndef GS_HAS_SHARING_SERVICES

static NSString * const GSSharingRclonePrefix = @"GSSharingRclone:";
static NSString * const GSSharingRcloneUnlockName = @"GSSharingRcloneUnlock";

/* An encrypted config's password, while the app runs; never written
   anywhere. */
static NSString *rclonePassword = nil;
/* When the remotes were last asked for, so the sheet asks again only now
   and then (each answer lays the sheet out again, which asks for the
   services). */
static NSDate *lastRefresh = nil;

@interface GSSharingRcloneUpload : NSObject <GSSharingRcloneTransferDelegate>
{
  GSSharingRcloneTransfer *_transfer;
  NSPanel *_panel;
  NSTextField *_label;
  NSProgressIndicator *_bar;
}
+ (void) upload: (NSArray *)items service: (NSSharingService *)service;
+ (void) unlock: (NSArray *)items service: (NSSharingService *)service;
@end

/* The first file among items, or nil. */
static NSURL *
GSSharingRcloneFileOfItems(NSArray *items)
{
  NSEnumerator *e = [items objectEnumerator];
  id item;

  while ((item = [e nextObject]) != nil)
    {
      if (GSSharingKindOfItem(item) == GSSharingItemFile)
        {
          return item;
        }
    }
  return nil;
}

static NSSharingService *
GSSharingRcloneMakeService(NSString *name, NSString *title, SEL action)
{
  NSSharingService *service
    = AUTORELEASE([[NSSharingService alloc]
                    initWithTitle: title
                            image: nil
                   alternateImage: nil
                           target: [GSSharingRcloneUpload class]
                           action: action]);
  GSSharingServiceState *state = GSSharingStateForService(service, YES);

  ASSIGNCOPY(state->name, name);
  ASSIGNCOPY(state->imageName, @"GSSharing-cloud");
  state->accepts = GSSharingItemFile;
  return service;
}

NSArray *
GSSharingRcloneServicesForItems(NSArray *items)
{
  NSMutableArray *services = [NSMutableArray array];
  NSArray *remotes;
  NSError *error;
  NSEnumerator *e;
  GSSharingRcloneRemote *remote;

  /* A Flatpak's sandbox has no rclone, and shouldn't reach the user's
     cloud sign-ins; one file at a time. */
  if ([[NSFileManager defaultManager] fileExistsAtPath: @"/.flatpak-info"]
    || [GSSharingRclone executablePath] == nil
    || (items != nil && ([items count] != 1
                         || GSSharingRcloneFileOfItems(items) == nil)))
    {
      return services;
    }
  if (lastRefresh == nil || -[lastRefresh timeIntervalSinceNow] > 60.0)
    {
      ASSIGN(lastRefresh, [NSDate date]);
      [GSSharingRclone refreshRemotesInBackgroundWithPassword: rclonePassword];
    }
  remotes = [GSSharingRclone cachedRemotes];
  error = [GSSharingRclone lastRemotesError];
  if (remotes == nil && [error code] == GSSharingRcloneErrorNeedsPassword)
    {
      [services addObject: GSSharingRcloneMakeService(GSSharingRcloneUnlockName,
        @"rclone", @selector(unlock:service:))];
      return services;
    }
  e = [remotes objectEnumerator];
  while ((remote = [e nextObject]) != nil)
    {
      [services addObject: GSSharingRcloneMakeService(
        [GSSharingRclonePrefix stringByAppendingString: [remote name]],
        [remote name], @selector(upload:service:))];
    }
  return services;
}

static GSSharingRcloneRemote *
GSSharingRcloneRemoteNamed(NSString *name)
{
  NSEnumerator *e = [[GSSharingRclone cachedRemotes] objectEnumerator];
  GSSharingRcloneRemote *remote;

  while ((remote = [e nextObject]) != nil)
    {
      if ([[remote name] isEqualToString: name])
        {
          return remote;
        }
    }
  return nil;
}

/* A small modal panel: a message, a field or a pop-up, OK and Cancel.
   Returns YES for OK. */
static BOOL
GSSharingRcloneAsk(NSString *title, NSString *message, NSControl *control,
                   NSString *okTitle)
{
  NSPanel *panel = AUTORELEASE([[NSPanel alloc]
    initWithContentRect: NSMakeRect(0, 0, 380, 150)
              styleMask: NSTitledWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO]);
  NSView *content = [panel contentView];
  NSTextField *label = AUTORELEASE([[NSTextField alloc]
    initWithFrame: NSMakeRect(20, 86, 340, 48)]);
  NSButton *ok = AUTORELEASE([[NSButton alloc]
    initWithFrame: NSMakeRect(270, 14, 90, 28)]);
  NSButton *cancel = AUTORELEASE([[NSButton alloc]
    initWithFrame: NSMakeRect(172, 14, 90, 28)]);
  NSInteger answer;

  [panel setTitle: title];
  [label setStringValue: message];
  [label setEditable: NO];
  [label setSelectable: NO];
  [label setBezeled: NO];
  [label setBordered: NO];
  [label setDrawsBackground: NO];
  [[label cell] setWraps: YES];
  [content addSubview: label];
  [control setFrame: NSMakeRect(20, 54, 340, 24)];
  [content addSubview: control];
  [ok setTitle: okTitle];
  [ok setBezelStyle: NSRoundedBezelStyle];
  [ok setKeyEquivalent: @"\r"];
  [ok setTarget: NSApp];
  [ok setAction: @selector(stopModal)];
  [cancel setTitle: @"Cancel"];
  [cancel setBezelStyle: NSRoundedBezelStyle];
  [cancel setKeyEquivalent: @"\e"];
  [cancel setTarget: NSApp];
  [cancel setAction: @selector(abortModal)];
  [content addSubview: ok];
  [content addSubview: cancel];
  [panel center];
  [panel makeFirstResponder: control];
  answer = [NSApp runModalForWindow: panel];
  [panel orderOut: nil];
  return answer == NSRunStoppedResponse;
}

@implementation GSSharingRcloneUpload

- (id) initWithFile: (NSString *)path remote: (GSSharingRcloneRemote *)remote
{
  if ((self = [super init]) != nil)
    {
      _transfer = [[GSSharingRcloneTransfer alloc] initWithFile: path
                                                         remote: remote
                                                         folder: nil];
      [_transfer setDelegate: self];
      [_transfer setPassword: rclonePassword];
    }
  return self;
}

- (void) dealloc
{
  [_transfer setDelegate: nil];
  RELEASE(_transfer);
  RELEASE(_panel);
  [super dealloc];
}

/* The progress panel: what is uploaded where, the bar, Cancel. */
- (void) showPanel
{
  NSView *content;
  NSButton *cancel;

  _panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 400, 112)
                                      styleMask: NSTitledWindowMask
                                        backing: NSBackingStoreBuffered
                                          defer: NO];
  [_panel setTitle: @"Share"];
  [_panel setReleasedWhenClosed: NO];
  content = [_panel contentView];
  _label = AUTORELEASE([[NSTextField alloc] initWithFrame: NSMakeRect(20, 72, 360, 20)]);
  [_label setStringValue: [NSString stringWithFormat: @"Uploading “%@” to %@…",
                                    [[_transfer file] lastPathComponent],
                                    [[_transfer remote] displayName]]];
  [_label setEditable: NO];
  [_label setSelectable: NO];
  [_label setBezeled: NO];
  [_label setBordered: NO];
  [_label setDrawsBackground: NO];
  [content addSubview: _label];
  _bar = AUTORELEASE([[NSProgressIndicator alloc] initWithFrame: NSMakeRect(20, 50, 360, 16)]);
  [_bar setStyle: NSProgressIndicatorBarStyle];
  [_bar setIndeterminate: YES];
  [_bar setMinValue: 0.0];
  [_bar setMaxValue: 1.0];
  [content addSubview: _bar];
  [_bar startAnimation: nil];
  cancel = AUTORELEASE([[NSButton alloc] initWithFrame: NSMakeRect(290, 12, 90, 28)]);
  [cancel setTitle: @"Cancel"];
  [cancel setBezelStyle: NSRoundedBezelStyle];
  [cancel setKeyEquivalent: @"\e"];
  [cancel setTarget: self];
  [cancel setAction: @selector(cancel:)];
  [content addSubview: cancel];
  [_panel center];
  [_panel makeKeyAndOrderFront: nil];
}

- (void) start
{
  /* Kept until the transfer is done. */
  RETAIN(self);
  [self showPanel];
  [_transfer start];
}

- (void) cancel: (id)sender
{
  [_label setStringValue: @"Cancelling…"];
  [sender setEnabled: NO];
  [_transfer cancel];
}

- (void) rcloneTransfer: (id)transfer didProgress: (double)fraction
{
  if ([_bar isIndeterminate])
    {
      [_bar stopAnimation: nil];
      [_bar setIndeterminate: NO];
    }
  [_bar setDoubleValue: fraction];
}

- (void) rcloneTransfer: (id)transfer didFinishWithLink: (NSURL *)link
{
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

  [_panel orderOut: nil];
  [pasteboard declareTypes: [NSArray arrayWithObject: NSStringPboardType]
                     owner: nil];
  [pasteboard setString: [link absoluteString] forType: NSStringPboardType];
  [GSSharingNotice showMessage:
     [NSString stringWithFormat: @"The link to “%@” is on the clipboard.",
               [[_transfer file] lastPathComponent]]
                        detail: [NSString stringWithFormat: @"%@ The file is in %@.",
                                          [[_transfer remote] audience],
                                          [_transfer remoteDisplayPath]]
                          file: nil];
  AUTORELEASE(self);
}

- (void) rcloneTransfer: (id)transfer didFailWithError: (NSError *)error
{
  [_panel orderOut: nil];
  if ([error code] != GSSharingRcloneErrorCancelled)
    {
      NSString *reason = [error localizedFailureReason];
      NSString *text = [error localizedDescription];

      if ([reason length] > 0)
        {
          text = [NSString stringWithFormat: @"%@\n\n%@", text, reason];
        }
      NSRunAlertPanel(@"Couldn't upload the file", @"%@", @"OK", nil, nil, text);
    }
  AUTORELEASE(self);
}

+ (void) uploadFile: (NSString *)path to: (GSSharingRcloneRemote *)remote
{
  GSSharingRcloneUpload *upload = AUTORELEASE([[self alloc] initWithFile: path
                                                                  remote: remote]);

  [upload start];
}

+ (void) upload: (NSArray *)items service: (NSSharingService *)service
{
  GSSharingServiceState *state = GSSharingStateForService(service, NO);
  NSString *name = [state->name substringFromIndex: [GSSharingRclonePrefix length]];
  GSSharingRcloneRemote *remote = GSSharingRcloneRemoteNamed(name);
  NSURL *file = GSSharingRcloneFileOfItems(items);

  if (remote == nil || file == nil)
    {
      NSBeep();
      return;
    }
  [self uploadFile: [file path] to: remote];
}

/* An encrypted config: its password, then the remote, then the upload. */
+ (void) unlock: (NSArray *)items service: (NSSharingService *)service
{
  NSURL *file = GSSharingRcloneFileOfItems(items);
  NSSecureTextField *field = AUTORELEASE([[NSSecureTextField alloc]
    initWithFrame: NSMakeRect(0, 0, 340, 24)]);
  NSArray *remotes;
  NSError *error = nil;
  GSSharingRcloneRemote *remote;

  if (file == nil)
    {
      return;
    }
  if (GSSharingRcloneAsk(@"rclone",
        @"rclone's configuration is encrypted. Its password is needed to list your remotes; it is kept only while this app runs.",
        field, @"Unlock") == NO)
    {
      return;
    }
  [GSSharingRclone forgetRemotes];
  remotes = [GSSharingRclone remotesWithPassword: [field stringValue] error: &error];
  if (remotes == nil)
    {
      NSRunAlertPanel(@"Couldn't unlock rclone", @"%@", @"OK", nil, nil,
                      [error localizedDescription]);
      return;
    }
  ASSIGN(rclonePassword, [field stringValue]);
  ASSIGN(lastRefresh, [NSDate date]);
  if ([remotes count] == 0)
    {
      NSRunAlertPanel(@"rclone", @"None of your rclone remotes can make links to files.",
                      @"OK", nil, nil);
      return;
    }
  remote = [remotes objectAtIndex: 0];
  if ([remotes count] > 1)
    {
      NSPopUpButton *popup = AUTORELEASE([[NSPopUpButton alloc]
        initWithFrame: NSMakeRect(0, 0, 340, 24) pullsDown: NO]);
      NSEnumerator *e = [remotes objectEnumerator];
      GSSharingRcloneRemote *r;

      while ((r = [e nextObject]) != nil)
        {
          [popup addItemWithTitle: [r displayName]];
        }
      if (GSSharingRcloneAsk(@"rclone",
            [NSString stringWithFormat: @"Upload “%@” to:",
                      [[file path] lastPathComponent]],
            popup, @"Upload") == NO)
        {
          return;
        }
      remote = [remotes objectAtIndex: [popup indexOfSelectedItem]];
    }
  [self uploadFile: [file path] to: remote];
}

@end

#endif /* GS_HAS_SHARING_SERVICES */
