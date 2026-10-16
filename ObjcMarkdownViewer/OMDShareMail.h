// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// A mailto: draft link with a subject, its value percent-encoded as
// RFC 6068 asks (everything but letters, digits and -._~).
NSURL *OMDMailtoURLWithSubject(NSString *subject);

// Whether the mail app with this desktop file ID or executable name can
// take an attachment handed over by xdg-email: the desktop clients
// xdg-email knows (Evolution, Thunderbird, KMail, Claws...). A browser
// (webmail) or an unknown app can't; it gets a draft without the file.
BOOL OMDMailAppTakesAttachments(NSString *appID);
