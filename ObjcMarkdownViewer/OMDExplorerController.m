// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDExplorerController.h"
#import "OMDExplorerRoot.h"
#import "OMDExplorerTree.h"
#import "OMDExternalTools.h"
#import "OMDLayoutMetrics.h"
#import "OMDPanelSelection.h"
#import "OMDTextFileSupport.h"
#import "OMDViewerDefaults.h"
#import "OMDViewerImages.h"

#include <math.h>

static const CGFloat OMDExplorerListMinFontSize = 10.0;
static const CGFloat OMDExplorerListMaxFontSize = 20.0;
static const CGFloat OMDExplorerListMinimumRowHeight = 20.0;
static const CGFloat OMDExplorerIconSize = 16.0;
static const CGFloat OMDExplorerIconGap = 5.0;
static const NSUInteger OMDExplorerRecentRootLimit = 8;
// How much of a large tree a filter searches, and how many files it shows.
static const NSUInteger OMDExplorerFilterVisitLimit = 100000;
static const NSUInteger OMDExplorerFilterMatchLimit = 2000;
static const NSTimeInterval OMDExplorerFilterDelay = 0.15;

// Tags of the root menu's items.
typedef NS_ENUM(NSInteger, OMDExplorerRootMenuTag) {
    OMDExplorerRootMenuTagRoot = 0,
    OMDExplorerRootMenuTagOpenFolder = 1,
    OMDExplorerRootMenuTagClearRecent = 2
};

static NSString *OMDExplorerIconNameForKind(OMDExplorerFileKind kind)
{
    switch (kind) {
        case OMDExplorerFileKindFolder:
            return @"omd-folder-symbolic";
        case OMDExplorerFileKindMarkdown:
            return @"omd-text-x-markdown-symbolic";
        case OMDExplorerFileKindImportable:
            return @"omd-document-import-symbolic";
        default:
            return @"omd-text-x-generic-symbolic";
    }
}

// Draws an icon the way buttons do, through -[NSButtonCell
// drawImage:withFrame:inView:], so a theme that tints symbolic images in
// buttons tints these too.
static NSButtonCell *OMDExplorerIconDrawingCell(void)
{
    static NSButtonCell *cell = nil;
    if (cell == nil) {
        cell = [[NSButtonCell alloc] initImageCell:nil];
        [cell setBordered:NO];
        [cell setImagePosition:NSImageOnly];
        [cell setImageDimsWhenDisabled:YES];
    }
    return cell;
}

// A name with its file-kind icon in front.
@interface OMDExplorerCell : NSTextFieldCell
{
    NSImage *_icon;
    BOOL _iconDimmed;
}
- (void)setIcon:(NSImage *)icon dimmed:(BOOL)dimmed;
@end

@implementation OMDExplorerCell

- (id)copyWithZone:(NSZone *)zone
{
    OMDExplorerCell *copy = [super copyWithZone:zone];
    copy->_icon = [_icon retain];
    return copy;
}

- (void)dealloc
{
    [_icon release];
    [super dealloc];
}

- (void)setIcon:(NSImage *)icon dimmed:(BOOL)dimmed
{
    if (icon != _icon) {
        [_icon release];
        _icon = [icon retain];
    }
    _iconDimmed = dimmed;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSRect iconFrame = NSZeroRect;
    NSRect textFrame = NSZeroRect;
    NSDivideRect(cellFrame, &iconFrame, &textFrame, OMDExplorerIconSize + OMDExplorerIconGap, NSMinXEdge);
    iconFrame.size.width = OMDExplorerIconSize;
    if (_icon != nil) {
        NSButtonCell *iconCell = OMDExplorerIconDrawingCell();
        [iconCell setEnabled:!_iconDimmed];
        [iconCell drawImage:_icon withFrame:iconFrame inView:controlView];
    }
    [super drawInteriorWithFrame:textFrame inView:controlView];
}

@end

@interface NSObject (OMDExplorerContextMenu)
- (NSMenu *)explorerContextMenuForRow:(NSInteger)row;
@end

// Return opens the selected file, or opens or closes the selected folder.
// A right click, the Menu key or Shift-F10 shows the row's context menu.
@interface OMDExplorerOutlineView : NSOutlineView
@end

@implementation OMDExplorerOutlineView

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSInteger row = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    if (row < 0 || ![[self target] respondsToSelector:@selector(explorerContextMenuForRow:)]) {
        return nil;
    }
    // Select it without opening it (no action is sent).
    [self selectRow:row byExtendingSelection:NO];
    return [[self target] explorerContextMenuForRow:row];
}

- (void)showContextMenuForSelectedRow
{
    NSInteger row = [self selectedRow];
    if (row < 0 || ![[self target] respondsToSelector:@selector(explorerContextMenuForRow:)]) {
        return;
    }
    NSMenu *menu = [[self target] explorerContextMenuForRow:row];
    if (menu == nil) {
        return;
    }
    [self scrollRowToVisible:row];
    NSRect rowRect = [self rectOfRow:row];
    NSPoint location = [self convertPoint:NSMakePoint(NSMinX(rowRect) + 24.0, NSMaxY(rowRect)) toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:NSRightMouseDown
                                        location:location
                                   modifierFlags:0
                                       timestamp:[[NSApp currentEvent] timestamp]
                                    windowNumber:[[self window] windowNumber]
                                         context:nil
                                     eventNumber:0
                                      clickCount:1
                                        pressure:1.0];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)keyDown:(NSEvent *)event
{
    NSString *characters = [event charactersIgnoringModifiers];
    if ([characters length] == 1) {
        unichar character = [characters characterAtIndex:0];
        if (character == NSCarriageReturnCharacter || character == NSEnterCharacter ||
            character == NSNewlineCharacter) {
            [NSApp sendAction:@selector(explorerOpenSelection:) to:[self target] from:self];
            return;
        }
        if (character == NSMenuFunctionKey ||
            (character == NSF10FunctionKey && ([event modifierFlags] & NSShiftKeyMask) != 0)) {
            [self showContextMenuForSelectedRow];
            return;
        }
    }
    [super keyDown:event];
}

@end

