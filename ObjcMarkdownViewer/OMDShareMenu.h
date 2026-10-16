// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDShareItem.h"

// The tag of Email as > In the Message: the rendered document as the
// email's body (pasted from the clipboard, or filled in where the mail app
// takes a body). The other Email as items are tagged with their format.
enum {
    OMDShareEmailInMessageTag = 100
};

// The Share items, the same in File > Share and the toolbar's menu: each
// "Share as" item has its format as its tag and the action shareDocument:;
// then the Email as submenu (emailDocument:, tagged by format, and In the
// Message), copyRenderedDocument:, copyDocumentForSlack: and
// showDocumentInFolder:.
// The target is not retained (nil sends them along the responder chain).
void OMDAddShareMenuItems(NSMenu *menu, id target);

// The format last shared in (PDF until something is shared).
OMDShareFormat OMDShareLastFormat(void);
void OMDShareSetLastFormat(OMDShareFormat format);

// The Email as item last used: a format, or OMDShareEmailInMessageTag
// (PDF until something is emailed).
NSInteger OMDShareLastEmailChoice(void);
void OMDShareSetLastEmailChoice(NSInteger choice);
