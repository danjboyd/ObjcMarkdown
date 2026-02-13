// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDAppDelegate.h"
#import "OMMarkdownRenderer.h"
#import "OMDTextView.h"
#import "OMDSourceTextView.h"
#import "OMDLineNumberRulerView.h"
#import "OMDDocumentConverter.h"
#import <AppKit/NSInterfaceStyle.h>
#import <GNUstepGUI/GSTheme.h>

#include <math.h>

typedef NS_ENUM(NSInteger, OMDViewerMode) {
    OMDViewerModeRead = 0,
    OMDViewerModeEdit = 1,
    OMDViewerModeSplit = 2
};

static const CGFloat OMDPrintExportZoomScale = 0.8;
static const NSTimeInterval OMDInteractiveRenderDebounceInterval = 0.15;
static const NSTimeInterval OMDMathArtifactRefreshDebounceInterval = 0.10;
static const NSTimeInterval OMDLivePreviewDebounceInterval = 0.12;
static const CGFloat OMDSourceEditorDefaultFontSize = 13.0;
static const CGFloat OMDSourceEditorMinFontSize = 9.0;
static const CGFloat OMDSourceEditorMaxFontSize = 32.0;
static NSString * const OMDSourceEditorFontNameDefaultsKey = @"ObjcMarkdownSourceEditorFontName";
static NSString * const OMDSourceEditorFontSizeDefaultsKey = @"ObjcMarkdownSourceEditorFontSize";

static NSTimeInterval OMDNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

static BOOL OMDTruthyFlagValue(NSString *value)
{
    if (value == nil) {
        return NO;
    }
    NSString *lower = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [lower isEqualToString:@"1"] ||
           [lower isEqualToString:@"true"] ||
           [lower isEqualToString:@"yes"] ||
           [lower isEqualToString:@"on"];
}

static BOOL OMDPerformanceLoggingEnabled(void)
{
    static BOOL resolved = NO;
    static BOOL enabled = NO;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_PERF_LOG"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_PERF_LOG"];
        }
        if (flag != nil && [flag length] > 0) {
            enabled = OMDTruthyFlagValue(flag);
        } else {
            enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownPerfLog"];
        }
        resolved = YES;
    }
    return enabled;
}

static OMDViewerMode OMDViewerModeFromInteger(NSInteger value)
{
    if (value == OMDViewerModeEdit) {
        return OMDViewerModeEdit;
    }
    if (value == OMDViewerModeSplit) {
        return OMDViewerModeSplit;
    }
    return OMDViewerModeRead;
}

static NSString *OMDViewerModeTitle(OMDViewerMode mode)
{
    if (mode == OMDViewerModeEdit) {
        return @"Edit";
    }
    if (mode == OMDViewerModeSplit) {
        return @"Split";
    }
    return @"Read";
}

@interface OMDAppDelegate ()
- (void)importDocument:(id)sender;
- (void)saveDocumentAsMarkdown:(id)sender;
- (void)printDocument:(id)sender;
- (void)exportDocumentAsPDF:(id)sender;
- (void)exportDocumentAsRTF:(id)sender;
- (void)exportDocumentAsDOCX:(id)sender;
- (void)exportDocumentAsODT:(id)sender;
- (BOOL)hasLoadedDocument;
- (BOOL)ensureDocumentLoadedForActionName:(NSString *)actionName;
- (BOOL)ensureConverterAvailableForActionName:(NSString *)actionName;
- (OMDDocumentConverter *)documentConverter;
- (BOOL)importDocumentAtPath:(NSString *)path;
- (void)presentConverterError:(NSError *)error fallbackTitle:(NSString *)title;
- (void)setCurrentMarkdown:(NSString *)markdown sourcePath:(NSString *)sourcePath;
- (NSString *)defaultSaveMarkdownFileName;
- (NSString *)defaultExportFileNameWithExtension:(NSString *)extension;
- (NSString *)defaultExportPDFFileName;
- (void)exportDocumentWithTitle:(NSString *)panelTitle
                      extension:(NSString *)extension
                     actionName:(NSString *)actionName;
- (NSPrintInfo *)configuredPrintInfo;
- (CGFloat)printableContentWidthForPrintInfo:(NSPrintInfo *)printInfo;
- (OMDTextView *)newPrintTextViewForPrintInfo:(NSPrintInfo *)printInfo;
- (void)requestInteractiveRender;
- (void)scheduleInteractiveRenderAfterDelay:(NSTimeInterval)delay;
- (void)interactiveRenderTimerFired:(NSTimer *)timer;
- (void)cancelPendingInteractiveRender;
- (void)mathArtifactsDidWarm:(NSNotification *)notification;
- (void)scheduleMathArtifactRefresh;
- (void)mathArtifactRenderTimerFired:(NSTimer *)timer;
- (void)cancelPendingMathArtifactRender;
- (void)modeControlChanged:(id)sender;
- (void)setReadMode:(id)sender;
- (void)setEditMode:(id)sender;
- (void)setSplitMode:(id)sender;
- (void)setViewerMode:(OMDViewerMode)mode persistPreference:(BOOL)persistPreference;
- (void)applyViewerModeLayout;
- (void)layoutDocumentViews;
- (void)updateModeControlSelection;
- (void)synchronizeSourceEditorWithCurrentMarkdown;
- (void)scheduleLivePreviewRender;
- (void)livePreviewRenderTimerFired:(NSTimer *)timer;
- (void)cancelPendingLivePreviewRender;
- (void)applySplitViewRatio;
- (void)persistSplitViewRatio;
- (BOOL)isPreviewVisible;
- (void)updateWindowTitle;
- (NSColor *)modeLabelTextColor;
- (void)applySourceEditorFontFromDefaults;
- (void)setSourceEditorFont:(NSFont *)font persistPreference:(BOOL)persistPreference;
- (void)increaseSourceEditorFontSize:(id)sender;
- (void)decreaseSourceEditorFontSize:(id)sender;
- (void)resetSourceEditorFontSize:(id)sender;
- (void)chooseSourceEditorFont:(id)sender;
@end

@implementation OMDAppDelegate

static NSMutableArray *OMDSecondaryWindows(void)
{
    static NSMutableArray *windows = nil;
    if (windows == nil) {
        windows = [[NSMutableArray alloc] init];
    }
    return windows;
}

- (void)registerAsSecondaryWindow
{
    if (_isSecondaryWindow) {
        return;
    }
    _isSecondaryWindow = YES;
    [OMDSecondaryWindows() addObject:self];
}

- (void)unregisterAsSecondaryWindow
{
    if (!_isSecondaryWindow) {
        return;
    }
    [OMDSecondaryWindows() removeObject:self];
    _isSecondaryWindow = NO;
}