@interface OMDExplorerController ()
- (void)setupExplorerSidebar;
- (void)layoutExplorerControls;
- (void)showRoot:(NSString *)root;
- (void)showRoot:(NSString *)root remember:(BOOL)remember;
- (NSArray *)recentRoots;
- (void)rebuildRootPopup;
- (void)explorerRootPopupChanged:(id)sender;
- (void)chooseRootByHand:(NSString *)root;
- (void)openFolderAsRoot;
- (void)revealDocumentExpandingFolders:(BOOL)expand;
- (void)reloadOutlineKeepingSelection;
- (void)applyExplorerListFontPreference;
- (BOOL)isExplorerShowHiddenFilesEnabled;
- (void)setExplorerShowHiddenFilesEnabled:(BOOL)enabled;
- (void)explorerShowHiddenFilesChanged:(id)sender;
- (void)explorerItemClicked:(id)sender;
- (void)explorerItemDoubleClicked:(id)sender;
- (void)explorerOpenSelection:(id)sender;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (OMDExplorerNode *)explorerClickedNode;
- (void)cancelPendingExplorerClick;
- (void)openPendingExplorerClick;
- (void)toggleExplorerFolder:(OMDExplorerNode *)node;
- (NSMenu *)explorerContextMenuForRow:(NSInteger)row;
- (void)explorerContextOpen:(id)sender;
- (void)explorerContextOpenInNewTab:(id)sender;
- (void)explorerContextToggleFolder:(id)sender;
- (void)explorerContextReveal:(id)sender;
- (void)explorerContextOpenFolder:(id)sender;
- (void)explorerContextUseAsRoot:(id)sender;
- (void)explorerContextCopyPath:(id)sender;
- (void)explorerContextCopyRelativePath:(id)sender;
- (void)openFirstShownFile;
- (BOOL)isExplorerMarkdownOnlyEnabled;
- (BOOL)isExplorerFiltering;
- (NSString *)explorerFilterText;
- (void)explorerFilterChanged:(id)sender;
- (void)explorerMarkdownOnlyChanged:(id)sender;
- (void)scheduleExplorerFilter;
- (void)applyExplorerFilter;
- (void)showExplorerFilterResult:(NSArray *)files complete:(BOOL)complete restoreExpansion:(BOOL)restore;
- (void)setExplorerFilterStatus:(NSString *)status;
- (NSArray *)expandedExplorerNodes;
- (void)restoreExplorerExpansion;
- (void)refreshExplorerTree;
@end

@implementation OMDExplorerController

- (instancetype)initWithDelegate:(id<OMDExplorerControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_explorerPendingClickNode release];
    [_explorerRootPopup release];
    [_explorerFilterField setDelegate:nil];
    [_explorerFilterField release];
    [_explorerMarkdownOnlyButton release];
    [_explorerShowHiddenFilesButton release];
    [_explorerFilterStatusLabel release];
    [_explorerVisiblePaths release];
    [_explorerExpandedBeforeFilter release];
    [_explorerOutlineView setDelegate:nil];
    [_explorerOutlineView setDataSource:nil];
    [_explorerOutlineView release];
    [_explorerScrollView release];
    [_explorerRootNode release];
    [_explorerLocalRootPath release];
    [_explorerDocumentPath release];
    [super dealloc];
}

- (void)setupInContainer:(NSView *)container
{
    _containerView = container;
    [self setupExplorerSidebar];
}

- (NSScrollView *)scrollView
{
    return _explorerScrollView;
}

- (void)applyLayoutDensity
{
    NSFont *labelFont = OMDChromeSmallFont();
    [_explorerShowHiddenFilesButton setFont:labelFont];
    [_explorerMarkdownOnlyButton setFont:labelFont];
    [_explorerFilterStatusLabel setFont:labelFont];
    [self applyExplorerListFontPreference];
    [self layoutExplorerControls];
}

- (NSString *)explorerLocalRootPathPreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *stored = [defaults stringForKey:OMDExplorerLocalRootPathDefaultsKey];
    NSString *resolved = OMDTrimmedString(stored);
    if ([resolved length] == 0) {
        resolved = NSHomeDirectory();
    } else {
        resolved = [resolved stringByExpandingTildeInPath];
    }

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolved isDirectory:&isDirectory] || !isDirectory) {
        resolved = NSHomeDirectory();
    }
    if (resolved == nil || [resolved length] == 0) {
        resolved = @"/";
    }
    return resolved;
}

- (void)setExplorerLocalRootPathPreference:(NSString *)path
{
    NSString *resolved = OMDTrimmedString(path);
    if ([resolved length] == 0) {
        resolved = NSHomeDirectory();
    }
    resolved = [resolved stringByExpandingTildeInPath];

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:resolved isDirectory:&isDirectory] || !isDirectory) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Invalid local root folder"];
        [alert setInformativeText:@"Choose an existing directory for the local explorer root."];
        [alert runModal];
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:resolved forKey:OMDExplorerLocalRootPathDefaultsKey];
    if (OMDExplorerRootForDocumentPath(_explorerDocumentPath) == nil) {
        [self showRoot:resolved];
    }
}

- (void)showRoot:(NSString *)root
{
    [self showRoot:root remember:YES];
}

// remember adds the root to the root menu's recent folders.
- (void)showRoot:(NSString *)root remember:(BOOL)remember
{
    if ([root isEqualToString:_explorerLocalRootPath]) {
        return;
    }
    [_explorerLocalRootPath release];
    _explorerLocalRootPath = [root copy];
    [self cancelPendingExplorerClick];
    [_explorerRootNode release];
    _explorerRootNode = [[OMDExplorerNode alloc] initWithPath:root isDirectory:YES parent:nil];
    if (remember) {
        NSArray *recent = OMDExplorerRecentRootsAdding([self recentRoots], root, OMDExplorerRecentRootLimit);
        [[NSUserDefaults standardUserDefaults] setObject:recent forKey:OMDExplorerRecentRootsDefaultsKey];
    }
    if (_explorerOutlineView != nil) {
        [self rebuildRootPopup];
        [_explorerOutlineView reloadData];
        [_explorerOutlineView scrollRowToVisible:0];
        if ([self isExplorerFiltering]) {
            [self applyExplorerFilter];
        }
    }
}

