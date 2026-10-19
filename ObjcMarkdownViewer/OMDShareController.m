// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareController.h"
#import "OMDShareNotice.h"
#import "OMDRichPasteboard.h"
#import "OMDDocumentConverter.h"
#import "OMDViewerImages.h"
#import "OMDShareChecks.h"
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
    [_selectionCheckbox release];
    [_warningsView release];
    [_sheetWarnings release];
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

// What is shared: the selection when the share is of the selection only
// and the source has one, otherwise the whole document.
- (NSString *)sharedMarkdown
{
    if (_selectionOnly && [_source respondsToSelector:@selector(shareSelectedMarkdownText)]) {
        NSString *selected = [_source shareSelectedMarkdownText];
        if (selected != nil) {
            return selected;
        }
    }
    return [_source shareMarkdownText];
}

- (NSAttributedString *)sharedRenderedText
{
    if (_selectionOnly && [_source respondsToSelector:@selector(shareSelectedMarkdownText)] &&
        [_source respondsToSelector:@selector(shareRenderedTextForMarkdown:)]) {
        NSString *selected = [_source shareSelectedMarkdownText];
        if (selected != nil) {
            return [_source shareRenderedTextForMarkdown:selected];
        }
    }
    return [_source shareRenderedText];
}

// What a reader of a share in format would miss, for what is shared.
- (NSArray *)warningsForFormat:(OMDShareFormat)format
{
    NSString *markdown = [self sharedMarkdown];
    if (markdown == nil) {
        return [NSArray array];
    }
    return OMDShareWarningsForFormat(OMDShareWarnings(markdown, [_source shareResourceDirectory]), format);
}

- (OMDShareItem *)exportInFormat:(OMDShareFormat)format
{
    NSError *error = nil;
    OMDShareItem *item = [_exporter shareItemForFormat:format selectionOnly:_selectionOnly error:&error];
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
        NSAttributedString *rendered = [self sharedRenderedText];
        id text = rendered != nil ? (id)rendered : (id)[self sharedMarkdown];
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

// The sheet's own row above the services: the format switcher with a
// spinner at its right (shown while a format exports in the background),
// "Selection only" under it while there is a selection, and the warnings
// for the choice under that (-updateSheetAccessory lays them out).
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

        NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(controlFrame), 20.0)];
        [checkbox setButtonType:NSSwitchButton];
        [checkbox setTitle:@"Selection only"];
        [checkbox setTarget:self];
        [checkbox setAction:@selector(sheetSelectionOnlyChanged:)];
        [view addSubview:checkbox];

        NSView *warnings = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([view frame]), 0)];
        [view addSubview:warnings];

        _accessoryView = view;
        _spinner = spinner;
        _selectionCheckbox = checkbox;
        _warningsView = warnings;
    }
    return _accessoryView;
}

static NSTextField *OMDShareSheetLabel(NSString *text, CGFloat width)
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, width, 18.0)] autorelease];
    [label setStringValue:text];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setTextColor:[NSColor secondaryLabelColor]];
    [[label cell] setWraps:YES];
    NSSize size = [[label cell] cellSizeForBounds:NSMakeRect(0, 0, width, 1000.0)];
    [label setFrameSize:NSMakeSize(width, ceil(size.height))];
    return label;
}

static NSButton *OMDShareSheetButton(NSString *title, id target, SEL action)
{
    NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 24.0)] autorelease];
    [button setButtonType:NSMomentaryPushInButton];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTitle:title];
    [button setTarget:target];
    [button setAction:action];
    [button sizeToFit];
    [button setFrameSize:NSMakeSize(NSWidth([button frame]) + 12.0, 24.0)];
    return button;
}

// The format the warnings are checked for: the message is HTML.
static OMDShareFormat OMDShareFormatForSheetChoice(NSInteger choice)
{
    return choice == OMDShareEmailInMessageTag ? OMDShareFormatHTML : (OMDShareFormat)choice;
}

