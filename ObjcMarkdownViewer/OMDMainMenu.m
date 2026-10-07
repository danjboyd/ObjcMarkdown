// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDMainMenu.h"
#import "OMDViewerDiagnostics.h"

@interface OMDMainMenu ()
- (NSMenu *)buildMenubarWithTarget:(id)target;
@end

#if !defined(GNUSTEP)
// macOS's own menus and items, which AppKit fills in or acts on.

static NSMenuItem *OMDAddMenuItem(NSMenu *menu, NSString *title, SEL action, NSString *key, id target)
{
    NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:title action:action keyEquivalent:key];
    [item setTarget:target];
    return item;
}

static NSMenuItem *OMDAddSubmenu(NSMenu *menubar, NSMenu *menu)
{
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[menu title] action:NULL keyEquivalent:@""] autorelease];
    [menubar addItem:item];
    [menubar setSubmenu:menu forItem:item];
    return item;
}

static void OMDBuildMacApplicationMenu(NSMenu *appMenu, NSString *appName, id target)
{
    OMDAddMenuItem(appMenu, [NSString stringWithFormat:@"About %@", appName], @selector(showAboutPanel:), @"", target);
    [appMenu addItem:[NSMenuItem separatorItem]];
    // "Preferences" became "Settings" in macOS 13.
    NSString *settingsTitle = @"Preferences...";
    if (@available(macOS 13.0, *)) {
        settingsTitle = @"Settings...";
    }
    OMDAddMenuItem(appMenu, settingsTitle, @selector(showPreferences:), @",", target);
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenu *servicesMenu = [[[NSMenu alloc] initWithTitle:@"Services"] autorelease];
    NSMenuItem *servicesItem = OMDAddMenuItem(appMenu, @"Services", NULL, @"", nil);
    [appMenu setSubmenu:servicesMenu forItem:servicesItem];
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];

    OMDAddMenuItem(appMenu, [NSString stringWithFormat:@"Hide %@", appName], @selector(hide:), @"h", NSApp);
    NSMenuItem *hideOthersItem = OMDAddMenuItem(appMenu, @"Hide Others", @selector(hideOtherApplications:), @"h", NSApp);
    [hideOthersItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
    OMDAddMenuItem(appMenu, @"Show All", @selector(unhideAllApplications:), @"", NSApp);
    [appMenu addItem:[NSMenuItem separatorItem]];

    OMDAddMenuItem(appMenu, [NSString stringWithFormat:@"Quit %@", appName], @selector(terminate:), @"q", NSApp);
}