// The remembered roots that still exist, most recent first.
- (NSArray *)recentRoots
{
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:OMDExplorerRecentRootsDefaultsKey];
    NSMutableArray *roots = [NSMutableArray array];
    if (![stored isKindOfClass:[NSArray class]]) {
        return roots;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (id path in (NSArray *)stored) {
        BOOL isDirectory = NO;
        if ([path isKindOfClass:[NSString class]] &&
            [fileManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            [roots addObject:path];
        }
    }
    return roots;
}

// The root menu: the current root (checked) among the recent ones, then
// Open Folder... and, with more than one root, Clear Recent.
- (void)rebuildRootPopup
{
    if (_explorerRootPopup == nil) {
        return;
    }
    NSArray *roots = OMDExplorerRecentRootsAdding([self recentRoots], _explorerLocalRootPath, OMDExplorerRecentRootLimit);
    NSArray *titles = OMDExplorerRootMenuTitles(roots);
    NSMenu *menu = [_explorerRootPopup menu];
    [_explorerRootPopup removeAllItems];
    NSUInteger index = 0;
    for (; index < [roots count]; index++) {
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:index]
                                                       action:NULL
                                                keyEquivalent:@""] autorelease];
        [item setTag:OMDExplorerRootMenuTagRoot];
        [item setRepresentedObject:[roots objectAtIndex:index]];
        if ([item respondsToSelector:@selector(setToolTip:)]) {
            [item setToolTip:[roots objectAtIndex:index]];
        }
        [menu addItem:item];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *openItem = [[[NSMenuItem alloc] initWithTitle:@"Open Folder..." action:NULL keyEquivalent:@""] autorelease];
    [openItem setTag:OMDExplorerRootMenuTagOpenFolder];
    [menu addItem:openItem];
    // Only with something to clear: GNUstep lets a pop-up select a
    // disabled item.
    if ([roots count] > 1) {
        NSMenuItem *clearItem = [[[NSMenuItem alloc] initWithTitle:@"Clear Recent" action:NULL keyEquivalent:@""] autorelease];
        [clearItem setTag:OMDExplorerRootMenuTagClearRecent];
        [menu addItem:clearItem];
    }

    [_explorerRootPopup selectItemAtIndex:0];
    [_explorerRootPopup setToolTip:_explorerLocalRootPath];
}

- (void)explorerRootPopupChanged:(id)sender
{
    (void)sender;
    NSMenuItem *item = (NSMenuItem *)[_explorerRootPopup selectedItem];
    NSInteger tag = (item != nil ? [item tag] : OMDExplorerRootMenuTagRoot);
    if (tag == OMDExplorerRootMenuTagOpenFolder) {
        [self rebuildRootPopup];
        // Once the menu has closed, not from inside its tracking.
        [self performSelector:@selector(openFolderAsRoot) withObject:nil afterDelay:0.0];
        return;
    }
    if (tag == OMDExplorerRootMenuTagClearRecent) {
        NSArray *current = (_explorerLocalRootPath != nil ? [NSArray arrayWithObject:_explorerLocalRootPath] : [NSArray array]);
        [[NSUserDefaults standardUserDefaults] setObject:current forKey:OMDExplorerRecentRootsDefaultsKey];
        [self rebuildRootPopup];
        return;
    }
    NSString *root = [item representedObject];
    if ([root isKindOfClass:[NSString class]]) {
        [self chooseRootByHand:root];
    } else {
        [self rebuildRootPopup];
    }
}

- (void)chooseRootByHand:(NSString *)root
{
    NSString *documentRoot = OMDExplorerRootForDocumentPath(_explorerDocumentPath);
    _explorerRootChosenByHand = !(documentRoot != nil && [documentRoot isEqualToString:root]);
    [self showRoot:root];
    [self rebuildRootPopup];
    [self revealDocumentExpandingFolders:YES];
}

- (void)openFolderAsRoot
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setTitle:@"Open Folder in Explorer"];
    [panel setPrompt:@"Open"];
    if ([_explorerLocalRootPath length] > 0) {
        [panel setDirectory:_explorerLocalRootPath];
    }
    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return;
    }
    NSArray *paths = OMDSelectedPathsFromOpenPanel(panel);
    NSString *path = ([paths count] > 0 ? [[paths objectAtIndex:0] stringByStandardizingPath] : nil);
    BOOL isDirectory = NO;
    if (path != nil && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
        [self chooseRootByHand:path];
    }
}

- (void)setDocumentPath:(NSString *)path
{
    NSString *normalized = ([path length] > 0 ? [path stringByStandardizingPath] : nil);
    if (normalized == _explorerDocumentPath || [normalized isEqualToString:_explorerDocumentPath]) {
        return;
    }
    [_explorerDocumentPath release];
    _explorerDocumentPath = [normalized copy];

    // An untitled document leaves the explorer where it is.
    NSString *root = OMDExplorerRootForDocumentPath(_explorerDocumentPath);
    if (root != nil && !_explorerRootChosenByHand) {
        [self showRoot:root];
    }
    [self revealDocumentExpandingFolders:YES];
}

// Selects the open document's row. With expand, opens the folders above
// it and scrolls to it, reading its folder again if it is new (just saved
// there); otherwise only selects it if it is already visible.
- (void)revealDocumentExpandingFolders:(BOOL)expand
{
    if (_explorerOutlineView == nil) {
        return;
    }
    OMDExplorerNode *node = nil;
    if (_explorerDocumentPath != nil && _explorerRootNode != nil) {
        node = [_explorerRootNode descendantForPath:_explorerDocumentPath];
        if (node == nil && expand && [_explorerRootNode hasLoadedChildren]) {
            [_explorerRootNode reloadChildren];
            [_explorerOutlineView reloadData];
            node = [_explorerRootNode descendantForPath:_explorerDocumentPath];
        }
    }
    if (node == nil || node == _explorerRootNode) {
        [_explorerOutlineView deselectAll:nil];
        return;
    }

    if (expand) {
        NSMutableArray *ancestors = [NSMutableArray array];
        for (OMDExplorerNode *parent = [node parent];
             parent != nil && parent != _explorerRootNode;
             parent = [parent parent]) {
            [ancestors insertObject:parent atIndex:0];
        }
        for (OMDExplorerNode *ancestor in ancestors) {
            [_explorerOutlineView expandItem:ancestor];
        }
    }
    NSInteger row = [_explorerOutlineView rowForItem:node];
    if (row < 0) {
        [_explorerOutlineView deselectAll:nil];
        return;
    }
    [_explorerOutlineView selectRow:row byExtendingSelection:NO];
    if (expand) {
        [_explorerOutlineView scrollRowToVisible:row];
    }
}

- (NSUInteger)explorerMaxOpenFileSizeBytes
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:OMDExplorerMaxFileSizeMBDefaultsKey];
    NSInteger megabytes = 5;
    if ([value respondsToSelector:@selector(integerValue)]) {
        megabytes = [value integerValue];
    }
    if (megabytes < 1) {
        megabytes = 1;
    }
    if (megabytes > 200) {
        megabytes = 200;
    }
    return (NSUInteger)megabytes * 1024U * 1024U;
}