// Lays the warnings for choice out in warnings, bottom up (the view isn't
// flipped): what to do instead, then the warnings. Returns their height, 0
// for none.
- (CGFloat)layoutWarningsForChoice:(NSInteger)choice inView:(NSView *)warnings width:(CGFloat)width
{
    OMDShareFormat format = OMDShareFormatForSheetChoice(choice);
    // The document is checked once per sheet, not once per choice: each
    // check parses it, and a long document would make Share slow to open.
    if (_sheetWarnings == nil) {
        NSString *markdown = [self sharedMarkdown];
        _sheetWarnings = [(markdown != nil ? OMDShareWarnings(markdown, [_source shareResourceDirectory])
                                           : [NSArray array]) retain];
    }
    NSArray *found = OMDShareWarningsForFormat(_sheetWarnings, format);
    BOOL offerPDF = NO;
    BOOL offerBundle = NO;
    NSMutableArray *labels = [NSMutableArray array];
    NSEnumerator *e = [found objectEnumerator];
    OMDShareWarning *warning = nil;

    while ((warning = [e nextObject]) != nil) {
        // The .zip carries the local images.
        if (_sheetBundled && choice == _sheetChoice && [warning offersBundle]) {
            continue;
        }
        [labels addObject:OMDShareSheetLabel([warning messageForFormat:format], width)];
        offerPDF = offerPDF || ([warning suggestsPDF] && choice != OMDShareFormatPDF);
        offerBundle = offerBundle || ([warning offersBundle] && choice == OMDShareFormatMarkdown &&
                                      !_selectionOnly && !(_sheetBundled && choice == _sheetChoice));
    }

    [[[[warnings subviews] copy] autorelease] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSMutableArray *buttons = [NSMutableArray array];
    if (offerPDF) {
        [buttons addObject:OMDShareSheetButton(@"Share as PDF", self, @selector(sheetShareAsPDF:))];
    }
    if (offerBundle) {
        [buttons addObject:OMDShareSheetButton(@"Share as .zip with Images", self, @selector(sheetShareBundle:))];
    }

    CGFloat y = 0.0;
    if ([buttons count] > 0) {
        CGFloat x = 0.0;
        NSEnumerator *b = [buttons objectEnumerator];
        NSButton *button = nil;
        while ((button = [b nextObject]) != nil) {
            [button setFrameOrigin:NSMakePoint(x, 0.0)];
            [warnings addSubview:button];
            x += NSWidth([button frame]) + 8.0;
        }
        y = 24.0 + 6.0;
    }
    NSEnumerator *l = [labels reverseObjectEnumerator];
    NSTextField *label = nil;
    while ((label = [l nextObject]) != nil) {
        [label setFrameOrigin:NSMakePoint(0.0, y)];
        [warnings addSubview:label];
        y += NSHeight([label frame]) + 2.0;
    }
    return [labels count] > 0 ? y - 2.0 : 0.0;
}

// The height the warnings take for the tallest choice: the warnings area
// keeps it while the sheet shows, so the tiles under it don't move as the
// format is switched (#242).
- (CGFloat)tallestWarningsHeightInWidth:(CGFloat)width
{
    NSView *scratch = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, 0)] autorelease];
    CGFloat tallest = 0.0;
    NSUInteger index = 0;
    for (index = 0; index < sizeof(OMDShareSheetChoices) / sizeof(OMDShareSheetChoices[0]); index++) {
        tallest = MAX(tallest, [self layoutWarningsForChoice:OMDShareSheetChoices[index]
                                                      inView:scratch
                                                       width:width]);
    }
    return tallest;
}