- (void)dealloc
{
    [self unregisterAsSecondaryWindow];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:OMMarkdownRendererMathArtifactsDidWarmNotification
                                                  object:nil];
    [self cancelPendingInteractiveRender];
    [self cancelPendingMathArtifactRender];
    [self cancelPendingLivePreviewRender];
    [_currentMarkdown release];
    [_currentPath release];
    [_zoomSlider release];
    [_zoomLabel release];
    [_zoomResetButton release];
    [_zoomContainer release];
    [_modeLabel release];
    [_modeControl release];
    [_modeContainer release];
    [_codeBlockButtons release];
    [_documentConverter release];
    [_sourceLineNumberRuler release];
    [_splitView release];
    [_renderer release];
    [_sourceTextView release];
    [_sourceScrollView release];
    [_previewScrollView release];
    [_documentContainer release];
    [_textView release];
    [_window release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self setupWindow];
    BOOL openedFromArgs = [self openDocumentFromArguments];
    if (!_openedFileOnLaunch && !openedFromArgs) {
        [self openDocument:self];
    }
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [self setupMainMenu];
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
    NSMenu *menubar = [[[NSMenu alloc] initWithTitle:@"GSMainMenu"] autorelease];
    [NSApp setMainMenu:menubar];

    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);

    NSMenuItem *appMenuItem = nil;
    NSMenu *appMenu = nil;

    if (style == NSWindows95InterfaceStyle && [menubar numberOfItems] > 0) {
        appMenuItem = (NSMenuItem *)[menubar itemAtIndex:0];
        appMenu = [appMenuItem submenu];
        if (appMenu == nil) {
            appMenu = [[[NSMenu alloc] initWithTitle:appName] autorelease];
            [menubar setSubmenu:appMenu forItem:appMenuItem];
        }
    } else {
        appMenuItem = [[[NSMenuItem alloc] initWithTitle:appName
                                                  action:NULL
                                           keyEquivalent:@""] autorelease];
        appMenu = [[[NSMenu alloc] initWithTitle:appName] autorelease];
        [menubar addItem:appMenuItem];
        [menubar setSubmenu:appMenu forItem:appMenuItem];
    }

    NSString *aboutTitle = [NSString stringWithFormat:@"About %@", appName];
    NSMenuItem *aboutItem = [[[NSMenuItem alloc] initWithTitle:aboutTitle
                                                         action:@selector(orderFrontStandardAboutPanel:)
                                                  keyEquivalent:@""] autorelease];
    [aboutItem setTarget:NSApp];
    [appMenu addItem:aboutItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSString *quitTitle = [NSString stringWithFormat:@"Quit %@", appName];
    NSMenuItem *quitItem = (NSMenuItem *)[appMenu addItemWithTitle:quitTitle
                                                             action:@selector(terminate:)
                                                      keyEquivalent:@"q"];
    [quitItem setTarget:NSApp];

    NSMenuItem *fileMenuItem = [[[NSMenuItem alloc] initWithTitle:@"File"
                                                           action:NULL
                                                    keyEquivalent:@""] autorelease];
    [menubar addItem:fileMenuItem];

    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    NSMenuItem *openItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Open Markdown..."
                                                             action:@selector(openDocument:)
                                                      keyEquivalent:@"o"];
    [openItem setTarget:self];

    NSMenuItem *importItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Import..."
                                                                action:@selector(importDocument:)
                                                         keyEquivalent:@"I"];
    [importItem setTarget:self];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *saveAsItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Save Markdown As..."
                                                                action:@selector(saveDocumentAsMarkdown:)
                                                         keyEquivalent:@"S"];
    [saveAsItem setTarget:self];

    NSMenuItem *exportMenuItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Export"
                                                                    action:NULL
                                                             keyEquivalent:@""];
    NSMenu *exportMenu = [[[NSMenu alloc] initWithTitle:@"Export"] autorelease];
    NSMenuItem *exportPDFItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as PDF..."
                                                                     action:@selector(exportDocumentAsPDF:)
                                                              keyEquivalent:@""];
    [exportPDFItem setTarget:self];
    NSMenuItem *exportRTFItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as RTF..."
                                                                     action:@selector(exportDocumentAsRTF:)
                                                              keyEquivalent:@""];
    [exportRTFItem setTarget:self];
    NSMenuItem *exportDOCXItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as DOCX..."
                                                                      action:@selector(exportDocumentAsDOCX:)
                                                               keyEquivalent:@""];
    [exportDOCXItem setTarget:self];
    NSMenuItem *exportODTItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as ODT..."
                                                                     action:@selector(exportDocumentAsODT:)
                                                              keyEquivalent:@""];
    [exportODTItem setTarget:self];
    [exportMenuItem setSubmenu:exportMenu];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *printItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Print..."
                                                               action:@selector(printDocument:)
                                                        keyEquivalent:@"p"];
    [printItem setTarget:self];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *closeItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Close"
                                                               action:@selector(performClose:)
                                                        keyEquivalent:@"w"];
    [closeItem setTarget:nil];

    [fileMenuItem setSubmenu:fileMenu];

    NSMenuItem *viewMenuItem = [[[NSMenuItem alloc] initWithTitle:@"View"
                                                            action:NULL
                                                     keyEquivalent:@""] autorelease];
    [menubar addItem:viewMenuItem];

    NSMenu *viewMenu = [[[NSMenu alloc] initWithTitle:@"View"] autorelease];
    NSMenuItem *readItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Reading Mode"
                                                             action:@selector(setReadMode:)
                                                      keyEquivalent:@"1"];
    [readItem setTarget:self];
    NSMenuItem *editItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Edit Mode"
                                                             action:@selector(setEditMode:)
                                                      keyEquivalent:@"2"];
    [editItem setTarget:self];
    NSMenuItem *splitItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Split Mode"
                                                              action:@selector(setSplitMode:)
                                                       keyEquivalent:@"3"];
    [splitItem setTarget:self];

    [viewMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fontMenuItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Source Editor Font"
                                                                  action:NULL
                                                           keyEquivalent:@""];
    NSMenu *fontMenu = [[[NSMenu alloc] initWithTitle:@"Source Editor Font"] autorelease];
    NSMenuItem *chooseFontItem = (NSMenuItem *)[fontMenu addItemWithTitle:@"Choose Monospace Font..."
                                                                    action:@selector(chooseSourceEditorFont:)
                                                             keyEquivalent:@""];
    [chooseFontItem setTarget:self];
    NSMenuItem *increaseFontItem = (NSMenuItem *)[fontMenu addItemWithTitle:@"Increase Size"
                                                                      action:@selector(increaseSourceEditorFontSize:)
                                                               keyEquivalent:@""];
    [increaseFontItem setTarget:self];
    NSMenuItem *decreaseFontItem = (NSMenuItem *)[fontMenu addItemWithTitle:@"Decrease Size"
                                                                      action:@selector(decreaseSourceEditorFontSize:)
                                                               keyEquivalent:@""];
    [decreaseFontItem setTarget:self];
    NSMenuItem *resetFontItem = (NSMenuItem *)[fontMenu addItemWithTitle:@"Reset Size"
                                                                   action:@selector(resetSourceEditorFontSize:)
                                                            keyEquivalent:@""];
    [resetFontItem setTarget:self];
    [fontMenuItem setSubmenu:fontMenu];

    [viewMenuItem setSubmenu:viewMenu];

    [NSApp setMainMenu:menubar];
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
    [_window setTitle:@"Markdown Viewer"];
    [_window setDelegate:self];

    NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
    if (style == NSWindows95InterfaceStyle) {
        NSMenu *mainMenu = [NSApp mainMenu];
        if (mainMenu != nil) {
            [_window setMenu:mainMenu];
        }
    }

    _zoomScale = 1.0;
    NSNumber *savedZoom = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownZoomScale"];
    if (savedZoom != nil) {
        double value = [savedZoom doubleValue];
        if (value > 0.25 && value < 4.0) {
            _zoomScale = value;
        }
    }
    [self setupToolbar];

    _documentContainer = [[NSView alloc] initWithFrame:[[_window contentView] bounds]];
    [_documentContainer setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    _splitRatio = 0.5;
    NSNumber *savedSplitRatio = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownSplitRatio"];
    if ([savedSplitRatio respondsToSelector:@selector(doubleValue)]) {
        double value = [savedSplitRatio doubleValue];
        if (value > 0.15 && value < 0.85) {
            _splitRatio = (CGFloat)value;
        }
    }

    _splitView = [[NSSplitView alloc] initWithFrame:[_documentContainer bounds]];
    [_splitView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_splitView setVertical:YES];
    [_splitView setDelegate:self];

    _previewScrollView = [[NSScrollView alloc] initWithFrame:[_documentContainer bounds]];
    [_previewScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_previewScrollView setHasVerticalScroller:YES];

    _textView = [[OMDTextView alloc] initWithFrame:[[_previewScrollView contentView] bounds]];
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

    [_previewScrollView setDocumentView:_textView];

    _sourceScrollView = [[NSScrollView alloc] initWithFrame:[_documentContainer bounds]];
    [_sourceScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_sourceScrollView setHasVerticalScroller:YES];
    [_sourceScrollView setHasVerticalRuler:YES];
    [_sourceScrollView setRulersVisible:YES];

    _sourceTextView = [[OMDSourceTextView alloc] initWithFrame:[[_sourceScrollView contentView] bounds]];
    [_sourceTextView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_sourceTextView setEditable:YES];
    [_sourceTextView setSelectable:YES];
    [_sourceTextView setRichText:NO];
    [_sourceTextView setUsesRuler:YES];
    [_sourceTextView setRulerVisible:YES];
    [_sourceTextView setTextContainerInset:NSMakeSize(20.0, 16.0)];
    [[_sourceTextView textContainer] setLineFragmentPadding:0.0];
    [_sourceTextView setDelegate:self];
    [self applySourceEditorFontFromDefaults];
    [_sourceTextView setString:@""];
    [_sourceScrollView setDocumentView:_sourceTextView];
    _sourceLineNumberRuler = [[OMDLineNumberRulerView alloc] initWithScrollView:_sourceScrollView
                                                                        textView:_sourceTextView];
    [_sourceScrollView setVerticalRulerView:_sourceLineNumberRuler];

    [_splitView addSubview:_sourceScrollView];
    [_splitView addSubview:_previewScrollView];

    [_documentContainer addSubview:_previewScrollView];
    [[_window contentView] addSubview:_documentContainer];

    [_window makeKeyAndOrderFront:nil];

    _renderer = [[OMMarkdownRenderer alloc] init];
    [_renderer setAsynchronousMathGenerationEnabled:YES];
    [_renderer setZoomScale:_zoomScale];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mathArtifactsDidWarm:)
                                                 name:OMMarkdownRendererMathArtifactsDidWarmNotification
                                               object:nil];

    _viewerMode = OMDViewerModeFromInteger([[NSUserDefaults standardUserDefaults] integerForKey:@"ObjcMarkdownViewerMode"]);
    [self setViewerMode:_viewerMode persistPreference:NO];
}

