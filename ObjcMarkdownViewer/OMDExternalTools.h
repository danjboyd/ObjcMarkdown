// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// Finding external executables, normalising paths from other programs and
// opening links outside the app.
NSString *OMDExecutablePathNamed(NSString *name);
BOOL OMDLooksLikeWindowsAbsolutePath(NSString *path);
NSString *OMDNormalizedExternalLocalPath(NSString *path);
BOOL OMDOpenURLUsingXDGOpen(NSURL *url);
BOOL OMDShouldOpenURLForUserNavigation(NSURL *url);

#if defined(_WIN32)
BOOL OMDWindowsBundledExternalMathToolchainAvailable(void);
NSString *OMDHTMLEscapedString(NSString *value);
#endif
