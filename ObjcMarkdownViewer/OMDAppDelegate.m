// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDAppDelegate.h"
#import "OMMarkdownRenderer.h"

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
    _zoomScale = 1.0;
    [self setupToolbar];

    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:[[_window contentView] bounds]] autorelease];
    [scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [scrollView setHasVerticalScroller:YES];

    _textView = [[NSTextView alloc] initWithFrame:[[scrollView contentView] bounds]];
    [_textView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_textView setEditable:NO];
    [_textView setSelectable:YES];
    [_textView setRichText:YES];

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
            [_zoomSlider setDoubleValue:100];
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
    [self updateZoomLabel];
    [self renderCurrentMarkdown];
}

- (void)zoomReset:(id)sender
{
    _zoomScale = 1.0;
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
    NSAttributedString *rendered = [_renderer attributedStringFromMarkdown:_currentMarkdown];
    [[_textView textStorage] setAttributedString:rendered];
    NSColor *bg = [_renderer backgroundColor];
    if (bg != nil) {
        [_textView setDrawsBackground:YES];
        [_textView setBackgroundColor:bg];
    }
    if (_currentPath != nil) {
        [_window setTitle:[_currentPath lastPathComponent]];
    }
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
