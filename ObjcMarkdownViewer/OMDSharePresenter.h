// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDShareItem.h"

// What to do about the warnings before a share (OMDShareChecks.h, #190).
typedef NS_ENUM(NSInteger, OMDShareWarningChoice) {
    OMDShareWarningChoiceCancel = 0,
    OMDShareWarningChoiceContinue,
    OMDShareWarningChoicePDF,      // share as PDF instead
    OMDShareWarningChoiceBundle    // share the Markdown as a .zip with its images
};

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
// canShare says cheaply whether there is a document to share; the provider
// exports it in the last-used format, only when a share asks for the file
// (never when the toolbar is built or validated: #236). Without this method
// the share controller makes its own item, which pops up the Share menu.
- (NSToolbarItem *)shareToolbarItemWithIdentifier:(NSString *)identifier
                                         canShare:(BOOL (^)(void))canShare
                                     itemProvider:(OMDShareItem *(^)(void))provider;
// Asked before a share in format that has warnings (OMDShareWarning, those
// that apply to format) or while the document has a selection, where the
// share controller has no sheet of its own to show them in (macOS, the
// Windows share UI). Offer PDF if any warning -suggestsPDF, Bundle if
// format is Markdown and any -offersBundle, and "Selection only" if
// hasSelection. Calls completion once, on the main thread. Without this
// method the share goes ahead, for the whole document.
- (void)confirmShareWithWarnings:(NSArray *)warnings
                          format:(OMDShareFormat)format
                    hasSelection:(BOOL)hasSelection
                       forWindow:(NSWindow *)window
                      completion:(void (^)(OMDShareWarningChoice choice, BOOL selectionOnly))completion;
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
