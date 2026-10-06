// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDExplorerController.h"
#import "OMDDocumentConverter.h"
#import "OMDLayoutMetrics.h"
#import "OMDExplorerRoot.h"
#import "OMDExternalTools.h"
#import "OMDTextFileSupport.h"
#import "OMDViewerColors.h"
#import "OMDViewerDefaults.h"
#import "OMDViewerImages.h"

#include <math.h>

static const CGFloat OMDExplorerListMinFontSize = 10.0;
static const CGFloat OMDExplorerListMaxFontSize = 20.0;
static const CGFloat OMDExplorerListMinimumRowHeight = 20.0;

static NSInteger OMDExplorerFileColorTierForPath(NSString *path)
{
    NSString *extension = [[path pathExtension] lowercaseString];
    if (OMDIsMarkdownExtension(extension)) {
        return 1;
    }
    if ([OMDDocumentConverter isSupportedExtension:extension]) {
        return 2;
    }
    return 3;
}

@interface OMDExplorerController ()
- (void)setupExplorerSidebar;
- (void)updateExplorerControlsVisibility;
- (void)updateNavigateUpButton;
- (void)reloadLocalExplorerEntries;
- (void)showRoot:(NSString *)root;
- (void)applyExplorerListFontPreference;
- (BOOL)isExplorerShowHiddenFilesEnabled;
- (void)setExplorerShowHiddenFilesEnabled:(BOOL)enabled;
- (void)explorerNavigateUp:(id)sender;
- (void)explorerShowHiddenFilesChanged:(id)sender;
- (void)explorerItemClicked:(id)sender;
- (void)explorerItemDoubleClicked:(id)sender;
- (NSDictionary *)explorerClickedEntry;
- (void)cancelPendingExplorerClick;
- (void)openPendingExplorerClick;
- (void)openExplorerEntry:(NSDictionary *)entry inNewTab:(BOOL)inNewTab;
@end

@implementation OMDExplorerController

- (instancetype)initWithDelegate:(id<OMDExplorerControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        _explorerEntries = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_explorerPendingClickEntry release];
    [_explorerShowHiddenFilesButton release];
    [_explorerNavigateUpButton release];
    [_explorerPathLabel release];
    [_explorerTableView setDelegate:nil];
    [_explorerTableView setDataSource:nil];
    [_explorerTableView release];
    [_explorerScrollView release];
    [_explorerEntries release];
    [_explorerLocalRootPath release];
    [_explorerLocalCurrentPath release];
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
    if (_explorerShowHiddenFilesButton != nil) {
        [_explorerShowHiddenFilesButton setFont:labelFont];
    }
    if (_explorerPathLabel != nil) {
        [_explorerPathLabel setFont:pathFont];
    }
    [self applyExplorerListFontPreference];
    [self updateExplorerControlsVisibility];
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
    [_explorerLocalCurrentPath release];
    _explorerLocalCurrentPath = [root copy];
    if (_explorerTableView != nil) {
        [self reloadExplorerEntries];
    }
}

- (void)setDocumentPath:(NSString *)path
{
    NSString *normalized = ([path length] > 0 ? path : nil);
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

- (void)applyExplorerListFontPreference
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    if (_explorerTableView == nil) {
        return;
    }

    CGFloat fontSize = [self explorerListFontSizePreference];
    NSFont *font = [NSFont systemFontOfSize:fontSize];
    if (font == nil) {
        font = [NSFont systemFontOfSize:OMDExplorerListDefaultFontSize];
    }
    CGFloat rowHeight = ceil(fontSize + metrics.explorerRowPadding);
    if (rowHeight < OMDExplorerListMinimumRowHeight) {
        rowHeight = OMDExplorerListMinimumRowHeight;
    }
    [_explorerTableView setRowHeight:rowHeight];

    NSTableColumn *column = [_explorerTableView tableColumnWithIdentifier:@"ExplorerName"];
    id dataCell = [column dataCell];
    if (dataCell != nil && [dataCell respondsToSelector:@selector(setFont:)]) {
        [dataCell setFont:font];
    }
    [_explorerTableView reloadData];
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

- (void)setupExplorerSidebar
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    if (_containerView == nil) {
        return;
    }

    NSRect bounds = [_containerView bounds];
    NSFont *labelFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 12.0 : 11.0)];
    NSFont *pathFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 11.0 : 10.5)];

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

    _explorerNavigateUpButton = [[NSButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                           NSHeight(bounds) - 84,
                                                                           32,
                                                                           metrics.explorerControlHeight)];
    [_explorerNavigateUpButton setTitle:@""];
    [_explorerNavigateUpButton setBezelStyle:NSRoundedBezelStyle];
    [_explorerNavigateUpButton setImage:OMDSymbolicImageNamed(@"omd-go-up-symbolic")];