// Lays out the accessory for the choice shown: the warnings that apply,
// what to do instead, and "Selection only" while there is a selection.
// Called before the picker's items change, which lays out the sheet again.
- (void)updateSheetAccessory
{
    NSView *view = [self sheetAccessoryView];
    NSView *warnings = (NSView *)_warningsView;
    NSButton *checkbox = (NSButton *)_selectionCheckbox;
    CGFloat width = NSWidth([view frame]);

    if (_warningsReserve < 0.0) {
        _warningsReserve = [self tallestWarningsHeightInWidth:width];
    }
    CGFloat warningsHeight = [self layoutWarningsForChoice:_sheetChoice inView:warnings width:width];
    // Kept at the top of the reserved height.
    if (warningsHeight < _warningsReserve) {
        CGFloat lift = _warningsReserve - warningsHeight;
        NSEnumerator *e = [[warnings subviews] objectEnumerator];
        NSView *subview = nil;
        while ((subview = [e nextObject]) != nil) {
            [subview setFrameOrigin:NSMakePoint(NSMinX([subview frame]), NSMinY([subview frame]) + lift)];
        }
        warningsHeight = _warningsReserve;
    }
    [warnings setFrame:NSMakeRect(0.0, 0.0, width, warningsHeight)];
    [warnings setHidden:(warningsHeight == 0.0)];

    BOOL hasSelection = [_exporter hasSelection];
    [checkbox setHidden:!hasSelection];
    [checkbox setState:(_selectionOnly ? NSOnState : NSOffState)];

    CGFloat height = (warningsHeight > 0.0 ? warningsHeight + 10.0 : 0.0)
                   + (hasSelection ? 20.0 + 6.0 : 0.0) + 24.0;
    [view setFrameSize:NSMakeSize(width, height)];
    CGFloat top = height;
    [[self formatControl] setFrameOrigin:NSMakePoint(0.0, top - 24.0)];
    [(NSView *)_spinner setFrameOrigin:NSMakePoint(NSWidth([[self formatControl] frame]) + 8.0, top - 20.0)];
    top -= 24.0;
    if (hasSelection) {
        top -= 6.0 + 20.0;
        [checkbox setFrameOrigin:NSMakePoint(0.0, top)];
    }
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
                    selectionOnly:_selectionOnly
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
    // Each sheet starts with the whole document.
    _selectionOnly = NO;
    _sheetBundled = NO;
    _warningsReserve = -1.0;
    [_sheetWarnings release];
    _sheetWarnings = nil;
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
    // Save a Copy opens in the document's folder, not the exports' temporary
    // one (libs-sharing#15).
    [(NSSharingServicePicker *)_picker setSaveDirectory:[_source shareResourceDirectory]];
    [self updateSheetAccessory];
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

// Shows choice in the sheet: exports it (Word and HTML in the background)
// and lays out the warnings for it. NO, with the switcher back on the
// choice shown, if it couldn't be made.
- (BOOL)switchSheetToChoice:(NSInteger)choice
{
    _sheetBundled = NO;
    if (choice != OMDShareEmailInMessageTag &&
        [OMDShareExporter formatNeedsConverter:(OMDShareFormat)choice]) {
        if ([_source documentConverter] == nil) {
            [self presentError:nil format:(OMDShareFormat)choice];
            [self selectSheetChoice:_sheetChoice];
            return NO;
        }
        _sheetChoice = choice;
        OMDShareSetLastSheetChoice(choice);
        [self selectSheetChoice:choice];
        [self updateSheetAccessory];
        [(NSSharingServicePicker *)_picker setItems:[self placeholderItemsForChoice:choice]];
        [self exportSheetChoiceInBackground:choice];
        return YES;
    }
    ++_exportGeneration;
    [self setSheetBusy:NO];
    NSArray *items = [self sheetItemsForChoice:choice];
    if (items == nil) {
        [self selectSheetChoice:_sheetChoice];
        return NO;
    }
    _sheetChoice = choice;
    OMDShareSetLastSheetChoice(choice);
    [self selectSheetChoice:choice];
    [self updateSheetAccessory];
    [(NSSharingServicePicker *)_picker setItems:items];
    return YES;
}

- (void)sheetFormatChanged:(id)sender
{
    NSInteger index = [(NSSegmentedControl *)sender selectedSegment];
    if (index < 0 || index >= 4) {
        return;
    }
    [self switchSheetToChoice:OMDShareSheetChoices[index]];
}

- (void)sheetSelectionOnlyChanged:(id)sender
{
    BOOL wanted = ([(NSButton *)sender state] == NSOnState);
    BOOL was = _selectionOnly;
    _selectionOnly = wanted;
    // The selection has its own warnings: check and measure again.
    _warningsReserve = -1.0;
    [_sheetWarnings release];
    _sheetWarnings = nil;
    if (![self switchSheetToChoice:_sheetChoice]) {
        _selectionOnly = was;
        [(NSButton *)sender setState:(was ? NSOnState : NSOffState)];
    }
}

- (void)sheetShareAsPDF:(id)sender
{
    (void)sender;
    [self switchSheetToChoice:OMDShareFormatPDF];
}

// The Markdown and its local images in a .zip (OMDShareExporter).
- (void)sheetShareBundle:(id)sender
{
    (void)sender;
    NSError *error = nil;
    OMDShareItem *item = [_exporter bundleShareItemWithError:&error];
    if (item == nil) {
        [self presentError:error format:OMDShareFormatMarkdown];
        return;
    }
    ++_exportGeneration;
    _sheetBundled = YES;
    [self updateSheetAccessory];
    [(NSSharingServicePicker *)_picker setItems:[NSArray arrayWithObject:[item fileURL]]];
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
                                         [self sharedMarkdown],
                                         [self sharedRenderedText]);
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
    _selectionOnly = NO;
    BOOL hasSelection = [_exporter hasSelection];
    NSArray *warnings = [self warningsForFormat:format];
    if (([warnings count] > 0 || hasSelection) &&
        [_presenter respondsToSelector:@selector(confirmShareWithWarnings:format:hasSelection:forWindow:completion:)]) {
        OMDShareController *controller = self;
        NSView *from = view;
        [_presenter confirmShareWithWarnings:warnings
                                      format:format
                                hasSelection:hasSelection
                                   forWindow:_window
                                  completion:^(OMDShareWarningChoice choice, BOOL selectionOnly) {
            [controller finishShareWithChoice:choice format:format selectionOnly:selectionOnly fromView:from];
        }];
        return;
    }
    [self finishShareWithChoice:OMDShareWarningChoiceContinue format:format selectionOnly:NO fromView:view];
}

