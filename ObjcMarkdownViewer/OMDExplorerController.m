// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDExplorerController.h"
#import "OMDDocumentConverter.h"
#import "OMDGitHubClient.h"
#import "OMDLayoutMetrics.h"
#import "OMDExternalTools.h"
#import "OMDTextFileSupport.h"
#import "OMDViewerColors.h"
#import "OMDViewerDefaults.h"
#import "OMDViewerImages.h"

#include <math.h>

static const CGFloat OMDExplorerListMinFontSize = 10.0;
static const CGFloat OMDExplorerListMaxFontSize = 20.0;
static const CGFloat OMDExplorerListMinimumRowHeight = 20.0;
static const NSTimeInterval OMDGitLockRetryDelaySeconds = 0.20;
static const NSTimeInterval OMDGitStaleLockMinimumAgeSeconds = 2.0;
static NSString * const OMDGitHubCacheErrorDomain = @"OMDGitHubCacheErrorDomain";

typedef NS_ENUM(NSInteger, OMDExplorerSourceMode) {
    OMDExplorerSourceModeLocal = 0,
    OMDExplorerSourceModeGitHub = 1
};

static NSImage *OMDExplorerNavigateParentBaseImage(void)
{
    static NSImage *cached = nil;
    if (cached != nil) {
        return cached;
    }

    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)] autorelease];
    [image lockFocus];
    [[NSColor blackColor] setStroke];
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow setLineWidth:2.0];
    [arrow setLineCapStyle:NSRoundLineCapStyle];
    [arrow setLineJoinStyle:NSRoundLineJoinStyle];
    [arrow moveToPoint:NSMakePoint(12.5, 12.0)];
    [arrow lineToPoint:NSMakePoint(5.2, 4.7)];
    [arrow moveToPoint:NSMakePoint(5.2, 4.7)];
    [arrow lineToPoint:NSMakePoint(5.2, 9.1)];
    [arrow moveToPoint:NSMakePoint(5.2, 4.7)];
    [arrow lineToPoint:NSMakePoint(9.6, 4.7)];
    [arrow stroke];
    [image unlockFocus];
    [image setSize:NSMakeSize(16.0, 16.0)];
    cached = [image retain];
    return cached;
}

static BOOL OMDGitErrorLooksLikeLockConflict(NSString *reason)
{
    NSString *trimmed = OMDTrimmedString(reason);
    if ([trimmed length] == 0) {
        return NO;
    }

    NSRange lockRange = [trimmed rangeOfString:@".lock" options:NSCaseInsensitiveSearch];
    if (lockRange.location == NSNotFound) {
        return NO;
    }
    if ([trimmed rangeOfString:@"file exists" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }
    if ([trimmed rangeOfString:@"another git process seems to be running" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }
    return ([trimmed rangeOfString:@"unable to create" options:NSCaseInsensitiveSearch].location != NSNotFound);
}

static NSString *OMDGitLockPathFromErrorReason(NSString *reason)
{
    NSString *trimmed = OMDTrimmedString(reason);
    if ([trimmed length] == 0) {
        return nil;
    }

    NSRange scanRange = NSMakeRange(0, [trimmed length]);
    while (scanRange.length > 0) {
        NSRange startQuote = [trimmed rangeOfString:@"'" options:0 range:scanRange];
        if (startQuote.location == NSNotFound) {
            break;
        }

        NSUInteger start = NSMaxRange(startQuote);
        if (start >= [trimmed length]) {
            break;
        }
        NSRange tailRange = NSMakeRange(start, [trimmed length] - start);
        NSRange endQuote = [trimmed rangeOfString:@"'" options:0 range:tailRange];
        if (endQuote.location == NSNotFound) {
            break;
        }

        NSString *candidate = [trimmed substringWithRange:NSMakeRange(start, endQuote.location - start)];
        if ([candidate hasSuffix:@".lock"]) {
            return candidate;
        }

        NSUInteger nextLocation = NSMaxRange(endQuote);
        if (nextLocation >= [trimmed length]) {
            break;
        }
        scanRange = NSMakeRange(nextLocation, [trimmed length] - nextLocation);
    }

    NSCharacterSet *splitSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSCharacterSet *trimSet = [NSCharacterSet characterSetWithCharactersInString:@"'\"`:,.;()[]{}"];
    NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:splitSet];
    for (NSString *part in parts) {
        NSString *clean = [part stringByTrimmingCharactersInSet:trimSet];
        if ([clean hasSuffix:@".lock"]) {
            return clean;
        }
    }

    return nil;
}

static BOOL OMDGitRemoveStaleLockFile(NSString *lockPath, NSString *repoPath)
{
    NSString *normalizedLockPath = OMDTrimmedString(lockPath);
    if ([normalizedLockPath length] == 0) {
        return NO;
    }
    normalizedLockPath = [normalizedLockPath stringByStandardizingPath];
    if (![normalizedLockPath hasSuffix:@".lock"]) {
        return NO;
    }
    if ([normalizedLockPath rangeOfString:@"/.git/"].location == NSNotFound) {
        return NO;
    }

    NSString *normalizedRepoPath = OMDTrimmedString(repoPath);
    if ([normalizedRepoPath length] > 0) {
        normalizedRepoPath = [normalizedRepoPath stringByStandardizingPath];
        NSString *allowedPrefix = [[normalizedRepoPath stringByAppendingPathComponent:@".git"] stringByAppendingString:@"/"];
        if (![normalizedLockPath hasPrefix:allowedPrefix]) {
            return NO;
        }
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:normalizedLockPath isDirectory:&isDirectory] || isDirectory) {
        return NO;
    }

    NSDictionary *attributes = [fileManager attributesOfItemAtPath:normalizedLockPath error:NULL];
    NSDate *modifiedAt = [attributes objectForKey:NSFileModificationDate];
    if (modifiedAt != nil) {
        NSTimeInterval age = -[modifiedAt timeIntervalSinceNow];
        if (age >= 0.0 && age < OMDGitStaleLockMinimumAgeSeconds) {
            return NO;
        }
    }

    return [fileManager removeItemAtPath:normalizedLockPath error:NULL];
}

static NSString *OMDTrimmedComboBoxSelectionOrText(NSComboBox *comboBox)
{
    if (comboBox == nil) {
        return @"";
    }

    NSString *typedValue = OMDTrimmedString([comboBox stringValue]);
    NSString *resolved = nil;
    NSInteger selectedIndex = [comboBox indexOfSelectedItem];
    if (selectedIndex >= 0) {
        id selectedValue = nil;
        if ([comboBox respondsToSelector:@selector(objectValueOfSelectedItem)]) {
            selectedValue = [comboBox objectValueOfSelectedItem];
        }
        if (selectedValue == nil &&
            [comboBox respondsToSelector:@selector(itemObjectValueAtIndex:)] &&
            selectedIndex < [comboBox numberOfItems]) {
            selectedValue = [comboBox itemObjectValueAtIndex:selectedIndex];
        }
        if ([selectedValue respondsToSelector:@selector(description)]) {
            resolved = [selectedValue description];
        }
    }

    if ([typedValue length] > 0) {
        if ([resolved length] == 0 ||
            [typedValue caseInsensitiveCompare:OMDTrimmedString(resolved)] != NSOrderedSame) {
            return typedValue;
        }
    }

    if ([resolved length] > 0) {
        [comboBox setStringValue:resolved];
        return OMDTrimmedString(resolved);
    }
    return typedValue;
}

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

static NSString *OMDDefaultCacheDirectory(void)
{
#if defined(__APPLE__)
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
#else
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *xdg = OMDTrimmedString([environment objectForKey:@"XDG_CACHE_HOME"]);
    if ([xdg length] > 0) {
        return [xdg stringByExpandingTildeInPath];
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:@".cache"];
#endif
}