- (void)setExplorerMaxOpenFileSizeMBPreference:(NSUInteger)megabytes
{
    if (megabytes < 1) {
        megabytes = 1;
    }
    if (megabytes > 200) {
        megabytes = 200;
    }
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)megabytes
                                               forKey:OMDExplorerMaxFileSizeMBDefaultsKey];
}

- (CGFloat)explorerListFontSizePreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:OMDExplorerListFontSizeDefaultsKey];
    CGFloat fontSize = OMDExplorerListDefaultFontSize;
    if ([value respondsToSelector:@selector(doubleValue)]) {
        fontSize = (CGFloat)[value doubleValue];
    }
    if (fontSize < OMDExplorerListMinFontSize) {
        fontSize = OMDExplorerListMinFontSize;
    }
    if (fontSize > OMDExplorerListMaxFontSize) {
        fontSize = OMDExplorerListMaxFontSize;
    }
    return fontSize;
}

- (void)setExplorerListFontSizePreference:(CGFloat)fontSize
{
    if (fontSize < OMDExplorerListMinFontSize) {
        fontSize = OMDExplorerListMinFontSize;
    }
    if (fontSize > OMDExplorerListMaxFontSize) {
        fontSize = OMDExplorerListMaxFontSize;
    }
    [[NSUserDefaults standardUserDefaults] setDouble:fontSize forKey:OMDExplorerListFontSizeDefaultsKey];
    [self applyExplorerListFontPreference];
}

- (BOOL)isExplorerShowHiddenFilesEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:OMDExplorerShowHiddenFilesDefaultsKey];
}

- (void)setExplorerShowHiddenFilesEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:OMDExplorerShowHiddenFilesDefaultsKey];
}

- (void)applyExplorerListFontPreference
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    if (_explorerOutlineView == nil) {
        return;
    }

    CGFloat fontSize = [self explorerListFontSizePreference];
    NSFont *font = [NSFont systemFontOfSize:fontSize];
    if (font == nil) {
        font = [NSFont systemFontOfSize:OMDExplorerListDefaultFontSize];
    }
    CGFloat rowHeight = ceil(MAX(fontSize, OMDExplorerIconSize) + metrics.explorerRowPadding);
    if (rowHeight < OMDExplorerListMinimumRowHeight) {
        rowHeight = OMDExplorerListMinimumRowHeight;
    }
    [_explorerOutlineView setRowHeight:rowHeight];
    [[[_explorerOutlineView outlineTableColumn] dataCell] setFont:font];
    [self reloadOutlineKeepingSelection];
}

// Reloading the outline view leaves its selection on a row number, which
// may now be another item.
- (void)reloadOutlineKeepingSelection
{
    [_explorerOutlineView reloadData];
    [self revealDocumentExpandingFolders:NO];
}

- (void)setupExplorerSidebar
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    if (_containerView == nil) {
        return;
    }

    NSRect bounds = [_containerView bounds];
    NSFont *labelFont = OMDChromeSmallFont();

    _explorerRootPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                         NSHeight(bounds) - 34,
                                                                         100,
                                                                         metrics.explorerControlHeight)
                                                    pullsDown:NO];
    [_explorerRootPopup setTarget:self];
    [_explorerRootPopup setAction:@selector(explorerRootPopupChanged:)];
    [_explorerRootPopup setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerRootPopup];

    _explorerFilterField = [[NSSearchField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                           NSHeight(bounds) - 64,
                                                                           100,
                                                                           metrics.explorerControlHeight)];
    [[_explorerFilterField cell] setPlaceholderString:@"Filter files"];
    [_explorerFilterField setToolTip:@"Show the files whose names contain this text"];
    [_explorerFilterField setTarget:self];
    [_explorerFilterField setAction:@selector(explorerFilterChanged:)];
    [_explorerFilterField setDelegate:self];
    [_explorerFilterField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerFilterField];

    _explorerMarkdownOnlyButton = [[NSButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                             NSHeight(bounds) - 88,
                                                                             100,
                                                                             metrics.explorerMinorControlHeight)];
    [_explorerMarkdownOnlyButton setButtonType:NSSwitchButton];
    [_explorerMarkdownOnlyButton setTitle:@"Markdown only"];
    [_explorerMarkdownOnlyButton setToolTip:@"Show only Markdown files and the folders that hold them"];
    [_explorerMarkdownOnlyButton setFont:labelFont];
    [_explorerMarkdownOnlyButton setState:([self isExplorerMarkdownOnlyEnabled] ? NSOnState : NSOffState)];
    [_explorerMarkdownOnlyButton setTarget:self];
    [_explorerMarkdownOnlyButton setAction:@selector(explorerMarkdownOnlyChanged:)];
    [_explorerMarkdownOnlyButton setAutoresizingMask:NSViewMinYMargin];
    [_containerView addSubview:_explorerMarkdownOnlyButton];

    _explorerFilterStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                               NSHeight(bounds) - 110,
                                                                               100,
                                                                               16)];
    [_explorerFilterStatusLabel setBezeled:NO];
    [_explorerFilterStatusLabel setEditable:NO];
    [_explorerFilterStatusLabel setSelectable:NO];
    [_explorerFilterStatusLabel setDrawsBackground:NO];
    [_explorerFilterStatusLabel setTextColor:[NSColor secondaryLabelColor]];
    [_explorerFilterStatusLabel setFont:labelFont];
    [_explorerFilterStatusLabel setHidden:YES];
    [_explorerFilterStatusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerFilterStatusLabel];

    _explorerShowHiddenFilesButton = [[NSButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                                NSHeight(bounds) - 88,
                                                                                100,
                                                                                metrics.explorerMinorControlHeight)];
    [_explorerShowHiddenFilesButton setButtonType:NSSwitchButton];
    [_explorerShowHiddenFilesButton setTitle:@"Hidden files"];
    [_explorerShowHiddenFilesButton setToolTip:@"Show files and folders whose names start with a dot"];
    [_explorerShowHiddenFilesButton setFont:labelFont];
    [_explorerShowHiddenFilesButton setState:([self isExplorerShowHiddenFilesEnabled] ? NSOnState : NSOffState)];
    [_explorerShowHiddenFilesButton setTarget:self];
    [_explorerShowHiddenFilesButton setAction:@selector(explorerShowHiddenFilesChanged:)];
    [_explorerShowHiddenFilesButton setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerShowHiddenFilesButton];

    // Not 0 wide while the sidebar is collapsed: tiling would size the clip
    // view below zero (#78). -layoutExplorerControls sets the real frame.
    _explorerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 10, MAX(NSWidth(bounds), 100.0), 80)];
    [_explorerScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_explorerScrollView setHasVerticalScroller:YES];
    [_explorerScrollView setHasHorizontalScroller:NO];
    [_explorerScrollView setBorderType:NSBezelBorder];

    _explorerOutlineView = [[OMDExplorerOutlineView alloc] initWithFrame:[_explorerScrollView bounds]];
    [_explorerOutlineView setHeaderView:nil];
    [_explorerOutlineView setAllowsEmptySelection:YES];
    [_explorerOutlineView setAllowsMultipleSelection:NO];
    [_explorerOutlineView setRowHeight:OMDExplorerListMinimumRowHeight];
    [_explorerOutlineView setIndentationPerLevel:14.0];
    [_explorerOutlineView setAutoresizesOutlineColumn:NO];
    [_explorerOutlineView setTarget:self];
    [_explorerOutlineView setAction:@selector(explorerItemClicked:)];
    [_explorerOutlineView setDoubleAction:@selector(explorerItemDoubleClicked:)];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"ExplorerName"] autorelease];
    [column setEditable:NO];
    OMDExplorerCell *cell = [[[OMDExplorerCell alloc] initTextCell:@""] autorelease];
    [cell setEditable:NO];
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
    [column setDataCell:cell];
    [column setWidth:NSWidth([_explorerScrollView bounds]) - 2.0];
    [_explorerOutlineView addTableColumn:column];
    [_explorerOutlineView setOutlineTableColumn:column];
    [_explorerOutlineView setDataSource:self];
    [_explorerOutlineView setDelegate:self];
    [_explorerScrollView setDocumentView:_explorerOutlineView];
    [_delegate applyScrollSpeedPreference];
    [_containerView addSubview:_explorerScrollView];
    [self applyExplorerListFontPreference];

    // A stand-in until the window says which document it shows.
    if (_explorerLocalRootPath == nil) {
        [self showRoot:[self explorerLocalRootPathPreference] remember:NO];
    }
    [self rebuildRootPopup];
    if ([self isExplorerMarkdownOnlyEnabled]) {
        [self applyExplorerFilter];
    }

    // Files change behind the app's back; look again when it comes back.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidBecomeKey:)
                                                 name:NSWindowDidBecomeKeyNotification
                                               object:nil];
    // Lay the controls out for each new sidebar size rather than leave it
    // to autoresizing, which can't bring them back from a collapsed sidebar
    // and left them wider than it, clipped at its right edge; collapsing,
    // it also shrank them to negative widths (#78).
    [_containerView setAutoresizesSubviews:NO];
    [_containerView setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(containerFrameDidChange:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:_containerView];
    [self layoutExplorerControls];
}