// Find in the preview and the source: the text views' find bars.
static void OMDAddMacFindMenu(NSMenu *editMenu)
{
    NSMenu *findMenu = [[[NSMenu alloc] initWithTitle:@"Find"] autorelease];
    NSMenuItem *item = OMDAddMenuItem(findMenu, @"Find...", @selector(performTextFinderAction:), @"f", nil);
    [item setTag:NSTextFinderActionShowFindInterface];
    item = OMDAddMenuItem(findMenu, @"Find and Replace...", @selector(performTextFinderAction:), @"f", nil);
    [item setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
    [item setTag:NSTextFinderActionShowReplaceInterface];
    item = OMDAddMenuItem(findMenu, @"Find Next", @selector(performTextFinderAction:), @"g", nil);
    [item setTag:NSTextFinderActionNextMatch];
    item = OMDAddMenuItem(findMenu, @"Find Previous", @selector(performTextFinderAction:), @"G", nil);
    [item setTag:NSTextFinderActionPreviousMatch];
    item = OMDAddMenuItem(findMenu, @"Use Selection for Find", @selector(performTextFinderAction:), @"e", nil);
    [item setTag:NSTextFinderActionSetSearchString];
    OMDAddMenuItem(findMenu, @"Jump to Selection", @selector(centerSelectionInVisibleArea:), @"j", nil);

    NSMenuItem *findItem = OMDAddMenuItem(editMenu, @"Find", NULL, @"", nil);
    [editMenu setSubmenu:findMenu forItem:findItem];
}

static void OMDAddMacWindowAndHelpMenus(NSMenu *menubar, NSString *appName, id target)
{
    NSMenu *windowMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    OMDAddMenuItem(windowMenu, @"Minimize", @selector(performMiniaturize:), @"m", nil);
    OMDAddMenuItem(windowMenu, @"Zoom", @selector(performZoom:), @"", nil);
    [windowMenu addItem:[NSMenuItem separatorItem]];
    OMDAddMenuItem(windowMenu, @"Bring All to Front", @selector(arrangeInFront:), @"", NSApp);
    OMDAddSubmenu(menubar, windowMenu);
    [NSApp setWindowsMenu:windowMenu];

    NSMenu *helpMenu = [[[NSMenu alloc] initWithTitle:@"Help"] autorelease];
    OMDAddMenuItem(helpMenu, [NSString stringWithFormat:@"%@ on GitHub", appName],
                   @selector(showProjectHomePage:), @"", target);
    OMDAddSubmenu(menubar, helpMenu);
    [NSApp setHelpMenu:helpMenu];
}

// macOS menus end the title of an item that asks for more with an ellipsis
// character rather than three dots.
static void OMDUseEllipsisCharacters(NSMenu *menu)
{
    for (NSMenuItem *item in [menu itemArray]) {
        NSString *title = [item title];
        if ([title hasSuffix:@"..."]) {
            [item setTitle:[[title substringToIndex:[title length] - 3] stringByAppendingString:@"…"]];
        }
        if ([item submenu] != nil) {
            OMDUseEllipsisCharacters([item submenu]);
        }
    }
}
#endif

@implementation OMDMainMenu

- (instancetype)initWithTarget:(id)target
{
    self = [super init];
    if (self != nil) {
        _menubar = [[self buildMenubarWithTarget:target] retain];
    }
    return self;
}

- (void)dealloc
{
    [_menubar release];
    [_openRecentMenu release];
    [super dealloc];
}

- (NSMenu *)menubar
{
    return _menubar;
}

- (NSMenu *)openRecentMenu
{
    return _openRecentMenu;
}

- (NSMenu *)buildMenubarWithTarget:(id)target
{
    NSMenu *menubar = [[[NSMenu alloc] initWithTitle:@"GSMainMenu"] autorelease];

    NSString *appName = OMDInfoStringForKey(@"ApplicationName");
    if (appName == nil || [appName length] == 0) {
        appName = [[NSProcessInfo processInfo] processName];
    }
    NSMenuItem *appMenuItem = [[[NSMenuItem alloc] initWithTitle:appName
                                                          action:NULL
                                                   keyEquivalent:@""] autorelease];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:appName] autorelease];
    [menubar addItem:appMenuItem];
    [menubar setSubmenu:appMenu forItem:appMenuItem];

#if !defined(GNUSTEP)
    OMDBuildMacApplicationMenu(appMenu, appName, target);
#else
    NSString *aboutTitle = [NSString stringWithFormat:@"About %@", appName];
    NSMenuItem *aboutItem = [[[NSMenuItem alloc] initWithTitle:aboutTitle
                                                         action:@selector(showAboutPanel:)
                                                  keyEquivalent:@""] autorelease];
    [aboutItem setTarget:target];
    [appMenu addItem:aboutItem];

    NSMenuItem *updatesItem = (NSMenuItem *)[appMenu addItemWithTitle:@"Check for Updates..."
                                                               action:@selector(checkForUpdates:)
                                                        keyEquivalent:@""];
    [updatesItem setTarget:target];

    NSMenuItem *preferencesItem = (NSMenuItem *)[appMenu addItemWithTitle:@"Preferences..."
                                                                    action:@selector(showPreferences:)
                                                             keyEquivalent:@","];
    [preferencesItem setTarget:target];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSString *quitTitle = [NSString stringWithFormat:@"Quit %@", appName];
    NSMenuItem *quitItem = (NSMenuItem *)[appMenu addItemWithTitle:quitTitle
                                                             action:@selector(terminate:)
                                                      keyEquivalent:@"q"];
    [quitItem setTarget:NSApp];
