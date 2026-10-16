// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareNotice.h"

// The shared file's icon, which drags the file into a mail or a chat.
#if defined(GNUSTEP)
@interface OMDShareFileDragView : NSImageView
#else
@interface OMDShareFileDragView : NSImageView <NSDraggingSource>
#endif
{
    NSURL *_fileURL;
}
- (void)setFileURL:(NSURL *)fileURL;
@end

@implementation OMDShareFileDragView

- (void)dealloc
{
    [_fileURL release];
    [super dealloc];
}

- (void)setFileURL:(NSURL *)fileURL
{
    [_fileURL release];
    _fileURL = [fileURL copy];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent *)event
{
    if (_fileURL == nil) {
        return;
    }
#if defined(GNUSTEP)
    [self dragFile:[_fileURL path] fromRect:[self bounds] slideBack:YES event:event];
#else
    NSDraggingItem *item = [[[NSDraggingItem alloc] initWithPasteboardWriter:_fileURL] autorelease];
    [item setDraggingFrame:[self bounds] contents:[self image]];
    [self beginDraggingSessionWithItems:[NSArray arrayWithObject:item] event:event source:self];
#endif
}

#if defined(GNUSTEP)
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    (void)isLocal;
    return NSDragOperationCopy;
}
#else
- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    (void)session;
    (void)context;
    return NSDragOperationCopy;
}
#endif

@end

// Escape closes the notice.
@interface OMDShareNoticePanel : NSPanel
@end

@implementation OMDShareNoticePanel

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)cancelOperation:(id)sender
{
    (void)sender;
    [self performClose:nil];
}

@end

@interface OMDShareNotice () <NSWindowDelegate>
{
    NSPanel *_panel;
    NSWindow *_window;
    OMDShareItem *_item;
    id<OMDSharePresenter> _presenter;
}
- (instancetype)initWithMessage:(NSString *)message
                      shareItem:(OMDShareItem *)item
                      presenter:(id<OMDSharePresenter>)presenter
                      forWindow:(NSWindow *)window;
- (void)show;
- (void)close;
@end

// The notice of each window, keyed by the window's address.
static NSMutableDictionary *OMDShareNotices(void)
{
    static NSMutableDictionary *notices = nil;
    if (notices == nil) {
        notices = [[NSMutableDictionary alloc] init];
    }
    return notices;
}

static NSValue *OMDShareNoticeKey(NSWindow *window)
{
    return [NSValue valueWithPointer:window];
}

static NSTextField *OMDShareNoticeLabel(NSString *text, NSRect frame, NSFont *font, NSColor *color)
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setStringValue:text];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setFont:font];
    [label setTextColor:color];
    [[label cell] setWraps:YES];
    return label;
}

static NSButton *OMDShareNoticeButton(NSString *title, NSRect frame, id target, SEL action)
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:target];
    [button setAction:action];
    return button;
}

@implementation OMDShareNotice

+ (void)showNoticeWithMessage:(NSString *)message
                    shareItem:(OMDShareItem *)item
                    presenter:(id<OMDSharePresenter>)presenter
                    forWindow:(NSWindow *)window
{
    [self dismissNoticeForWindow:window];
    OMDShareNotice *notice = [[[OMDShareNotice alloc] initWithMessage:message
                                                            shareItem:item
                                                            presenter:presenter
                                                            forWindow:window] autorelease];
    [OMDShareNotices() setObject:notice forKey:OMDShareNoticeKey(window)];
    [notice show];
}

+ (void)dismissNoticeForWindow:(NSWindow *)window
{
    OMDShareNotice *notice = [OMDShareNotices() objectForKey:OMDShareNoticeKey(window)];
    [notice close];
}

