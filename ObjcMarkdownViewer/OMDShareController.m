// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareController.h"
#import "OMDShareNotice.h"
#import "OMDRichPasteboard.h"
#import "OMDDocumentConverter.h"
#import "OMDViewerImages.h"
#if defined(GNUSTEP)
#import "GSSharing.h"
#endif

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
#if defined(GNUSTEP)
    [(NSSharingServicePicker *)_picker setDelegate:nil];
    [(NSSharingServicePicker *)_picker close];
    [_picker release];
    [_formatControl release];
    [_accessoryView release];
    [_spinner release];
#endif
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
    NSString *text = error != nil ? [error localizedDescription]
                                  : [OMDDocumentConverter missingBackendInstallMessage];
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

#if defined(GNUSTEP)
// Whether Share shows the library's sheet (no system share sheet here).
- (BOOL)usesShareSheet
{
    return !([_presenter respondsToSelector:@selector(presentsSystemShareSheet)] &&
             [_presenter presentsSystemShareSheet]);
}

static NSInteger OMDShareSheetChoices[] = {
    OMDShareFormatPDF, OMDShareFormatWord, OMDShareFormatMarkdown, OMDShareEmailInMessageTag
};

// What the sheet shares for a choice: the exported file, or for In the
// Message the rendered document. Nil (after an alert) if it couldn't be made.
- (NSArray *)sheetItemsForChoice:(NSInteger)choice
{
    if (choice == OMDShareEmailInMessageTag) {
        NSAttributedString *rendered = [_source shareRenderedText];
        id text = rendered != nil ? (id)rendered : (id)[_source shareMarkdownText];
        return text != nil ? [NSArray arrayWithObject:text] : nil;
    }
    OMDShareItem *item = [self exportInFormat:(OMDShareFormat)choice];
    return item != nil ? [NSArray arrayWithObject:[item fileURL]] : nil;
}

- (NSSegmentedControl *)formatControl
{
    if (_formatControl == nil) {
        NSArray *labels = [NSArray arrayWithObjects:@"PDF", @"Word", @"Markdown", @"In the Message", nil];
        NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)];
        NSUInteger index = 0;
        [control setSegmentCount:[labels count]];
        for (index = 0; index < [labels count]; index++) {
            [control setLabel:[labels objectAtIndex:index] forSegment:index];
            [control setWidth:(index == 3 ? 132.0 : 92.0) forSegment:index];
        }
        // Its frame fits the segments (GNUstep's -sizeToFit shrinks it to
        // nothing once the widths are set).
        [control setFrameSize:NSMakeSize(3 * 92.0 + 132.0 + 8.0, 24.0)];
        [control setTarget:self];
        [control setAction:@selector(sheetFormatChanged:)];
        _formatControl = control;
    }
    return _formatControl;
}

// The format switcher with a spinner at its right, shown while a format
// exports in the background.
- (NSView *)sheetAccessoryView
{
    if (_accessoryView == nil) {
        NSSegmentedControl *control = [self formatControl];
        NSRect controlFrame = [control frame];
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(controlFrame) + 28.0, 24.0)];
        NSProgressIndicator *spinner = [[NSProgressIndicator alloc]
                                           initWithFrame:NSMakeRect(NSWidth(controlFrame) + 8.0, 4.0, 16.0, 16.0)];
        [spinner setStyle:NSProgressIndicatorSpinningStyle];
        [spinner setDisplayedWhenStopped:NO];
        [control setFrameOrigin:NSZeroPoint];
        [view addSubview:control];
        [view addSubview:spinner];
        _accessoryView = view;
        _spinner = spinner;
    }
    return _accessoryView;
}

- (void)setSheetBusy:(BOOL)busy
{
    [(NSSharingServicePicker *)_picker setServicesEnabled:!busy];
    if (busy) {
        [(NSProgressIndicator *)_spinner startAnimation:nil];
    } else {
        [(NSProgressIndicator *)_spinner stopAnimation:nil];
    }
}

