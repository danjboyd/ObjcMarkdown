// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Images from the app bundle.
NSImage *OMDImageNamed(NSString *resourceName);
// One of the app's symbolic icons (Resources/icons, made by
// tools/icons/make-symbolic-icons.py), by its name without ".png", such as
// @"omd-document-open-symbolic". The image keeps that name, so a theme
// that tints template images draws it in the colour of the text around it.
NSImage *OMDSymbolicImageNamed(NSString *name);
// The same icon where it stands for a command (an image-only button or
// segment): what assistive technology (VoiceOver) says for it.
NSImage *OMDSymbolicImageNamedForCommand(NSString *name, NSString *commandName);
// A shortcut as written in tooltips: "Bold (Ctrl+B)" on GNUstep, with the
// Command key ("Bold (\u2318B)") on macOS.
NSString *OMDShortcutText(NSString *text);