#if defined(_WIN32)
    [_explorerNavigateUpButton setTitle:@"Up"];
    [_explorerNavigateUpButton setFont:labelFont];
    [_explorerNavigateUpButton setImagePosition:NSImageLeft];
#else
    [_explorerNavigateUpButton setImagePosition:NSImageOnly];
#endif
    [_explorerNavigateUpButton setToolTip:@"Go to the parent folder"];
    [_explorerNavigateUpButton setTarget:self];
    [_explorerNavigateUpButton setAction:@selector(explorerNavigateUp:)];
    [_explorerNavigateUpButton setAutoresizingMask:NSViewMinYMargin];
    [_containerView addSubview:_explorerNavigateUpButton];

    _explorerPathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding + 38, NSHeight(bounds) - 80, 100, 18)];
    [_explorerPathLabel setBezeled:NO];
    [_explorerPathLabel setEditable:NO];
    [_explorerPathLabel setSelectable:NO];
    [_explorerPathLabel setDrawsBackground:NO];
    [_explorerPathLabel setFont:pathFont];
    [_explorerPathLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerPathLabel];

    _explorerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 10, NSWidth(bounds), 80)];
    [_explorerScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_explorerScrollView setHasVerticalScroller:YES];
    [_explorerScrollView setHasHorizontalScroller:NO];
    [_explorerScrollView setBorderType:NSBezelBorder];

    _explorerTableView = [[NSTableView alloc] initWithFrame:[_explorerScrollView bounds]];
    [_explorerTableView setHeaderView:nil];
    [_explorerTableView setAllowsEmptySelection:YES];
    [_explorerTableView setAllowsMultipleSelection:NO];
    [_explorerTableView setRowHeight:OMDExplorerListMinimumRowHeight];
    [_explorerTableView setTarget:self];
    [_explorerTableView setAction:@selector(explorerItemClicked:)];
    [_explorerTableView setDoubleAction:@selector(explorerItemDoubleClicked:)];
    [_explorerTableView setDataSource:self];
    [_explorerTableView setDelegate:self];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"ExplorerName"] autorelease];
    [column setEditable:NO];
    [column setWidth:NSWidth([_explorerScrollView bounds]) - 2.0];
    [_explorerTableView addTableColumn:column];
    [_explorerScrollView setDocumentView:_explorerTableView];
    [_delegate applyScrollSpeedPreference];
    [_containerView addSubview:_explorerScrollView];
    [self applyExplorerListFontPreference];

    if (_explorerLocalRootPath == nil) {
        NSString *root = OMDExplorerRootForDocumentPath(_explorerDocumentPath);
        _explorerLocalRootPath = [(root != nil ? root : [self explorerLocalRootPathPreference]) copy];
        [_explorerLocalCurrentPath release];
        _explorerLocalCurrentPath = [_explorerLocalRootPath copy];
    }

    [self updateExplorerControlsVisibility];
}

// Up is available below the root.
- (void)updateNavigateUpButton
{
    BOOL canNavigateUp = (_explorerLocalCurrentPath != nil &&
                          _explorerLocalRootPath != nil &&
                          ![_explorerLocalCurrentPath isEqualToString:_explorerLocalRootPath]);
    [_explorerNavigateUpButton setEnabled:canNavigateUp];
}