- (void)containerFrameDidChange:(NSNotification *)notification
{
    (void)notification;
    if (NSWidth([_containerView bounds]) >= 1.0 && ![_containerView isHidden]) {
        [self layoutExplorerControls];
    }
}

- (void)layoutExplorerControls
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    [_explorerShowHiddenFilesButton setState:([self isExplorerShowHiddenFilesEnabled] ? NSOnState : NSOffState)];

    NSRect bounds = [_containerView bounds];
    // Collapsed (0 wide while the explorer is hidden, or before the window
    // has its size), the controls would get negative widths (#78). The
    // container's frame-change notification lays them out once it has room.
    if (NSWidth(bounds) < (metrics.explorerSidePadding * 2.0) + 40.0) {
        return;
    }
    CGFloat wideControlWidth = MAX(1.0, NSWidth(bounds) - (metrics.explorerSidePadding * 2.0));
    CGFloat top = NSHeight(bounds) - metrics.explorerTopPadding;

    [_explorerRootPopup setFrame:NSMakeRect(metrics.explorerSidePadding,
                                            top - metrics.explorerControlHeight,
                                            wideControlWidth,
                                            metrics.explorerControlHeight)];
    [_explorerFilterField setFrame:NSMakeRect(metrics.explorerSidePadding,
                                              NSMinY([_explorerRootPopup frame]) - 6.0 - metrics.explorerControlHeight,
                                              wideControlWidth,
                                              metrics.explorerControlHeight)];
    // The two options side by side under the field.
    CGFloat optionsY = NSMinY([_explorerFilterField frame]) - 6.0 - metrics.explorerMinorControlHeight;
    CGFloat optionWidth = floor((wideControlWidth - 8.0) / 2.0);
    [_explorerMarkdownOnlyButton setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                     optionsY,
                                                     optionWidth,
                                                     metrics.explorerMinorControlHeight)];
    [_explorerShowHiddenFilesButton setFrame:NSMakeRect(metrics.explorerSidePadding + optionWidth + 8.0,
                                                        optionsY,
                                                        wideControlWidth - optionWidth - 8.0,
                                                        metrics.explorerMinorControlHeight)];
    CGFloat controlsBottom = optionsY;
    if (![_explorerFilterStatusLabel isHidden]) {
        [_explorerFilterStatusLabel setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                        optionsY - 4.0 - 16.0,
                                                        wideControlWidth,
                                                        16.0)];
        controlsBottom = NSMinY([_explorerFilterStatusLabel frame]);
    }
    CGFloat scrollBottomInset = 10.0;
    CGFloat scrollTop = controlsBottom - 8.0;
    [_explorerScrollView setFrame:NSMakeRect(MAX(0.0, metrics.explorerSidePadding - 2.0),
                                             scrollBottomInset,
                                             MAX(1.0, wideControlWidth + 4.0),
                                             MAX(1.0, scrollTop - scrollBottomInset))];
    [[_explorerOutlineView outlineTableColumn] setWidth:NSWidth([[_explorerScrollView contentView] bounds])];
}

- (void)reloadExplorerEntries
{
    [self layoutExplorerControls];
    if (_explorerRootNode == nil) {
        [self showRoot:[self explorerLocalRootPathPreference] remember:NO];
    }
    [_explorerRootNode reloadChildren];
    [_explorerOutlineView reloadData];
    [self revealDocumentExpandingFolders:YES];
    if ([self isExplorerFiltering]) {
        [self applyExplorerFilter];
    }
}