- (void)setupToolbar
{
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:@"ObjcMarkdownViewerToolbar"] autorelease];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
    [toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
    [toolbar setSizeMode:NSToolbarSizeModeRegular];
    [_window setToolbar:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
      itemForItemIdentifier:(NSString *)identifier
  willBeInsertedIntoToolbar:(BOOL)flag
{
    if ([identifier isEqualToString:@"OpenDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"OpenDocument"] autorelease];
        [item setLabel:@"Open"];
        [item setPaletteLabel:@"Open"];
        [item setToolTip:@"Open a Markdown file"];
        [item setTarget:self];
        [item setAction:@selector(openDocument:)];
        NSImage *image = [NSImage imageNamed:@"toolbar-open.png"];
        if (image == nil) {
            image = [NSImage imageNamed:@"open-icon.png"];
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"NSOpen"];
        }
        if (image != nil) {
            [item setImage:image];
        }
        return item;
    }

    if ([identifier isEqualToString:@"ImportDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ImportDocument"] autorelease];
        [item setLabel:@"Import"];
        [item setPaletteLabel:@"Import"];
        [item setToolTip:@"Import RTF, DOCX, or ODT"];
        [item setTarget:self];
        [item setAction:@selector(importDocument:)];
        NSImage *image = [NSImage imageNamed:@"toolbar-import.png"];
        if (image == nil) {
            image = [NSImage imageNamed:@"NSOpen"];
        }
        if (image != nil) {
            [item setImage:image];
        }
        return item;
    }

    if ([identifier isEqualToString:@"PrintDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"PrintDocument"] autorelease];
        [item setLabel:@"Print"];
        [item setPaletteLabel:@"Print"];
        [item setToolTip:@"Print the current document"];
        [item setTarget:self];
        [item setAction:@selector(printDocument:)];
        NSImage *image = [NSImage imageNamed:@"toolbar-print.png"];
        if (image == nil) {
            image = [NSImage imageNamed:@"NSPrint"];
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"common_Printer.tiff"];
        }
        if (image != nil) {
            [item setImage:image];
        }
        return item;
    }

    if ([identifier isEqualToString:@"ExportDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ExportDocument"] autorelease];
        [item setLabel:@"Export PDF"];
        [item setPaletteLabel:@"Export PDF"];
        [item setToolTip:@"Export the current document as PDF (more formats in File > Export)"];
        [item setTarget:self];
        [item setAction:@selector(exportDocumentAsPDF:)];
        NSImage *image = [NSImage imageNamed:@"toolbar-export.png"];
        if (image == nil) {
            image = [NSImage imageNamed:@"NSSave"];
        }
        if (image != nil) {
            [item setImage:image];
        }
        return item;
    }

    if ([identifier isEqualToString:@"ModeControls"]) {
        if (_modeContainer == nil) {
            _modeContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 26)];
            _modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 3, 34, 20)];
            [_modeLabel setBezeled:NO];
            [_modeLabel setEditable:NO];
            [_modeLabel setSelectable:NO];
            [_modeLabel setDrawsBackground:NO];
            [_modeLabel setAlignment:NSRightTextAlignment];
            [_modeLabel setFont:[NSFont systemFontOfSize:11.0]];
            [_modeLabel setTextColor:[self modeLabelTextColor]];
            [_modeLabel setStringValue:@"Mode"];
            [_modeContainer addSubview:_modeLabel];

            _modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(38, 2, 182, 22)];
            [_modeControl setSegmentCount:3];
            [_modeControl setLabel:@"Read" forSegment:0];
            [_modeControl setLabel:@"Edit" forSegment:1];
            [_modeControl setLabel:@"Split" forSegment:2];
            [_modeControl setTarget:self];
            [_modeControl setAction:@selector(modeControlChanged:)];
            [_modeContainer addSubview:_modeControl];

            [self updateModeControlSelection];
        }
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ModeControls"] autorelease];
        [item setView:_modeContainer];
        [item setMinSize:NSMakeSize(220, 26)];
        [item setMaxSize:NSMakeSize(220, 26)];
        [item setLabel:@""];
        [item setPaletteLabel:@"Mode"];
        [item setToolTip:@"Switch between read, edit, and split modes"];
        return item;
    }

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
    return [NSArray arrayWithObjects:
        @"OpenDocument",
        @"ImportDocument",
        @"ExportDocument",
        @"PrintDocument",
        @"ModeControls",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ZoomControls",
        nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:
        @"OpenDocument",
        @"ImportDocument",
        @"ExportDocument",
        @"PrintDocument",
        @"ModeControls",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ZoomControls",
        nil];
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
    [self cancelPendingInteractiveRender];
    [self renderCurrentMarkdown];
}

