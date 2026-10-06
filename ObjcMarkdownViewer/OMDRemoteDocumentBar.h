// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDRemoteDocument;

// The line above a document opened from the web: where it is from, that it
// is read-only (or what went wrong following a link), and buttons to save a
// copy or open it in the browser. Standard controls only; it draws nothing
// itself.
@interface OMDRemoteDocumentBar : NSView
{
    NSTextField *_label;
    NSButton *_saveButton;
    NSButton *_browserButton;
    NSBox *_separator;
    OMDRemoteDocument *_document;
}

// The bar's height for the layout density's control height.
+ (CGFloat)heightForControlHeight:(CGFloat)controlHeight;

// The buttons send saveCopyAction and openInBrowserAction to target.
- (instancetype)initWithFrame:(NSRect)frame
                       target:(id)target
               saveCopyAction:(SEL)saveCopyAction
          openInBrowserAction:(SEL)openInBrowserAction;
- (void)setDocument:(OMDRemoteDocument *)document;
- (OMDRemoteDocument *)document;
// A message in place of the usual "read-only" (nil restores it).
- (void)setMessage:(NSString *)message;

@end