// Reads the folders again, and searches again while filtering.
- (void)refreshExplorerTree
{
    [_explorerRootNode reloadChildren];
    if ([self isExplorerFiltering]) {
        [self applyExplorerFilter];
    } else {
        [self reloadOutlineKeepingSelection];
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if ([notification object] != [_containerView window] || ![_explorerRootNode hasLoadedChildren]) {
        return;
    }
    [self refreshExplorerTree];
}

- (void)explorerShowHiddenFilesChanged:(id)sender
{
    (void)sender;
    [self setExplorerShowHiddenFilesEnabled:([_explorerShowHiddenFilesButton state] == NSOnState)];
    [self refreshExplorerTree];
}

- (BOOL)isExplorerMarkdownOnlyEnabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:OMDExplorerMarkdownOnlyDefaultsKey];
}

- (void)explorerMarkdownOnlyChanged:(id)sender
{
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:([_explorerMarkdownOnlyButton state] == NSOnState)
                                            forKey:OMDExplorerMarkdownOnlyDefaultsKey];
    [self applyExplorerFilter];
}

- (NSString *)explorerFilterText
{
    return OMDTrimmedString([_explorerFilterField stringValue]);
}

- (BOOL)isExplorerFiltering
{
    return ([[self explorerFilterText] length] > 0 || [self isExplorerMarkdownOnlyEnabled]);
}

- (void)focusFilterField
{
    if (_explorerFilterField == nil) {
        return;
    }
    [[_explorerFilterField window] makeFirstResponder:_explorerFilterField];
    [_explorerFilterField selectText:nil];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    if ([notification object] == _explorerFilterField) {
        [self scheduleExplorerFilter];
    }
}

- (void)openFirstShownFile
{
    NSInteger row = 0;
    for (; row < [_explorerOutlineView numberOfRows]; row++) {
        OMDExplorerNode *node = [_explorerOutlineView itemAtRow:row];
        if (![node isDirectory]) {
            [_delegate openLocalPath:[node path] inNewTab:NO];
            return;
        }
    }
}

// The search field's own action. GNUstep sends it on every key typed, on
// Return and Escape, and from the clear button, whose clearing doesn't
// reach the field editor while the field is edited (nor does Escape, its
// key equivalent), so the text is cleared here.
- (void)explorerFilterChanged:(id)sender
{
    (void)sender;
    NSEvent *event = [NSApp currentEvent];
    NSText *editor = [_explorerFilterField currentEditor];
    unichar character = 0;
    if ([event type] == NSKeyDown && [[event charactersIgnoringModifiers] length] == 1) {
        character = [[event charactersIgnoringModifiers] characterAtIndex:0];
    }
    if (character == 0x1b) {
        [editor setString:@""];
        [_explorerFilterField setStringValue:@""];
        [self applyExplorerFilter];
        return;
    }
    if (character == NSCarriageReturnCharacter || character == NSEnterCharacter ||
        character == NSNewlineCharacter) {
        _explorerOpenFirstMatchWhenShown = ([[self explorerFilterText] length] > 0);
        [self applyExplorerFilter];
        return;
    }
    if ([event type] == NSKeyDown) {
        [self scheduleExplorerFilter];
        return;
    }
    if (editor != nil && [[[_explorerFilterField cell] stringValue] length] == 0) {
        [editor setString:@""];
    }
    [self applyExplorerFilter];
}

// In the filter field, Return opens the first file shown, Down moves into
// the tree and Escape clears the filter.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
    if (control != _explorerFilterField) {
        return NO;
    }
    if (command == @selector(insertNewline:)) {
        _explorerOpenFirstMatchWhenShown = ([[self explorerFilterText] length] > 0);
        [self applyExplorerFilter];
        return YES;
    }
    if (command == @selector(moveDown:)) {
        if ([_explorerOutlineView numberOfRows] > 0) {
            [[_explorerOutlineView window] makeFirstResponder:_explorerOutlineView];
            if ([_explorerOutlineView selectedRow] < 0) {
                [_explorerOutlineView selectRow:0 byExtendingSelection:NO];
            }
        }
        return YES;
    }
    // Escape: GNUstep's field editor sends complete:, Cocoa's cancelOperation:.
    if (command == @selector(cancelOperation:) || command == @selector(complete:)) {
        if ([[textView string] length] == 0) {
            return NO;
        }
        // The field editor holds the text while the field is edited.
        [textView setString:@""];
        [_explorerFilterField setStringValue:@""];
        [self applyExplorerFilter];
        return YES;
    }
    return NO;
}

- (void)scheduleExplorerFilter
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyExplorerFilter) object:nil];
    [self performSelector:@selector(applyExplorerFilter) withObject:nil afterDelay:OMDExplorerFilterDelay];
}

- (NSArray *)expandedExplorerNodes
{
    NSMutableArray *expanded = [NSMutableArray array];
    NSInteger row = 0;
    for (; row < [_explorerOutlineView numberOfRows]; row++) {
        id item = [_explorerOutlineView itemAtRow:row];
        if ([_explorerOutlineView isItemExpanded:item]) {
            [expanded addObject:item];
        }
    }
    return expanded;
}

// Closes everything, then opens the folders that were open before the
// filter text (in row order, so each parent before its children).
- (void)restoreExplorerExpansion
{
    for (id child in [self childrenOfItem:nil]) {
        if ([_explorerOutlineView isItemExpanded:child]) {
            [_explorerOutlineView collapseItem:child collapseChildren:YES];
        }
    }
    for (id item in _explorerExpandedBeforeFilter) {
        [_explorerOutlineView expandItem:item];
    }
    [_explorerExpandedBeforeFilter release];
    _explorerExpandedBeforeFilter = nil;
}