- (BOOL)hasLoadedDocument
{
    return _currentMarkdown != nil;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = [menuItem action];
    if (action == @selector(setReadMode:) ||
        action == @selector(setEditMode:) ||
        action == @selector(setSplitMode:)) {
        OMDViewerMode modeForAction = OMDViewerModeRead;
        if (action == @selector(setEditMode:)) {
            modeForAction = OMDViewerModeEdit;
        } else if (action == @selector(setSplitMode:)) {
            modeForAction = OMDViewerModeSplit;
        }
        [menuItem setState:(_viewerMode == modeForAction ? NSOnState : NSOffState)];
        return YES;
    }

    if (action == @selector(chooseSourceEditorFont:) ||
        action == @selector(increaseSourceEditorFontSize:) ||
        action == @selector(decreaseSourceEditorFontSize:) ||
        action == @selector(resetSourceEditorFontSize:)) {
        return _sourceTextView != nil;
    }

    if (action == @selector(saveDocumentAsMarkdown:) ||
        action == @selector(printDocument:) ||
        action == @selector(exportDocumentAsPDF:) ||
        action == @selector(exportDocumentAsRTF:) ||
        action == @selector(exportDocumentAsDOCX:) ||
        action == @selector(exportDocumentAsODT:)) {
        return [self hasLoadedDocument];
    }
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem
{
    NSString *identifier = [toolbarItem itemIdentifier];
    if ([identifier isEqualToString:@"PrintDocument"] ||
        [identifier isEqualToString:@"ExportDocument"]) {
        return [self hasLoadedDocument];
    }
    return YES;
}

- (void)openDocument:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setTitle:@"Open Markdown"];
    [panel setPrompt:@"Open"];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"md", @"markdown", @"mdown", @"txt", nil]];
    NSString *lastDir = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownLastOpenDir"];
    if (lastDir != nil) {
        [panel setDirectory:lastDir];
    } else {
        NSString *home = NSHomeDirectory();
        NSString *documents = [home stringByAppendingPathComponent:@"Documents"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:documents]) {
            [panel setDirectory:documents];
        } else if (home != nil) {
            [panel setDirectory:home];
        }
    }

    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }

    NSArray *filenames = [panel filenames];
    if ([filenames count] == 0) {
        return;
    }

    NSString *path = [filenames objectAtIndex:0];
    if (_currentPath == nil && _currentMarkdown == nil) {
        [self openDocumentAtPath:path];
    } else {
        [self openDocumentAtPathInNewWindow:path];
    }
}

- (void)importDocument:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setTitle:@"Import"];
    [panel setPrompt:@"Import"];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"rtf", @"docx", @"odt", nil]];

    NSString *lastDir = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownLastOpenDir"];
    if (lastDir != nil) {
        [panel setDirectory:lastDir];
    } else {
        NSString *home = NSHomeDirectory();
        NSString *documents = [home stringByAppendingPathComponent:@"Documents"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:documents]) {
            [panel setDirectory:documents];
        } else if (home != nil) {
            [panel setDirectory:home];
        }
    }

    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }

    NSArray *filenames = [panel filenames];
    if ([filenames count] == 0) {
        return;
    }

    NSString *path = [filenames objectAtIndex:0];
    NSString *extension = [[path pathExtension] lowercaseString];
    BOOL supportsFormatNow = [OMDDocumentConverter isSupportedExtension:extension];

    if (_currentPath == nil && _currentMarkdown == nil) {
        [self importDocumentAtPath:path];
    } else if (supportsFormatNow) {
        OMDAppDelegate *controller = [[OMDAppDelegate alloc] init];
        [controller setupWindow];
        BOOL imported = [controller importDocumentAtPath:path];
        if (imported) {
            [controller registerAsSecondaryWindow];
        } else {
            [controller->_window close];
        }
        [controller release];
    } else {
        [self importDocumentAtPath:path];
    }
}

- (BOOL)ensureDocumentLoadedForActionName:(NSString *)actionName
{
    if ([self hasLoadedDocument]) {
        return YES;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:@"%@ unavailable", actionName]];
    [alert setInformativeText:@"Open or import a document first."];
    [alert runModal];
    return NO;
}

- (OMDDocumentConverter *)documentConverter
{
    if (_documentConverter == nil) {
        _documentConverter = [[OMDDocumentConverter defaultConverter] retain];
    }
    return _documentConverter;
}

- (BOOL)ensureConverterAvailableForActionName:(NSString *)actionName
{
    if ([self documentConverter] != nil) {
        return YES;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:@"%@ requires pandoc", actionName]];
    [alert setInformativeText:[OMDDocumentConverter missingBackendInstallMessage]];
    [alert runModal];
    return NO;
}

- (void)presentConverterError:(NSError *)error fallbackTitle:(NSString *)title
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title];
    if (error != nil) {
        NSString *failureReason = [[error userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
        NSString *description = [error localizedDescription];
        if (failureReason != nil && [failureReason length] > 0) {
            [alert setInformativeText:[NSString stringWithFormat:@"%@\n\n%@", description, failureReason]];
        } else {
            [alert setInformativeText:description];
        }
    } else {
        [alert setInformativeText:@"Conversion failed."];
    }
    [alert runModal];
}

- (void)setCurrentMarkdown:(NSString *)markdown sourcePath:(NSString *)sourcePath
{
    NSString *newMarkdown = markdown != nil ? [markdown copy] : nil;
    NSString *newSourcePath = sourcePath != nil ? [sourcePath copy] : nil;

    [_currentMarkdown release];
    _currentMarkdown = newMarkdown;
    [_currentPath release];
    _currentPath = newSourcePath;
    _sourceIsDirty = NO;

    if (_currentPath != nil) {
        NSString *lastDir = [_currentPath stringByDeletingLastPathComponent];
        if (lastDir != nil) {
            [[NSUserDefaults standardUserDefaults] setObject:lastDir forKey:@"ObjcMarkdownLastOpenDir"];
        }
    }

    [self synchronizeSourceEditorWithCurrentMarkdown];
    [self updateWindowTitle];
    if ([self isPreviewVisible]) {
        [self renderCurrentMarkdown];
    }
}

- (BOOL)importDocumentAtPath:(NSString *)path
{
    NSString *extension = [[path pathExtension] lowercaseString];
    if (![OMDDocumentConverter isSupportedExtension:extension]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Unsupported import format"];
        [alert setInformativeText:@"Choose an .rtf, .docx, or .odt file."];
        [alert runModal];
        return NO;
    }

    if (![self ensureConverterAvailableForActionName:@"Import"]) {
        return NO;
    }

    NSString *importedMarkdown = nil;
    NSError *error = nil;
    BOOL success = [[self documentConverter] importFileAtPath:path
                                                     markdown:&importedMarkdown
                                                        error:&error];
    if (!success) {
        [self presentConverterError:error fallbackTitle:@"Import failed"];
        return NO;
    }

    [self setCurrentMarkdown:(importedMarkdown != nil ? importedMarkdown : @"")
                  sourcePath:path];
    return YES;
}

- (NSString *)defaultExportFileNameWithExtension:(NSString *)extension
{
    NSString *baseName = nil;
    if (_currentPath != nil) {
        baseName = [[_currentPath lastPathComponent] stringByDeletingPathExtension];
    }
    if (baseName == nil || [baseName length] == 0) {
        baseName = @"Document";
    }
    return [baseName stringByAppendingPathExtension:extension];
}

- (NSString *)defaultSaveMarkdownFileName
{
    return [self defaultExportFileNameWithExtension:@"md"];
}

- (NSString *)defaultExportPDFFileName
{
    return [self defaultExportFileNameWithExtension:@"pdf"];
}

- (void)saveDocumentAsMarkdown:(id)sender
{
    if (![self ensureDocumentLoadedForActionName:@"Save Markdown As"]) {
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"md", @"markdown", nil]];
    [panel setCanCreateDirectories:YES];
    [panel setTitle:@"Save Markdown As"];
    [panel setPrompt:@"Save"];
    [panel setNameFieldStringValue:[self defaultSaveMarkdownFileName]];
    if (_currentPath != nil) {
        [panel setDirectory:[_currentPath stringByDeletingLastPathComponent]];
    }

    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }

    NSString *path = [panel filename];
    if (path == nil || [path length] == 0) {
        return;
    }
    NSString *extension = [[path pathExtension] lowercaseString];
    if (![extension isEqualToString:@"md"] && ![extension isEqualToString:@"markdown"]) {
        path = [path stringByAppendingPathExtension:@"md"];
    }

    NSError *error = nil;
    BOOL success = [_currentMarkdown writeToFile:path
                                      atomically:YES
                                        encoding:NSUTF8StringEncoding
                                           error:&error];
    if (!success) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Save failed"];
        [alert setInformativeText:[error localizedDescription]];
        [alert runModal];
        return;
    }

    [self setCurrentMarkdown:_currentMarkdown sourcePath:path];
}