#endif

    NSMenuItem *fileMenuItem = [[[NSMenuItem alloc] initWithTitle:@"File"
                                                           action:NULL
                                                    keyEquivalent:@""] autorelease];
    [menubar addItem:fileMenuItem];

    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    NSMenuItem *newItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"New"
                                                            action:@selector(newDocument:)
                                                     keyEquivalent:@"n"];
    [newItem setTarget:target];
    NSMenuItem *openItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Open Markdown..."
                                                             action:@selector(openDocument:)
                                                      keyEquivalent:@"o"];
    [openItem setTarget:target];
    [[fileMenu addItemWithTitle:@"Open Location..."
                         action:@selector(openLocation:)
                  keyEquivalent:@"l"] setTarget:target];

    NSMenuItem *newWindowItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"New Window"
                                                                   action:@selector(newWindow:)
                                                            keyEquivalent:@"N"];
    [newWindowItem setTarget:target];

    NSMenuItem *openRecentItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Open Recent"
                                                                    action:NULL
                                                             keyEquivalent:@""];
    NSMenu *openRecentMenu = [[[NSMenu alloc] initWithTitle:@"Open Recent"] autorelease];
    [openRecentMenu setAutoenablesItems:NO];
    [openRecentMenu setDelegate:target];
    [openRecentItem setSubmenu:openRecentMenu];
    _openRecentMenu = [openRecentMenu retain];

    NSMenuItem *importItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Import..."
                                                                action:@selector(importDocument:)
                                                         keyEquivalent:@"I"];
    [importItem setTarget:target];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *saveItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Save"
                                                              action:@selector(saveDocument:)
                                                       keyEquivalent:@"s"];
    [saveItem setTarget:target];

    NSMenuItem *saveAsItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Save Markdown As..."
                                                                action:@selector(saveDocumentAsMarkdown:)
                                                         keyEquivalent:@"S"];
    [saveAsItem setTarget:target];

    NSMenuItem *reloadItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Refresh"
                                                               action:@selector(reloadDocumentFromDisk:)
                                                        keyEquivalent:@"r"];
    [reloadItem setTarget:target];

    NSMenuItem *exportMenuItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Export"
                                                                    action:NULL
                                                             keyEquivalent:@""];
    NSMenu *exportMenu = [[[NSMenu alloc] initWithTitle:@"Export"] autorelease];
    NSMenuItem *exportPDFItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as PDF..."
                                                                     action:@selector(exportDocumentAsPDF:)
                                                              keyEquivalent:@""];
    [exportPDFItem setTarget:target];
    NSMenuItem *exportRTFItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as RTF..."
                                                                     action:@selector(exportDocumentAsRTF:)
                                                              keyEquivalent:@""];
    [exportRTFItem setTarget:target];
    NSMenuItem *exportDOCXItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as DOCX..."
                                                                      action:@selector(exportDocumentAsDOCX:)
                                                               keyEquivalent:@""];
    [exportDOCXItem setTarget:target];
    NSMenuItem *exportODTItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as ODT..."
                                                                     action:@selector(exportDocumentAsODT:)
                                                              keyEquivalent:@""];
    [exportODTItem setTarget:target];
    NSMenuItem *exportHTMLItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as HTML..."
                                                                      action:@selector(exportDocumentAsHTML:)
                                                               keyEquivalent:@""];
    [exportHTMLItem setTarget:target];
    [exportMenuItem setSubmenu:exportMenu];

    [fileMenu addItem:[NSMenuItem separatorItem]];

#if !defined(GNUSTEP)
    NSMenuItem *pageSetupItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Page Setup..."
                                                                   action:@selector(runPageLayout:)
                                                            keyEquivalent:@"P"];
    [pageSetupItem setTarget:nil];