// The share once the warnings are answered: the format, a PDF instead, or
// the Markdown with its images in a .zip.
- (void)finishShareWithChoice:(OMDShareWarningChoice)choice
                       format:(OMDShareFormat)format
                selectionOnly:(BOOL)selectionOnly
                     fromView:(NSView *)view
{
    if (choice == OMDShareWarningChoiceCancel) {
        return;
    }
    OMDShareItem *item = nil;
    _selectionOnly = selectionOnly;
    if (choice == OMDShareWarningChoiceBundle) {
        NSError *error = nil;
        item = [_exporter bundleShareItemWithError:&error];
        if (item == nil) {
            [self presentError:error format:OMDShareFormatMarkdown];
        }
    } else {
        item = [self exportInFormat:(choice == OMDShareWarningChoicePDF ? OMDShareFormatPDF : format)];
    }
    _selectionOnly = NO;
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
    NSString *markdown = [self sharedMarkdown];
    if (markdown == nil) {
        return;
    }
    NSString *title = [OMDShareExporter safeFileBaseName:[_source shareBaseName]];
    NSAttributedString *rendered = [self sharedRenderedText];
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
    if ([_presenter respondsToSelector:@selector(shareToolbarItemWithIdentifier:canShare:itemProvider:)]) {
        // __block: under manual retain counting a copied block doesn't
        // retain it, so the presenter keeping the block doesn't keep this
        // controller alive (it outlives every click on the item).
        __block OMDShareController *controller = self;
        __block id<OMDShareSource> source = _source;
        item = [_presenter shareToolbarItemWithIdentifier:identifier
                                                 canShare:^BOOL (void) {
            return [source shareSourceText] != nil;
        }
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
