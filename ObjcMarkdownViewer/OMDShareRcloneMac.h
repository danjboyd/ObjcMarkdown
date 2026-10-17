// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

#if !defined(GNUSTEP)
#import "GSSharingRclone.h"

// Links through rclone in Apple's sharing picker (#198): one service per
// rclone remote that can make links, which uploads the shared file there
// (libs-sharing's GSSharingRclone) with a progress sheet, then puts the
// link on the clipboard and says who can open it. Shown only when rclone
// is installed; an encrypted config shows one service that asks for its
// password, kept in memory for this launch only.
@interface OMDShareRcloneMac : NSObject <GSSharingRcloneTransferDelegate>
{
    GSSharingRcloneTransfer *_transfer;
    NSWindow *_window;
    NSPanel *_progressSheet;
    NSProgressIndicator *_progressBar;
    // A file waiting for the remotes after the config is unlocked.
    NSURL *_pendingFile;
}

// Looks for rclone's remotes in the background, so the picker has them
// when it opens (it can't wait for rclone).
+ (void)refreshRemotes;

// The picker's services for a shared file, from the remotes found so far;
// window is where the sheets go.
- (NSArray *)sharingServicesForFile:(NSURL *)file window:(NSWindow *)window;

@end
#endif
