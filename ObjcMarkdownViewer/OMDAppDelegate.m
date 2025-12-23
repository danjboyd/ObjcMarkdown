// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDAppDelegate.h"
#import "OMMarkdownRenderer.h"
#import "OMDTextView.h"

#include <math.h>

@implementation OMDAppDelegate

- (void)dealloc
{
    [_currentMarkdown release];
    [_currentPath release];
    [_zoomSlider release];
    [_zoomLabel release];
    [_zoomResetButton release];
    [_zoomContainer release];
    [_codeBlockButtons release];
    [_renderer release];
    [_textView release];
    [_window release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self setupMainMenu];
    [self setupWindow];
    BOOL openedFromArgs = [self openDocumentFromArguments];
    if (!_openedFileOnLaunch && !openedFromArgs) {
        [self openDocument:self];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    _openedFileOnLaunch = YES;
    [self openDocumentAtPath:filename];
    return YES;
}

- (void)setupMainMenu
{
    NSMenu *menubar = [[[NSMenu alloc] init] autorelease];
    NSMenuItem *appMenuItem = [[[NSMenuItem alloc] initWithTitle:@""
                                                          action:NULL
                                                   keyEquivalent:@""] autorelease];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];

    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"ObjcMarkdownViewer"] autorelease];
    [appMenu addItemWithTitle:@"Quit ObjcMarkdownViewer"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];

    NSMenuItem *fileMenuItem = [[[NSMenuItem alloc] initWithTitle:@"File"
                                                           action:NULL
                                                    keyEquivalent:@""] autorelease];
    [menubar addItem:fileMenuItem];

    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    NSMenuItem *openItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Open..."
                                                             action:@selector(openDocument:)
                                                      keyEquivalent:@"o"];
    [openItem setTarget:self];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close"
                        action:@selector(performClose:)
                 keyEquivalent:@"w"];

    [fileMenuItem setSubmenu:fileMenu];
}

- (void)setupWindow
{
    NSRect frame = NSMakeRect(100, 100, 900, 700);
    _window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [_window setFrameAutosaveName:@"ObjcMarkdownViewerMainWindow"];
    [_window setTitle:@"ObjcMarkdownViewer"];
    [_window setDelegate:self];
    _zoomScale = 1.0;
    NSNumber *savedZoom = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownZoomScale"];
    if (savedZoom != nil) {
        double value = [savedZoom doubleValue];
        if (value > 0.25 && value < 4.0) {
            _zoomScale = value;
        }
    }
    [self setupToolbar];

    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:[[_window contentView] bounds]] autorelease];
    [scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [scrollView setHasVerticalScroller:YES];

    _textView = [[OMDTextView alloc] initWithFrame:[[scrollView contentView] bounds]];
    [_textView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_textView setEditable:NO];
    [_textView setSelectable:YES];
    [_textView setRichText:YES];
    [_textView setTextContainerInset:NSMakeSize(20.0, 16.0)];
    [[_textView textContainer] setLineFragmentPadding:0.0];
    [_textView setDelegate:self];

    [_textView setLinkTextAttributes:@{
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.03 green:0.41 blue:0.85 alpha:1.0],
        NSUnderlineStyleAttributeName: [NSNumber numberWithInt:NSUnderlineStyleSingle]
    }];

    [scrollView setDocumentView:_textView];
    [[_window contentView] addSubview:scrollView];

    [_window makeKeyAndOrderFront:nil];

    _renderer = [[OMMarkdownRenderer alloc] init];
    [_renderer setZoomScale:_zoomScale];
}