#endif
    NSMenuItem *printItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Print..."
                                                               action:@selector(printDocument:)
                                                        keyEquivalent:@"p"];
    [printItem setTarget:target];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *closeItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Close"
                                                               action:@selector(performClose:)
                                                        keyEquivalent:@"w"];
    [closeItem setTarget:nil];

    [fileMenuItem setSubmenu:fileMenu];

    NSMenuItem *editMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Edit"
                                                            action:NULL
                                                     keyEquivalent:@""] autorelease];
    [menubar addItem:editMenuItem];

    NSMenu *editMenu = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
    NSMenuItem *undoItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Undo"
                                                              action:@selector(undo:)
                                                       keyEquivalent:@"z"];
    [undoItem setTarget:target];
    NSMenuItem *redoItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Redo"
                                                              action:@selector(redo:)
                                                       keyEquivalent:@"Z"];
    [redoItem setTarget:target];
    [editMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *cutItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Cut"
                                                             action:@selector(cut:)
                                                      keyEquivalent:@"x"];
    [cutItem setTarget:nil];
    NSMenuItem *copyItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Copy"
                                                              action:@selector(copy:)
                                                       keyEquivalent:@"c"];
    [copyItem setTarget:nil];
    NSMenuItem *pasteItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Paste"
                                                               action:@selector(paste:)
                                                        keyEquivalent:@"v"];
    [pasteItem setTarget:nil];
    [editMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *selectAllItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Select All"
                                                                   action:@selector(selectAll:)
                                                            keyEquivalent:@"a"];
    [selectAllItem setTarget:nil];
    [editMenu addItem:[NSMenuItem separatorItem]];
#if !defined(GNUSTEP)
    // macOS's find bar, in its usual Find submenu (with the same fallback).
    OMDAddMacFindMenu(editMenu);
#else
    // Find in the editor or the preview (#87): the focused text view takes
    // them, else the app delegate passes them to the one on show.
    struct { NSString *title; NSString *key; NSInteger tag; } findItems[] = {
        { @"Find...", @"f", NSFindPanelActionShowFindPanel },
        { @"Find Next", @"g", NSFindPanelActionNext },
        { @"Find Previous", @"G", NSFindPanelActionPrevious },
        { @"Use Selection for Find", @"e", NSFindPanelActionSetFindString },
    };
    NSUInteger findIndex = 0;
    for (; findIndex < sizeof(findItems) / sizeof(findItems[0]); findIndex++) {
        NSMenuItem *findItem = (NSMenuItem *)[editMenu addItemWithTitle:findItems[findIndex].title
                                                                 action:@selector(performFindPanelAction:)
                                                          keyEquivalent:findItems[findIndex].key];
        [findItem setTag:findItems[findIndex].tag];
        [findItem setTarget:nil];
    }
