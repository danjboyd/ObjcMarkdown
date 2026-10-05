// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDMainMenu.h"
#import "OMDViewerDiagnostics.h"

@interface OMDMainMenu ()
- (NSMenu *)buildMenubarWithTarget:(id)target;
@end

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

#if defined(_WIN32)
    NSMenuItem *fileMenuItemWin = [[[NSMenuItem alloc] initWithTitle:@"File"
                                                              action:NULL
                                                       keyEquivalent:@""] autorelease];
    [menubar addItem:fileMenuItemWin];

    NSMenu *fileMenuWin = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    [[fileMenuWin addItemWithTitle:@"Open Markdown..."
                            action:@selector(openDocument:)
                     keyEquivalent:@"o"] setTarget:target];
    [[fileMenuWin addItemWithTitle:@"New Window"
                            action:@selector(newWindow:)
                     keyEquivalent:@"n"] setTarget:target];
    NSMenuItem *openRecentItemWin = (NSMenuItem *)[fileMenuWin addItemWithTitle:@"Open Recent"
                                                                           action:NULL
                                                                    keyEquivalent:@""];
    NSMenu *openRecentMenuWin = [[[NSMenu alloc] initWithTitle:@"Open Recent"] autorelease];
    [openRecentMenuWin setAutoenablesItems:NO];
    [openRecentMenuWin setDelegate:target];
    [openRecentItemWin setSubmenu:openRecentMenuWin];
    _openRecentMenu = [openRecentMenuWin retain];
    [[fileMenuWin addItemWithTitle:@"Import..."
                            action:@selector(importDocument:)
                     keyEquivalent:@"I"] setTarget:target];
    [fileMenuWin addItem:[NSMenuItem separatorItem]];
    [[fileMenuWin addItemWithTitle:@"Save"
                            action:@selector(saveDocument:)
                     keyEquivalent:@"s"] setTarget:target];
    [[fileMenuWin addItemWithTitle:@"Save Markdown As..."
                            action:@selector(saveDocumentAsMarkdown:)
                     keyEquivalent:@"S"] setTarget:target];
    [[fileMenuWin addItemWithTitle:@"Refresh"
                            action:@selector(reloadDocumentFromDisk:)
                     keyEquivalent:@"r"] setTarget:target];
    [fileMenuWin addItem:[NSMenuItem separatorItem]];
    [[fileMenuWin addItemWithTitle:@"Print..."
                            action:@selector(printDocument:)
                     keyEquivalent:@"p"] setTarget:target];
    [fileMenuWin addItem:[NSMenuItem separatorItem]];
    [[fileMenuWin addItemWithTitle:@"Close"
                            action:@selector(performClose:)
                     keyEquivalent:@"w"] setTarget:nil];
    [fileMenuItemWin setSubmenu:fileMenuWin];

    NSMenuItem *editMenuItemWin = [[[NSMenuItem alloc] initWithTitle:@"Edit"
                                                               action:NULL
                                                        keyEquivalent:@""] autorelease];
    [menubar addItem:editMenuItemWin];

    NSMenu *editMenuWin = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
    [[editMenuWin addItemWithTitle:@"Undo"
                            action:@selector(undo:)
                     keyEquivalent:@"z"] setTarget:target];
    [[editMenuWin addItemWithTitle:@"Redo"
                            action:@selector(redo:)
                     keyEquivalent:@"Z"] setTarget:target];
    [editMenuWin addItem:[NSMenuItem separatorItem]];
    [[editMenuWin addItemWithTitle:@"Cut"
                            action:@selector(cut:)
                     keyEquivalent:@"x"] setTarget:nil];
    [[editMenuWin addItemWithTitle:@"Copy"
                            action:@selector(copy:)
                     keyEquivalent:@"c"] setTarget:nil];
    [[editMenuWin addItemWithTitle:@"Paste"
                            action:@selector(paste:)
                     keyEquivalent:@"v"] setTarget:nil];
    [editMenuWin addItem:[NSMenuItem separatorItem]];
    [[editMenuWin addItemWithTitle:@"Select All"
                            action:@selector(selectAll:)
                     keyEquivalent:@"a"] setTarget:nil];
    [editMenuItemWin setSubmenu:editMenuWin];

    NSMenuItem *viewMenuItemWin = [[[NSMenuItem alloc] initWithTitle:@"View"
                                                               action:NULL
                                                        keyEquivalent:@""] autorelease];
    [menubar addItem:viewMenuItemWin];

    NSMenu *viewMenuWin = [[[NSMenu alloc] initWithTitle:@"View"] autorelease];
    [[viewMenuWin addItemWithTitle:@"Reading Mode"
                         action:@selector(setReadMode:)
                  keyEquivalent:@"1"] setTarget:target];
    [[viewMenuWin addItemWithTitle:@"Edit Mode"
                         action:@selector(setEditMode:)
                  keyEquivalent:@"2"] setTarget:target];
    [[viewMenuWin addItemWithTitle:@"Split Mode"
                         action:@selector(setSplitMode:)
                  keyEquivalent:@"3"] setTarget:target];
    NSMenuItem *showExplorerItem = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Show Explorer"
                                                                   action:@selector(toggleExplorerSidebar:)
                                                            keyEquivalent:@""];
    [showExplorerItem setTarget:target];
    NSMenuItem *showOutlineItem = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Show Outline"
                                                                  action:@selector(toggleOutline:)
                                                           keyEquivalent:@"O"];
    [showOutlineItem setTarget:target];
    NSMenuItem *showFormattingBarItem = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Show Formatting Bar"
                                                                        action:@selector(toggleFormattingBar:)
                                                                 keyEquivalent:@""];
    [showFormattingBarItem setTarget:target];
    [[viewMenuWin addItemWithTitle:@"Full-Width Preview"
                            action:@selector(togglePreviewFullWidth:)
                     keyEquivalent:@""] setTarget:target];
    [viewMenuWin addItem:[NSMenuItem separatorItem]];
    NSMenuItem *zoomInItemWin = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Zoom In"
                                                                    action:@selector(zoomIn:)
                                                             keyEquivalent:@"="];
    [zoomInItemWin setKeyEquivalentModifierMask:NSControlKeyMask];
    [zoomInItemWin setTarget:target];
    NSMenuItem *zoomOutItemWin = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Zoom Out"
                                                                     action:@selector(zoomOut:)
                                                              keyEquivalent:@"-"];
    [zoomOutItemWin setKeyEquivalentModifierMask:NSControlKeyMask];
    [zoomOutItemWin setTarget:target];
    NSMenuItem *actualSizeItemWin = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Actual Size"
                                                                        action:@selector(zoomToActualSize:)
                                                                 keyEquivalent:@"0"];
    [actualSizeItemWin setKeyEquivalentModifierMask:NSControlKeyMask];
    [actualSizeItemWin setTarget:target];
    [viewMenuItemWin setSubmenu:viewMenuWin];

    return menubar;
