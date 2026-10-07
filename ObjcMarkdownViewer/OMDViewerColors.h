// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// The GSTheme user default, which names the GNUstep theme.
extern NSString * const OMDThemeDefaultsKey;

// Chrome colours: each is one of the theme's system colours.
BOOL OMDSystemAppearanceIsDark(void);
NSString *OMDColorDefaultsString(NSColor *color);
NSColor *OMDColorFromDefaultsString(NSString *value);
NSColor *OMDResolvedControlTextColor(void);
NSColor *OMDResolvedChromeBackgroundColor(void);
NSColor *OMDResolvedPanelBackdropColor(void);
NSColor *OMDResolvedMutedTextColor(void);
