// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRemoteDocumentBar.h"
#import "OMDRemoteDocument.h"

static const CGFloat OMDRemoteBarPadding = 8.0;
static const CGFloat OMDRemoteBarGap = 6.0;

@interface OMDRemoteDocumentBar ()
- (void)layoutBar;
@end

@implementation OMDRemoteDocumentBar

+ (CGFloat)heightForControlHeight:(CGFloat)controlHeight
{
    return controlHeight + 2.0 * OMDRemoteBarPadding;
}

- (instancetype)initWithFrame:(NSRect)frame
                       target:(id)target
               saveCopyAction:(SEL)saveCopyAction
          openInBrowserAction:(SEL)openInBrowserAction
{
    self = [super initWithFrame:frame];
    if (self != nil) {
        _label = [[NSTextField alloc] initWithFrame:NSZeroRect];
        [_label setBezeled:NO];
        [_label setEditable:NO];
        [_label setSelectable:YES];
        [_label setDrawsBackground:NO];
        [_label setTextColor:[NSColor secondaryLabelColor]];
        [[_label cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
        [self addSubview:_label];

        _saveButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        [_saveButton setTitle:@"Save a Copy..."];
        [_saveButton setBezelStyle:NSRoundedBezelStyle];
        [_saveButton setTarget:target];
        [_saveButton setAction:saveCopyAction];
        [_saveButton setToolTip:@"Save this document as a local Markdown file you can edit"];
        [self addSubview:_saveButton];

        _browserButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        [_browserButton setBezelStyle:NSRoundedBezelStyle];
        [_browserButton setTarget:target];
        [_browserButton setAction:openInBrowserAction];
        [self addSubview:_browserButton];

        _separator = [[NSBox alloc] initWithFrame:NSZeroRect];
        [_separator setBoxType:NSBoxSeparator];
        [self addSubview:_separator];
        [self setAutoresizesSubviews:NO];
    }
    return self;
}

- (void)dealloc
{
    [_label release];
    [_saveButton release];
    [_browserButton release];
    [_separator release];
    [_document release];
    [super dealloc];
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    [self layoutBar];
}

- (void)layoutBar
{
    NSRect bounds = [self bounds];
    CGFloat height = NSHeight(bounds) - 2.0 * OMDRemoteBarPadding;
    [_browserButton sizeToFit];
    [_saveButton sizeToFit];
    CGFloat browserWidth = MAX(NSWidth([_browserButton frame]), 96.0);
    CGFloat saveWidth = MAX(NSWidth([_saveButton frame]), 96.0);
    CGFloat x = NSMaxX(bounds) - OMDRemoteBarPadding - browserWidth;
    [_browserButton setFrame:NSMakeRect(x, OMDRemoteBarPadding, browserWidth, height)];
    x -= OMDRemoteBarGap + saveWidth;
    [_saveButton setFrame:NSMakeRect(x, OMDRemoteBarPadding, saveWidth, height)];
    CGFloat labelHeight = 18.0;
    [_label setFrame:NSMakeRect(OMDRemoteBarPadding,
                                floor(NSMidY(bounds) - labelHeight / 2.0),
                                MAX(1.0, x - OMDRemoteBarGap - OMDRemoteBarPadding),
                                labelHeight)];
    [_separator setFrame:NSMakeRect(0.0, 0.0, NSWidth(bounds), 1.0)];
}

- (void)setDocument:(OMDRemoteDocument *)document
{
    if (document != _document) {
        [_document release];
        _document = [document retain];
    }
    [_browserButton setTitle:([document isOnGitHub] ? @"Open on GitHub" : @"Open in Browser")];
    [_browserButton setToolTip:[[document pageURL] absoluteString]];
    [self setMessage:nil];
    [self layoutBar];
}

- (OMDRemoteDocument *)document
{
    return _document;
}

- (void)setMessage:(NSString *)message
{
    NSString *text = message;
    if (text == nil) {
        text = (_document != nil ? [NSString stringWithFormat:@"%@ · %@ · read-only",
                                                              [_document summary], [_document fileName]]
                                 : @"");
    }
    [_label setStringValue:text];
    [_label setToolTip:[[_document rawURL] absoluteString]];
}

@end
