// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDShareItem.h"

// Hands an exported document to the platform: its share sheet, its email
// client, its file manager, its clipboard (docs/share-design.md). Each
// platform has its own file: OMDSharePresenterMac.m, ...Windows.m and
// ...Linux.m.
@protocol OMDSharePresenter <NSObject>
// Offers the file to the platform's destinations (its share sheet, or our
// picker), from a view in the document's window.
- (void)presentShareItem:(OMDShareItem *)item fromView:(NSView *)view;
// A draft in the default email client with the file attached, or as close
// to that as the client allows (then the notice offers the file).
- (void)emailShareItem:(OMDShareItem *)item forWindow:(NSWindow *)window;
// Opens the file manager with the file selected.
- (void)showShareItemInFolder:(OMDShareItem *)item;
// Puts the file on the clipboard, so pasting attaches it.
- (void)copyFileOfShareItem:(OMDShareItem *)item;
// Opens a draft in the default email client with this subject and nothing
// else; NO if none opened.
- (BOOL)openEmailDraftWithSubject:(NSString *)subject;
@optional
// Whether -presentShareItem:fromView: shows the system's own share sheet
// (macOS; Windows where its share UI is supported). Without it, or NO, the
// share controller shows the library's sheet (libs-sharing) on GNUstep,
// with the format switcher.
- (BOOL)presentsSystemShareSheet;
// A draft whose body is the rendered document (item's renderedText; it has
// no file), where the mail app takes a body (macOS: Mail). NO to have the
// share controller put the document on the clipboard to paste instead.
- (BOOL)emailRenderedDocument:(OMDShareItem *)item forWindow:(NSWindow *)window;
// The platform's own toolbar item (macOS: NSSharingServicePickerToolbarItem).
// The provider exports in the last-used format when the item needs it.
// Without this method the share controller makes its own item, which pops
// up the Share menu.
- (NSToolbarItem *)shareToolbarItemWithIdentifier:(NSString *)identifier
                                     itemProvider:(OMDShareItem *(^)(void))provider;
@end

// What every platform can do with AppKit alone: a notice for present and
// email (which also opens a mailto: draft), NSWorkspace for Show in Folder,
// the pasteboard for Copy File. Platform presenters subclass it.
@interface OMDShareBasicPresenter : NSObject <OMDSharePresenter>
// A mailto: draft with the document's title as the subject, and the notice
// offering the file to attach: what email falls back to when the client
// can't take an attachment.
- (void)emailShareItemWithMailtoDraft:(OMDShareItem *)item forWindow:(NSWindow *)window;
@end

// The presenter of this platform, retained by the caller.
id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void);