#endif

    NSMenuItem *fileMenuItem = [[[NSMenuItem alloc] initWithTitle:@"File"
                                                           action:NULL
                                                    keyEquivalent:@""] autorelease];
    [menubar addItem:fileMenuItem];

    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    NSMenuItem *openItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Open Markdown..."
                                                             action:@selector(openDocument:)
                                                      keyEquivalent:@"o"];
    [openItem setTarget:target];

    NSMenuItem *newWindowItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"New Window"
                                                                   action:@selector(newWindow:)
                                                            keyEquivalent:@"n"];
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
    NSMenuItem *toggleBoldItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Toggle Bold"
                                                                    action:@selector(toggleBoldFormatting:)
                                                             keyEquivalent:@"b"];
    [toggleBoldItem setTarget:target];
    [toggleBoldItem setKeyEquivalentModifierMask:NSControlKeyMask];
    NSMenuItem *toggleItalicItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Toggle Italic"
                                                                      action:@selector(toggleItalicFormatting:)
                                                               keyEquivalent:@"i"];
    [toggleItalicItem setTarget:target];
    [toggleItalicItem setKeyEquivalentModifierMask:NSControlKeyMask];
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

    NSMenuItem *zoomInItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Zoom In"
                                                              action:@selector(zoomIn:)
                                                       keyEquivalent:@"="];
    [zoomInItem setKeyEquivalentModifierMask:NSControlKeyMask];
    [zoomInItem setTarget:target];
    NSMenuItem *zoomOutItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Zoom Out"
                                                               action:@selector(zoomOut:)
                                                        keyEquivalent:@"-"];
    [zoomOutItem setKeyEquivalentModifierMask:NSControlKeyMask];
    [zoomOutItem setTarget:target];
    NSMenuItem *actualSizeItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Actual Size"
                                                                  action:@selector(zoomToActualSize:)
                                                           keyEquivalent:@"0"];
    [actualSizeItem setKeyEquivalentModifierMask:NSControlKeyMask];
    [actualSizeItem setTarget:target];

    [viewMenuItem setSubmenu:viewMenu];

    return menubar;
}

@end