- (void)setupToolbar
{
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:@"ObjcMarkdownViewerToolbar"] autorelease];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
    [_window setToolbar:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
      itemForItemIdentifier:(NSString *)identifier
  willBeInsertedIntoToolbar:(BOOL)flag
{
    if ([identifier isEqualToString:@"ZoomControls"]) {
        if (_zoomContainer == nil) {
            _zoomContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 26)];

            _zoomLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 3, 55, 20)];
            [_zoomLabel setBezeled:NO];
            [_zoomLabel setEditable:NO];
            [_zoomLabel setSelectable:NO];
            [_zoomLabel setDrawsBackground:NO];
            [_zoomLabel setAlignment:NSRightTextAlignment];

            _zoomSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(60, 2, 160, 22)];
            [_zoomSlider setMinValue:50];
            [_zoomSlider setMaxValue:200];
            [_zoomSlider setDoubleValue:_zoomScale * 100.0];
            [_zoomSlider setTarget:self];
            [_zoomSlider setAction:@selector(zoomSliderChanged:)];

            _zoomResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(225, 2, 55, 22)];
            [_zoomResetButton setTitle:@"Reset"];
            [_zoomResetButton setBezelStyle:NSRoundedBezelStyle];
            [_zoomResetButton setTarget:self];
            [_zoomResetButton setAction:@selector(zoomReset:)];

            [_zoomContainer addSubview:_zoomLabel];
            [_zoomContainer addSubview:_zoomSlider];
            [_zoomContainer addSubview:_zoomResetButton];
            [self updateZoomLabel];
        }

        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ZoomControls"] autorelease];
        [item setView:_zoomContainer];
        [item setMinSize:NSMakeSize(280, 26)];
        [item setMaxSize:NSMakeSize(280, 26)];
        return item;
    }

    return nil;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObject:@"ZoomControls"];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObject:@"ZoomControls"];
}

- (void)updateZoomLabel
{
    if (_zoomLabel == nil) {
        return;
    }
    NSInteger percent = (NSInteger)lrint(_zoomScale * 100.0);
    [_zoomLabel setStringValue:[NSString stringWithFormat:@"%ld%%", (long)percent]];
}

- (void)zoomSliderChanged:(id)sender
{
    _zoomScale = [_zoomSlider doubleValue] / 100.0;
    [[NSUserDefaults standardUserDefaults] setDouble:_zoomScale forKey:@"ObjcMarkdownZoomScale"];
    [self updateZoomLabel];
    [self renderCurrentMarkdown];
}

- (void)zoomReset:(id)sender
{
    _zoomScale = 1.0;
    [[NSUserDefaults standardUserDefaults] setDouble:_zoomScale forKey:@"ObjcMarkdownZoomScale"];
    [_zoomSlider setDoubleValue:100.0];
    [self updateZoomLabel];
    [self renderCurrentMarkdown];
}

- (void)openDocument:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];

    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }

    NSArray *filenames = [panel filenames];
    if ([filenames count] == 0) {
        return;
    }

    [self openDocumentAtPath:[filenames objectAtIndex:0]];
}