// Word and HTML export in the background: the sheet shows the file's name
// with its services off and the spinner going until the file is ready.
- (void)exportSheetChoiceInBackground:(NSInteger)choice
{
    NSUInteger generation = ++_exportGeneration;
    OMDShareController *controller = self;
    [self setSheetBusy:YES];
    [_exporter shareItemForFormat:(OMDShareFormat)choice
                       completion:^(OMDShareItem *item, NSError *error) {
        if (generation != controller->_exportGeneration || controller->_picker == nil) {
            return;
        }
        [controller setSheetBusy:NO];
        if (item == nil) {
            [controller presentError:error format:(OMDShareFormat)choice];
            return;
        }
        OMDShareSetLastFormat((OMDShareFormat)choice);
        [(NSSharingServicePicker *)controller->_picker setItems:[NSArray arrayWithObject:[item fileURL]]];
    }];
}

// What the sheet shows while choice exports: a file named after the
// document, not there yet.
- (NSArray *)placeholderItemsForChoice:(NSInteger)choice
{
    NSString *name = [[OMDShareExporter safeFileBaseName:[_source shareBaseName]]
                         stringByAppendingPathExtension:[OMDShareExporter fileExtensionForFormat:(OMDShareFormat)choice]];
    return [NSArray arrayWithObject:[NSURL fileURLWithPath:
        [[OMDShareExporter temporaryRootDirectory] stringByAppendingPathComponent:name]]];
}

- (void)selectSheetChoice:(NSInteger)choice
{
    NSUInteger index = 0;
    for (index = 0; index < sizeof(OMDShareSheetChoices) / sizeof(OMDShareSheetChoices[0]); index++) {
        if (OMDShareSheetChoices[index] == choice) {
            [[self formatControl] setSelectedSegment:index];
        }
    }
}

- (void)showShareSheetWithChoice:(NSInteger)choice fromView:(NSView *)view
{
    BOOL inBackground = (choice != OMDShareEmailInMessageTag &&
                         [OMDShareExporter formatNeedsConverter:(OMDShareFormat)choice]);
    if (inBackground && [_source documentConverter] == nil) {
        [self presentError:nil format:(OMDShareFormat)choice];
        inBackground = NO;
        choice = OMDShareFormatPDF;
    }
    NSArray *items = inBackground ? [self placeholderItemsForChoice:choice]
                                  : [self sheetItemsForChoice:choice];
    if (items == nil) {
        return;
    }
    _sheetChoice = choice;
    OMDShareSetLastSheetChoice(choice);
    [self selectSheetChoice:choice];
    [(NSSharingServicePicker *)_picker setDelegate:nil];
    [(NSSharingServicePicker *)_picker close];
    [_picker release];
    _picker = [[NSSharingServicePicker alloc] initWithItems:items];
    [(NSSharingServicePicker *)_picker setDelegate:self];
    [(NSSharingServicePicker *)_picker setAccessoryView:[self sheetAccessoryView]];
    NSRect rect;
    if (view == nil || view == [_window contentView]) {
        // From the toolbar or a menu: under the top right of the window.
        view = [_window contentView];
        NSRect bounds = [view bounds];
        rect = NSMakeRect(NSMaxX(bounds) - 560.0, NSMaxY(bounds) - 1.0, 1.0, 1.0);
    } else {
        rect = [view bounds];
    }
    [(NSSharingServicePicker *)_picker showRelativeToRect:rect ofView:view preferredEdge:NSMinYEdge];
    if (inBackground) {
        [self exportSheetChoiceInBackground:choice];
    } else {
        [self setSheetBusy:NO];
    }
}

- (void)sheetFormatChanged:(id)sender
{
    NSInteger index = [(NSSegmentedControl *)sender selectedSegment];
    if (index < 0 || index >= 4) {
        return;
    }
    NSInteger choice = OMDShareSheetChoices[index];
    if (choice != OMDShareEmailInMessageTag &&
        [OMDShareExporter formatNeedsConverter:(OMDShareFormat)choice]) {
        if ([_source documentConverter] == nil) {
            [self presentError:nil format:(OMDShareFormat)choice];
            [self selectSheetChoice:_sheetChoice];
            return;
        }
        _sheetChoice = choice;
        OMDShareSetLastSheetChoice(choice);
        [(NSSharingServicePicker *)_picker setItems:[self placeholderItemsForChoice:choice]];
        [self exportSheetChoiceInBackground:choice];
        return;
    }
    ++_exportGeneration;
    [self setSheetBusy:NO];
    NSArray *items = [self sheetItemsForChoice:choice];
    if (items == nil) {
        [self selectSheetChoice:_sheetChoice];
        return;
    }
    _sheetChoice = choice;
    OMDShareSetLastSheetChoice(choice);
    [(NSSharingServicePicker *)_picker setItems:items];
}