@interface OMDExplorerController ()
- (NSInteger)selectedExplorerSourceModeControlIndex;
- (void)setSelectedExplorerSourceModeControlIndex:(NSInteger)index;
- (void)setupExplorerSidebar;
- (void)updateExplorerControlsVisibility;
- (void)updateNavigateUpButton;
- (void)reloadLocalExplorerEntries;
- (void)reloadGitHubExplorerEntries;
- (void)setExplorerLoading:(BOOL)loading message:(NSString *)message;
- (void)applyExplorerListFontPreference;
- (BOOL)isExplorerIncludeForkArchivedEnabled;
- (void)setExplorerIncludeForkArchivedEnabled:(BOOL)enabled;
- (BOOL)isExplorerShowHiddenFilesEnabled;
- (void)setExplorerShowHiddenFilesEnabled:(BOOL)enabled;
- (void)explorerSourceModeChanged:(id)sender;
- (void)explorerNavigateUp:(id)sender;
- (void)explorerGitHubUserChanged:(id)sender;
- (void)explorerGitHubRepoChanged:(id)sender;
- (void)explorerGitHubIncludeForkArchivedChanged:(id)sender;
- (void)explorerShowHiddenFilesChanged:(id)sender;
- (void)explorerItemClicked:(id)sender;
- (void)explorerItemDoubleClicked:(id)sender;
- (void)openExplorerEntry:(NSDictionary *)entry inNewTab:(BOOL)inNewTab;
- (void)openGitHubFileEntry:(NSDictionary *)entry inNewTab:(BOOL)inNewTab;
- (void)loadGitHubRepositoriesForUser:(NSString *)user;
- (void)loadGitHubCachedContentsForUser:(NSString *)user repo:(NSString *)repo path:(NSString *)path;
- (NSString *)gitHubCacheRootPath;
- (NSString *)gitHubCachePathForUser:(NSString *)user repository:(NSString *)repository;
- (NSArray *)cachedGitHubUsers;
- (NSArray *)cachedGitHubRepositoriesForUser:(NSString *)user;
- (void)refreshCachedGitHubUserOptions;
- (BOOL)runGitArguments:(NSArray *)arguments
            inDirectory:(NSString *)directory
                 output:(NSString **)output
                  error:(NSError **)error;
- (BOOL)ensureGitHubRepositoryCacheForUser:(NSString *)user
                                      repo:(NSString *)repo
                                 cachePath:(NSString **)cachePath
                                     error:(NSError **)error;
- (NSArray *)gitHubEntriesForRepositoryCachePath:(NSString *)repoCachePath
                                     relativePath:(NSString *)relativePath
                                     resolvedPath:(NSString **)resolvedPath
                                            error:(NSError **)error;
- (OMDGitHubClient *)gitHubClient;
@end

@implementation OMDExplorerController

- (instancetype)initWithDelegate:(id<OMDExplorerControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        _explorerEntries = [[NSMutableArray alloc] init];
        _explorerGitHubRepos = [[NSArray alloc] init];
        _explorerSourceMode = OMDExplorerSourceModeLocal;
        _explorerRequestToken = 0;
        _explorerIsLoading = NO;
    }
    return self;
}

- (void)dealloc
{
    [_gitHubClient release];
    [_explorerSourceModeControl release];
    [_explorerLocalRootLabel release];
    [_explorerGitHubUserLabel release];
    [_explorerGitHubUserComboBox release];
    [_explorerGitHubRepoComboBox release];
    [_explorerGitHubIncludeForkArchivedButton release];
    [_explorerShowHiddenFilesButton release];
    [_explorerNavigateUpButton release];
    [_explorerPathLabel release];
    [_explorerTableView setDelegate:nil];
    [_explorerTableView setDataSource:nil];
    [_explorerTableView release];
    [_explorerScrollView release];
    [_explorerEntries release];
    [_explorerGitHubRepos release];
    [_explorerLocalRootPath release];
    [_explorerLocalCurrentPath release];
    [_explorerGitHubUser release];
    [_explorerGitHubRepo release];
    [_explorerGitHubCurrentPath release];
    [_explorerGitHubRepoCachePath release];
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
    if (_explorerLocalRootLabel != nil) {
        [_explorerLocalRootLabel setFont:labelFont];
    }
    if (_explorerGitHubUserLabel != nil) {
        [_explorerGitHubUserLabel setFont:labelFont];
    }
    if (_explorerGitHubIncludeForkArchivedButton != nil) {
        [_explorerGitHubIncludeForkArchivedButton setFont:labelFont];
    }
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
    [_explorerLocalRootPath release];
    _explorerLocalRootPath = [resolved copy];

    [_explorerLocalCurrentPath release];
    _explorerLocalCurrentPath = [_explorerLocalRootPath copy];
    [self reloadExplorerEntries];
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

- (BOOL)isExplorerIncludeForkArchivedEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:OMDExplorerIncludeForkArchivedDefaultsKey];
}

- (void)setExplorerIncludeForkArchivedEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:OMDExplorerIncludeForkArchivedDefaultsKey];
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

- (NSString *)explorerGitHubTokenPreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults stringForKey:OMDExplorerGitHubTokenDefaultsKey];
    return OMDTrimmedString(token);
}

- (void)setExplorerGitHubTokenPreference:(NSString *)token
{
    NSString *trimmed = OMDTrimmedString(token);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([trimmed length] == 0) {
        [defaults removeObjectForKey:OMDExplorerGitHubTokenDefaultsKey];
    } else {
        [defaults setObject:trimmed forKey:OMDExplorerGitHubTokenDefaultsKey];
    }
}

- (OMDGitHubClient *)gitHubClient
{
    if (_gitHubClient == nil) {
        _gitHubClient = [[OMDGitHubClient alloc] init];
    }
    return _gitHubClient;
}

- (void)setupExplorerSidebar
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    if (_containerView == nil) {
        return;
    }

    NSRect bounds = [_containerView bounds];
    CGFloat width = NSWidth(bounds);
    CGFloat wideControlWidth = width - (metrics.explorerSidePadding * 2.0);
    if (wideControlWidth < 1.0) {
        wideControlWidth = 1.0;
    }
    CGFloat userComboWidth = width - (metrics.explorerSidePadding * 2.0) - 46.0;
    if (userComboWidth < 1.0) {
        userComboWidth = 1.0;
    }
    CGFloat navigateButtonWidth = 32.0;
#if defined(_WIN32)
    navigateButtonWidth = 44.0;
#endif
    CGFloat navigateButtonGap = 6.0;
    CGFloat pathWidth = width - (metrics.explorerSidePadding * 2.0) - navigateButtonWidth - navigateButtonGap;
    if (pathWidth < 1.0) {
        pathWidth = 1.0;
    }
    CGFloat scrollHeight = NSHeight(bounds) - 168.0;
    if (scrollHeight < 80.0) {
        scrollHeight = 80.0;
    }
    CGFloat scrollWidth = width - (metrics.explorerSidePadding * 2.0) + 4.0;
    if (scrollWidth < 1.0) {
        scrollWidth = 1.0;
    }
    NSFont *labelFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 12.0 : 11.0)];
    NSFont *pathFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 11.0 : 10.5)];

#if defined(_WIN32)
    _explorerSourceModeControl = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                                 NSHeight(bounds) - 34,
                                                                                 wideControlWidth,
                                                                                 metrics.explorerControlHeight)
                                                            pullsDown:NO];
    [(NSPopUpButton *)_explorerSourceModeControl removeAllItems];
    [(NSPopUpButton *)_explorerSourceModeControl addItemWithTitle:@"Local"];
    [(NSPopUpButton *)_explorerSourceModeControl addItemWithTitle:@"GitHub"];
    [(NSPopUpButton *)_explorerSourceModeControl setFont:labelFont];
#else
    _explorerSourceModeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                                      NSHeight(bounds) - 34,
                                                                                      wideControlWidth,
                                                                                      metrics.explorerControlHeight)];
    [(NSSegmentedControl *)_explorerSourceModeControl setSegmentCount:2];
    [(NSSegmentedControl *)_explorerSourceModeControl setLabel:@"Local" forSegment:0];
    [(NSSegmentedControl *)_explorerSourceModeControl setLabel:@"GitHub" forSegment:1];
