// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDOpenLocationController.h"
#import "OMDRemoteDocument.h"

static const CGFloat OMDOpenLocationWidth = 520.0;
static const CGFloat OMDOpenLocationHeight = 168.0;

@interface OMDOpenLocationController ()
- (void)buildPanel;
- (void)openLocation:(id)sender;
- (void)cancel:(id)sender;
- (void)setStatus:(NSString *)status;
@end

@implementation OMDOpenLocationController

- (instancetype)initWithDelegate:(id<OMDOpenLocationDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [_addressField setDelegate:nil];
    [_panel release];
    [_addressField release];
    [_statusLabel release];
    [_openButton release];
    [super dealloc];
}

- (void)buildPanel
{
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, OMDOpenLocationWidth, OMDOpenLocationHeight)
                                        styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                          backing:NSBackingStoreBuffered
                                            defer:YES];
    [_panel setTitle:@"Open Location"];
    [_panel setReleasedWhenClosed:NO];
    NSView *content = [_panel contentView];
    CGFloat pad = 16.0;
    CGFloat width = OMDOpenLocationWidth - 2.0 * pad;

    NSTextField *prompt = [[[NSTextField alloc] initWithFrame:NSMakeRect(pad, OMDOpenLocationHeight - pad - 18.0, width, 18.0)] autorelease];
    [prompt setBezeled:NO];
    [prompt setEditable:NO];
    [prompt setSelectable:NO];
    [prompt setDrawsBackground:NO];
    [prompt setStringValue:@"The address of a Markdown file on GitHub or the web:"];
    [content addSubview:prompt];

    _addressField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, NSMinY([prompt frame]) - 8.0 - 26.0, width, 26.0)];
    [[_addressField cell] setPlaceholderString:@"https://github.com/owner/repo/blob/main/README.md"];
    [[_addressField cell] setScrollable:YES];
    [_addressField setDelegate:self];
    [content addSubview:_addressField];

    // Two lines, for the longer messages.
    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, NSMinY([_addressField frame]) - 6.0 - 36.0, width, 36.0)];
    [_statusLabel setBezeled:NO];
    [_statusLabel setEditable:NO];
    // Not selectable: GNUstep scrolls a selectable field's text instead of
    // wrapping it.
    [_statusLabel setSelectable:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [[_statusLabel cell] setWraps:YES];
    [content addSubview:_statusLabel];

    _openButton = [[NSButton alloc] initWithFrame:NSMakeRect(OMDOpenLocationWidth - pad - 96.0, pad, 96.0, 28.0)];
    [_openButton setTitle:@"Open"];
    [_openButton setBezelStyle:NSRoundedBezelStyle];
    [_openButton setKeyEquivalent:@"\r"];
    [_openButton setTarget:self];
    [_openButton setAction:@selector(openLocation:)];
    [content addSubview:_openButton];

    NSButton *cancelButton = [[[NSButton alloc] initWithFrame:NSMakeRect(NSMinX([_openButton frame]) - 8.0 - 96.0, pad, 96.0, 28.0)] autorelease];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setBezelStyle:NSRoundedBezelStyle];
    [cancelButton setKeyEquivalent:@"\e"];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancel:)];
    [content addSubview:cancelButton];
}

- (void)showOverWindow:(NSWindow *)window
{
    if (_panel == nil) {
        [self buildPanel];
    }
    if (!_opening) {
        [self setStatus:nil];
    }
    if (window != nil) {
        NSRect parent = [window frame];
        NSRect frame = [_panel frame];
        frame.origin.x = NSMidX(parent) - NSWidth(frame) / 2.0;
        frame.origin.y = NSMaxY(parent) - NSHeight(frame) - 120.0;
        [_panel setFrame:frame display:NO];
    }
    [_panel makeKeyAndOrderFront:nil];
    [_panel makeFirstResponder:_addressField];
    [_addressField selectText:nil];
}

- (void)showAddress:(NSString *)address message:(NSString *)message
{
    if (_panel == nil) {
        [self buildPanel];
    }
    [_addressField setStringValue:(address != nil ? address : @"")];
    [self setStatus:message];
}

- (void)setStatus:(NSString *)status
{
    [_statusLabel setStringValue:(status != nil ? status : @"")];
}

- (void)openLocation:(id)sender
{
    (void)sender;
    if (_opening) {
        return;
    }
    OMDRemoteDocument *document = [OMDRemoteDocument documentWithURLString:[_addressField stringValue]];
    if (document == nil) {
        [self setStatus:@"That isn't the address of a Markdown file (.md) on GitHub or the web."];
        return;
    }
    _opening = YES;
    [_openButton setEnabled:NO];
    [self setStatus:[NSString stringWithFormat:@"Opening %@...", [document fileName]]];
    [self retain];
    [_delegate openRemoteDocument:document completion:^(NSString *errorMessage) {
        _opening = NO;
        [_openButton setEnabled:YES];
        if (errorMessage != nil) {
            [self setStatus:errorMessage];
        } else {
            [self setStatus:nil];
            [_panel orderOut:nil];
        }
        [self release];
    }];
}

- (void)cancel:(id)sender
{
    (void)sender;
    [_panel orderOut:nil];
}

@end