- (void)emailInMessageService:(NSArray *)items service:(id)service
{
    (void)items;
    (void)service;
    [self emailDocumentInMessage];
}

- (void)copyRenderedService:(NSArray *)items service:(id)service
{
    (void)items;
    (void)service;
    OMDWriteRenderedDocumentToPasteboard([NSPasteboard generalPasteboard],
                                         [_source shareMarkdownText],
                                         [_source shareRenderedText]);
}

- (void)sharingServicePicker:(NSSharingServicePicker *)picker
     didChooseSharingService:(NSSharingService *)service
{
    (void)picker;
    (void)service;
    // A background export finishing after the sheet closed is dropped.
    ++_exportGeneration;
}

// In the Message: the app's own Email (draft and paste) and Copy (the
// rendered document as HTML with inline styles, RTF and text), with the
// library's titles and images; files get the library's services as they are.
- (NSArray *)sharingServicePicker:(NSSharingServicePicker *)picker
          sharingServicesForItems:(NSArray *)items
          proposedSharingServices:(NSArray *)proposed
{
    (void)picker;
    (void)items;
    if (_sheetChoice != OMDShareEmailInMessageTag) {
        return proposed;
    }
    NSSharingService *email = [NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail];
    NSSharingService *copy = [NSSharingService sharingServiceNamed:GSSharingServiceNameCopy];
    NSSharingService *ours = [[[NSSharingService alloc] initWithTitle:@"Email"
                                                                image:[email image]
                                                       alternateImage:nil
                                                               target:self
                                                               action:@selector(emailInMessageService:service:)] autorelease];
    NSSharingService *copyRendered = [[[NSSharingService alloc] initWithTitle:@"Copy"
                                                                        image:[copy image]
                                                               alternateImage:nil
                                                                       target:self
                                                                       action:@selector(copyRenderedService:service:)] autorelease];
    return [NSArray arrayWithObjects:ours, copyRendered, nil];
}
#endif

- (void)shareInFormat:(OMDShareFormat)format fromView:(NSView *)view
{
#if defined(GNUSTEP)
    if ([self usesShareSheet]) {
        [self showShareSheetWithChoice:format fromView:view];
        return;
    }
#endif
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
    // The document as an HTML file too, for a mail app that takes its body
    // from a file (Thunderbird); nil if it couldn't be written.
    NSURL *htmlFile = nil;
    NSString *directory = [OMDShareExporter launchTemporaryDirectory];
    NSString *html = OMDClipboardHTMLFromMarkdown(markdown);
    if (directory != nil && html != nil) {
        NSString *path = [[directory stringByAppendingPathComponent:@"message"]
                             stringByAppendingPathComponent:[title stringByAppendingPathExtension:@"html"]];
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        // The fragment starts with its charset, which a body may hold.
        NSString *document = [NSString stringWithFormat:@"<!DOCTYPE html>\n<html><body>%@</body></html>\n", html];
        if ([document writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
            htmlFile = [NSURL fileURLWithPath:path];
        }
    }
    OMDShareItem *item = [[[OMDShareItem alloc] initWithTitle:title
                                                       format:OMDShareFormatHTML
                                                      fileURL:htmlFile
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
    if ([self usesShareSheet]) {
        // One sheet: the Share button opens it, in the last format.
        [self showShareSheetWithChoice:OMDShareSuggestedSheetChoice(OMDShareLastSheetChoice(),
                                                                    [[_source shareSourceText] length])
                              fromView:nil];
        return;
    }
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