#endif
    [self setSelectedExplorerSourceModeControlIndex:_explorerSourceMode];
    [_explorerSourceModeControl setTarget:self];
    [_explorerSourceModeControl setAction:@selector(explorerSourceModeChanged:)];
    [_explorerSourceModeControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerSourceModeControl];

    _explorerLocalRootLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding, NSHeight(bounds) - 60, wideControlWidth, 16)];
    [_explorerLocalRootLabel setBezeled:NO];
    [_explorerLocalRootLabel setEditable:NO];
    [_explorerLocalRootLabel setSelectable:NO];
    [_explorerLocalRootLabel setDrawsBackground:NO];
    [_explorerLocalRootLabel setFont:labelFont];
    [_explorerLocalRootLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerLocalRootLabel];

    _explorerGitHubUserLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding, NSHeight(bounds) - 60, 44, 20)];
    [_explorerGitHubUserLabel setBezeled:NO];
    [_explorerGitHubUserLabel setEditable:NO];
    [_explorerGitHubUserLabel setSelectable:NO];
    [_explorerGitHubUserLabel setDrawsBackground:NO];
    [_explorerGitHubUserLabel setStringValue:@"User:"];
    [_explorerGitHubUserLabel setFont:labelFont];
    [_explorerGitHubUserLabel setAutoresizingMask:NSViewMinYMargin];
    [_containerView addSubview:_explorerGitHubUserLabel];

    _explorerGitHubUserComboBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding + 46.0,
                                                                                NSHeight(bounds) - 64,
                                                                                userComboWidth,
                                                                                metrics.explorerControlHeight)];
    [_explorerGitHubUserComboBox setUsesDataSource:NO];
    [_explorerGitHubUserComboBox setCompletes:YES];
    [_explorerGitHubUserComboBox setTarget:self];
    [_explorerGitHubUserComboBox setAction:@selector(explorerGitHubUserChanged:)];
    [_explorerGitHubUserComboBox setDelegate:self];
    [_explorerGitHubUserComboBox setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerGitHubUserComboBox];

    _explorerGitHubRepoComboBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                                NSHeight(bounds) - 90,
                                                                                wideControlWidth,
                                                                                metrics.explorerControlHeight)];
    [_explorerGitHubRepoComboBox setUsesDataSource:NO];
    [_explorerGitHubRepoComboBox setCompletes:YES];
    [_explorerGitHubRepoComboBox setTarget:self];
    [_explorerGitHubRepoComboBox setAction:@selector(explorerGitHubRepoChanged:)];
    [_explorerGitHubRepoComboBox setDelegate:self];
    [_explorerGitHubRepoComboBox setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerGitHubRepoComboBox];

    _explorerGitHubIncludeForkArchivedButton = [[NSButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                                           NSHeight(bounds) - 116,
                                                                                           wideControlWidth,
                                                                                           metrics.explorerMinorControlHeight)];
    [_explorerGitHubIncludeForkArchivedButton setButtonType:NSSwitchButton];
    [_explorerGitHubIncludeForkArchivedButton setTitle:@"Include forked + archived repos"];
    [_explorerGitHubIncludeForkArchivedButton setFont:labelFont];
    [_explorerGitHubIncludeForkArchivedButton setTarget:self];
    [_explorerGitHubIncludeForkArchivedButton setAction:@selector(explorerGitHubIncludeForkArchivedChanged:)];
    [_explorerGitHubIncludeForkArchivedButton setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerGitHubIncludeForkArchivedButton];

    _explorerShowHiddenFilesButton = [[NSButton alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                                NSHeight(bounds) - 84,
                                                                                wideControlWidth,
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
                                                                           NSHeight(bounds) - 144,
                                                                           navigateButtonWidth,
                                                                           metrics.explorerControlHeight)];
    [_explorerNavigateUpButton setTitle:@""];
    [_explorerNavigateUpButton setBezelStyle:NSRoundedBezelStyle];
    [_explorerNavigateUpButton setImage:OMDToolbarTintedImage(OMDExplorerNavigateParentBaseImage(),
                                                              OMDResolvedControlTextColor())];
#if defined(_WIN32)
    [_explorerNavigateUpButton setTitle:@"Up"];
    [_explorerNavigateUpButton setFont:labelFont];
    [_explorerNavigateUpButton setImagePosition:NSImageLeft];
#else
    [_explorerNavigateUpButton setImagePosition:NSImageOnly];
#endif
    [_explorerNavigateUpButton setToolTip:@"Go to the parent folder or repository path"];
    [_explorerNavigateUpButton setTarget:self];
    [_explorerNavigateUpButton setAction:@selector(explorerNavigateUp:)];
    [_explorerNavigateUpButton setAutoresizingMask:NSViewMinYMargin];
    [_containerView addSubview:_explorerNavigateUpButton];

    _explorerPathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding + navigateButtonWidth + navigateButtonGap,
                                                                       NSHeight(bounds) - 140,
                                                                       pathWidth,
                                                                       18)];
    [_explorerPathLabel setBezeled:NO];
    [_explorerPathLabel setEditable:NO];
    [_explorerPathLabel setSelectable:NO];
    [_explorerPathLabel setDrawsBackground:NO];
    [_explorerPathLabel setFont:pathFont];
    [_explorerPathLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_containerView addSubview:_explorerPathLabel];

    _explorerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(MAX(0.0, metrics.explorerSidePadding - 2.0),
                                                                         10,
                                                                         scrollWidth,
                                                                         scrollHeight)];
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

    [_explorerLocalRootPath release];
    _explorerLocalRootPath = [[self explorerLocalRootPathPreference] copy];
    [_explorerLocalCurrentPath release];
    _explorerLocalCurrentPath = [_explorerLocalRootPath copy];

    [_explorerGitHubUser release];
    _explorerGitHubUser = [@"" copy];
    [_explorerGitHubRepo release];
    _explorerGitHubRepo = [@"" copy];
    [_explorerGitHubCurrentPath release];
    _explorerGitHubCurrentPath = [@"" copy];
    [_explorerGitHubRepoCachePath release];
    _explorerGitHubRepoCachePath = [@"" copy];

    [_explorerGitHubIncludeForkArchivedButton setState:([self isExplorerIncludeForkArchivedEnabled] ? NSOnState : NSOffState)];
    [self refreshCachedGitHubUserOptions];
    [self updateExplorerControlsVisibility];
}

// Up is available below the local root, or inside a GitHub repository.
- (void)updateNavigateUpButton
{
    BOOL githubMode = (_explorerSourceMode == OMDExplorerSourceModeGitHub);
    BOOL canNavigateUp = NO;
    if (githubMode) {
        canNavigateUp = (_explorerGitHubCurrentPath != nil && [_explorerGitHubCurrentPath length] > 0);
    } else {
        canNavigateUp = (_explorerLocalCurrentPath != nil &&
                         _explorerLocalRootPath != nil &&
                         ![_explorerLocalCurrentPath isEqualToString:_explorerLocalRootPath]);
    }
    [_explorerNavigateUpButton setImage:OMDToolbarTintedImage(OMDExplorerNavigateParentBaseImage(),
                                                              (canNavigateUp ? OMDResolvedControlTextColor()
                                                                             : OMDResolvedMutedTextColor()))];
    [_explorerNavigateUpButton setEnabled:canNavigateUp];
}

- (void)updateExplorerControlsVisibility
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    BOOL githubMode = (_explorerSourceMode == OMDExplorerSourceModeGitHub);
    [self setSelectedExplorerSourceModeControlIndex:_explorerSourceMode];
    if (_explorerGitHubUserComboBox != nil) {
        [_explorerGitHubUserComboBox setStringValue:(_explorerGitHubUser != nil ? _explorerGitHubUser : @"")];
    }
    if (_explorerGitHubRepoComboBox != nil) {
    [_explorerGitHubRepoComboBox setStringValue:(_explorerGitHubRepo != nil ? _explorerGitHubRepo : @"")];
    }

    [_explorerLocalRootLabel setHidden:githubMode];
    [_explorerShowHiddenFilesButton setHidden:githubMode];
    [_explorerGitHubUserLabel setHidden:!githubMode];
    [_explorerGitHubUserComboBox setHidden:!githubMode];
    [_explorerGitHubRepoComboBox setHidden:!githubMode];
    [_explorerGitHubIncludeForkArchivedButton setHidden:!githubMode];
    [_explorerShowHiddenFilesButton setState:([self isExplorerShowHiddenFilesEnabled] ? NSOnState : NSOffState)];
    [self updateNavigateUpButton];

    NSRect bounds = [_containerView bounds];
    CGFloat width = NSWidth(bounds);
    CGFloat height = NSHeight(bounds);
    CGFloat wideControlWidth = width - (metrics.explorerSidePadding * 2.0);
    if (wideControlWidth < 1.0) {
        wideControlWidth = 1.0;
    }
    CGFloat userComboWidth = width - (metrics.explorerSidePadding * 2.0) - 46.0;
    if (userComboWidth < 1.0) {
        userComboWidth = 1.0;
    }
    CGFloat navigateButtonWidth = 32.0;
#if defined(_WIN32)
    navigateButtonWidth = 44.0;
