// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// String, path and file-content helpers shared across the viewer.
NSString *OMDTrimmedString(NSString *value);
NSString *OMDDiskFingerprintForFileAttributes(NSDictionary *attributes);
BOOL OMDIsMarkdownExtension(NSString *extension);
NSString *OMDVerbatimSyntaxTokenForExtension(NSString *extension);
NSString *OMDMarkdownCodeFenceWrappedText(NSString *text, NSString *languageToken);
BOOL OMDDataAppearsBinary(NSData *data);
NSString *OMDDecodeTextFromData(NSData *data, NSStringEncoding *usedEncodingOut);
NSString *OMDNormalizedRelativePath(NSString *value);
// The name a print job (and a PDF saved from it) carries: what the window
// shows, or nil to leave the print system's default (#261).
NSString *OMDPrintJobTitle(NSString *path, NSString *displayTitle);