- (void)updateExplorerControlsVisibility
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    [_explorerShowHiddenFilesButton setState:([self isExplorerShowHiddenFilesEnabled] ? NSOnState : NSOffState)];
    [self updateNavigateUpButton];

    NSRect bounds = [_containerView bounds];
    CGFloat width = NSWidth(bounds);
    CGFloat height = NSHeight(bounds);
    CGFloat wideControlWidth = MAX(1.0, width - (metrics.explorerSidePadding * 2.0));
    CGFloat navigateButtonWidth = 32.0;
#if defined(_WIN32)
    navigateButtonWidth = 44.0;
#endif
    CGFloat navigateButtonGap = 6.0;
    CGFloat pathWidth = MAX(1.0, wideControlWidth - navigateButtonWidth - navigateButtonGap);
    CGFloat scrollWidth = MAX(1.0, wideControlWidth + 4.0);
    CGFloat top = height - metrics.explorerTopPadding;

    [_explorerShowHiddenFilesButton setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                        top - metrics.explorerMinorControlHeight,
                                                        wideControlWidth,
                                                        metrics.explorerMinorControlHeight)];
    CGFloat navigateUpY = NSMinY([_explorerShowHiddenFilesButton frame]) - 8.0 - metrics.explorerControlHeight;
    [_explorerNavigateUpButton setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                   navigateUpY,
                                                   navigateButtonWidth,
                                                   metrics.explorerControlHeight)];
    [_explorerPathLabel setFrame:NSMakeRect(metrics.explorerSidePadding + navigateButtonWidth + navigateButtonGap,
                                            navigateUpY + 4.0,
                                            pathWidth,
                                            18)];
    CGFloat scrollBottomInset = 10.0;
    CGFloat scrollHeight = MAX(1.0, navigateUpY - 8.0 - scrollBottomInset);
    [_explorerScrollView setFrame:NSMakeRect(MAX(0.0, metrics.explorerSidePadding - 2.0),
                                             scrollBottomInset,
                                             scrollWidth,
                                             scrollHeight)];
    NSTableColumn *nameColumn = [_explorerTableView tableColumnWithIdentifier:@"ExplorerName"];
    if (nameColumn != nil) {
        [nameColumn setWidth:NSWidth([_explorerScrollView bounds]) - 2.0];
    }
}

- (void)reloadExplorerEntries
{
    [self updateExplorerControlsVisibility];
    [self reloadLocalExplorerEntries];
}

