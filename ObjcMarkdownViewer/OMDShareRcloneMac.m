// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareRcloneMac.h"

#if !defined(GNUSTEP)

// An encrypted rclone config's password, once given: for this launch only,
// never written anywhere.
static NSString *OMDRclonePassword = nil;

@interface OMDShareRcloneMac ()
- (void)uploadFile:(NSURL *)file toRemote:(GSSharingRcloneRemote *)remote;
- (void)askForPasswordForFile:(NSURL *)file;
- (void)remotesDidChange:(NSNotification *)notification;
- (void)cancelUpload:(id)sender;
@end

@implementation OMDShareRcloneMac

+ (void)refreshRemotes
{
    if ([GSSharingRclone executablePath] != nil) {
        [GSSharingRclone refreshRemotesInBackgroundWithPassword:OMDRclonePassword];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // The transfer keeps itself until it has told its delegate; this one
    // is going.
    [_transfer setDelegate:nil];
    [_transfer release];
    [_progressSheet release];
    [_pendingFile release];
    [super dealloc];
}

- (NSWindow *)sheetWindow
{
    return _window != nil ? _window : [NSApp mainWindow];
}

- (NSArray *)sharingServicesForFile:(NSURL *)file window:(NSWindow *)window
{
    NSMutableArray *services = [NSMutableArray array];
    if (file == nil || ![file isFileURL] || [GSSharingRclone executablePath] == nil) {
        return services;
    }
    _window = window;
    NSImage *image = [NSImage imageWithSystemSymbolName:@"link" accessibilityDescription:@"Link"];
    NSArray *remotes = [GSSharingRclone cachedRemotes];
    for (GSSharingRcloneRemote *remote in remotes) {
        NSString *title = [NSString stringWithFormat:@"Link on %@", [remote displayName]];
        NSSharingService *service = [[[NSSharingService alloc] initWithTitle:title
                                                                       image:image
                                                              alternateImage:nil
                                                                     handler:^{
            [self uploadFile:file toRemote:remote];
        }] autorelease];
        [services addObject:service];
    }
    if (remotes == nil &&
        [[[GSSharingRclone lastRemotesError] domain] isEqualToString:GSSharingRcloneErrorDomain] &&
        [[GSSharingRclone lastRemotesError] code] == GSSharingRcloneErrorNeedsPassword) {
        NSSharingService *service = [[[NSSharingService alloc] initWithTitle:@"Link with rclone (Locked)"
                                                                       image:image
                                                              alternateImage:nil
                                                                     handler:^{
            [self askForPasswordForFile:file];
        }] autorelease];
        [services addObject:service];
    }
    return services;
}

#pragma mark The password

- (void)askForPasswordForFile:(NSURL *)file
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Unlock rclone's configuration"];
    [alert setInformativeText:@"Its password is used for this upload and kept until you quit, never saved."];
    NSSecureTextField *field = [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 24.0)] autorelease];
    [alert setAccessoryView:field];
    [alert addButtonWithTitle:@"Unlock"];
    [alert addButtonWithTitle:@"Cancel"];
    [[alert window] setInitialFirstResponder:field];
    [alert beginSheetModalForWindow:[self sheetWindow] completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn || [[field stringValue] length] == 0) {
            return;
        }
        [OMDRclonePassword release];
        OMDRclonePassword = [[field stringValue] copy];
        [_pendingFile release];
        _pendingFile = [file retain];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(remotesDidChange:)
                                                     name:GSSharingRcloneRemotesDidChangeNotification
                                                   object:nil];
        [GSSharingRclone refreshRemotesInBackgroundWithPassword:OMDRclonePassword];
    }];
}

// After unlocking: upload to the one remote, or ask which.
- (void)remotesDidChange:(NSNotification *)notification
{
    (void)notification;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:GSSharingRcloneRemotesDidChangeNotification
                                                  object:nil];
    NSURL *file = [[_pendingFile retain] autorelease];
    [_pendingFile release];
    _pendingFile = nil;
    NSArray *remotes = [GSSharingRclone cachedRemotes];
    if (remotes == nil) {
        [OMDRclonePassword release];
        OMDRclonePassword = nil;
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"The password didn't unlock rclone's configuration."];
        [alert beginSheetModalForWindow:[self sheetWindow] completionHandler:nil];
        return;
    }
    if ([remotes count] == 0) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"None of rclone's remotes can make links."];
        [alert beginSheetModalForWindow:[self sheetWindow] completionHandler:nil];
        return;
    }
    if ([remotes count] == 1) {
        [self uploadFile:file toRemote:[remotes objectAtIndex:0]];
        return;
    }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Where should the link point?"];
    NSPopUpButton *choice = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 26.0) pullsDown:NO] autorelease];
    for (GSSharingRcloneRemote *remote in remotes) {
        [choice addItemWithTitle:[remote displayName]];
    }
    [alert setAccessoryView:choice];
    [alert addButtonWithTitle:@"Upload"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:[self sheetWindow] completionHandler:^(NSModalResponse response) {
        NSInteger index = [choice indexOfSelectedItem];
        if (response == NSAlertFirstButtonReturn && index >= 0 && (NSUInteger)index < [remotes count]) {
            [self uploadFile:file toRemote:[remotes objectAtIndex:(NSUInteger)index]];
        }
    }];
}

