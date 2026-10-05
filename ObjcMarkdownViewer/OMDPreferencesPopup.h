// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// On Windows, covers the pop-up button with a view that opens a themed
// pop-up panel instead of the native menu; does nothing elsewhere.
void OMDAddPreferencesPopupOverlay(NSView *container, NSPopUpButton *popup);