- (instancetype)initWithMessage:(NSString *)message
                      shareItem:(OMDShareItem *)item
                      presenter:(id<OMDSharePresenter>)presenter
                      forWindow:(NSWindow *)window
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _window = window;
    _item = [item retain];
    _presenter = [presenter retain];

    CGFloat width = 440.0;
    CGFloat height = 140.0;
    CGFloat margin = 16.0;
    CGFloat iconSize = 48.0;
    _panel = [[OMDShareNoticePanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, width, height)
                                                    styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSUtilityWindowMask)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    [_panel setTitle:@"Share"];
    [_panel setReleasedWhenClosed:NO];
    [_panel setHidesOnDeactivate:NO];
    [_panel setDelegate:self];
    NSView *content = [_panel contentView];

    OMDShareFileDragView *icon = [[[OMDShareFileDragView alloc] initWithFrame:
        NSMakeRect(margin, height - margin - iconSize, iconSize, iconSize)] autorelease];
    NSImage *fileIcon = [[NSWorkspace sharedWorkspace] iconForFile:[[item fileURL] path]];
    [icon setImage:fileIcon];
    [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
    [icon setEditable:NO];
    [icon setFileURL:[item fileURL]];
    [icon setToolTip:@"Drag the file into an email or a chat"];
    [content addSubview:icon];

    CGFloat textX = margin + iconSize + 12.0;
    CGFloat textWidth = width - textX - margin;
    [content addSubview:OMDShareNoticeLabel(message,
                                            NSMakeRect(textX, height - margin - 36.0, textWidth, 36.0),
                                            [NSFont systemFontOfSize:0.0],
                                            [NSColor labelColor])];
    [content addSubview:OMDShareNoticeLabel(@"Drag it into an email or a chat, or copy it.",
                                            NSMakeRect(textX, height - margin - 70.0, textWidth, 32.0),
                                            [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
                                            [NSColor secondaryLabelColor])];

    CGFloat buttonHeight = 28.0;
    CGFloat buttonY = margin - 4.0;
    NSButton *close = OMDShareNoticeButton(@"Close", NSMakeRect(width - margin - 80.0, buttonY, 80.0, buttonHeight),
                                           self, @selector(closeClicked:));
    [close setKeyEquivalent:@"\e"];
    NSButton *copy = OMDShareNoticeButton(@"Copy File", NSMakeRect(width - margin - 80.0 - 8.0 - 100.0, buttonY, 100.0, buttonHeight),
                                          self, @selector(copyFileClicked:));
    NSButton *show = OMDShareNoticeButton(@"Show in Folder", NSMakeRect(width - margin - 80.0 - 8.0 - 100.0 - 8.0 - 130.0, buttonY, 130.0, buttonHeight),
                                          self, @selector(showInFolderClicked:));
    [content addSubview:show];
    [content addSubview:copy];
    [content addSubview:close];

    if (window != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(documentWindowWillClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:window];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_panel setDelegate:nil];
    [_panel release];
    [_item release];
    [_presenter release];
    [super dealloc];
}

- (void)show
{
    NSRect frame = [_panel frame];
    if (_window != nil) {
        NSRect parent = [_window frame];
        frame.origin.x = floor(NSMidX(parent) - frame.size.width / 2.0);
        frame.origin.y = floor(NSMaxY(parent) - frame.size.height - 96.0);
        [_panel setFrameOrigin:frame.origin];
    } else {
        [_panel center];
    }
    [_panel makeKeyAndOrderFront:nil];
}

- (void)close
{
    [_panel close];
}

- (void)copyFileClicked:(id)sender
{
    (void)sender;
    [_presenter copyFileOfShareItem:_item];
}

- (void)showInFolderClicked:(id)sender
{
    (void)sender;
    [_presenter showShareItemInFolder:_item];
}

- (void)closeClicked:(id)sender
{
    (void)sender;
    [self close];
}

- (void)documentWindowWillClose:(NSNotification *)notification
{
    (void)notification;
    [self close];
}

- (void)windowWillClose:(NSNotification *)notification
{
    if ([notification object] != _panel) {
        return;
    }
    // The last reference: the notice goes once its panel has closed.
    [[self retain] autorelease];
    [OMDShareNotices() removeObjectForKey:OMDShareNoticeKey(_window)];
}

@end
