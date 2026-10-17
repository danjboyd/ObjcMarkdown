// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// The Windows clipboard written directly, in the formats other Windows apps
// read (#179). GNUstep's win32 pasteboard server passes only text and images
// to the clipboard, so HTML, RTF and files never reached Outlook or Teams.
// It watches the clipboard, so text written here still pastes in GNUstep
// apps. Elsewhere these return NO and do nothing.

// "HTML Format" (CF_HTML, its header's offsets counted in UTF-8 bytes),
// "Rich Text Format" when rtf isn't nil, and the plain text. YES when the
// clipboard took them.
BOOL OMDWindowsClipboardWriteRichText(NSString *plain, NSString *htmlFragment, NSData *rtf);

// The files as CF_HDROP, marked for copying (what Explorer, Outlook and
// Teams paste as attachments), and their paths as text.
BOOL OMDWindowsClipboardWriteFiles(NSArray *paths);

// The "HTML Format" clipboard data for an HTML fragment: the header with
// its byte offsets, the fragment between the StartFragment and EndFragment
// comments, NUL-terminated. Exposed for tests.
NSData *OMDWindowsClipboardHTMLData(NSString *htmlFragment);