#endif
    CGFloat navigateButtonGap = 6.0;
    CGFloat pathWidth = width - (metrics.explorerSidePadding * 2.0) - navigateButtonWidth - navigateButtonGap;
    if (pathWidth < 1.0) {
        pathWidth = 1.0;
    }
    CGFloat scrollWidth = width - (metrics.explorerSidePadding * 2.0) + 4.0;
    if (scrollWidth < 1.0) {
        scrollWidth = 1.0;
    }
    [_explorerSourceModeControl setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                    height - metrics.explorerTopPadding - metrics.explorerControlHeight,
                                                    wideControlWidth,
                                                    metrics.explorerControlHeight)];
    [_explorerLocalRootLabel setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                 height - metrics.explorerTopPadding - metrics.explorerControlHeight - 26.0,
                                                 wideControlWidth,
                                                 16)];
    [_explorerGitHubUserLabel setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                  height - metrics.explorerTopPadding - metrics.explorerControlHeight - 28.0,
                                                  44,
                                                  20)];
    [_explorerGitHubUserComboBox setFrame:NSMakeRect(metrics.explorerSidePadding + 46.0,
                                                     height - metrics.explorerTopPadding - metrics.explorerControlHeight - 32.0,
                                                     userComboWidth,
                                                     metrics.explorerControlHeight)];
    [_explorerGitHubRepoComboBox setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                     height - metrics.explorerTopPadding - metrics.explorerControlHeight - 64.0,
                                                     wideControlWidth,
                                                     metrics.explorerControlHeight)];
    [_explorerGitHubIncludeForkArchivedButton setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                                  height - metrics.explorerTopPadding - metrics.explorerControlHeight - 94.0,
                                                                  wideControlWidth,
                                                                  metrics.explorerMinorControlHeight)];
    [_explorerShowHiddenFilesButton setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                        height - metrics.explorerTopPadding - metrics.explorerControlHeight - 58.0,
                                                        wideControlWidth,
                                                        metrics.explorerMinorControlHeight)];

    CGFloat navigateUpY = (githubMode
                           ? (height - metrics.explorerTopPadding - metrics.explorerControlHeight - 122.0)
                           : (height - metrics.explorerTopPadding - metrics.explorerControlHeight - 94.0));
    CGFloat pathY = navigateUpY + 4.0;
    CGFloat scrollBottomInset = 10.0;
    CGFloat scrollGap = 8.0;
    [_explorerNavigateUpButton setFrame:NSMakeRect(metrics.explorerSidePadding,
                                                   navigateUpY,
                                                   navigateButtonWidth,
                                                   metrics.explorerControlHeight)];
    [_explorerPathLabel setFrame:NSMakeRect(metrics.explorerSidePadding + navigateButtonWidth + navigateButtonGap,
                                            pathY,
                                            pathWidth,
                                            18)];
    CGFloat scrollTop = MIN(NSMinY([_explorerNavigateUpButton frame]),
                            NSMinY([_explorerPathLabel frame])) - scrollGap;
    CGFloat scrollHeight = scrollTop - scrollBottomInset;
    if (scrollHeight < 1.0) {
        scrollHeight = 1.0;
    }
    [_explorerScrollView setFrame:NSMakeRect(MAX(0.0, metrics.explorerSidePadding - 2.0),
                                             scrollBottomInset,
                                             scrollWidth,
                                             scrollHeight)];
    NSTableColumn *nameColumn = [_explorerTableView tableColumnWithIdentifier:@"ExplorerName"];
    if (nameColumn != nil) {
        [nameColumn setWidth:NSWidth([_explorerScrollView bounds]) - 2.0];
    }

    if (!githubMode) {
        NSString *root = (_explorerLocalRootPath != nil ? _explorerLocalRootPath : [self explorerLocalRootPathPreference]);
        [_explorerLocalRootLabel setStringValue:[NSString stringWithFormat:@"Root: %@", root]];
    }
}

- (void)setExplorerLoading:(BOOL)loading message:(NSString *)message
{
    _explorerIsLoading = loading;
    [_explorerTableView setEnabled:!loading];
    if (loading) {
        [_explorerEntries removeAllObjects];
        [_explorerTableView reloadData];
        if (message != nil) {
            [_explorerPathLabel setStringValue:message];
        }
    }
}

- (void)reloadExplorerEntries
{
    [self updateExplorerControlsVisibility];
    if (_explorerSourceMode == OMDExplorerSourceModeGitHub) {
        [self reloadGitHubExplorerEntries];
    } else {
        [self reloadLocalExplorerEntries];
    }
}

- (void)reloadLocalExplorerEntries
{
    [self setExplorerLoading:NO message:nil];
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
    [_explorerPathLabel setStringValue:[NSString stringWithFormat:@"Local: %@", _explorerLocalCurrentPath]];
    [_explorerLocalRootLabel setStringValue:[NSString stringWithFormat:@"Root: %@", _explorerLocalRootPath]];
}

- (void)reloadGitHubExplorerEntries
{
    [self setExplorerLoading:NO message:nil];
    NSString *trimmedUser = OMDTrimmedString(_explorerGitHubUser);
    if ([trimmedUser length] == 0) {
        [_explorerEntries removeAllObjects];
        [_explorerTableView reloadData];
        [_explorerPathLabel setStringValue:@"Enter a GitHub user."];
        return;
    }

    if ([_explorerGitHubRepos count] == 0) {
        NSString *manualRepo = OMDTrimmedString(_explorerGitHubRepo);
        if ([manualRepo length] > 0) {
            [self loadGitHubCachedContentsForUser:trimmedUser repo:manualRepo path:_explorerGitHubCurrentPath];
            return;
        }
        [self loadGitHubRepositoriesForUser:trimmedUser];
        return;
    }

    NSString *trimmedRepo = OMDTrimmedString(_explorerGitHubRepo);
    if ([trimmedRepo length] == 0) {
        [_explorerEntries removeAllObjects];
        [_explorerTableView reloadData];
        [_explorerPathLabel setStringValue:@"Choose a repository."];
        return;
    }

    [self loadGitHubCachedContentsForUser:trimmedUser repo:trimmedRepo path:_explorerGitHubCurrentPath];
}

- (NSString *)gitHubCacheRootPath
{
    NSString *root = [OMDDefaultCacheDirectory() stringByAppendingPathComponent:@"ObjcMarkdownViewer/github"];
    return [root stringByExpandingTildeInPath];
}

- (NSString *)gitHubCachePathForUser:(NSString *)user repository:(NSString *)repository
{
    NSString *trimmedUser = OMDTrimmedString(user);
    NSString *trimmedRepo = OMDTrimmedString(repository);
    if ([trimmedUser length] == 0 || [trimmedRepo length] == 0) {
        return nil;
    }
    NSString *root = [self gitHubCacheRootPath];
    return [[root stringByAppendingPathComponent:trimmedUser] stringByAppendingPathComponent:trimmedRepo];
}

- (NSArray *)cachedGitHubUsers
{
    NSString *root = [self gitHubCacheRootPath];
    NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL];
    if (children == nil) {
        return [NSArray array];
    }

    NSMutableArray *users = [NSMutableArray array];
    for (NSString *candidate in children) {
        if (candidate == nil || [candidate length] == 0 ||
            [candidate isEqualToString:@"."] ||
            [candidate isEqualToString:@".."]) {
            continue;
        }
        NSString *fullPath = [root stringByAppendingPathComponent:candidate];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory] || !isDirectory) {
            continue;
        }
        if ([[self cachedGitHubRepositoriesForUser:candidate] count] > 0) {
            [users addObject:candidate];
        }
    }
    [users sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return users;
}

- (NSArray *)cachedGitHubRepositoriesForUser:(NSString *)user
{
    NSString *trimmedUser = OMDTrimmedString(user);
    if ([trimmedUser length] == 0) {
        return [NSArray array];
    }

    NSString *userRoot = [[self gitHubCacheRootPath] stringByAppendingPathComponent:trimmedUser];
    NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:userRoot error:NULL];
    if (children == nil) {
        return [NSArray array];
    }

    NSMutableArray *repos = [NSMutableArray array];
    for (NSString *candidate in children) {
        if (candidate == nil || [candidate length] == 0 ||
            [candidate isEqualToString:@"."] ||
            [candidate isEqualToString:@".."]) {
            continue;
        }

        NSString *repoPath = [userRoot stringByAppendingPathComponent:candidate];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:repoPath isDirectory:&isDirectory] || !isDirectory) {
            continue;
        }
        NSString *gitDir = [repoPath stringByAppendingPathComponent:@".git"];
        BOOL hasGitDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:gitDir isDirectory:&hasGitDirectory] || !hasGitDirectory) {
            continue;
        }
        [repos addObject:candidate];
    }

    [repos sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return repos;
}

