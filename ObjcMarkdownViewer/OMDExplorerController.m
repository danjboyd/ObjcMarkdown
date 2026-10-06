// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDExplorerController.h"
#import "OMDExplorerRoot.h"
#import "OMDExplorerTree.h"
#import "OMDLayoutMetrics.h"
#import "OMDTextFileSupport.h"
#import "OMDViewerDefaults.h"
#import "OMDViewerImages.h"

#include <math.h>

static const CGFloat OMDExplorerListMinFontSize = 10.0;
static const CGFloat OMDExplorerListMaxFontSize = 20.0;
static const CGFloat OMDExplorerListMinimumRowHeight = 20.0;
static const CGFloat OMDExplorerIconSize = 16.0;
static const CGFloat OMDExplorerIconGap = 5.0;

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

// Return opens the selected file, or opens or closes the selected folder.
@interface OMDExplorerOutlineView : NSOutlineView
@end

@implementation OMDExplorerOutlineView

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
    }
    [super keyDown:event];
}

@end

@interface OMDExplorerController ()
- (void)setupExplorerSidebar;
- (void)layoutExplorerControls;
- (void)showRoot:(NSString *)root;
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
    [_explorerShowHiddenFilesButton release];
    [_explorerPathLabel release];
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
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    NSFont *labelFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 12.0 : 11.0)];
    NSFont *pathFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 11.0 : 10.5)];
    [_explorerShowHiddenFilesButton setFont:labelFont];
    [_explorerPathLabel setFont:pathFont];
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
    if ([root isEqualToString:_explorerLocalRootPath]) {
        return;
    }
    [_explorerLocalRootPath release];
    _explorerLocalRootPath = [root copy];
    [self cancelPendingExplorerClick];
    [_explorerRootNode release];
    _explorerRootNode = [[OMDExplorerNode alloc] initWithPath:root isDirectory:YES parent:nil];
    if (_explorerOutlineView != nil) {
        [_explorerPathLabel setStringValue:[root stringByAbbreviatingWithTildeInPath]];
        [_explorerPathLabel setToolTip:root];
        [_explorerOutlineView reloadData];
        [_explorerOutlineView scrollRowToVisible:0];
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
    if (root != nil) {
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
    NSFont *labelFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 12.0 : 11.0)];
    NSFont *pathFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 11.0 : 10.5)];

    _explorerPathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding, NSHeight(bounds) - 30, 100, 16)];
    [_explorerPathLabel setBezeled:NO];
    [_explorerPathLabel setEditable:NO];
    [_explorerPathLabel setSelectable:NO];
    [_explorerPathLabel setDrawsBackground:NO];
    [_explorerPathLabel setFont:pathFont];
    [[_explorerPathLabel cell] setLineBreakMode:NSLineBreakByTruncatingHead];
    [_explorerPathLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerPathLabel];

    _explorerShowHiddenFilesButton = [[NSButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                                NSHeight(bounds) - 54,
                                                                                100,
                                                                                metrics.explorerMinorControlHeight)];
    [_explorerShowHiddenFilesButton setButtonType:NSSwitchButton];
    [_explorerShowHiddenFilesButton setTitle:@"Show hidden files"];
    [_explorerShowHiddenFilesButton setFont:labelFont];
    [_explorerShowHiddenFilesButton setState:([self isExplorerShowHiddenFilesEnabled] ? NSOnState : NSOffState)];
    [_explorerShowHiddenFilesButton setTarget:self];
    [_explorerShowHiddenFilesButton setAction:@selector(explorerShowHiddenFilesChanged:)];
    [_explorerShowHiddenFilesButton setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerShowHiddenFilesButton];

    _explorerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 10, NSWidth(bounds), 80)];
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

    if (_explorerLocalRootPath == nil) {
        [self showRoot:[self explorerLocalRootPathPreference]];
    }
    [_explorerPathLabel setStringValue:[_explorerLocalRootPath stringByAbbreviatingWithTildeInPath]];
    [_explorerPathLabel setToolTip:_explorerLocalRootPath];

    // Files change behind the app's back; look again when it comes back.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidBecomeKey:)
                                                 name:NSWindowDidBecomeKeyNotification
                                               object:nil];
    [self layoutExplorerControls];
}

- (void)layoutExplorerControls
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    [_explorerShowHiddenFilesButton setState:([self isExplorerShowHiddenFilesEnabled] ? NSOnState : NSOffState)];

    NSRect bounds = [_containerView bounds];
    CGFloat wideControlWidth = MAX(1.0, NSWidth(bounds) - (metrics.explorerSidePadding * 2.0));
    CGFloat top = NSHeight(bounds) - metrics.explorerTopPadding;

    [_explorerPathLabel setFrame:NSMakeRect(metrics.explorerSidePadding, top - 16.0, wideControlWidth, 16.0)];
    [_explorerShowHiddenFilesButton setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                        NSMinY([_explorerPathLabel frame]) - 6.0 - metrics.explorerMinorControlHeight,
                                                        wideControlWidth,
                                                        metrics.explorerMinorControlHeight)];
    CGFloat scrollBottomInset = 10.0;
    CGFloat scrollTop = NSMinY([_explorerShowHiddenFilesButton frame]) - 8.0;
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
        [self showRoot:[self explorerLocalRootPathPreference]];
    }
    [_explorerRootNode reloadChildren];
    [_explorerOutlineView reloadData];
    [self revealDocumentExpandingFolders:YES];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if ([notification object] != [_containerView window] || ![_explorerRootNode hasLoadedChildren]) {
        return;
    }
    [_explorerRootNode reloadChildren];
    [self reloadOutlineKeepingSelection];
}

- (void)explorerShowHiddenFilesChanged:(id)sender
{
    (void)sender;
    [self setExplorerShowHiddenFilesEnabled:([_explorerShowHiddenFilesButton state] == NSOnState)];
    [self reloadOutlineKeepingSelection];
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

- (NSArray *)childrenOfItem:(id)item
{
    OMDExplorerNode *node = (item != nil ? (OMDExplorerNode *)item : _explorerRootNode);
    if (node == nil) {
        return [NSArray array];
    }
    return [node childrenShowingHidden:[self isExplorerShowHiddenFilesEnabled]];
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