- (NSPrintInfo *)configuredPrintInfo
{
    NSPrintInfo *shared = [NSPrintInfo sharedPrintInfo];
    NSPrintInfo *printInfo = shared != nil ? [shared copy] : [[NSPrintInfo alloc] init];
    NSSize paperSize = [printInfo paperSize];
    if (paperSize.width <= 0.0 || paperSize.height <= 0.0) {
        [printInfo setPaperSize:NSMakeSize(612.0, 792.0)];
    }
    [printInfo setHorizontalPagination:NSAutoPagination];
    [printInfo setVerticalPagination:NSAutoPagination];
    [printInfo setHorizontallyCentered:NO];
    [printInfo setVerticallyCentered:NO];
    return [printInfo autorelease];
}

- (CGFloat)printableContentWidthForPrintInfo:(NSPrintInfo *)printInfo
{
    if (printInfo == nil) {
        return 540.0;
    }
    NSSize paperSize = [printInfo paperSize];
    CGFloat width = paperSize.width - [printInfo leftMargin] - [printInfo rightMargin];
    if (width <= 0.0) {
        width = paperSize.width;
    }
    if (width <= 0.0) {
        width = 540.0;
    }
    if (width < 240.0) {
        width = 240.0;
    }
    return width;
}

- (OMDTextView *)newPrintTextViewForPrintInfo:(NSPrintInfo *)printInfo
{
    if (_currentMarkdown == nil) {
        return nil;
    }

    CGFloat viewWidth = [self printableContentWidthForPrintInfo:printInfo];
    CGFloat insetX = 20.0;
    CGFloat insetY = 16.0;
    CGFloat layoutWidth = viewWidth - (insetX * 2.0);
    if (layoutWidth < 1.0) {
        layoutWidth = viewWidth;
    }

    OMMarkdownRenderer *printRenderer = [[OMMarkdownRenderer alloc] init];
    [printRenderer setZoomScale:OMDPrintExportZoomScale];
    [printRenderer setLayoutWidth:layoutWidth];
    NSAttributedString *rendered = [printRenderer attributedStringFromMarkdown:_currentMarkdown];

    OMDTextView *printView = [[OMDTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, viewWidth, 100.0)];
    [printView setEditable:NO];
    [printView setSelectable:NO];
    [printView setRichText:YES];
    [printView setDrawsBackground:YES];
    [printView setTextContainerInset:NSMakeSize(insetX, insetY)];
    [[printView textContainer] setLineFragmentPadding:0.0];
    [[printView textStorage] setAttributedString:rendered];
    [printView setCodeBlockRanges:[printRenderer codeBlockRanges]];
    [printView setCodeBlockBackgroundColor:[NSColor colorWithCalibratedWhite:0.97 alpha:1.0]];
    [printView setCodeBlockPadding:NSMakeSize(14.0, 8.0)];
    [printView setBlockquoteRanges:[printRenderer blockquoteRanges]];
    [printView setBlockquoteLineColor:[NSColor colorWithCalibratedWhite:0.82 alpha:1.0]];
    [printView setBlockquoteLineWidth:3.0];

    NSColor *background = [printRenderer backgroundColor];
    if (background != nil) {
        [printView setBackgroundColor:background];
    } else {
        [printView setBackgroundColor:[NSColor whiteColor]];
    }

    [printView setHorizontallyResizable:NO];
    [printView setVerticallyResizable:YES];
    [[printView textContainer] setWidthTracksTextView:YES];
    [[printView textContainer] setHeightTracksTextView:NO];
    [[printView textContainer] setContainerSize:NSMakeSize(layoutWidth, FLT_MAX)];

    NSLayoutManager *layoutManager = [printView layoutManager];
    NSTextContainer *container = [printView textContainer];
    [layoutManager ensureLayoutForTextContainer:container];
    NSRect usedRect = [layoutManager usedRectForTextContainer:container];
    CGFloat viewHeight = ceil(usedRect.size.height + (insetY * 2.0) + 2.0);
    if (viewHeight < 100.0) {
        viewHeight = 100.0;
    }
    [printView setFrame:NSMakeRect(0.0, 0.0, viewWidth, viewHeight)];
    [printView setNeedsDisplay:YES];

    [printRenderer release];
    return printView;
}

- (void)printDocument:(id)sender
{
    if (![self ensureDocumentLoadedForActionName:@"Print"]) {
        return;
    }

    NSPrintInfo *printInfo = [self configuredPrintInfo];
    OMDTextView *printView = [self newPrintTextViewForPrintInfo:printInfo];
    if (printView == nil) {
        return;
    }

    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:printView printInfo:printInfo];
    [operation setShowsPrintPanel:YES];
    [operation setShowsProgressPanel:YES];
    BOOL ok = [operation runOperation];
    [printView release];

    if (!ok) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Print failed"];
        [alert setInformativeText:@"The document could not be sent to the print system."];
        [alert runModal];
    }
}

- (void)exportDocumentAsPDF:(id)sender
{
    if (![self ensureDocumentLoadedForActionName:@"Export as PDF"]) {
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"pdf"]];
    [panel setCanCreateDirectories:YES];
    [panel setTitle:@"Export as PDF"];
    [panel setPrompt:@"Export"];
    [panel setNameFieldStringValue:[self defaultExportPDFFileName]];
    if (_currentPath != nil) {
        [panel setDirectory:[_currentPath stringByDeletingLastPathComponent]];
    }

    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }

    NSString *path = [panel filename];
    if (path == nil || [path length] == 0) {
        return;
    }
    if (![[[path pathExtension] lowercaseString] isEqualToString:@"pdf"]) {
        path = [path stringByAppendingPathExtension:@"pdf"];
    }

    NSPrintInfo *printInfo = [self configuredPrintInfo];
    OMDTextView *printView = [self newPrintTextViewForPrintInfo:printInfo];
    if (printView == nil) {
        return;
    }

    [printInfo setJobDisposition:NSPrintSaveJob];
    [[printInfo dictionary] setObject:path forKey:NSPrintSavePath];

    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:printView
                                                                 printInfo:printInfo];
    [operation setShowsPrintPanel:NO];
    [operation setShowsProgressPanel:YES];
    BOOL success = [operation runOperation];

    [printView release];

    if (!success) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Export failed"];
        [alert setInformativeText:@"The PDF could not be created."];
        [alert runModal];
    }
}

