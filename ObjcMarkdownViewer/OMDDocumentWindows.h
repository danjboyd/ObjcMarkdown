// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDWindowController.h"
#import "OMDMarkdownDocument.h"

#if !defined(GNUSTEP)
// macOS: documents in the system's document architecture. Each document
// has its own window (the system groups them as tabs), is saved in place
// as it changes (autosave), and has Versions, Duplicate, Rename and Move
// To; the system notices changes made to its file by other apps. On
// GNUstep, documents stay the app's own tabs in a window.

// Posted (object: the document) after it saved, or read its file again.
extern NSString * const OMDMarkdownDocumentDidSaveNotification;
extern NSString * const OMDMarkdownDocumentDidRevertNotification;

// The shared document controller. Word, RTF, ODT and HTML files are
// imported as new Markdown documents; other files open as themselves.
@interface OMDDocumentController : NSDocumentController
@end

// Ties a window (an OMDWindowController's) to its document, so the system
// can title it, close it with the document and restore it.
@interface OMDDocumentWindowController : NSWindowController
{
    OMDWindowController *_contentController;
}
- (instancetype)initWithContentController:(OMDWindowController *)contentController;
- (OMDWindowController *)contentController;
@end

@interface OMDWindowController (OMDDocumentWindows)
// A new window for documents (shown, and kept until it closes).
+ (OMDWindowController *)documentWindowController;
// Called once the window exists: its NSWindowController, tabbing.
- (void)setUpDocumentWindow;
- (OMDDocumentWindowController *)documentWindowController;
// Whether this window shows a document of the document architecture.
- (BOOL)showsArchitectureDocument;
// Before document is shown: YES when it went to another window (a new
// tab, or because the document on show can't be put away); otherwise
// the document on show has been put away and document goes here.
- (BOOL)prepareToShowDocument:(OMDMarkdownDocument *)document inNewTab:(BOOL)inNewTab;
// After document is shown here: it joins the document architecture.
- (void)adoptShownDocument:(OMDMarkdownDocument *)document;
// The window of an open document of the file at path, brought to the
// front; NO when none is open.
- (BOOL)showOpenDocumentAtPath:(NSString *)path;
// A document the document controller opened: shown here.
- (void)showDocumentFromDocumentController:(OMDMarkdownDocument *)document;
// The window's close button: asks the document (which saves itself in
// place, or asks about an untitled one) and closes once it agrees.
- (BOOL)architectureDocumentWindowShouldClose;
// Reads the document's file again (it changed on disk), keeping the view.
- (void)revertArchitectureDocumentQuietly;
@end
#endif
