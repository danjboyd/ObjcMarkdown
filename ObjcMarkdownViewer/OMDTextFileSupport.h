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
