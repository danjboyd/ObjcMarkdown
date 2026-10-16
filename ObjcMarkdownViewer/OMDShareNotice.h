// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDSharePresenter.h"

// The small notice a share shows when the destination couldn't take the
// file itself (webmail as the email client, Teams or Slack on Linux): the
// message, the file (drag it into a mail or chat), Copy File and Show in
// Folder. Standard controls in tooltip colours, near the top of the
// document's window. Non-modal; Escape, Close or closing the window
// dismisses it. One notice per window: a new one replaces the old.
@interface OMDShareNotice : NSObject

+ (void)showNoticeWithMessage:(NSString *)message
                    shareItem:(OMDShareItem *)item
                    presenter:(id<OMDSharePresenter>)presenter
                    forWindow:(NSWindow *)window;

// Closes the window's notice, if it has one.
+ (void)dismissNoticeForWindow:(NSWindow *)window;

@end
