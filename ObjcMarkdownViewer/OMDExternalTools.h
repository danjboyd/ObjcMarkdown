// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// Finding external executables, normalising paths from other programs and
// opening links outside the app.
NSString *OMDExecutablePathNamed(NSString *name);
BOOL OMDLooksLikeWindowsAbsolutePath(NSString *path);
NSString *OMDNormalizedExternalLocalPath(NSString *path);
BOOL OMDOpenURLUsingXDGOpen(NSURL *url);
// Opens a URL with the desktop's handler (the browser for web links).
BOOL OMDOpenURL(NSURL *url);
BOOL OMDShouldOpenURLForUserNavigation(NSURL *url);
// Opens a folder in the desktop's file manager.
BOOL OMDOpenFolderInFileManager(NSString *folder);
// Shows a file or folder selected in the desktop's file manager, or else
// opens the folder that holds it.
BOOL OMDRevealPathInFileManager(NSString *path);

// The arguments that have a headless Edge or Chrome print the page at url to
// pdfPath, without the browser's page header and footer (date, title, the
// page's address): --no-pdf-header-footer for current versions and
// --print-to-pdf-no-header for older ones, which ignore the other (#378).
NSArray *OMDHeadlessPrintToPDFArguments(NSString *pdfPath, NSString *url);

#if defined(_WIN32)
BOOL OMDWindowsBundledExternalMathToolchainAvailable(void);
NSString *OMDHTMLEscapedString(NSString *value);
#endif