- (void)reloadLocalExplorerEntries
{
    if (_explorerLocalRootPath == nil || [_explorerLocalRootPath length] == 0) {
        [_explorerLocalRootPath release];
        _explorerLocalRootPath = [[self explorerLocalRootPathPreference] copy];
    }
    if (_explorerLocalCurrentPath == nil || [_explorerLocalCurrentPath length] == 0) {
        [_explorerLocalCurrentPath release];
        _explorerLocalCurrentPath = [_explorerLocalRootPath copy];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:_explorerLocalCurrentPath isDirectory:&isDirectory] || !isDirectory) {
        [_explorerLocalCurrentPath release];
        _explorerLocalCurrentPath = [_explorerLocalRootPath copy];
    }

    NSError *error = nil;
    NSArray *children = [fileManager contentsOfDirectoryAtPath:_explorerLocalCurrentPath error:&error];
    if (children == nil) {
        [_explorerEntries removeAllObjects];
        [_explorerTableView reloadData];
        [_explorerPathLabel setStringValue:@"Unable to read folder."];
        return;
    }

    NSMutableArray *entries = [NSMutableArray array];
    if (![_explorerLocalCurrentPath isEqualToString:_explorerLocalRootPath]) {
        NSString *parent = [_explorerLocalCurrentPath stringByDeletingLastPathComponent];
        if ([parent length] == 0) {
            parent = _explorerLocalRootPath;
        }
        [entries addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                            @"..", @"name",
                            parent, @"path",
                            [NSNumber numberWithBool:YES], @"isDirectory",
                            [NSNumber numberWithBool:YES], @"isParent",
                            [NSNumber numberWithInteger:0], @"colorTier",
                            nil]];
    }

    NSMutableArray *sortedChildren = [children mutableCopy];
    [sortedChildren sortUsingComparator:^NSComparisonResult(id leftValue, id rightValue) {
        NSString *left = (NSString *)leftValue;
        NSString *right = (NSString *)rightValue;
        NSString *leftPath = [_explorerLocalCurrentPath stringByAppendingPathComponent:left];
        NSString *rightPath = [_explorerLocalCurrentPath stringByAppendingPathComponent:right];
        BOOL leftDir = NO;
        BOOL rightDir = NO;
        [fileManager fileExistsAtPath:leftPath isDirectory:&leftDir];
        [fileManager fileExistsAtPath:rightPath isDirectory:&rightDir];
        if (leftDir != rightDir) {
            return leftDir ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left compare:right options:NSCaseInsensitiveSearch];
    }];

    BOOL showHiddenFiles = [self isExplorerShowHiddenFilesEnabled];
    for (NSString *name in sortedChildren) {
        if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
            continue;
        }
        if (!showHiddenFiles && [name hasPrefix:@"."]) {
            continue;
        }

        NSString *fullPath = [_explorerLocalCurrentPath stringByAppendingPathComponent:name];
        BOOL childIsDirectory = NO;
        if (![fileManager fileExistsAtPath:fullPath isDirectory:&childIsDirectory]) {
            continue;
        }

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        [entry setObject:name forKey:@"name"];
        [entry setObject:fullPath forKey:@"path"];
        [entry setObject:[NSNumber numberWithBool:childIsDirectory] forKey:@"isDirectory"];
        [entry setObject:[NSNumber numberWithBool:NO] forKey:@"isParent"];
        [entry setObject:[NSNumber numberWithInteger:(childIsDirectory ? 0 : OMDExplorerFileColorTierForPath(fullPath))]
                 forKey:@"colorTier"];

        if (!childIsDirectory) {
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:fullPath error:NULL];
            NSNumber *size = [attributes objectForKey:NSFileSize];
            if ([size respondsToSelector:@selector(unsignedLongLongValue)]) {
                [entry setObject:size forKey:@"size"];
            }
        }
        [entries addObject:entry];
    }
    [sortedChildren release];

    [_explorerEntries removeAllObjects];
    [_explorerEntries addObjectsFromArray:entries];
    [_explorerTableView reloadData];
    [_explorerPathLabel setStringValue:[_explorerLocalCurrentPath stringByAbbreviatingWithTildeInPath]];
    [_explorerPathLabel setToolTip:_explorerLocalCurrentPath];
}

- (void)explorerNavigateUp:(id)sender
{
    (void)sender;
    if (_explorerLocalCurrentPath == nil) {
        return;
    }
    if ([_explorerLocalCurrentPath isEqualToString:_explorerLocalRootPath]) {
        return;
    }

    NSString *parent = [_explorerLocalCurrentPath stringByDeletingLastPathComponent];
    if ([parent length] == 0) {
        parent = _explorerLocalRootPath;
    }
    [_explorerLocalCurrentPath release];
    _explorerLocalCurrentPath = [parent copy];
    [self reloadLocalExplorerEntries];
    [self updateNavigateUpButton];
}

- (void)explorerShowHiddenFilesChanged:(id)sender
{
    (void)sender;
    BOOL enabled = ([_explorerShowHiddenFilesButton state] == NSOnState);
    [self setExplorerShowHiddenFilesEnabled:enabled];
    [self reloadLocalExplorerEntries];
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

- (NSDictionary *)explorerClickedEntry
{
    NSInteger row = [_explorerTableView clickedRow];
    if (row < 0) {
        row = [_explorerTableView selectedRow];
    }
    if (row < 0 || row >= (NSInteger)[_explorerEntries count]) {
        return nil;
    }
    return [_explorerEntries objectAtIndex:row];
}

- (void)cancelPendingExplorerClick
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(openPendingExplorerClick)
                                               object:nil];
    [_explorerPendingClickEntry release];
    _explorerPendingClickEntry = nil;
}

