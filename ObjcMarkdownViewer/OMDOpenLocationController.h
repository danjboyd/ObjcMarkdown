// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDRemoteDocument;

@protocol OMDOpenLocationDelegate <NSObject>
// Fetches and opens the document, then calls completion with nil, or with
// a message saying why it couldn't.
- (void)openRemoteDocument:(OMDRemoteDocument *)document
                completion:(void (^)(NSString *errorMessage))completion;
@end

// File > Open Location...: a panel taking the address of a Markdown file on
// the web, which says inside it what went wrong instead of an alert.
@interface OMDOpenLocationController : NSObject <NSTextFieldDelegate>
{
    id<OMDOpenLocationDelegate> _delegate;
    NSPanel *_panel;
    NSTextField *_addressField;
    NSTextField *_statusLabel;
    NSButton *_openButton;
    BOOL _opening;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDOpenLocationDelegate>)delegate;
// Shows the panel over the window, its address selected.
- (void)showOverWindow:(NSWindow *)window;
// Fills in an address and says what went wrong opening it.
- (void)showAddress:(NSString *)address message:(NSString *)message;

@end