- (void)renderCurrentMarkdown
{
    if (_currentMarkdown == nil) {
        return;
    }
    [_renderer setZoomScale:_zoomScale];
    [self updateRendererLayoutWidth];
    NSAttributedString *rendered = [_renderer attributedStringFromMarkdown:_currentMarkdown];
    [[_textView textStorage] setAttributedString:rendered];
    [self updateCodeBlockButtons];
    if ([_textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *codeView = (OMDTextView *)_textView;
        [codeView setCodeBlockRanges:[_renderer codeBlockRanges]];
        [codeView setCodeBlockBackgroundColor:[NSColor colorWithCalibratedWhite:0.97 alpha:1.0]];
        [codeView setCodeBlockPadding:NSMakeSize(14.0, 8.0)];
        [codeView setBlockquoteRanges:[_renderer blockquoteRanges]];
        [codeView setBlockquoteLineColor:[NSColor colorWithCalibratedWhite:0.82 alpha:1.0]];
        [codeView setBlockquoteLineWidth:3.0];
        [codeView setNeedsDisplay:YES];
    }
    NSColor *bg = [_renderer backgroundColor];
    if (bg != nil) {
        [_textView setDrawsBackground:YES];
        [_textView setBackgroundColor:bg];
    }
    if (_currentPath != nil) {
        [_window setTitle:[_currentPath lastPathComponent]];
    }
}

- (void)updateRendererLayoutWidth
{
    NSRect bounds = [_textView bounds];
    NSSize inset = [_textView textContainerInset];
    CGFloat padding = [[_textView textContainer] lineFragmentPadding];
    CGFloat width = bounds.size.width - (inset.width * 2.0) - (padding * 2.0);
    if (width < 0.0) {
        width = 0.0;
    }
    [_renderer setLayoutWidth:width];
}

- (void)windowDidResize:(NSNotification *)notification
{
    if (_currentMarkdown == nil) {
        return;
    }
    [self renderCurrentMarkdown];
}

- (void)updateCodeBlockButtons
{
    if (_codeBlockButtons == nil) {
        _codeBlockButtons = [[NSMutableArray alloc] init];
    }
    for (NSButton *button in _codeBlockButtons) {
        [button removeFromSuperview];
    }
    [_codeBlockButtons removeAllObjects];

    NSArray *ranges = [_renderer codeBlockRanges];
    if ([ranges count] == 0) {
        return;
    }

    NSLayoutManager *layoutManager = [_textView layoutManager];
    NSTextContainer *container = [_textView textContainer];
    if (layoutManager == nil || container == nil) {
        return;
    }
    [layoutManager ensureLayoutForTextContainer:container];

    NSInteger index = 0;
    for (NSValue *value in ranges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            index++;
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        if (glyphRange.length == 0) {
            continue;
        }

        NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];
        NSRect lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphRange.location effectiveRange:NULL];

        CGFloat buttonWidth = 48.0;
        CGFloat buttonHeight = 18.0;
        CGFloat x = blockRect.origin.x + blockRect.size.width - buttonWidth - 6.0;
        if (x < blockRect.origin.x) {
            x = blockRect.origin.x;
        }
        CGFloat y = lineRect.origin.y + 2.0;

        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, buttonWidth, buttonHeight)];
        [button setTitle:@"Copy"];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setFont:[NSFont systemFontOfSize:11.0]];
        [button setTarget:self];
        [button setAction:@selector(copyCodeBlock:)];
        [button setTag:index];
        [_textView addSubview:button];
        [_codeBlockButtons addObject:button];
        [button release];
        index++;
    }
}

- (void)copyCodeBlock:(id)sender
{
    NSInteger index = [sender tag];
    NSArray *ranges = [_renderer codeBlockRanges];
    if (index < 0 || index >= (NSInteger)[ranges count]) {
        return;
    }
    NSRange range = [[ranges objectAtIndex:index] rangeValue];
    NSString *fullText = [[_textView textStorage] string];
    if (fullText == nil || NSMaxRange(range) > [fullText length]) {
        return;
    }

    NSString *snippet = [fullText substringWithRange:range];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pasteboard setString:snippet forType:NSStringPboardType];
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link
{
    NSURL *url = nil;
    if ([link isKindOfClass:[NSURL class]]) {
        url = (NSURL *)link;
    } else if ([link isKindOfClass:[NSString class]]) {
        NSString *linkString = (NSString *)link;
        url = [NSURL URLWithString:linkString];
        if (url == nil) {
            url = [NSURL fileURLWithPath:linkString];
        }
    }

    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return YES;
    }

    return NO;
}

- (BOOL)openDocumentFromArguments
{
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    if ([args count] <= 1) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger i = 1;
    for (; i < [args count]; i++) {
        NSString *candidate = [args objectAtIndex:i];
        NSString *expanded = [candidate stringByExpandingTildeInPath];
        if (![expanded isAbsolutePath]) {
            NSString *cwd = [fm currentDirectoryPath];
            expanded = [cwd stringByAppendingPathComponent:expanded];
        }
        if ([fm fileExistsAtPath:expanded]) {
            _openedFileOnLaunch = YES;
            [self openDocumentAtPath:expanded];
            return YES;
        }
    }

    return NO;
}

- (void)openDocumentAtPath:(NSString *)path
{
    if (path == nil) {
        return;
    }

    NSString *resolvedPath = [path stringByExpandingTildeInPath];
    if (![resolvedPath isAbsolutePath]) {
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        resolvedPath = [cwd stringByAppendingPathComponent:resolvedPath];
    }

    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfFile:resolvedPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (markdown == nil) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Unable to open file"];
        [alert setInformativeText:[error localizedDescription]];
        [alert runModal];
        return;
    }

    [_currentMarkdown release];
    _currentMarkdown = [markdown retain];
    [_currentPath release];
    _currentPath = [resolvedPath retain];
    [self renderCurrentMarkdown];
}

@end
