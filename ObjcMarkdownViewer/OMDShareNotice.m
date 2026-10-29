// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareNotice.h"
#import "OMDViewerImages.h"

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
                      forWindow:(NSWindow *)window
                         picker:(BOOL)picker
                         detail:(NSString *)detail;
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
                                                            forWindow:window
                                                               picker:NO
                                                               detail:nil] autorelease];
    [OMDShareNotices() setObject:notice forKey:OMDShareNoticeKey(window)];
    [notice show];
}

+ (void)showPickerForShareItem:(OMDShareItem *)item
                     presenter:(id<OMDSharePresenter>)presenter
                     forWindow:(NSWindow *)window
{
    [self dismissNoticeForWindow:window];
    NSString *message = [NSString stringWithFormat:@"\u201C%@\u201D is ready to share.", [item fileName]];
    OMDShareNotice *notice = [[[OMDShareNotice alloc] initWithMessage:message
                                                            shareItem:item
                                                            presenter:presenter
                                                            forWindow:window
                                                               picker:YES
                                                               detail:nil] autorelease];
    [OMDShareNotices() setObject:notice forKey:OMDShareNoticeKey(window)];
    [notice show];
}

+ (void)showMessage:(NSString *)message
            detail:(NSString *)detail
         forWindow:(NSWindow *)window
{
    [self dismissNoticeForWindow:window];
    OMDShareNotice *notice = [[[OMDShareNotice alloc] initWithMessage:message
                                                            shareItem:nil
                                                            presenter:nil
                                                            forWindow:window
                                                               picker:NO
                                                               detail:detail] autorelease];
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
                         picker:(BOOL)picker
                         detail:(NSString *)detail
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _window = window;
    _item = [item retain];
    _presenter = [presenter retain];

    CGFloat width = picker ? 600.0 : 440.0;
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

    // The file, when there is one: dragged into a mail or a chat.
    BOOL hasFile = ([item fileURL] != nil);
    if (hasFile) {
        OMDShareFileDragView *icon = [[[OMDShareFileDragView alloc] initWithFrame:
            NSMakeRect(margin, height - margin - iconSize, iconSize, iconSize)] autorelease];
#if defined(GNUSTEP) && !defined(_WIN32)
        // Icon themes no longer carry coloured file icons, and GNUstep's own
        // is a question mark: the app's page.
        NSImage *fileIcon = OMDSymbolicImageNamed(@"omd-share-file-symbolic");
#else
        NSImage *fileIcon = [[NSWorkspace sharedWorkspace] iconForFile:[[item fileURL] path]];
#endif
        [icon setImage:fileIcon];
        [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
        [icon setEditable:NO];
        [icon setFileURL:[item fileURL]];
        [icon setToolTip:@"Drag the file into an email or a chat"];
        [content addSubview:icon];
    }

    CGFloat textX = hasFile ? margin + iconSize + 12.0 : margin;
    CGFloat textWidth = width - textX - margin;
    [content addSubview:OMDShareNoticeLabel(message,
                                            NSMakeRect(textX, height - margin - 36.0, textWidth, 36.0),
                                            [NSFont systemFontOfSize:0.0],
                                            [NSColor labelColor])];
    if (detail == nil) {
        // Show in Folder selects a temporary copy unless it is the document as saved (#265).
        detail = (hasFile && [item documentURL] == nil)
            ? @"A temporary copy: drag it into an email or a chat, or copy it."
            : @"Drag it into an email or a chat, or copy it.";
    }
    [content addSubview:OMDShareNoticeLabel(detail,
                                            NSMakeRect(textX, height - margin - 70.0, textWidth, 32.0),
                                            [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
                                            [NSColor secondaryLabelColor])];

    // The buttons, right to left: Close, Copy File, Show in Folder, and in
    // the picker Save a Copy... and Email... (the default).
    CGFloat buttonHeight = 28.0;
    CGFloat buttonY = margin - 4.0;
    CGFloat x = width - margin;
    NSArray *titles = [NSArray arrayWithObjects:@"Close", @"Copy File", @"Show in Folder", @"Save a Copy...", @"Email...", nil];
    CGFloat widths[] = { 80.0, 100.0, 130.0, 120.0, 90.0 };
    SEL actions[] = { @selector(closeClicked:), @selector(copyFileClicked:), @selector(showInFolderClicked:),
                      @selector(saveCopyClicked:), @selector(emailClicked:) };
    NSUInteger count = picker ? 5 : (hasFile ? 3 : 1);
    NSUInteger index = 0;
    for (index = 0; index < count; index++) {
        x -= widths[index];
        NSButton *button = OMDShareNoticeButton([titles objectAtIndex:index],
                                                NSMakeRect(x, buttonY, widths[index], buttonHeight),
                                                self, actions[index]);
        if (index == 0) {
            [button setKeyEquivalent:@"\e"];
        } else if (picker && index == 4) {
            [button setKeyEquivalent:@"\r"];
        }
        [content addSubview:button];
        x -= 8.0;
    }

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

- (void)emailClicked:(id)sender
{
    (void)sender;
    // Email may put up a notice of its own, which replaces this one.
    [[_item retain] autorelease];
    [[_presenter retain] autorelease];
    OMDShareItem *item = _item;
    id<OMDSharePresenter> presenter = _presenter;
    NSWindow *window = _window;
    [self close];
    [presenter emailShareItem:item forWindow:window];
}

- (void)saveCopyClicked:(id)sender
{
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:@"Save a Copy"];
    [panel setNameFieldStringValue:[_item fileName]];
    [panel setCanCreateDirectories:YES];
    [panel setDirectory:NSHomeDirectory()];
    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }
    NSString *destination = [[panel URL] path];
    if ([destination length] == 0) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    // The panel has asked about replacing it.
    [manager removeItemAtPath:destination error:NULL];
    NSError *error = nil;
    if (![manager copyItemAtPath:[[_item fileURL] path] toPath:destination error:&error]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Couldn't save a copy"];
        [alert setInformativeText:(error != nil ? [error localizedDescription] : destination)];
        [alert runModal];
        return;
    }
    [self close];
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
