// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDShareExporter.h"
#import "OMDSharePresenter.h"

// The Share items, the same in File > Share and the toolbar's menu: each
// "Share as" item has its format as its tag and the action shareDocument:;
// then the Email as submenu (emailDocument:, tagged by format the same
// way), copyRenderedDocument: and showDocumentInFolder:.
// The target is not retained (nil sends them along the responder chain).
void OMDAddShareMenuItems(NSMenu *menu, id target);

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
}

// The source and window are not retained.
- (instancetype)initWithSource:(id<OMDShareSource>)source window:(NSWindow *)window;

- (id<OMDSharePresenter>)presenter;

// The format last shared in (PDF until something is shared).
+ (OMDShareFormat)lastFormat;

// Exports in format and presents the file from view (the window's content
// view if nil). Errors are shown in an alert.
- (void)shareInFormat:(OMDShareFormat)format fromView:(NSView *)view;
// An email draft with the document attached in format.
- (void)emailDocumentInFormat:(OMDShareFormat)format;
// The document's own file in the file manager.
- (void)showDocumentFileInFolder:(NSString *)path;

// The toolbar's Share item: the presenter's own, or one that pops up the
// Share menu with actions to target.
- (NSToolbarItem *)toolbarItemWithIdentifier:(NSString *)identifier target:(id)target;

@end
