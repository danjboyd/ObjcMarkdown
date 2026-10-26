// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// Reopening the documents that were open when the app last quit, on the
// first launch of another version (#266). An in-app update quits the app
// and the old version's updater starts the new one with no documents (the
// Windows MSI, the Linux AppImage, Sparkle on macOS), so the app keeps the
// list itself. A launch of the same version reopens nothing.

// The defaults key the record is kept under.
extern NSString * const OMDRelaunchReopenDefaultsKey;

// The record to keep at quit: the version quitting, the local files open
// (in order) and the one selected. Nil when no file is open.
NSDictionary *OMDRelaunchReopenRecordMake(NSString *version, NSArray *paths, NSString *selectedPath);

// The files to open at launch, in order, from a record kept at quit: none
// unless the record is from another version than currentVersion. Each
// path once, only files that exist; the selected one comes last, again if
// it was open before another (opening an open file only shows it).
NSArray *OMDRelaunchReopenPathsForLaunch(NSDictionary *record,
                                         NSString *currentVersion,
                                         BOOL (^fileExists)(NSString *path));
