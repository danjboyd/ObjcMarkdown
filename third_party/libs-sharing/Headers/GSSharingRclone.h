/* GSSharingRclone.h: uploads a file with rclone and makes a link to it.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   Foundation only, so an app on macOS can compile Source/GSSharingRclone.m
   on its own; on GNUstep the library offers it as a sharing service, one
   per remote. rclone is run by its argv, never through a shell; the
   app stores no credentials (rclone keeps its own config, and an
   encrypted config's password is used for one run only). */

#ifndef _GNUstep_H_GSSharingRclone
#define _GNUstep_H_GSSharingRclone

#import <Foundation/Foundation.h>

#if defined(__cplusplus)
extern "C" {
#endif

extern NSString * const GSSharingRcloneErrorDomain;
/** Posted on the main thread when a background refresh of the remotes
    (+refreshRemotesInBackgroundWithPassword:) is done. */
extern NSString * const GSSharingRcloneRemotesDidChangeNotification;

enum {
  GSSharingRcloneErrorNotInstalled = 1,  /* no rclone on this computer */
  GSSharingRcloneErrorNeedsPassword,     /* the config is encrypted */
  GSSharingRcloneErrorExpiredToken,      /* sign in again: rclone config reconnect */
  GSSharingRcloneErrorNoLinks,           /* the remote can't make links */
  GSSharingRcloneErrorCancelled,
  GSSharingRcloneErrorFailed             /* anything else; rclone's own words in the failure reason */
};

#if defined(__cplusplus)
}
#endif

/** A remote in rclone's config that can make links to files. */
@interface GSSharingRcloneRemote : NSObject
{
  NSString *_name;
  NSString *_type;
}
- (id) initWithName: (NSString *)name type: (NSString *)type;
/** As rclone knows it, without the colon: "Work Drive". */
- (NSString *) name;
/** rclone's backend: "onedrive", "drive", "dropbox", ... */
- (NSString *) type;
/** For a button or a menu: "Work Drive (OneDrive)". */
- (NSString *) displayName;
/** Who can open a link it makes, as a sentence for the user. It goes
    with -linkArguments:
    - onedrive: --onedrive-link-scope organization --onedrive-link-type view
      ("People in your organization who have the link can open it.");
    - every other backend (drive, dropbox, box, pcloud, mega, ...): no
      flags, as none can narrow who opens a link ("Anyone with the link
      can open it."). */
- (NSString *) audience;
/** rclone link's arguments for the scope, after the path. */
- (NSArray *) linkArguments;
@end

@interface GSSharingRclone : NSObject
/** rclone's path: the PATH first, then the usual places (/usr/local/bin,
    /opt/homebrew/bin, /opt/local/bin, ~/.local/bin, ~/bin, and on Windows
    the Scoop, Chocolatey and WinGet links); nil when it isn't installed. A
    GUI app on macOS gets a short PATH, so the list is what finds it. */
+ (NSString *) executablePath;
/** Uses this rclone instead of looking for one (an app that bundles
    rclone, or a test); nil to look again. */
+ (void) setExecutablePath: (NSString *)path;
/** The remotes that can make links, from `rclone listremotes --long`
    (never `config show`, which prints tokens), kept for a minute.
    password is for an encrypted config, or nil. Nil with the error when
    rclone isn't there or fails; an empty array when no remote can make
    links. */
+ (NSArray *) remotesWithPassword: (NSString *)password error: (NSError **)error;
/** Forgets the remotes kept, so the next call asks rclone again. */
+ (void) forgetRemotes;
/** For a share sheet, which can't wait for rclone: the remotes kept from
    the last look (nil if none yet, or it failed), the error of the last
    look (GSSharingRcloneErrorNeedsPassword for an encrypted config), and a
    look in the background that posts
    GSSharingRcloneRemotesDidChangeNotification when it's done. The remotes
    kept stay until the look ends. A look asked for while one runs (with a
    password just typed, say) runs after it, and the notification comes
    once, after the last. */
+ (NSArray *) cachedRemotes;
+ (NSError *) lastRemotesError;
+ (void) refreshRemotesInBackgroundWithPassword: (NSString *)password;
/** The error for rclone's own error text: an expired sign-in or an
    encrypted config are told apart; the text is the failure reason. */
+ (NSError *) errorForOutput: (NSString *)output remote: (NSString *)remote;
@end

/** What a transfer tells its delegate, on the main thread. */
@protocol GSSharingRcloneTransferDelegate
/** How much is uploaded, from 0 to 1. */
- (void) rcloneTransfer: (id)transfer didProgress: (double)fraction;
- (void) rcloneTransfer: (id)transfer didFinishWithLink: (NSURL *)link;
- (void) rcloneTransfer: (id)transfer didFailWithError: (NSError *)error;
@end

/** Uploads a file to a remote with `rclone copyto`, into a folder of its
    own there, then makes a link with `rclone link` with the narrowest scope
    the backend has (OneDrive: people in the organization, view only). */
@interface GSSharingRcloneTransfer : NSObject
{
  NSString *_file;
  GSSharingRcloneRemote *_remote;
  NSString *_folder;
  NSString *_password;
  NSString *_remotePath;
  id _delegate;
  NSTask *_task;
  NSLock *_lock;
  BOOL _cancelled;
  BOOL _running;
  BOOL _uploadStarted;
}
/** folder is where the file goes on the remote; nil for "Shared from"
    and the app's name (CFBundleDisplayName, CFBundleName, then the process
    name). A name taken there gets " (2)", " (3)", ... */
- (id) initWithFile: (NSString *)path
             remote: (GSSharingRcloneRemote *)remote
             folder: (NSString *)folder;
/** Not retained. */
- (void) setDelegate: (id)delegate;
- (id) delegate;
/** An encrypted config's password, for this transfer's runs of rclone
    only. */
- (void) setPassword: (NSString *)password;
- (void) start;
/** Stops rclone, and deletes what an interrupted upload left on the
    remote as best it can; the delegate is told with
    GSSharingRcloneErrorCancelled. */
- (void) cancel;
/** "Work Drive:Shared from App/Report.pdf", once the upload has begun. */
- (NSString *) remotePath;
/** The same for a person: "Work Drive: Shared from App/Report.pdf". */
- (NSString *) remoteDisplayPath;
- (GSSharingRcloneRemote *) remote;
- (NSString *) file;
@end

#endif /* _GNUstep_H_GSSharingRclone */