- (void)exportDocumentAsRTF:(id)sender
{
    [self exportDocumentWithTitle:@"Export as RTF"
                        extension:@"rtf"
                       actionName:@"Export as RTF"];
}

- (void)exportDocumentAsDOCX:(id)sender
{
    [self exportDocumentWithTitle:@"Export as DOCX"
                        extension:@"docx"
                       actionName:@"Export as DOCX"];
}

- (void)exportDocumentAsODT:(id)sender
{
    [self exportDocumentWithTitle:@"Export as ODT"
                        extension:@"odt"
                       actionName:@"Export as ODT"];
}

- (void)exportDocumentWithTitle:(NSString *)panelTitle
                      extension:(NSString *)extension
                     actionName:(NSString *)actionName
{
    if (![self ensureDocumentLoadedForActionName:actionName]) {
        return;
    }
    if (![self ensureConverterAvailableForActionName:actionName]) {
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:extension]];
    [panel setCanCreateDirectories:YES];
    [panel setTitle:panelTitle];
    [panel setPrompt:@"Export"];
    [panel setNameFieldStringValue:[self defaultExportFileNameWithExtension:extension]];
    if (_currentPath != nil) {
        [panel setDirectory:[_currentPath stringByDeletingLastPathComponent]];
    }

    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }

    NSString *path = [panel filename];
    if (path == nil || [path length] == 0) {
        return;
    }
    if (![[[path pathExtension] lowercaseString] isEqualToString:[extension lowercaseString]]) {
        path = [path stringByAppendingPathExtension:extension];
    }

    NSError *error = nil;
    BOOL success = [[self documentConverter] exportMarkdown:_currentMarkdown
                                                     toPath:path
                                                      error:&error];
    if (!success) {
        [self presentConverterError:error fallbackTitle:@"Export failed"];
    }
}

- (void)renderCurrentMarkdown
{
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }
    BOOL perfLogging = OMDPerformanceLoggingEnabled();
    NSTimeInterval totalStart = perfLogging ? OMDNow() : 0.0;
    [self cancelPendingInteractiveRender];
    [self cancelPendingMathArtifactRender];
    [self cancelPendingLivePreviewRender];
    [_renderer setZoomScale:_zoomScale];
    [self updateRendererLayoutWidth];
    NSTimeInterval markdownStart = perfLogging ? OMDNow() : 0.0;
    NSAttributedString *rendered = [_renderer attributedStringFromMarkdown:_currentMarkdown];
    NSTimeInterval markdownMs = perfLogging ? ((OMDNow() - markdownStart) * 1000.0) : 0.0;
    NSTimeInterval applyStart = perfLogging ? OMDNow() : 0.0;
    [[_textView textStorage] setAttributedString:rendered];
    NSTimeInterval applyMs = perfLogging ? ((OMDNow() - applyStart) * 1000.0) : 0.0;
    NSTimeInterval postStart = perfLogging ? OMDNow() : 0.0;
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
    [self updateWindowTitle];
    if (perfLogging) {
        NSLog(@"[Perf][Viewer] total=%.1fms markdown=%.1fms apply=%.1fms post=%.1fms zoom=%.2f charsIn=%lu charsOut=%lu",
              (OMDNow() - totalStart) * 1000.0,
              markdownMs,
              applyMs,
              (OMDNow() - postStart) * 1000.0,
              _zoomScale,
              (unsigned long)[_currentMarkdown length],
              (unsigned long)[rendered length]);
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
    [self layoutDocumentViews];
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }
    [self requestInteractiveRender];
}

- (CGFloat)splitView:(NSSplitView *)splitView
constrainSplitPosition:(CGFloat)proposedPosition
         ofSubviewAt:(NSInteger)dividerIndex
{
    if (splitView != _splitView) {
        return proposedPosition;
    }

    CGFloat width = [_splitView bounds].size.width;
    CGFloat divider = [_splitView dividerThickness];
    CGFloat available = width - divider;
    CGFloat minWidth = 180.0;
    CGFloat minPosition = minWidth;
    CGFloat maxPosition = available - minWidth;
    if (maxPosition < minPosition) {
        return floor(available / 2.0);
    }
    if (proposedPosition < minPosition) {
        return minPosition;
    }
    if (proposedPosition > maxPosition) {
        return maxPosition;
    }
    return proposedPosition;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    if ([notification object] != _splitView) {
        return;
    }
    [self persistSplitViewRatio];
}

- (void)requestInteractiveRender
{
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }
    // Trailing-edge debounce: rapid UI events collapse to one render.
    [self scheduleInteractiveRenderAfterDelay:OMDInteractiveRenderDebounceInterval];
}

- (void)scheduleInteractiveRenderAfterDelay:(NSTimeInterval)delay
{
    if (delay < 0.01) {
        delay = 0.01;
    }

    if (_interactiveRenderTimer != nil) {
        [_interactiveRenderTimer invalidate];
        [_interactiveRenderTimer release];
        _interactiveRenderTimer = nil;
    }

    _interactiveRenderTimer = [[NSTimer scheduledTimerWithTimeInterval:delay
                                                                 target:self
                                                               selector:@selector(interactiveRenderTimerFired:)
                                                               userInfo:nil
                                                                repeats:NO] retain];
}

- (void)interactiveRenderTimerFired:(NSTimer *)timer
{
    if (timer != _interactiveRenderTimer) {
        return;
    }
    [_interactiveRenderTimer invalidate];
    [_interactiveRenderTimer release];
    _interactiveRenderTimer = nil;
    [self renderCurrentMarkdown];
}

- (void)cancelPendingInteractiveRender
{
    if (_interactiveRenderTimer != nil) {
        [_interactiveRenderTimer invalidate];
        [_interactiveRenderTimer release];
        _interactiveRenderTimer = nil;
    }
}

- (void)mathArtifactsDidWarm:(NSNotification *)notification
{
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }
    [self scheduleMathArtifactRefresh];
}

- (void)scheduleMathArtifactRefresh
{
    if (_mathArtifactRenderTimer != nil) {
        [_mathArtifactRenderTimer invalidate];
        [_mathArtifactRenderTimer release];
        _mathArtifactRenderTimer = nil;
    }
    _mathArtifactRenderTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDMathArtifactRefreshDebounceInterval
                                                                  target:self
                                                                selector:@selector(mathArtifactRenderTimerFired:)
                                                                userInfo:nil
                                                                 repeats:NO] retain];
}

- (void)mathArtifactRenderTimerFired:(NSTimer *)timer
{
    if (timer != _mathArtifactRenderTimer) {
        return;
    }
    [_mathArtifactRenderTimer invalidate];
    [_mathArtifactRenderTimer release];
    _mathArtifactRenderTimer = nil;
    [self renderCurrentMarkdown];
}

- (void)cancelPendingMathArtifactRender
{
    if (_mathArtifactRenderTimer != nil) {
        [_mathArtifactRenderTimer invalidate];
        [_mathArtifactRenderTimer release];
        _mathArtifactRenderTimer = nil;
    }
}