- (void)refreshCachedGitHubUserOptions
{
    if (_explorerGitHubUserComboBox == nil) {
        return;
    }

    NSArray *cachedUsers = [self cachedGitHubUsers];
    [_explorerGitHubUserComboBox removeAllItems];
    for (NSString *user in cachedUsers) {
        [_explorerGitHubUserComboBox addItemWithObjectValue:user];
    }

    NSString *selectedUser = OMDTrimmedString(_explorerGitHubUser);
    if ([selectedUser length] > 0) {
        BOOL found = NO;
        for (NSString *user in cachedUsers) {
            if ([selectedUser caseInsensitiveCompare:user] == NSOrderedSame) {
                found = YES;
                break;
            }
        }
        if (!found) {
            [_explorerGitHubUserComboBox addItemWithObjectValue:selectedUser];
        }
    }
    [_explorerGitHubUserComboBox setStringValue:(selectedUser != nil ? selectedUser : @"")];
}

- (BOOL)runGitArguments:(NSArray *)arguments
            inDirectory:(NSString *)directory
                 output:(NSString **)output
                  error:(NSError **)error
{
    NSString *gitPath = OMDExecutablePathNamed(@"git");
    if (gitPath == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:OMDGitHubCacheErrorDomain
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Git is required for GitHub cache browsing." }];
        }
        return NO;
    }

    NSString *stdoutText = @"";
    NSString *stderrText = @"";
    NSString *launchFailureReason = nil;
    BOOL succeeded = NO;
    BOOL lastAttemptLaunched = YES;

    NSInteger attempt = 0;
    for (; attempt < 3; attempt++) {
        NSTask *task = [[[NSTask alloc] init] autorelease];
        NSMutableArray *taskArguments = [NSMutableArray array];
        [task setLaunchPath:gitPath];
        if (arguments != nil) {
            [taskArguments addObjectsFromArray:arguments];
        }
        [task setArguments:taskArguments];
        if (directory != nil && [directory length] > 0) {
            [task setCurrentDirectoryPath:directory];
        }
        NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
        [environment setObject:@"0" forKey:@"GIT_TERMINAL_PROMPT"];
        [environment setObject:@"never" forKey:@"GIT_ASKPASS"];
        [environment setObject:@"Never" forKey:@"GCM_INTERACTIVE"];
        [task setEnvironment:environment];

        NSPipe *stdoutPipe = [NSPipe pipe];
        NSPipe *stderrPipe = [NSPipe pipe];
        [task setStandardOutput:stdoutPipe];
        [task setStandardError:stderrPipe];
        if ([NSFileHandle respondsToSelector:@selector(fileHandleWithNullDevice)]) {
            [task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
        }

        BOOL launched = YES;
        NSString *attemptLaunchFailureReason = nil;
        @try {
            [task launch];
            [task waitUntilExit];
        } @catch (NSException *exception) {
            launched = NO;
            attemptLaunchFailureReason = [exception reason];
        }
        lastAttemptLaunched = launched;
        launchFailureReason = attemptLaunchFailureReason;

        NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
        NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        NSString *attemptStdoutText = [[[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] autorelease];
        NSString *attemptStderrText = [[[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] autorelease];
        stdoutText = (attemptStdoutText != nil ? attemptStdoutText : @"");
        stderrText = (attemptStderrText != nil ? attemptStderrText : @"");

        if (launched && [task terminationStatus] == 0) {
            succeeded = YES;
            break;
        }

        NSString *reason = OMDTrimmedString(stderrText);
        if (!OMDGitErrorLooksLikeLockConflict(reason)) {
            break;
        }

        if (attempt == 0) {
            [NSThread sleepForTimeInterval:OMDGitLockRetryDelaySeconds];
            continue;
        }
        if (attempt == 1) {
            NSString *lockPath = OMDGitLockPathFromErrorReason(reason);
            if (!OMDGitRemoveStaleLockFile(lockPath, directory)) {
                break;
            }
            [NSThread sleepForTimeInterval:OMDGitLockRetryDelaySeconds];
            continue;
        }
    }

    if (output != NULL) {
        *output = [stdoutText copy];
    }
    if (succeeded) {
        return YES;
    }

    if (error != NULL) {
        NSString *reason = OMDTrimmedString(stderrText);
        if ([reason length] == 0 && [launchFailureReason length] > 0) {
            reason = launchFailureReason;
        }
        if ([reason length] == 0) {
            reason = @"git exited with a non-zero status.";
        }
        BOOL launchFailure = (!lastAttemptLaunched && [launchFailureReason length] > 0);
        *error = [NSError errorWithDomain:OMDGitHubCacheErrorDomain
                                     code:(launchFailure ? 2 : 3)
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: (launchFailure
                                                                 ? @"Unable to run git command."
                                                                 : @"Git command failed."),
                                     NSLocalizedFailureReasonErrorKey: reason
                                 }];
    }
    return NO;
}

- (BOOL)ensureGitHubRepositoryCacheForUser:(NSString *)user
                                      repo:(NSString *)repo
                                 cachePath:(NSString **)cachePath
                                     error:(NSError **)error
{
    NSString *trimmedUser = OMDTrimmedString(user);
    NSString *trimmedRepo = OMDTrimmedString(repo);
    if ([trimmedUser length] == 0 || [trimmedRepo length] == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:OMDGitHubCacheErrorDomain
                                         code:4
                                     userInfo:@{ NSLocalizedDescriptionKey: @"GitHub user/repository is required." }];
        }
        return NO;
    }

    NSString *root = [self gitHubCacheRootPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSString *userRoot = [root stringByAppendingPathComponent:trimmedUser];
    if (![fileManager createDirectoryAtPath:userRoot withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSString *repoPath = [userRoot stringByAppendingPathComponent:trimmedRepo];
    NSString *remoteURL = [NSString stringWithFormat:@"https://github.com/%@/%@.git", trimmedUser, trimmedRepo];
    NSString *gitDir = [repoPath stringByAppendingPathComponent:@".git"];

    BOOL isDirectory = NO;
    BOOL exists = [fileManager fileExistsAtPath:repoPath isDirectory:&isDirectory];
    if (exists) {
        BOOL hasGit = NO;
        BOOL hasGitDirectory = [fileManager fileExistsAtPath:gitDir isDirectory:&hasGit] && hasGit;
        if (!isDirectory || !hasGitDirectory) {
            // Cache path is stale or partially created from a failed attempt; reset it.
            [fileManager removeItemAtPath:repoPath error:NULL];
            exists = [fileManager fileExistsAtPath:repoPath isDirectory:&isDirectory];
        }
    }

    if (!exists) {
        NSError *cloneError = nil;
        BOOL cloned = [self runGitArguments:@[@"clone", @"--quiet", @"--depth", @"1", remoteURL, repoPath]
                                inDirectory:nil
                                     output:NULL
                                      error:&cloneError];
        if (!cloned) {
            BOOL hasGitAfterFailure = NO;
            BOOL gitDirectoryFlag = NO;
            if ([fileManager fileExistsAtPath:gitDir isDirectory:&gitDirectoryFlag] && gitDirectoryFlag) {
                hasGitAfterFailure = YES;
            }

            if (!hasGitAfterFailure) {
                NSString *reason = [[cloneError userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
                NSRange existsRange = [reason rangeOfString:@"already exists and is not an empty directory"
                                                    options:NSCaseInsensitiveSearch];
                if (existsRange.location != NSNotFound) {
                    [fileManager removeItemAtPath:repoPath error:NULL];
                    cloned = [self runGitArguments:@[@"clone", @"--quiet", @"--depth", @"1", remoteURL, repoPath]
                                       inDirectory:nil
                                            output:NULL
                                             error:&cloneError];
                }
            } else {
                cloned = YES;
            }
        }

        if (!cloned) {
            if (error != NULL) {
                *error = cloneError;
            }
            return NO;
        }
    }

    BOOL hasGit = NO;
    if (![fileManager fileExistsAtPath:gitDir isDirectory:&hasGit] || !hasGit) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:OMDGitHubCacheErrorDomain
                                         code:5
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Unable to initialize GitHub repository cache." }];
        }
        return NO;
    }

    [self runGitArguments:@[@"remote", @"set-url", @"origin", remoteURL]
              inDirectory:repoPath
                   output:NULL
                    error:NULL];

    NSError *fetchError = nil;
    BOOL fetched = [self runGitArguments:@[@"fetch", @"--quiet", @"--depth", @"1", @"origin"]
                             inDirectory:repoPath
                                  output:NULL
                                   error:&fetchError];
    if (fetched) {
        BOOL checkedOut = [self runGitArguments:@[@"checkout", @"--quiet", @"-f", @"--detach", @"origin/HEAD"]
                                    inDirectory:repoPath
                                         output:NULL
                                          error:NULL];
        if (!checkedOut) {
            checkedOut = [self runGitArguments:@[@"checkout", @"--quiet", @"-f", @"--detach", @"origin/main"]
                                    inDirectory:repoPath
                                         output:NULL
                                          error:NULL];
        }
        if (!checkedOut) {
            [self runGitArguments:@[@"checkout", @"--quiet", @"-f", @"--detach", @"origin/master"]
                      inDirectory:repoPath
                           output:NULL
                            error:NULL];
        }
        [self runGitArguments:@[@"reset", @"--quiet", @"--hard"]
                  inDirectory:repoPath
                       output:NULL
                        error:NULL];
    } else {
        BOOL hasHead = [self runGitArguments:@[@"rev-parse", @"--verify", @"HEAD"]
                                 inDirectory:repoPath
                                      output:NULL
                                       error:NULL];
        if (!hasHead) {
            if (error != NULL) {
                *error = fetchError;
            }
            return NO;
        }
    }

    if (cachePath != NULL) {
        *cachePath = [repoPath copy];
    }
    return YES;
}

- (NSArray *)gitHubEntriesForRepositoryCachePath:(NSString *)repoCachePath
                                     relativePath:(NSString *)relativePath
                                     resolvedPath:(NSString **)resolvedPath
                                            error:(NSError **)error
{
    NSString *normalizedPath = OMDNormalizedRelativePath(relativePath);
    NSString *directoryPath = repoCachePath;
    if ([normalizedPath length] > 0) {
        directoryPath = [repoCachePath stringByAppendingPathComponent:normalizedPath];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:directoryPath isDirectory:&isDirectory] || !isDirectory) {
        normalizedPath = @"";
        directoryPath = repoCachePath;
    }

    NSError *contentsError = nil;
    NSArray *children = [fileManager contentsOfDirectoryAtPath:directoryPath error:&contentsError];
    if (children == nil) {
        if (error != NULL) {
            *error = contentsError;
        }
        return nil;
    }

    NSMutableArray *sortedChildren = [children mutableCopy];
    [sortedChildren sortUsingComparator:^NSComparisonResult(id leftValue, id rightValue) {
        NSString *left = (NSString *)leftValue;
        NSString *right = (NSString *)rightValue;
        NSString *leftPath = [directoryPath stringByAppendingPathComponent:left];
        NSString *rightPath = [directoryPath stringByAppendingPathComponent:right];
        BOOL leftDir = NO;
        BOOL rightDir = NO;
        [fileManager fileExistsAtPath:leftPath isDirectory:&leftDir];
        [fileManager fileExistsAtPath:rightPath isDirectory:&rightDir];
        if (leftDir != rightDir) {
            return leftDir ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left compare:right options:NSCaseInsensitiveSearch];
    }];

    NSMutableArray *entries = [NSMutableArray array];
    if ([normalizedPath length] > 0) {
        NSString *parent = [normalizedPath stringByDeletingLastPathComponent];
        [entries addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                            @"..", @"name",
                            parent, @"path",
                            [NSNumber numberWithBool:YES], @"isDirectory",
                            [NSNumber numberWithBool:YES], @"isParent",
                            [NSNumber numberWithInteger:0], @"colorTier",
                            nil]];
    }

    for (NSString *name in sortedChildren) {
        if ([name isEqualToString:@"."] ||
            [name isEqualToString:@".."] ||
            [name isEqualToString:@".git"]) {
            continue;
        }

        NSString *fullPath = [directoryPath stringByAppendingPathComponent:name];
        BOOL childIsDirectory = NO;
        if (![fileManager fileExistsAtPath:fullPath isDirectory:&childIsDirectory]) {
            continue;
        }

        NSString *relativeEntryPath = nil;
        if ([normalizedPath length] > 0) {
            relativeEntryPath = [normalizedPath stringByAppendingPathComponent:name];
        } else {
            relativeEntryPath = name;
        }

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        [entry setObject:name forKey:@"name"];
        [entry setObject:relativeEntryPath forKey:@"path"];
        [entry setObject:[NSNumber numberWithBool:childIsDirectory] forKey:@"isDirectory"];
        [entry setObject:[NSNumber numberWithBool:NO] forKey:@"isParent"];
        [entry setObject:[NSNumber numberWithInteger:(childIsDirectory ? 0 : OMDExplorerFileColorTierForPath(relativeEntryPath))]
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

    if (resolvedPath != NULL) {
        *resolvedPath = [normalizedPath copy];
    }
    return entries;
}

- (void)loadGitHubRepositoriesForUser:(NSString *)user
{
    NSString *trimmedUser = OMDTrimmedString(user);
    [_explorerGitHubUser release];
    _explorerGitHubUser = [trimmedUser copy];
    [self refreshCachedGitHubUserOptions];

    NSArray *cachedRepoNames = [[self cachedGitHubRepositoriesForUser:trimmedUser] retain];
    if ([trimmedUser length] == 0) {
        [_explorerGitHubRepos release];
        _explorerGitHubRepos = [[NSArray alloc] init];
        [_explorerGitHubRepoComboBox removeAllItems];
        [_explorerEntries removeAllObjects];
        [_explorerTableView reloadData];
        [cachedRepoNames release];
        return;
    }

    NSUInteger token = ++_explorerRequestToken;
    BOOL includeForksAndArchived = [self isExplorerIncludeForkArchivedEnabled];
    [self setExplorerLoading:YES message:@"Loading repositories..."];

    OMDGitHubClient *client = [[self gitHubClient] retain];
    NSString *requestUser = [trimmedUser copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *requestError = nil;
        NSArray *repos = [[client publicRepositoriesForUser:requestUser
                                   includeForksAndArchived:includeForksAndArchived
                                                     error:&requestError] retain];
        NSError *retainedError = [requestError retain];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != _explorerRequestToken) {
                [repos release];
                [retainedError release];
                [requestUser release];
                [client release];
                [cachedRepoNames release];
                return;
            }

            [self setExplorerLoading:NO message:nil];

            BOOL usingCachedFallback = NO;
            NSMutableArray *mergedRepos = [NSMutableArray array];
            if (retainedError == nil && repos != nil) {
                [mergedRepos addObjectsFromArray:repos];
            } else if ([cachedRepoNames count] > 0) {
                usingCachedFallback = YES;
                for (NSString *repoName in cachedRepoNames) {
                    [mergedRepos addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                            repoName, @"name",
                                            @"", @"updated_at",
                                            [NSNumber numberWithBool:NO], @"fork",
                                            [NSNumber numberWithBool:NO], @"archived",
                                            nil]];
                }
            } else {
                [_explorerEntries removeAllObjects];
                [_explorerTableView reloadData];
                [_explorerPathLabel setStringValue:@"Unable to load repositories."];
                NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                [alert setMessageText:@"GitHub repositories unavailable"];
                NSString *reason = [[retainedError userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
                NSString *detail = [retainedError localizedDescription];
                if (reason != nil && [reason length] > 0) {
                    detail = [NSString stringWithFormat:@"%@\n\n%@", detail, reason];
                }
                [alert setInformativeText:detail];
                [alert runModal];
                [repos release];
                [retainedError release];
                [requestUser release];
                [client release];
                [cachedRepoNames release];
                return;
            }

            if (!usingCachedFallback && [cachedRepoNames count] > 0) {
                for (NSString *cachedName in cachedRepoNames) {
                    BOOL exists = NO;
                    for (NSDictionary *repoRecord in mergedRepos) {
                        NSString *repoName = [repoRecord objectForKey:@"name"];
                        if (repoName != nil && [cachedName caseInsensitiveCompare:repoName] == NSOrderedSame) {
                            exists = YES;
                            break;
                        }
                    }
                    if (!exists) {
                        [mergedRepos addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                                cachedName, @"name",
                                                @"", @"updated_at",
                                                [NSNumber numberWithBool:NO], @"fork",
                                                [NSNumber numberWithBool:NO], @"archived",
                                                nil]];
                    }
                }
            }

            [_explorerGitHubRepos release];
            _explorerGitHubRepos = [mergedRepos copy];
            [_explorerGitHubRepoComboBox removeAllItems];
            for (NSDictionary *repoRecord in _explorerGitHubRepos) {
                NSString *repoName = [repoRecord objectForKey:@"name"];
                if (repoName != nil && [repoName length] > 0) {
                    [_explorerGitHubRepoComboBox addItemWithObjectValue:repoName];
                }
            }

            NSString *selectedRepo = OMDTrimmedString(_explorerGitHubRepo);
            BOOL selectedRepoStillExists = NO;
            for (NSDictionary *repoRecord in _explorerGitHubRepos) {
                NSString *repoName = [repoRecord objectForKey:@"name"];
                if (repoName != nil && [selectedRepo caseInsensitiveCompare:repoName] == NSOrderedSame) {
                    selectedRepo = repoName;
                    selectedRepoStillExists = YES;
                    break;
                }
            }
            if (!selectedRepoStillExists) {
                if ([_explorerGitHubRepos count] > 0) {
                    selectedRepo = [[_explorerGitHubRepos objectAtIndex:0] objectForKey:@"name"];
                } else {
                    selectedRepo = @"";
                }
            }

            [_explorerGitHubRepo release];
            _explorerGitHubRepo = [selectedRepo copy];
            [_explorerGitHubRepoComboBox setStringValue:(_explorerGitHubRepo != nil ? _explorerGitHubRepo : @"")];
            [_explorerGitHubCurrentPath release];
            _explorerGitHubCurrentPath = [@"" copy];
            [_explorerGitHubRepoCachePath release];
            _explorerGitHubRepoCachePath = [@"" copy];

            if (usingCachedFallback) {
                [_explorerPathLabel setStringValue:@"GitHub API unavailable. Showing cached repositories."];
            }

            if ([_explorerGitHubRepo length] == 0) {
                [_explorerEntries removeAllObjects];
                [_explorerTableView reloadData];
                if ([cachedRepoNames count] > 0) {
                    [_explorerPathLabel setStringValue:@"No repositories match current filter."];
                } else {
                    [_explorerPathLabel setStringValue:@"No public repositories found."];
                }
            } else {
                [self loadGitHubCachedContentsForUser:_explorerGitHubUser repo:_explorerGitHubRepo path:_explorerGitHubCurrentPath];
            }

            [repos release];
            [retainedError release];
            [requestUser release];
            [client release];
            [cachedRepoNames release];
        });

        [pool release];
    });
}