- (void)applyExplorerFilter
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyExplorerFilter) object:nil];
    if (_explorerOutlineView == nil || _explorerRootNode == nil) {
        return;
    }
    NSString *text = [self explorerFilterText];
    BOOL markdownOnly = [self isExplorerMarkdownOnlyEnabled];
    BOOL textActive = ([text length] > 0);
    BOOL restore = (_explorerTextFilterActive && !textActive);
    if (textActive && !_explorerTextFilterActive) {
        [_explorerExpandedBeforeFilter release];
        _explorerExpandedBeforeFilter = [[self expandedExplorerNodes] retain];
    }
    _explorerTextFilterActive = textActive;
    NSUInteger generation = ++_explorerFilterGeneration;

    if (!textActive) {
        _explorerOpenFirstMatchWhenShown = NO;
    }
    if (!textActive && !markdownOnly) {
        [_explorerVisiblePaths release];
        _explorerVisiblePaths = nil;
        [self setExplorerFilterStatus:nil];
        [_explorerOutlineView reloadData];
        if (restore) {
            [self restoreExplorerExpansion];
        }
        [self revealDocumentExpandingFolders:NO];
        return;
    }

    if (textActive) {
        [self setExplorerFilterStatus:@"Searching..."];
    }
    NSString *root = [[[_explorerRootNode path] copy] autorelease];
    NSString *filter = [[text copy] autorelease];
    BOOL showHidden = [self isExplorerShowHiddenFilesEnabled];
    [self retain];
    [root retain];
    [filter retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        BOOL complete = YES;
        NSArray *files = [OMDExplorerFindFiles(root, filter, showHidden, markdownOnly,
                                               OMDExplorerFilterVisitLimit, OMDExplorerFilterMatchLimit,
                                               &complete) retain];
        // Not dispatch_get_main_queue(): GNUstep's run loop doesn't drain it on Windows.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (generation == _explorerFilterGeneration &&
                [root isEqualToString:[_explorerRootNode path]]) {
                [self showExplorerFilterResult:files complete:complete restoreExpansion:restore];
            }
            [files release];
            [root release];
            [filter release];
            [self release];
        }];
        [pool release];
    });
}

- (void)showExplorerFilterResult:(NSArray *)files complete:(BOOL)complete restoreExpansion:(BOOL)restore
{
    NSString *root = [_explorerRootNode path];
    [_explorerVisiblePaths release];
    _explorerVisiblePaths = [OMDExplorerVisiblePathsForFiles(files, root) retain];
    [_explorerOutlineView reloadData];

    if (_explorerTextFilterActive) {
        // Open every folder on the way to a match, parents first.
        NSMutableArray *folders = [NSMutableArray array];
        for (NSString *path in _explorerVisiblePaths) {
            if (![files containsObject:path]) {
                [folders addObject:path];
            }
        }
        [folders sortUsingSelector:@selector(compare:)];
        for (NSString *folder in folders) {
            OMDExplorerNode *node = [_explorerRootNode descendantForPath:folder];
            if (node != nil) {
                [_explorerOutlineView expandItem:node];
            }
        }
        NSUInteger count = [files count];
        if (count == 0) {
            [self setExplorerFilterStatus:@"No files match"];
        } else if (!complete) {
            [self setExplorerFilterStatus:[NSString stringWithFormat:@"First %lu files", (unsigned long)count]];
        } else {
            [self setExplorerFilterStatus:[NSString stringWithFormat:(count == 1 ? @"%lu file" : @"%lu files"),
                                                                     (unsigned long)count]];
        }
        if (_explorerOpenFirstMatchWhenShown) {
            _explorerOpenFirstMatchWhenShown = NO;
            [self openFirstShownFile];
            return;
        }
    } else {
        if (restore) {
            [self restoreExplorerExpansion];
        }
        [self setExplorerFilterStatus:([files count] == 0 ? @"No Markdown files here"
                                       : (complete ? nil : @"Large folder: not every file was searched"))];
    }
    [self revealDocumentExpandingFolders:NO];
}

// A line under the options while it says something; nil hides it.
- (void)setExplorerFilterStatus:(NSString *)status
{
    BOOL hidden = ([status length] == 0);
    [_explorerFilterStatusLabel setStringValue:(hidden ? @"" : status)];
    if ([_explorerFilterStatusLabel isHidden] != hidden) {
        [_explorerFilterStatusLabel setHidden:hidden];
        [self layoutExplorerControls];
    }
}

// The time within which a second click makes a double-click. GNUstep's
// +doubleClickInterval returns 0; its X11 backend counts clicks with the
// GSDoubleClickTime default, in milliseconds (300 below 200).
static NSTimeInterval OMDDoubleClickInterval(void)
{
    NSTimeInterval interval = [NSEvent doubleClickInterval];
    if (interval > 0.0) {
        return interval;
    }
    NSInteger milliseconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"GSDoubleClickTime"];
    return (milliseconds < 200 ? 300 : milliseconds) / 1000.0;
}

- (OMDExplorerNode *)explorerClickedNode
{
    NSInteger row = [_explorerOutlineView clickedRow];
    if (row < 0) {
        row = [_explorerOutlineView selectedRow];
    }
    if (row < 0) {
        return nil;
    }
    return [_explorerOutlineView itemAtRow:row];
}

- (void)cancelPendingExplorerClick
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(openPendingExplorerClick)
                                               object:nil];
    [_explorerPendingClickNode release];
    _explorerPendingClickNode = nil;
}

- (void)openPendingExplorerClick
{
    OMDExplorerNode *node = [[_explorerPendingClickNode retain] autorelease];
    [self cancelPendingExplorerClick];
    if (node != nil) {
        [_delegate openLocalPath:[node path] inNewTab:NO];
    }
}

- (void)toggleExplorerFolder:(OMDExplorerNode *)node
{
    if ([_explorerOutlineView isItemExpanded:node]) {
        [_explorerOutlineView collapseItem:node];
    } else {
        [_explorerOutlineView expandItem:node];
    }
}

// A click on a folder opens or closes it at once. A click on a file opens
// it in the current tab once the double-click interval has passed without
// a second click; a double-click opens it in a new tab instead.
- (void)explorerItemClicked:(id)sender
{
    (void)sender;
    NSEvent *event = [NSApp currentEvent];
    if (event != nil && [event clickCount] > 1) {
        return;
    }
    OMDExplorerNode *node = [self explorerClickedNode];
    if (node == nil) {
        return;
    }
    [self cancelPendingExplorerClick];
    if ([node isDirectory]) {
        // A quick second click would close the folder again.
        _explorerIgnoreDoubleClick = YES;
        [self toggleExplorerFolder:node];
        return;
    }
    _explorerIgnoreDoubleClick = NO;
    _explorerPendingClickNode = [node retain];
    [self performSelector:@selector(openPendingExplorerClick)
               withObject:nil
               afterDelay:OMDDoubleClickInterval()];
}