- (void)modeControlChanged:(id)sender
{
    NSInteger selectedSegment = [_modeControl selectedSegment];
    [self setViewerMode:OMDViewerModeFromInteger(selectedSegment) persistPreference:YES];
}

- (void)setReadMode:(id)sender
{
    [self setViewerMode:OMDViewerModeRead persistPreference:YES];
}

- (void)setEditMode:(id)sender
{
    [self setViewerMode:OMDViewerModeEdit persistPreference:YES];
}

- (void)setSplitMode:(id)sender
{
    [self setViewerMode:OMDViewerModeSplit persistPreference:YES];
}

- (void)setViewerMode:(OMDViewerMode)mode persistPreference:(BOOL)persistPreference
{
    mode = OMDViewerModeFromInteger(mode);
    if (_viewerMode == OMDViewerModeSplit && mode != OMDViewerModeSplit) {
        [self persistSplitViewRatio];
    }
    _viewerMode = mode;
    if (persistPreference) {
        [[NSUserDefaults standardUserDefaults] setInteger:_viewerMode forKey:@"ObjcMarkdownViewerMode"];
    }

    [self updateModeControlSelection];
    [self applyViewerModeLayout];
    [self updateWindowTitle];

    if (_viewerMode == OMDViewerModeEdit) {
        [self cancelPendingInteractiveRender];
        [self cancelPendingMathArtifactRender];
        [self cancelPendingLivePreviewRender];
        if (_sourceTextView != nil) {
            [_window makeFirstResponder:_sourceTextView];
        }
    } else if (_currentMarkdown != nil) {
        [self renderCurrentMarkdown];
        if (_viewerMode == OMDViewerModeSplit && _sourceTextView != nil) {
            [_window makeFirstResponder:_sourceTextView];
        }
    }
}

- (void)applyViewerModeLayout
{
    [self layoutDocumentViews];
}

- (void)layoutDocumentViews
{
    if (_documentContainer == nil) {
        return;
    }

    NSRect bounds = [_documentContainer bounds];
    if (_viewerMode == OMDViewerModeRead) {
        [_splitView removeFromSuperview];
        [_previewScrollView removeFromSuperview];
        [_sourceScrollView removeFromSuperview];
        [_previewScrollView setHidden:NO];
        [_sourceScrollView setHidden:YES];
        [_documentContainer addSubview:_previewScrollView];
        [_sourceScrollView setHidden:YES];
        [_previewScrollView setFrame:bounds];
        return;
    }

    if (_viewerMode == OMDViewerModeEdit) {
        [_splitView removeFromSuperview];
        [_previewScrollView removeFromSuperview];
        [_sourceScrollView removeFromSuperview];
        [_previewScrollView setHidden:YES];
        [_sourceScrollView setHidden:NO];
        [_documentContainer addSubview:_sourceScrollView];
        [_previewScrollView setHidden:YES];
        [_sourceScrollView setFrame:bounds];
        return;
    }

    [_previewScrollView removeFromSuperview];
    [_sourceScrollView removeFromSuperview];
    [_splitView removeFromSuperview];
    [_splitView addSubview:_sourceScrollView];
    [_splitView addSubview:_previewScrollView];
    [_documentContainer addSubview:_splitView];
    [_splitView setFrame:bounds];
    [_sourceScrollView setHidden:NO];
    [_previewScrollView setHidden:NO];
    [self applySplitViewRatio];
}

- (void)updateModeControlSelection
{
    if (_modeControl == nil) {
        return;
    }
    [_modeControl setSelectedSegment:_viewerMode];
    if (_modeLabel != nil) {
        [_modeLabel setTextColor:[self modeLabelTextColor]];
    }
}

- (void)synchronizeSourceEditorWithCurrentMarkdown
{
    if (_sourceTextView == nil) {
        return;
    }

    NSString *text = _currentMarkdown != nil ? _currentMarkdown : @"";
    NSString *existing = [_sourceTextView string];
    if (existing == text || [existing isEqualToString:text]) {
        return;
    }
    _isProgrammaticSourceUpdate = YES;
    [_sourceTextView setString:text];
    _isProgrammaticSourceUpdate = NO;
    if (_sourceLineNumberRuler != nil) {
        [_sourceLineNumberRuler invalidateLineNumbers];
    }
}

- (void)scheduleLivePreviewRender
{
    if (![self isPreviewVisible] || _currentMarkdown == nil) {
        return;
    }

    if (_livePreviewRenderTimer != nil) {
        [_livePreviewRenderTimer invalidate];
        [_livePreviewRenderTimer release];
        _livePreviewRenderTimer = nil;
    }
    _livePreviewRenderTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDLivePreviewDebounceInterval
                                                                 target:self
                                                               selector:@selector(livePreviewRenderTimerFired:)
                                                               userInfo:nil
                                                                repeats:NO] retain];
}

- (void)livePreviewRenderTimerFired:(NSTimer *)timer
{
    if (timer != _livePreviewRenderTimer) {
        return;
    }
    [_livePreviewRenderTimer invalidate];
    [_livePreviewRenderTimer release];
    _livePreviewRenderTimer = nil;
    [self renderCurrentMarkdown];
}

- (void)cancelPendingLivePreviewRender
{
    if (_livePreviewRenderTimer != nil) {
        [_livePreviewRenderTimer invalidate];
        [_livePreviewRenderTimer release];
        _livePreviewRenderTimer = nil;
    }
}

- (void)applySplitViewRatio
{
    if (_splitView == nil || [[_splitView subviews] count] < 2) {
        return;
    }

    CGFloat width = [_splitView bounds].size.width;
    CGFloat divider = [_splitView dividerThickness];
    if (width <= divider + 20.0) {
        return;
    }

    CGFloat minWidth = 180.0;
    CGFloat available = width - divider;
    CGFloat position = floor(available * _splitRatio);
    if (position < minWidth) {
        position = minWidth;
    }
    if (position > (available - minWidth)) {
        position = available - minWidth;
    }
    [_splitView setPosition:position ofDividerAtIndex:0];
}

- (void)persistSplitViewRatio
{
    if (_splitView == nil || [[_splitView subviews] count] < 2) {
        return;
    }

    NSArray *subviews = [_splitView subviews];
    NSView *left = [subviews objectAtIndex:0];
    CGFloat width = [_splitView bounds].size.width;
    CGFloat divider = [_splitView dividerThickness];
    CGFloat available = width - divider;
    if (available <= 20.0) {
        return;
    }

    CGFloat ratio = [left frame].size.width / available;
    if (ratio < 0.15) {
        ratio = 0.15;
    } else if (ratio > 0.85) {
        ratio = 0.85;
    }
    _splitRatio = ratio;
    [[NSUserDefaults standardUserDefaults] setDouble:_splitRatio forKey:@"ObjcMarkdownSplitRatio"];
}

- (void)applySourceEditorFontFromDefaults
{
    if (_sourceTextView == nil) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *fontName = [defaults stringForKey:OMDSourceEditorFontNameDefaultsKey];
    CGFloat fontSize = (CGFloat)[defaults doubleForKey:OMDSourceEditorFontSizeDefaultsKey];
    if (fontSize < OMDSourceEditorMinFontSize || fontSize > OMDSourceEditorMaxFontSize) {
        fontSize = OMDSourceEditorDefaultFontSize;
    }

    NSFont *font = nil;
    if (fontName != nil && [fontName length] > 0) {
        font = [NSFont fontWithName:fontName size:fontSize];
    }
    if (font == nil || ![font isFixedPitch]) {
        font = [NSFont userFixedPitchFontOfSize:fontSize];
    }
    if (font == nil || ![font isFixedPitch]) {
        font = [NSFont fontWithName:@"Courier" size:fontSize];
    }
    if (font == nil) {
        font = [NSFont systemFontOfSize:fontSize];
    }

    [self setSourceEditorFont:font persistPreference:NO];
}

