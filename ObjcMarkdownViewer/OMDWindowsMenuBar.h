// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

#if defined(_WIN32)
// Replaces the window's GNUstep menu bar with a native Win32 menu bar drawn
// in the WinUI style.
void OMDInstallWinUIStyleWindowsMenuBar(NSWindow *window, NSMenu *menu);
#endif
