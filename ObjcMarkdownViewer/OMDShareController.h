// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDShareExporter.h"
#import "OMDSharePresenter.h"
#import "OMDShareMenu.h"

// Share for one window: exports the document (OMDShareExporter) and hands
// it to the platform's presenter. It remembers the last format used, which
// Email and the macOS toolbar item use.
@interface OMDShareController : NSObject
{
    id<OMDShareSource> _source;
    NSWindow *_window;
    OMDShareExporter *_exporter;
    id<OMDSharePresenter> _presenter;
    NSMenu *_toolbarMenu;
    // GNUstep: the share sheet showing (an NSSharingServicePicker), its
    // format switcher, and the choice it shows (a format, or
    // OMDShareEmailInMessageTag for the document as a message).
    id _picker;
    id _formatControl;
    id _accessoryView;      // the format switcher and a spinner, then the rows below
    id _spinner;
    id _selectionCheckbox;  // "Selection only", shown while there is a selection
    id _warningsView;       // the warnings for the choice, and what to do instead
    NSInteger _sheetChoice;
    // Whether the share is of the selection only (#192).
    BOOL _selectionOnly;
    // Whether the sheet shows the Markdown's .zip with its images.
    BOOL _sheetBundled;
    // The warnings area's height while the sheet shows: the tallest any
    // choice needs, so the tiles don't move (#242); < 0 to measure again.
    CGFloat _warningsReserve;
    // What the sheet's document would miss, found once per sheet (every
    // choice's warnings come from it); nil to find again.
    NSArray *_sheetWarnings;
    // Each background export's number: a result for an earlier one (the
    // format was switched again, or the sheet closed) is dropped.
    NSUInteger _exportGeneration;
}

// The source and window are not retained.
- (instancetype)initWithSource:(id<OMDShareSource>)source window:(NSWindow *)window;

- (id<OMDSharePresenter>)presenter;

// The format last shared in (PDF until something is shared).
+ (OMDShareFormat)lastFormat;

// Exports in format and presents the file from view (the window's content
// view if nil). Errors are shown in an alert. What the reader would miss
// (OMDShareChecks.h) is shown first: in the sheet on GNUstep, through the
// presenter's -confirmShareWithWarnings:... elsewhere.
- (void)shareInFormat:(OMDShareFormat)format fromView:(NSView *)view;
// An email draft with the document attached in format.
- (void)emailDocumentInFormat:(OMDShareFormat)format;
// An email draft with the rendered document as its body: filled in where
// the presenter can (emailRenderedDocument:forWindow:), otherwise put on the
// clipboard to paste into the draft, with a notice saying so.
- (void)emailDocumentInMessage;
// The document's own file in the file manager.
- (void)showDocumentFileInFolder:(NSString *)path;

// The toolbar's Share item: the presenter's own, or one that pops up the
// Share menu with actions to target.
- (NSToolbarItem *)toolbarItemWithIdentifier:(NSString *)identifier target:(id)target;

@end