- (void)setSourceEditorFont:(NSFont *)font persistPreference:(BOOL)persistPreference
{
    if (_sourceTextView == nil || font == nil) {
        return;
    }

    NSFont *resolved = font;
    CGFloat size = [resolved pointSize];
    if (size < OMDSourceEditorMinFontSize) {
        size = OMDSourceEditorMinFontSize;
    } else if (size > OMDSourceEditorMaxFontSize) {
        size = OMDSourceEditorMaxFontSize;
    }
    if ([resolved pointSize] != size) {
        NSFont *sized = [NSFont fontWithName:[resolved fontName] size:size];
        if (sized != nil) {
            resolved = sized;
        }
    }

    if (![resolved isFixedPitch]) {
        NSFont *fallback = [NSFont userFixedPitchFontOfSize:size];
        if (fallback == nil || ![fallback isFixedPitch]) {
            fallback = [NSFont fontWithName:@"Courier" size:size];
        }
        if (fallback != nil) {
            resolved = fallback;
        }
    }

    [_sourceTextView setFont:resolved];

    NSMutableDictionary *typing = nil;
    NSDictionary *currentTyping = [_sourceTextView typingAttributes];
    if (currentTyping != nil) {
        typing = [currentTyping mutableCopy];
    } else {
        typing = [[NSMutableDictionary alloc] init];
    }
    [typing setObject:resolved forKey:NSFontAttributeName];
    [_sourceTextView setTypingAttributes:typing];
    [typing release];

    NSTextStorage *storage = [_sourceTextView textStorage];
    if (storage != nil && [storage length] > 0) {
        [storage addAttribute:NSFontAttributeName
                        value:resolved
                        range:NSMakeRange(0, [storage length])];
    }

    if (_sourceLineNumberRuler != nil) {
        [_sourceLineNumberRuler invalidateLineNumbers];
    }

    if (persistPreference) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:[resolved fontName] forKey:OMDSourceEditorFontNameDefaultsKey];
        [defaults setDouble:[resolved pointSize] forKey:OMDSourceEditorFontSizeDefaultsKey];
    }
}

- (void)increaseSourceEditorFontSize:(id)sender
{
    NSFont *current = [_sourceTextView font];
    CGFloat size = current != nil ? [current pointSize] : OMDSourceEditorDefaultFontSize;
    size += 1.0;
    NSFont *next = [NSFont fontWithName:(current != nil ? [current fontName] : @"Courier") size:size];
    if (next == nil) {
        next = [NSFont userFixedPitchFontOfSize:size];
    }
    [self setSourceEditorFont:next persistPreference:YES];
}

- (void)decreaseSourceEditorFontSize:(id)sender
{
    NSFont *current = [_sourceTextView font];
    CGFloat size = current != nil ? [current pointSize] : OMDSourceEditorDefaultFontSize;
    size -= 1.0;
    NSFont *next = [NSFont fontWithName:(current != nil ? [current fontName] : @"Courier") size:size];
    if (next == nil) {
        next = [NSFont userFixedPitchFontOfSize:size];
    }
    [self setSourceEditorFont:next persistPreference:YES];
}

- (void)resetSourceEditorFontSize:(id)sender
{
    NSFont *fallback = [NSFont userFixedPitchFontOfSize:OMDSourceEditorDefaultFontSize];
    if (fallback == nil) {
        fallback = [NSFont fontWithName:@"Courier" size:OMDSourceEditorDefaultFontSize];
    }
    if (fallback == nil) {
        fallback = [NSFont systemFontOfSize:OMDSourceEditorDefaultFontSize];
    }
    [self setSourceEditorFont:fallback persistPreference:YES];
}

- (void)chooseSourceEditorFont:(id)sender
{
    if (_sourceTextView == nil) {
        return;
    }
    [_window makeFirstResponder:_sourceTextView];
    NSFontManager *manager = [NSFontManager sharedFontManager];
    [manager setAction:@selector(changeFont:)];
    NSFont *font = [_sourceTextView font];
    if (font != nil) {
        [manager setSelectedFont:font isMultiple:NO];
    }
    [manager orderFrontFontPanel:self];
}

- (void)changeFont:(id)sender
{
    if (_sourceTextView == nil) {
        return;
    }

    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *current = [_sourceTextView font];
    if (current == nil) {
        current = [NSFont userFixedPitchFontOfSize:OMDSourceEditorDefaultFontSize];
    }
    NSFont *converted = [manager convertFont:current];
    if (converted == nil) {
        return;
    }
    if (![converted isFixedPitch]) {
        NSBeep();
        return;
    }
    [self setSourceEditorFont:converted persistPreference:YES];
}

- (BOOL)isPreviewVisible
{
    return _viewerMode != OMDViewerModeEdit;
}

- (NSColor *)modeLabelTextColor
{
    GSTheme *theme = [GSTheme theme];
    NSColor *color = nil;
    if (theme != nil) {
        color = [theme colorNamed:@"controlTextColor" state:GSThemeNormalState];
        if (color == nil) {
            color = [theme colorNamed:@"menuBarTextColor" state:GSThemeNormalState];
        }
        if (color == nil) {
            color = [theme colorNamed:@"menuItemTextColor" state:GSThemeNormalState];
        }
        if (color == nil) {
            color = [theme colorNamed:@"textColor" state:GSThemeNormalState];
        }
    }
    if (color == nil) {
        color = [NSColor controlTextColor];
    }
    if (color == nil) {
        color = [NSColor textColor];
    }
    if (color == nil) {
        color = [NSColor whiteColor];
    }
    return color;
}

- (void)updateWindowTitle
{
    if (_window == nil) {
        return;
    }

    NSString *baseTitle = _currentPath != nil ? [_currentPath lastPathComponent] : @"Markdown Viewer";
    NSString *modeTitle = OMDViewerModeTitle(_viewerMode);
    NSString *dirtyMarker = _sourceIsDirty ? @" *" : @"";
    [_window setTitle:[NSString stringWithFormat:@"%@%@ (%@)", baseTitle, dirtyMarker, modeTitle]];
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

- (void)textDidChange:(NSNotification *)notification
{
    if (_isProgrammaticSourceUpdate) {
        return;
    }
    if ([notification object] != _sourceTextView) {
        return;
    }

    NSString *updatedMarkdown = [[_sourceTextView string] copy];
    [_currentMarkdown release];
    _currentMarkdown = updatedMarkdown;
    _sourceIsDirty = YES;
    [self updateWindowTitle];

    if (_viewerMode == OMDViewerModeSplit) {
        [self scheduleLivePreviewRender];
    }
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

    [self setCurrentMarkdown:markdown sourcePath:resolvedPath];
}

- (void)openDocumentAtPathInNewWindow:(NSString *)path
{
    OMDAppDelegate *controller = [[OMDAppDelegate alloc] init];
    [controller setupWindow];
    [controller openDocumentAtPath:path];
    [controller registerAsSecondaryWindow];
    [controller release];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self persistSplitViewRatio];
    [self cancelPendingInteractiveRender];
    [self cancelPendingMathArtifactRender];
    [self cancelPendingLivePreviewRender];
    [self unregisterAsSecondaryWindow];
}

@end