- (void)openPendingExplorerClick
{
    NSDictionary *entry = [[_explorerPendingClickEntry retain] autorelease];
    [self cancelPendingExplorerClick];
    [self openExplorerEntry:entry inNewTab:NO];
}

// A click on a folder opens it at once. A click on a file opens it in the
// current tab once the double-click interval has passed without a second
// click; a double-click opens it in a new tab instead.
- (void)explorerItemClicked:(id)sender
{
    (void)sender;
    NSEvent *event = [NSApp currentEvent];
    if (event != nil && [event clickCount] > 1) {
        return;
    }
    NSDictionary *entry = [self explorerClickedEntry];
    if (entry == nil) {
        return;
    }
    [self cancelPendingExplorerClick];
    if ([[entry objectForKey:@"isDirectory"] boolValue]) {
        // The second click of a double-click would land in the new listing.
        _explorerIgnoreDoubleClick = YES;
        [self openExplorerEntry:entry inNewTab:NO];
        return;
    }
    _explorerIgnoreDoubleClick = NO;
    _explorerPendingClickEntry = [entry retain];
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
    NSDictionary *entry = [[_explorerPendingClickEntry retain] autorelease];
    [self cancelPendingExplorerClick];
    if (entry == nil) {
        entry = [self explorerClickedEntry];
    }
    if (entry == nil) {
        return;
    }
    [self openExplorerEntry:entry inNewTab:YES];
}

- (void)openExplorerEntry:(NSDictionary *)entry inNewTab:(BOOL)inNewTab
{
    if (entry == nil) {
        return;
    }

    BOOL isDirectory = [[entry objectForKey:@"isDirectory"] boolValue];
    NSString *path = [entry objectForKey:@"path"];
    if (path == nil || [path length] == 0) {
        return;
    }

    if (isDirectory) {
        [_explorerLocalCurrentPath release];
        _explorerLocalCurrentPath = [path copy];
        [self reloadLocalExplorerEntries];
        [self updateNavigateUpButton];
        return;
    }

    [_delegate openLocalPath:path inNewTab:inNewTab];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView != _explorerTableView) {
        return 0;
    }
    return (NSInteger)[_explorerEntries count];
}

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(NSInteger)row
{
    (void)tableColumn;
    if (tableView != _explorerTableView) {
        return @"";
    }
    if (row < 0 || row >= (NSInteger)[_explorerEntries count]) {
        return @"";
    }

    NSDictionary *entry = [_explorerEntries objectAtIndex:row];
    NSString *name = [entry objectForKey:@"name"];
    BOOL isDirectory = [[entry objectForKey:@"isDirectory"] boolValue];
    BOOL isParent = [[entry objectForKey:@"isParent"] boolValue];
    if (isParent) {
        return @"..";
    }
    if (isDirectory) {
        return [NSString stringWithFormat:@"%@/", name != nil ? name : @""];
    }
    return name != nil ? name : @"";
}

- (void)tableView:(NSTableView *)tableView
 willDisplayCell:(id)cell
  forTableColumn:(NSTableColumn *)tableColumn
             row:(NSInteger)row
{
    (void)tableColumn;
    if (tableView != _explorerTableView || row < 0 || row >= (NSInteger)[_explorerEntries count]) {
        return;
    }
    if (![cell respondsToSelector:@selector(setTextColor:)]) {
        return;
    }

    NSDictionary *entry = [_explorerEntries objectAtIndex:row];
    BOOL isDirectory = [[entry objectForKey:@"isDirectory"] boolValue];
    NSInteger colorTier = [[entry objectForKey:@"colorTier"] integerValue];
    // Folders and the files the viewer opens or converts read normally;
    // the rest are dimmed.
    BOOL opens = (isDirectory || colorTier == 1 || colorTier == 2);
    [cell setTextColor:(opens ? [NSColor controlTextColor] : [NSColor disabledControlTextColor])];
}


@end