- (void)loadGitHubCachedContentsForUser:(NSString *)user repo:(NSString *)repo path:(NSString *)path
{
    NSString *trimmedUser = OMDTrimmedString(user);
    NSString *trimmedRepo = OMDTrimmedString(repo);
    NSString *trimmedPath = OMDNormalizedRelativePath(path);
    if ([trimmedUser length] == 0 || [trimmedRepo length] == 0) {
        return;
    }

    NSString *expectedCachePath = [self gitHubCachePathForUser:trimmedUser repository:trimmedRepo];
    BOOL shouldRefreshCache = YES;
    if (expectedCachePath != nil &&
        [_explorerGitHubRepoCachePath isEqualToString:expectedCachePath]) {
        BOOL isDirectory = NO;
        NSString *gitDir = [expectedCachePath stringByAppendingPathComponent:@".git"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:gitDir isDirectory:&isDirectory] && isDirectory) {
            shouldRefreshCache = NO;
        }
    }

    NSUInteger token = ++_explorerRequestToken;
    [self setExplorerLoading:YES message:(shouldRefreshCache ? @"Refreshing repository cache..." : @"Loading files...")];

    NSString *requestUser = [trimmedUser copy];
    NSString *requestRepo = [trimmedRepo copy];
    NSString *requestPath = [trimmedPath copy];
    NSString *requestExpectedCachePath = [expectedCachePath copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *cacheError = nil;
        NSString *repoCachePath = nil;
        BOOL cached = NO;
        if (shouldRefreshCache) {
            cached = [self ensureGitHubRepositoryCacheForUser:requestUser
                                                         repo:requestRepo
                                                    cachePath:&repoCachePath
                                                        error:&cacheError];
        } else {
            repoCachePath = [requestExpectedCachePath copy];
            cached = (repoCachePath != nil && [repoCachePath length] > 0);
        }

        NSArray *entries = nil;
        NSString *resolvedPath = nil;
        NSError *listingError = nil;
        if (cached) {
            entries = [[self gitHubEntriesForRepositoryCachePath:repoCachePath
                                                    relativePath:requestPath
                                                    resolvedPath:&resolvedPath
                                                           error:&listingError] retain];
        }

        NSError *finalError = nil;
        if (cacheError != nil) {
            finalError = [cacheError retain];
        } else if (listingError != nil) {
            finalError = [listingError retain];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != _explorerRequestToken) {
                [entries release];
                [finalError release];
                [repoCachePath release];
                [resolvedPath release];
                [requestUser release];
                [requestRepo release];
                [requestPath release];
                [requestExpectedCachePath release];
                return;
            }

            [self setExplorerLoading:NO message:nil];
            if (finalError != nil) {
                [_explorerEntries removeAllObjects];
                [_explorerTableView reloadData];
                [_explorerPathLabel setStringValue:@"Unable to load repository contents."];
                NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                [alert setMessageText:@"GitHub repository unavailable"];
                NSString *reason = [[finalError userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
                NSString *detail = [finalError localizedDescription];
                if (reason != nil && [reason length] > 0) {
                    detail = [NSString stringWithFormat:@"%@\n\n%@", detail, reason];
                }
                [alert setInformativeText:detail];
                [alert runModal];
                [entries release];
                [finalError release];
                [repoCachePath release];
                [resolvedPath release];
                [requestUser release];
                [requestRepo release];
                [requestPath release];
                [requestExpectedCachePath release];
                return;
            }

            [_explorerGitHubRepoCachePath release];
            _explorerGitHubRepoCachePath = [repoCachePath copy];
            [_explorerGitHubCurrentPath release];
            _explorerGitHubCurrentPath = [resolvedPath copy];

            for (NSMutableDictionary *entry in entries) {
                if ([entry objectForKey:@"githubUser"] == nil) {
                    [entry setObject:requestUser forKey:@"githubUser"];
                }
                if ([entry objectForKey:@"githubRepo"] == nil) {
                    [entry setObject:requestRepo forKey:@"githubRepo"];
                }
            }

            [_explorerEntries removeAllObjects];
            [_explorerEntries addObjectsFromArray:entries];
            [_explorerTableView reloadData];

            NSString *pathDisplay = ([_explorerGitHubCurrentPath length] > 0
                                     ? [@"/" stringByAppendingString:_explorerGitHubCurrentPath]
                                     : @"/");
            [_explorerPathLabel setStringValue:[NSString stringWithFormat:@"%@/%@%@",
                                                requestUser,
                                                requestRepo,
                                                pathDisplay]];
            [self refreshCachedGitHubUserOptions];

            [entries release];
            [finalError release];
            [repoCachePath release];
            [resolvedPath release];
            [requestUser release];
            [requestRepo release];
            [requestPath release];
            [requestExpectedCachePath release];
        });

        [pool release];
    });
}