#endif
    [editMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *toggleBoldItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Toggle Bold"
                                                                    action:@selector(toggleBoldFormatting:)
                                                             keyEquivalent:@"b"];
    [toggleBoldItem setTarget:target];
    NSMenuItem *toggleItalicItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Toggle Italic"
                                                                      action:@selector(toggleItalicFormatting:)
                                                               keyEquivalent:@"i"];
    [toggleItalicItem setTarget:target];
    [editMenuItem setSubmenu:editMenu];

    NSMenuItem *viewMenuItem = [[[NSMenuItem alloc] initWithTitle:@"View"
                                                            action:NULL
                                                     keyEquivalent:@""] autorelease];
    [menubar addItem:viewMenuItem];

    NSMenu *viewMenu = [[[NSMenu alloc] initWithTitle:@"View"] autorelease];
    NSMenuItem *readItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Reading Mode"
                                                             action:@selector(setReadMode:)
                                                      keyEquivalent:@"1"];
    [readItem setTarget:target];
    NSMenuItem *editItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Edit Mode"
                                                             action:@selector(setEditMode:)
                                                      keyEquivalent:@"2"];
    [editItem setTarget:target];
    NSMenuItem *splitItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Split Mode"
                                                              action:@selector(setSplitMode:)
                                                       keyEquivalent:@"3"];
    [splitItem setTarget:target];

    NSMenuItem *splitSyncMenuItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Split Sync"
                                                                       action:NULL
                                                                keyEquivalent:@""];
    NSMenu *splitSyncMenu = [[[NSMenu alloc] initWithTitle:@"Split Sync"] autorelease];
    NSMenuItem *splitSyncUnlinkedItem = (NSMenuItem *)[splitSyncMenu addItemWithTitle:@"Independent"
                                                                                 action:@selector(setSplitSyncModeUnlinked:)
                                                                          keyEquivalent:@""];
    [splitSyncUnlinkedItem setTarget:target];
    NSMenuItem *splitSyncLinkedItem = (NSMenuItem *)[splitSyncMenu addItemWithTitle:@"Linked Scrolling"
                                                                               action:@selector(setSplitSyncModeLinkedScrolling:)
                                                                        keyEquivalent:@""];
    [splitSyncLinkedItem setTarget:target];
    NSMenuItem *splitSyncCaretItem = (NSMenuItem *)[splitSyncMenu addItemWithTitle:@"Follow Caret"
                                                                              action:@selector(setSplitSyncModeCaretSelectionFollow:)
                                                                       keyEquivalent:@""];
    [splitSyncCaretItem setTarget:target];
    [splitSyncMenuItem setSubmenu:splitSyncMenu];

    NSMenuItem *showExplorerItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Show Explorer"
                                                                   action:@selector(toggleExplorerSidebar:)
                                                            keyEquivalent:@""];
    [showExplorerItem setTarget:target];
    [[viewMenu addItemWithTitle:@"Filter Files"
                         action:@selector(filterExplorerFiles:)
                  keyEquivalent:@"F"] setTarget:target];

    NSMenuItem *showOutlineItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Show Outline"
                                                               action:@selector(toggleOutline:)
                                                        keyEquivalent:@"O"];
    [showOutlineItem setTarget:target];

    NSMenuItem *showFormattingBarItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Show Formatting Bar"
                                                                        action:@selector(toggleFormattingBar:)
                                                                 keyEquivalent:@""];
    [showFormattingBarItem setTarget:target];
    [[viewMenu addItemWithTitle:@"Full-Width Preview"
                         action:@selector(togglePreviewFullWidth:)
                  keyEquivalent:@""] setTarget:target];

    [viewMenu addItem:[NSMenuItem separatorItem]];

    // The usual Command mask, like every other shortcut (Ctrl with GNUstep's
    // default key mapping); OMDMainWindow also takes Command-+ for Zoom In.
    NSMenuItem *zoomInItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Zoom In"
                                                              action:@selector(zoomIn:)
                                                       keyEquivalent:@"="];
    [zoomInItem setTarget:target];
    NSMenuItem *zoomOutItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Zoom Out"
                                                               action:@selector(zoomOut:)
                                                        keyEquivalent:@"-"];
    [zoomOutItem setTarget:target];
    NSMenuItem *actualSizeItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Actual Size"
                                                                  action:@selector(zoomToActualSize:)
                                                           keyEquivalent:@"0"];
    [actualSizeItem setTarget:target];

#if !defined(GNUSTEP)
    // AppKit retitles these (Hide Toolbar, Exit Full Screen) as they apply.
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *toolbarItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Show Toolbar"
                                                                 action:@selector(toggleToolbarShown:)
                                                          keyEquivalent:@"t"];
    [toolbarItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
    [toolbarItem setTarget:nil];
    NSMenuItem *fullScreenItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Enter Full Screen"
                                                                    action:@selector(toggleFullScreen:)
                                                             keyEquivalent:@"f"];
    [fullScreenItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagControl)];
    [fullScreenItem setTarget:nil];
#endif

    [viewMenuItem setSubmenu:viewMenu];

#if !defined(GNUSTEP)
    OMDAddMacWindowAndHelpMenus(menubar, appName, target);
    OMDUseEllipsisCharacters(menubar);
#endif

    return menubar;
}

@end
