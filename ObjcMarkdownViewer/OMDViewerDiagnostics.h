// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// Appends a line to the startup log in the temporary directory on Windows;
// does nothing elsewhere.
void OMDStartupTrace(NSString *message);