#pragma mark The upload

- (void)uploadFile:(NSURL *)file toRemote:(GSSharingRcloneRemote *)remote
{
    if (_transfer != nil) {
        NSBeep();
        return;
    }
    _transfer = [[GSSharingRcloneTransfer alloc] initWithFile:[file path] remote:remote folder:nil];
    [_transfer setDelegate:self];
    [_transfer setPassword:OMDRclonePassword];

    // The progress sheet: what is going where, a bar and Cancel.
    [_progressSheet release];
    _progressSheet = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 380.0, 112.0)
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    NSView *content = [_progressSheet contentView];
    NSString *text = [NSString stringWithFormat:@"Uploading %@ to %@...",
                                                [[file path] lastPathComponent], [remote displayName]];
    NSTextField *label = [NSTextField labelWithString:text];
    [label setFrame:NSMakeRect(20.0, 76.0, 340.0, 18.0)];
    [label setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [content addSubview:label];
    _progressBar = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20.0, 50.0, 340.0, 20.0)] autorelease];
    [_progressBar setStyle:NSProgressIndicatorStyleBar];
    [_progressBar setIndeterminate:YES];
    [_progressBar setMinValue:0.0];
    [_progressBar setMaxValue:1.0];
    [_progressBar startAnimation:nil];
    [content addSubview:_progressBar];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelUpload:)];
    [cancel setKeyEquivalent:@"\033"];
    [cancel sizeToFit];
    NSRect frame = [cancel frame];
    frame.origin = NSMakePoint(360.0 - NSWidth(frame), 12.0);
    [cancel setFrame:frame];
    [content addSubview:cancel];

    NSWindow *window = [self sheetWindow];
    if (window != nil) {
        [window beginSheet:_progressSheet completionHandler:nil];
    } else {
        [_progressSheet center];
        [_progressSheet makeKeyAndOrderFront:nil];
    }
    [_transfer start];
}

- (void)cancelUpload:(id)sender
{
    (void)sender;
    [_transfer cancel];
}

- (void)endUpload
{
    if ([_progressSheet sheetParent] != nil) {
        [[_progressSheet sheetParent] endSheet:_progressSheet];
    } else {
        [_progressSheet orderOut:nil];
    }
    [_progressSheet release];
    _progressSheet = nil;
    _progressBar = nil;
    [_transfer setDelegate:nil];
    [_transfer autorelease];
    _transfer = nil;
}

#pragma mark GSSharingRcloneTransferDelegate

- (void)rcloneTransfer:(id)transfer didProgress:(double)fraction
{
    if (transfer != _transfer) {
        return;
    }
    [_progressBar setIndeterminate:NO];
    [_progressBar setDoubleValue:fraction];
}

- (void)rcloneTransfer:(id)transfer didFinishWithLink:(NSURL *)link
{
    if (transfer != _transfer) {
        return;
    }
    NSString *place = [_transfer remoteDisplayPath];
    NSString *audience = [[_transfer remote] audience];
    NSString *name = [[_transfer file] lastPathComponent];
    [self endUpload];

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:[NSArray arrayWithObjects:link, [link absoluteString], nil]];

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    // The same words as the GNUstep notice.
    [alert setMessageText:[NSString stringWithFormat:@"The link to \u201C%@\u201D is on the clipboard.", name]];
    [alert setInformativeText:[NSString stringWithFormat:@"%@ The file is in %@.", audience, place]];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Open Link"];
    [alert beginSheetModalForWindow:[self sheetWindow] completionHandler:^(NSModalResponse response) {
        if (response == NSAlertSecondButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:link];
        }
    }];
}

- (void)rcloneTransfer:(id)transfer didFailWithError:(NSError *)error
{
    if (transfer != _transfer) {
        return;
    }
    [self endUpload];
    if ([[error domain] isEqualToString:GSSharingRcloneErrorDomain]) {
        if ([error code] == GSSharingRcloneErrorCancelled) {
            return;
        }
        if ([error code] == GSSharingRcloneErrorNeedsPassword) {
            [OMDRclonePassword release];
            OMDRclonePassword = nil;
        }
    }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[error localizedDescription]];
    NSString *reason = [[error userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
    if ([reason length] > 0) {
        [alert setInformativeText:reason];
    }
    [alert beginSheetModalForWindow:[self sheetWindow] completionHandler:nil];
}

@end

#endif