- (void)explorerItemDoubleClicked:(id)sender
{
    (void)sender;
    if (_explorerIgnoreDoubleClick) {
        _explorerIgnoreDoubleClick = NO;
        return;
    }
    OMDExplorerNode *node = [[_explorerPendingClickNode retain] autorelease];
    [self cancelPendingExplorerClick];
    if (node == nil) {
        node = [self explorerClickedNode];
    }
    if (node == nil || [node isDirectory]) {
        return;
    }
    [_delegate openLocalPath:[node path] inNewTab:YES];
}

- (void)explorerOpenSelection:(id)sender
{
    (void)sender;
    NSInteger row = [_explorerOutlineView selectedRow];
    if (row < 0) {
        return;
    }
    OMDExplorerNode *node = [_explorerOutlineView itemAtRow:row];
    [self cancelPendingExplorerClick];
    if ([node isDirectory]) {
        [self toggleExplorerFolder:node];
    } else {
        [_delegate openLocalPath:[node path] inNewTab:NO];
    }
}

// The context menu for a row: what applies to that file or folder.
- (NSMenu *)explorerContextMenuForRow:(NSInteger)row
{
    OMDExplorerNode *node = (row >= 0 ? [_explorerOutlineView itemAtRow:row] : nil);
    if (node == nil) {
        return nil;
    }
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [menu setAutoenablesItems:NO];
    NSArray *entries = nil;
    if ([node isDirectory]) {
        BOOL expanded = [_explorerOutlineView isItemExpanded:node];
        entries = [NSArray arrayWithObjects:
                   (expanded ? @"Collapse" : @"Expand"), NSStringFromSelector(@selector(explorerContextToggleFolder:)),
                   @"Open in Files", NSStringFromSelector(@selector(explorerContextOpenFolder:)),
                   @"Use as Explorer Root", NSStringFromSelector(@selector(explorerContextUseAsRoot:)),
                   @"-", @"",
                   @"Copy Path", NSStringFromSelector(@selector(explorerContextCopyPath:)),
                   @"Copy Relative Path", NSStringFromSelector(@selector(explorerContextCopyRelativePath:)),
                   nil];
    } else {
        entries = [NSArray arrayWithObjects:
                   @"Open", NSStringFromSelector(@selector(explorerContextOpen:)),
                   @"Open in New Tab", NSStringFromSelector(@selector(explorerContextOpenInNewTab:)),
                   @"-", @"",
                   @"Reveal in Files", NSStringFromSelector(@selector(explorerContextReveal:)),
                   @"-", @"",
                   @"Copy Path", NSStringFromSelector(@selector(explorerContextCopyPath:)),
                   @"Copy Relative Path", NSStringFromSelector(@selector(explorerContextCopyRelativePath:)),
                   nil];
    }
    NSUInteger index = 0;
    for (; index + 1 < [entries count]; index += 2) {
        NSString *title = [entries objectAtIndex:index];
        if ([title isEqualToString:@"-"]) {
            [menu addItem:[NSMenuItem separatorItem]];
            continue;
        }
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                       action:NSSelectorFromString([entries objectAtIndex:index + 1])
                                                keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setRepresentedObject:node];
        [menu addItem:item];
    }
    return menu;
}

- (void)explorerContextOpen:(id)sender
{
    [self cancelPendingExplorerClick];
    [_delegate openLocalPath:[[sender representedObject] path] inNewTab:NO];
}

- (void)explorerContextOpenInNewTab:(id)sender
{
    [self cancelPendingExplorerClick];
    [_delegate openLocalPath:[[sender representedObject] path] inNewTab:YES];
}

- (void)explorerContextToggleFolder:(id)sender
{
    [self toggleExplorerFolder:[sender representedObject]];
}

- (void)explorerContextReveal:(id)sender
{
    if (!OMDRevealPathInFileManager([[sender representedObject] path])) {
        NSBeep();
    }
}

- (void)explorerContextOpenFolder:(id)sender
{
    if (!OMDOpenFolderInFileManager([[sender representedObject] path])) {
        NSBeep();
    }
}

- (void)explorerContextUseAsRoot:(id)sender
{
    [self chooseRootByHand:[[sender representedObject] path]];
}

- (void)copyStringToPasteboard:(NSString *)string
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pasteboard setString:string forType:NSStringPboardType];
}

- (void)explorerContextCopyPath:(id)sender
{
    [self copyStringToPasteboard:[[sender representedObject] path]];
}

- (void)explorerContextCopyRelativePath:(id)sender
{
    [self copyStringToPasteboard:OMDExplorerRelativePath([[sender representedObject] path], [_explorerRootNode path])];
}

- (NSArray *)childrenOfItem:(id)item
{
    OMDExplorerNode *node = (item != nil ? (OMDExplorerNode *)item : _explorerRootNode);
    if (node == nil) {
        return [NSArray array];
    }
    NSArray *children = [node childrenShowingHidden:[self isExplorerShowHiddenFilesEnabled]];
    if (_explorerVisiblePaths == nil) {
        return children;
    }
    NSMutableArray *visible = [NSMutableArray arrayWithCapacity:[children count]];
    for (OMDExplorerNode *child in children) {
        if ([_explorerVisiblePaths containsObject:[child path]]) {
            [visible addObject:child];
        }
    }
    return visible;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    (void)outlineView;
    return (NSInteger)[[self childrenOfItem:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    (void)outlineView;
    NSArray *children = [self childrenOfItem:item];
    if (index < 0 || index >= (NSInteger)[children count]) {
        return nil;
    }
    return [children objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    (void)outlineView;
    return [(OMDExplorerNode *)item isDirectory];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    (void)outlineView;
    (void)tableColumn;
    NSString *name = [(OMDExplorerNode *)item name];
    return (name != nil ? name : @"");
}

- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
               item:(id)item
{
    (void)outlineView;
    (void)tableColumn;
    OMDExplorerFileKind kind = [(OMDExplorerNode *)item kind];
    // Folders and the files the viewer opens or converts read normally;
    // the rest are dimmed.
    BOOL dimmed = (kind == OMDExplorerFileKindOther);
    if ([cell respondsToSelector:@selector(setTextColor:)]) {
        [cell setTextColor:(dimmed ? [NSColor disabledControlTextColor] : [NSColor controlTextColor])];
    }
    if ([cell isKindOfClass:[OMDExplorerCell class]]) {
        [(OMDExplorerCell *)cell setIcon:OMDSymbolicImageNamed(OMDExplorerIconNameForKind(kind)) dimmed:dimmed];
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    (void)outlineView;
    (void)tableColumn;
    (void)item;
    return NO;
}

@end
