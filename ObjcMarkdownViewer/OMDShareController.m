// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareController.h"
#import "OMDShareNotice.h"
#import "OMDRichPasteboard.h"
#import "OMDViewerImages.h"

@implementation OMDShareController

+ (OMDShareFormat)lastFormat
{
    return OMDShareLastFormat();
}

- (instancetype)initWithSource:(id<OMDShareSource>)source window:(NSWindow *)window
{
    self = [super init];
    if (self != nil) {
        _source = source;
        _window = window;
        _exporter = [[OMDShareExporter alloc] initWithSource:source];
        _presenter = OMDCreatePlatformSharePresenter();
    }
    return self;
}

- (void)dealloc
{
    [OMDShareNotice dismissNoticeForWindow:_window];
    [_exporter release];
    [_presenter release];
    [_toolbarMenu release];
    [super dealloc];
}

- (id<OMDSharePresenter>)presenter
{
    return _presenter;
}

- (void)presentError:(NSError *)error format:(OMDShareFormat)format
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:@"Couldn't share as %@",
                                                     [OMDShareExporter displayNameForFormat:format]]];
    NSString *text = [error localizedDescription];
    NSString *reason = [[error userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
    if ([reason length] > 0) {
        text = [NSString stringWithFormat:@"%@\n\n%@", text, reason];
    }
    [alert setInformativeText:(text != nil ? text : @"The file could not be created.")];
    [alert runModal];
}

- (OMDShareItem *)exportInFormat:(OMDShareFormat)format
{
    NSError *error = nil;
    OMDShareItem *item = [_exporter shareItemForFormat:format error:&error];
    if (item == nil) {
        [self presentError:error format:format];
        return nil;
    }
    OMDShareSetLastFormat(format);
    return item;
}

- (void)shareInFormat:(OMDShareFormat)format fromView:(NSView *)view
{
    OMDShareItem *item = [self exportInFormat:format];
    if (item == nil) {
        return;
    }
    [_presenter presentShareItem:item fromView:(view != nil ? view : [_window contentView])];
}

- (void)emailDocumentInFormat:(OMDShareFormat)format
{
    OMDShareItem *item = [self exportInFormat:format];
    if (item != nil) {
        OMDShareSetLastEmailChoice(format);
        [_presenter emailShareItem:item forWindow:_window];
    }
}

- (void)emailDocumentInMessage
{
    NSString *markdown = [_source shareMarkdownText];
    if (markdown == nil) {
        return;
    }
    NSString *title = [OMDShareExporter safeFileBaseName:[_source shareBaseName]];
    NSAttributedString *rendered = [_source shareRenderedText];
    OMDShareItem *item = [[[OMDShareItem alloc] initWithTitle:title
                                                       format:OMDShareFormatHTML
                                                      fileURL:nil
                                                 renderedText:rendered] autorelease];
    OMDShareSetLastEmailChoice(OMDShareEmailInMessageTag);
    // A mail app that takes the body itself (Mail on macOS).
    if ([_presenter respondsToSelector:@selector(emailRenderedDocument:forWindow:)] &&
        [_presenter emailRenderedDocument:item forWindow:_window]) {
        return;
    }
    // Everywhere else a draft link carries only plain text, so the rendered
    // document goes on the clipboard (as Copy Rendered puts it) and is
    // pasted into the draft.
    OMDWriteRenderedDocumentToPasteboard([NSPasteboard generalPasteboard], markdown, rendered);
    BOOL opened = [_presenter openEmailDraftWithSubject:title];
    NSString *message = opened
        ? @"The document is on the clipboard: paste it into the message."
        : @"No email app opened. The document is on the clipboard, ready to paste into a message.";
    [OMDShareNotice showMessage:message
                         detail:OMDShortcutText(@"Paste with Ctrl+V; its formatting comes with it.")
                      forWindow:_window];
}

- (void)showDocumentFileInFolder:(NSString *)path
{
    if ([path length] == 0) {
        return;
    }
    NSString *title = [[path lastPathComponent] stringByDeletingPathExtension];
    OMDShareItem *item = [[[OMDShareItem alloc] initWithTitle:title
                                                       format:OMDShareFormatMarkdown
                                                      fileURL:[NSURL fileURLWithPath:path]
                                                 renderedText:nil] autorelease];
    [_presenter showShareItemInFolder:item];
}

- (NSMenu *)toolbarMenuWithTarget:(id)target
{
    if (_toolbarMenu == nil) {
        _toolbarMenu = [[NSMenu alloc] initWithTitle:@"Share"];
        OMDAddShareMenuItems(_toolbarMenu, target);
    }
    return _toolbarMenu;
}

#if defined(GNUSTEP)
- (void)toolbarItemClicked:(id)sender
{
    (void)sender;
    NSEvent *event = [NSApp currentEvent];
    NSView *view = [_window contentView];
    if (event == nil || view == nil) {
        return;
    }
    [NSMenu popUpContextMenu:_toolbarMenu withEvent:event forView:view];
}
#endif

- (NSToolbarItem *)toolbarItemWithIdentifier:(NSString *)identifier target:(id)target
{
    NSToolbarItem *item = nil;
    if ([_presenter respondsToSelector:@selector(shareToolbarItemWithIdentifier:itemProvider:)]) {
        // __block: under manual retain counting a copied block doesn't
        // retain it, so the presenter keeping the block doesn't keep this
        // controller alive (it outlives every click on the item).
        __block OMDShareController *controller = self;
        item = [_presenter shareToolbarItemWithIdentifier:identifier
                                             itemProvider:^OMDShareItem *(void) {
            return [controller exportInFormat:[OMDShareController lastFormat]];
        }];
    }
    if (item == nil) {
        NSMenu *menu = [self toolbarMenuWithTarget:target];
#if defined(GNUSTEP)
        // The item pops up the Share menu itself: GNUstep's toolbar has no
        // menu item that a theme draws.
        item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        [item setTarget:self];
        [item setAction:@selector(toolbarItemClicked:)];
        (void)menu;
#else
        NSMenuToolbarItem *menuItem = [[[NSMenuToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        [menuItem setMenu:menu];
        [menuItem setShowsIndicator:NO];
        item = menuItem;
#endif
        [item setImage:OMDSymbolicImageNamedForCommand(@"omd-share-symbolic", @"Share")];
    }
    [item setLabel:@"Share"];
    [item setPaletteLabel:@"Share"];
    [item setToolTip:@"Share this document"];
    return item;
}

@end