- (void)explorerSourceModeChanged:(id)sender
{
    NSInteger mode = [self selectedExplorerSourceModeControlIndex];
    if (mode != OMDExplorerSourceModeGitHub) {
        mode = OMDExplorerSourceModeLocal;
    }
    _explorerSourceMode = mode;
    [self reloadExplorerEntries];
}

- (NSInteger)selectedExplorerSourceModeControlIndex
{
#if defined(_WIN32)
    if ([_explorerSourceModeControl isKindOfClass:[NSPopUpButton class]]) {
        return [(NSPopUpButton *)_explorerSourceModeControl indexOfSelectedItem];
    }
#else
    if ([_explorerSourceModeControl isKindOfClass:[NSSegmentedControl class]]) {
        return [(NSSegmentedControl *)_explorerSourceModeControl selectedSegment];
    }
#endif
    return OMDExplorerSourceModeLocal;
}

- (void)setSelectedExplorerSourceModeControlIndex:(NSInteger)index
{
    if (index != OMDExplorerSourceModeGitHub) {
        index = OMDExplorerSourceModeLocal;
    }
#if defined(_WIN32)
    if ([_explorerSourceModeControl isKindOfClass:[NSPopUpButton class]]) {
        [(NSPopUpButton *)_explorerSourceModeControl selectItemAtIndex:index];
    }
#else
    if ([_explorerSourceModeControl isKindOfClass:[NSSegmentedControl class]]) {
        [(NSSegmentedControl *)_explorerSourceModeControl setSelectedSegment:index];
    }
#endif
}

- (void)explorerNavigateUp:(id)sender
{
    (void)sender;
    if (_explorerSourceMode == OMDExplorerSourceModeGitHub) {
        if (_explorerGitHubCurrentPath != nil && [_explorerGitHubCurrentPath length] > 0) {
            NSString *parent = [_explorerGitHubCurrentPath stringByDeletingLastPathComponent];
            [_explorerGitHubCurrentPath release];
            _explorerGitHubCurrentPath = [parent copy];
            [self reloadGitHubExplorerEntries];
            [self updateNavigateUpButton];
        }
        return;
    }

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

- (void)explorerGitHubUserChanged:(id)sender
{
    (void)sender;
    NSString *user = OMDTrimmedComboBoxSelectionOrText(_explorerGitHubUserComboBox);
    [_explorerGitHubUser release];
    _explorerGitHubUser = [user copy];
    [_explorerGitHubRepo release];
    _explorerGitHubRepo = [@"" copy];
    [_explorerGitHubCurrentPath release];
    _explorerGitHubCurrentPath = [@"" copy];
    [_explorerGitHubRepoCachePath release];
    _explorerGitHubRepoCachePath = [@"" copy];
    [_explorerGitHubRepos release];
    _explorerGitHubRepos = [[NSArray alloc] init];
    [self loadGitHubRepositoriesForUser:_explorerGitHubUser];
}

- (void)explorerGitHubRepoChanged:(id)sender
{
    (void)sender;
    NSString *repo = OMDTrimmedComboBoxSelectionOrText(_explorerGitHubRepoComboBox);
    [_explorerGitHubRepo release];
    _explorerGitHubRepo = [repo copy];
    [_explorerGitHubCurrentPath release];
    _explorerGitHubCurrentPath = [@"" copy];
    [_explorerGitHubRepoCachePath release];
    _explorerGitHubRepoCachePath = [@"" copy];
    [self reloadGitHubExplorerEntries];
}

- (void)explorerGitHubIncludeForkArchivedChanged:(id)sender
{
    BOOL enabled = ([_explorerGitHubIncludeForkArchivedButton state] == NSOnState);
    [self setExplorerIncludeForkArchivedEnabled:enabled];
    [_explorerGitHubRepos release];
    _explorerGitHubRepos = [[NSArray alloc] init];
    [_explorerGitHubRepo release];
    _explorerGitHubRepo = [@"" copy];
    [_explorerGitHubCurrentPath release];
    _explorerGitHubCurrentPath = [@"" copy];
    [_explorerGitHubRepoCachePath release];
    _explorerGitHubRepoCachePath = [@"" copy];
    [self loadGitHubRepositoriesForUser:_explorerGitHubUser];
}

- (void)explorerShowHiddenFilesChanged:(id)sender
{
    (void)sender;
    BOOL enabled = ([_explorerShowHiddenFilesButton state] == NSOnState);
    [self setExplorerShowHiddenFilesEnabled:enabled];
    if (_explorerSourceMode == OMDExplorerSourceModeLocal) {
        [self reloadLocalExplorerEntries];
    }
}

- (void)explorerItemClicked:(id)sender
{
    (void)sender;
    NSEvent *event = [NSApp currentEvent];
    if (event != nil && [event clickCount] > 1) {
        return;
    }
    NSInteger row = [_explorerTableView clickedRow];
    if (row < 0) {
        row = [_explorerTableView selectedRow];
    }
    if (row < 0 || row >= (NSInteger)[_explorerEntries count]) {
        return;
    }
    NSDictionary *entry = [_explorerEntries objectAtIndex:row];
    [self openExplorerEntry:entry inNewTab:NO];
}

- (void)explorerItemDoubleClicked:(id)sender
{
    (void)sender;
    NSInteger row = [_explorerTableView clickedRow];
    if (row < 0) {
        row = [_explorerTableView selectedRow];
    }
    if (row < 0 || row >= (NSInteger)[_explorerEntries count]) {
        return;
    }
    NSDictionary *entry = [_explorerEntries objectAtIndex:row];
    [self openExplorerEntry:entry inNewTab:YES];
}

- (void)openExplorerEntry:(NSDictionary *)entry inNewTab:(BOOL)inNewTab
{
    if (entry == nil) {
        return;
    }

    BOOL isDirectory = [[entry objectForKey:@"isDirectory"] boolValue];
    NSString *path = [entry objectForKey:@"path"];
    BOOL allowEmptyGitHubParent = (isDirectory &&
                                   _explorerSourceMode == OMDExplorerSourceModeGitHub &&
                                   [[entry objectForKey:@"isParent"] boolValue]);
    if ((path == nil || [path length] == 0) && !allowEmptyGitHubParent) {
        return;
    }

    if (isDirectory) {
        if (_explorerSourceMode == OMDExplorerSourceModeGitHub) {
            [_explorerGitHubCurrentPath release];
            _explorerGitHubCurrentPath = [path copy];
            [self reloadGitHubExplorerEntries];
        } else {
            [_explorerLocalCurrentPath release];
            _explorerLocalCurrentPath = [path copy];
            [self reloadLocalExplorerEntries];
        }
        [self updateNavigateUpButton];
        return;
    }

    if (_explorerSourceMode == OMDExplorerSourceModeGitHub) {
        [self openGitHubFileEntry:entry inNewTab:inNewTab];
    } else {
        [_delegate openLocalPath:path inNewTab:inNewTab];
    }
}

- (void)openGitHubFileEntry:(NSDictionary *)entry inNewTab:(BOOL)inNewTab
{
    NSString *entryPath = OMDNormalizedRelativePath([entry objectForKey:@"path"]);
    if ([entryPath length] == 0) {
        return;
    }

    NSString *githubUser = [entry objectForKey:@"githubUser"];
    NSString *githubRepo = [entry objectForKey:@"githubRepo"];
    if (githubUser == nil || [githubUser length] == 0) {
        githubUser = _explorerGitHubUser;
    }
    if (githubRepo == nil || [githubRepo length] == 0) {
        githubRepo = _explorerGitHubRepo;
    }
    if ([OMDTrimmedString(githubUser) length] == 0 || [OMDTrimmedString(githubRepo) length] == 0) {
        return;
    }

    if ([_delegate selectDocumentTabForGitHubUser:githubUser repo:githubRepo path:entryPath]) {
        return;
    }

    NSString *repoCachePath = _explorerGitHubRepoCachePath;
    if (repoCachePath == nil || [repoCachePath length] == 0) {
        NSError *cacheError = nil;
        NSString *resolvedPath = nil;
        if (![self ensureGitHubRepositoryCacheForUser:githubUser
                                                 repo:githubRepo
                                            cachePath:&resolvedPath
                                                error:&cacheError]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"GitHub repository unavailable"];
            NSString *reason = [[cacheError userInfo] objectForKey:NSLocalizedFailureReasonErrorKey];
            NSString *detail = [cacheError localizedDescription];
            if (reason != nil && [reason length] > 0) {
                detail = [NSString stringWithFormat:@"%@\n\n%@", detail, reason];
            }
            [alert setInformativeText:detail];
            [alert runModal];
            [resolvedPath release];
            return;
        }
        [_explorerGitHubRepoCachePath release];
        _explorerGitHubRepoCachePath = [resolvedPath copy];
        [resolvedPath release];
        repoCachePath = _explorerGitHubRepoCachePath;
        [self refreshCachedGitHubUserOptions];
    }

    NSString *fullPath = [repoCachePath stringByAppendingPathComponent:entryPath];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory] || isDirectory) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"File unavailable"];
        [alert setInformativeText:@"The selected file is not available in the local cache."];
        [alert runModal];
        return;
    }

    [_delegate openGitHubFileAtCachePath:fullPath
                                    user:githubUser
                                    repo:githubRepo
                            relativePath:entryPath
                              descriptor:[entry objectForKey:@"name"]
                                inNewTab:inNewTab];
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

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
    if ([notification object] == _explorerGitHubUserComboBox) {
        NSString *selected = OMDTrimmedComboBoxSelectionOrText(_explorerGitHubUserComboBox);
        if ([selected length] > 0) {
            [_explorerGitHubUserComboBox setStringValue:selected];
        }
        [self explorerGitHubUserChanged:_explorerGitHubUserComboBox];
        return;
    }
    if ([notification object] == _explorerGitHubRepoComboBox) {
        NSString *selected = OMDTrimmedComboBoxSelectionOrText(_explorerGitHubRepoComboBox);
        if ([selected length] > 0) {
            [_explorerGitHubRepoComboBox setStringValue:selected];
        }
        [self explorerGitHubRepoChanged:_explorerGitHubRepoComboBox];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    id object = [notification object];
    if (object == _explorerGitHubUserComboBox) {
        [self explorerGitHubUserChanged:_explorerGitHubUserComboBox];
        return;
    }
    if (object == _explorerGitHubRepoComboBox) {
        [self explorerGitHubRepoChanged:_explorerGitHubRepoComboBox];
        return;
    }
}

@end