// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDAppDelegate.h"
#import "OMMarkdownRenderer.h"
#import "OMDTextView.h"
#import "OMDSourceTextView.h"
#import "OMDSourceHighlighter.h"
#import "OMDLineNumberRulerView.h"
#import "OMDDocumentConverter.h"
#import "OMDCodeCopyButton.h"
#import "OMDCopyFeedbackBadgeView.h"
#import "OMDFormattingBarView.h"
#import "OMDPreviewSync.h"
#import "OMDViewerModeState.h"
#import "OMDGitHubClient.h"
#import "OMDInlineToggle.h"
#import "OMDPanelSelection.h"
#import "GSVVimBindingController.h"
#import "GSVVimConfigLoader.h"
#import "GSOpenSave.h"
#import <AppKit/NSInterfaceStyle.h>
#import <AppKit/NSPrinter.h>
#import <GNUstepGUI/GSPrinting.h>
#import <GNUstepGUI/GSTheme.h>

#include <sys/types.h>
#if defined(_WIN32)
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#endif
#include <math.h>

static const CGFloat OMDPrintExportZoomScale = 0.8;
static const NSTimeInterval OMDInteractiveRenderDebounceInterval = 0.15;
static const NSTimeInterval OMDZoomAdaptiveSamplingWindow = 0.35;
static const NSTimeInterval OMDZoomAdaptiveSlowRenderThresholdMs = 85.0;
static const NSTimeInterval OMDZoomAdaptiveFastRenderThresholdMs = 42.0;
static const NSUInteger OMDZoomAdaptiveFastRenderStreakRequired = 4;
static const NSTimeInterval OMDMathArtifactRefreshDebounceInterval = 0.10;
static const NSTimeInterval OMDLivePreviewDebounceInterval = 0.12;
static const NSTimeInterval OMDPreviewStatusUpdatingDelayInterval = 0.30;
static const NSTimeInterval OMDPreviewStatusUpdatedDisplayInterval = 0.90;
static const NSTimeInterval OMDLinkedScrollDriverHoldInterval = 0.14;
static const NSTimeInterval OMDSourceSyntaxHighlightDebounceInterval = 0.08;
static const NSTimeInterval OMDSourceSyntaxHighlightLargeDocDebounceInterval = 0.16;
static const NSTimeInterval OMDRecoveryAutosaveDebounceInterval = 1.25;
static const NSTimeInterval OMDExternalFileMonitorInterval = 1.50;
static const NSTimeInterval OMDCopyFeedbackDisplayInterval = 0.95;
static const NSUInteger OMDSourceSyntaxIncrementalThreshold = 120000;
static const NSUInteger OMDSourceSyntaxIncrementalContextChars = 12000;
static const CGFloat OMDFormattingBarHeight = 32.0;
static const CGFloat OMDFormattingBarInsetX = 8.0;
static const CGFloat OMDFormattingBarControlHeight = 22.0;
static const CGFloat OMDFormattingBarPopupWidth = 84.0;
static const CGFloat OMDFormattingBarButtonWidth = 22.0;
static const CGFloat OMDFormattingBarButtonWideWidth = 24.0;
static const CGFloat OMDFormattingBarControlSpacing = 2.0;
static const CGFloat OMDFormattingBarGroupSpacing = 6.0;
static const CGFloat OMDSourceEditorDefaultFontSize = 13.0;
static const CGFloat OMDSourceEditorMinFontSize = 9.0;
static const CGFloat OMDSourceEditorMaxFontSize = 32.0;
static const CGFloat OMDExplorerSidebarDefaultWidth = 300.0;
static const CGFloat OMDTabStripHeight = 30.0;
static const CGFloat OMDExplorerListDefaultFontSize = 14.0;
static const CGFloat OMDExplorerListMinFontSize = 10.0;
static const CGFloat OMDExplorerListMaxFontSize = 20.0;
static const CGFloat OMDExplorerListMinimumRowHeight = 20.0;
static const CGFloat OMDToolbarControlHeight = 28.0;
static const CGFloat OMDToolbarLabelHeight = 20.0;
static const CGFloat OMDToolbarItemHeight = 32.0;
static const CGFloat OMDToolbarIconSize = 22.0;
static const CGFloat OMDToolbarIconInset = 2.0;
static const CGFloat OMDToolbarActionSegmentWidth = 46.0;
static const CGFloat OMDToolbarActionGroupSpacing = 8.0;
static const CGFloat OMDToolbarModeControlsWidth = 356.0;
static const CGFloat OMDToolbarZoomControlsWidth = 300.0;
static const CGFloat OMDWin11SplitDividerThickness = 3.0;
static const CGFloat OMDWin11SplitDividerHitThickness = 12.0;
static const CGFloat OMDUsableWindowWidthPadding = 96.0;
static const CGFloat OMDPreviewCanvasHorizontalMargin = 32.0;
static const CGFloat OMDPreviewMaximumLayoutWidth = 920.0;
static const CGFloat OMDPreviewPageCornerRadius = 10.0;
static const CGFloat OMDPreviewPageBorderWidth = 1.0;
static const CGFloat OMDLinkedScrollViewportAnchor = 0.30;
static const CGFloat OMDLinkedScrollDeadband = 8.0;
static const CGFloat OMDScrollSpeedMinimum = 10.0;
static const CGFloat OMDScrollSpeedMaximum = 40.0;
static const CGFloat OMDScrollSpeedDefault = 20.0;
static const NSTimeInterval OMDGitLockRetryDelaySeconds = 0.20;
static const NSTimeInterval OMDGitStaleLockMinimumAgeSeconds = 2.0;
static NSString * const OMDTextFileErrorDomain = @"OMDTextFileErrorDomain";
static NSString * const OMDSourceEditorFontNameDefaultsKey = @"ObjcMarkdownSourceEditorFontName";
static NSString * const OMDSourceEditorFontSizeDefaultsKey = @"ObjcMarkdownSourceEditorFontSize";
static NSString * const OMDMathRenderingPolicyDefaultsKey = @"ObjcMarkdownMathRenderingPolicy";
static NSString * const OMDAllowRemoteImagesDefaultsKey = @"ObjcMarkdownAllowRemoteImages";
static NSString * const OMDSplitSyncModeDefaultsKey = @"ObjcMarkdownSplitSyncMode";
static NSString * const OMDWordSelectionModifierShimDefaultsKey = @"ObjcMarkdownWordSelectionShimEnabled";
static NSString * const OMDSourceSyntaxHighlightingDefaultsKey = @"ObjcMarkdownSourceSyntaxHighlightingEnabled";
static NSString * const OMDSourceHighlightHighContrastDefaultsKey = @"ObjcMarkdownSourceHighlightHighContrastEnabled";
static NSString * const OMDSourceHighlightAccentColorDefaultsKey = @"ObjcMarkdownSourceHighlightAccentColor";
static NSString * const OMDSourceVimKeyBindingsDefaultsKey = @"ObjcMarkdownSourceVimKeyBindingsEnabled";
static NSString * const OMDRendererSyntaxHighlightingDefaultsKey = @"ObjcMarkdownRendererSyntaxHighlightingEnabled";
static NSString * const OMDShowFormattingBarDefaultsKey = @"ObjcMarkdownShowFormattingBar";
static NSString * const OMDThemeDefaultsKey = @"GSTheme";
static NSString * const OMDLayoutDensityDefaultsKey = @"ObjcMarkdownLayoutDensityMode";
static NSString * const OMDScrollSpeedDefaultsKey = @"ObjcMarkdownScrollSpeed";
static NSString * const OMDExplorerLocalRootPathDefaultsKey = @"ObjcMarkdownExplorerLocalRootPath";
static NSString * const OMDExplorerMaxFileSizeMBDefaultsKey = @"ObjcMarkdownExplorerMaxFileSizeMB";
static NSString * const OMDExplorerListFontSizeDefaultsKey = @"ObjcMarkdownExplorerListFontSize";
static NSString * const OMDExplorerIncludeForkArchivedDefaultsKey = @"ObjcMarkdownExplorerIncludeForkArchived";
static NSString * const OMDExplorerShowHiddenFilesDefaultsKey = @"ObjcMarkdownExplorerShowHiddenFiles";
static NSString * const OMDExplorerSidebarVisibleDefaultsKey = @"ObjcMarkdownExplorerSidebarVisible";
static NSString * const OMDExplorerGitHubTokenDefaultsKey = @"ObjcMarkdownGitHubToken";
static NSString * const OMDGitHubCacheErrorDomain = @"OMDGitHubCacheErrorDomain";

static void OMDStartupTrace(NSString *message)
{
    if (message == nil || [message length] == 0) {
        return;
    }
#if defined(_WIN32)
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ObjcMarkdown-startup.log"];
    NSData *existing = [NSData dataWithContentsOfFile:logPath];
    if (existing == nil) {
        [[NSData data] writeToFile:logPath atomically:YES];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (handle == nil) {
        return;
    }
    [handle seekToEndOfFile];
    NSString *line = [NSString stringWithFormat:@"%@\r\n", message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data != nil) {
        [handle writeData:data];
    }
    [handle closeFile];
#else
    (void)message;
#endif
}

static void OMDApplyWindowsMenuToWindow(NSWindow *window)
{
    if (window == nil) {
        return;
    }

    if (NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil) == NSWindows95InterfaceStyle) {
        NSMenu *mainMenu = [NSApp mainMenu];
        if (mainMenu != nil) {
            [window setMenu:mainMenu];
            if ([[GSTheme theme] respondsToSelector:@selector(updateMenu:forWindow:)]) {
                [[GSTheme theme] updateMenu:mainMenu forWindow:window];
            }
            OMDStartupTrace(@"windows-style menu applied to window");
        }
    }
}

static void OMDRefreshWindowsMainMenu(void)
{
    if (NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil) == NSWindows95InterfaceStyle) {
        NSMenu *mainMenu = [NSApp mainMenu];
        if (mainMenu != nil) {
            [mainMenu update];
            if ([[GSTheme theme] respondsToSelector:@selector(updateAllWindowsWithMenu:)]) {
                [[GSTheme theme] updateAllWindowsWithMenu:mainMenu];
            }
            OMDStartupTrace(@"windows-style main menu refreshed");
        }
    }
}

static BOOL OMDShouldUseToolbarFlexibleSpace(void)
{
#if defined(_WIN32) || defined(__APPLE__)
    return YES;
#else
    return NO;
#endif
}

static CGFloat OMDMinimumUsableWindowWidth(void)
{
#if defined(__APPLE__)
    return 900.0;
#else
    CGFloat primaryActionsWidth = (OMDToolbarActionSegmentWidth * 6.0) + OMDToolbarActionGroupSpacing;
    return primaryActionsWidth + OMDToolbarModeControlsWidth + OMDToolbarZoomControlsWidth + OMDUsableWindowWidthPadding;
#endif
}

static CGFloat OMDDefaultWindowWidth(void)
{
    return OMDMinimumUsableWindowWidth();
}

static CGFloat OMDDefaultWindowHeight(void)
{
    return 760.0;
}

static void OMDLogMenuSnapshot(NSString *label, NSMenu *menu, NSWindow *window)
{
    NSMutableArray *titles = [NSMutableArray array];
    NSUInteger count = 0;
    if (menu != nil) {
        count = [menu numberOfItems];
        for (NSUInteger index = 0; index < count; index++) {
            id item = [menu itemAtIndex:index];
            NSString *title = [item title];
            if (title == nil) {
                title = @"<nil>";
            }
            [titles addObject:title];
        }
    }

    NSString *windowTitle = nil;
    NSString *windowMenuTitle = nil;
    if (window != nil) {
        windowTitle = [window title];
        if ([window menu] != nil) {
            windowMenuTitle = [[window menu] title];
        }
    }

    OMDStartupTrace([NSString stringWithFormat:@"%@ menuCount=%lu menuTitle=%@ windowTitle=%@ windowMenuTitle=%@ items=%@",
                                               label,
                                               (unsigned long)count,
                                               (menu != nil ? [menu title] : @"<nil>"),
                                               (windowTitle != nil ? windowTitle : @"<nil>"),
                                               (windowMenuTitle != nil ? windowMenuTitle : @"<nil>"),
                                               [titles componentsJoinedByString:@","]]);
}

static NSString * const OMDTabMarkdownKey = @"markdown";
static NSString * const OMDTabSourcePathKey = @"sourcePath";
static NSString * const OMDTabDisplayTitleKey = @"displayTitle";
static NSString * const OMDTabDirtyKey = @"dirty";
static NSString * const OMDTabReadOnlyKey = @"readOnly";
static NSString * const OMDTabIsGitHubKey = @"isGitHub";
static NSString * const OMDTabGitHubUserKey = @"githubUser";
static NSString * const OMDTabGitHubRepoKey = @"githubRepo";
static NSString * const OMDTabGitHubPathKey = @"githubPath";
static NSString * const OMDTabRenderModeKey = @"renderMode";
static NSString * const OMDTabSyntaxLanguageKey = @"syntaxLanguage";
static NSString * const OMDTabLoadedDiskFingerprintKey = @"loadedDiskFingerprint";
static NSString * const OMDTabObservedDiskFingerprintKey = @"observedDiskFingerprint";
static NSString * const OMDTabSuppressedDiskFingerprintKey = @"suppressedDiskFingerprint";

static NSString *OMDTrimmedString(NSString *value);
#if defined(_WIN32)
static NSString *OMDHTMLEscapedString(NSString *value);
#endif

static NSArray *OMDExecutableCandidateNames(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return [NSArray array];
    }
#if defined(_WIN32)
    return [NSArray arrayWithObjects:name,
                                      [name stringByAppendingString:@".exe"],
                                      [name stringByAppendingString:@".cmd"],
                                      [name stringByAppendingString:@".bat"],
                                      nil];
#else
    return [NSArray arrayWithObject:name];
#endif
}

static NSArray *OMDExecutableSearchDirectories(void)
{
    NSMutableArray *directories = [NSMutableArray array];
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *pathValue = [environment objectForKey:@"PATH"];
    if (pathValue != nil && [pathValue length] > 0) {
#if defined(_WIN32)
        NSArray *searchPaths = [pathValue componentsSeparatedByString:@";"];
#else
        NSArray *searchPaths = [pathValue componentsSeparatedByString:@":"];
#endif
        for (NSString *searchPath in searchPaths) {
            if (searchPath != nil && [searchPath length] > 0) {
                [directories addObject:searchPath];
            }
        }
    }

#if defined(_WIN32)
    [directories addObjectsFromArray:@[
        @"C:/msys64/usr/bin",
        @"C:/msys64/clang64/bin",
        @"C:/clang64/bin"
    ]];
#else
    [directories addObject:@"/usr/bin"];
#endif

    return directories;
}

static NSString *OMDExecutablePathNamed(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *candidateNames = OMDExecutableCandidateNames(name);
    NSArray *searchPaths = OMDExecutableSearchDirectories();
    for (NSString *searchPath in searchPaths) {
        if (searchPath == nil || [searchPath length] == 0) {
            continue;
        }
        for (NSString *candidateName in candidateNames) {
            NSString *candidate = [searchPath stringByAppendingPathComponent:candidateName];
            if ([fileManager isExecutableFileAtPath:candidate]) {
                return candidate;
            }
        }
    }

    return nil;
}

static BOOL OMDLooksLikeWindowsAbsolutePath(NSString *path)
{
#if defined(_WIN32)
    if (path == nil || [path length] < 2) {
        return NO;
    }

    unichar first = [path characterAtIndex:0];
    unichar second = [path characterAtIndex:1];
    if (((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z')) &&
        second == ':') {
        return YES;
    }

    if ([path hasPrefix:@"\\\\"] || [path hasPrefix:@"//"]) {
        return YES;
    }
#else
    (void)path;
#endif
    return NO;
}

static NSString *OMDNormalizedExternalLocalPath(NSString *path)
{
    NSString *trimmed = OMDTrimmedString(path);
    if ([trimmed length] == 0) {
        return nil;
    }

    if ([trimmed hasPrefix:@"file://"]) {
        NSURL *url = [NSURL URLWithString:trimmed];
        if (url != nil && [url isFileURL]) {
            NSString *urlPath = [url path];
            if ([urlPath length] > 0) {
                trimmed = urlPath;
            }
        }
    }

#if defined(_WIN32)
    if ([trimmed rangeOfString:@"\\"].location != NSNotFound) {
        trimmed = [trimmed stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    }
#endif

    return trimmed;
}

#if defined(_WIN32)
static NSString *OMDHTMLEscapedString(NSString *value)
{
    if (value == nil) {
        return @"";
    }

    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return escaped;
}
#endif

static BOOL OMDPreviewStyleDiagnosticsEnabled(void)
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *flag = [environment objectForKey:@"OMD_LOG_PREVIEW_STYLE_ATTRS"];
    if (flag == nil || [flag length] == 0) {
        flag = [environment objectForKey:@"OBJCMARKDOWN_LOG_PREVIEW_STYLE_ATTRS"];
    }
    if (flag == nil || [flag length] == 0) {
        return [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownLogPreviewStyleAttrs"];
    }

    NSString *lower = [[flag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [lower isEqualToString:@"1"] ||
           [lower isEqualToString:@"true"] ||
           [lower isEqualToString:@"yes"] ||
           [lower isEqualToString:@"on"];
}

typedef NS_ENUM(NSInteger, OMDSplitSyncMode) {
    OMDSplitSyncModeUnlinked = 0,
    OMDSplitSyncModeLinkedScrolling = 1,
    OMDSplitSyncModeCaretSelectionFollow = 2
};

typedef NS_ENUM(NSInteger, OMDExplorerSourceMode) {
    OMDExplorerSourceModeLocal = 0,
    OMDExplorerSourceModeGitHub = 1
};

typedef NS_ENUM(NSInteger, OMDLayoutDensityMode) {
    OMDLayoutDensityModeCompact = 0,
    OMDLayoutDensityModeBalanced = 1,
    OMDLayoutDensityModeAdwaita = 2
};

typedef NS_ENUM(NSInteger, OMDPreferencesSection) {
    OMDPreferencesSectionAppearance = 0,
    OMDPreferencesSectionExplorer = 1,
    OMDPreferencesSectionPreview = 2,
    OMDPreferencesSectionEditor = 3
};

typedef NS_ENUM(NSInteger, OMDDocumentRenderMode) {
    OMDDocumentRenderModeMarkdown = 0,
    OMDDocumentRenderModeVerbatim = 1
};

typedef NS_ENUM(NSInteger, OMDFormattingCommandTag) {
    OMDFormattingCommandTagBold = 1001,
    OMDFormattingCommandTagItalic = 1002,
    OMDFormattingCommandTagStrike = 1003,
    OMDFormattingCommandTagInlineCode = 1004,
    OMDFormattingCommandTagLink = 1005,
    OMDFormattingCommandTagImage = 1006,
    OMDFormattingCommandTagListBullet = 1010,
    OMDFormattingCommandTagListNumber = 1011,
    OMDFormattingCommandTagListTask = 1012,
    OMDFormattingCommandTagBlockQuote = 1013,
    OMDFormattingCommandTagCodeFence = 1014,
    OMDFormattingCommandTagTable = 1015,
    OMDFormattingCommandTagHorizontalRule = 1016
};

typedef NS_ENUM(NSInteger, OMDLinkedScrollDriver) {
    OMDLinkedScrollDriverNone = 0,
    OMDLinkedScrollDriverSource = 1,
    OMDLinkedScrollDriverPreview = 2
};

typedef struct {
    CGFloat scale;
    CGFloat sidebarDefaultWidth;
    CGFloat previewCanvasMargin;
    CGFloat previewTextInsetX;
    CGFloat previewTextInsetY;
    CGFloat sourceTextInsetX;
    CGFloat sourceTextInsetY;
    CGFloat tabStripHeight;
    CGFloat explorerTopPadding;
    CGFloat explorerSidePadding;
    CGFloat explorerControlHeight;
    CGFloat explorerMinorControlHeight;
    CGFloat explorerRowPadding;
    CGFloat formattingBarHeight;
    CGFloat formattingBarInsetX;
    CGFloat formattingBarControlHeight;
    CGFloat formattingBarPopupWidth;
    CGFloat formattingBarButtonWidth;
    CGFloat formattingBarButtonWideWidth;
    CGFloat formattingBarControlSpacing;
    CGFloat formattingBarGroupSpacing;
    CGFloat formattingBarFontSize;
    CGFloat preferencesWindowWidth;
    CGFloat preferencesWindowMinHeight;
    CGFloat preferencesOuterPadding;
    CGFloat preferencesColumnGap;
    CGFloat preferencesCardCornerRadius;
    CGFloat preferencesCardPadding;
    CGFloat preferencesRowGap;
    CGFloat preferencesNoteHeight;
    CGFloat preferencesLabelWidth;
    CGFloat preferencesControlHeight;
    CGFloat preferencesSmallFieldWidth;
    CGFloat preferencesSmallButtonWidth;
    CGFloat preferencesAppearanceCardHeight;
    CGFloat preferencesExplorerCardHeight;
    CGFloat preferencesPreviewCardHeight;
    CGFloat preferencesRenderingCardHeight;
    CGFloat preferencesEditingCardHeight;
} OMDLayoutMetrics;

#ifndef NSAlertFirstButtonReturn
#define NSAlertFirstButtonReturn NSAlertDefaultReturn
#endif
#ifndef NSAlertSecondButtonReturn
#define NSAlertSecondButtonReturn NSAlertAlternateReturn
#endif
#ifndef NSAlertThirdButtonReturn
#define NSAlertThirdButtonReturn NSAlertOtherReturn
#endif
#ifndef NSModalResponseCancel
#define NSModalResponseCancel (-1000)
#endif

static id OMDInfoValueForKey(NSString *key)
{
    if (key == nil || [key length] == 0) {
        return nil;
    }

    NSBundle *bundle = [NSBundle mainBundle];
    id value = [bundle objectForInfoDictionaryKey:key];
    if (value != nil) {
        return value;
    }

    NSDictionary *info = [bundle infoDictionary];
    return [info objectForKey:key];
}

static NSString *OMDInfoStringForKey(NSString *key)
{
    id value = OMDInfoValueForKey(key);
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

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

static BOOL OMDPrintDiagnosticsEnabled(void)
{
    static BOOL resolved = NO;
    static BOOL enabled = NO;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_PRINT_DIAGNOSTICS"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_PRINT_DIAGNOSTICS"];
        }
        if (flag != nil && [flag length] > 0) {
            enabled = OMDTruthyFlagValue(flag);
        } else {
            enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownPrintDiagnostics"];
        }
        resolved = YES;
    }
    return enabled;
}

static BOOL OMDLaunchPrintAutomationEnabled(void)
{
    static BOOL resolved = NO;
    static BOOL enabled = NO;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_AUTOMATION_PRINT_ON_LAUNCH"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_AUTOMATION_PRINT_ON_LAUNCH"];
        }
        enabled = OMDTruthyFlagValue(flag);
        resolved = YES;
    }
    return enabled;
}

static NSString *OMDLaunchPDFExportAutomationPath(void)
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *path = [environment objectForKey:@"OMD_AUTOMATION_EXPORT_PDF_PATH"];
    if (path == nil || [path length] == 0) {
        path = [environment objectForKey:@"OBJCMARKDOWN_AUTOMATION_EXPORT_PDF_PATH"];
    }
    if (path == nil || [path length] == 0) {
        return nil;
    }
    return [[path stringByExpandingTildeInPath] stringByStandardizingPath];
}

static void OMDLogPrintDiagnostics(NSString *message)
{
    if (!OMDPrintDiagnosticsEnabled() || message == nil || [message length] == 0) {
        return;
    }
    NSLog(@"OMDPrint: %@", message);
}

static NSString *OMDCUPSDefaultPrinterName(void)
{
    NSString *lpstatPath = OMDExecutablePathNamed(@"lpstat");
    if (lpstatPath == nil || [lpstatPath length] == 0) {
        return nil;
    }

    NSPipe *outputPipe = [NSPipe pipe];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:lpstatPath];
    [task setArguments:[NSArray arrayWithObject:@"-d"]];
    [task setStandardOutput:outputPipe];
    [task setStandardError:outputPipe];

    NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
    [environment setObject:@"C" forKey:@"LC_ALL"];
    [environment setObject:@"C" forKey:@"LANG"];
    [task setEnvironment:environment];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"lpstat -d launch failed: %@", [exception reason]]);
        return nil;
    }

    NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
    NSString *trimmed = OMDTrimmedString(output);
    if ([trimmed length] == 0) {
        return nil;
    }

    if ([trimmed hasPrefix:@"system default destination:"]) {
        NSString *printerName = [trimmed substringFromIndex:[@"system default destination:" length]];
        return OMDTrimmedString(printerName);
    }

    if ([trimmed isEqualToString:@"no system default destination"]) {
        return nil;
    }

    OMDLogPrintDiagnostics([NSString stringWithFormat:@"unexpected lpstat -d output: %@", trimmed]);
    return nil;
}

static BOOL OMDFontIsMonospaced(NSFont *font)
{
    if (font == nil) {
        return NO;
    }
    if ([font respondsToSelector:@selector(isFixedPitch)] && [font isFixedPitch]) {
        return YES;
    }

    NSDictionary *attrs = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
    CGFloat iWidth = [@"iiiiiiiiii" sizeWithAttributes:attrs].width;
    CGFloat wWidth = [@"WWWWWWWWWW" sizeWithAttributes:attrs].width;
    if (iWidth <= 0.0 || wWidth <= 0.0) {
        return NO;
    }

    CGFloat averageI = iWidth / 10.0;
    CGFloat averageW = wWidth / 10.0;
    return fabs(averageI - averageW) < 0.05;
}

static NSInteger OMDAlertButtonIndexForResponse(NSInteger response)
{
    // Newer AppKit-style responses are 1000 + buttonIndex.
    if (response >= 1000 && response < 1100) {
        return response - 1000;
    }

    // GNUstep/older AppKit constants can vary by SDK, so normalize them here.
    if (response == NSAlertFirstButtonReturn || response == NSAlertDefaultReturn) {
        return 0;
    }
    if (response == NSAlertSecondButtonReturn || response == NSAlertAlternateReturn) {
        return 1;
    }
    if (response == NSAlertThirdButtonReturn || response == NSAlertOtherReturn || response == NSModalResponseCancel) {
        return 2;
    }
    return -1;
}

static void OMDDisableSelectableTextFieldsInView(NSView *view)
{
    if (view == nil) {
        return;
    }

    if ([view isKindOfClass:[NSTextField class]]) {
        NSTextField *field = (NSTextField *)view;
        [field setSelectable:NO];
        [field setEditable:NO];
    }

    NSArray *subviews = [view subviews];
    for (NSView *subview in subviews) {
        OMDDisableSelectableTextFieldsInView(subview);
    }
}

static BOOL OMDOpenURLUsingXDGOpen(NSURL *url)
{
#if defined(__APPLE__)
    (void)url;
    return NO;
#else
    if (url == nil) {
        return NO;
    }

    NSString *xdgOpenPath = @"/usr/bin/xdg-open";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:xdgOpenPath]) {
        return NO;
    }

    NSString *urlString = [url absoluteString];
    if (urlString == nil || [urlString length] == 0) {
        return NO;
    }

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:xdgOpenPath];
    [task setArguments:[NSArray arrayWithObject:urlString]];

    BOOL launched = YES;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        launched = NO;
    }

    return launched && [task terminationStatus] == 0;
#endif
}

static NSSet *OMDAllowedLinkSchemes(void)
{
    static NSSet *schemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        schemes = [[NSSet alloc] initWithObjects:@"file", @"http", @"https", @"mailto", nil];
    });
    return schemes;
}

static BOOL OMDShouldOpenURLForUserNavigation(NSURL *url)
{
    if (url == nil) {
        return NO;
    }
    NSString *scheme = [[url scheme] lowercaseString];
    if (scheme == nil || [scheme length] == 0) {
        return NO;
    }
    return [OMDAllowedLinkSchemes() containsObject:scheme];
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

static OMMarkdownMathRenderingPolicy OMDMathRenderingPolicyFromInteger(NSInteger value)
{
    if (value == OMMarkdownMathRenderingPolicyDisabled) {
        return OMMarkdownMathRenderingPolicyDisabled;
    }
    if (value == OMMarkdownMathRenderingPolicyExternalTools) {
        return OMMarkdownMathRenderingPolicyExternalTools;
    }
    return OMMarkdownMathRenderingPolicyStyledText;
}

static OMDSplitSyncMode OMDSplitSyncModeFromInteger(NSInteger value)
{
    if (value == OMDSplitSyncModeUnlinked) {
        return OMDSplitSyncModeUnlinked;
    }
    if (value == OMDSplitSyncModeCaretSelectionFollow) {
        return OMDSplitSyncModeCaretSelectionFollow;
    }
    return OMDSplitSyncModeLinkedScrolling;
}

static NSString *OMDColorDefaultsString(NSColor *color)
{
    if (color == nil) {
        return nil;
    }
    @try {
        NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (rgb == nil) {
            return nil;
        }
        return [NSString stringWithFormat:@"%.6f,%.6f,%.6f,%.6f",
                                          [rgb redComponent],
                                          [rgb greenComponent],
                                          [rgb blueComponent],
                                          [rgb alphaComponent]];
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

static NSColor *OMDColorFromDefaultsString(NSString *value)
{
    if (value == nil || [value length] == 0) {
        return nil;
    }
    NSArray *parts = [value componentsSeparatedByString:@","];
    if ([parts count] != 4) {
        return nil;
    }

    CGFloat red = [[parts objectAtIndex:0] doubleValue];
    CGFloat green = [[parts objectAtIndex:1] doubleValue];
    CGFloat blue = [[parts objectAtIndex:2] doubleValue];
    CGFloat alpha = [[parts objectAtIndex:3] doubleValue];

    if (red < 0.0 || red > 1.0 || green < 0.0 || green > 1.0 || blue < 0.0 || blue > 1.0 || alpha < 0.0 || alpha > 1.0) {
        return nil;
    }
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static BOOL OMDThemeLikelyLight(void)
{
    NSString *themeName = [[NSUserDefaults standardUserDefaults] stringForKey:OMDThemeDefaultsKey];
    if (themeName == nil || [themeName length] == 0) {
        return NO;
    }
    NSString *lower = [themeName lowercaseString];
    return ([lower rangeOfString:@"winux"].location != NSNotFound ||
            [lower rangeOfString:@"windows"].location != NSNotFound ||
            [lower rangeOfString:@"aqua"].location != NSNotFound);
}

static NSColor *OMDResolvedControlTextColor(void)
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
        color = OMDThemeLikelyLight() ? [NSColor blackColor] : [NSColor whiteColor];
    }
    return color;
}

static NSColor *OMDResolvedChromeBackgroundColor(void)
{
    GSTheme *theme = [GSTheme theme];
    NSColor *color = nil;
    if (theme != nil) {
        color = [theme colorNamed:@"windowBackgroundColor" state:GSThemeNormalState];
        if (color == nil) {
            color = [theme colorNamed:@"controlBackgroundColor" state:GSThemeNormalState];
        }
        if (color == nil) {
            color = [theme colorNamed:@"scrollViewBackgroundColor" state:GSThemeNormalState];
        }
    }
    if (color == nil) {
        color = [NSColor windowBackgroundColor];
    }
    if (color == nil) {
        color = [NSColor controlBackgroundColor];
    }
    if (color == nil) {
        color = [NSColor colorWithCalibratedWhite:0.94 alpha:1.0];
    }
    return color;
}

static NSColor *OMDResolvedSubtleSeparatorColor(void)
{
    GSTheme *theme = [GSTheme theme];
    NSColor *color = nil;
    if (theme != nil) {
        color = [theme colorNamed:@"gridColor" state:GSThemeNormalState];
        if (color == nil) {
            color = [theme colorNamed:@"controlShadowColor" state:GSThemeNormalState];
        }
    }
    if (color == nil) {
        color = [NSColor gridColor];
    }
    if (color == nil) {
        color = [NSColor colorWithCalibratedWhite:0.80 alpha:1.0];
    }
    return color;
}

static NSColor *OMDResolvedAccentColor(void)
{
    GSTheme *theme = [GSTheme theme];
    NSColor *color = nil;
    if (theme != nil) {
        color = [theme colorNamed:@"selectedControlColor" state:GSThemeNormalState];
        if (color == nil) {
            color = [theme colorNamed:@"alternateSelectedControlColor" state:GSThemeNormalState];
        }
        if (color == nil) {
            color = [theme colorNamed:@"keyboardFocusIndicatorColor" state:GSThemeNormalState];
        }
    }
    if (color == nil) {
        color = [NSColor selectedControlColor];
    }
    if (color == nil) {
        color = [NSColor keyboardFocusIndicatorColor];
    }
    if (color == nil) {
        color = [NSColor colorWithCalibratedRed:0.0 green:0.47 blue:0.84 alpha:1.0];
    }
    return color;
}

static BOOL OMDColorRGBAComponents(NSColor *color,
                                   CGFloat *red,
                                   CGFloat *green,
                                   CGFloat *blue,
                                   CGFloat *alpha)
{
    if (color == nil) {
        return NO;
    }
    @try {
        NSColor *rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (rgbColor == nil) {
            return NO;
        }
        if (red != NULL) {
            *red = [rgbColor redComponent];
        }
        if (green != NULL) {
            *green = [rgbColor greenComponent];
        }
        if (blue != NULL) {
            *blue = [rgbColor blueComponent];
        }
        if (alpha != NULL) {
            *alpha = [rgbColor alphaComponent];
        }
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

static BOOL OMDColorIsDark(NSColor *color)
{
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!OMDColorRGBAComponents(color, &red, &green, &blue, NULL)) {
        return NO;
    }
    return ((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) < 0.55;
}

static NSColor *OMDColorByBlending(NSColor *baseColor, NSColor *mixColor, CGFloat fraction)
{
    CGFloat baseRed = 0.0;
    CGFloat baseGreen = 0.0;
    CGFloat baseBlue = 0.0;
    CGFloat baseAlpha = 1.0;
    CGFloat mixRed = 0.0;
    CGFloat mixGreen = 0.0;
    CGFloat mixBlue = 0.0;
    CGFloat mixAlpha = 1.0;

    if (fraction < 0.0) {
        fraction = 0.0;
    } else if (fraction > 1.0) {
        fraction = 1.0;
    }

    if (!OMDColorRGBAComponents(baseColor, &baseRed, &baseGreen, &baseBlue, &baseAlpha) ||
        !OMDColorRGBAComponents(mixColor, &mixRed, &mixGreen, &mixBlue, &mixAlpha)) {
        return baseColor;
    }

    return [NSColor colorWithCalibratedRed:(baseRed + ((mixRed - baseRed) * fraction))
                                     green:(baseGreen + ((mixGreen - baseGreen) * fraction))
                                      blue:(baseBlue + ((mixBlue - baseBlue) * fraction))
                                     alpha:(baseAlpha + ((mixAlpha - baseAlpha) * fraction))];
}

static NSColor *OMDResolvedControlBackgroundColor(void)
{
    GSTheme *theme = [GSTheme theme];
    NSColor *color = nil;
    if (theme != nil) {
        color = [theme colorNamed:@"controlBackgroundColor" state:GSThemeNormalState];
        if (color == nil) {
            color = [theme colorNamed:@"textBackgroundColor" state:GSThemeNormalState];
        }
        if (color == nil) {
            color = [theme colorNamed:@"scrollViewBackgroundColor" state:GSThemeNormalState];
        }
    }
    if (color == nil) {
        color = [NSColor controlBackgroundColor];
    }
    if (color == nil) {
        color = OMDResolvedChromeBackgroundColor();
    }
    if (color == nil) {
        color = [NSColor colorWithCalibratedWhite:0.97 alpha:1.0];
    }
    return color;
}

static NSColor *OMDResolvedPanelBackdropColor(void)
{
    NSColor *chrome = OMDResolvedChromeBackgroundColor();
    if (chrome == nil) {
        chrome = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
    }
    if (OMDColorIsDark(chrome)) {
        return OMDColorByBlending(chrome, [NSColor blackColor], 0.10);
    }
    return OMDColorByBlending(chrome, [NSColor colorWithCalibratedWhite:0.92 alpha:1.0], 0.30);
}

static NSColor *OMDResolvedPanelCardFillColor(void)
{
    NSColor *card = OMDResolvedControlBackgroundColor();
    if (card == nil) {
        card = OMDResolvedChromeBackgroundColor();
    }
    if (card == nil) {
        card = [NSColor whiteColor];
    }
    return card;
}

static NSColor *OMDResolvedPanelCardBorderColor(void)
{
    NSColor *separator = OMDResolvedSubtleSeparatorColor();
    if (separator == nil) {
        separator = [NSColor colorWithCalibratedWhite:0.80 alpha:1.0];
    }
    if ([separator respondsToSelector:@selector(colorWithAlphaComponent:)]) {
        return [separator colorWithAlphaComponent:0.70];
    }
    return separator;
}

static NSColor *OMDResolvedMutedTextColor(void)
{
    NSColor *color = [NSColor disabledControlTextColor];
    if (color == nil) {
        color = OMDColorByBlending(OMDResolvedControlTextColor(),
                                   OMDResolvedPanelCardFillColor(),
                                   0.35);
    }
    if (color == nil) {
        color = [NSColor colorWithCalibratedWhite:0.45 alpha:1.0];
    }
    return color;
}

static OMDLayoutDensityMode OMDClampedLayoutDensityMode(NSInteger rawValue)
{
    if (rawValue == OMDLayoutDensityModeCompact) {
        return OMDLayoutDensityModeCompact;
    }
    if (rawValue == OMDLayoutDensityModeAdwaita) {
        return OMDLayoutDensityModeAdwaita;
    }
    return OMDLayoutDensityModeBalanced;
}

static CGFloat OMDClampedScrollSpeed(CGFloat value)
{
    if (value < OMDScrollSpeedMinimum) {
        return OMDScrollSpeedMinimum;
    }
    if (value > OMDScrollSpeedMaximum) {
        return OMDScrollSpeedMaximum;
    }
    return value;
}

static OMDPreferencesSection OMDClampedPreferencesSection(NSInteger rawValue)
{
    if (rawValue == OMDPreferencesSectionExplorer) {
        return OMDPreferencesSectionExplorer;
    }
    if (rawValue == OMDPreferencesSectionPreview) {
        return OMDPreferencesSectionPreview;
    }
    if (rawValue == OMDPreferencesSectionEditor) {
        return OMDPreferencesSectionEditor;
    }
    return OMDPreferencesSectionAppearance;
}

static BOOL OMDDefaultFormattingBarEnabledForMode(OMDLayoutDensityMode mode)
{
    return mode != OMDLayoutDensityModeAdwaita;
}

static OMDLayoutMetrics OMDLayoutMetricsForMode(OMDLayoutDensityMode mode)
{
    OMDLayoutMetrics metrics;
    metrics.scale = 1.0;
    metrics.sidebarDefaultWidth = OMDExplorerSidebarDefaultWidth;
    metrics.previewCanvasMargin = OMDPreviewCanvasHorizontalMargin;
    metrics.previewTextInsetX = 20.0;
    metrics.previewTextInsetY = 16.0;
    metrics.sourceTextInsetX = 20.0;
    metrics.sourceTextInsetY = 16.0;
    metrics.tabStripHeight = OMDTabStripHeight;
    metrics.explorerTopPadding = 14.0;
    metrics.explorerSidePadding = 10.0;
    metrics.explorerControlHeight = 24.0;
    metrics.explorerMinorControlHeight = 20.0;
    metrics.explorerRowPadding = 8.0;
    metrics.formattingBarHeight = OMDFormattingBarHeight;
    metrics.formattingBarInsetX = OMDFormattingBarInsetX;
    metrics.formattingBarControlHeight = OMDFormattingBarControlHeight;
    metrics.formattingBarPopupWidth = OMDFormattingBarPopupWidth + 4.0;
    metrics.formattingBarButtonWidth = OMDFormattingBarButtonWidth + 2.0;
    metrics.formattingBarButtonWideWidth = OMDFormattingBarButtonWideWidth + 2.0;
    metrics.formattingBarControlSpacing = OMDFormattingBarControlSpacing + 1.0;
    metrics.formattingBarGroupSpacing = OMDFormattingBarGroupSpacing + 2.0;
    metrics.formattingBarFontSize = 11.0;
    metrics.preferencesWindowWidth = 820.0;
    metrics.preferencesWindowMinHeight = 380.0;
    metrics.preferencesOuterPadding = 20.0;
    metrics.preferencesColumnGap = 16.0;
    metrics.preferencesCardCornerRadius = 12.0;
    metrics.preferencesCardPadding = 18.0;
    metrics.preferencesRowGap = 12.0;
    metrics.preferencesNoteHeight = 30.0;
    metrics.preferencesLabelWidth = 120.0;
    metrics.preferencesControlHeight = 28.0;
    metrics.preferencesSmallFieldWidth = 56.0;
    metrics.preferencesSmallButtonWidth = 80.0;
    metrics.preferencesAppearanceCardHeight = 236.0;
    metrics.preferencesExplorerCardHeight = 258.0;
    metrics.preferencesPreviewCardHeight = 132.0;
    metrics.preferencesRenderingCardHeight = 236.0;
    metrics.preferencesEditingCardHeight = 366.0;

    if (mode == OMDLayoutDensityModeCompact) {
        metrics.scale = 0.92;
        metrics.sidebarDefaultWidth = 286.0;
        metrics.previewCanvasMargin = 28.0;
        metrics.previewTextInsetX = 18.0;
        metrics.previewTextInsetY = 14.0;
        metrics.sourceTextInsetX = 18.0;
        metrics.sourceTextInsetY = 14.0;
        metrics.tabStripHeight = 28.0;
        metrics.explorerTopPadding = 12.0;
        metrics.explorerControlHeight = 22.0;
        metrics.formattingBarHeight = 30.0;
        metrics.formattingBarPopupWidth = 84.0;
        metrics.formattingBarButtonWidth = 22.0;
        metrics.formattingBarButtonWideWidth = 24.0;
        metrics.formattingBarControlSpacing = 2.0;
        metrics.formattingBarGroupSpacing = 6.0;
        metrics.preferencesWindowWidth = 780.0;
        metrics.preferencesWindowMinHeight = 360.0;
        metrics.preferencesOuterPadding = 18.0;
        metrics.preferencesColumnGap = 14.0;
        metrics.preferencesCardPadding = 16.0;
        metrics.preferencesRowGap = 10.0;
        metrics.preferencesNoteHeight = 28.0;
        metrics.preferencesLabelWidth = 112.0;
        metrics.preferencesControlHeight = 26.0;
        metrics.preferencesSmallFieldWidth = 52.0;
        metrics.preferencesSmallButtonWidth = 74.0;
        metrics.preferencesAppearanceCardHeight = 220.0;
        metrics.preferencesExplorerCardHeight = 244.0;
        metrics.preferencesPreviewCardHeight = 124.0;
        metrics.preferencesRenderingCardHeight = 224.0;
        metrics.preferencesEditingCardHeight = 346.0;
    } else if (mode == OMDLayoutDensityModeAdwaita) {
        metrics.scale = 1.14;
        metrics.sidebarDefaultWidth = 324.0;
        metrics.previewCanvasMargin = 40.0;
        metrics.previewTextInsetX = 24.0;
        metrics.previewTextInsetY = 20.0;
        metrics.sourceTextInsetX = 24.0;
        metrics.sourceTextInsetY = 18.0;
        metrics.tabStripHeight = 34.0;
        metrics.explorerTopPadding = 20.0;
        metrics.explorerSidePadding = 14.0;
        metrics.explorerControlHeight = 26.0;
        metrics.explorerMinorControlHeight = 22.0;
        metrics.explorerRowPadding = 10.0;
        metrics.formattingBarHeight = 38.0;
        metrics.formattingBarInsetX = 12.0;
        metrics.formattingBarControlHeight = 26.0;
        metrics.formattingBarPopupWidth = 102.0;
        metrics.formattingBarButtonWidth = 28.0;
        metrics.formattingBarButtonWideWidth = 34.0;
        metrics.formattingBarControlSpacing = 4.0;
        metrics.formattingBarGroupSpacing = 12.0;
        metrics.formattingBarFontSize = 12.0;
        metrics.preferencesWindowWidth = 860.0;
        metrics.preferencesWindowMinHeight = 420.0;
        metrics.preferencesOuterPadding = 24.0;
        metrics.preferencesColumnGap = 20.0;
        metrics.preferencesCardCornerRadius = 14.0;
        metrics.preferencesCardPadding = 22.0;
        metrics.preferencesRowGap = 14.0;
        metrics.preferencesNoteHeight = 34.0;
        metrics.preferencesLabelWidth = 128.0;
        metrics.preferencesControlHeight = 32.0;
        metrics.preferencesSmallFieldWidth = 64.0;
        metrics.preferencesSmallButtonWidth = 96.0;
        metrics.preferencesAppearanceCardHeight = 270.0;
        metrics.preferencesExplorerCardHeight = 300.0;
        metrics.preferencesPreviewCardHeight = 156.0;
        metrics.preferencesRenderingCardHeight = 272.0;
        metrics.preferencesEditingCardHeight = 424.0;
    }

    return metrics;
}

static CGFloat OMDPreferencesPreviewSectionHeightForMetrics(OMDLayoutMetrics metrics)
{
    return metrics.preferencesRenderingCardHeight +
           metrics.preferencesControlHeight +
           metrics.preferencesRowGap +
           metrics.preferencesNoteHeight +
           8.0;
}

static CGFloat OMDPreferencesSectionContentHeight(OMDPreferencesSection section, OMDLayoutMetrics metrics)
{
    switch (section) {
        case OMDPreferencesSectionExplorer:
            return metrics.preferencesExplorerCardHeight;
        case OMDPreferencesSectionPreview:
            return OMDPreferencesPreviewSectionHeightForMetrics(metrics);
        case OMDPreferencesSectionEditor:
            return metrics.preferencesEditingCardHeight;
        case OMDPreferencesSectionAppearance:
        default:
            return metrics.preferencesAppearanceCardHeight;
    }
}

static CGFloat OMDPreferencesPanelWidthForMetrics(OMDLayoutMetrics metrics)
{
    CGFloat width = metrics.preferencesWindowWidth;
    if (width < 720.0) {
        width = 720.0;
    }
    return ceil(width);
}

static CGFloat OMDPreferencesPanelHeightForSection(OMDPreferencesSection section, OMDLayoutMetrics metrics)
{
    CGFloat tabChromeHeight = (metrics.scale > 1.05 ? 76.0 : 68.0);
    CGFloat height = metrics.preferencesOuterPadding +
                     tabChromeHeight +
                     OMDPreferencesSectionContentHeight(section, metrics) +
                     metrics.preferencesOuterPadding;
    if (height < metrics.preferencesWindowMinHeight) {
        height = metrics.preferencesWindowMinHeight;
    }
    return ceil(height);
}

static NSFont *OMDPreferencesSectionTitleFont(OMDLayoutMetrics metrics)
{
    return [NSFont boldSystemFontOfSize:(metrics.scale > 1.05 ? 15.0 : 14.0)];
}

static NSFont *OMDPreferencesSectionSubtitleFont(OMDLayoutMetrics metrics)
{
    return [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 14.0 : 12.0)];
}

static NSFont *OMDPreferencesLabelFont(OMDLayoutMetrics metrics)
{
    return [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 13.0 : 12.0)];
}

static NSFont *OMDPreferencesNoteFont(OMDLayoutMetrics metrics)
{
    return [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 12.0 : 11.5)];
}

static NSFont *OMDPreferencesSectionControlFont(OMDLayoutMetrics metrics)
{
    return [NSFont boldSystemFontOfSize:(metrics.scale > 1.05 ? 13.0 : 12.0)];
}

static NSTextField *OMDStaticTextField(NSRect frame,
                                       NSString *stringValue,
                                       NSFont *font,
                                       NSColor *textColor,
                                       NSTextAlignment alignment,
                                       BOOL wraps)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setBezeled:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    [field setDrawsBackground:NO];
    [field setAlignment:alignment];
    [field setStringValue:(stringValue != nil ? stringValue : @"")];
    if (font != nil) {
        [field setFont:font];
    }
    if (textColor != nil) {
        [field setTextColor:textColor];
    }
    if (wraps) {
        id cell = [field cell];
        if ([cell respondsToSelector:@selector(setWraps:)]) {
            [cell setWraps:YES];
        }
        if ([cell respondsToSelector:@selector(setScrollable:)]) {
            [cell setScrollable:NO];
        }
        if ([cell respondsToSelector:@selector(setLineBreakMode:)]) {
            [cell setLineBreakMode:NSLineBreakByWordWrapping];
        }
    }
    return field;
}

static CGFloat OMDControlWidthForTitle(NSString *title,
                                       NSFont *font,
                                       CGFloat minWidth,
                                       CGFloat horizontalPadding)
{
    if (minWidth < 1.0) {
        minWidth = 1.0;
    }
    if (horizontalPadding < 0.0) {
        horizontalPadding = 0.0;
    }
    if (title == nil || [title length] == 0) {
        return ceil(minWidth);
    }
    if (font == nil) {
        font = [NSFont systemFontOfSize:11.0];
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName,
                                nil];
    CGFloat width = ceil([title sizeWithAttributes:attributes].width + (horizontalPadding * 2.0));
    if (width < minWidth) {
        width = minWidth;
    }
    return width;
}

static void OMDClearSegmentedControlSelection(NSSegmentedControl *control)
{
    if (control == nil) {
        return;
    }
    NSInteger segmentCount = [control segmentCount];
    NSInteger segmentIndex = 0;
    for (; segmentIndex < segmentCount; segmentIndex++) {
        [control setSelected:NO forSegment:segmentIndex];
    }
}

static NSImage *OMDImageNamed(NSString *resourceName)
{
    if (resourceName == nil || [resourceName length] == 0) {
        return nil;
    }

    NSImage *image = [NSImage imageNamed:resourceName];
    if (image != nil) {
        return image;
    }

    NSString *baseName = [resourceName stringByDeletingPathExtension];
    NSString *extension = [resourceName pathExtension];
    if (extension == nil || [extension length] == 0) {
        extension = @"png";
    }
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:baseName ofType:extension];
    if (resourcePath == nil && [baseName length] > 0) {
        resourcePath = [[NSBundle mainBundle] pathForResource:resourceName ofType:nil];
    }
    if (resourcePath != nil) {
        NSImage *fileImage = [[[NSImage alloc] initWithContentsOfFile:resourcePath] autorelease];
        if (fileImage != nil) {
            return fileImage;
        }
    }
    return nil;
}

static NSImage *OMDToolbarPreparedImage(NSImage *image)
{
    if (image == nil) {
        return nil;
    }

    NSSize targetSize = NSMakeSize(OMDToolbarIconSize, OMDToolbarIconSize);
    NSSize imageSize = [image size];
    NSRect sourceRect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);
    NSData *tiffData = [image TIFFRepresentation];
    if (tiffData != nil) {
        NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithData:tiffData] autorelease];
        NSInteger width = [bitmap pixelsWide];
        NSInteger height = [bitmap pixelsHigh];
        if (width > 0 && height > 0) {
            NSInteger minX = width;
            NSInteger minY = height;
            NSInteger maxX = -1;
            NSInteger maxY = -1;
            NSInteger x = 0;
            NSInteger y = 0;
            for (y = 0; y < height; y++) {
                for (x = 0; x < width; x++) {
                    NSColor *pixel = [bitmap colorAtX:x y:y];
                    if (pixel != nil && [pixel alphaComponent] > 0.01) {
                        if (x < minX) {
                            minX = x;
                        }
                        if (y < minY) {
                            minY = y;
                        }
                        if (x > maxX) {
                            maxX = x;
                        }
                        if (y > maxY) {
                            maxY = y;
                        }
                    }
                }
            }
            if (maxX >= minX && maxY >= minY && imageSize.width > 0.0 && imageSize.height > 0.0) {
                CGFloat scaleX = imageSize.width / (CGFloat)width;
                CGFloat scaleY = imageSize.height / (CGFloat)height;
                sourceRect = NSMakeRect(minX * scaleX,
                                        minY * scaleY,
                                        (maxX - minX + 1) * scaleX,
                                        (maxY - minY + 1) * scaleY);
            }
        }
    }

    NSImage *prepared = [[[NSImage alloc] initWithSize:targetSize] autorelease];
    if (prepared == nil) {
        return image;
    }

    NSRect rect = NSMakeRect(0.0, 0.0, targetSize.width, targetSize.height);
    NSRect drawRect = NSInsetRect(rect, OMDToolbarIconInset, OMDToolbarIconInset);
    if (drawRect.size.width <= 0.0 || drawRect.size.height <= 0.0) {
        drawRect = rect;
    }
    [prepared lockFocus];
    [image drawInRect:drawRect fromRect:sourceRect operation:NSCompositeCopy fraction:1.0];
    [prepared unlockFocus];
    [prepared setSize:targetSize];
    return prepared;
}

static void OMDSetToolbarItemImage(NSToolbarItem *item, NSImage *image)
{
    if (item == nil || image == nil) {
        return;
    }

    NSImage *prepared = OMDToolbarPreparedImage(image);
    [item setImage:(prepared != nil ? prepared : image)];
}

static NSImage *OMDToolbarImageNamed(NSString *resourceName)
{
    return OMDToolbarPreparedImage(OMDImageNamed(resourceName));
}

static NSImage *OMDToolbarTintedImage(NSImage *image, NSColor *tint)
{
    if (image == nil) {
        return nil;
    }

    if (tint == nil) {
        NSImage *prepared = OMDToolbarPreparedImage(image);
        return (prepared != nil ? prepared : image);
    }

    NSImage *prepared = OMDToolbarPreparedImage(image);
    if (prepared != nil) {
        image = prepared;
    }

    NSSize size = [image size];
    if (size.width <= 0.0 || size.height <= 0.0) {
        return image;
    }

    NSImage *tinted = [[[NSImage alloc] initWithSize:size] autorelease];
    if (tinted == nil) {
        return image;
    }
    NSRect rect = NSMakeRect(0.0, 0.0, size.width, size.height);
    [tinted lockFocus];
    [tint set];
    NSRectFill(rect);
    [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0];
    [tinted unlockFocus];
    [tinted setSize:size];
    return tinted;
}

static NSImage *OMDToolbarThemedImageNamed(NSString *resourceName)
{
    return OMDToolbarTintedImage(OMDImageNamed(resourceName), OMDResolvedControlTextColor());
}

static NSImage *OMDCodeBlockCopyImage(void)
{
    static NSImage *cached = nil;
    if (cached != nil) {
        return cached;
    }

    NSImage *image = OMDImageNamed(@"code-copy-icon.png");
    if (image == nil) {
        return nil;
    }

    [image setSize:NSMakeSize(16.0, 16.0)];
    cached = [image retain];
    return cached;
}

static NSImage *OMDCodeBlockCopiedCheckImage(void)
{
    static NSImage *cached = nil;
    if (cached != nil) {
        return cached;
    }

    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)] autorelease];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.13 green:0.62 blue:0.30 alpha:1.0] setStroke];
    NSBezierPath *check = [NSBezierPath bezierPath];
    [check setLineWidth:2.0];
    [check setLineCapStyle:NSRoundLineCapStyle];
    [check setLineJoinStyle:NSRoundLineJoinStyle];
    [check moveToPoint:NSMakePoint(3.2, 8.2)];
    [check lineToPoint:NSMakePoint(6.5, 4.8)];
    [check lineToPoint:NSMakePoint(12.8, 11.2)];
    [check stroke];
    [image unlockFocus];
    [image setSize:NSMakeSize(16.0, 16.0)];
    cached = [image retain];
    return cached;
}

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

static NSString *OMDTrimmedString(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *OMDDiskFingerprintForFileAttributes(NSDictionary *attributes)
{
    if (attributes == nil) {
        return nil;
    }

    NSDate *modificationDate = [attributes objectForKey:NSFileModificationDate];
    NSNumber *sizeValue = [attributes objectForKey:NSFileSize];
    NSNumber *inodeValue = [attributes objectForKey:NSFileSystemFileNumber];
    if (modificationDate == nil && sizeValue == nil && inodeValue == nil) {
        return nil;
    }

    NSTimeInterval modifiedAt = (modificationDate != nil
                                 ? [modificationDate timeIntervalSinceReferenceDate]
                                 : 0.0);
    unsigned long long size = [sizeValue respondsToSelector:@selector(unsignedLongLongValue)]
                              ? [sizeValue unsignedLongLongValue]
                              : 0ULL;
    unsigned long long inode = [inodeValue respondsToSelector:@selector(unsignedLongLongValue)]
                               ? [inodeValue unsignedLongLongValue]
                               : 0ULL;
    return [NSString stringWithFormat:@"%.6f:%llu:%llu",
                                      modifiedAt,
                                      size,
                                      inode];
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

static BOOL OMDIsMarkdownExtension(NSString *extension)
{
    if (extension == nil || [extension length] == 0) {
        return NO;
    }
    NSString *lower = [extension lowercaseString];
    return [lower isEqualToString:@"md"] ||
           [lower isEqualToString:@"markdown"] ||
           [lower isEqualToString:@"mdown"];
}

static BOOL OMDIsPlainTextNoHighlightExtension(NSString *extension)
{
    if (extension == nil || [extension length] == 0) {
        return NO;
    }
    NSString *lower = [extension lowercaseString];
    return [lower isEqualToString:@"txt"] ||
           [lower isEqualToString:@"text"] ||
           [lower isEqualToString:@"log"];
}

static NSString *OMDVerbatimSyntaxTokenForExtension(NSString *extension)
{
    NSString *lower = [[OMDTrimmedString(extension) lowercaseString] copy];
    if ([lower length] == 0 || OMDIsPlainTextNoHighlightExtension(lower)) {
        [lower release];
        return nil;
    }

    NSString *token = lower;
    if ([lower isEqualToString:@"yml"]) {
        token = @"yaml";
    } else if ([lower isEqualToString:@"py"]) {
        token = @"python";
    } else if ([lower isEqualToString:@"zsh"]) {
        token = @"bash";
    } else if ([lower isEqualToString:@"htm"]) {
        token = @"html";
    }

    NSString *result = [token copy];
    [lower release];
    return [result autorelease];
}

static NSUInteger OMDMaxBacktickRunLength(NSString *text)
{
    if (text == nil || [text length] == 0) {
        return 0;
    }

    NSUInteger longest = 0;
    NSUInteger run = 0;
    NSUInteger length = [text length];
    NSUInteger index = 0;
    for (; index < length; index++) {
        unichar ch = [text characterAtIndex:index];
        if (ch == '`') {
            run += 1;
            if (run > longest) {
                longest = run;
            }
        } else {
            run = 0;
        }
    }
    return longest;
}

static NSString *OMDBacktickFenceString(NSUInteger length)
{
    if (length < 3) {
        length = 3;
    }
    NSMutableString *fence = [NSMutableString stringWithCapacity:length];
    NSUInteger index = 0;
    for (; index < length; index++) {
        [fence appendString:@"`"];
    }
    return fence;
}

static NSString *OMDMarkdownCodeFenceWrappedText(NSString *text, NSString *languageToken)
{
    NSString *payload = (text != nil ? text : @"");
    NSUInteger fenceLength = OMDMaxBacktickRunLength(payload) + 1;
    if (fenceLength < 3) {
        fenceLength = 3;
    }
    NSString *fence = OMDBacktickFenceString(fenceLength);
    NSString *language = OMDTrimmedString(languageToken);

    NSMutableString *wrapped = [NSMutableString string];
    [wrapped appendString:fence];
    if ([language length] > 0) {
        [wrapped appendString:language];
    }
    [wrapped appendString:@"\n"];
    [wrapped appendString:payload];
    if (![payload hasSuffix:@"\n"]) {
        [wrapped appendString:@"\n"];
    }
    [wrapped appendString:fence];
    return wrapped;
}

static BOOL OMDDataAppearsBinary(NSData *data)
{
    if (data == nil || [data length] == 0) {
        return NO;
    }

    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger sampleLength = [data length];
    if (sampleLength > 8192) {
        sampleLength = 8192;
    }
    NSUInteger controlCount = 0;
    NSUInteger index = 0;
    for (; index < sampleLength; index++) {
        unsigned char value = bytes[index];
        if (value == 0) {
            return YES;
        }
        if (value < 0x09 || (value > 0x0D && value < 0x20)) {
            controlCount += 1;
        }
    }

    return controlCount > ((sampleLength / 16) + 1);
}

static NSString *OMDDecodeTextFromData(NSData *data, NSStringEncoding *usedEncodingOut)
{
    if (data == nil) {
        return nil;
    }
    if ([data length] == 0) {
        if (usedEncodingOut != NULL) {
            *usedEncodingOut = NSUTF8StringEncoding;
        }
        return @"";
    }

    NSStringEncoding encodings[] = {
        NSUTF8StringEncoding,
        NSUTF16StringEncoding,
        NSUTF16LittleEndianStringEncoding,
        NSUTF16BigEndianStringEncoding,
        NSUTF32StringEncoding,
        NSISOLatin1StringEncoding,
        NSWindowsCP1252StringEncoding
    };
    NSUInteger encodingCount = sizeof(encodings) / sizeof(encodings[0]);
    NSUInteger index = 0;
    for (; index < encodingCount; index++) {
        NSStringEncoding encoding = encodings[index];
        NSString *decoded = [[[NSString alloc] initWithData:data encoding:encoding] autorelease];
        if (decoded != nil) {
            if (usedEncodingOut != NULL) {
                *usedEncodingOut = encoding;
            }
            return decoded;
        }
    }
    return nil;
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

static NSString *OMDNormalizedRelativePath(NSString *value)
{
    NSString *trimmed = OMDTrimmedString(value);
    if ([trimmed length] == 0) {
        return @"";
    }

    NSArray *components = [trimmed pathComponents];
    NSMutableArray *normalized = [NSMutableArray array];
    for (NSString *component in components) {
        if (component == nil || [component length] == 0 ||
            [component isEqualToString:@"/"] ||
            [component isEqualToString:@"."]) {
            continue;
        }
        if ([component isEqualToString:@".."]) {
            if ([normalized count] > 0) {
                [normalized removeLastObject];
            }
            continue;
        }
        [normalized addObject:component];
    }
    return [normalized componentsJoinedByString:@"/"];
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

@interface OMDMainWindow : NSWindow
@end

@implementation OMDMainWindow

- (void)performClose:(id)sender
{
    (void)sender;

    id delegate = [self delegate];
    BOOL shouldClose = YES;
    if (delegate != nil && [delegate respondsToSelector:@selector(windowShouldClose:)]) {
        shouldClose = [delegate windowShouldClose:self];
    }

    if (shouldClose) {
        [self close];
    }
}

@end

@interface OMDFlippedFillView : NSView
{
    NSColor *_fillColor;
}
@property (nonatomic, retain) NSColor *fillColor;
@end

@implementation OMDFlippedFillView

@synthesize fillColor = _fillColor;

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _fillColor = [OMDResolvedPanelBackdropColor() retain];
    }
    return self;
}

- (void)dealloc
{
    [_fillColor release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)setFillColor:(NSColor *)fillColor
{
    if (_fillColor == fillColor) {
        return;
    }
    [_fillColor release];
    _fillColor = [fillColor retain];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSColor *fill = (_fillColor != nil ? _fillColor : [NSColor clearColor]);
    [fill setFill];
    NSRectFill([self bounds]);
}

@end

@interface OMDPreviewCanvasView : OMDFlippedFillView
@end

@implementation OMDPreviewCanvasView

- (BOOL)isFlipped
{
    return YES;
}

@end

@interface OMDRoundedCardView : OMDFlippedFillView
{
    NSColor *_borderColor;
    CGFloat _cornerRadius;
}
@property (nonatomic, retain) NSColor *borderColor;
@property (nonatomic, assign) CGFloat cornerRadius;
@end

@implementation OMDRoundedCardView

@synthesize borderColor = _borderColor;
@synthesize cornerRadius = _cornerRadius;

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        [self setFillColor:OMDResolvedPanelCardFillColor()];
        _borderColor = [OMDResolvedPanelCardBorderColor() retain];
        _cornerRadius = 12.0;
    }
    return self;
}

- (void)dealloc
{
    [_borderColor release];
    [super dealloc];
}

- (void)setBorderColor:(NSColor *)borderColor
{
    if (_borderColor == borderColor) {
        return;
    }
    [_borderColor release];
    _borderColor = [borderColor retain];
    [self setNeedsDisplay:YES];
}

- (void)setCornerRadius:(CGFloat)cornerRadius
{
    if (_cornerRadius == cornerRadius) {
        return;
    }
    _cornerRadius = cornerRadius;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                         xRadius:_cornerRadius
                                                         yRadius:_cornerRadius];
    NSColor *fill = ([self fillColor] != nil ? [self fillColor] : [NSColor clearColor]);
    [fill setFill];
    [path fill];
    if (_borderColor != nil) {
        [_borderColor setStroke];
        [path setLineWidth:1.0];
        [path stroke];
    }
}

@end

@interface OMDWin11SplitView : NSSplitView
{
    NSMutableArray *_dividerTrackingTags;
    NSInteger _hoveredDividerIndex;
    NSInteger _activeDividerIndex;
}
- (void)omdRebuildDividerTrackingRects;
@end

@implementation OMDWin11SplitView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _dividerTrackingTags = [[NSMutableArray alloc] init];
        _hoveredDividerIndex = -1;
        _activeDividerIndex = -1;
        [self setDividerStyle:NSSplitViewDividerStyleThin];
        [self setDraggedBarWidth:OMDWin11SplitDividerHitThickness];
        if ([self respondsToSelector:@selector(setDividerColor:)]) {
            [self setDividerColor:OMDResolvedSubtleSeparatorColor()];
        }
    }
    return self;
}

- (void)dealloc
{
    NSUInteger i = 0;
    for (i = 0; i < [_dividerTrackingTags count]; i++) {
        [self removeTrackingRect:(NSTrackingRectTag)[[_dividerTrackingTags objectAtIndex:i] integerValue]];
    }
    [_dividerTrackingTags release];
    [super dealloc];
}

- (NSUInteger)omdDividerCount
{
    NSUInteger subviewCount = [[self subviews] count];
    return (subviewCount > 0 ? (subviewCount - 1) : 0);
}

- (NSRect)omdDividerRectForIndex:(NSUInteger)index
{
    NSArray *subviews = [self subviews];
    NSRect bounds = [self bounds];
    CGFloat thickness = [self dividerThickness];
    NSRect leadingFrame = NSZeroRect;

    if ((index + 1) >= [subviews count]) {
        return NSZeroRect;
    }

    leadingFrame = [[subviews objectAtIndex:index] frame];
    if ([self isVertical]) {
        return NSMakeRect(NSMaxX(leadingFrame),
                          NSMinY(bounds),
                          thickness,
                          NSHeight(bounds));
    }

    return NSMakeRect(NSMinX(bounds),
                      NSMaxY(leadingFrame),
                      NSWidth(bounds),
                      thickness);
}

- (NSRect)omdInteractiveDividerRectForIndex:(NSUInteger)index
{
    NSRect effectiveRect = [self omdDividerRectForIndex:index];
    CGFloat extra = 0.0;

    if (NSEqualRects(effectiveRect, NSZeroRect)) {
        return NSZeroRect;
    }

    if ([self isVertical]) {
        extra = MAX(0.0, OMDWin11SplitDividerHitThickness - NSWidth(effectiveRect));
        effectiveRect.origin.x -= floor(extra / 2.0);
        effectiveRect.size.width += extra;
    } else {
        extra = MAX(0.0, OMDWin11SplitDividerHitThickness - NSHeight(effectiveRect));
        effectiveRect.origin.y -= floor(extra / 2.0);
        effectiveRect.size.height += extra;
    }

    return NSIntersectionRect(effectiveRect, [self bounds]);
}

- (NSInteger)omdDividerIndexForPoint:(NSPoint)point
{
    NSUInteger dividerCount = [self omdDividerCount];
    NSUInteger index = 0;

    for (index = 0; index < dividerCount; index++) {
        if (NSPointInRect(point, [self omdInteractiveDividerRectForIndex:index])) {
            return (NSInteger)index;
        }
    }

    return -1;
}

- (NSInteger)omdDividerIndexForDrawRect:(NSRect)dividerRect
{
    NSUInteger dividerCount = [self omdDividerCount];
    NSUInteger index = 0;

    for (index = 0; index < dividerCount; index++) {
        NSRect candidateRect = [self omdDividerRectForIndex:index];

        if (NSEqualRects(candidateRect, dividerRect)) {
            return (NSInteger)index;
        }
        if ([self isVertical]) {
            if (fabs(NSMidX(candidateRect) - NSMidX(dividerRect)) < 0.5) {
                return (NSInteger)index;
            }
        } else {
            if (fabs(NSMidY(candidateRect) - NSMidY(dividerRect)) < 0.5) {
                return (NSInteger)index;
            }
        }
    }

    return -1;
}

- (void)omdInvalidateCursorRects
{
    NSWindow *window = [self window];

    [self discardCursorRects];
    if (window != nil) {
        [window invalidateCursorRectsForView:self];
    }
}

- (void)omdRebuildDividerTrackingRects
{
    NSUInteger i = 0;
    NSUInteger dividerCount = [self omdDividerCount];

    for (i = 0; i < [_dividerTrackingTags count]; i++) {
        [self removeTrackingRect:(NSTrackingRectTag)[[_dividerTrackingTags objectAtIndex:i] integerValue]];
    }
    [_dividerTrackingTags removeAllObjects];

    for (i = 0; i < dividerCount; i++) {
        NSRect trackingRect = [self omdInteractiveDividerRectForIndex:i];
        NSTrackingRectTag tag = 0;

        if (NSEqualRects(trackingRect, NSZeroRect)) {
            continue;
        }

        tag = [self addTrackingRect:trackingRect
                              owner:self
                           userData:(void *)(intptr_t)(i + 1)
                       assumeInside:NO];
        [_dividerTrackingTags addObject:[NSNumber numberWithInteger:tag]];
    }

    if (_hoveredDividerIndex >= (NSInteger)dividerCount) {
        _hoveredDividerIndex = -1;
    }
    if (_activeDividerIndex >= (NSInteger)dividerCount) {
        _activeDividerIndex = -1;
    }
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self omdRebuildDividerTrackingRects];
    [self omdInvalidateCursorRects];
}

- (void)adjustSubviews
{
    [super adjustSubviews];
    [self omdRebuildDividerTrackingRects];
    [self omdInvalidateCursorRects];
}

- (void)mouseEntered:(NSEvent *)event
{
    NSInteger dividerIndex = (NSInteger)(intptr_t)[event userData] - 1;

    if (_hoveredDividerIndex != dividerIndex) {
        _hoveredDividerIndex = dividerIndex;
        [self setNeedsDisplay:YES];
    }

    [super mouseEntered:event];
}

- (void)mouseExited:(NSEvent *)event
{
    NSInteger dividerIndex = (NSInteger)(intptr_t)[event userData] - 1;

    if (_hoveredDividerIndex == dividerIndex && _activeDividerIndex != dividerIndex) {
        _hoveredDividerIndex = -1;
        [self setNeedsDisplay:YES];
    }

    [super mouseExited:event];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSWindow *window = [self window];

    _activeDividerIndex = [self omdDividerIndexForPoint:point];
    if (_activeDividerIndex >= 0) {
        _hoveredDividerIndex = _activeDividerIndex;
        [self setNeedsDisplay:YES];
    }

    [super mouseDown:event];

    _activeDividerIndex = -1;
    if (window != nil) {
        NSPoint currentPoint = [self convertPoint:[window mouseLocationOutsideOfEventStream] fromView:nil];
        _hoveredDividerIndex = [self omdDividerIndexForPoint:currentPoint];
    } else {
        _hoveredDividerIndex = -1;
    }
    [self omdRebuildDividerTrackingRects];
    [self setNeedsDisplay:YES];
}

- (void)resetCursorRects
{
    NSCursor *cursor = ([self isVertical]
                        ? [NSCursor resizeLeftRightCursor]
                        : [NSCursor resizeUpDownCursor]);
    NSUInteger dividerCount = [self omdDividerCount];
    NSUInteger index = 0;

    for (index = 0; index < dividerCount; index++) {
        NSRect interactiveRect = [self omdInteractiveDividerRectForIndex:index];

        if (!NSEqualRects(interactiveRect, NSZeroRect)) {
            [self addCursorRect:interactiveRect cursor:cursor];
        }
    }
}

- (CGFloat)dividerThickness
{
    return OMDWin11SplitDividerThickness;
}

- (void)drawDividerInRect:(NSRect)dividerRect
{
    NSColor *background = OMDResolvedChromeBackgroundColor();
    NSColor *separator = OMDResolvedSubtleSeparatorColor();
    NSColor *accent = OMDResolvedAccentColor();
    NSInteger dividerIndex = [self omdDividerIndexForDrawRect:dividerRect];
    BOOL hovered = (dividerIndex >= 0 && dividerIndex == _hoveredDividerIndex);
    BOOL active = (dividerIndex >= 0 && dividerIndex == _activeDividerIndex);
    BOOL dark = OMDColorIsDark(background);
    NSColor *bandColor = nil;
    NSColor *lineColor = nil;
    NSRect strokeRect = dividerRect;

    if (background == nil) {
        background = [NSColor clearColor];
    }
    if (separator == nil) {
        separator = [NSColor colorWithCalibratedWhite:0.80 alpha:1.0];
    }
    if ([separator respondsToSelector:@selector(colorWithAlphaComponent:)]) {
        separator = [separator colorWithAlphaComponent:(OMDColorIsDark(background) ? 0.58 : 0.78)];
    }

    if (active) {
        bandColor = OMDColorByBlending(background, accent, dark ? 0.22 : 0.16);
        lineColor = accent;
    } else if (hovered) {
        bandColor = OMDColorByBlending(background, separator, dark ? 0.30 : 0.20);
        lineColor = OMDColorByBlending(separator, accent, 0.28);
    } else {
        bandColor = OMDColorByBlending(background, separator, dark ? 0.22 : 0.15);
        lineColor = separator;
    }

    [bandColor setFill];
    NSRectFill(dividerRect);

    if ([self isVertical]) {
        CGFloat lineWidth = MIN(NSWidth(dividerRect), (active || hovered) ? 2.0 : 1.0);
        strokeRect.origin.x = floor(NSMidX(dividerRect) - (lineWidth / 2.0));
        strokeRect.size.width = MAX(1.0, lineWidth);
    } else {
        CGFloat lineHeight = MIN(NSHeight(dividerRect), (active || hovered) ? 2.0 : 1.0);
        strokeRect.origin.y = floor(NSMidY(dividerRect) - (lineHeight / 2.0));
        strokeRect.size.height = MAX(1.0, lineHeight);
    }

    if ([lineColor respondsToSelector:@selector(colorWithAlphaComponent:)]) {
        lineColor = [lineColor colorWithAlphaComponent:(active ? 0.96 : (hovered ? 0.90 : (dark ? 0.82 : 0.80)))];
    }

    [lineColor setFill];
    NSRectFill(strokeRect);
}

@end

static OMDRoundedCardView *OMDCreatePreferencesCard(NSRect frame, OMDLayoutMetrics metrics)
{
    OMDRoundedCardView *card = [[[OMDRoundedCardView alloc] initWithFrame:frame] autorelease];
    [card setCornerRadius:metrics.preferencesCardCornerRadius];
    [card setFillColor:OMDResolvedPanelCardFillColor()];
    [card setBorderColor:OMDResolvedPanelCardBorderColor()];
    return card;
}

@interface OMDAppDelegate () <GSVVimBindingControllerDelegate>
- (void)importDocument:(id)sender;
- (void)newWindow:(id)sender;
- (void)saveDocument:(id)sender;
- (void)saveDocumentAsMarkdown:(id)sender;
- (void)printDocument:(id)sender;
- (void)runLaunchPrintAutomationIfRequested;
- (void)runLaunchPDFExportAutomationIfRequested;
- (void)logPrintDiagnosticsForOperation:(NSPrintOperation *)operation
                              printInfo:(NSPrintInfo *)printInfo
                                  stage:(NSString *)stage;
- (void)ensurePrintDefaultPrinterConfigured;
- (BOOL)exportDocumentAsPDFToPath:(NSString *)path;
- (void)exportDocumentAsPDF:(id)sender;
- (void)exportDocumentAsRTF:(id)sender;
- (void)exportDocumentAsDOCX:(id)sender;
- (void)exportDocumentAsODT:(id)sender;
- (void)exportDocumentAsHTML:(id)sender;
- (BOOL)hasLoadedDocument;
- (BOOL)ensureDocumentLoadedForActionName:(NSString *)actionName;
- (BOOL)ensureConverterAvailableForActionName:(NSString *)actionName;
- (OMDDocumentConverter *)documentConverter;
- (BOOL)importDocumentAtPath:(NSString *)path;
- (BOOL)isImportableDocumentPath:(NSString *)path;
- (void)presentConverterError:(NSError *)error fallbackTitle:(NSString *)title;
- (NSString *)resolvedAbsolutePathForLocalPath:(NSString *)path;
- (NSString *)diskFingerprintForPath:(NSString *)path;
- (BOOL)isCurrentDocumentReloadableFromDisk;
- (BOOL)currentDocumentHasNewerDiskVersion;
- (void)setCurrentDiskFingerprintStateLoaded:(NSString *)loaded
                                    observed:(NSString *)observed
                                  suppressed:(NSString *)suppressed;
- (void)refreshCurrentDocumentDiskStateAllowPrompt:(BOOL)allowPrompt;
- (void)startExternalFileMonitor;
- (void)stopExternalFileMonitor;
- (void)externalFileMonitorTimerFired:(NSTimer *)timer;
- (BOOL)reloadCurrentDocumentFromDiskPreservingViewport;
- (BOOL)loadDocumentContentsAtPath:(NSString *)path
                        actionName:(NSString *)actionName
                          markdown:(NSString **)markdownOut
                      displayTitle:(NSString **)displayTitleOut
                        renderMode:(OMDDocumentRenderMode *)renderModeOut
                    syntaxLanguage:(NSString **)syntaxLanguageOut
                       fingerprint:(NSString **)fingerprintOut;
- (void)reloadDocumentFromDisk:(id)sender;
- (void)setCurrentMarkdown:(NSString *)markdown sourcePath:(NSString *)sourcePath;
- (void)setCurrentDocumentText:(NSString *)text
                    sourcePath:(NSString *)sourcePath
                    renderMode:(OMDDocumentRenderMode)renderMode
                syntaxLanguage:(NSString *)syntaxLanguage;
- (NSString *)markdownForCurrentPreview;
- (NSString *)decodedTextForFileAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)openDocumentAtPath:(NSString *)path;
- (BOOL)openDocumentAtPath:(NSString *)path
                  inNewTab:(BOOL)inNewTab
       requireDirtyConfirm:(BOOL)requireDirtyConfirm;
- (BOOL)openDocumentAtPathInNewWindow:(NSString *)path;
- (NSInteger)selectedExplorerSourceModeControlIndex;
- (void)setSelectedExplorerSourceModeControlIndex:(NSInteger)index;
- (void)openRecentDocumentFromMenuItem:(id)sender;
- (void)clearRecentDocumentsMenu:(id)sender;
- (void)rebuildOpenRecentMenu;
- (void)noteRecentDocumentAtPathIfAvailable:(NSString *)path;
- (void)setupWorkspaceChrome;
- (void)showLaunchOverlayWithTitle:(NSString *)title detail:(NSString *)detail;
- (void)hideLaunchOverlay;
- (NSString *)firstLaunchDocumentPathFromArguments;
- (BOOL)hasRecoverySnapshotAvailable;
- (void)performDeferredInitialLaunchWork;
- (void)schedulePostPresentationSetupIfNeeded;
- (void)runDeferredPostPresentationSetup;
- (void)presentWindowIfNeeded;
- (void)applyWindowsWindowIconsIfPossible;
- (void)layoutWorkspaceChrome;
- (CGFloat)currentTabStripHeight;
- (BOOL)isExplorerSidebarVisiblePreference;
- (void)setExplorerSidebarVisiblePreference:(BOOL)visible;
- (void)applyExplorerSidebarVisibility;
- (void)setupExplorerSidebar;
- (void)updateExplorerControlsVisibility;
- (void)toggleExplorerSidebar:(id)sender;
- (void)reloadExplorerEntries;
- (void)reloadLocalExplorerEntries;
- (void)reloadGitHubExplorerEntries;
- (void)setExplorerLoading:(BOOL)loading message:(NSString *)message;
- (NSString *)explorerLocalRootPathPreference;
- (void)setExplorerLocalRootPathPreference:(NSString *)path;
- (NSUInteger)explorerMaxOpenFileSizeBytes;
- (void)setExplorerMaxOpenFileSizeMBPreference:(NSUInteger)megabytes;
- (CGFloat)explorerListFontSizePreference;
- (void)setExplorerListFontSizePreference:(CGFloat)fontSize;
- (void)applyExplorerListFontPreference;
- (BOOL)isExplorerIncludeForkArchivedEnabled;
- (void)setExplorerIncludeForkArchivedEnabled:(BOOL)enabled;
- (BOOL)isExplorerShowHiddenFilesEnabled;
- (void)setExplorerShowHiddenFilesEnabled:(BOOL)enabled;
- (NSString *)explorerGitHubTokenPreference;
- (void)setExplorerGitHubTokenPreference:(NSString *)token;
- (void)explorerSourceModeChanged:(id)sender;
- (void)explorerNavigateUp:(id)sender;
- (void)explorerGitHubUserChanged:(id)sender;
- (void)explorerGitHubRepoChanged:(id)sender;
- (void)explorerGitHubIncludeForkArchivedChanged:(id)sender;
- (void)explorerShowHiddenFilesChanged:(id)sender;
- (void)explorerItemClicked:(id)sender;
- (void)explorerItemDoubleClicked:(id)sender;
- (void)openExplorerEntry:(NSDictionary *)entry inNewTab:(BOOL)inNewTab;
- (void)openLocalPath:(NSString *)path inNewTab:(BOOL)inNewTab;
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
- (BOOL)isMarkdownTextPath:(NSString *)path;
- (NSString *)temporaryPathForRemoteImportWithExtension:(NSString *)extension;
- (BOOL)ensureOpenFileSizeWithinLimit:(unsigned long long)size
                           descriptor:(NSString *)descriptor;
- (void)updateTabStrip;
- (void)tabButtonPressed:(id)sender;
- (void)tabCloseButtonPressed:(id)sender;
- (void)closeDocumentTabAtIndex:(NSInteger)index;
- (void)selectDocumentTabAtIndex:(NSInteger)index;
- (NSInteger)documentTabIndexForLocalPath:(NSString *)sourcePath;
- (NSInteger)documentTabIndexForGitHubUser:(NSString *)user
                                      repo:(NSString *)repo
                                      path:(NSString *)path;
- (void)captureCurrentStateIntoSelectedTab;
- (NSMutableDictionary *)newDocumentTabWithMarkdown:(NSString *)markdown
                                         sourcePath:(NSString *)sourcePath
                                       displayTitle:(NSString *)displayTitle
                                           readOnly:(BOOL)readOnly
                                         renderMode:(OMDDocumentRenderMode)renderMode
                                     syntaxLanguage:(NSString *)syntaxLanguage
                                    diskFingerprint:(NSString *)diskFingerprint;
- (void)installDocumentTabRecord:(NSMutableDictionary *)tab
                         inNewTab:(BOOL)inNewTab
                    resetViewport:(BOOL)resetViewport;
- (void)applyDocumentTabRecord:(NSDictionary *)tabRecord;
- (BOOL)openDocumentWithMarkdown:(NSString *)markdown
                      sourcePath:(NSString *)sourcePath
                    displayTitle:(NSString *)displayTitle
                        readOnly:(BOOL)readOnly
                      renderMode:(OMDDocumentRenderMode)renderMode
                  syntaxLanguage:(NSString *)syntaxLanguage
                        inNewTab:(BOOL)inNewTab
             requireDirtyConfirm:(BOOL)requireDirtyConfirm;
- (void)scrollScrollViewToDocumentTop:(NSScrollView *)scrollView;
- (void)resetCurrentDocumentViewportToStart;
- (CGFloat)scrollSpeedPreference;
- (void)setScrollSpeedPreference:(CGFloat)scrollSpeed;
- (void)applyScrollSpeedPreference;
- (void)applyCurrentDocumentReadOnlyState;
- (void)toolbarActionControlChanged:(id)sender;
- (void)updateToolbarActionControlsState;
- (BOOL)canSaveCurrentDocument;
- (void)preferencesExplorerLocalRootChanged:(id)sender;
- (void)preferencesExplorerMaxFileSizeChanged:(id)sender;
- (void)preferencesExplorerListFontSizeChanged:(id)sender;
- (void)preferencesExplorerGitHubTokenChanged:(id)sender;
- (BOOL)saveCurrentMarkdownToPath:(NSString *)path;
- (BOOL)saveDocumentAsMarkdownWithPanel;
- (BOOL)saveDocumentFromVimCommand;
- (void)performCloseFromVimCommandForcingDiscard:(BOOL)force;
- (BOOL)confirmDiscardingUnsavedChangesForAction:(NSString *)actionName;
- (BOOL)confirmReloadingFromDiskDiscardingCurrentChanges;
- (BOOL)confirmOverwritingNewerDiskVersionAtPath:(NSString *)path;
- (NSString *)defaultSaveMarkdownFileName;
- (NSString *)defaultExportFileNameWithExtension:(NSString *)extension;
- (NSString *)defaultExportPDFFileName;
- (void)exportDocumentWithTitle:(NSString *)panelTitle
                      extension:(NSString *)extension
                     actionName:(NSString *)actionName;
- (NSPrintInfo *)configuredPrintInfo;
- (CGFloat)printableContentWidthForPrintInfo:(NSPrintInfo *)printInfo;
- (OMDTextView *)newPrintTextViewForPrintInfo:(NSPrintInfo *)printInfo;
#if defined(_WIN32)
- (NSString *)windowsHeadlessBrowserPath;
- (NSString *)temporaryHTMLExportPath;
- (NSString *)windowsPDFSavePathWithSuggestedName:(NSString *)suggestedName;
- (NSString *)styledHTMLDocumentWithBody:(NSString *)bodyHTML title:(NSString *)title;
- (BOOL)writePandocHTMLForCurrentPreviewToPath:(NSString *)path;
- (BOOL)writeHTMLForPrintView:(OMDTextView *)printView toPath:(NSString *)path;
- (BOOL)exportHTMLAtPath:(NSString *)htmlPath toPDFAtPath:(NSString *)pdfPath usingBrowser:(NSString *)browserPath;
- (BOOL)exportPrintView:(OMDTextView *)printView toPDFAtPath:(NSString *)pdfPath usingBrowser:(NSString *)browserPath;
- (NSString *)temporaryPDFPrintPath;
- (BOOL)launchWindowsShellPrintForPDFAtPath:(NSString *)path;
#endif
- (void)requestInteractiveRender;
- (void)requestInteractiveRenderForLayoutWidthIfNeeded;
- (void)logPreviewStyleDiagnosticsForRenderedString:(NSAttributedString *)rendered;
- (void)updateAdaptiveZoomDebounceWithRenderDurationMs:(NSTimeInterval)durationMs
                                     sampledAsZoomRender:(BOOL)isZoomRender;
- (NSRect)currentPreviewClipBounds;
- (CGFloat)currentPreviewLayoutWidth;
- (void)clearPreviewPresentation;
- (void)updatePreviewDocumentGeometry;
- (void)scheduleInteractiveRenderAfterDelay:(NSTimeInterval)delay;
- (void)interactiveRenderTimerFired:(NSTimer *)timer;
- (void)cancelPendingInteractiveRender;
- (void)mathArtifactsDidWarm:(NSNotification *)notification;
- (void)remoteImagesDidWarm:(NSNotification *)notification;
- (void)scheduleMathArtifactRefresh;
- (void)mathArtifactRenderTimerFired:(NSTimer *)timer;
- (void)cancelPendingMathArtifactRender;
- (void)modeControlChanged:(id)sender;
- (void)setReadMode:(id)sender;
- (void)setEditMode:(id)sender;
- (void)setSplitMode:(id)sender;
- (void)setViewerMode:(OMDViewerMode)mode persistPreference:(BOOL)persistPreference;
- (BOOL)isFormattingBarEnabledPreference;
- (void)setFormattingBarEnabledPreference:(BOOL)enabled;
- (BOOL)isFormattingBarVisibleInCurrentMode;
- (void)toggleFormattingBar:(id)sender;
- (OMDSplitSyncMode)currentSplitSyncMode;
- (void)setSplitSyncModePreference:(OMDSplitSyncMode)mode;
- (void)setSplitSyncModeUnlinked:(id)sender;
- (void)setSplitSyncModeLinkedScrolling:(id)sender;
- (void)setSplitSyncModeCaretSelectionFollow:(id)sender;
- (BOOL)usesLinkedScrolling;
- (BOOL)usesCaretSelectionSync;
- (void)applyViewerModeLayout;
- (void)layoutDocumentViews;
- (void)setupFormattingBar;
- (void)rebuildFormattingBar;
- (CGFloat)layoutFormattingBarControlsForWidth:(CGFloat)containerWidth
                                  applyFrames:(BOOL)applyFrames;
- (void)layoutSourceEditorContainer;
- (void)normalizeWindowFrameIfNeeded;
- (void)updateFormattingBarContextState;
- (void)formattingHeadingControlChanged:(id)sender;
- (void)formattingCommandGroupChanged:(id)sender;
- (void)formattingCommandPressed:(id)sender;
- (void)performFormattingCommandWithTag:(NSInteger)tag;
- (void)toggleBoldFormatting:(id)sender;
- (void)toggleItalicFormatting:(id)sender;
- (NSTextView *)activeEditingTextView;
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (void)updateModeControlSelection;
- (void)updatePreviewStatusIndicator;
- (NSString *)sourceVimStatusText;
- (NSColor *)sourceVimStatusColor;
- (void)schedulePreviewStatusUpdatingVisibility;
- (void)previewStatusUpdatingDelayTimerFired:(NSTimer *)timer;
- (void)cancelPendingPreviewStatusUpdatingVisibility;
- (void)schedulePreviewStatusAutoHideAfterDelay:(NSTimeInterval)delay;
- (void)previewStatusAutoHideTimerFired:(NSTimer *)timer;
- (void)cancelPendingPreviewStatusAutoHide;
- (void)synchronizeSourceEditorWithCurrentMarkdown;
- (void)setPreviewUpdating:(BOOL)updating;
- (void)scrollViewContentBoundsDidChange:(NSNotification *)notification;
- (NSUInteger)visibleCharacterIndexForTextView:(NSTextView *)textView
                                  inScrollView:(NSScrollView *)scrollView
                                verticalAnchor:(CGFloat)verticalAnchor;
- (BOOL)targetScrollPoint:(NSPoint *)pointOut
              forTextView:(NSTextView *)textView
             inScrollView:(NSScrollView *)scrollView
           characterIndex:(NSUInteger)characterIndex
           verticalAnchor:(CGFloat)verticalAnchor;
- (void)linkedScrollDriverResetTimerFired:(NSTimer *)timer;
- (void)refreshLinkedScrollDriver:(OMDLinkedScrollDriver)driver;
- (void)cancelPendingLinkedScrollDriverReset;
- (void)syncPreviewToSourceScrollPosition;
- (void)syncSourceToPreviewScrollPosition;
- (void)syncPreviewToSourceInteractionAnchor;
- (void)syncPreviewToSourceSelection;
- (void)syncSourceSelectionToPreviewSelection;
- (void)scrollPreviewToCharacterIndex:(NSUInteger)characterIndex;
- (void)scrollPreviewToCharacterIndex:(NSUInteger)characterIndex verticalAnchor:(CGFloat)verticalAnchor;
- (void)scrollSourceToCharacterIndex:(NSUInteger)characterIndex verticalAnchor:(CGFloat)verticalAnchor;
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
- (void)updateRendererParsingOptionsForSourcePath:(NSString *)sourcePath;
- (OMMarkdownMathRenderingPolicy)currentMathRenderingPolicy;
- (BOOL)isAllowRemoteImagesEnabled;
- (void)setMathRenderingPolicyPreference:(OMMarkdownMathRenderingPolicy)policy;
- (void)setAllowRemoteImagesPreference:(BOOL)allow;
- (void)applyParsingOptionsAndRender:(OMMarkdownParsingOptions *)options;
- (void)setMathRenderingDisabled:(id)sender;
- (void)setMathRenderingStyledText:(id)sender;
- (void)setMathRenderingExternalTools:(id)sender;
- (void)toggleAllowRemoteImages:(id)sender;
- (void)increaseSourceEditorFontSize:(id)sender;
- (void)decreaseSourceEditorFontSize:(id)sender;
- (void)resetSourceEditorFontSize:(id)sender;
- (void)chooseSourceEditorFont:(id)sender;
- (void)showAboutPanel:(id)sender;
- (void)showPreferences:(id)sender;
- (void)releasePreferencesPanelControls;
- (void)rebuildPreferencesPanelContent;
- (void)normalizePreferencesPanelFrameForSize:(NSSize)size;
- (void)syncPreferencesPanelFromSettings;
- (void)buildPreferencesAppearanceSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (void)buildPreferencesExplorerSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (void)buildPreferencesPreviewSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (void)buildPreferencesEditorSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (NSView *)preferencesItemContainerForSection:(OMDPreferencesSection)section
                                   contentRect:(NSRect)contentRect
                                       metrics:(OMDLayoutMetrics)metrics;
- (void)preferencesSectionChanged:(id)sender;
- (void)preferencesMathPolicyChanged:(id)sender;
- (void)preferencesSplitSyncModeChanged:(id)sender;
- (void)preferencesLayoutModeChanged:(id)sender;
- (void)preferencesScrollSpeedChanged:(id)sender;
- (void)preferencesAllowRemoteImagesChanged:(id)sender;
- (void)preferencesFormattingBarChanged:(id)sender;
- (void)preferencesWordSelectionShimChanged:(id)sender;
- (void)preferencesSourceVimKeyBindingsChanged:(id)sender;
- (void)preferencesSyntaxHighlightingChanged:(id)sender;
- (void)preferencesSourceHighContrastChanged:(id)sender;
- (void)preferencesSourceAccentColorChanged:(id)sender;
- (void)preferencesSourceAccentReset:(id)sender;
- (void)preferencesRendererSyntaxHighlightingChanged:(id)sender;
- (BOOL)isWordSelectionModifierShimEnabled;
- (void)setWordSelectionModifierShimEnabled:(BOOL)enabled;
- (void)toggleWordSelectionModifierShim:(id)sender;
- (BOOL)isSourceVimKeyBindingsEnabled;
- (void)setSourceVimKeyBindingsEnabled:(BOOL)enabled;
- (void)toggleSourceVimKeyBindings:(id)sender;
- (void)configureSourceVimBindingController;
- (BOOL)sourceTextView:(OMDSourceTextView *)textView handleVimKeyEvent:(NSEvent *)event;
- (BOOL)vimBindingController:(GSVVimBindingController *)controller
              handleExAction:(GSVVimExAction)action
                       force:(BOOL)force
                  rawCommand:(NSString *)rawCommand
                 forTextView:(NSTextView *)textView;
- (void)vimBindingController:(GSVVimBindingController *)controller
        didUpdateCommandLine:(NSString *)commandLine
                      active:(BOOL)active
                 forTextView:(NSTextView *)textView;
- (BOOL)isSourceSyntaxHighlightingEnabled;
- (void)setSourceSyntaxHighlightingEnabled:(BOOL)enabled;
- (void)toggleSourceSyntaxHighlighting:(id)sender;
- (BOOL)isSourceHighlightHighContrastEnabled;
- (void)setSourceHighlightHighContrastEnabled:(BOOL)enabled;
- (void)toggleSourceHighlightHighContrast:(id)sender;
- (NSColor *)sourceHighlightAccentColor;
- (void)setSourceHighlightAccentColor:(NSColor *)color;
- (BOOL)isTreeSitterAvailable;
- (BOOL)isRendererSyntaxHighlightingPreferenceEnabled;
- (BOOL)isRendererSyntaxHighlightingEnabled;
- (void)setRendererSyntaxHighlightingPreferenceEnabled:(BOOL)enabled;
- (void)toggleRendererSyntaxHighlighting:(id)sender;
- (NSString *)currentGNUstepThemeName;
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (void)setLayoutDensityPreference:(OMDLayoutDensityMode)mode;
- (void)applyLayoutDensityPreference;
- (void)requestSourceSyntaxHighlightingRefresh;
- (void)scheduleSourceSyntaxHighlightingAfterDelay:(NSTimeInterval)delay;
- (void)sourceSyntaxHighlightTimerFired:(NSTimer *)timer;
- (void)cancelPendingSourceSyntaxHighlighting;
- (NSString *)themePreference;
- (void)setThemePreference:(NSString *)themeName;
- (NSArray *)availableThemeNames;
- (void)reloadThemePopupItems;
- (void)preferencesThemeChanged:(id)sender;
- (void)showThemeRestartNotice;
- (NSColor *)sourceEditorBaseTextColor;
- (NSRange)sourceSyntaxHighlightIncrementalRangeForStorage:(NSTextStorage *)storage;
- (void)applySourceSyntaxHighlightingNow;
- (void)clearSourceSyntaxHighlighting;
- (BOOL)restoreRecoveryIfAvailable;
- (void)scheduleRecoveryAutosave;
- (void)recoveryAutosaveTimerFired:(NSTimer *)timer;
- (void)cancelPendingRecoveryAutosave;
- (BOOL)writeRecoverySnapshot;
- (void)clearRecoverySnapshot;
- (NSString *)recoverySnapshotPath;
- (void)applyCopyButtonDefaultAppearance:(NSButton *)button;
- (void)showCopyFeedbackForButton:(NSButton *)button;
- (void)copyFeedbackTimerFired:(NSTimer *)timer;
- (void)hideCopyFeedback;
- (void)replaceSourceTextInRange:(NSRange)range withString:(NSString *)replacement selectedRange:(NSRange)selection;
- (void)applyInlineWrapWithPrefix:(NSString *)prefix
                           suffix:(NSString *)suffix
                      placeholder:(NSString *)placeholder;
- (void)applyLinkTemplateCommand;
- (void)applyImageTemplateCommand;
- (NSRange)sourceLineRangeForSelection:(NSRange)selection source:(NSString *)source;
- (NSArray *)sourceLinesForRange:(NSRange)range source:(NSString *)source trailingNewline:(BOOL *)trailingNewline;
- (void)applyLineTransformWithTag:(OMDFormattingCommandTag)tag;
- (void)applyCodeFenceCommand;
- (void)applyTableCommand;
- (void)applyHorizontalRuleCommand;
- (void)applyHeadingLevel:(NSInteger)level;
- (NSString *)lineByRemovingMarkdownPrefix:(NSString *)line;
- (NSInteger)headingLevelForLine:(NSString *)line;
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
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:OMMarkdownRendererRemoteImagesDidWarmNotification
                                                  object:nil];
    if (_sourceScrollView != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSViewBoundsDidChangeNotification
                                                      object:[_sourceScrollView contentView]];
    }
    if (_previewScrollView != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSViewBoundsDidChangeNotification
                                                      object:[_previewScrollView contentView]];
    }
    [self cancelPendingInteractiveRender];
    [self cancelPendingMathArtifactRender];
    [self cancelPendingLivePreviewRender];
    [self cancelPendingPreviewStatusUpdatingVisibility];
    [self cancelPendingPreviewStatusAutoHide];
    [self cancelPendingSourceSyntaxHighlighting];
    [self cancelPendingRecoveryAutosave];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(performDeferredInitialLaunchWork)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(runDeferredPostPresentationSetup)
                                               object:nil];
    [self stopExternalFileMonitor];
    [self hideCopyFeedback];
    [_sourceVimCommandLine release];
    [_pendingLaunchOpenPath release];
    [_currentDocumentSyntaxLanguage release];
    [_currentDisplayTitle release];
    [_currentMarkdown release];
    [_currentPath release];
    [_currentLoadedDiskFingerprint release];
    [_currentObservedDiskFingerprint release];
    [_currentSuppressedDiskFingerprint release];
    [_documentTabs release];
    [_gitHubClient release];
    if (_fileOpenRecentMenu != nil) {
        [_fileOpenRecentMenu setDelegate:nil];
        [_fileOpenRecentMenu release];
    }
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
    [_toolbarFileActionsControl release];
    [_toolbarUtilityActionsControl release];
    [_toolbarPrimaryActionsContainer release];
    [_zoomSlider release];
    [_zoomLabel release];
    [_zoomResetButton release];
    [_zoomContainer release];
    [_launchOverlayTitleLabel release];
    [_launchOverlayDetailLabel release];
    [_launchOverlayView release];
    [_modeLabel release];
    [_previewStatusLabel release];
    [_modeControl release];
    [_modeContainer release];
    [_linkedScrollDriverResetTimer invalidate];
    [_linkedScrollDriverResetTimer release];
    [_preferencesSectionControl release];
    [_preferencesMathPolicyPopup release];
    [_preferencesSplitSyncModePopup release];
    [_preferencesThemePopup release];
    [_preferencesLayoutModePopup release];
    [_preferencesAllowRemoteImagesButton release];
    [_preferencesFormattingBarButton release];
    [_preferencesWordSelectionShimButton release];
    [_preferencesSourceVimKeyBindingsButton release];
    [_preferencesSyntaxHighlightingButton release];
    [_preferencesSourceHighContrastButton release];
    [_preferencesSourceAccentColorWell release];
    [_preferencesSourceAccentResetButton release];
    [_preferencesRendererSyntaxHighlightingButton release];
    [_preferencesRendererSyntaxHighlightingNoteLabel release];
    [_preferencesExplorerLocalRootField release];
    [_preferencesExplorerMaxFileSizeField release];
    [_preferencesExplorerListFontSizeField release];
    [_preferencesExplorerGitHubTokenField release];
    [_formatHeadingControl release];
    [_formatCommandButtons release];
    [_formattingBarView release];
    [_sourceEditorContainer release];
    [_preferencesPanel release];
    [_codeBlockButtons release];
    [_documentConverter release];
    [_sourceVimBindingController release];
    [_sourceLineNumberRuler release];
    [_splitView release];
    [_workspaceSplitView release];
    [_workspaceMainContainer release];
    [_sidebarContainer release];
    [_tabStripView release];
    [_renderer release];
    [_sourceTextView release];
    [_sourceScrollView release];
    [_previewScrollView release];
    [_previewCanvasView release];
    [_documentContainer release];
    [_textView release];
    [_window release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    OMDStartupTrace(@"appDidFinishLaunching: enter");
#if defined(_WIN32)
    // Ensure OpenSave is initialized and prefers native Win32 dialogs.
    GSOpenSaveSetMode(GSOpenSaveModeWin32);
#else
    GSOpenSaveSetMode(GSOpenSaveModeAuto);
#endif
    OMDStartupTrace(@"appDidFinishLaunching: open-save mode set");

    [self setupWindow];
    OMDStartupTrace(@"appDidFinishLaunching: setupWindow returned");
    if ([NSApp mainMenu] == nil || [[NSApp mainMenu] numberOfItems] == 0) {
        OMDStartupTrace(@"appDidFinishLaunching: main menu missing, rebuilding");
        @try {
            [self setupMainMenu];
            OMDRefreshWindowsMainMenu();
            OMDApplyWindowsMenuToWindow(_window);
            OMDLogMenuSnapshot(@"appDidFinishLaunching: after menu rebuild", [NSApp mainMenu], _window);
        } @catch (id exception) {
            OMDStartupTrace([NSString stringWithFormat:@"appDidFinishLaunching: menu rebuild threw class=%@ description=%@",
                                                       NSStringFromClass([exception class]),
                                                       exception]);
        }
    }

    NSString *startupPath = (_pendingLaunchOpenPath != nil ? _pendingLaunchOpenPath
                                                           : [self firstLaunchDocumentPathFromArguments]);
    BOOL shouldCheckRecovery = (!_openedFileOnLaunch &&
                                [startupPath length] == 0 &&
                                [self hasRecoverySnapshotAvailable]);
    if ([startupPath length] > 0) {
        [self showLaunchOverlayWithTitle:@"Loading document..."
                                  detail:[startupPath lastPathComponent]];
    } else if (shouldCheckRecovery) {
        [self showLaunchOverlayWithTitle:@"Checking recovery snapshot..."
                                  detail:nil];
    } else {
        [self hideLaunchOverlay];
    }

    [self presentWindowIfNeeded];
    if ([startupPath length] > 0 || shouldCheckRecovery) {
        _launchWorkScheduled = YES;
        [self performSelector:@selector(performDeferredInitialLaunchWork)
                   withObject:nil
                   afterDelay:0.0];
    } else {
        [self schedulePostPresentationSetupIfNeeded];
    }

    if (OMDLaunchPrintAutomationEnabled()) {
        [self performSelector:@selector(runLaunchPrintAutomationIfRequested)
                   withObject:nil
                   afterDelay:0.8];
    }
    if (OMDLaunchPDFExportAutomationPath() != nil) {
        [self performSelector:@selector(runLaunchPDFExportAutomationIfRequested)
                   withObject:nil
                   afterDelay:1.0];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    [self refreshCurrentDocumentDiskStateAllowPrompt:YES];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    OMDStartupTrace(@"applicationWillFinishLaunching: enter");
    @try {
        [self setupMainMenu];
        OMDStartupTrace(@"applicationWillFinishLaunching: setupMainMenu returned");
    } @catch (id exception) {
        OMDStartupTrace([NSString stringWithFormat:@"applicationWillFinishLaunching: setupMainMenu threw class=%@ description=%@",
                                                   NSStringFromClass([exception class]),
                                                   exception]);
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    (void)theApplication;
    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:filename];
    _openedFileOnLaunch = YES;

    BOOL shouldDeferForLaunch = (_window == nil ||
                                 _launchWorkScheduled ||
                                 (!_postPresentationSetupComplete &&
                                  [_documentTabs count] == 0 &&
                                  _currentPath == nil &&
                                  _currentMarkdown == nil));
    if (shouldDeferForLaunch) {
        [_pendingLaunchOpenPath release];
        _pendingLaunchOpenPath = [(resolvedPath != nil ? resolvedPath : filename) copy];
        if (_window != nil) {
            [self showLaunchOverlayWithTitle:@"Loading document..."
                                      detail:[_pendingLaunchOpenPath lastPathComponent]];
            [self presentWindowIfNeeded];
            if (!_launchWorkScheduled) {
                _launchWorkScheduled = YES;
                [self performSelector:@selector(performDeferredInitialLaunchWork)
                           withObject:nil
                           afterDelay:0.0];
            }
        }
        return YES;
    }

    BOOL openInNewTab = !([_documentTabs count] == 0 && _currentPath == nil && _currentMarkdown == nil);
    return [self openDocumentAtPath:(resolvedPath != nil ? resolvedPath : filename)
                           inNewTab:openInNewTab
                requireDirtyConfirm:!openInNewTab];
}

- (void)setupMainMenu
{
    OMDStartupTrace(@"setupMainMenu: enter");
    NSMenu *menubar = [[[NSMenu alloc] initWithTitle:@"GSMainMenu"] autorelease];

    NSString *appName = [[NSProcessInfo processInfo] processName];
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
    [aboutItem setTarget:self];
    [appMenu addItem:aboutItem];

    NSMenuItem *preferencesItem = (NSMenuItem *)[appMenu addItemWithTitle:@"Preferences..."
                                                                    action:@selector(showPreferences:)
                                                             keyEquivalent:@","];
    [preferencesItem setTarget:self];
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
                     keyEquivalent:@"o"] setTarget:self];
    [[fileMenuWin addItemWithTitle:@"New Window"
                            action:@selector(newWindow:)
                     keyEquivalent:@"n"] setTarget:self];
    NSMenuItem *openRecentItemWin = (NSMenuItem *)[fileMenuWin addItemWithTitle:@"Open Recent"
                                                                           action:NULL
                                                                    keyEquivalent:@""];
    NSMenu *openRecentMenuWin = [[[NSMenu alloc] initWithTitle:@"Open Recent"] autorelease];
    [openRecentMenuWin setAutoenablesItems:NO];
    [openRecentMenuWin setDelegate:(id)self];
    [openRecentItemWin setSubmenu:openRecentMenuWin];
    [_fileOpenRecentMenu release];
    _fileOpenRecentMenu = [openRecentMenuWin retain];
    [[fileMenuWin addItemWithTitle:@"Import..."
                            action:@selector(importDocument:)
                     keyEquivalent:@"I"] setTarget:self];
    [fileMenuWin addItem:[NSMenuItem separatorItem]];
    [[fileMenuWin addItemWithTitle:@"Save"
                            action:@selector(saveDocument:)
                     keyEquivalent:@"s"] setTarget:self];
    [[fileMenuWin addItemWithTitle:@"Save Markdown As..."
                            action:@selector(saveDocumentAsMarkdown:)
                     keyEquivalent:@"S"] setTarget:self];
    [[fileMenuWin addItemWithTitle:@"Reload from Disk"
                            action:@selector(reloadDocumentFromDisk:)
                     keyEquivalent:@""] setTarget:self];
    [fileMenuWin addItem:[NSMenuItem separatorItem]];
    [[fileMenuWin addItemWithTitle:@"Print..."
                            action:@selector(printDocument:)
                     keyEquivalent:@"p"] setTarget:self];
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
                     keyEquivalent:@"z"] setTarget:self];
    [[editMenuWin addItemWithTitle:@"Redo"
                            action:@selector(redo:)
                     keyEquivalent:@"Z"] setTarget:self];
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
                  keyEquivalent:@"1"] setTarget:self];
    [[viewMenuWin addItemWithTitle:@"Edit Mode"
                         action:@selector(setEditMode:)
                  keyEquivalent:@"2"] setTarget:self];
    [[viewMenuWin addItemWithTitle:@"Split Mode"
                         action:@selector(setSplitMode:)
                  keyEquivalent:@"3"] setTarget:self];
    _viewShowExplorerMenuItem = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Show Explorer"
                                                                   action:@selector(toggleExplorerSidebar:)
                                                            keyEquivalent:@""];
    [_viewShowExplorerMenuItem setTarget:self];
    _viewShowFormattingBarMenuItem = (NSMenuItem *)[viewMenuWin addItemWithTitle:@"Show Formatting Bar"
                                                                        action:@selector(toggleFormattingBar:)
                                                                 keyEquivalent:@""];
    [_viewShowFormattingBarMenuItem setTarget:self];
    [viewMenuItemWin setSubmenu:viewMenuWin];

    OMDLogMenuSnapshot(@"setupMainMenu: before setMainMenu", menubar, _window);
    [NSApp setMainMenu:menubar];
    OMDLogMenuSnapshot(@"setupMainMenu: after setMainMenu", [NSApp mainMenu], _window);
    OMDRefreshWindowsMainMenu();
    OMDLogMenuSnapshot(@"setupMainMenu: after refresh", [NSApp mainMenu], _window);
    OMDStartupTrace(@"setupMainMenu: complete");
    return;
#endif

    NSMenuItem *fileMenuItem = [[[NSMenuItem alloc] initWithTitle:@"File"
                                                           action:NULL
                                                    keyEquivalent:@""] autorelease];
    [menubar addItem:fileMenuItem];

    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    NSMenuItem *openItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Open Markdown..."
                                                             action:@selector(openDocument:)
                                                      keyEquivalent:@"o"];
    [openItem setTarget:self];

    NSMenuItem *newWindowItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"New Window"
                                                                   action:@selector(newWindow:)
                                                            keyEquivalent:@"n"];
    [newWindowItem setTarget:self];

    NSMenuItem *openRecentItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Open Recent"
                                                                    action:NULL
                                                             keyEquivalent:@""];
    NSMenu *openRecentMenu = [[[NSMenu alloc] initWithTitle:@"Open Recent"] autorelease];
    [openRecentMenu setAutoenablesItems:NO];
    [openRecentMenu setDelegate:(id)self];
    [openRecentItem setSubmenu:openRecentMenu];
    [_fileOpenRecentMenu release];
    _fileOpenRecentMenu = [openRecentMenu retain];
    [self rebuildOpenRecentMenu];

    NSMenuItem *importItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Import..."
                                                                action:@selector(importDocument:)
                                                         keyEquivalent:@"I"];
    [importItem setTarget:self];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *saveItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Save"
                                                              action:@selector(saveDocument:)
                                                       keyEquivalent:@"s"];
    [saveItem setTarget:self];

    NSMenuItem *saveAsItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Save Markdown As..."
                                                                action:@selector(saveDocumentAsMarkdown:)
                                                         keyEquivalent:@"S"];
    [saveAsItem setTarget:self];

    NSMenuItem *reloadItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Reload from Disk"
                                                               action:@selector(reloadDocumentFromDisk:)
                                                        keyEquivalent:@""];
    [reloadItem setTarget:self];

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
    NSMenuItem *exportHTMLItem = (NSMenuItem *)[exportMenu addItemWithTitle:@"Export as HTML..."
                                                                      action:@selector(exportDocumentAsHTML:)
                                                               keyEquivalent:@""];
    [exportHTMLItem setTarget:self];
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

    NSMenuItem *editMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Edit"
                                                            action:NULL
                                                     keyEquivalent:@""] autorelease];
    [menubar addItem:editMenuItem];

    NSMenu *editMenu = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
    NSMenuItem *undoItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Undo"
                                                              action:@selector(undo:)
                                                       keyEquivalent:@"z"];
    [undoItem setTarget:self];
    NSMenuItem *redoItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Redo"
                                                              action:@selector(redo:)
                                                       keyEquivalent:@"Z"];
    [redoItem setTarget:self];
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
    [toggleBoldItem setTarget:self];
    [toggleBoldItem setKeyEquivalentModifierMask:NSControlKeyMask];
    NSMenuItem *toggleItalicItem = (NSMenuItem *)[editMenu addItemWithTitle:@"Toggle Italic"
                                                                      action:@selector(toggleItalicFormatting:)
                                                               keyEquivalent:@"i"];
    [toggleItalicItem setTarget:self];
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
    [readItem setTarget:self];
    NSMenuItem *editItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Edit Mode"
                                                             action:@selector(setEditMode:)
                                                      keyEquivalent:@"2"];
    [editItem setTarget:self];
    NSMenuItem *splitItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Split Mode"
                                                              action:@selector(setSplitMode:)
                                                       keyEquivalent:@"3"];
    [splitItem setTarget:self];

    NSMenuItem *splitSyncMenuItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Split Sync"
                                                                       action:NULL
                                                                keyEquivalent:@""];
    NSMenu *splitSyncMenu = [[[NSMenu alloc] initWithTitle:@"Split Sync"] autorelease];
    NSMenuItem *splitSyncUnlinkedItem = (NSMenuItem *)[splitSyncMenu addItemWithTitle:@"Independent"
                                                                                 action:@selector(setSplitSyncModeUnlinked:)
                                                                          keyEquivalent:@""];
    [splitSyncUnlinkedItem setTarget:self];
    NSMenuItem *splitSyncLinkedItem = (NSMenuItem *)[splitSyncMenu addItemWithTitle:@"Linked Scrolling"
                                                                               action:@selector(setSplitSyncModeLinkedScrolling:)
                                                                        keyEquivalent:@""];
    [splitSyncLinkedItem setTarget:self];
    NSMenuItem *splitSyncCaretItem = (NSMenuItem *)[splitSyncMenu addItemWithTitle:@"Follow Caret"
                                                                              action:@selector(setSplitSyncModeCaretSelectionFollow:)
                                                                       keyEquivalent:@""];
    [splitSyncCaretItem setTarget:self];
    [splitSyncMenuItem setSubmenu:splitSyncMenu];

    _viewShowExplorerMenuItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Show Explorer"
                                                                   action:@selector(toggleExplorerSidebar:)
                                                            keyEquivalent:@""];
    [_viewShowExplorerMenuItem setTarget:self];

    _viewShowFormattingBarMenuItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Show Formatting Bar"
                                                                        action:@selector(toggleFormattingBar:)
                                                                 keyEquivalent:@""];
    [_viewShowFormattingBarMenuItem setTarget:self];

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
                                                               keyEquivalent:@"="];
    [increaseFontItem setTarget:self];
    [increaseFontItem setKeyEquivalentModifierMask:NSControlKeyMask];
    NSMenuItem *decreaseFontItem = (NSMenuItem *)[fontMenu addItemWithTitle:@"Decrease Size"
                                                                      action:@selector(decreaseSourceEditorFontSize:)
                                                               keyEquivalent:@"-"];
    [decreaseFontItem setTarget:self];
    [decreaseFontItem setKeyEquivalentModifierMask:NSControlKeyMask];
    NSMenuItem *resetFontItem = (NSMenuItem *)[fontMenu addItemWithTitle:@"Reset Size"
                                                                   action:@selector(resetSourceEditorFontSize:)
                                                            keyEquivalent:@""];
    [resetFontItem setTarget:self];
    [fontMenuItem setSubmenu:fontMenu];

    NSMenuItem *wordSelectionShimItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Word Selection for Ctrl/Cmd+Shift+Arrow"
                                                                            action:@selector(toggleWordSelectionModifierShim:)
                                                                     keyEquivalent:@""];
    [wordSelectionShimItem setTarget:self];
    NSMenuItem *sourceVimKeyBindingsItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Vim Key Bindings (Source Editor)"
                                                                               action:@selector(toggleSourceVimKeyBindings:)
                                                                        keyEquivalent:@""];
    [sourceVimKeyBindingsItem setTarget:self];
    NSMenuItem *syntaxHighlightingItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Source Syntax Highlighting"
                                                                            action:@selector(toggleSourceSyntaxHighlighting:)
                                                                     keyEquivalent:@""];
    [syntaxHighlightingItem setTarget:self];
    NSMenuItem *sourceHighlightContrastItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Source Highlight High Contrast"
                                                                                  action:@selector(toggleSourceHighlightHighContrast:)
                                                                           keyEquivalent:@""];
    [sourceHighlightContrastItem setTarget:self];
    NSMenuItem *rendererSyntaxHighlightingItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Renderer Syntax Highlighting"
                                                                                    action:@selector(toggleRendererSyntaxHighlighting:)
                                                                             keyEquivalent:@""];
    [rendererSyntaxHighlightingItem setTarget:self];

    [viewMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *mathMenuItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Math Rendering"
                                                                  action:NULL
                                                           keyEquivalent:@""];
    NSMenu *mathMenu = [[[NSMenu alloc] initWithTitle:@"Math Rendering"] autorelease];
    NSMenuItem *mathStyledItem = (NSMenuItem *)[mathMenu addItemWithTitle:@"Styled Text (Safe)"
                                                                    action:@selector(setMathRenderingStyledText:)
                                                             keyEquivalent:@""];
    [mathStyledItem setTarget:self];
    NSMenuItem *mathDisabledItem = (NSMenuItem *)[mathMenu addItemWithTitle:@"Disabled (Literal $...$)"
                                                                      action:@selector(setMathRenderingDisabled:)
                                                               keyEquivalent:@""];
    [mathDisabledItem setTarget:self];
    NSMenuItem *mathExternalItem = (NSMenuItem *)[mathMenu addItemWithTitle:@"External Tools (LaTeX)"
                                                                      action:@selector(setMathRenderingExternalTools:)
                                                               keyEquivalent:@""];
    [mathExternalItem setTarget:self];
    [mathMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *remoteImagesItem = (NSMenuItem *)[mathMenu addItemWithTitle:@"Allow Remote Images"
                                                                      action:@selector(toggleAllowRemoteImages:)
                                                               keyEquivalent:@""];
    [remoteImagesItem setTarget:self];
    [mathMenuItem setSubmenu:mathMenu];

    [viewMenuItem setSubmenu:viewMenu];

    OMDLogMenuSnapshot(@"setupMainMenu: before setMainMenu", menubar, _window);
    [NSApp setMainMenu:menubar];
    OMDLogMenuSnapshot(@"setupMainMenu: after setMainMenu", [NSApp mainMenu], _window);
    OMDRefreshWindowsMainMenu();
    OMDLogMenuSnapshot(@"setupMainMenu: after refresh", [NSApp mainMenu], _window);
    OMDStartupTrace(@"setupMainMenu: complete");
}

- (void)setupWindow
{
    OMDStartupTrace(@"setupWindow: enter");
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    NSRect frame = NSMakeRect(100, 100, OMDDefaultWindowWidth(), OMDDefaultWindowHeight());
    _window = [[OMDMainWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [_window setMinSize:NSMakeSize(OMDMinimumUsableWindowWidth(), 600.0)];
    [_window setFrameAutosaveName:@"ObjcMarkdownViewerMainWindow"];
    [self normalizeWindowFrameIfNeeded];
    [_window setTitle:@"Markdown Viewer"];
    [_window setDelegate:self];
    NSImage *appIcon = OMDImageNamed(@"markdown_icon.png");
    if (appIcon != nil) {
        [NSApp setApplicationIconImage:appIcon];
        if ([_window respondsToSelector:@selector(setMiniwindowImage:)]) {
            [_window setMiniwindowImage:appIcon];
        }
    }
    [self applyWindowsWindowIconsIfPossible];
    OMDStartupTrace(@"setupWindow: window created");

    OMDApplyWindowsMenuToWindow(_window);

    _zoomScale = 1.0;
    _zoomUsesDebouncedRendering = NO;
    _zoomFastRenderStreak = 0;
    _lastZoomSliderEventTime = 0.0;
    NSNumber *savedZoom = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownZoomScale"];
    if (savedZoom != nil) {
        double value = [savedZoom doubleValue];
        if (value > 0.25 && value < 4.0) {
            _zoomScale = value;
        }
    }
    [self setupToolbar];
    OMDStartupTrace(@"setupWindow: setupToolbar returned");
    [self setupWorkspaceChrome];
    OMDStartupTrace(@"setupWindow: setupWorkspaceChrome returned");

    _splitRatio = 0.5;
    _lastObservedSplitAvailableWidth = -1.0;
    _isApplyingSplitViewRatio = NO;
    NSNumber *savedSplitRatio = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownSplitRatio"];
    if ([savedSplitRatio respondsToSelector:@selector(doubleValue)]) {
        double value = [savedSplitRatio doubleValue];
        if (value > 0.15 && value < 0.85) {
            _splitRatio = (CGFloat)value;
        }
    }

    _splitView = [[OMDWin11SplitView alloc] initWithFrame:[_documentContainer bounds]];
    [_splitView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_splitView setVertical:YES];
    [_splitView setDelegate:self];

    _previewScrollView = [[NSScrollView alloc] initWithFrame:[_documentContainer bounds]];
    [_previewScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_previewScrollView setHasVerticalScroller:YES];
    [_previewScrollView setHasHorizontalScroller:YES];
    [_previewScrollView setAutohidesScrollers:YES];
    [_previewScrollView setDrawsBackground:YES];
    [_previewScrollView setBackgroundColor:OMDResolvedChromeBackgroundColor()];

    _previewCanvasView = [[OMDPreviewCanvasView alloc] initWithFrame:[[_previewScrollView contentView] bounds]];
    [_previewCanvasView setAutoresizesSubviews:NO];
    if ([_previewCanvasView isKindOfClass:[OMDFlippedFillView class]]) {
        [(OMDFlippedFillView *)_previewCanvasView setFillColor:OMDResolvedChromeBackgroundColor()];
    }

    _textView = [[OMDTextView alloc] initWithFrame:[[_previewScrollView contentView] bounds]];
    [_textView setAutoresizingMask:0];
    [_textView setMinSize:NSMakeSize(0.0, 0.0)];
    [_textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [_textView setHorizontallyResizable:NO];
    [_textView setVerticallyResizable:NO];
    [_textView setEditable:NO];
    [_textView setSelectable:YES];
    [_textView setRichText:YES];
    [_textView setDrawsBackground:NO];
    [_textView setTextContainerInset:NSMakeSize(metrics.previewTextInsetX, metrics.previewTextInsetY)];
    if ([_textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *previewTextView = (OMDTextView *)_textView;
        [previewTextView setDocumentBackgroundColor:[NSColor whiteColor]];
        [previewTextView setDocumentBorderColor:OMDResolvedSubtleSeparatorColor()];
        [previewTextView setDocumentCornerRadius:OMDPreviewPageCornerRadius];
        [previewTextView setDocumentBorderWidth:OMDPreviewPageBorderWidth];
    }
    NSTextContainer *previewContainer = [_textView textContainer];
    [previewContainer setLineFragmentPadding:0.0];
    [previewContainer setWidthTracksTextView:NO];
    [previewContainer setHeightTracksTextView:NO];
    CGFloat initialLayoutWidth = NSWidth([[_previewScrollView contentView] bounds]) - 40.0;
    if (initialLayoutWidth < 1.0) {
        initialLayoutWidth = 1.0;
    }
    [previewContainer setContainerSize:NSMakeSize(initialLayoutWidth, FLT_MAX)];
    [_textView setDelegate:self];

    [_textView setLinkTextAttributes:@{
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.03 green:0.41 blue:0.85 alpha:1.0],
        NSUnderlineStyleAttributeName: [NSNumber numberWithInt:NSUnderlineStyleSingle]
    }];

    [_previewCanvasView addSubview:_textView];
    [_previewScrollView setDocumentView:_previewCanvasView];
    [self clearPreviewPresentation];
    [[_previewScrollView contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scrollViewContentBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:[_previewScrollView contentView]];

    _sourceEditorContainer = [[NSView alloc] initWithFrame:[_documentContainer bounds]];
    [_sourceEditorContainer setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    _sourceScrollView = [[NSScrollView alloc] initWithFrame:[_sourceEditorContainer bounds]];
    [_sourceScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_sourceScrollView setHasVerticalScroller:YES];
    [_sourceScrollView setAutohidesScrollers:YES];
    [_sourceScrollView setHasHorizontalRuler:NO];
    [_sourceScrollView setHasVerticalRuler:YES];
    [_sourceScrollView setRulersVisible:YES];

    _sourceTextView = [[OMDSourceTextView alloc] initWithFrame:[[_sourceScrollView contentView] bounds]];
    [_sourceTextView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_sourceTextView setEditable:YES];
    [_sourceTextView setSelectable:YES];
    [_sourceTextView setRichText:NO];
    [_sourceTextView setAllowsUndo:YES];
    [_sourceTextView setUsesRuler:NO];
    [_sourceTextView setRulerVisible:NO];
    [_sourceTextView setTextContainerInset:NSMakeSize(metrics.sourceTextInsetX, metrics.sourceTextInsetY)];
    [[_sourceTextView textContainer] setLineFragmentPadding:0.0];
    [_sourceTextView setDelegate:self];
    [self applySourceEditorFontFromDefaults];
    [self configureSourceVimBindingController];
    [_sourceTextView setString:@""];
    _sourceHighlightNeedsFullPass = YES;
    [_sourceScrollView setDocumentView:_sourceTextView];
    [[_sourceScrollView contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scrollViewContentBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:[_sourceScrollView contentView]];
    [self applyScrollSpeedPreference];
    _sourceLineNumberRuler = [[OMDLineNumberRulerView alloc] initWithScrollView:_sourceScrollView
                                                                        textView:_sourceTextView];
    [_sourceScrollView setVerticalRulerView:_sourceLineNumberRuler];
    [_sourceEditorContainer addSubview:_sourceScrollView];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    (void)defaults;
    _showFormattingBar = [self isFormattingBarEnabledPreference];
    [self setupFormattingBar];
    [self layoutSourceEditorContainer];

    [_splitView addSubview:_sourceEditorContainer];
    [_splitView addSubview:_previewScrollView];

    [_documentContainer addSubview:_previewScrollView];
    _launchOverlayView = [[OMDFlippedFillView alloc] initWithFrame:[_documentContainer bounds]];
    [_launchOverlayView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    if ([_launchOverlayView isKindOfClass:[OMDFlippedFillView class]]) {
        [(OMDFlippedFillView *)_launchOverlayView setFillColor:OMDResolvedChromeBackgroundColor()];
    }
    [_launchOverlayView setHidden:YES];

    NSRect overlayBounds = [_launchOverlayView bounds];
    CGFloat cardWidth = 420.0;
    CGFloat cardHeight = 110.0;
    OMDRoundedCardView *launchCard = [[[OMDRoundedCardView alloc]
        initWithFrame:NSMakeRect(floor((NSWidth(overlayBounds) - cardWidth) * 0.5),
                                 floor((NSHeight(overlayBounds) - cardHeight) * 0.5),
                                 cardWidth,
                                 cardHeight)] autorelease];
    [launchCard setAutoresizingMask:(NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin)];
    [launchCard setFillColor:OMDResolvedPanelCardFillColor()];
    [launchCard setBorderColor:OMDResolvedPanelCardBorderColor()];
    [launchCard setCornerRadius:14.0];

    _launchOverlayTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(22.0, 58.0, cardWidth - 44.0, 24.0)];
    [_launchOverlayTitleLabel setBezeled:NO];
    [_launchOverlayTitleLabel setEditable:NO];
    [_launchOverlayTitleLabel setSelectable:NO];
    [_launchOverlayTitleLabel setDrawsBackground:NO];
    [_launchOverlayTitleLabel setAlignment:NSCenterTextAlignment];
    [_launchOverlayTitleLabel setFont:[NSFont boldSystemFontOfSize:16.0]];
    [_launchOverlayTitleLabel setStringValue:@"Loading document..."];
    [launchCard addSubview:_launchOverlayTitleLabel];

    _launchOverlayDetailLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(22.0, 30.0, cardWidth - 44.0, 20.0)];
    [_launchOverlayDetailLabel setBezeled:NO];
    [_launchOverlayDetailLabel setEditable:NO];
    [_launchOverlayDetailLabel setSelectable:NO];
    [_launchOverlayDetailLabel setDrawsBackground:NO];
    [_launchOverlayDetailLabel setAlignment:NSCenterTextAlignment];
    [_launchOverlayDetailLabel setTextColor:[NSColor disabledControlTextColor]];
    [_launchOverlayDetailLabel setFont:[NSFont systemFontOfSize:12.0]];
    [_launchOverlayDetailLabel setStringValue:@""];
    [launchCard addSubview:_launchOverlayDetailLabel];

    [_launchOverlayView addSubview:launchCard];
    [_documentContainer addSubview:_launchOverlayView];

    [self applyExplorerSidebarVisibility];

    _renderer = [[OMMarkdownRenderer alloc] init];
    OMDStartupTrace(@"setupWindow: renderer allocated");
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    id mathPolicyValue = [defaults objectForKey:OMDMathRenderingPolicyDefaultsKey];
    if ([mathPolicyValue respondsToSelector:@selector(integerValue)]) {
        [options setMathRenderingPolicy:OMDMathRenderingPolicyFromInteger([mathPolicyValue integerValue])];
    } else {
        [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
    }
    id allowRemoteImages = [defaults objectForKey:OMDAllowRemoteImagesDefaultsKey];
    if ([allowRemoteImages respondsToSelector:@selector(boolValue)]) {
        [options setAllowRemoteImages:[allowRemoteImages boolValue]];
    }
    BOOL rendererSyntaxHighlightingEnabled = YES;
    id rendererSyntaxHighlighting = [defaults objectForKey:OMDRendererSyntaxHighlightingDefaultsKey];
    if ([rendererSyntaxHighlighting respondsToSelector:@selector(boolValue)]) {
        rendererSyntaxHighlightingEnabled = [rendererSyntaxHighlighting boolValue];
    }
    if (![OMMarkdownRenderer isTreeSitterAvailable]) {
        rendererSyntaxHighlightingEnabled = NO;
    }
    [options setCodeSyntaxHighlightingEnabled:rendererSyntaxHighlightingEnabled];
    [_renderer setParsingOptions:options];
    [self updateRendererParsingOptionsForSourcePath:nil];
    _lastRenderedLayoutWidth = -1.0;
    [_renderer setAsynchronousMathGenerationEnabled:YES];
    [_renderer setAllowTableHorizontalOverflow:YES];
    [_renderer setZoomScale:_zoomScale];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mathArtifactsDidWarm:)
                                                 name:OMMarkdownRendererMathArtifactsDidWarmNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(remoteImagesDidWarm:)
                                                 name:OMMarkdownRendererRemoteImagesDidWarmNotification
                                               object:nil];

    _viewerMode = OMDViewerModeFromInteger([[NSUserDefaults standardUserDefaults] integerForKey:@"ObjcMarkdownViewerMode"]);
    [self setViewerMode:_viewerMode persistPreference:NO];
    OMDStartupTrace(@"setupWindow: viewer mode applied");
    [self updateTabStrip];
    OMDStartupTrace(@"setupWindow: tab strip updated");
    OMDStartupTrace(@"setupWindow: complete");
    [self performSelector:@selector(logDelayedMenuSnapshot:)
               withObject:nil
               afterDelay:1.0];
}

- (void)showLaunchOverlayWithTitle:(NSString *)title detail:(NSString *)detail
{
    if (_launchOverlayView == nil || _launchOverlayTitleLabel == nil) {
        return;
    }

    NSString *resolvedTitle = ([title length] > 0 ? title : @"Loading...");
    [_launchOverlayTitleLabel setStringValue:resolvedTitle];

    NSString *resolvedDetail = OMDTrimmedString(detail);
    if ([resolvedDetail length] > 0 && _launchOverlayDetailLabel != nil) {
        [_launchOverlayDetailLabel setStringValue:resolvedDetail];
        [_launchOverlayDetailLabel setHidden:NO];
    } else if (_launchOverlayDetailLabel != nil) {
        [_launchOverlayDetailLabel setStringValue:@""];
        [_launchOverlayDetailLabel setHidden:YES];
    }

    [_documentContainer addSubview:_launchOverlayView
                        positioned:NSWindowAbove
                        relativeTo:nil];
    [_launchOverlayView setHidden:NO];
    [_launchOverlayView setNeedsDisplay:YES];
}

- (void)hideLaunchOverlay
{
    if (_launchOverlayView == nil) {
        return;
    }
    [_launchOverlayView setHidden:YES];
}

- (NSString *)firstLaunchDocumentPathFromArguments
{
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    if ([args count] <= 1) {
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger i = 1;
    for (; i < [args count]; i++) {
        NSString *candidate = [args objectAtIndex:i];
        NSString *expanded = [self resolvedAbsolutePathForLocalPath:candidate];
        if ([expanded length] == 0) {
            continue;
        }
        if ([fm fileExistsAtPath:expanded]) {
            return expanded;
        }
    }
    return nil;
}

- (BOOL)hasRecoverySnapshotAvailable
{
    NSString *snapshotPath = [self recoverySnapshotPath];
    if ([snapshotPath length] == 0) {
        return NO;
    }

    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:snapshotPath];
    NSString *markdown = [snapshot objectForKey:@"markdown"];
    return [markdown isKindOfClass:[NSString class]] && [markdown length] > 0;
}

- (void)performDeferredInitialLaunchWork
{
    _launchWorkScheduled = NO;

    BOOL openedFromArgs = NO;
    if ([_pendingLaunchOpenPath length] > 0) {
        NSString *pendingPath = [[_pendingLaunchOpenPath copy] autorelease];
        [_pendingLaunchOpenPath release];
        _pendingLaunchOpenPath = nil;
        openedFromArgs = [self openDocumentAtPath:pendingPath
                                         inNewTab:NO
                              requireDirtyConfirm:NO];
        OMDStartupTrace([NSString stringWithFormat:@"performDeferredInitialLaunchWork: pending open=%@",
                                                   openedFromArgs ? @"YES" : @"NO"]);
    } else {
        openedFromArgs = [self openDocumentFromArguments];
        OMDStartupTrace([NSString stringWithFormat:@"performDeferredInitialLaunchWork: openDocumentFromArguments=%@",
                                                   openedFromArgs ? @"YES" : @"NO"]);
    }

    if (!_openedFileOnLaunch && !openedFromArgs) {
        [self restoreRecoveryIfAvailable];
        OMDStartupTrace(@"performDeferredInitialLaunchWork: restoreRecoveryIfAvailable returned");
    }

    [self hideLaunchOverlay];
    [self schedulePostPresentationSetupIfNeeded];
}

- (void)schedulePostPresentationSetupIfNeeded
{
    if (_postPresentationSetupComplete || _postPresentationSetupScheduled) {
        return;
    }

    _postPresentationSetupScheduled = YES;
    [self performSelector:@selector(runDeferredPostPresentationSetup)
               withObject:nil
               afterDelay:0.0];
}

- (void)runDeferredPostPresentationSetup
{
    _postPresentationSetupScheduled = NO;
    if (_postPresentationSetupComplete) {
        return;
    }

    [self reloadExplorerEntries];
    OMDStartupTrace(@"runDeferredPostPresentationSetup: explorer reloaded");
    [self applyLayoutDensityPreference];
    OMDStartupTrace(@"runDeferredPostPresentationSetup: layout density applied");
    [self startExternalFileMonitor];
    OMDStartupTrace(@"runDeferredPostPresentationSetup: external file monitor started");
    _postPresentationSetupComplete = YES;
}

- (void)presentWindowIfNeeded
{
    if (_window == nil || [_window isVisible]) {
        return;
    }

    [_window makeKeyAndOrderFront:nil];
    [self normalizeWindowFrameIfNeeded];
    [_window makeKeyAndOrderFront:nil];
    OMDRefreshWindowsMainMenu();
    OMDApplyWindowsMenuToWindow(_window);
    OMDLogMenuSnapshot(@"presentWindowIfNeeded: after menu attach", [NSApp mainMenu], _window);
    [self applyExplorerSidebarVisibility];
    OMDStartupTrace(@"presentWindowIfNeeded: window visible");
}

- (void)logDelayedMenuSnapshot:(id)sender
{
    (void)sender;
    OMDLogMenuSnapshot(@"delayed menu snapshot", [NSApp mainMenu], _window);
}

- (void)setupWorkspaceChrome
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    NSRect contentBounds = [[_window contentView] bounds];
    CGFloat contentWidth = NSWidth(contentBounds);
    CGFloat contentHeight = NSHeight(contentBounds);
    if (contentWidth < 0.0) {
        contentWidth = 0.0;
    }
    if (contentHeight < 0.0) {
        contentHeight = 0.0;
    }
    CGFloat initialSidebarWidth = metrics.sidebarDefaultWidth;
    if (initialSidebarWidth > contentWidth) {
        initialSidebarWidth = contentWidth;
    }
    if (initialSidebarWidth < 0.0) {
        initialSidebarWidth = 0.0;
    }
    CGFloat initialMainWidth = contentWidth - initialSidebarWidth;
    if (initialMainWidth < 0.0) {
        initialMainWidth = 0.0;
    }

    _workspaceSplitView = [[OMDWin11SplitView alloc] initWithFrame:NSMakeRect(NSMinX(contentBounds),
                                                                               NSMinY(contentBounds),
                                                                               contentWidth,
                                                                               contentHeight)];
    [_workspaceSplitView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_workspaceSplitView setVertical:YES];
    [_workspaceSplitView setDelegate:self];

    _sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                 0.0,
                                                                 initialSidebarWidth,
                                                                 contentHeight)];
    [_sidebarContainer setAutoresizingMask:NSViewHeightSizable];

    _workspaceMainContainer = [[NSView alloc] initWithFrame:NSMakeRect(initialSidebarWidth,
                                                                       0.0,
                                                                       initialMainWidth,
                                                                       contentHeight)];
    [_workspaceMainContainer setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    [_workspaceSplitView addSubview:_sidebarContainer];
    [_workspaceSplitView addSubview:_workspaceMainContainer];
    [[_window contentView] addSubview:_workspaceSplitView];

    _tabStripView = [[NSView alloc] initWithFrame:NSZeroRect];
    [_tabStripView setAutoresizingMask:0];
    [_workspaceMainContainer addSubview:_tabStripView];

    _documentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    [_documentContainer setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_workspaceMainContainer addSubview:_documentContainer];

    _documentTabs = [[NSMutableArray alloc] init];
    _selectedDocumentTabIndex = -1;
    _currentDocumentRenderMode = OMDDocumentRenderModeMarkdown;
    _explorerEntries = [[NSMutableArray alloc] init];
    _explorerGitHubRepos = [[NSArray alloc] init];
    _explorerSourceMode = OMDExplorerSourceModeLocal;
    _explorerRequestToken = 0;
    _explorerIsLoading = NO;
    _explorerSidebarVisible = [self isExplorerSidebarVisiblePreference];
    _explorerSidebarLastVisibleWidth = metrics.sidebarDefaultWidth;

    [self layoutWorkspaceChrome];

    CGFloat totalWidth = NSWidth([_workspaceSplitView bounds]);
    CGFloat divider = [_workspaceSplitView dividerThickness];
    CGFloat available = totalWidth - divider;
    if (available > 1.0) {
        [_workspaceSplitView adjustSubviews];
    }
    CGFloat sidebarWidth = metrics.sidebarDefaultWidth;
    if (available > 0.0) {
        CGFloat minMainWidth = (metrics.scale > 1.05 ? 460.0 : 420.0);
        CGFloat maxSidebar = available - minMainWidth;
        if (maxSidebar < 220.0) {
            maxSidebar = available * 0.35;
        }
        if (sidebarWidth > maxSidebar) {
            sidebarWidth = maxSidebar;
        }
        if (sidebarWidth < 180.0) {
            sidebarWidth = MIN(220.0, available * 0.45);
        }
        if (sidebarWidth < 120.0) {
            sidebarWidth = available * 0.4;
        }
        if (sidebarWidth > 0.0) {
            [_workspaceSplitView setPosition:sidebarWidth ofDividerAtIndex:0];
        }
    }

    [self applyExplorerSidebarVisibility];
    [self setupExplorerSidebar];
}

- (void)layoutWorkspaceChrome
{
    if (_workspaceMainContainer == nil || _documentContainer == nil || _tabStripView == nil) {
        return;
    }

    NSRect bounds = [_workspaceMainContainer bounds];
    CGFloat tabHeight = [self currentTabStripHeight];
    if (tabHeight > NSHeight(bounds)) {
        tabHeight = NSHeight(bounds);
    }
    BOOL tabStripVisible = (tabHeight > 0.0);
    [_tabStripView setHidden:!tabStripVisible];
    if (tabStripVisible) {
        NSRect tabFrame = NSMakeRect(NSMinX(bounds),
                                     NSMaxY(bounds) - tabHeight,
                                     NSWidth(bounds),
                                     tabHeight);
        [_tabStripView setFrame:NSIntegralRect(tabFrame)];
    } else {
        [_tabStripView setFrame:NSZeroRect];
    }

    NSRect documentFrame = NSMakeRect(NSMinX(bounds),
                                      NSMinY(bounds),
                                      NSWidth(bounds),
                                      NSHeight(bounds) - tabHeight);
    if (documentFrame.size.height < 0.0) {
        documentFrame.size.height = 0.0;
    }
    [_documentContainer setFrame:NSIntegralRect(documentFrame)];
    [self layoutDocumentViews];
    [self updateTabStrip];
}

- (CGFloat)currentTabStripHeight
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    if (_documentTabs == nil) {
        return 0.0;
    }
    if ([_documentTabs count] <= 1) {
        return 0.0;
    }
    return metrics.tabStripHeight;
}

- (BOOL)isExplorerSidebarVisiblePreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:OMDExplorerSidebarVisibleDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return YES;
}

- (void)setExplorerSidebarVisiblePreference:(BOOL)visible
{
    [[NSUserDefaults standardUserDefaults] setBool:visible forKey:OMDExplorerSidebarVisibleDefaultsKey];
}

- (void)applyExplorerSidebarVisibility
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    if (_workspaceSplitView == nil || _sidebarContainer == nil) {
        return;
    }

    NSArray *subviews = [_workspaceSplitView subviews];
    if ([subviews count] < 2) {
        return;
    }

    NSView *sidebarView = [subviews objectAtIndex:0];
    if (_explorerSidebarVisible) {
        [_sidebarContainer setHidden:NO];

        CGFloat totalWidth = NSWidth([_workspaceSplitView bounds]);
        CGFloat divider = [_workspaceSplitView dividerThickness];
        CGFloat available = totalWidth - divider;
        if (available <= 1.0) {
            [self layoutWorkspaceChrome];
            return;
        }
        CGFloat target = _explorerSidebarLastVisibleWidth;
        if (target < 170.0) {
            target = metrics.sidebarDefaultWidth;
        }
        CGFloat minMain = (metrics.scale > 1.05 ? 400.0 : 360.0);
        CGFloat maxSidebar = available - minMain;
        if (maxSidebar < 170.0) {
            maxSidebar = available * 0.40;
        }
        if (target > maxSidebar) {
            target = maxSidebar;
        }
        if (target < 120.0) {
            target = MIN(220.0, available * 0.40);
        }
        if (target < 1.0) {
            target = metrics.sidebarDefaultWidth;
        }
        [_workspaceSplitView setPosition:target ofDividerAtIndex:0];
    } else {
        CGFloat currentWidth = NSWidth([sidebarView frame]);
        if (currentWidth > 20.0) {
            _explorerSidebarLastVisibleWidth = currentWidth;
        }
        [_workspaceSplitView setPosition:0.0 ofDividerAtIndex:0];
        [_sidebarContainer setHidden:YES];
    }

    [self layoutWorkspaceChrome];
}

- (void)toggleExplorerSidebar:(id)sender
{
    (void)sender;
    _explorerSidebarVisible = !_explorerSidebarVisible;
    [self setExplorerSidebarVisiblePreference:_explorerSidebarVisible];
    [self applyExplorerSidebarVisibility];
}

- (void)normalizeWindowFrameIfNeeded
{
    if (_window == nil) {
        return;
    }

    NSScreen *screen = [_window screen];
    if (screen == nil) {
        screen = [NSScreen mainScreen];
    }
    if (screen == nil) {
        return;
    }

    NSRect visible = [screen visibleFrame];
    if (visible.size.width <= 0.0 || visible.size.height <= 0.0) {
        return;
    }

    NSRect frame = [_window frame];
    BOOL outsideVisible = !NSIntersectsRect(frame, visible);
    BOOL tooWide = frame.size.width > visible.size.width;
    BOOL tooTall = frame.size.height > visible.size.height;
    NSRect overlap = NSIntersectionRect(frame, visible);
    CGFloat frameArea = frame.size.width * frame.size.height;
    CGFloat overlapArea = overlap.size.width * overlap.size.height;
    BOOL mostlyOutside = (frameArea > 0.0 && overlapArea < (frameArea * 0.50));
    BOOL centerOutside = !NSPointInRect(NSMakePoint(NSMidX(frame), NSMidY(frame)), visible);
    if (!outsideVisible && !tooWide && !tooTall && !mostlyOutside && !centerOutside) {
        return;
    }

    CGFloat width = frame.size.width;
    CGFloat height = frame.size.height;
    if (width > visible.size.width) {
        width = floor(visible.size.width * 0.92);
    }
    if (height > visible.size.height) {
        height = floor(visible.size.height * 0.92);
    }
    if (width < OMDMinimumUsableWindowWidth()) {
        width = MIN(OMDDefaultWindowWidth(), visible.size.width);
    }
    if (height < 520.0) {
        height = MIN(OMDDefaultWindowHeight(), visible.size.height);
    }

    CGFloat x = visible.origin.x + floor((visible.size.width - width) * 0.5);
    CGFloat y = visible.origin.y + floor((visible.size.height - height) * 0.5);
    NSRect normalized = NSIntegralRect(NSMakeRect(x, y, width, height));
    [_window setFrame:normalized display:NO];
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
    if ([identifier isEqualToString:@"PrimaryActions"]) {
        CGFloat fileActionsWidth = OMDToolbarActionSegmentWidth * 3.0;
        CGFloat utilityActionsWidth = OMDToolbarActionSegmentWidth * 3.0;
        CGFloat containerWidth = fileActionsWidth + OMDToolbarActionGroupSpacing + utilityActionsWidth;
        if (_toolbarPrimaryActionsContainer == nil) {
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            _toolbarPrimaryActionsContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, containerWidth, OMDToolbarItemHeight)];

            _toolbarFileActionsControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, controlY, fileActionsWidth, OMDToolbarControlHeight)];
            [_toolbarFileActionsControl setSegmentCount:3];
            [_toolbarFileActionsControl setSegmentStyle:NSSegmentStyleRounded];
            [[_toolbarFileActionsControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
            [_toolbarFileActionsControl setTarget:self];
            [_toolbarFileActionsControl setAction:@selector(toolbarActionControlChanged:)];
            [_toolbarFileActionsControl setTag:1];
            [_toolbarFileActionsControl setImage:(OMDToolbarThemedImageNamed(@"toolbar-explorer-toggle.png") ?: [NSImage imageNamed:@"NSMenuOnStateTemplate"]) forSegment:0];
            [_toolbarFileActionsControl setImage:(OMDToolbarThemedImageNamed(@"toolbar-open.png") ?: OMDToolbarImageNamed(@"open-icon.png")) forSegment:1];
            [_toolbarFileActionsControl setImage:(OMDToolbarThemedImageNamed(@"toolbar-saveas.png") ?: [NSImage imageNamed:@"NSSave"]) forSegment:2];
            [[_toolbarFileActionsControl cell] setToolTip:@"Show or hide the file explorer" forSegment:0];
            [[_toolbarFileActionsControl cell] setToolTip:@"Open a Markdown file" forSegment:1];
            [[_toolbarFileActionsControl cell] setToolTip:@"Save current markdown changes" forSegment:2];
            [_toolbarFileActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:0];
            [_toolbarFileActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:1];
            [_toolbarFileActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:2];
            [_toolbarPrimaryActionsContainer addSubview:_toolbarFileActionsControl];

            _toolbarUtilityActionsControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(fileActionsWidth + OMDToolbarActionGroupSpacing,
                                                                                                 controlY,
                                                                                                 utilityActionsWidth,
                                                                                                 OMDToolbarControlHeight)];
            [_toolbarUtilityActionsControl setSegmentCount:3];
            [_toolbarUtilityActionsControl setSegmentStyle:NSSegmentStyleRounded];
            [[_toolbarUtilityActionsControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
            [_toolbarUtilityActionsControl setTarget:self];
            [_toolbarUtilityActionsControl setAction:@selector(toolbarActionControlChanged:)];
            [_toolbarUtilityActionsControl setTag:2];
            [_toolbarUtilityActionsControl setImage:(OMDToolbarThemedImageNamed(@"toolbar-export.png") ?: [NSImage imageNamed:@"NSSave"]) forSegment:0];
            [_toolbarUtilityActionsControl setImage:(OMDToolbarThemedImageNamed(@"toolbar-print.png") ?: [NSImage imageNamed:@"NSPrint"]) forSegment:1];
            [_toolbarUtilityActionsControl setImage:(OMDToolbarThemedImageNamed(@"toolbar-preferences.png")
                                                    ?: [NSImage imageNamed:@"NSPreferencesGeneral"]
                                                    ?: [NSImage imageNamed:@"preferences"]) forSegment:2];
            [[_toolbarUtilityActionsControl cell] setToolTip:@"Export the current document as PDF" forSegment:0];
            [[_toolbarUtilityActionsControl cell] setToolTip:@"Print the current document" forSegment:1];
            [[_toolbarUtilityActionsControl cell] setToolTip:@"Open Preferences" forSegment:2];
            [_toolbarUtilityActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:0];
            [_toolbarUtilityActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:1];
            [_toolbarUtilityActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:2];
            [_toolbarPrimaryActionsContainer addSubview:_toolbarUtilityActionsControl];

            [self updateToolbarActionControlsState];
        }

        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"PrimaryActions"] autorelease];
        [item setView:_toolbarPrimaryActionsContainer];
        [item setMinSize:NSMakeSize(containerWidth, OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(containerWidth, OMDToolbarItemHeight)];
        [item setLabel:@""];
        [item setPaletteLabel:@"Actions"];
        [item setToolTip:@"Common document and workspace actions"];
        return item;
    }

    if ([identifier isEqualToString:@"ToggleExplorer"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ToggleExplorer"] autorelease];
        [item setLabel:@"Explorer"];
        [item setPaletteLabel:@"Explorer"];
        [item setToolTip:@"Show or hide the file explorer"];
        [item setTarget:self];
        [item setAction:@selector(toggleExplorerSidebar:)];
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-explorer-toggle.png");
        if (image == nil) {
            image = [NSImage imageNamed:@"NSMenuOnStateTemplate"];
        }
        OMDSetToolbarItemImage(item, image);
        return item;
    }

    if ([identifier isEqualToString:@"OpenDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"OpenDocument"] autorelease];
        [item setLabel:@"Open"];
        [item setPaletteLabel:@"Open"];
        [item setToolTip:@"Open a Markdown file"];
        [item setTarget:self];
        [item setAction:@selector(openDocument:)];
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-open.png");
        if (image == nil) {
            image = OMDToolbarImageNamed(@"open-icon.png");
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"NSOpen"];
        }
        OMDSetToolbarItemImage(item, image);
        return item;
    }

    if ([identifier isEqualToString:@"SaveDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"SaveDocument"] autorelease];
        [item setLabel:@"Save"];
        [item setPaletteLabel:@"Save"];
        [item setToolTip:@"Save current markdown changes"];
        [item setTarget:self];
        [item setAction:@selector(saveDocument:)];
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-saveas.png");
        if (image == nil) {
            image = OMDToolbarImageNamed(@"open-icon.png");
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"NSSave"];
        }
        OMDSetToolbarItemImage(item, image);
        return item;
    }

    if ([identifier isEqualToString:@"Preferences"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Preferences"] autorelease];
        [item setLabel:@"Prefs"];
        [item setPaletteLabel:@"Preferences"];
        [item setToolTip:@"Open Preferences"];
        [item setTarget:self];
        [item setAction:@selector(showPreferences:)];
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-preferences.png");
        if (image == nil) {
            image = [NSImage imageNamed:@"NSPreferencesGeneral"];
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"preferences"];
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"NSAdvanced"];
        }
        OMDSetToolbarItemImage(item, image);
        return item;
    }

    if ([identifier isEqualToString:@"PrintDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"PrintDocument"] autorelease];
        [item setLabel:@"Print"];
        [item setPaletteLabel:@"Print"];
        [item setToolTip:@"Print the current document"];
        [item setTarget:self];
        [item setAction:@selector(printDocument:)];
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-print.png");
        if (image == nil) {
            image = [NSImage imageNamed:@"NSPrint"];
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"common_Printer.tiff"];
        }
        OMDSetToolbarItemImage(item, image);
        return item;
    }

    if ([identifier isEqualToString:@"ExportDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ExportDocument"] autorelease];
        [item setLabel:@"Export PDF"];
        [item setPaletteLabel:@"Export PDF"];
        [item setToolTip:@"Export the current document as PDF (more formats in File > Export)"];
        [item setTarget:self];
        [item setAction:@selector(exportDocumentAsPDF:)];
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-export.png");
        if (image == nil) {
            image = [NSImage imageNamed:@"NSSave"];
        }
        OMDSetToolbarItemImage(item, image);
        return item;
    }

    if ([identifier isEqualToString:@"ModeControls"]) {
        if (_modeContainer == nil) {
            CGFloat labelY = floor((OMDToolbarItemHeight - OMDToolbarLabelHeight) * 0.5);
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            _modeContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 356, OMDToolbarItemHeight)];
            _modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, labelY, 32, OMDToolbarLabelHeight)];
            [_modeLabel setBezeled:NO];
            [_modeLabel setEditable:NO];
            [_modeLabel setSelectable:NO];
            [_modeLabel setDrawsBackground:NO];
            [_modeLabel setAlignment:NSRightTextAlignment];
            [_modeLabel setFont:[NSFont boldSystemFontOfSize:11.0]];
            [_modeLabel setTextColor:[self modeLabelTextColor]];
            [_modeLabel setStringValue:@"View"];
            [_modeContainer addSubview:_modeLabel];

            _modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(36, controlY, 182, OMDToolbarControlHeight)];
            [_modeControl setSegmentCount:3];
            [_modeControl setLabel:@"Read" forSegment:0];
            [_modeControl setLabel:@"Edit" forSegment:1];
            [_modeControl setLabel:@"Split" forSegment:2];
            [_modeControl setTarget:self];
            [_modeControl setAction:@selector(modeControlChanged:)];
            [_modeContainer addSubview:_modeControl];

            _previewStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(224, labelY, 132, OMDToolbarLabelHeight)];
            [_previewStatusLabel setBezeled:NO];
            [_previewStatusLabel setEditable:NO];
            [_previewStatusLabel setSelectable:NO];
            [_previewStatusLabel setDrawsBackground:NO];
            [_previewStatusLabel setAlignment:NSLeftTextAlignment];
            [_previewStatusLabel setFont:[NSFont boldSystemFontOfSize:11.0]];
            [_previewStatusLabel setStringValue:@""];
            [_previewStatusLabel setHidden:YES];
            [_modeContainer addSubview:_previewStatusLabel];

            [self updateModeControlSelection];
            [self updatePreviewStatusIndicator];
        }
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ModeControls"] autorelease];
        [item setView:_modeContainer];
        [item setMinSize:NSMakeSize(356, OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(356, OMDToolbarItemHeight)];
        [item setLabel:@""];
        [item setPaletteLabel:@"View"];
        [item setToolTip:@"Switch view mode and monitor preview state"];
        return item;
    }

    if ([identifier isEqualToString:@"ZoomControls"]) {
        if (_zoomContainer == nil) {
            CGFloat labelY = floor((OMDToolbarItemHeight - OMDToolbarLabelHeight) * 0.5);
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            _zoomContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, OMDToolbarItemHeight)];

            _zoomLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, labelY, 55, OMDToolbarLabelHeight)];
            [_zoomLabel setBezeled:NO];
            [_zoomLabel setEditable:NO];
            [_zoomLabel setSelectable:NO];
            [_zoomLabel setDrawsBackground:NO];
            [_zoomLabel setAlignment:NSRightTextAlignment];
            [_zoomLabel setFont:[NSFont boldSystemFontOfSize:11.0]];

            _zoomSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(60, controlY, 130, OMDToolbarControlHeight)];
            [_zoomSlider setMinValue:50];
            [_zoomSlider setMaxValue:200];
            [_zoomSlider setDoubleValue:_zoomScale * 100.0];
            [_zoomSlider setTarget:self];
            [_zoomSlider setAction:@selector(zoomSliderChanged:)];

            _zoomResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(205, controlY, 90, OMDToolbarControlHeight)];
            [_zoomResetButton setTitle:@"100%"];
            [_zoomResetButton setBezelStyle:NSRoundedBezelStyle];
            [_zoomResetButton setFont:[NSFont systemFontOfSize:11.0]];
            [_zoomResetButton setTarget:self];
            [_zoomResetButton setAction:@selector(zoomReset:)];
            [_zoomResetButton setToolTip:@"Reset zoom to 100%"];

            [_zoomContainer addSubview:_zoomLabel];
            [_zoomContainer addSubview:_zoomSlider];
            [_zoomContainer addSubview:_zoomResetButton];
            [self updateZoomLabel];
        }

        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ZoomControls"] autorelease];
        [item setView:_zoomContainer];
        [item setMinSize:NSMakeSize(300, OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(300, OMDToolbarItemHeight)];
        return item;
    }

    return nil;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    NSMutableArray *identifiers = [NSMutableArray arrayWithObjects:
        @"PrimaryActions",
        nil];
    [identifiers addObject:@"ModeControls"];
    if (OMDShouldUseToolbarFlexibleSpace()) {
        [identifiers addObject:NSToolbarFlexibleSpaceItemIdentifier];
    }
    [identifiers addObject:@"ZoomControls"];
    return identifiers;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (void)updateZoomLabel
{
    if (_zoomLabel == nil) {
        return;
    }
    NSInteger percent = (NSInteger)lrint(_zoomScale * 100.0);
    [_zoomLabel setStringValue:[NSString stringWithFormat:@"%ld%%", (long)percent]];
}

- (void)toolbarActionControlChanged:(id)sender
{
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = [control selectedSegment];
    if (segment < 0) {
        return;
    }

    if (control == _toolbarFileActionsControl) {
        switch (segment) {
            case 0:
                [self toggleExplorerSidebar:control];
                break;
            case 1:
                [self openDocument:control];
                break;
            case 2:
                [self saveDocument:control];
                break;
            default:
                break;
        }
    } else if (control == _toolbarUtilityActionsControl) {
        switch (segment) {
            case 0:
                [self exportDocumentAsPDF:control];
                break;
            case 1:
                [self printDocument:control];
                break;
            case 2:
                [self showPreferences:control];
                break;
            default:
                break;
        }
    }

    [control setSelectedSegment:-1];
    [self updateToolbarActionControlsState];
}

- (BOOL)canSaveCurrentDocument
{
    return ([self hasLoadedDocument] && _sourceIsDirty);
}

- (void)updateToolbarActionControlsState
{
    BOOL hasDocument = [self hasLoadedDocument];
    BOOL canSaveDocument = [self canSaveCurrentDocument];
    NSColor *activeIconTint = OMDResolvedControlTextColor();
    NSColor *disabledIconTint = OMDResolvedMutedTextColor();
    if (_toolbarFileActionsControl != nil) {
        NSImage *saveBaseImage = (OMDImageNamed(@"toolbar-saveas.png") ?: [NSImage imageNamed:@"NSSave"]);
        [_toolbarFileActionsControl setImage:OMDToolbarTintedImage(saveBaseImage,
                                                                   (canSaveDocument ? activeIconTint : disabledIconTint))
                                  forSegment:2];
        [_toolbarFileActionsControl setEnabled:YES forSegment:0];
        [_toolbarFileActionsControl setEnabled:YES forSegment:1];
        [_toolbarFileActionsControl setEnabled:canSaveDocument forSegment:2];
        [[_toolbarFileActionsControl cell] setToolTip:(_explorerSidebarVisible
                                                        ? @"Hide the file explorer"
                                                        : @"Show the file explorer")
                                           forSegment:0];
        [[_toolbarFileActionsControl cell] setToolTip:(canSaveDocument
                                                       ? @"Save current markdown changes"
                                                       : @"No unsaved changes to save")
                                           forSegment:2];
    }
    if (_toolbarUtilityActionsControl != nil) {
        NSImage *exportBaseImage = (OMDImageNamed(@"toolbar-export.png") ?: [NSImage imageNamed:@"NSSave"]);
        NSImage *printBaseImage = (OMDImageNamed(@"toolbar-print.png") ?: [NSImage imageNamed:@"NSPrint"]);
        [_toolbarUtilityActionsControl setImage:OMDToolbarTintedImage(exportBaseImage,
                                                                      (hasDocument ? activeIconTint : disabledIconTint))
                                     forSegment:0];
        [_toolbarUtilityActionsControl setImage:OMDToolbarTintedImage(printBaseImage,
                                                                      (hasDocument ? activeIconTint : disabledIconTint))
                                     forSegment:1];
        [_toolbarUtilityActionsControl setEnabled:hasDocument forSegment:0];
        [_toolbarUtilityActionsControl setEnabled:hasDocument forSegment:1];
        [_toolbarUtilityActionsControl setEnabled:YES forSegment:2];
    }
}

- (void)zoomSliderChanged:(id)sender
{
    _zoomScale = [_zoomSlider doubleValue] / 100.0;
    [[NSUserDefaults standardUserDefaults] setDouble:_zoomScale forKey:@"ObjcMarkdownZoomScale"];
    [self updateZoomLabel];
    _lastZoomSliderEventTime = OMDNow();
    if (_zoomUsesDebouncedRendering) {
        [self requestInteractiveRender];
        return;
    }
    [self cancelPendingInteractiveRender];
    [self renderCurrentMarkdown];
}

- (void)zoomReset:(id)sender
{
    _zoomScale = 1.0;
    [[NSUserDefaults standardUserDefaults] setDouble:_zoomScale forKey:@"ObjcMarkdownZoomScale"];
    [_zoomSlider setDoubleValue:100.0];
    [self updateZoomLabel];
    _lastZoomSliderEventTime = OMDNow();
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

    if (action == @selector(setSplitSyncModeUnlinked:) ||
        action == @selector(setSplitSyncModeLinkedScrolling:) ||
        action == @selector(setSplitSyncModeCaretSelectionFollow:)) {
        OMDSplitSyncMode mode = [self currentSplitSyncMode];
        OMDSplitSyncMode modeForAction = OMDSplitSyncModeLinkedScrolling;
        if (action == @selector(setSplitSyncModeUnlinked:)) {
            modeForAction = OMDSplitSyncModeUnlinked;
        } else if (action == @selector(setSplitSyncModeCaretSelectionFollow:)) {
            modeForAction = OMDSplitSyncModeCaretSelectionFollow;
        }
        [menuItem setState:(mode == modeForAction ? NSOnState : NSOffState)];
        return YES;
    }

    if (action == @selector(toggleExplorerSidebar:)) {
        [menuItem setState:(_explorerSidebarVisible ? NSOnState : NSOffState)];
        return YES;
    }

    if (action == @selector(undo:)) {
        NSTextView *textView = [self activeEditingTextView];
        NSUndoManager *undoManager = (textView != nil ? [textView undoManager] : nil);
        return undoManager != nil && [undoManager canUndo];
    }

    if (action == @selector(redo:)) {
        NSTextView *textView = [self activeEditingTextView];
        NSUndoManager *undoManager = (textView != nil ? [textView undoManager] : nil);
        return undoManager != nil && [undoManager canRedo];
    }

    if (action == @selector(chooseSourceEditorFont:) ||
        action == @selector(increaseSourceEditorFontSize:) ||
        action == @selector(decreaseSourceEditorFontSize:) ||
        action == @selector(resetSourceEditorFontSize:)) {
        return _sourceTextView != nil;
    }

    if (action == @selector(setMathRenderingDisabled:) ||
        action == @selector(setMathRenderingStyledText:) ||
        action == @selector(setMathRenderingExternalTools:)) {
        OMMarkdownMathRenderingPolicy policy = [self currentMathRenderingPolicy];
        OMMarkdownMathRenderingPolicy itemPolicy = OMMarkdownMathRenderingPolicyStyledText;
        if (action == @selector(setMathRenderingDisabled:)) {
            itemPolicy = OMMarkdownMathRenderingPolicyDisabled;
        } else if (action == @selector(setMathRenderingExternalTools:)) {
            itemPolicy = OMMarkdownMathRenderingPolicyExternalTools;
        }
        [menuItem setState:(policy == itemPolicy ? NSOnState : NSOffState)];
        return _renderer != nil;
    }

    if (action == @selector(toggleAllowRemoteImages:)) {
        [menuItem setState:([self isAllowRemoteImagesEnabled] ? NSOnState : NSOffState)];
        return _renderer != nil;
    }

    if (action == @selector(toggleWordSelectionModifierShim:)) {
        [menuItem setState:([self isWordSelectionModifierShimEnabled] ? NSOnState : NSOffState)];
        return YES;
    }

    if (action == @selector(toggleSourceVimKeyBindings:)) {
        [menuItem setState:([self isSourceVimKeyBindingsEnabled] ? NSOnState : NSOffState)];
        return _sourceTextView != nil;
    }

    if (action == @selector(toggleFormattingBar:)) {
        [menuItem setState:([self isFormattingBarEnabledPreference] ? NSOnState : NSOffState)];
        return YES;
    }

    if (action == @selector(toggleSourceSyntaxHighlighting:)) {
        [menuItem setState:([self isSourceSyntaxHighlightingEnabled] ? NSOnState : NSOffState)];
        return _sourceTextView != nil;
    }

    if (action == @selector(toggleSourceHighlightHighContrast:)) {
        [menuItem setState:([self isSourceHighlightHighContrastEnabled] ? NSOnState : NSOffState)];
        return _sourceTextView != nil && [self isSourceSyntaxHighlightingEnabled];
    }

    if (action == @selector(toggleRendererSyntaxHighlighting:)) {
        [menuItem setState:([self isRendererSyntaxHighlightingEnabled] ? NSOnState : NSOffState)];
        return _renderer != nil && [self isTreeSitterAvailable];
    }

    if (action == @selector(saveDocument:) ||
        action == @selector(reloadDocumentFromDisk:) ||
        action == @selector(saveDocumentAsMarkdown:) ||
        action == @selector(printDocument:) ||
        action == @selector(exportDocumentAsPDF:) ||
        action == @selector(exportDocumentAsRTF:) ||
        action == @selector(exportDocumentAsDOCX:) ||
        action == @selector(exportDocumentAsODT:) ||
        action == @selector(exportDocumentAsHTML:)) {
        if (action == @selector(saveDocument:)) {
            return [self canSaveCurrentDocument];
        }
        if (action == @selector(reloadDocumentFromDisk:)) {
            [self refreshCurrentDocumentDiskStateAllowPrompt:NO];
            return [self currentDocumentHasNewerDiskVersion];
        }
        return [self hasLoadedDocument];
    }
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem
{
    NSString *identifier = [toolbarItem itemIdentifier];
    if ([identifier isEqualToString:@"ToggleExplorer"]) {
        [toolbarItem setToolTip:(_explorerSidebarVisible
                                 ? @"Hide the file explorer"
                                 : @"Show the file explorer")];
        return YES;
    }
    if ([identifier isEqualToString:@"SaveDocument"] ||
        [identifier isEqualToString:@"PrintDocument"] ||
        [identifier isEqualToString:@"ExportDocument"]) {
        if ([identifier isEqualToString:@"SaveDocument"]) {
            return [self canSaveCurrentDocument];
        }
        return [self hasLoadedDocument];
    }
    return YES;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu == _fileOpenRecentMenu) {
        [self rebuildOpenRecentMenu];
    }
}

- (void)rebuildOpenRecentMenu
{
    if (_fileOpenRecentMenu == nil) {
        return;
    }

    while ([_fileOpenRecentMenu numberOfItems] > 0) {
        [_fileOpenRecentMenu removeItemAtIndex:0];
    }

    NSArray *recentURLs = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
    NSUInteger addedCount = 0;
    NSUInteger index = 0;
    for (; index < [recentURLs count]; index++) {
        NSURL *url = [recentURLs objectAtIndex:index];
        if (url == nil || ![url isFileURL]) {
            continue;
        }

        NSString *path = [url path];
        if (path == nil || [path length] == 0) {
            continue;
        }

        NSString *title = [path lastPathComponent];
        if (title == nil || [title length] == 0) {
            title = path;
        }

        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                        action:@selector(openRecentDocumentFromMenuItem:)
                                                 keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setRepresentedObject:path];
        if ([item respondsToSelector:@selector(setToolTip:)]) {
            [item setToolTip:path];
        }
        [_fileOpenRecentMenu addItem:item];
        addedCount += 1;
    }

    if (addedCount == 0) {
        NSMenuItem *empty = [[[NSMenuItem alloc] initWithTitle:@"No Recent Documents"
                                                         action:NULL
                                                  keyEquivalent:@""] autorelease];
        [empty setEnabled:NO];
        [_fileOpenRecentMenu addItem:empty];
        return;
    }

    [_fileOpenRecentMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clearItem = [[[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                                         action:@selector(clearRecentDocumentsMenu:)
                                                  keyEquivalent:@""] autorelease];
    [clearItem setTarget:self];
    [_fileOpenRecentMenu addItem:clearItem];
}

- (void)noteRecentDocumentAtPathIfAvailable:(NSString *)path
{
    NSString *trimmedPath = OMDTrimmedString(path);
    if ([trimmedPath length] == 0) {
        return;
    }

    NSString *resolvedPath = [trimmedPath stringByExpandingTildeInPath];
    if (![resolvedPath isAbsolutePath]) {
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        resolvedPath = [cwd stringByAppendingPathComponent:resolvedPath];
    }

    NSURL *url = [NSURL fileURLWithPath:resolvedPath];
    if (url != nil) {
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];
    }
}

- (void)openRecentDocumentFromMenuItem:(id)sender
{
    NSString *path = nil;
    if ([sender respondsToSelector:@selector(representedObject)]) {
        id represented = [sender representedObject];
        if ([represented isKindOfClass:[NSString class]]) {
            path = (NSString *)represented;
        }
    }

    if (path == nil || [path length] == 0) {
        return;
    }

    BOOL openInNewTab = !([_documentTabs count] == 0 && _currentPath == nil && _currentMarkdown == nil);
    [self openDocumentAtPath:path inNewTab:openInNewTab requireDirtyConfirm:!openInNewTab];
}

- (void)clearRecentDocumentsMenu:(id)sender
{
    [[NSDocumentController sharedDocumentController] clearRecentDocuments:sender];
    [self rebuildOpenRecentMenu];
}

- (void)newWindow:(id)sender
{
    (void)sender;

    OMDAppDelegate *controller = [[OMDAppDelegate alloc] init];
    [controller setupWindow];
    [controller presentWindowIfNeeded];
    [controller schedulePostPresentationSetupIfNeeded];
    [controller registerAsSecondaryWindow];
    [controller release];
}

- (void)openDocument:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setTitle:@"Open Document"];
    [panel setPrompt:@"Open"];
    [panel setAllowedFileTypes:nil];
    if ([panel respondsToSelector:@selector(setAllowsOtherFileTypes:)]) {
        [panel setAllowsOtherFileTypes:YES];
    }
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

    NSArray *filenames = OMDSelectedPathsFromOpenPanel(panel);
    if ([filenames count] == 0) {
        return;
    }

    NSString *path = [filenames objectAtIndex:0];
    BOOL openInNewTab = !([_documentTabs count] == 0 && _currentPath == nil && _currentMarkdown == nil);
    [self openDocumentAtPath:path inNewTab:openInNewTab requireDirtyConfirm:!openInNewTab];
}

- (void)importDocument:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setTitle:@"Import"];
    [panel setPrompt:@"Import"];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"html", @"htm", @"rtf", @"docx", @"odt", nil]];

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

    NSArray *filenames = OMDSelectedPathsFromOpenPanel(panel);
    if ([filenames count] == 0) {
        return;
    }

    NSString *path = [filenames objectAtIndex:0];
    NSString *extension = [[path pathExtension] lowercaseString];
    BOOL supportsFormatNow = [OMDDocumentConverter isSupportedExtension:extension];

    if ([_documentTabs count] == 0 && _currentPath == nil && _currentMarkdown == nil) {
        [self importDocumentAtPath:path];
    } else if (supportsFormatNow) {
        OMDAppDelegate *controller = [[OMDAppDelegate alloc] init];
        [controller setupWindow];
        BOOL imported = [controller importDocumentAtPath:path];
        if (imported) {
            [controller schedulePostPresentationSetupIfNeeded];
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

- (NSString *)resolvedAbsolutePathForLocalPath:(NSString *)path
{
    NSString *trimmed = OMDNormalizedExternalLocalPath(path);
    if ([trimmed length] == 0) {
        return nil;
    }

    NSString *resolvedPath = [trimmed stringByExpandingTildeInPath];
    if (![resolvedPath isAbsolutePath] && !OMDLooksLikeWindowsAbsolutePath(resolvedPath)) {
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        resolvedPath = [cwd stringByAppendingPathComponent:resolvedPath];
    }
    return [resolvedPath stringByStandardizingPath];
}

- (NSString *)diskFingerprintForPath:(NSString *)path
{
    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:path];
    if ([resolvedPath length] == 0) {
        return nil;
    }

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:resolvedPath error:NULL];
    return OMDDiskFingerprintForFileAttributes(attributes);
}

- (BOOL)isCurrentDocumentReloadableFromDisk
{
    if (![self hasLoadedDocument]) {
        return NO;
    }
    if ([OMDTrimmedString(_currentPath) length] == 0) {
        return NO;
    }
    if (_selectedDocumentTabIndex >= 0 && _selectedDocumentTabIndex < (NSInteger)[_documentTabs count]) {
        NSDictionary *tab = [_documentTabs objectAtIndex:_selectedDocumentTabIndex];
        if ([[tab objectForKey:OMDTabIsGitHubKey] boolValue]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)currentDocumentHasNewerDiskVersion
{
    if (![self isCurrentDocumentReloadableFromDisk]) {
        return NO;
    }
    if ([_currentLoadedDiskFingerprint length] == 0 || [_currentObservedDiskFingerprint length] == 0) {
        return NO;
    }
    return ![_currentLoadedDiskFingerprint isEqualToString:_currentObservedDiskFingerprint];
}

- (void)setCurrentDiskFingerprintStateLoaded:(NSString *)loaded
                                    observed:(NSString *)observed
                                  suppressed:(NSString *)suppressed
{
    NSString *normalizedLoaded = ([loaded length] > 0 ? loaded : nil);
    NSString *normalizedObserved = ([observed length] > 0 ? observed : nil);
    NSString *normalizedSuppressed = ([suppressed length] > 0 ? suppressed : nil);

    if (_currentLoadedDiskFingerprint != normalizedLoaded &&
        ![_currentLoadedDiskFingerprint isEqualToString:normalizedLoaded]) {
        [_currentLoadedDiskFingerprint release];
        _currentLoadedDiskFingerprint = [normalizedLoaded copy];
    }
    if (_currentObservedDiskFingerprint != normalizedObserved &&
        ![_currentObservedDiskFingerprint isEqualToString:normalizedObserved]) {
        [_currentObservedDiskFingerprint release];
        _currentObservedDiskFingerprint = [normalizedObserved copy];
    }
    if (_currentSuppressedDiskFingerprint != normalizedSuppressed &&
        ![_currentSuppressedDiskFingerprint isEqualToString:normalizedSuppressed]) {
        [_currentSuppressedDiskFingerprint release];
        _currentSuppressedDiskFingerprint = [normalizedSuppressed copy];
    }
}

- (void)startExternalFileMonitor
{
    if (_externalFileMonitorTimer != nil) {
        return;
    }

    _externalFileMonitorTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDExternalFileMonitorInterval
                                                                  target:self
                                                                selector:@selector(externalFileMonitorTimerFired:)
                                                                userInfo:nil
                                                                 repeats:YES] retain];
}

- (void)stopExternalFileMonitor
{
    if (_externalFileMonitorTimer != nil) {
        [_externalFileMonitorTimer invalidate];
        [_externalFileMonitorTimer release];
        _externalFileMonitorTimer = nil;
    }
}

- (void)externalFileMonitorTimerFired:(NSTimer *)timer
{
    if (timer != _externalFileMonitorTimer) {
        return;
    }
    [self refreshCurrentDocumentDiskStateAllowPrompt:YES];
}

- (BOOL)loadDocumentContentsAtPath:(NSString *)path
                        actionName:(NSString *)actionName
                          markdown:(NSString **)markdownOut
                      displayTitle:(NSString **)displayTitleOut
                        renderMode:(OMDDocumentRenderMode *)renderModeOut
                    syntaxLanguage:(NSString **)syntaxLanguageOut
                       fingerprint:(NSString **)fingerprintOut
{
    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:path];
    if ([resolvedPath length] == 0) {
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:resolvedPath error:NULL];
    if (attributes == nil) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:[NSString stringWithFormat:@"%@ failed", actionName]];
        [alert setInformativeText:@"The file is no longer available on disk."];
        [alert runModal];
        return NO;
    }

    NSNumber *sizeValue = [attributes objectForKey:NSFileSize];
    if ([sizeValue respondsToSelector:@selector(unsignedLongLongValue)]) {
        if (![self ensureOpenFileSizeWithinLimit:[sizeValue unsignedLongLongValue]
                                      descriptor:[resolvedPath lastPathComponent]]) {
            return NO;
        }
    }

    NSString *extension = [[resolvedPath pathExtension] lowercaseString];
    BOOL importable = [OMDDocumentConverter isSupportedExtension:extension];
    NSString *markdown = nil;
    OMDDocumentRenderMode renderMode = OMDDocumentRenderModeMarkdown;
    NSString *syntaxLanguage = nil;

    if (importable) {
        if (![self ensureConverterAvailableForActionName:actionName]) {
            return NO;
        }

        NSError *conversionError = nil;
        BOOL converted = [[self documentConverter] importFileAtPath:resolvedPath
                                                           markdown:&markdown
                                                              error:&conversionError];
        if (!converted) {
            [self presentConverterError:conversionError
                          fallbackTitle:[NSString stringWithFormat:@"%@ failed", actionName]];
            return NO;
        }
    } else {
        NSError *readError = nil;
        markdown = [self decodedTextForFileAtPath:resolvedPath error:&readError];
        if (markdown == nil) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            NSString *messageText = [actionName isEqualToString:@"Open"]
                                    ? @"Unsupported file type"
                                    : [NSString stringWithFormat:@"%@ failed", actionName];
            [alert setMessageText:messageText];
            [alert setInformativeText:(readError != nil ? [readError localizedDescription]
                                                        : @"This file cannot be opened as text.")];
            [alert runModal];
            return NO;
        }

        renderMode = [self isMarkdownTextPath:resolvedPath]
                     ? OMDDocumentRenderModeMarkdown
                     : OMDDocumentRenderModeVerbatim;
        if (renderMode == OMDDocumentRenderModeVerbatim) {
            syntaxLanguage = OMDVerbatimSyntaxTokenForExtension(extension);
        }
    }

    if (markdownOut != NULL) {
        *markdownOut = markdown;
    }
    if (displayTitleOut != NULL) {
        *displayTitleOut = [resolvedPath lastPathComponent];
    }
    if (renderModeOut != NULL) {
        *renderModeOut = renderMode;
    }
    if (syntaxLanguageOut != NULL) {
        *syntaxLanguageOut = syntaxLanguage;
    }
    if (fingerprintOut != NULL) {
        *fingerprintOut = OMDDiskFingerprintForFileAttributes(attributes);
    }
    return YES;
}

- (void)setCurrentDocumentText:(NSString *)text
                    sourcePath:(NSString *)sourcePath
                    renderMode:(OMDDocumentRenderMode)renderMode
                syntaxLanguage:(NSString *)syntaxLanguage
{
    NSString *newText = text != nil ? [text copy] : nil;
    NSString *newSourcePath = sourcePath != nil ? [sourcePath copy] : nil;
    NSString *normalizedSyntax = OMDTrimmedString(syntaxLanguage);
    NSString *newSyntax = ([normalizedSyntax length] > 0 ? [normalizedSyntax copy] : nil);

    [_currentMarkdown release];
    _currentMarkdown = newText;
    [_currentPath release];
    _currentPath = newSourcePath;
    [_currentDocumentSyntaxLanguage release];
    _currentDocumentSyntaxLanguage = newSyntax;
    _currentDocumentRenderMode = (renderMode == OMDDocumentRenderModeVerbatim
                                  ? OMDDocumentRenderModeVerbatim
                                  : OMDDocumentRenderModeMarkdown);
    if (_currentDisplayTitle != nil) {
        [_currentDisplayTitle release];
        _currentDisplayTitle = nil;
    }
    [self setCurrentDiskFingerprintStateLoaded:nil observed:nil suppressed:nil];
    _currentDocumentReadOnly = NO;
    _sourceIsDirty = NO;
    _sourceRevision = 0;
    _lastRenderedSourceRevision = 0;
    _lastRenderedLayoutWidth = -1.0;
    _isProgrammaticSelectionSync = NO;
    [self cancelPendingRecoveryAutosave];

    if (_currentPath != nil) {
        NSString *lastDir = [_currentPath stringByDeletingLastPathComponent];
        if (lastDir != nil) {
            [[NSUserDefaults standardUserDefaults] setObject:lastDir forKey:@"ObjcMarkdownLastOpenDir"];
        }
    }

    [self updateRendererParsingOptionsForSourcePath:_currentPath];
    [self synchronizeSourceEditorWithCurrentMarkdown];
    [self applyCurrentDocumentReadOnlyState];
    [self updatePreviewStatusIndicator];
    [self updateWindowTitle];
    if (_currentMarkdown == nil) {
        [self clearPreviewPresentation];
        [self setPreviewUpdating:NO];
        return;
    }
    if ([self isPreviewVisible]) {
        [self renderCurrentMarkdown];
    }
}

- (void)setCurrentMarkdown:(NSString *)markdown sourcePath:(NSString *)sourcePath
{
    [self setCurrentDocumentText:markdown
                      sourcePath:sourcePath
                      renderMode:OMDDocumentRenderModeMarkdown
                  syntaxLanguage:nil];
}

- (void)refreshCurrentDocumentDiskStateAllowPrompt:(BOOL)allowPrompt
{
    if (![self isCurrentDocumentReloadableFromDisk]) {
        [self setCurrentDiskFingerprintStateLoaded:nil observed:nil suppressed:nil];
        [self captureCurrentStateIntoSelectedTab];
        return;
    }

    NSString *observedFingerprint = [self diskFingerprintForPath:_currentPath];
    NSString *loadedFingerprint = _currentLoadedDiskFingerprint;
    NSString *suppressedFingerprint = _currentSuppressedDiskFingerprint;

    if ([observedFingerprint length] == 0) {
        [self setCurrentDiskFingerprintStateLoaded:loadedFingerprint
                                          observed:nil
                                        suppressed:suppressedFingerprint];
        [self captureCurrentStateIntoSelectedTab];
        return;
    }

    if ([loadedFingerprint length] == 0) {
        loadedFingerprint = observedFingerprint;
        suppressedFingerprint = nil;
    } else if ([observedFingerprint isEqualToString:loadedFingerprint]) {
        suppressedFingerprint = nil;
    }

    [self setCurrentDiskFingerprintStateLoaded:loadedFingerprint
                                      observed:observedFingerprint
                                    suppressed:suppressedFingerprint];
    [self captureCurrentStateIntoSelectedTab];

    if (!allowPrompt || _externalReloadPromptVisible) {
        return;
    }
    if (_window == nil || ![_window isVisible] || ![_window isKeyWindow]) {
        return;
    }
    if (NSApp != nil && ![NSApp isActive]) {
        return;
    }
    if (![self currentDocumentHasNewerDiskVersion]) {
        return;
    }
    if ([_currentObservedDiskFingerprint isEqualToString:_currentSuppressedDiskFingerprint]) {
        return;
    }

    NSString *documentName = (_currentPath != nil ? [_currentPath lastPathComponent] : @"Untitled");
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Reload from disk?"];
    if (_sourceIsDirty) {
        [alert setInformativeText:[NSString stringWithFormat:@"\"%@\" changed on disk. Reloading discards your unsaved changes in this window. Keep stops prompts until the file changes again.",
                                                             documentName]];
    } else {
        [alert setInformativeText:[NSString stringWithFormat:@"\"%@\" changed on disk. Keep stops prompts until the file changes again.",
                                                             documentName]];
    }
    [alert addButtonWithTitle:@"Reload"];
    [alert addButtonWithTitle:@"Keep"];

    _externalReloadPromptVisible = YES;
    NSInteger buttonIndex = OMDAlertButtonIndexForResponse([alert runModal]);
    _externalReloadPromptVisible = NO;

    if (buttonIndex == 0) {
        if (![self reloadCurrentDocumentFromDiskPreservingViewport]) {
            [self setCurrentDiskFingerprintStateLoaded:_currentLoadedDiskFingerprint
                                              observed:_currentObservedDiskFingerprint
                                            suppressed:_currentObservedDiskFingerprint];
            [self captureCurrentStateIntoSelectedTab];
        }
    } else {
        [self setCurrentDiskFingerprintStateLoaded:_currentLoadedDiskFingerprint
                                          observed:_currentObservedDiskFingerprint
                                        suppressed:_currentObservedDiskFingerprint];
        [self captureCurrentStateIntoSelectedTab];
    }
}

- (BOOL)reloadCurrentDocumentFromDiskPreservingViewport
{
    if (![self isCurrentDocumentReloadableFromDisk]) {
        return NO;
    }

    NSString *path = [[_currentPath copy] autorelease];
    NSString *markdown = nil;
    NSString *displayTitle = nil;
    NSString *syntaxLanguage = nil;
    NSString *fingerprint = nil;
    OMDDocumentRenderMode renderMode = OMDDocumentRenderModeMarkdown;
    if (![self loadDocumentContentsAtPath:path
                               actionName:@"Reload from Disk"
                                 markdown:&markdown
                             displayTitle:&displayTitle
                               renderMode:&renderMode
                           syntaxLanguage:&syntaxLanguage
                              fingerprint:&fingerprint]) {
        return NO;
    }

    NSMutableDictionary *tab = [self newDocumentTabWithMarkdown:(markdown != nil ? markdown : @"")
                                                     sourcePath:path
                                                   displayTitle:displayTitle
                                                       readOnly:_currentDocumentReadOnly
                                                     renderMode:renderMode
                                                 syntaxLanguage:syntaxLanguage
                                                diskFingerprint:fingerprint];
    [self installDocumentTabRecord:tab inNewTab:NO resetViewport:NO];
    [self clearRecoverySnapshot];
    return YES;
}

- (void)reloadDocumentFromDisk:(id)sender
{
    (void)sender;
    if (![self ensureDocumentLoadedForActionName:@"Reload from Disk"]) {
        return;
    }

    [self refreshCurrentDocumentDiskStateAllowPrompt:NO];
    if (![self currentDocumentHasNewerDiskVersion]) {
        return;
    }
    if (![self confirmReloadingFromDiskDiscardingCurrentChanges]) {
        return;
    }
    [self reloadCurrentDocumentFromDiskPreservingViewport];
}

- (NSString *)markdownForCurrentPreview
{
    if (_currentMarkdown == nil) {
        return nil;
    }
    if (_currentDocumentRenderMode != OMDDocumentRenderModeVerbatim) {
        return _currentMarkdown;
    }
    return OMDMarkdownCodeFenceWrappedText(_currentMarkdown, _currentDocumentSyntaxLanguage);
}

- (NSString *)decodedTextForFileAtPath:(NSString *)path error:(NSError **)error
{
    if (path == nil || [path length] == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:OMDTextFileErrorDomain
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Missing file path." }];
        }
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:OMDTextFileErrorDomain
                                         code:4
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Unable to read file data." }];
        }
        return nil;
    }
    if (OMDDataAppearsBinary(data)) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:OMDTextFileErrorDomain
                                         code:2
                                     userInfo:@{ NSLocalizedDescriptionKey: @"This file appears to be binary and cannot be previewed as text." }];
        }
        return nil;
    }

    NSStringEncoding usedEncoding = NSUTF8StringEncoding;
    NSString *decoded = OMDDecodeTextFromData(data, &usedEncoding);
    if (decoded == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:OMDTextFileErrorDomain
                                         code:3
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Unable to decode this file as text." }];
        }
        return nil;
    }
    (void)usedEncoding;
    return decoded;
}

- (BOOL)importDocumentAtPath:(NSString *)path
{
    NSString *extension = [[path pathExtension] lowercaseString];
    if (![OMDDocumentConverter isSupportedExtension:extension]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Unsupported import format"];
        [alert setInformativeText:@"Choose an .html, .rtf, .docx, or .odt file."];
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

    BOOL opened = [self openDocumentWithMarkdown:(importedMarkdown != nil ? importedMarkdown : @"")
                                       sourcePath:path
                                     displayTitle:[path lastPathComponent]
                                         readOnly:NO
                                       renderMode:OMDDocumentRenderModeMarkdown
                                   syntaxLanguage:nil
                                         inNewTab:NO
                              requireDirtyConfirm:YES];
    if (opened) {
        [self noteRecentDocumentAtPathIfAvailable:path];
    }
    return opened;
}

- (NSString *)defaultExportFileNameWithExtension:(NSString *)extension
{
    NSString *baseName = nil;
    if (_currentPath != nil) {
        baseName = [[_currentPath lastPathComponent] stringByDeletingPathExtension];
    } else if (_currentDisplayTitle != nil && [_currentDisplayTitle length] > 0) {
        baseName = [[_currentDisplayTitle lastPathComponent] stringByDeletingPathExtension];
        baseName = [baseName stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    }
    if (baseName == nil || [baseName length] == 0) {
        baseName = @"Document";
    }
    return [baseName stringByAppendingPathExtension:extension];
}

- (NSString *)defaultSaveMarkdownFileName
{
    if (_currentDocumentRenderMode == OMDDocumentRenderModeVerbatim) {
        NSString *extension = nil;
        if (_currentPath != nil) {
            extension = [[_currentPath pathExtension] lowercaseString];
        } else if (_currentDisplayTitle != nil) {
            NSString *candidate = [_currentDisplayTitle lastPathComponent];
            extension = [[candidate pathExtension] lowercaseString];
        }
        if (extension == nil || [extension length] == 0) {
            extension = @"txt";
        }
        return [self defaultExportFileNameWithExtension:extension];
    }
    return [self defaultExportFileNameWithExtension:@"md"];
}

- (NSString *)defaultExportPDFFileName
{
    return [self defaultExportFileNameWithExtension:@"pdf"];
}

- (NSString *)recoverySnapshotPath
{
    NSString *home = NSHomeDirectory();
    if (home == nil || [home length] == 0) {
        home = NSTemporaryDirectory();
    }
    NSString *directory = [home stringByAppendingPathComponent:@"GNUstep/Library/ApplicationSupport/ObjcMarkdownViewer/Recovery"];
    return [directory stringByAppendingPathComponent:@"autosave-recovery.plist"];
}

- (void)scheduleRecoveryAutosave
{
    if (!_sourceIsDirty || _currentMarkdown == nil) {
        return;
    }

    if (_recoveryAutosaveTimer != nil) {
        [_recoveryAutosaveTimer invalidate];
        [_recoveryAutosaveTimer release];
        _recoveryAutosaveTimer = nil;
    }

    _recoveryAutosaveTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDRecoveryAutosaveDebounceInterval
                                                                target:self
                                                              selector:@selector(recoveryAutosaveTimerFired:)
                                                              userInfo:nil
                                                               repeats:NO] retain];
}

- (void)recoveryAutosaveTimerFired:(NSTimer *)timer
{
    if (timer != _recoveryAutosaveTimer) {
        return;
    }
    [_recoveryAutosaveTimer invalidate];
    [_recoveryAutosaveTimer release];
    _recoveryAutosaveTimer = nil;
    [self writeRecoverySnapshot];
}

- (void)cancelPendingRecoveryAutosave
{
    if (_recoveryAutosaveTimer != nil) {
        [_recoveryAutosaveTimer invalidate];
        [_recoveryAutosaveTimer release];
        _recoveryAutosaveTimer = nil;
    }
}

- (BOOL)writeRecoverySnapshot
{
    if (!_sourceIsDirty || _currentMarkdown == nil) {
        return NO;
    }

    NSString *snapshotPath = [self recoverySnapshotPath];
    if (snapshotPath == nil || [snapshotPath length] == 0) {
        return NO;
    }

    NSString *directory = [snapshotPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:directory]) {
        [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    [snapshot setObject:_currentMarkdown forKey:@"markdown"];
    [snapshot setObject:[NSDate date] forKey:@"timestamp"];
    [snapshot setObject:[NSNumber numberWithBool:_sourceIsDirty] forKey:@"dirty"];
    [snapshot setObject:[NSNumber numberWithInteger:_currentDocumentRenderMode] forKey:@"renderMode"];
    if (_currentPath != nil) {
        [snapshot setObject:_currentPath forKey:@"sourcePath"];
    }
    if (_currentDocumentSyntaxLanguage != nil && [_currentDocumentSyntaxLanguage length] > 0) {
        [snapshot setObject:_currentDocumentSyntaxLanguage forKey:@"syntaxLanguage"];
    }

    return [snapshot writeToFile:snapshotPath atomically:YES];
}

- (void)clearRecoverySnapshot
{
    NSString *snapshotPath = [self recoverySnapshotPath];
    if (snapshotPath == nil || [snapshotPath length] == 0) {
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:snapshotPath]) {
        [fm removeItemAtPath:snapshotPath error:NULL];
    }
}

- (BOOL)restoreRecoveryIfAvailable
{
    NSString *snapshotPath = [self recoverySnapshotPath];
    if (snapshotPath == nil || [snapshotPath length] == 0) {
        return NO;
    }

    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:snapshotPath];
    if (snapshot == nil) {
        return NO;
    }

    NSString *markdown = [snapshot objectForKey:@"markdown"];
    if (![markdown isKindOfClass:[NSString class]]) {
        [self clearRecoverySnapshot];
        return NO;
    }

    id dirtyValue = [snapshot objectForKey:@"dirty"];
    if ([dirtyValue respondsToSelector:@selector(boolValue)] && ![dirtyValue boolValue]) {
        [self clearRecoverySnapshot];
        return NO;
    }

    NSString *sourcePath = nil;
    id sourcePathValue = [snapshot objectForKey:@"sourcePath"];
    if ([sourcePathValue isKindOfClass:[NSString class]] && [sourcePathValue length] > 0) {
        sourcePath = sourcePathValue;
    }
    OMDDocumentRenderMode renderMode = OMDDocumentRenderModeMarkdown;
    id renderModeValue = [snapshot objectForKey:@"renderMode"];
    if ([renderModeValue respondsToSelector:@selector(integerValue)]) {
        NSInteger rawMode = [renderModeValue integerValue];
        if (rawMode == OMDDocumentRenderModeVerbatim) {
            renderMode = OMDDocumentRenderModeVerbatim;
        }
    }
    NSString *syntaxLanguage = nil;
    id syntaxValue = [snapshot objectForKey:@"syntaxLanguage"];
    if ([syntaxValue isKindOfClass:[NSString class]]) {
        syntaxLanguage = OMDTrimmedString((NSString *)syntaxValue);
    }
    if (renderMode == OMDDocumentRenderModeMarkdown &&
        sourcePath != nil &&
        ![self isMarkdownTextPath:sourcePath] &&
        ![self isImportableDocumentPath:sourcePath]) {
        renderMode = OMDDocumentRenderModeVerbatim;
        if ([syntaxLanguage length] == 0) {
            syntaxLanguage = OMDVerbatimSyntaxTokenForExtension([sourcePath pathExtension]);
        }
    }

    NSString *documentName = sourcePath != nil ? [sourcePath lastPathComponent] : @"Untitled";
    NSString *timestampDescription = nil;
    id timestampValue = [snapshot objectForKey:@"timestamp"];
    if ([timestampValue isKindOfClass:[NSDate class]]) {
        timestampDescription = [timestampValue description];
    } else if ([timestampValue isKindOfClass:[NSString class]]) {
        timestampDescription = timestampValue;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Recover unsaved changes?"];
    if (timestampDescription != nil && [timestampDescription length] > 0) {
        [alert setInformativeText:[NSString stringWithFormat:@"A recovery snapshot for \"%@\" was found (%@).",
                                                             documentName,
                                                             timestampDescription]];
    } else {
        [alert setInformativeText:[NSString stringWithFormat:@"A recovery snapshot for \"%@\" was found.",
                                                             documentName]];
    }
    [alert addButtonWithTitle:@"Recover"];
    [alert addButtonWithTitle:@"Discard"];

    NSInteger buttonIndex = OMDAlertButtonIndexForResponse([alert runModal]);
    if (buttonIndex != 0) {
        [self clearRecoverySnapshot];
        return NO;
    }

    [self openDocumentWithMarkdown:markdown
                        sourcePath:sourcePath
                      displayTitle:documentName
                          readOnly:NO
                        renderMode:renderMode
                    syntaxLanguage:syntaxLanguage
                          inNewTab:NO
               requireDirtyConfirm:NO];
    _sourceIsDirty = YES;
    _sourceRevision = 1;
    [self captureCurrentStateIntoSelectedTab];
    [self updateTabStrip];
    [self updateWindowTitle];
    [self scheduleRecoveryAutosave];
    return YES;
}

- (BOOL)saveCurrentMarkdownToPath:(NSString *)path
{
    if (path == nil || [path length] == 0 || _currentMarkdown == nil) {
        return NO;
    }

    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:path];
    if ([resolvedPath length] == 0) {
        return NO;
    }
    NSString *currentResolvedPath = [self resolvedAbsolutePathForLocalPath:_currentPath];
    if ([currentResolvedPath length] > 0 &&
        [resolvedPath isEqualToString:currentResolvedPath]) {
        [self refreshCurrentDocumentDiskStateAllowPrompt:NO];
        if (![self confirmOverwritingNewerDiskVersionAtPath:resolvedPath]) {
            return NO;
        }
    }

    NSError *error = nil;
    BOOL success = [_currentMarkdown writeToFile:resolvedPath
                                      atomically:YES
                                        encoding:NSUTF8StringEncoding
                                           error:&error];
    if (!success) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Save failed"];
        [alert setInformativeText:[error localizedDescription]];
        [alert runModal];
        return NO;
    }

    [self setCurrentDocumentText:_currentMarkdown
                      sourcePath:resolvedPath
                      renderMode:(OMDDocumentRenderMode)_currentDocumentRenderMode
                  syntaxLanguage:_currentDocumentSyntaxLanguage];
    NSString *savedFingerprint = [self diskFingerprintForPath:resolvedPath];
    [self setCurrentDiskFingerprintStateLoaded:savedFingerprint
                                      observed:savedFingerprint
                                    suppressed:nil];
    [self captureCurrentStateIntoSelectedTab];
    [self updateTabStrip];
    [self clearRecoverySnapshot];
    return YES;
}

- (BOOL)saveDocumentAsMarkdownWithPanel
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    BOOL verbatimMode = (_currentDocumentRenderMode == OMDDocumentRenderModeVerbatim);
    if (verbatimMode) {
        [panel setAllowedFileTypes:nil];
        if ([panel respondsToSelector:@selector(setAllowsOtherFileTypes:)]) {
            [panel setAllowsOtherFileTypes:YES];
        }
    } else {
        [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"md", @"markdown", nil]];
    }
    [panel setCanCreateDirectories:YES];
    [panel setTitle:(verbatimMode ? @"Save As" : @"Save Markdown As")];
    [panel setPrompt:@"Save"];
    [panel setNameFieldStringValue:[self defaultSaveMarkdownFileName]];
    if (_currentPath != nil) {
        [panel setDirectory:[_currentPath stringByDeletingLastPathComponent]];
    }

    NSInteger result = [panel runModal];
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        return NO;
    }

    NSString *path = OMDSelectedPathFromSavePanel(panel);
    if (path == nil || [path length] == 0) {
        return NO;
    }
    if (!verbatimMode) {
        NSString *extension = [[path pathExtension] lowercaseString];
        if (![extension isEqualToString:@"md"] && ![extension isEqualToString:@"markdown"]) {
            path = [path stringByAppendingPathExtension:@"md"];
        }
    }

    return [self saveCurrentMarkdownToPath:path];
}

- (BOOL)saveDocumentFromVimCommand
{
    if (![self ensureDocumentLoadedForActionName:@"Save"]) {
        return NO;
    }

    if (_currentPath != nil && [_currentPath length] > 0) {
        return [self saveCurrentMarkdownToPath:_currentPath];
    }
    return [self saveDocumentAsMarkdownWithPanel];
}

- (void)performCloseFromVimCommandForcingDiscard:(BOOL)force
{
    if (_window == nil) {
        return;
    }

    if (force) {
        _sourceVimForceClose = YES;
    }
    [_window performClose:self];
    _sourceVimForceClose = NO;
}

- (void)saveDocument:(id)sender
{
    (void)sender;
    [self saveDocumentFromVimCommand];
}

- (void)saveDocumentAsMarkdown:(id)sender
{
    if (![self ensureDocumentLoadedForActionName:@"Save Markdown As"]) {
        return;
    }

    [self saveDocumentAsMarkdownWithPanel];
}

- (BOOL)confirmDiscardingUnsavedChangesForAction:(NSString *)actionName
{
    if (!_sourceIsDirty) {
        return YES;
    }

    NSString *documentName = _currentPath != nil ? [_currentPath lastPathComponent] : @"Untitled";
    NSString *action = ([actionName length] > 0) ? actionName : @"continuing";
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:@"Do you want to save changes to \"%@\" before %@?",
                                                      documentName,
                                                      action]];
    [alert setInformativeText:@"If you don't save, your changes will be lost."];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];

    if (_sourceTextView != nil) {
        [NSObject cancelPreviousPerformRequestsWithTarget:_sourceTextView
                                                 selector:@selector(omdApplyDeferredEditorCursorShape)
                                                   object:nil];
    }
    NSCursor *arrowCursor = [NSCursor arrowCursor];
    if (arrowCursor != nil) {
        [arrowCursor set];
    }
    NSWindow *alertWindow = [alert window];
    if (alertWindow != nil) {
        OMDDisableSelectableTextFieldsInView([alertWindow contentView]);
    }

    NSInteger buttonIndex = OMDAlertButtonIndexForResponse([alert runModal]);
    if (buttonIndex == 0) {
        if (_currentPath != nil && [_currentPath length] > 0) {
            return [self saveCurrentMarkdownToPath:_currentPath];
        }
        return [self saveDocumentAsMarkdownWithPanel];
    }
    if (buttonIndex == 1) {
        return YES;
    }
    return NO;
}

- (BOOL)confirmReloadingFromDiskDiscardingCurrentChanges
{
    if (!_sourceIsDirty) {
        return YES;
    }

    NSString *documentName = (_currentPath != nil ? [_currentPath lastPathComponent] : @"Untitled");
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:@"Reload \"%@\" from disk?", documentName]];
    [alert setInformativeText:@"Reloading the newer version will discard your unsaved changes in this window."];
    [alert addButtonWithTitle:@"Reload"];
    [alert addButtonWithTitle:@"Cancel"];

    NSInteger buttonIndex = OMDAlertButtonIndexForResponse([alert runModal]);
    return (buttonIndex == 0);
}

- (BOOL)confirmOverwritingNewerDiskVersionAtPath:(NSString *)path
{
    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:path];
    NSString *currentResolvedPath = [self resolvedAbsolutePathForLocalPath:_currentPath];
    if ([resolvedPath length] == 0 || ![resolvedPath isEqualToString:currentResolvedPath]) {
        return YES;
    }

    if (![self currentDocumentHasNewerDiskVersion]) {
        return YES;
    }

    NSString *documentName = [resolvedPath lastPathComponent];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:[NSString stringWithFormat:@"Overwrite newer on-disk changes to \"%@\"?", documentName]];
    [alert setInformativeText:@"A newer version of this file exists on disk. Saving now will overwrite those outside changes with the version in this window."];
    [alert addButtonWithTitle:@"Overwrite"];
    [alert addButtonWithTitle:@"Cancel"];

    NSInteger buttonIndex = OMDAlertButtonIndexForResponse([alert runModal]);
    return (buttonIndex == 0);
}

- (NSPrintInfo *)configuredPrintInfo
{
    [self ensurePrintDefaultPrinterConfigured];
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

- (void)ensurePrintDefaultPrinterConfigured
{
#if defined(_WIN32)
    return;
#else
    NSString *defaultPrinterName = OMDCUPSDefaultPrinterName();
    if (defaultPrinterName != nil && [defaultPrinterName length] > 0) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"existing CUPS default printer=%@", defaultPrinterName]);
        return;
    }

    NSArray *printerNames = nil;
    @try {
        printerNames = [NSPrinter printerNames];
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"printerNames lookup failed: %@", [exception reason]]);
        return;
    }

    if ([printerNames count] == 0) {
        OMDLogPrintDiagnostics(@"no printers available while trying to seed default printer");
        return;
    }

    NSString *printerName = [printerNames objectAtIndex:0];
    if ([printerName isEqualToString:@"GSCUPSDummyPrinter"]) {
        OMDLogPrintDiagnostics(@"only GSCUPSDummyPrinter is available; leaving default printer unset");
        return;
    }

    NSPrinter *printer = nil;
    @try {
        printer = [NSPrinter printerWithName:printerName];
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"printerWithName failed for %@: %@", printerName, [exception reason]]);
        return;
    }

    if (printer == nil) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"printerWithName returned nil for %@", printerName]);
        return;
    }

    [NSPrintInfo setDefaultPrinter:printer];
    OMDLogPrintDiagnostics([NSString stringWithFormat:@"seeded CUPS default printer=%@", printerName]);
#endif
}

- (void)runLaunchPrintAutomationIfRequested
{
    if (!OMDLaunchPrintAutomationEnabled()) {
        return;
    }

    OMDLogPrintDiagnostics([NSString stringWithFormat:@"launch automation currentPath=%@ markdownLength=%lu",
                                                      (_currentPath != nil ? _currentPath : @"<nil>"),
                                                      (unsigned long)[_currentMarkdown length]]);
    if (_window != nil) {
        [_window makeKeyAndOrderFront:nil];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self printDocument:nil];
}

- (void)runLaunchPDFExportAutomationIfRequested
{
    NSString *path = OMDLaunchPDFExportAutomationPath();
    if (path == nil || [path length] == 0) {
        return;
    }

    OMDLogPrintDiagnostics([NSString stringWithFormat:@"launch PDF export automation path=%@", path]);
    if (_window != nil) {
        [_window makeKeyAndOrderFront:nil];
    }
    [NSApp activateIgnoringOtherApps:YES];

    if ([self exportDocumentAsPDFToPath:path]) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        unsigned long long fileSize = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"launch PDF export automation succeeded path=%@ size=%llu",
                                                          path,
                                                          fileSize]);
    } else {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"launch PDF export automation failed path=%@", path]);
    }
}

- (void)logPrintDiagnosticsForOperation:(NSPrintOperation *)operation
                              printInfo:(NSPrintInfo *)printInfo
                                  stage:(NSString *)stage
{
    if (!OMDPrintDiagnosticsEnabled()) {
        return;
    }

    NSArray *printerNames = nil;
    NSPrinter *defaultPrinter = nil;
    NSPrinter *selectedPrinter = nil;
    NSPrintPanel *panel = nil;
    NSBundle *printingBundle = nil;

    @try {
        printerNames = [NSPrinter printerNames];
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"%@ printerNames exception=%@",
                                                          stage,
                                                          [exception reason]]);
    }

    @try {
        defaultPrinter = [NSPrintInfo defaultPrinter];
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"%@ defaultPrinter exception=%@",
                                                          stage,
                                                          [exception reason]]);
    }

    @try {
        selectedPrinter = [printInfo printer];
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"%@ selectedPrinter exception=%@",
                                                          stage,
                                                          [exception reason]]);
    }

    @try {
        panel = (operation != nil ? [operation printPanel] : nil);
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"%@ printPanel exception=%@",
                                                          stage,
                                                          [exception reason]]);
    }

    @try {
        printingBundle = [GSPrinting printingBundle];
    } @catch (NSException *exception) {
        OMDLogPrintDiagnostics([NSString stringWithFormat:@"%@ printingBundle exception=%@",
                                                          stage,
                                                          [exception reason]]);
    }

    OMDLogPrintDiagnostics([NSString stringWithFormat:@"%@ operationClass=%@ panelClass=%@ panelVisible=%@ panelFrame=%@ bundlePath=%@ selectedPrinter=%@ defaultPrinter=%@ printerNames=%@ jobDisposition=%@",
                                                      stage,
                                                      (operation != nil ? NSStringFromClass([operation class]) : @"<nil>"),
                                                      (panel != nil ? NSStringFromClass([panel class]) : @"<nil>"),
                                                      (panel != nil && [panel isVisible] ? @"YES" : @"NO"),
                                                      (panel != nil ? NSStringFromRect([panel frame]) : @"<nil>"),
                                                      (printingBundle != nil ? [printingBundle bundlePath] : @"<nil>"),
                                                      (selectedPrinter != nil ? [selectedPrinter name] : @"<nil>"),
                                                      (defaultPrinter != nil ? [defaultPrinter name] : @"<nil>"),
                                                      (printerNames != nil ? [printerNames componentsJoinedByString:@", "] : @"<nil>"),
                                                      (printInfo != nil ? [printInfo jobDisposition] : @"<nil>")]);
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
    NSString *previewMarkdown = [self markdownForCurrentPreview];
    if (previewMarkdown == nil) {
        return nil;
    }

    CGFloat viewWidth = [self printableContentWidthForPrintInfo:printInfo];
    CGFloat insetX = 20.0;
    CGFloat insetY = 16.0;
    CGFloat layoutWidth = viewWidth - (insetX * 2.0);
    if (layoutWidth < 1.0) {
        layoutWidth = viewWidth;
    }

    OMMarkdownParsingOptions *printOptions = nil;
    if (_renderer != nil && [_renderer parsingOptions] != nil) {
        printOptions = [[[_renderer parsingOptions] copy] autorelease];
    } else {
        printOptions = [OMMarkdownParsingOptions defaultOptions];
    }

    OMMarkdownRenderer *printRenderer = [[OMMarkdownRenderer alloc] initWithTheme:nil
                                                                   parsingOptions:printOptions];
    [printRenderer setZoomScale:OMDPrintExportZoomScale];
    [printRenderer setLayoutWidth:layoutWidth];
    NSAttributedString *rendered = [printRenderer attributedStringFromMarkdown:previewMarkdown];

    OMDTextView *printView = [[OMDTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, viewWidth, 100.0)];
    [printView setEditable:NO];
    [printView setSelectable:NO];
    [printView setRichText:YES];
    [printView setDrawsBackground:NO];
    [printView setTextContainerInset:NSMakeSize(insetX, insetY)];
    [[printView textContainer] setLineFragmentPadding:0.0];
    [[printView textStorage] setAttributedString:rendered];
    [printView setCodeBlockRanges:[printRenderer codeBlockRanges]];
    [printView setCodeBlockBackgroundColor:[NSColor colorWithCalibratedRed:(239.0 / 255.0)
                                                                      green:(243.0 / 255.0)
                                                                       blue:(247.0 / 255.0)
                                                                      alpha:1.0]];
    [printView setCodeBlockBorderColor:[NSColor colorWithCalibratedRed:(208.0 / 255.0)
                                                                  green:(215.0 / 255.0)
                                                                   blue:(222.0 / 255.0)
                                                                  alpha:1.0]];
    [printView setCodeBlockPadding:NSMakeSize(20.0, 14.0)];
    [printView setCodeBlockCornerRadius:6.0];
    [printView setCodeBlockBorderWidth:1.0];
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
    (void)sender;
    if (![self ensureDocumentLoadedForActionName:@"Print"]) {
        return;
    }

    NSPrintInfo *printInfo = [self configuredPrintInfo];
    OMDTextView *printView = [self newPrintTextViewForPrintInfo:printInfo];
    if (printView == nil) {
        OMDLogPrintDiagnostics(@"printDocument aborting because printView is nil");
        return;
    }

    BOOL ok = NO;
#if defined(_WIN32)
    NSString *temporaryPDFPath = [self temporaryPDFPrintPath];
    NSString *browserPath = [self windowsHeadlessBrowserPath];
    if (temporaryPDFPath != nil &&
        browserPath != nil &&
        [self exportPrintView:printView toPDFAtPath:temporaryPDFPath usingBrowser:browserPath]) {
        ok = [self launchWindowsShellPrintForPDFAtPath:temporaryPDFPath];
    }
#else
    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:printView printInfo:printInfo];
    [self logPrintDiagnosticsForOperation:operation printInfo:printInfo stage:@"before runOperation"];
    [operation setShowsPrintPanel:YES];
    [operation setShowsProgressPanel:YES];
    ok = [operation runOperation];
    [self logPrintDiagnosticsForOperation:operation printInfo:printInfo stage:@"after runOperation"];
#endif
    [printView release];

    if (!ok) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Print failed"];
        [alert setInformativeText:@"The document could not be sent to the print system."];
        [alert runModal];
    }
}

#if defined(_WIN32)
- (NSString *)windowsHeadlessBrowserPath
{
    NSArray *candidates = [NSArray arrayWithObjects:
                           @"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
                           @"C:/Program Files/Microsoft/Edge/Application/msedge.exe",
                           @"C:/Program Files/Google/Chrome/Application/chrome.exe",
                           @"C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
                           nil];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *candidate in candidates) {
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (NSString *)temporaryHTMLExportPath
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory == nil || [temporaryDirectory length] == 0) {
        temporaryDirectory = @"C:/Windows/Temp";
    }
    NSString *fileName = [NSString stringWithFormat:@"ObjcMarkdown-Export-%@.html",
                                                    [[NSProcessInfo processInfo] globallyUniqueString]];
    return [temporaryDirectory stringByAppendingPathComponent:fileName];
}

- (NSString *)windowsPDFSavePathWithSuggestedName:(NSString *)suggestedName
{
    NSString *initialDirectory = nil;
    if (_currentPath != nil && [_currentPath length] > 0) {
        initialDirectory = [_currentPath stringByDeletingLastPathComponent];
    } else {
        initialDirectory = [@"~/Desktop" stringByExpandingTildeInPath];
    }

    NSString *fileName = (suggestedName != nil && [suggestedName length] > 0)
        ? suggestedName
        : @"Export.pdf";
    if (![[[fileName pathExtension] lowercaseString] isEqualToString:@"pdf"]) {
        fileName = [fileName stringByAppendingPathExtension:@"pdf"];
    }

    NSUInteger dirLength = [initialDirectory length];
    wchar_t *wideDirectory = (wchar_t *)calloc(dirLength + 1, sizeof(wchar_t));
    if (wideDirectory == NULL) {
        return nil;
    }
    [initialDirectory getCharacters:(unichar *)wideDirectory range:NSMakeRange(0, dirLength)];
    wideDirectory[dirLength] = L'\0';

    NSUInteger fileLength = [fileName length];
    wchar_t fileBuffer[32768];
    memset(fileBuffer, 0, sizeof(fileBuffer));
    if (fileLength > 0) {
        NSUInteger copyLength = MIN(fileLength, ((sizeof(fileBuffer) / sizeof(wchar_t)) - 1));
        [fileName getCharacters:(unichar *)fileBuffer range:NSMakeRange(0, copyLength)];
        fileBuffer[copyLength] = L'\0';
    }

    const wchar_t filter[] = L"PDF Files (*.pdf)\0*.pdf\0All Files (*.*)\0*.*\0\0";
    const wchar_t defaultExt[] = L"pdf";
    const wchar_t title[] = L"Export as PDF";

    OPENFILENAMEW ofn;
    memset(&ofn, 0, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = NULL;
    ofn.lpstrFile = fileBuffer;
    ofn.nMaxFile = sizeof(fileBuffer) / sizeof(wchar_t);
    ofn.lpstrFilter = filter;
    ofn.nFilterIndex = 1;
    ofn.lpstrDefExt = defaultExt;
    ofn.lpstrTitle = title;
    ofn.lpstrInitialDir = wideDirectory;
    ofn.Flags = OFN_EXPLORER | OFN_HIDEREADONLY | OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT;

    NSString *selectedPath = nil;
    if (GetSaveFileNameW(&ofn)) {
        selectedPath = [NSString stringWithCharacters:(const unichar *)fileBuffer length:wcslen(fileBuffer)];
    }

    free(wideDirectory);
    return selectedPath;
}

- (NSString *)styledHTMLDocumentWithBody:(NSString *)bodyHTML title:(NSString *)title
{
    NSString *safeTitle = OMDHTMLEscapedString(title != nil ? title : @"Document");
    NSString *body = (bodyHTML != nil ? bodyHTML : @"");
    return [NSString stringWithFormat:
            @"<!doctype html><html><head><meta charset=\"utf-8\">"
            "<title>%@</title>"
            "<style>"
            "@page{size:auto;margin:0.7in;}"
            "html,body{margin:0;padding:0;background:#ffffff;color:#24292f;}"
            "body{font-family:Segoe UI,Arial,sans-serif;font-size:12pt;line-height:1.55;}"
            ".page{max-width:7.2in;margin:0 auto;}"
            "h1,h2,h3,h4,h5,h6{font-weight:600;line-height:1.25;margin:1.2em 0 0.5em;color:#24292f;page-break-after:avoid;}"
            "h1{font-size:2em;padding-bottom:0.3em;border-bottom:1px solid #d0d7de;}"
            "h2{font-size:1.5em;padding-bottom:0.2em;border-bottom:1px solid #d0d7de;}"
            "h3{font-size:1.25em;}"
            "p,ul,ol,blockquote,table,pre{margin:0 0 1em 0;}"
            "ul,ol{padding-left:1.6em;}"
            "li + li{margin-top:0.25em;}"
            "a{color:#0969da;text-decoration:none;}"
            "code{font-family:Consolas,'Courier New',monospace;font-size:0.92em;background:#f6f8fa;border-radius:4px;padding:0.12em 0.35em;}"
            "pre{background:#f6f8fa;border:1px solid #d0d7de;border-radius:6px;padding:14px 16px;overflow-wrap:anywhere;white-space:pre-wrap;}"
            "pre code{background:transparent;padding:0;border-radius:0;}"
            "blockquote{margin-left:0;padding:0 1em;color:#57606a;border-left:0.25em solid #d0d7de;}"
            "table{width:100%%;border-collapse:collapse;table-layout:auto;font-size:0.96em;page-break-inside:auto;}"
            "thead{display:table-header-group;}"
            "tr{page-break-inside:avoid;page-break-after:auto;}"
            "th,td{border:1px solid #d0d7de;padding:6px 10px;vertical-align:top;text-align:left;}"
            "th{font-weight:600;background:#f6f8fa;}"
            "img{max-width:100%%;}"
            "hr{border:none;border-top:1px solid #d0d7de;margin:1.5em 0;}"
            "</style></head><body><div class=\"page\">%@</div></body></html>",
            safeTitle,
            body];
}

- (BOOL)writePandocHTMLForCurrentPreviewToPath:(NSString *)path
{
    if (path == nil || [path length] == 0) {
        return NO;
    }

    OMDDocumentConverter *converter = [self documentConverter];
    if (converter == nil ||
        ![[converter backendName] isEqualToString:@"pandoc"] ||
        ![converter canExportExtension:@"html"]) {
        return NO;
    }

    NSString *markdown = [self markdownForCurrentPreview];
    if (markdown == nil) {
        markdown = _currentMarkdown;
    }
    if (markdown == nil) {
        return NO;
    }

    NSString *fragmentPath = [self temporaryHTMLExportPath];
    if (fragmentPath == nil) {
        return NO;
    }

    NSError *error = nil;
    BOOL exported = [converter exportMarkdown:markdown toPath:fragmentPath error:&error];
    if (!exported) {
        [[NSFileManager defaultManager] removeItemAtPath:fragmentPath error:NULL];
        return NO;
    }

    NSString *fragment = [NSString stringWithContentsOfFile:fragmentPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:fragmentPath error:NULL];
    if (fragment == nil || [fragment length] == 0) {
        return NO;
    }

    NSString *title = (_currentPath != nil ? [[_currentPath lastPathComponent] stringByDeletingPathExtension] : @"Markdown Export");
    NSString *html = nil;
    NSRange htmlTagRange = [[fragment lowercaseString] rangeOfString:@"<html"];
    if (htmlTagRange.location != NSNotFound) {
        html = fragment;
    } else {
        html = [self styledHTMLDocumentWithBody:fragment title:title];
    }

    NSData *htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];
    if (htmlData == nil || [htmlData length] == 0) {
        return NO;
    }
    return [htmlData writeToFile:path atomically:YES];
}

- (BOOL)writeHTMLForPrintView:(OMDTextView *)printView toPath:(NSString *)path
{
    if (printView == nil || path == nil || [path length] == 0) {
        return NO;
    }

    NSAttributedString *content = [[printView textStorage] copy];
    if (content == nil) {
        return NO;
    }
    NSError *error = nil;
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                NSHTMLTextDocumentType, NSDocumentTypeDocumentAttribute,
                                [NSNumber numberWithUnsignedInteger:NSUTF8StringEncoding], NSCharacterEncodingDocumentAttribute,
                                nil];
    NSData *htmlData = [content dataFromRange:NSMakeRange(0, [content length])
                           documentAttributes:attributes
                                        error:&error];
    [content release];
    if (htmlData == nil || [htmlData length] == 0) {
        NSString *plainText = [[printView textStorage] string];
        if (plainText == nil) {
            plainText = @"";
        }
        NSString *htmlString = [NSString stringWithFormat:
                                @"<!doctype html><html><head><meta charset=\"utf-8\">"
                                "<style>body{font-family:Segoe UI,Arial,sans-serif;margin:40px;line-height:1.45;color:#222;}pre{white-space:pre-wrap;word-wrap:break-word;font:14px/1.45 Consolas,'Courier New',monospace;}</style>"
                                "</head><body><pre>%@</pre></body></html>",
                                OMDHTMLEscapedString(plainText)];
        htmlData = [htmlString dataUsingEncoding:NSUTF8StringEncoding];
        if (htmlData == nil || [htmlData length] == 0) {
            return NO;
        }
    }
    return [htmlData writeToFile:path atomically:YES];
}

- (BOOL)exportHTMLAtPath:(NSString *)htmlPath toPDFAtPath:(NSString *)pdfPath usingBrowser:(NSString *)browserPath
{
    if (htmlPath == nil || [htmlPath length] == 0 || pdfPath == nil || [pdfPath length] == 0 || browserPath == nil) {
        return NO;
    }

    NSURL *htmlURL = [NSURL fileURLWithPath:htmlPath];
    if (htmlURL == nil) {
        return NO;
    }

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:browserPath];
    [task setArguments:[NSArray arrayWithObjects:
                        @"--headless",
                        @"--disable-gpu",
                        @"--allow-file-access-from-files",
                        @"--no-pdf-header-footer",
                        [NSString stringWithFormat:@"--print-to-pdf=%@", pdfPath],
                        [htmlURL absoluteString],
                        nil]];

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    [task setStandardOutput:stdoutPipe];
    [task setStandardError:stderrPipe];

    BOOL launched = YES;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        launched = NO;
        (void)exception;
    }

    return (launched &&
            [task terminationStatus] == 0 &&
            [[NSFileManager defaultManager] fileExistsAtPath:pdfPath]);
}

- (BOOL)exportPrintView:(OMDTextView *)printView toPDFAtPath:(NSString *)pdfPath usingBrowser:(NSString *)browserPath
{
    NSString *htmlPath = [self temporaryHTMLExportPath];
    if (htmlPath == nil) {
        return NO;
    }

    BOOL wroteHTML = [self writePandocHTMLForCurrentPreviewToPath:htmlPath];
    if (!wroteHTML) {
        wroteHTML = [self writeHTMLForPrintView:printView toPath:htmlPath];
    }
    if (!wroteHTML) {
        [[NSFileManager defaultManager] removeItemAtPath:htmlPath error:NULL];
        return NO;
    }

    BOOL success = [self exportHTMLAtPath:htmlPath toPDFAtPath:pdfPath usingBrowser:browserPath];
    [[NSFileManager defaultManager] removeItemAtPath:htmlPath error:NULL];
    return success;
}

- (NSString *)temporaryPDFPrintPath
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory == nil || [temporaryDirectory length] == 0) {
        temporaryDirectory = @"C:/Windows/Temp";
    }
    NSString *fileName = [NSString stringWithFormat:@"ObjcMarkdown-Print-%@.pdf",
                                                    [[NSProcessInfo processInfo] globallyUniqueString]];
    return [temporaryDirectory stringByAppendingPathComponent:fileName];
}

- (BOOL)launchWindowsShellPrintForPDFAtPath:(NSString *)path
{
    if (path == nil || [path length] == 0) {
        return NO;
    }

    NSUInteger length = [path length];
    wchar_t *widePath = (wchar_t *)calloc(length + 1, sizeof(wchar_t));
    if (widePath == NULL) {
        return NO;
    }

    [path getCharacters:(unichar *)widePath range:NSMakeRange(0, length)];
    widePath[length] = L'\0';

    HINSTANCE result = ShellExecuteW(NULL, L"print", widePath, NULL, NULL, SW_HIDE);
    if ((INT_PTR)result <= 32) {
        result = ShellExecuteW(NULL, L"open", widePath, NULL, NULL, SW_SHOWNORMAL);
    }

    free(widePath);
    return ((INT_PTR)result > 32);
}
#endif

- (BOOL)exportDocumentAsPDFToPath:(NSString *)path
{
    if (path == nil || [path length] == 0) {
        OMDLogPrintDiagnostics(@"export PDF aborted because destination path is empty");
        return NO;
    }

    NSString *normalizedPath = path;
    if (![[[normalizedPath pathExtension] lowercaseString] isEqualToString:@"pdf"]) {
        normalizedPath = [normalizedPath stringByAppendingPathExtension:@"pdf"];
    }

    OMDLogPrintDiagnostics([NSString stringWithFormat:@"export PDF destination=%@", normalizedPath]);

    NSPrintInfo *printInfo = [self configuredPrintInfo];
    OMDTextView *printView = [self newPrintTextViewForPrintInfo:printInfo];
    if (printView == nil) {
        OMDLogPrintDiagnostics(@"export PDF aborting because printView is nil");
        return NO;
    }

#if defined(_WIN32)
    NSString *browserPath = [self windowsHeadlessBrowserPath];
    BOOL success = (browserPath != nil &&
                    [self exportPrintView:printView toPDFAtPath:normalizedPath usingBrowser:browserPath]);
#else
    [printInfo setJobDisposition:NSPrintSaveJob];
    [[printInfo dictionary] setObject:normalizedPath forKey:NSPrintSavePath];

    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:printView
                                                                 printInfo:printInfo];
    [self logPrintDiagnosticsForOperation:operation printInfo:printInfo stage:@"before export runOperation"];
    [operation setShowsPrintPanel:NO];
    [operation setShowsProgressPanel:YES];
    BOOL success = [operation runOperation];
    [self logPrintDiagnosticsForOperation:operation printInfo:printInfo stage:@"after export runOperation"];
#endif

    [printView release];

    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:normalizedPath];
    OMDLogPrintDiagnostics([NSString stringWithFormat:@"export PDF result success=%@ fileExists=%@ path=%@",
                                                      (success ? @"YES" : @"NO"),
                                                      (fileExists ? @"YES" : @"NO"),
                                                      normalizedPath]);
    return success && fileExists;
}

- (void)exportDocumentAsPDF:(id)sender
{
    (void)sender;
    if (![self ensureDocumentLoadedForActionName:@"Export as PDF"]) {
        return;
    }

#if defined(_WIN32)
    NSString *path = [self windowsPDFSavePathWithSuggestedName:[self defaultExportFileNameWithExtension:@"pdf"]];
    if (path == nil || [path length] == 0) {
        OMDLogPrintDiagnostics(@"export PDF cancelled before destination selection on Windows");
        return;
    }
#else
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"pdf"]];
    [panel setCanCreateDirectories:YES];
    [panel setTitle:@"Export as PDF"];
    [panel setPrompt:@"Export"];
    [panel setNameFieldStringValue:[self defaultExportPDFFileName]];
    if (_currentPath != nil) {
        [panel setDirectory:[_currentPath stringByDeletingLastPathComponent]];
    }

    OMDLogPrintDiagnostics(@"export PDF presenting save panel");
    NSInteger result = [panel runModal];
    OMDLogPrintDiagnostics([NSString stringWithFormat:@"export PDF save panel result=%ld",
                                                      (long)result]);
    if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
        OMDLogPrintDiagnostics(@"export PDF cancelled in save panel");
        return;
    }

    NSString *path = OMDSelectedPathFromSavePanel(panel);
    if (path == nil || [path length] == 0) {
        OMDLogPrintDiagnostics(@"export PDF save panel returned empty filename");
        return;
    }
#endif
    BOOL success = [self exportDocumentAsPDFToPath:path];

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

- (void)exportDocumentAsHTML:(id)sender
{
    [self exportDocumentWithTitle:@"Export as HTML"
                        extension:@"html"
                       actionName:@"Export as HTML"];
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

    NSString *path = OMDSelectedPathFromSavePanel(panel);
    if (path == nil || [path length] == 0) {
        return;
    }
    if (![[[path pathExtension] lowercaseString] isEqualToString:[extension lowercaseString]]) {
        path = [path stringByAppendingPathExtension:extension];
    }

    NSString *markdownForExport = [self markdownForCurrentPreview];
    if (markdownForExport == nil) {
        markdownForExport = _currentMarkdown;
    }
    NSError *error = nil;
    BOOL success = [[self documentConverter] exportMarkdown:markdownForExport
                                                     toPath:path
                                                      error:&error];
    if (!success) {
        [self presentConverterError:error fallbackTitle:@"Export failed"];
    }
}

- (void)renderCurrentMarkdown
{
    NSString *previewMarkdown = [self markdownForCurrentPreview];
    if (previewMarkdown == nil) {
        [self clearPreviewPresentation];
        [self setPreviewUpdating:NO];
        return;
    }
    if (![self isPreviewVisible]) {
        [self setPreviewUpdating:NO];
        return;
    }
    [self setPreviewUpdating:YES];
    NSTimeInterval renderStart = OMDNow();
    BOOL sampledAsZoomRender = ((renderStart - _lastZoomSliderEventTime) <= OMDZoomAdaptiveSamplingWindow);
    BOOL perfLogging = OMDPerformanceLoggingEnabled();
    NSUInteger revisionAtRenderStart = _sourceRevision;
    [self cancelPendingInteractiveRender];
    [self cancelPendingMathArtifactRender];
    [self cancelPendingLivePreviewRender];
    [_renderer setZoomScale:_zoomScale];
    [self updateRendererLayoutWidth];
    NSTimeInterval markdownStart = perfLogging ? OMDNow() : 0.0;
    NSAttributedString *rendered = [_renderer attributedStringFromMarkdown:previewMarkdown];
    NSTimeInterval markdownMs = perfLogging ? ((OMDNow() - markdownStart) * 1000.0) : 0.0;
    NSTimeInterval applyStart = perfLogging ? OMDNow() : 0.0;
    _isProgrammaticPreviewUpdate = YES;
    [[_textView textStorage] setAttributedString:rendered];
    _isProgrammaticPreviewUpdate = NO;
    [self logPreviewStyleDiagnosticsForRenderedString:rendered];
    NSTimeInterval applyMs = perfLogging ? ((OMDNow() - applyStart) * 1000.0) : 0.0;
    [self updatePreviewDocumentGeometry];
    NSTimeInterval postStart = perfLogging ? OMDNow() : 0.0;
    [self updateCodeBlockButtons];
    NSColor *bg = [_renderer backgroundColor];
    if ([_textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *codeView = (OMDTextView *)_textView;
        [codeView setDocumentBackgroundColor:(bg != nil ? bg : [NSColor whiteColor])];
        [codeView setDocumentBorderColor:OMDResolvedSubtleSeparatorColor()];
        [codeView setDocumentCornerRadius:OMDPreviewPageCornerRadius];
        [codeView setDocumentBorderWidth:OMDPreviewPageBorderWidth];
        [codeView setCodeBlockRanges:[_renderer codeBlockRanges]];
        [codeView setCodeBlockBackgroundColor:[NSColor colorWithCalibratedRed:(239.0 / 255.0)
                                                                         green:(243.0 / 255.0)
                                                                          blue:(247.0 / 255.0)
                                                                         alpha:1.0]];
        [codeView setCodeBlockBorderColor:[NSColor colorWithCalibratedRed:(208.0 / 255.0)
                                                                     green:(215.0 / 255.0)
                                                                      blue:(222.0 / 255.0)
                                                                     alpha:1.0]];
        [codeView setCodeBlockPadding:NSMakeSize(20.0, 14.0)];
        [codeView setCodeBlockCornerRadius:6.0];
        [codeView setCodeBlockBorderWidth:1.0];
        [codeView setBlockquoteRanges:[_renderer blockquoteRanges]];
        [codeView setBlockquoteLineColor:[NSColor colorWithCalibratedWhite:0.82 alpha:1.0]];
        [codeView setBlockquoteLineWidth:3.0];
        [codeView setNeedsDisplay:YES];
    }
    if (bg != nil) {
        [_textView setDrawsBackground:NO];
        [_previewScrollView setDrawsBackground:YES];
        [_previewScrollView setBackgroundColor:OMDResolvedChromeBackgroundColor()];
    } else {
        [_previewScrollView setDrawsBackground:YES];
        [_previewScrollView setBackgroundColor:OMDResolvedChromeBackgroundColor()];
    }
    _lastRenderedSourceRevision = revisionAtRenderStart;
    if (_viewerMode == OMDViewerModeSplit) {
        [self syncPreviewToSourceInteractionAnchor];
    }
    [self updatePreviewStatusIndicator];
    [self updateWindowTitle];
    if (_viewerMode == OMDViewerModeSplit && _sourceRevision > _lastRenderedSourceRevision) {
        [self scheduleLivePreviewRender];
    } else {
        [self setPreviewUpdating:NO];
    }
    NSTimeInterval totalMs = (OMDNow() - renderStart) * 1000.0;
    [self updateAdaptiveZoomDebounceWithRenderDurationMs:totalMs sampledAsZoomRender:sampledAsZoomRender];
    if (perfLogging) {
        NSLog(@"[Perf][Viewer] total=%.1fms markdown=%.1fms apply=%.1fms post=%.1fms zoom=%.2f charsIn=%lu charsOut=%lu",
              totalMs,
              markdownMs,
              applyMs,
              (OMDNow() - postStart) * 1000.0,
              _zoomScale,
              (unsigned long)[previewMarkdown length],
              (unsigned long)[rendered length]);
    }
}

- (void)logPreviewStyleDiagnosticsForRenderedString:(NSAttributedString *)rendered
{
    if (!OMDPreviewStyleDiagnosticsEnabled() || rendered == nil || [rendered length] == 0) {
        return;
    }

    static NSArray *tokens = nil;
    if (tokens == nil) {
        tokens = [[NSArray alloc] initWithObjects:@"italic sample", @"remove sample", @"bold sample", nil];
    }

    NSString *text = [rendered string];
    for (NSString *token in tokens) {
        NSRange range = [text rangeOfString:token];
        if (range.location == NSNotFound) {
            NSLog(@"[StyleDiag] token='%@' not found in preview text", token);
            continue;
        }

        NSDictionary *attrs = [rendered attributesAtIndex:range.location effectiveRange:NULL];
        NSFont *font = [attrs objectForKey:NSFontAttributeName];
        NSNumber *obliqueness = [attrs objectForKey:NSObliquenessAttributeName];
        NSNumber *strikethrough = [attrs objectForKey:NSStrikethroughStyleAttributeName];
        NSUInteger traits = 0;
        if (font != nil) {
            traits = [[NSFontManager sharedFontManager] traitsOfFont:font];
        }

        NSLog(@"[StyleDiag] token='%@' font='%@' traits=%lu obliqueness=%@ strikethrough=%@ attrs=%@",
              token,
              (font != nil ? [font fontName] : @"<nil>"),
              (unsigned long)traits,
              (obliqueness != nil ? [obliqueness description] : @"<nil>"),
              (strikethrough != nil ? [strikethrough description] : @"<nil>"),
              attrs);
    }
}

- (void)clearPreviewPresentation
{
    if (_textView == nil || _previewScrollView == nil || _previewCanvasView == nil) {
        return;
    }

    [self hideCopyFeedback];
    if (_codeBlockButtons != nil) {
        for (NSButton *button in _codeBlockButtons) {
            [button removeFromSuperview];
        }
        [_codeBlockButtons removeAllObjects];
    }

    _isProgrammaticPreviewUpdate = YES;
    NSAttributedString *empty = [[[NSAttributedString alloc] initWithString:@""] autorelease];
    [[_textView textStorage] setAttributedString:empty];
    _isProgrammaticPreviewUpdate = NO;

    if ([_textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *previewTextView = (OMDTextView *)_textView;
        [previewTextView setDocumentBackgroundColor:nil];
        [previewTextView setDocumentBorderColor:nil];
        [previewTextView setCodeBlockRanges:nil];
        [previewTextView setCodeBlockBackgroundColor:nil];
        [previewTextView setCodeBlockBorderColor:nil];
        [previewTextView setBlockquoteRanges:nil];
        [previewTextView setBlockquoteLineColor:nil];
        [previewTextView setNeedsDisplay:YES];
    }

    [_previewScrollView setDrawsBackground:YES];
    [_previewScrollView setBackgroundColor:OMDResolvedChromeBackgroundColor()];
    if ([_previewCanvasView isKindOfClass:[OMDFlippedFillView class]]) {
        [(OMDFlippedFillView *)_previewCanvasView setFillColor:OMDResolvedChromeBackgroundColor()];
    }

    NSRect clipBounds = [self currentPreviewClipBounds];
    CGFloat width = clipBounds.size.width > 1.0 ? clipBounds.size.width : 1.0;
    CGFloat height = clipBounds.size.height > 1.0 ? clipBounds.size.height : 1.0;
    NSRect previousTextFrame = [_textView frame];
    [_previewCanvasView setFrameSize:NSMakeSize(width, height)];
    NSRect targetFrame = NSIntegralRect(NSMakeRect(0.0, 0.0, width, height));
    [_textView setFrame:targetFrame];
    NSRect dirtyRect = NSUnionRect(previousTextFrame, targetFrame);
    dirtyRect = NSInsetRect(dirtyRect, -2.0, -2.0);
    [_previewCanvasView setNeedsDisplayInRect:dirtyRect];
    [_textView setNeedsDisplay:YES];
    [self scrollScrollViewToDocumentTop:_previewScrollView];
}

- (void)applyWindowsWindowIconsIfPossible
{
#if defined(_WIN32)
    if (_window == nil || ![_window respondsToSelector:@selector(windowHandle)]) {
        return;
    }

    HWND hwnd = (HWND)[_window windowHandle];
    if (hwnd == NULL) {
        return;
    }

    HINSTANCE instance = GetModuleHandleW(NULL);
    if (instance == NULL) {
        return;
    }

    HICON largeIcon = (HICON)LoadImageW(instance,
                                        MAKEINTRESOURCEW(1),
                                        IMAGE_ICON,
                                        GetSystemMetrics(SM_CXICON),
                                        GetSystemMetrics(SM_CYICON),
                                        LR_DEFAULTCOLOR);
    HICON smallIcon = (HICON)LoadImageW(instance,
                                        MAKEINTRESOURCEW(1),
                                        IMAGE_ICON,
                                        GetSystemMetrics(SM_CXSMICON),
                                        GetSystemMetrics(SM_CYSMICON),
                                        LR_DEFAULTCOLOR);
    if (largeIcon != NULL) {
        SendMessageW(hwnd, WM_SETICON, ICON_BIG, (LPARAM)largeIcon);
    }
    if (smallIcon != NULL) {
        SendMessageW(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)smallIcon);
    }
#endif
}

- (void)updateAdaptiveZoomDebounceWithRenderDurationMs:(NSTimeInterval)durationMs
                                     sampledAsZoomRender:(BOOL)isZoomRender
{
    if (!isZoomRender) {
        _zoomFastRenderStreak = 0;
        return;
    }

    if (durationMs >= OMDZoomAdaptiveSlowRenderThresholdMs) {
        _zoomUsesDebouncedRendering = YES;
        _zoomFastRenderStreak = 0;
        return;
    }

    if (!_zoomUsesDebouncedRendering) {
        return;
    }

    if (durationMs <= OMDZoomAdaptiveFastRenderThresholdMs) {
        _zoomFastRenderStreak += 1;
        if (_zoomFastRenderStreak >= OMDZoomAdaptiveFastRenderStreakRequired) {
            _zoomUsesDebouncedRendering = NO;
            _zoomFastRenderStreak = 0;
        }
        return;
    }

    _zoomFastRenderStreak = 0;
}

- (void)updateRendererLayoutWidth
{
    CGFloat width = [self currentPreviewLayoutWidth];
    [_renderer setLayoutWidth:width];
    _lastRenderedLayoutWidth = width;
}

- (void)windowDidResize:(NSNotification *)notification
{
    (void)notification;
    [self layoutWorkspaceChrome];
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }
    [self requestInteractiveRenderForLayoutWidthIfNeeded];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if ([notification object] != _window) {
        return;
    }
    [self refreshCurrentDocumentDiskStateAllowPrompt:YES];
}

- (CGFloat)splitView:(NSSplitView *)splitView
constrainSplitPosition:(CGFloat)proposedPosition
         ofSubviewAt:(NSInteger)dividerIndex
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    if (splitView == _workspaceSplitView) {
        if (!_explorerSidebarVisible) {
            return 0.0;
        }
        CGFloat width = [_workspaceSplitView bounds].size.width;
        CGFloat divider = [_workspaceSplitView dividerThickness];
        CGFloat available = width - divider;
        CGFloat minSidebar = 170.0;
        CGFloat minMain = (metrics.scale > 1.05 ? 400.0 : 360.0);
        CGFloat minPosition = minSidebar;
        CGFloat maxPosition = available - minMain;
        if (maxPosition < minPosition) {
            return floor(available * 0.32);
        }
        if (proposedPosition < minPosition) {
            return minPosition;
        }
        if (proposedPosition > maxPosition) {
            return maxPosition;
        }
        return proposedPosition;
    }

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

- (NSRect)splitView:(NSSplitView *)splitView
      effectiveRect:(NSRect)proposedEffectiveRect
       forDrawnRect:(NSRect)drawnRect
   ofDividerAtIndex:(NSInteger)dividerIndex
{
    NSRect effectiveRect = proposedEffectiveRect;
    CGFloat extra = 0.0;

    (void)dividerIndex;

    if (splitView != _splitView && splitView != _workspaceSplitView) {
        return proposedEffectiveRect;
    }

    effectiveRect = drawnRect;
    if ([splitView isVertical]) {
        extra = MAX(0.0, OMDWin11SplitDividerHitThickness - NSWidth(effectiveRect));
        effectiveRect.origin.x -= floor(extra / 2.0);
        effectiveRect.size.width += extra;
    } else {
        extra = MAX(0.0, OMDWin11SplitDividerHitThickness - NSHeight(effectiveRect));
        effectiveRect.origin.y -= floor(extra / 2.0);
        effectiveRect.size.height += extra;
    }

    return NSIntersectionRect(effectiveRect, [splitView bounds]);
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    id object = [notification object];
    if (object == _workspaceSplitView) {
        if (_explorerSidebarVisible) {
            NSArray *subviews = [_workspaceSplitView subviews];
            if ([subviews count] > 0) {
                CGFloat sidebarWidth = NSWidth([[subviews objectAtIndex:0] frame]);
                if (sidebarWidth > 20.0) {
                    _explorerSidebarLastVisibleWidth = sidebarWidth;
                }
            }
        }
        [self layoutWorkspaceChrome];
        return;
    }

    if (object != _splitView) {
        return;
    }

    CGFloat available = -1.0;
    CGFloat width = [_splitView bounds].size.width;
    CGFloat divider = [_splitView dividerThickness];
    if (width > divider) {
        available = width - divider;
    }
    BOOL canCompareWidth = (_lastObservedSplitAvailableWidth >= 0.0 && available >= 0.0);
    BOOL widthChanged = (canCompareWidth &&
                         fabs(available - _lastObservedSplitAvailableWidth) > 0.5);

    [self layoutSourceEditorContainer];
    // Preserve the user-selected split ratio when the window width changes.
    // Width-driven min-size clamping should not overwrite the stored ratio.
    if (!_isApplyingSplitViewRatio && canCompareWidth && !widthChanged) {
        [self persistSplitViewRatio];
    }
    if (available >= 0.0) {
        _lastObservedSplitAvailableWidth = available;
    }
    [self updatePreviewDocumentGeometry];
    [self updateCodeBlockButtons];
    [self requestInteractiveRenderForLayoutWidthIfNeeded];
    [_splitView setNeedsDisplay:YES];
}

- (void)requestInteractiveRender
{
    if (_currentMarkdown == nil) {
        [self setPreviewUpdating:NO];
        return;
    }
    if (![self isPreviewVisible]) {
        [self setPreviewUpdating:NO];
        return;
    }
    // Trailing-edge debounce: rapid UI events collapse to one render.
    [self scheduleInteractiveRenderAfterDelay:OMDInteractiveRenderDebounceInterval];
}

- (void)requestInteractiveRenderForLayoutWidthIfNeeded
{
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }

    CGFloat width = [self currentPreviewLayoutWidth];
    if (_lastRenderedLayoutWidth >= 0.0 && fabs(width - _lastRenderedLayoutWidth) < 0.5) {
        return;
    }
    [self requestInteractiveRender];
}

- (CGFloat)currentPreviewLayoutWidth
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    if (_textView == nil) {
        return 0.0;
    }

    NSRect bounds = NSZeroRect;
    if (_previewScrollView != nil) {
        bounds = [self currentPreviewClipBounds];
    } else {
        bounds = [_textView bounds];
    }
    NSSize inset = [_textView textContainerInset];
    NSTextContainer *container = [_textView textContainer];
    CGFloat padding = container != nil ? [container lineFragmentPadding] : 0.0;
    CGFloat fullWidth = bounds.size.width - (inset.width * 2.0) - (padding * 2.0);
    CGFloat width = fullWidth - (metrics.previewCanvasMargin * 2.0);
    if (width < 360.0) {
        width = fullWidth;
    }
    if (width > OMDPreviewMaximumLayoutWidth) {
        width = OMDPreviewMaximumLayoutWidth;
    }
    if (width < 0.0) {
        width = 0.0;
    }
    return width;
}

- (NSRect)currentPreviewClipBounds
{
    if (_previewScrollView == nil) {
        return NSZeroRect;
    }

    if ([_previewScrollView respondsToSelector:@selector(tile)]) {
        [_previewScrollView tile];
    }

    NSClipView *clipView = [_previewScrollView contentView];
    NSRect clipBounds = (clipView != nil ? [clipView bounds] : NSZeroRect);
    NSRect clipFrame = (clipView != nil ? [clipView frame] : NSZeroRect);
    NSSize contentSize = [_previewScrollView contentSize];
    if (clipFrame.size.width > clipBounds.size.width) {
        clipBounds.size.width = clipFrame.size.width;
    }
    if (clipFrame.size.height > clipBounds.size.height) {
        clipBounds.size.height = clipFrame.size.height;
    }
    if (contentSize.width > clipBounds.size.width) {
        clipBounds.size.width = contentSize.width;
    }
    if (contentSize.height > clipBounds.size.height) {
        clipBounds.size.height = contentSize.height;
    }
    return clipBounds;
}

- (void)updatePreviewDocumentGeometry
{
    if (_textView == nil || _previewScrollView == nil || _previewCanvasView == nil) {
        return;
    }

    NSTextContainer *container = [_textView textContainer];
    NSLayoutManager *layoutManager = [_textView layoutManager];
    if (container == nil || layoutManager == nil) {
        return;
    }

    NSClipView *clipView = [_previewScrollView contentView];
    NSRect clipBounds = [self currentPreviewClipBounds];
    NSSize inset = [_textView textContainerInset];
    CGFloat padding = [container lineFragmentPadding];
    CGFloat layoutWidth = [self currentPreviewLayoutWidth];
    if (layoutWidth < 1.0) {
        layoutWidth = 1.0;
    }

    [container setContainerSize:NSMakeSize(layoutWidth, FLT_MAX)];
    [layoutManager ensureLayoutForTextContainer:container];
    NSRect usedRect = [layoutManager usedRectForTextContainer:container];

    CGFloat contentWidth = ceil(usedRect.size.width + (inset.width * 2.0) + (padding * 2.0) + 2.0);
    CGFloat targetWidth = ceil(layoutWidth + (inset.width * 2.0) + (padding * 2.0) + 2.0);
    if (contentWidth > targetWidth) {
        targetWidth = contentWidth;
    }
    if (targetWidth < 1.0) {
        targetWidth = 1.0;
    }

    CGFloat contentHeight = ceil(usedRect.size.height + (inset.height * 2.0) + 2.0);
    CGFloat targetHeight = clipBounds.size.height;
    if (contentHeight > targetHeight) {
        targetHeight = contentHeight;
    }
    if (targetHeight < 1.0) {
        targetHeight = 1.0;
    }
    if (targetHeight < clipBounds.size.height) {
        targetHeight = clipBounds.size.height;
    }

    CGFloat canvasWidth = clipBounds.size.width;
    if (targetWidth > canvasWidth) {
        canvasWidth = targetWidth;
    }
    if (canvasWidth < 1.0) {
        canvasWidth = 1.0;
    }

    CGFloat canvasHeight = clipBounds.size.height;
    if (targetHeight > canvasHeight) {
        canvasHeight = targetHeight;
    }
    if (canvasHeight < 1.0) {
        canvasHeight = 1.0;
    }

    NSRect canvasFrame = [_previewCanvasView frame];
    BOOL canvasFrameChanged = (fabs(canvasFrame.size.width - canvasWidth) > 0.5 ||
                               fabs(canvasFrame.size.height - canvasHeight) > 0.5);
    if (canvasFrameChanged) {
        [_previewCanvasView setFrameSize:NSMakeSize(canvasWidth, canvasHeight)];
    }

    CGFloat textX = 0.0;
    if (canvasWidth > targetWidth) {
        CGFloat slackWidth = canvasWidth - targetWidth;
        if (_viewerMode == OMDViewerModeSplit) {
            CGFloat leadingGutter = floor(MIN(slackWidth, 6.0));
            textX = leadingGutter;
        } else {
            textX = floor(slackWidth * 0.5);
        }
    }
    NSRect frame = [_textView frame];
    NSRect targetFrame = NSIntegralRect(NSMakeRect(textX, 0.0, targetWidth, targetHeight));
    BOOL textFrameChanged = (fabs(frame.origin.x - targetFrame.origin.x) > 0.5 ||
                             fabs(frame.origin.y - targetFrame.origin.y) > 0.5 ||
                             fabs(frame.size.width - targetFrame.size.width) > 0.5 ||
                             fabs(frame.size.height - targetFrame.size.height) > 0.5);
    if (textFrameChanged) {
        [_textView setFrame:targetFrame];
    }
    if (canvasFrameChanged || textFrameChanged) {
        if ([_previewCanvasView isKindOfClass:[OMDFlippedFillView class]]) {
            [(OMDFlippedFillView *)_previewCanvasView setFillColor:OMDResolvedChromeBackgroundColor()];
        }
        if (canvasFrameChanged) {
            [_previewCanvasView setNeedsDisplay:YES];
        }
        if (textFrameChanged) {
            NSRect dirtyRect = NSUnionRect(frame, targetFrame);
            dirtyRect = NSInsetRect(dirtyRect, -2.0, -2.0);
            [_previewCanvasView setNeedsDisplayInRect:dirtyRect];
        }
        [_textView setNeedsDisplay:YES];
    }

    if (_viewerMode == OMDViewerModeSplit && targetWidth <= clipBounds.size.width + 0.5) {
        NSPoint clipOrigin = [clipView bounds].origin;
        if (clipOrigin.x > 0.5) {
            clipOrigin.x = 0.0;
            [clipView scrollToPoint:clipOrigin];
            [_previewScrollView reflectScrolledClipView:clipView];
        }
    }
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
    [self setPreviewUpdating:YES];
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

- (void)remoteImagesDidWarm:(NSNotification *)notification
{
    (void)notification;
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }
    [self requestInteractiveRender];
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
    [self setPreviewUpdating:YES];
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

- (OMDSplitSyncMode)currentSplitSyncMode
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDSplitSyncModeDefaultsKey];
    if ([value respondsToSelector:@selector(integerValue)]) {
        return OMDSplitSyncModeFromInteger([value integerValue]);
    }
    return OMDSplitSyncModeLinkedScrolling;
}

- (void)setSplitSyncModePreference:(OMDSplitSyncMode)mode
{
    mode = OMDSplitSyncModeFromInteger(mode);
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)mode
                                               forKey:OMDSplitSyncModeDefaultsKey];
    if (_viewerMode == OMDViewerModeSplit && _sourceRevision == _lastRenderedSourceRevision) {
        if (mode == OMDSplitSyncModeLinkedScrolling) {
            [self syncPreviewToSourceScrollPosition];
        } else if (mode == OMDSplitSyncModeCaretSelectionFollow) {
            [self syncPreviewToSourceSelection];
        }
    }
    [self syncPreferencesPanelFromSettings];
}

- (void)setSplitSyncModeUnlinked:(id)sender
{
    [self setSplitSyncModePreference:OMDSplitSyncModeUnlinked];
}

- (void)setSplitSyncModeLinkedScrolling:(id)sender
{
    [self setSplitSyncModePreference:OMDSplitSyncModeLinkedScrolling];
}

- (void)setSplitSyncModeCaretSelectionFollow:(id)sender
{
    [self setSplitSyncModePreference:OMDSplitSyncModeCaretSelectionFollow];
}

- (BOOL)usesLinkedScrolling
{
    return [self currentSplitSyncMode] == OMDSplitSyncModeLinkedScrolling;
}

- (BOOL)usesCaretSelectionSync
{
    return [self currentSplitSyncMode] == OMDSplitSyncModeCaretSelectionFollow;
}

- (BOOL)isFormattingBarEnabledPreference
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDShowFormattingBarDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return OMDDefaultFormattingBarEnabledForMode([self effectiveLayoutDensityMode]);
}

- (void)setFormattingBarEnabledPreference:(BOOL)enabled
{
    _showFormattingBar = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                             forKey:OMDShowFormattingBarDefaultsKey];
    [self layoutSourceEditorContainer];
    [self updateFormattingBarContextState];
}

- (BOOL)isFormattingBarVisibleInCurrentMode
{
    if (!_showFormattingBar) {
        return NO;
    }
    return _viewerMode == OMDViewerModeEdit || _viewerMode == OMDViewerModeSplit;
}

- (void)toggleFormattingBar:(id)sender
{
    (void)sender;
    [self setFormattingBarEnabledPreference:![self isFormattingBarEnabledPreference]];
}

- (void)setupFormattingBar
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    if (_sourceEditorContainer == nil) {
        return;
    }
    if (_formattingBarView != nil) {
        return;
    }

    _formattingBarView = [[OMDFormattingBarView alloc] initWithFrame:NSMakeRect(0.0,
                                                                                 0.0,
                                                                                 NSWidth([_sourceEditorContainer bounds]),
                                                                                 metrics.formattingBarHeight)];
    [_formattingBarView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_formattingBarView setFillColor:OMDResolvedControlBackgroundColor()];
    [_formattingBarView setBorderColor:OMDResolvedSubtleSeparatorColor()];
    [_sourceEditorContainer addSubview:_formattingBarView];

    _formatCommandButtons = [[NSMutableDictionary alloc] init];

    CGFloat x = metrics.formattingBarInsetX;
    NSFont *buttonFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 11.5 : metrics.formattingBarFontSize)];
    CGFloat compactPadding = (metrics.scale > 1.05 ? 8.0 : 7.0);
    CGFloat narrowPadding = (metrics.scale > 1.05 ? 7.0 : 6.0);

    CGFloat headingPWidth = OMDControlWidthForTitle(@"P", buttonFont, 30.0, narrowPadding);
    CGFloat headingLevelWidth = OMDControlWidthForTitle(@"H6", buttonFont, 36.0, narrowPadding);
    CGFloat headingWidth = headingPWidth + (headingLevelWidth * 6.0);
    _formatHeadingControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                 0.0,
                                                                                 headingWidth,
                                                                                 metrics.formattingBarControlHeight)];
    [_formatHeadingControl setSegmentCount:7];
    [_formatHeadingControl setSegmentStyle:NSSegmentStyleRounded];
    [[_formatHeadingControl cell] setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    [_formatHeadingControl setLabel:@"P" forSegment:0];
    [_formatHeadingControl setLabel:@"H1" forSegment:1];
    [_formatHeadingControl setLabel:@"H2" forSegment:2];
    [_formatHeadingControl setLabel:@"H3" forSegment:3];
    [_formatHeadingControl setLabel:@"H4" forSegment:4];
    [_formatHeadingControl setLabel:@"H5" forSegment:5];
    [_formatHeadingControl setLabel:@"H6" forSegment:6];
    [_formatHeadingControl setWidth:headingPWidth forSegment:0];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:1];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:2];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:3];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:4];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:5];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:6];
    [[_formatHeadingControl cell] setToolTip:@"Paragraph" forSegment:0];
    [[_formatHeadingControl cell] setToolTip:@"Heading 1" forSegment:1];
    [[_formatHeadingControl cell] setToolTip:@"Heading 2" forSegment:2];
    [[_formatHeadingControl cell] setToolTip:@"Heading 3" forSegment:3];
    [[_formatHeadingControl cell] setToolTip:@"Heading 4" forSegment:4];
    [[_formatHeadingControl cell] setToolTip:@"Heading 5" forSegment:5];
    [[_formatHeadingControl cell] setToolTip:@"Heading 6" forSegment:6];
    if ([_formatHeadingControl respondsToSelector:@selector(setFont:)]) {
        [_formatHeadingControl setFont:buttonFont];
    }
    [_formatHeadingControl setTarget:self];
    [_formatHeadingControl setAction:@selector(formattingHeadingControlChanged:)];
    [_formatHeadingControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:_formatHeadingControl];

    x += headingWidth + metrics.formattingBarGroupSpacing;

    CGFloat boldWidth = OMDControlWidthForTitle(@"B", buttonFont, 32.0, narrowPadding);
    CGFloat italicWidth = OMDControlWidthForTitle(@"I", buttonFont, 32.0, narrowPadding);
    CGFloat strikeWidth = OMDControlWidthForTitle(@"S", buttonFont, 32.0, narrowPadding);
    CGFloat inlineCodeWidth = OMDControlWidthForTitle(@"Code", buttonFont, 50.0, compactPadding);
    CGFloat inlineWidth = boldWidth + italicWidth + strikeWidth + inlineCodeWidth;
    NSSegmentedControl *inlineControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                               0.0,
                                                                                               inlineWidth,
                                                                                               metrics.formattingBarControlHeight)] autorelease];
    [inlineControl setSegmentCount:4];
    [inlineControl setSegmentStyle:NSSegmentStyleRounded];
    [[inlineControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [inlineControl setLabel:@"B" forSegment:0];
    [inlineControl setLabel:@"I" forSegment:1];
    [inlineControl setLabel:@"S" forSegment:2];
    [inlineControl setLabel:@"Code" forSegment:3];
    [inlineControl setWidth:boldWidth forSegment:0];
    [inlineControl setWidth:italicWidth forSegment:1];
    [inlineControl setWidth:strikeWidth forSegment:2];
    [inlineControl setWidth:inlineCodeWidth forSegment:3];
    [[inlineControl cell] setToolTip:@"Bold (Ctrl/Cmd+B)" forSegment:0];
    [[inlineControl cell] setToolTip:@"Italic (Ctrl/Cmd+I)" forSegment:1];
    [[inlineControl cell] setToolTip:@"Strikethrough" forSegment:2];
    [[inlineControl cell] setToolTip:@"Inline code" forSegment:3];
    if ([inlineControl respondsToSelector:@selector(setFont:)]) {
        [inlineControl setFont:buttonFont];
    }
    [inlineControl setTag:1];
    [inlineControl setTarget:self];
    [inlineControl setAction:@selector(formattingCommandGroupChanged:)];
    [inlineControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:inlineControl];
    [_formatCommandButtons setObject:inlineControl forKey:@"inline"];

    x += NSWidth([inlineControl frame]) + metrics.formattingBarGroupSpacing;

    NSSegmentedControl *mediaControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                              0.0,
                                                                                              0.0,
                                                                                              metrics.formattingBarControlHeight)] autorelease];
    [mediaControl setSegmentCount:2];
    [mediaControl setSegmentStyle:NSSegmentStyleRounded];
    [[mediaControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [mediaControl setLabel:@"Link" forSegment:0];
    [mediaControl setLabel:@"Image" forSegment:1];
    CGFloat linkWidth = OMDControlWidthForTitle(@"Link", buttonFont, 46.0, compactPadding);
    CGFloat imageWidth = OMDControlWidthForTitle(@"Image", buttonFont, 54.0, compactPadding);
    [mediaControl setFrame:NSMakeRect(x, 0.0, linkWidth + imageWidth, metrics.formattingBarControlHeight)];
    [mediaControl setWidth:linkWidth forSegment:0];
    [mediaControl setWidth:imageWidth forSegment:1];
    [[mediaControl cell] setToolTip:@"Insert link" forSegment:0];
    [[mediaControl cell] setToolTip:@"Insert image" forSegment:1];
    if ([mediaControl respondsToSelector:@selector(setFont:)]) {
        [mediaControl setFont:buttonFont];
    }
    [mediaControl setTag:2];
    [mediaControl setTarget:self];
    [mediaControl setAction:@selector(formattingCommandGroupChanged:)];
    [mediaControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:mediaControl];
    [_formatCommandButtons setObject:mediaControl forKey:@"media"];

    x += NSWidth([mediaControl frame]) + metrics.formattingBarGroupSpacing;

    NSSegmentedControl *listControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                             0.0,
                                                                                             0.0,
                                                                                             metrics.formattingBarControlHeight)] autorelease];
    [listControl setSegmentCount:4];
    [listControl setSegmentStyle:NSSegmentStyleRounded];
    [[listControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [listControl setLabel:@"-" forSegment:0];
    [listControl setLabel:@"1." forSegment:1];
    [listControl setLabel:@"[]" forSegment:2];
    [listControl setLabel:@">" forSegment:3];
    CGFloat bulletWidth = OMDControlWidthForTitle(@"-", buttonFont, 32.0, narrowPadding);
    CGFloat numberWidth = OMDControlWidthForTitle(@"1.", buttonFont, 36.0, narrowPadding);
    CGFloat taskWidth = OMDControlWidthForTitle(@"[]", buttonFont, 40.0, narrowPadding);
    CGFloat quoteWidth = OMDControlWidthForTitle(@">", buttonFont, 32.0, narrowPadding);
    [listControl setFrame:NSMakeRect(x,
                                     0.0,
                                     bulletWidth + numberWidth + taskWidth + quoteWidth,
                                     metrics.formattingBarControlHeight)];
    [listControl setWidth:bulletWidth forSegment:0];
    [listControl setWidth:numberWidth forSegment:1];
    [listControl setWidth:taskWidth forSegment:2];
    [listControl setWidth:quoteWidth forSegment:3];
    [[listControl cell] setToolTip:@"Toggle bullet list" forSegment:0];
    [[listControl cell] setToolTip:@"Toggle numbered list" forSegment:1];
    [[listControl cell] setToolTip:@"Toggle task list" forSegment:2];
    [[listControl cell] setToolTip:@"Toggle block quote" forSegment:3];
    if ([listControl respondsToSelector:@selector(setFont:)]) {
        [listControl setFont:buttonFont];
    }
    [listControl setTag:3];
    [listControl setTarget:self];
    [listControl setAction:@selector(formattingCommandGroupChanged:)];
    [listControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:listControl];
    [_formatCommandButtons setObject:listControl forKey:@"lists"];

    x += NSWidth([listControl frame]) + metrics.formattingBarGroupSpacing;

    NSSegmentedControl *insertControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                               0.0,
                                                                                               0.0,
                                                                                               metrics.formattingBarControlHeight)] autorelease];
    [insertControl setSegmentCount:3];
    [insertControl setSegmentStyle:NSSegmentStyleRounded];
    [[insertControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [insertControl setLabel:@"{}" forSegment:0];
    [insertControl setLabel:@"Tbl" forSegment:1];
    [insertControl setLabel:@"HR" forSegment:2];
    CGFloat codeBlockWidth = OMDControlWidthForTitle(@"{}", buttonFont, 40.0, narrowPadding);
    CGFloat tableWidth = OMDControlWidthForTitle(@"Tbl", buttonFont, 42.0, compactPadding);
    CGFloat ruleWidth = OMDControlWidthForTitle(@"HR", buttonFont, 40.0, narrowPadding);
    [insertControl setFrame:NSMakeRect(x,
                                       0.0,
                                       codeBlockWidth + tableWidth + ruleWidth,
                                       metrics.formattingBarControlHeight)];
    [insertControl setWidth:codeBlockWidth forSegment:0];
    [insertControl setWidth:tableWidth forSegment:1];
    [insertControl setWidth:ruleWidth forSegment:2];
    [[insertControl cell] setToolTip:@"Insert fenced code block" forSegment:0];
    [[insertControl cell] setToolTip:@"Insert table" forSegment:1];
    [[insertControl cell] setToolTip:@"Insert horizontal rule" forSegment:2];
    if ([insertControl respondsToSelector:@selector(setFont:)]) {
        [insertControl setFont:buttonFont];
    }
    [insertControl setTag:4];
    [insertControl setTarget:self];
    [insertControl setAction:@selector(formattingCommandGroupChanged:)];
    [insertControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:insertControl];
    [_formatCommandButtons setObject:insertControl forKey:@"insert"];

    [self updateFormattingBarContextState];
}

- (CGFloat)layoutFormattingBarControlsForWidth:(CGFloat)containerWidth
                                  applyFrames:(BOOL)applyFrames
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    CGFloat controlHeight = metrics.formattingBarControlHeight;
    CGFloat insetX = metrics.formattingBarInsetX;
    CGFloat rowInsetY = (metrics.scale > 1.05 ? 6.0 : 5.0);
    CGFloat rowGap = (metrics.scale > 1.05 ? 6.0 : 4.0);
    CGFloat availableWidth = containerWidth - (insetX * 2.0);

    NSSegmentedControl *inlineControl = [_formatCommandButtons objectForKey:@"inline"];
    NSSegmentedControl *mediaControl = [_formatCommandButtons objectForKey:@"media"];
    NSSegmentedControl *listControl = [_formatCommandButtons objectForKey:@"lists"];
    NSSegmentedControl *insertControl = [_formatCommandButtons objectForKey:@"insert"];

    CGFloat headingWidth = (_formatHeadingControl != nil ? NSWidth([_formatHeadingControl frame]) : 0.0);
    CGFloat inlineWidth = (inlineControl != nil ? NSWidth([inlineControl frame]) : 0.0);
    CGFloat mediaWidth = (mediaControl != nil ? NSWidth([mediaControl frame]) : 0.0);
    CGFloat listWidth = (listControl != nil ? NSWidth([listControl frame]) : 0.0);
    CGFloat insertWidth = (insertControl != nil ? NSWidth([insertControl frame]) : 0.0);

    CGFloat oneRowWidth = headingWidth +
                          inlineWidth +
                          mediaWidth +
                          listWidth +
                          insertWidth +
                          (metrics.formattingBarGroupSpacing * 4.0);
    BOOL usesTwoRows = oneRowWidth > availableWidth;

    CGFloat barHeight = rowInsetY + controlHeight + rowInsetY;
    if (usesTwoRows) {
        barHeight = rowInsetY + controlHeight + rowGap + controlHeight + rowInsetY;
    }
    if (!applyFrames) {
        return ceil(barHeight);
    }

    if (usesTwoRows) {
        CGFloat topRowY = barHeight - rowInsetY - controlHeight;
        CGFloat bottomRowY = rowInsetY;

        CGFloat topX = insetX;
        if (_formatHeadingControl != nil) {
            [_formatHeadingControl setFrame:NSMakeRect(topX,
                                                       topRowY,
                                                       headingWidth,
                                                       controlHeight)];
            topX += headingWidth + metrics.formattingBarGroupSpacing;
        }
        if (inlineControl != nil) {
            [inlineControl setFrame:NSMakeRect(topX,
                                               topRowY,
                                               inlineWidth,
                                               controlHeight)];
        }

        CGFloat bottomX = insetX;
        if (mediaControl != nil) {
            [mediaControl setFrame:NSMakeRect(bottomX,
                                              bottomRowY,
                                              mediaWidth,
                                              controlHeight)];
            bottomX += mediaWidth + metrics.formattingBarGroupSpacing;
        }
        if (listControl != nil) {
            [listControl setFrame:NSMakeRect(bottomX,
                                             bottomRowY,
                                             listWidth,
                                             controlHeight)];
            bottomX += listWidth + metrics.formattingBarGroupSpacing;
        }
        if (insertControl != nil) {
            [insertControl setFrame:NSMakeRect(bottomX,
                                               bottomRowY,
                                               insertWidth,
                                               controlHeight)];
        }
    } else {
        CGFloat controlY = floor((barHeight - controlHeight) / 2.0);
        CGFloat currentX = insetX;
        NSArray *orderedControls = [NSArray arrayWithObjects:
                                    _formatHeadingControl,
                                    inlineControl,
                                    mediaControl,
                                    listControl,
                                    insertControl,
                                    nil];
        NSEnumerator *enumerator = [orderedControls objectEnumerator];
        NSSegmentedControl *control = nil;
        while ((control = [enumerator nextObject]) != nil) {
            CGFloat controlWidth = NSWidth([control frame]);
            [control setFrame:NSMakeRect(currentX,
                                         controlY,
                                         controlWidth,
                                         controlHeight)];
            currentX += controlWidth + metrics.formattingBarGroupSpacing;
        }
    }

    return ceil(barHeight);
}

- (void)rebuildFormattingBar
{
    [_formatHeadingControl release];
    _formatHeadingControl = nil;
    [_formatCommandButtons release];
    _formatCommandButtons = nil;
    if (_formattingBarView != nil) {
        [_formattingBarView removeFromSuperview];
        [_formattingBarView release];
        _formattingBarView = nil;
    }
    [self setupFormattingBar];
}

- (void)layoutSourceEditorContainer
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    if (_sourceEditorContainer == nil || _sourceScrollView == nil) {
        return;
    }

    NSRect bounds = [_sourceEditorContainer bounds];
    BOOL showBar = [self isFormattingBarVisibleInCurrentMode];
    CGFloat barHeight = 0.0;
    if (showBar) {
        if (_formattingBarView != nil) {
            barHeight = [self layoutFormattingBarControlsForWidth:NSWidth(bounds)
                                                      applyFrames:YES];
        } else {
            barHeight = metrics.formattingBarHeight;
        }
    }

    if (_formattingBarView != nil) {
        [_formattingBarView setHidden:!showBar];
        if (showBar) {
            NSRect barFrame = NSMakeRect(NSMinX(bounds),
                                         NSMaxY(bounds) - barHeight,
                                         NSWidth(bounds),
                                         barHeight);
            [_formattingBarView setFrame:NSIntegralRect(barFrame)];
        }
    }

    NSRect scrollFrame = bounds;
    if (barHeight > 0.0) {
        scrollFrame.size.height -= barHeight;
    }
    if (scrollFrame.size.height < 0.0) {
        scrollFrame.size.height = 0.0;
    }
    [_sourceScrollView setFrame:NSIntegralRect(scrollFrame)];
}

- (void)updateFormattingBarContextState
{
    BOOL enabled = [self isFormattingBarVisibleInCurrentMode] &&
                   _sourceTextView != nil &&
                   !_currentDocumentReadOnly;
    if (_formatHeadingControl != nil) {
        [_formatHeadingControl setEnabled:enabled];
        if (!enabled) {
            OMDClearSegmentedControlSelection(_formatHeadingControl);
        }
    }
    NSEnumerator *enumerator = [_formatCommandButtons objectEnumerator];
    id control = nil;
    while ((control = [enumerator nextObject]) != nil) {
        if ([control respondsToSelector:@selector(setEnabled:)]) {
            [control setEnabled:enabled];
        }
        if (!enabled &&
            [control respondsToSelector:@selector(setSelectedSegment:)]) {
            OMDClearSegmentedControlSelection(control);
        }
    }

    if (!enabled || _formatHeadingControl == nil || _sourceTextView == nil) {
        return;
    }

    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }
    NSRange selection = [_sourceTextView selectedRange];
    if (selection.location > [source length]) {
        selection.location = [source length];
        selection.length = 0;
    }
    if (selection.length > [source length] - selection.location) {
        selection.length = [source length] - selection.location;
    }

    NSRange lineRange = [self sourceLineRangeForSelection:selection source:source];
    NSString *lineText = @"";
    if (lineRange.length > 0 && NSMaxRange(lineRange) <= [source length]) {
        lineText = [source substringWithRange:lineRange];
    }
    if ([lineText hasSuffix:@"\n"]) {
        lineText = [lineText substringToIndex:[lineText length] - 1];
    }
    NSInteger level = [self headingLevelForLine:lineText];
    if (level < 0) {
        level = 0;
    }
    if (level > 6) {
        level = 6;
    }
    [_formatHeadingControl setSelectedSegment:level];
}

- (void)setViewerMode:(OMDViewerMode)mode persistPreference:(BOOL)persistPreference
{
    OMDViewerMode previousMode = OMDViewerModeFromInteger(_viewerMode);
    mode = OMDViewerModeFromInteger(mode);
    NSString *sourceAnchorText = nil;
    NSUInteger sourceAnchorLocation = NSNotFound;
    BOOL preserveViewportAnchor = NO;

    if (_sourceTextView != nil) {
        sourceAnchorText = [_sourceTextView string];
    }
    if ((sourceAnchorText == nil || [sourceAnchorText length] == 0) && _currentMarkdown != nil) {
        sourceAnchorText = _currentMarkdown;
    }

    if (previousMode == OMDViewerModeRead && _textView != nil && sourceAnchorText != nil) {
        NSString *previewText = [[_textView textStorage] string];
        NSUInteger previewLocation = [self visibleCharacterIndexForTextView:_textView
                                                               inScrollView:_previewScrollView
                                                             verticalAnchor:OMDLinkedScrollViewportAnchor];
        sourceAnchorLocation = OMDMapTargetLocationWithBlockAnchors(sourceAnchorText,
                                                                    previewText,
                                                                    previewLocation,
                                                                    [_renderer blockAnchors]);
        preserveViewportAnchor = YES;
    } else if (previousMode == OMDViewerModeSplit && mode == OMDViewerModeRead) {
        if (_sourceTextView != nil) {
            sourceAnchorLocation = [self visibleCharacterIndexForTextView:_sourceTextView
                                                             inScrollView:_sourceScrollView
                                                           verticalAnchor:OMDLinkedScrollViewportAnchor];
            preserveViewportAnchor = YES;
        }
    } else if (previousMode == OMDViewerModeEdit || previousMode == OMDViewerModeSplit) {
        if (_sourceTextView != nil) {
            sourceAnchorLocation = [_sourceTextView selectedRange].location;
        }
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
        [self setPreviewUpdating:NO];
        if (_sourceTextView != nil) {
            if (sourceAnchorLocation != NSNotFound) {
                NSString *sourceText = [_sourceTextView string];
                NSUInteger sourceLength = [sourceText length];
                if (sourceAnchorLocation > sourceLength) {
                    sourceAnchorLocation = sourceLength;
                }
                _isProgrammaticSelectionSync = YES;
                [_sourceTextView setSelectedRange:NSMakeRange(sourceAnchorLocation, 0)];
                _isProgrammaticSelectionSync = NO;
                if (preserveViewportAnchor) {
                    [self scrollSourceToCharacterIndex:sourceAnchorLocation
                                        verticalAnchor:OMDLinkedScrollViewportAnchor];
                } else {
                    [_sourceTextView scrollRangeToVisible:NSMakeRange(sourceAnchorLocation, 0)];
                }
            }
            [_window makeFirstResponder:_sourceTextView];
        }
    } else if (_currentMarkdown != nil) {
        if (_viewerMode == OMDViewerModeSplit && _sourceTextView != nil && sourceAnchorLocation != NSNotFound) {
            NSString *sourceText = [_sourceTextView string];
            NSUInteger sourceLength = [sourceText length];
            if (sourceAnchorLocation > sourceLength) {
                sourceAnchorLocation = sourceLength;
            }
            _isProgrammaticSelectionSync = YES;
            [_sourceTextView setSelectedRange:NSMakeRange(sourceAnchorLocation, 0)];
            _isProgrammaticSelectionSync = NO;
            if (preserveViewportAnchor) {
                [self scrollSourceToCharacterIndex:sourceAnchorLocation
                                    verticalAnchor:OMDLinkedScrollViewportAnchor];
            } else {
                [_sourceTextView scrollRangeToVisible:NSMakeRange(sourceAnchorLocation, 0)];
            }
        }

        [self renderCurrentMarkdown];

        if (_viewerMode == OMDViewerModeSplit && _sourceTextView != nil) {
            [_window makeFirstResponder:_sourceTextView];
            [self syncPreviewToSourceInteractionAnchor];
        } else if (_viewerMode == OMDViewerModeRead && sourceAnchorLocation != NSNotFound) {
            NSString *sourceText = sourceAnchorText != nil ? sourceAnchorText : _currentMarkdown;
            NSString *previewText = [[_textView textStorage] string];
            NSUInteger previewLocation = OMDMapSourceLocationWithBlockAnchors(sourceText,
                                                                              sourceAnchorLocation,
                                                                              previewText,
                                                                              [_renderer blockAnchors]);
            if (preserveViewportAnchor) {
                [self scrollPreviewToCharacterIndex:previewLocation
                                     verticalAnchor:OMDLinkedScrollViewportAnchor];
            } else {
                if ([sourceText length] > 0 &&
                    sourceAnchorLocation >= [sourceText length] &&
                    [previewText length] > 0) {
                    previewLocation = [previewText length] - 1;
                }
                [self scrollPreviewToCharacterIndex:previewLocation];
            }
        }
    } else if (![self isPreviewVisible]) {
        [self setPreviewUpdating:NO];
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
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode((OMDViewerMode)_viewerMode);

    if (!layout.splitVisible && layout.previewVisible) {
        [_splitView removeFromSuperview];
        [_previewScrollView removeFromSuperview];
        [_sourceEditorContainer removeFromSuperview];
        [_previewScrollView setHidden:NO];
        [_sourceEditorContainer setHidden:YES];
        [_documentContainer addSubview:_previewScrollView];
        [_previewScrollView setFrame:bounds];
        [self updatePreviewDocumentGeometry];
        [self updateCodeBlockButtons];
        [self requestInteractiveRenderForLayoutWidthIfNeeded];
        [self layoutSourceEditorContainer];
        [self updateFormattingBarContextState];
        [_previewScrollView setNeedsDisplay:YES];
        [_documentContainer setNeedsDisplay:YES];
        return;
    }

    if (!layout.splitVisible && layout.sourceVisible) {
        [_splitView removeFromSuperview];
        [_previewScrollView removeFromSuperview];
        [_sourceEditorContainer removeFromSuperview];
        [_previewScrollView setHidden:YES];
        [_sourceEditorContainer setHidden:NO];
        [_documentContainer addSubview:_sourceEditorContainer];
        [_sourceEditorContainer setFrame:bounds];
        [self layoutSourceEditorContainer];
        [self updateFormattingBarContextState];
        [_sourceEditorContainer setNeedsDisplay:YES];
        [_documentContainer setNeedsDisplay:YES];
        return;
    }

    [_previewScrollView removeFromSuperview];
    [_sourceEditorContainer removeFromSuperview];
    [_splitView removeFromSuperview];
    [_splitView addSubview:_sourceEditorContainer];
    [_splitView addSubview:_previewScrollView];
    [_documentContainer addSubview:_splitView];
    [_splitView setFrame:bounds];
    [_sourceEditorContainer setHidden:NO];
    [_previewScrollView setHidden:NO];
    // GNUstep can defer split subview geometry until the next resize event.
    // Force one immediate pass so Edit->Split transitions are visually correct.
    [_splitView adjustSubviews];
    [self applySplitViewRatio];
    [_splitView adjustSubviews];
    [self layoutSourceEditorContainer];
    [self updateFormattingBarContextState];
    [_splitView setNeedsDisplay:YES];
    [_previewScrollView setNeedsDisplay:YES];
    [_sourceEditorContainer setNeedsDisplay:YES];
    [_documentContainer setNeedsDisplay:YES];
}

- (void)applyCurrentDocumentReadOnlyState
{
    if (_sourceTextView == nil) {
        [self updateToolbarActionControlsState];
        return;
    }

    BOOL editable = !_currentDocumentReadOnly;
    [_sourceTextView setEditable:editable];
    [_sourceTextView setSelectable:YES];
    [self updateFormattingBarContextState];
    [self updateToolbarActionControlsState];
}

- (void)updateTabStrip
{
    if (_tabStripView == nil) {
        return;
    }

    NSArray *existingSubviews = [[_tabStripView subviews] copy];
    for (NSView *view in existingSubviews) {
        [view removeFromSuperview];
    }
    [existingSubviews release];

    if ([_tabStripView isHidden] || [self currentTabStripHeight] <= 0.0) {
        return;
    }

    NSRect bounds = [_tabStripView bounds];
    if ([_documentTabs count] == 0) {
        NSTextField *label = [[[NSTextField alloc] initWithFrame:NSInsetRect(bounds, 8.0, 6.0)] autorelease];
        [label setBezeled:NO];
        [label setEditable:NO];
        [label setSelectable:NO];
        [label setDrawsBackground:NO];
        [label setTextColor:[NSColor disabledControlTextColor]];
        [label setFont:[NSFont systemFontOfSize:11.0]];
        [label setStringValue:@"No document open"];
        [_tabStripView addSubview:label];
        return;
    }

    CGFloat x = 6.0;
    CGFloat y = 4.0;
    CGFloat height = NSHeight(bounds) - 8.0;
    CGFloat available = NSWidth(bounds) - 6.0;
    const CGFloat closeButtonSize = 14.0;
    const CGFloat closeButtonInset = 3.0;

    NSInteger index = 0;
    for (; index < (NSInteger)[_documentTabs count]; index++) {
        NSDictionary *tab = [_documentTabs objectAtIndex:index];
        NSString *title = [tab objectForKey:OMDTabDisplayTitleKey];
        if (title == nil || [title length] == 0) {
            NSString *path = [tab objectForKey:OMDTabSourcePathKey];
            title = (path != nil ? [path lastPathComponent] : @"Untitled");
        }
        if ([[tab objectForKey:OMDTabDirtyKey] boolValue]) {
            title = [title stringByAppendingString:@" *"];
        }
        if ([[tab objectForKey:OMDTabReadOnlyKey] boolValue]) {
            title = [title stringByAppendingString:@" [RO]"];
        }

        CGFloat width = 30.0 + (CGFloat)[title length] * 6.8;
        if (width < 108.0) {
            width = 108.0;
        }
        if (width > 240.0) {
            width = 240.0;
        }
        if (x + width > available) {
            width = available - x;
        }
        if (width < 72.0) {
            break;
        }

        NSView *tabContainer = [[[NSView alloc] initWithFrame:NSMakeRect(x, y, width, height)] autorelease];
        [tabContainer setAutoresizingMask:NSViewMinYMargin];

        CGFloat titleWidth = width - closeButtonSize - (closeButtonInset * 2.0);
        if (titleWidth < 52.0) {
            titleWidth = width - closeButtonSize - closeButtonInset;
        }
        if (titleWidth < 40.0) {
            break;
        }

        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, titleWidth, height)] autorelease];
        [button setTitle:title];
        [button setTag:index];
        [button setButtonType:NSPushOnPushOffButton];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setState:(index == _selectedDocumentTabIndex ? NSOnState : NSOffState)];
        [button setTarget:self];
        [button setAction:@selector(tabButtonPressed:)];
        [button setFont:[NSFont systemFontOfSize:11.0]];
        [button setAlignment:NSLeftTextAlignment];
        [tabContainer addSubview:button];

        NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(width - closeButtonSize - closeButtonInset,
                                                                              floor((height - closeButtonSize) * 0.5),
                                                                              closeButtonSize,
                                                                              closeButtonSize)] autorelease];
        [closeButton setTitle:@"x"];
        [closeButton setTag:index];
        [closeButton setButtonType:NSMomentaryPushInButton];
        [closeButton setBezelStyle:NSRoundRectBezelStyle];
        [closeButton setTarget:self];
        [closeButton setAction:@selector(tabCloseButtonPressed:)];
        [closeButton setFont:[NSFont boldSystemFontOfSize:10.0]];
        [tabContainer addSubview:closeButton];

        [_tabStripView addSubview:tabContainer];
        x += width + 4.0;
    }
}

- (void)tabButtonPressed:(id)sender
{
    NSInteger index = [sender tag];
    [self selectDocumentTabAtIndex:index];
}

- (void)tabCloseButtonPressed:(id)sender
{
    NSInteger index = [sender tag];
    [self closeDocumentTabAtIndex:index];
}

- (void)closeDocumentTabAtIndex:(NSInteger)index
{
    NSInteger count = (NSInteger)[_documentTabs count];
    if (index < 0 || index >= count) {
        return;
    }

    [self captureCurrentStateIntoSelectedTab];

    NSDictionary *tabRecord = [_documentTabs objectAtIndex:index];
    BOOL tabIsDirty = [[tabRecord objectForKey:OMDTabDirtyKey] boolValue];
    NSInteger previousSelection = _selectedDocumentTabIndex;
    BOOL switchedToClosingTab = NO;

    if (tabIsDirty && index != _selectedDocumentTabIndex) {
        [self selectDocumentTabAtIndex:index];
        switchedToClosingTab = YES;
    }

    if (tabIsDirty) {
        if (![self confirmDiscardingUnsavedChangesForAction:@"closing this tab"]) {
            if (switchedToClosingTab &&
                previousSelection >= 0 &&
                previousSelection < (NSInteger)[_documentTabs count]) {
                [self selectDocumentTabAtIndex:previousSelection];
            }
            return;
        }
        [self captureCurrentStateIntoSelectedTab];
    }

    if (index < 0 || index >= (NSInteger)[_documentTabs count]) {
        return;
    }
    [_documentTabs removeObjectAtIndex:index];

    if ([_documentTabs count] == 0) {
        _selectedDocumentTabIndex = -1;
        [self setCurrentMarkdown:nil sourcePath:nil];
        [self clearRecoverySnapshot];
        [self updateTabStrip];
        [self updateWindowTitle];
        return;
    }

    NSInteger targetSelection = previousSelection;
    if (targetSelection < 0) {
        targetSelection = 0;
    }
    if (targetSelection == index) {
        targetSelection = index;
    } else if (targetSelection > index) {
        targetSelection -= 1;
    }

    NSInteger remainingCount = (NSInteger)[_documentTabs count];
    if (targetSelection >= remainingCount) {
        targetSelection = remainingCount - 1;
    }
    if (targetSelection < 0) {
        targetSelection = 0;
    }

    _selectedDocumentTabIndex = targetSelection;
    NSDictionary *selectedTab = [_documentTabs objectAtIndex:targetSelection];
    [self applyDocumentTabRecord:selectedTab];
    [self updateTabStrip];
}

- (void)captureCurrentStateIntoSelectedTab
{
    if (_selectedDocumentTabIndex < 0 || _selectedDocumentTabIndex >= (NSInteger)[_documentTabs count]) {
        return;
    }

    NSMutableDictionary *tab = [_documentTabs objectAtIndex:_selectedDocumentTabIndex];
    [tab setObject:(_currentMarkdown != nil ? _currentMarkdown : @"") forKey:OMDTabMarkdownKey];

    if (_currentPath != nil && [_currentPath length] > 0) {
        [tab setObject:_currentPath forKey:OMDTabSourcePathKey];
    } else {
        [tab removeObjectForKey:OMDTabSourcePathKey];
    }

    if (_currentDisplayTitle != nil && [_currentDisplayTitle length] > 0) {
        [tab setObject:_currentDisplayTitle forKey:OMDTabDisplayTitleKey];
    } else {
        [tab removeObjectForKey:OMDTabDisplayTitleKey];
    }

    [tab setObject:[NSNumber numberWithBool:_sourceIsDirty] forKey:OMDTabDirtyKey];
    [tab setObject:[NSNumber numberWithBool:_currentDocumentReadOnly] forKey:OMDTabReadOnlyKey];
    [tab setObject:[NSNumber numberWithInteger:_currentDocumentRenderMode] forKey:OMDTabRenderModeKey];
    if (_currentDocumentSyntaxLanguage != nil && [_currentDocumentSyntaxLanguage length] > 0) {
        [tab setObject:_currentDocumentSyntaxLanguage forKey:OMDTabSyntaxLanguageKey];
    } else {
        [tab removeObjectForKey:OMDTabSyntaxLanguageKey];
    }
    if (_currentLoadedDiskFingerprint != nil && [_currentLoadedDiskFingerprint length] > 0) {
        [tab setObject:_currentLoadedDiskFingerprint forKey:OMDTabLoadedDiskFingerprintKey];
    } else {
        [tab removeObjectForKey:OMDTabLoadedDiskFingerprintKey];
    }
    if (_currentObservedDiskFingerprint != nil && [_currentObservedDiskFingerprint length] > 0) {
        [tab setObject:_currentObservedDiskFingerprint forKey:OMDTabObservedDiskFingerprintKey];
    } else {
        [tab removeObjectForKey:OMDTabObservedDiskFingerprintKey];
    }
    if (_currentSuppressedDiskFingerprint != nil && [_currentSuppressedDiskFingerprint length] > 0) {
        [tab setObject:_currentSuppressedDiskFingerprint forKey:OMDTabSuppressedDiskFingerprintKey];
    } else {
        [tab removeObjectForKey:OMDTabSuppressedDiskFingerprintKey];
    }
}

- (NSMutableDictionary *)newDocumentTabWithMarkdown:(NSString *)markdown
                                         sourcePath:(NSString *)sourcePath
                                       displayTitle:(NSString *)displayTitle
                                           readOnly:(BOOL)readOnly
                                         renderMode:(OMDDocumentRenderMode)renderMode
                                     syntaxLanguage:(NSString *)syntaxLanguage
                                    diskFingerprint:(NSString *)diskFingerprint
{
    NSMutableDictionary *tab = [NSMutableDictionary dictionary];
    [tab setObject:(markdown != nil ? markdown : @"") forKey:OMDTabMarkdownKey];
    if (sourcePath != nil && [sourcePath length] > 0) {
        [tab setObject:sourcePath forKey:OMDTabSourcePathKey];
    }
    if (displayTitle != nil && [displayTitle length] > 0) {
        [tab setObject:displayTitle forKey:OMDTabDisplayTitleKey];
    }
    [tab setObject:[NSNumber numberWithBool:NO] forKey:OMDTabDirtyKey];
    [tab setObject:[NSNumber numberWithBool:readOnly] forKey:OMDTabReadOnlyKey];
    [tab setObject:[NSNumber numberWithInteger:renderMode] forKey:OMDTabRenderModeKey];
    NSString *normalizedSyntax = OMDTrimmedString(syntaxLanguage);
    if ([normalizedSyntax length] > 0) {
        [tab setObject:normalizedSyntax forKey:OMDTabSyntaxLanguageKey];
    }
    if ([diskFingerprint length] > 0) {
        [tab setObject:diskFingerprint forKey:OMDTabLoadedDiskFingerprintKey];
        [tab setObject:diskFingerprint forKey:OMDTabObservedDiskFingerprintKey];
    }
    return tab;
}

- (void)installDocumentTabRecord:(NSMutableDictionary *)tab
                         inNewTab:(BOOL)inNewTab
                    resetViewport:(BOOL)resetViewport
{
    if (tab == nil) {
        return;
    }

    if (inNewTab || _selectedDocumentTabIndex < 0 || _selectedDocumentTabIndex >= (NSInteger)[_documentTabs count]) {
        [self captureCurrentStateIntoSelectedTab];
        [_documentTabs addObject:tab];
        _selectedDocumentTabIndex = (NSInteger)[_documentTabs count] - 1;
    } else {
        [_documentTabs replaceObjectAtIndex:_selectedDocumentTabIndex withObject:tab];
    }

    [self applyDocumentTabRecord:tab];
    if (resetViewport) {
        [self resetCurrentDocumentViewportToStart];
    }
    [self updateTabStrip];
}

- (void)applyDocumentTabRecord:(NSDictionary *)tabRecord
{
    if (tabRecord == nil) {
        return;
    }

    NSString *markdown = [tabRecord objectForKey:OMDTabMarkdownKey];
    NSString *sourcePath = [tabRecord objectForKey:OMDTabSourcePathKey];
    NSInteger rawRenderMode = [[tabRecord objectForKey:OMDTabRenderModeKey] integerValue];
    OMDDocumentRenderMode renderMode = (rawRenderMode == OMDDocumentRenderModeVerbatim
                                        ? OMDDocumentRenderModeVerbatim
                                        : OMDDocumentRenderModeMarkdown);
    NSString *syntaxLanguage = [tabRecord objectForKey:OMDTabSyntaxLanguageKey];
    [self setCurrentDocumentText:(markdown != nil ? markdown : @"")
                      sourcePath:sourcePath
                      renderMode:renderMode
                  syntaxLanguage:syntaxLanguage];

    _sourceIsDirty = [[tabRecord objectForKey:OMDTabDirtyKey] boolValue];
    NSString *displayTitle = [tabRecord objectForKey:OMDTabDisplayTitleKey];
    [_currentDisplayTitle release];
    _currentDisplayTitle = [displayTitle copy];
    BOOL readOnly = [[tabRecord objectForKey:OMDTabReadOnlyKey] boolValue];
    BOOL isGitHubTab = [[tabRecord objectForKey:OMDTabIsGitHubKey] boolValue];
    if (isGitHubTab && readOnly) {
        readOnly = NO;
        if ([tabRecord isKindOfClass:[NSMutableDictionary class]]) {
            [(NSMutableDictionary *)tabRecord setObject:[NSNumber numberWithBool:NO] forKey:OMDTabReadOnlyKey];
        }
    }
    _currentDocumentReadOnly = readOnly;
    [self setCurrentDiskFingerprintStateLoaded:[tabRecord objectForKey:OMDTabLoadedDiskFingerprintKey]
                                      observed:[tabRecord objectForKey:OMDTabObservedDiskFingerprintKey]
                                    suppressed:[tabRecord objectForKey:OMDTabSuppressedDiskFingerprintKey]];
    [self applyCurrentDocumentReadOnlyState];
    [self updatePreviewStatusIndicator];
    [self updateWindowTitle];
}

- (void)selectDocumentTabAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)[_documentTabs count]) {
        return;
    }
    if (index == _selectedDocumentTabIndex) {
        return;
    }

    [self captureCurrentStateIntoSelectedTab];
    _selectedDocumentTabIndex = index;
    NSDictionary *tab = [_documentTabs objectAtIndex:index];
    [self applyDocumentTabRecord:tab];
    [self updateTabStrip];
    [self refreshCurrentDocumentDiskStateAllowPrompt:YES];
}

- (NSInteger)documentTabIndexForLocalPath:(NSString *)sourcePath
{
    NSString *targetPath = OMDTrimmedString(sourcePath);
    if ([targetPath length] == 0) {
        return -1;
    }
    targetPath = [targetPath stringByStandardizingPath];

    NSInteger index = 0;
    for (; index < (NSInteger)[_documentTabs count]; index++) {
        NSDictionary *tab = [_documentTabs objectAtIndex:index];
        NSString *tabPath = OMDTrimmedString([tab objectForKey:OMDTabSourcePathKey]);
        if ([tabPath length] == 0) {
            continue;
        }
        tabPath = [tabPath stringByStandardizingPath];
        if ([tabPath isEqualToString:targetPath]) {
            return index;
        }
    }
    return -1;
}

- (NSInteger)documentTabIndexForGitHubUser:(NSString *)user
                                      repo:(NSString *)repo
                                      path:(NSString *)path
{
    NSString *targetUser = [[OMDTrimmedString(user) lowercaseString] copy];
    NSString *targetRepo = [[OMDTrimmedString(repo) lowercaseString] copy];
    NSString *targetPath = [OMDNormalizedRelativePath(path) copy];
    if ([targetUser length] == 0 || [targetRepo length] == 0 || [targetPath length] == 0) {
        [targetUser release];
        [targetRepo release];
        [targetPath release];
        return -1;
    }

    NSInteger found = -1;
    NSInteger index = 0;
    for (; index < (NSInteger)[_documentTabs count]; index++) {
        NSDictionary *tab = [_documentTabs objectAtIndex:index];
        if (![[tab objectForKey:OMDTabIsGitHubKey] boolValue]) {
            continue;
        }

        NSString *tabUser = [[OMDTrimmedString([tab objectForKey:OMDTabGitHubUserKey]) lowercaseString] copy];
        NSString *tabRepo = [[OMDTrimmedString([tab objectForKey:OMDTabGitHubRepoKey]) lowercaseString] copy];
        NSString *tabPath = [OMDNormalizedRelativePath([tab objectForKey:OMDTabGitHubPathKey]) copy];

        BOOL matches = ([tabUser isEqualToString:targetUser] &&
                        [tabRepo isEqualToString:targetRepo] &&
                        [tabPath isEqualToString:targetPath]);
        [tabUser release];
        [tabRepo release];
        [tabPath release];

        if (matches) {
            found = index;
            break;
        }
    }

    [targetUser release];
    [targetRepo release];
    [targetPath release];
    return found;
}

- (BOOL)openDocumentWithMarkdown:(NSString *)markdown
                      sourcePath:(NSString *)sourcePath
                    displayTitle:(NSString *)displayTitle
                        readOnly:(BOOL)readOnly
                      renderMode:(OMDDocumentRenderMode)renderMode
                  syntaxLanguage:(NSString *)syntaxLanguage
                        inNewTab:(BOOL)inNewTab
             requireDirtyConfirm:(BOOL)requireDirtyConfirm
{
    NSString *normalizedSourcePath = OMDTrimmedString(sourcePath);
    NSString *initialDiskFingerprint = nil;
    if ([normalizedSourcePath length] > 0) {
        normalizedSourcePath = [normalizedSourcePath stringByStandardizingPath];
        initialDiskFingerprint = [self diskFingerprintForPath:normalizedSourcePath];
        NSInteger existingIndex = [self documentTabIndexForLocalPath:normalizedSourcePath];
        if (existingIndex >= 0) {
            [self selectDocumentTabAtIndex:existingIndex];
            [self presentWindowIfNeeded];
            return YES;
        }
    }

    if (!inNewTab && requireDirtyConfirm && _sourceIsDirty) {
        if (![self confirmDiscardingUnsavedChangesForAction:@"opening another document"]) {
            return NO;
        }
    }

    NSMutableDictionary *tab = [self newDocumentTabWithMarkdown:markdown
                                                      sourcePath:sourcePath
                                                    displayTitle:displayTitle
                                                        readOnly:readOnly
                                                      renderMode:renderMode
                                                  syntaxLanguage:syntaxLanguage
                                                 diskFingerprint:initialDiskFingerprint];

    [self installDocumentTabRecord:tab inNewTab:inNewTab resetViewport:YES];
    [self presentWindowIfNeeded];
    return YES;
}

- (void)resetCurrentDocumentViewportToStart
{
    [self cancelPendingLinkedScrollDriverReset];
    _activeLinkedScrollDriver = OMDLinkedScrollDriverNone;

    if (_sourceTextView != nil) {
        _isProgrammaticSelectionSync = YES;
        [_sourceTextView setSelectedRange:NSMakeRange(0, 0)];
        _isProgrammaticSelectionSync = NO;
    }

    _isProgrammaticScrollSync = YES;

    if (_sourceScrollView != nil && _viewerMode != OMDViewerModeRead) {
        [self scrollScrollViewToDocumentTop:_sourceScrollView];
    }

    if (_previewScrollView != nil && [self isPreviewVisible]) {
        [self scrollScrollViewToDocumentTop:_previewScrollView];
    }

    _isProgrammaticScrollSync = NO;
    [self updateFormattingBarContextState];
}

- (void)scrollScrollViewToDocumentTop:(NSScrollView *)scrollView
{
    if (scrollView == nil) {
        return;
    }

    NSClipView *clipView = [scrollView contentView];
    if (clipView == nil) {
        return;
    }

    NSView *documentView = [scrollView documentView];
    NSRect clipBounds = [clipView bounds];
    NSRect documentFrame = documentView != nil ? [documentView frame] : NSZeroRect;
    CGFloat maxY = documentFrame.size.height - clipBounds.size.height;
    if (maxY < 0.0) {
        maxY = 0.0;
    }

    BOOL isFlipped = documentView != nil ? [documentView isFlipped] : YES;
    NSPoint targetOrigin = NSMakePoint(0.0, (isFlipped ? 0.0 : maxY));
    NSPoint currentOrigin = [clipView bounds].origin;
    if (fabs(currentOrigin.x - targetOrigin.x) <= 0.5 &&
        fabs(currentOrigin.y - targetOrigin.y) <= 0.5) {
        return;
    }

    [clipView scrollToPoint:targetOrigin];
    [scrollView reflectScrolledClipView:clipView];
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
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
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

- (CGFloat)scrollSpeedPreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:OMDScrollSpeedDefaultsKey];
    CGFloat scrollSpeed = OMDScrollSpeedDefault;
    if ([value respondsToSelector:@selector(doubleValue)]) {
        scrollSpeed = (CGFloat)[value doubleValue];
    }
    return OMDClampedScrollSpeed(scrollSpeed);
}

- (void)setScrollSpeedPreference:(CGFloat)scrollSpeed
{
    scrollSpeed = OMDClampedScrollSpeed(scrollSpeed);
    [[NSUserDefaults standardUserDefaults] setDouble:scrollSpeed forKey:OMDScrollSpeedDefaultsKey];
    [self applyScrollSpeedPreference];
}

- (void)applyScrollSpeedPreference
{
    CGFloat scrollSpeed = [self scrollSpeedPreference];
    NSArray *scrollViews = [NSArray arrayWithObjects:_sourceScrollView, _previewScrollView, _explorerScrollView, nil];
    for (NSScrollView *scrollView in scrollViews) {
        if (scrollView == nil) {
            continue;
        }
        [scrollView setVerticalLineScroll:scrollSpeed];
        [scrollView setHorizontalLineScroll:scrollSpeed];
    }
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

- (BOOL)ensureOpenFileSizeWithinLimit:(unsigned long long)size
                           descriptor:(NSString *)descriptor
{
    NSUInteger limit = [self explorerMaxOpenFileSizeBytes];
    if (size <= (unsigned long long)limit) {
        return YES;
    }

    double sizeMB = (double)size / (1024.0 * 1024.0);
    double limitMB = (double)limit / (1024.0 * 1024.0);
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"File too large to open"];
    [alert setInformativeText:[NSString stringWithFormat:@"%@ is %.2f MB. Current limit is %.2f MB (change in Preferences).",
                                                         descriptor,
                                                         sizeMB,
                                                         limitMB]];
    [alert runModal];
    return NO;
}

- (BOOL)isMarkdownTextPath:(NSString *)path
{
    NSString *extension = [[path pathExtension] lowercaseString];
    return OMDIsMarkdownExtension(extension);
}

- (NSString *)temporaryPathForRemoteImportWithExtension:(NSString *)extension
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory == nil || [temporaryDirectory length] == 0) {
        temporaryDirectory = @"/tmp";
    }
    NSString *safeExtension = ([extension length] > 0 ? extension : @"tmp");
    NSString *name = [NSString stringWithFormat:@"objcmarkdown-remote-%@.%@",
                                               [[NSProcessInfo processInfo] globallyUniqueString],
                                               safeExtension];
    return [temporaryDirectory stringByAppendingPathComponent:name];
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
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    if (_sidebarContainer == nil) {
        return;
    }

    NSRect bounds = [_sidebarContainer bounds];
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
    [_sidebarContainer addSubview:_explorerSourceModeControl];

    _explorerLocalRootLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding, NSHeight(bounds) - 60, wideControlWidth, 16)];
    [_explorerLocalRootLabel setBezeled:NO];
    [_explorerLocalRootLabel setEditable:NO];
    [_explorerLocalRootLabel setSelectable:NO];
    [_explorerLocalRootLabel setDrawsBackground:NO];
    [_explorerLocalRootLabel setFont:labelFont];
    [_explorerLocalRootLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerLocalRootLabel];

    _explorerGitHubUserLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(metrics.explorerSidePadding, NSHeight(bounds) - 60, 44, 20)];
    [_explorerGitHubUserLabel setBezeled:NO];
    [_explorerGitHubUserLabel setEditable:NO];
    [_explorerGitHubUserLabel setSelectable:NO];
    [_explorerGitHubUserLabel setDrawsBackground:NO];
    [_explorerGitHubUserLabel setStringValue:@"User:"];
    [_explorerGitHubUserLabel setFont:labelFont];
    [_explorerGitHubUserLabel setAutoresizingMask:NSViewMinYMargin];
    [_sidebarContainer addSubview:_explorerGitHubUserLabel];

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
    [_sidebarContainer addSubview:_explorerGitHubUserComboBox];

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
    [_sidebarContainer addSubview:_explorerGitHubRepoComboBox];

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
    [_sidebarContainer addSubview:_explorerGitHubIncludeForkArchivedButton];

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
    [_sidebarContainer addSubview:_explorerShowHiddenFilesButton];

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
    [_sidebarContainer addSubview:_explorerNavigateUpButton];

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
    [_sidebarContainer addSubview:_explorerPathLabel];

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
    [self applyScrollSpeedPreference];
    [_sidebarContainer addSubview:_explorerScrollView];
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

- (void)updateExplorerControlsVisibility
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
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

    NSRect bounds = [_sidebarContainer bounds];
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
        return;
    }

    if (_explorerSourceMode == OMDExplorerSourceModeGitHub) {
        [self openGitHubFileEntry:entry inNewTab:inNewTab];
    } else {
        [self openLocalPath:path inNewTab:inNewTab];
    }
}

- (void)openLocalPath:(NSString *)path inNewTab:(BOOL)inNewTab
{
    if (path == nil || [path length] == 0) {
        return;
    }

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    NSNumber *sizeValue = [attributes objectForKey:NSFileSize];
    if ([sizeValue respondsToSelector:@selector(unsignedLongLongValue)]) {
        if (![self ensureOpenFileSizeWithinLimit:[sizeValue unsignedLongLongValue]
                                      descriptor:[path lastPathComponent]]) {
            return;
        }
    }

    NSString *extension = [[path pathExtension] lowercaseString];
    if ([OMDDocumentConverter isSupportedExtension:extension]) {
        if (![self ensureConverterAvailableForActionName:@"Import"]) {
            return;
        }

        NSString *importedMarkdown = nil;
        NSError *error = nil;
        BOOL success = [[self documentConverter] importFileAtPath:path markdown:&importedMarkdown error:&error];
        if (!success) {
            [self presentConverterError:error fallbackTitle:@"Import failed"];
            return;
        }

        BOOL opened = [self openDocumentWithMarkdown:(importedMarkdown != nil ? importedMarkdown : @"")
                                          sourcePath:path
                                        displayTitle:[path lastPathComponent]
                                            readOnly:NO
                                          renderMode:OMDDocumentRenderModeMarkdown
                                      syntaxLanguage:nil
                                            inNewTab:inNewTab
                                 requireDirtyConfirm:!inNewTab];
        if (opened) {
            [self noteRecentDocumentAtPathIfAvailable:path];
        }
        return;
    }

    NSError *error = nil;
    NSString *markdown = [self decodedTextForFileAtPath:path error:&error];
    if (markdown == nil) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Unsupported file type"];
        [alert setInformativeText:(error != nil ? [error localizedDescription]
                                                : @"This file cannot be opened as text.")];
        [alert runModal];
        return;
    }

    OMDDocumentRenderMode renderMode = [self isMarkdownTextPath:path]
                                       ? OMDDocumentRenderModeMarkdown
                                       : OMDDocumentRenderModeVerbatim;
    NSString *syntaxLanguage = (renderMode == OMDDocumentRenderModeVerbatim
                                ? OMDVerbatimSyntaxTokenForExtension(extension)
                                : nil);

    BOOL opened = [self openDocumentWithMarkdown:markdown
                                      sourcePath:path
                                    displayTitle:[path lastPathComponent]
                                        readOnly:NO
                                      renderMode:renderMode
                                  syntaxLanguage:syntaxLanguage
                                        inNewTab:inNewTab
                             requireDirtyConfirm:!inNewTab];
    if (opened) {
        [self noteRecentDocumentAtPathIfAvailable:path];
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

    NSInteger existingIndex = [self documentTabIndexForGitHubUser:githubUser
                                                             repo:githubRepo
                                                             path:entryPath];
    if (existingIndex >= 0) {
        [self selectDocumentTabAtIndex:existingIndex];
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

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:NULL];
    NSNumber *sizeValue = [attributes objectForKey:NSFileSize];
    if ([sizeValue respondsToSelector:@selector(unsignedLongLongValue)]) {
        if (![self ensureOpenFileSizeWithinLimit:[sizeValue unsignedLongLongValue]
                                      descriptor:[entry objectForKey:@"name"]]) {
            return;
        }
    }

    NSString *extension = [[entryPath pathExtension] lowercaseString];
    BOOL importable = [OMDDocumentConverter isSupportedExtension:extension];

    NSString *markdownResult = nil;
    OMDDocumentRenderMode renderMode = OMDDocumentRenderModeMarkdown;
    NSString *syntaxLanguage = nil;
    if (importable) {
        if (![self ensureConverterAvailableForActionName:@"Import"]) {
            return;
        }
        NSString *importedMarkdown = nil;
        NSError *conversionError = nil;
        BOOL converted = [[self documentConverter] importFileAtPath:fullPath
                                                           markdown:&importedMarkdown
                                                              error:&conversionError];
        if (!converted) {
            [self presentConverterError:conversionError fallbackTitle:@"Import failed"];
            return;
        }
        markdownResult = importedMarkdown;
    } else {
        NSError *readError = nil;
        markdownResult = [self decodedTextForFileAtPath:fullPath error:&readError];
        if (markdownResult == nil) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"Unsupported file type"];
            [alert setInformativeText:(readError != nil ? [readError localizedDescription]
                                                        : @"This cached file cannot be opened as text.")];
            [alert runModal];
            return;
        }
        renderMode = [self isMarkdownTextPath:entryPath]
                     ? OMDDocumentRenderModeMarkdown
                     : OMDDocumentRenderModeVerbatim;
        if (renderMode == OMDDocumentRenderModeVerbatim) {
            syntaxLanguage = OMDVerbatimSyntaxTokenForExtension(extension);
        }
    }

    NSString *displayTitle = [NSString stringWithFormat:@"%@/%@:%@",
                              githubUser != nil ? githubUser : @"",
                              githubRepo != nil ? githubRepo : @"",
                              entryPath];
    [self openDocumentWithMarkdown:(markdownResult != nil ? markdownResult : @"")
                        sourcePath:nil
                      displayTitle:displayTitle
                          readOnly:NO
                        renderMode:renderMode
                    syntaxLanguage:syntaxLanguage
                          inNewTab:inNewTab
               requireDirtyConfirm:!inNewTab];
    if (_selectedDocumentTabIndex >= 0 && _selectedDocumentTabIndex < (NSInteger)[_documentTabs count]) {
        NSMutableDictionary *tab = [_documentTabs objectAtIndex:_selectedDocumentTabIndex];
        [tab setObject:[NSNumber numberWithBool:YES] forKey:OMDTabIsGitHubKey];
        if (githubUser != nil) {
            [tab setObject:githubUser forKey:OMDTabGitHubUserKey];
        }
        if (githubRepo != nil) {
            [tab setObject:githubRepo forKey:OMDTabGitHubRepoKey];
        }
        [tab setObject:entryPath forKey:OMDTabGitHubPathKey];
    }
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
    NSColor *textColor = [NSColor controlTextColor];

    if (isDirectory) {
        textColor = [NSColor controlTextColor];
    } else if (colorTier == 1) {
        textColor = [NSColor colorWithCalibratedRed:0.30 green:0.62 blue:0.93 alpha:1.0];
    } else if (colorTier == 2) {
        textColor = [NSColor colorWithCalibratedRed:0.82 green:0.62 blue:0.22 alpha:1.0];
    } else {
        textColor = [NSColor disabledControlTextColor];
    }

    [cell setTextColor:textColor];
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

- (void)updateModeControlSelection
{
    if (_modeControl == nil) {
        return;
    }
    [_modeControl setSelectedSegment:_viewerMode];
    if (_modeLabel != nil) {
        [_modeLabel setTextColor:[self modeLabelTextColor]];
    }
    [self updatePreviewStatusIndicator];
}

- (void)updatePreviewStatusIndicator
{
    [self updateToolbarActionControlsState];
    if (_previewStatusLabel == nil) {
        return;
    }

    if (_sourceVimCommandLine != nil && [_sourceVimCommandLine length] > 0) {
        [_previewStatusLabel setStringValue:_sourceVimCommandLine];
        [_previewStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.85 green:0.50 blue:0.10 alpha:1.0]];
        [_previewStatusLabel setHidden:NO];
        return;
    }

    NSString *vimStatusText = [self sourceVimStatusText];
    if (vimStatusText != nil) {
        NSColor *vimStatusColor = [self sourceVimStatusColor];
        if (vimStatusColor == nil) {
            vimStatusColor = [NSColor controlTextColor];
        }
        if (vimStatusColor == nil) {
            vimStatusColor = [NSColor textColor];
        }
        [_previewStatusLabel setStringValue:vimStatusText];
        [_previewStatusLabel setTextColor:vimStatusColor];
        [_previewStatusLabel setHidden:NO];
        return;
    }

    NSString *status = OMDPreviewStatusTextForState((OMDViewerMode)_viewerMode,
                                                    _previewIsUpdating,
                                                    _sourceRevision,
                                                    _lastRenderedSourceRevision);

    BOOL showStatus = NO;
    NSString *statusText = nil;
    NSColor *statusColor = nil;

    if ([status isEqualToString:@"Preview Updating"]) {
        if (_previewStatusUpdatingVisible) {
            showStatus = YES;
            statusText = @"Updating...";
            statusColor = [NSColor colorWithCalibratedRed:0.85 green:0.50 blue:0.10 alpha:1.0];
        }
    } else if ([status isEqualToString:@"Preview Stale"]) {
        _previewStatusShowsUpdated = NO;
        [self cancelPendingPreviewStatusAutoHide];
        showStatus = YES;
        statusText = @"Preview stale";
        statusColor = [NSColor colorWithCalibratedRed:0.79 green:0.34 blue:0.10 alpha:1.0];
    } else if ([status isEqualToString:@"Preview Live"]) {
        if (_previewStatusShowsUpdated) {
            showStatus = YES;
            statusText = @"Updated";
            statusColor = [NSColor colorWithCalibratedRed:0.12 green:0.56 blue:0.24 alpha:1.0];
        }
    } else {
        _previewStatusShowsUpdated = NO;
        [self cancelPendingPreviewStatusAutoHide];
    }

    if (showStatus) {
        if (statusText == nil) {
            statusText = @"";
        }
        if (statusColor == nil) {
            statusColor = [NSColor controlTextColor];
        }
        if (statusColor == nil) {
            statusColor = [NSColor textColor];
        }
        [_previewStatusLabel setStringValue:statusText];
        [_previewStatusLabel setTextColor:statusColor];
        [_previewStatusLabel setHidden:NO];
    } else {
        [_previewStatusLabel setStringValue:@""];
        [_previewStatusLabel setHidden:YES];
    }
}

- (NSString *)sourceVimStatusText
{
    if (![self isSourceVimKeyBindingsEnabled]) {
        return nil;
    }
    if (_viewerMode == OMDViewerModeRead) {
        return nil;
    }
    if (_sourceTextView == nil || _sourceVimBindingController == nil) {
        return nil;
    }

    NSString *modeName = GSVVimModeDisplayName([_sourceVimBindingController mode]);
    if (modeName == nil || [modeName length] == 0) {
        modeName = @"NORMAL";
    }
    return [NSString stringWithFormat:@"Vim: %@", modeName];
}

- (NSColor *)sourceVimStatusColor
{
    if (_sourceVimBindingController == nil) {
        return [NSColor controlTextColor];
    }

    switch ([_sourceVimBindingController mode]) {
        case GSVVimModeInsert:
            return [NSColor colorWithCalibratedRed:0.12 green:0.56 blue:0.24 alpha:1.0];
        case GSVVimModeVisual:
        case GSVVimModeVisualLine:
            return [NSColor colorWithCalibratedRed:0.79 green:0.34 blue:0.10 alpha:1.0];
        case GSVVimModeNormal:
        default:
            return [NSColor colorWithCalibratedRed:0.20 green:0.42 blue:0.70 alpha:1.0];
    }
}

- (void)schedulePreviewStatusUpdatingVisibility
{
    if (_previewStatusUpdatingDelayTimer != nil) {
        return;
    }
    _previewStatusUpdatingDelayTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDPreviewStatusUpdatingDelayInterval
                                                                          target:self
                                                                        selector:@selector(previewStatusUpdatingDelayTimerFired:)
                                                                        userInfo:nil
                                                                         repeats:NO] retain];
}

- (void)previewStatusUpdatingDelayTimerFired:(NSTimer *)timer
{
    if (timer != _previewStatusUpdatingDelayTimer) {
        return;
    }
    [_previewStatusUpdatingDelayTimer invalidate];
    [_previewStatusUpdatingDelayTimer release];
    _previewStatusUpdatingDelayTimer = nil;

    if (!_previewIsUpdating) {
        return;
    }
    _previewStatusUpdatingVisible = YES;
    [self updatePreviewStatusIndicator];
}

- (void)cancelPendingPreviewStatusUpdatingVisibility
{
    if (_previewStatusUpdatingDelayTimer != nil) {
        [_previewStatusUpdatingDelayTimer invalidate];
        [_previewStatusUpdatingDelayTimer release];
        _previewStatusUpdatingDelayTimer = nil;
    }
}

- (void)schedulePreviewStatusAutoHideAfterDelay:(NSTimeInterval)delay
{
    if (delay < 0.01) {
        delay = 0.01;
    }
    [self cancelPendingPreviewStatusAutoHide];
    _previewStatusAutoHideTimer = [[NSTimer scheduledTimerWithTimeInterval:delay
                                                                     target:self
                                                                   selector:@selector(previewStatusAutoHideTimerFired:)
                                                                   userInfo:nil
                                                                    repeats:NO] retain];
}

- (void)previewStatusAutoHideTimerFired:(NSTimer *)timer
{
    if (timer != _previewStatusAutoHideTimer) {
        return;
    }
    [_previewStatusAutoHideTimer invalidate];
    [_previewStatusAutoHideTimer release];
    _previewStatusAutoHideTimer = nil;

    if (!_previewStatusShowsUpdated) {
        return;
    }
    _previewStatusShowsUpdated = NO;
    [self updatePreviewStatusIndicator];
}

- (void)cancelPendingPreviewStatusAutoHide
{
    if (_previewStatusAutoHideTimer != nil) {
        [_previewStatusAutoHideTimer invalidate];
        [_previewStatusAutoHideTimer release];
        _previewStatusAutoHideTimer = nil;
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
        [self updateFormattingBarContextState];
        return;
    }
    _isProgrammaticSourceUpdate = YES;
    [_sourceTextView setString:text];
    _isProgrammaticSourceUpdate = NO;
    _sourceHighlightNeedsFullPass = YES;
    [self requestSourceSyntaxHighlightingRefresh];
    if (_sourceLineNumberRuler != nil) {
        [_sourceLineNumberRuler invalidateLineNumbers];
    }
    [self updateFormattingBarContextState];
}

- (void)setPreviewUpdating:(BOOL)updating
{
    if (_previewIsUpdating == updating) {
        return;
    }

    BOOL wasUpdating = _previewIsUpdating;
    BOOL hadVisibleUpdating = _previewStatusUpdatingVisible;
    _previewIsUpdating = updating;

    if (updating) {
        _previewStatusShowsUpdated = NO;
        _previewStatusUpdatingVisible = NO;
        [self cancelPendingPreviewStatusAutoHide];
        [self schedulePreviewStatusUpdatingVisibility];
    } else {
        [self cancelPendingPreviewStatusUpdatingVisibility];
        _previewStatusUpdatingVisible = NO;

        if (wasUpdating && hadVisibleUpdating) {
            NSString *statusAfterUpdate = OMDPreviewStatusTextForState((OMDViewerMode)_viewerMode,
                                                                       NO,
                                                                       _sourceRevision,
                                                                       _lastRenderedSourceRevision);
            if ([statusAfterUpdate isEqualToString:@"Preview Live"]) {
                _previewStatusShowsUpdated = YES;
                [self schedulePreviewStatusAutoHideAfterDelay:OMDPreviewStatusUpdatedDisplayInterval];
            } else {
                _previewStatusShowsUpdated = NO;
                [self cancelPendingPreviewStatusAutoHide];
            }
        } else {
            _previewStatusShowsUpdated = NO;
            [self cancelPendingPreviewStatusAutoHide];
        }
    }

    [self updatePreviewStatusIndicator];
    [self updateWindowTitle];
}

- (void)scrollViewContentBoundsDidChange:(NSNotification *)notification
{
    if (_isProgrammaticScrollSync) {
        return;
    }
    if (_viewerMode != OMDViewerModeSplit || ![self usesLinkedScrolling]) {
        return;
    }
    if (_sourceRevision != _lastRenderedSourceRevision) {
        return;
    }

    id object = [notification object];
    OMDLinkedScrollDriver driver = OMDLinkedScrollDriverNone;
    if (_sourceScrollView != nil && object == [_sourceScrollView contentView]) {
        driver = OMDLinkedScrollDriverSource;
    } else if (_previewScrollView != nil && object == [_previewScrollView contentView]) {
        driver = OMDLinkedScrollDriverPreview;
    } else {
        return;
    }

    if (_activeLinkedScrollDriver != OMDLinkedScrollDriverNone &&
        _activeLinkedScrollDriver != driver) {
        return;
    }

    [self refreshLinkedScrollDriver:driver];
    if (driver == OMDLinkedScrollDriverSource) {
        [self syncPreviewToSourceScrollPosition];
    } else if (driver == OMDLinkedScrollDriverPreview) {
        [self syncSourceToPreviewScrollPosition];
    }
}

- (NSUInteger)visibleCharacterIndexForTextView:(NSTextView *)textView
                                  inScrollView:(NSScrollView *)scrollView
                                verticalAnchor:(CGFloat)verticalAnchor
{
    if (textView == nil || scrollView == nil) {
        return 0;
    }

    NSString *text = [[textView textStorage] string];
    NSUInteger length = [text length];
    if (length == 0) {
        return 0;
    }

    NSLayoutManager *layoutManager = [textView layoutManager];
    NSTextContainer *textContainer = [textView textContainer];
    if (layoutManager == nil || textContainer == nil) {
        return 0;
    }
    [layoutManager ensureLayoutForTextContainer:textContainer];
    if ([layoutManager numberOfGlyphs] == 0) {
        return 0;
    }

    NSRect visibleRect = [textView visibleRect];
    if (NSIsEmptyRect(visibleRect)) {
        visibleRect = [textView bounds];
    }
    if (verticalAnchor < 0.0) {
        verticalAnchor = 0.0;
    } else if (verticalAnchor > 1.0) {
        verticalAnchor = 1.0;
    }
    NSPoint textOrigin = [textView textContainerOrigin];
    CGFloat verticalOffset = floor(NSHeight(visibleRect) * verticalAnchor);
    if (verticalOffset < 1.0) {
        verticalOffset = 1.0;
    }
    CGFloat probeY = [textView isFlipped]
        ? (NSMinY(visibleRect) + verticalOffset)
        : (NSMaxY(visibleRect) - verticalOffset);
    NSPoint probe = NSMakePoint(NSMinX(visibleRect) + 4.0 - textOrigin.x,
                                probeY - textOrigin.y);
    if (probe.x < 0.0) {
        probe.x = 0.0;
    }
    if (probe.y < 0.0) {
        probe.y = 0.0;
    }

    NSUInteger glyphIndex = [layoutManager glyphIndexForPoint:probe
                                               inTextContainer:textContainer
                                fractionOfDistanceThroughGlyph:NULL];
    if (glyphIndex >= [layoutManager numberOfGlyphs]) {
        return length - 1;
    }

    NSUInteger characterIndex = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
    if (characterIndex >= length) {
        return length - 1;
    }
    return characterIndex;
}

- (BOOL)targetScrollPoint:(NSPoint *)pointOut
              forTextView:(NSTextView *)textView
             inScrollView:(NSScrollView *)scrollView
           characterIndex:(NSUInteger)characterIndex
           verticalAnchor:(CGFloat)verticalAnchor
{
    if (pointOut == NULL || textView == nil || scrollView == nil) {
        return NO;
    }

    NSString *text = [[textView textStorage] string];
    NSUInteger textLength = [text length];
    if (textLength == 0) {
        return NO;
    }
    if (characterIndex >= textLength) {
        characterIndex = textLength - 1;
    }

    NSLayoutManager *layoutManager = [textView layoutManager];
    NSTextContainer *textContainer = [textView textContainer];
    if (layoutManager == nil || textContainer == nil) {
        return NO;
    }

    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(characterIndex, 1)
                                                actualCharacterRange:NULL];
    if (glyphRange.length == 0) {
        return NO;
    }

    NSRect glyphRect = [layoutManager boundingRectForGlyphRange:glyphRange
                                                 inTextContainer:textContainer];
    NSPoint textOrigin = [textView textContainerOrigin];
    NSRect glyphViewRect = NSOffsetRect(glyphRect, textOrigin.x, textOrigin.y);

    NSClipView *clipView = [scrollView contentView];
    NSRect visibleRect = [textView visibleRect];
    if (NSIsEmptyRect(visibleRect)) {
        visibleRect = [textView bounds];
    }
    if (verticalAnchor < 0.0) {
        verticalAnchor = 0.0;
    } else if (verticalAnchor > 1.0) {
        verticalAnchor = 1.0;
    }

    CGFloat availableHeight = visibleRect.size.height - glyphViewRect.size.height;
    if (availableHeight < 0.0) {
        availableHeight = 0.0;
    }

    CGFloat targetViewY = 0.0;
    if ([textView isFlipped]) {
        targetViewY = NSMinY(glyphViewRect) - floor(availableHeight * verticalAnchor);
    } else {
        targetViewY = NSMaxY(glyphViewRect) - visibleRect.size.height + floor(availableHeight * verticalAnchor);
    }

    NSView *documentView = [scrollView documentView];
    if (documentView == nil) {
        documentView = textView;
    }
    NSPoint documentPoint = [documentView convertPoint:NSMakePoint(0.0, targetViewY)
                                              fromView:textView];
    CGFloat targetY = documentPoint.y;
    if (targetY < 0.0) {
        targetY = 0.0;
    }

    CGFloat maxY = [documentView bounds].size.height - NSHeight([clipView bounds]);
    if (maxY < 0.0) {
        maxY = 0.0;
    }
    if (targetY > maxY) {
        targetY = maxY;
    }

    *pointOut = NSMakePoint(NSMinX([clipView bounds]), targetY);
    return YES;
}

- (void)cancelPendingLinkedScrollDriverReset
{
    if (_linkedScrollDriverResetTimer != nil) {
        [_linkedScrollDriverResetTimer invalidate];
        [_linkedScrollDriverResetTimer release];
        _linkedScrollDriverResetTimer = nil;
    }
}

- (void)refreshLinkedScrollDriver:(OMDLinkedScrollDriver)driver
{
    _activeLinkedScrollDriver = driver;
    [self cancelPendingLinkedScrollDriverReset];
    _linkedScrollDriverResetTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDLinkedScrollDriverHoldInterval
                                                                      target:self
                                                                    selector:@selector(linkedScrollDriverResetTimerFired:)
                                                                    userInfo:nil
                                                                     repeats:NO] retain];
}

- (void)linkedScrollDriverResetTimerFired:(NSTimer *)timer
{
    if (timer != _linkedScrollDriverResetTimer) {
        return;
    }
    [self cancelPendingLinkedScrollDriverReset];
    _activeLinkedScrollDriver = OMDLinkedScrollDriverNone;
}

- (void)syncPreviewToSourceInteractionAnchor
{
    if (_viewerMode != OMDViewerModeSplit || _sourceRevision != _lastRenderedSourceRevision) {
        return;
    }
    if ([self usesLinkedScrolling]) {
        [self syncPreviewToSourceScrollPosition];
    } else if ([self usesCaretSelectionSync]) {
        [self syncPreviewToSourceSelection];
    }
}

- (void)syncPreviewToSourceScrollPosition
{
    if (_viewerMode != OMDViewerModeSplit || _sourceTextView == nil || _textView == nil) {
        return;
    }
    if (_sourceRevision != _lastRenderedSourceRevision) {
        return;
    }

    NSString *sourceText = [_sourceTextView string];
    NSString *previewText = [[_textView textStorage] string];
    if ([sourceText length] == 0 || [previewText length] == 0) {
        return;
    }

    NSUInteger sourceLocation = [self visibleCharacterIndexForTextView:_sourceTextView
                                                          inScrollView:_sourceScrollView
                                                        verticalAnchor:OMDLinkedScrollViewportAnchor];
    NSUInteger previewLocation = OMDMapSourceLocationWithBlockAnchors(sourceText,
                                                                      sourceLocation,
                                                                      previewText,
                                                                      [_renderer blockAnchors]);
    _isProgrammaticScrollSync = YES;
    [self scrollPreviewToCharacterIndex:previewLocation verticalAnchor:OMDLinkedScrollViewportAnchor];
    _isProgrammaticScrollSync = NO;
}

- (void)syncSourceToPreviewScrollPosition
{
    if (_viewerMode != OMDViewerModeSplit || _sourceTextView == nil || _textView == nil) {
        return;
    }
    if (_sourceRevision != _lastRenderedSourceRevision) {
        return;
    }

    NSString *sourceText = [_sourceTextView string];
    NSString *previewText = [[_textView textStorage] string];
    if ([sourceText length] == 0 || [previewText length] == 0) {
        return;
    }

    NSUInteger previewLocation = [self visibleCharacterIndexForTextView:_textView
                                                           inScrollView:_previewScrollView
                                                         verticalAnchor:OMDLinkedScrollViewportAnchor];
    NSUInteger sourceLocation = OMDMapTargetLocationWithBlockAnchors(sourceText,
                                                                     previewText,
                                                                     previewLocation,
                                                                     [_renderer blockAnchors]);
    _isProgrammaticScrollSync = YES;
    [self scrollSourceToCharacterIndex:sourceLocation verticalAnchor:OMDLinkedScrollViewportAnchor];
    _isProgrammaticScrollSync = NO;
}

- (void)scrollPreviewToCharacterIndex:(NSUInteger)characterIndex
{
    [self scrollPreviewToCharacterIndex:characterIndex verticalAnchor:0.35];
}

- (void)scrollPreviewToCharacterIndex:(NSUInteger)characterIndex verticalAnchor:(CGFloat)verticalAnchor
{
    if (_textView == nil || _previewScrollView == nil) {
        return;
    }
    NSClipView *clipView = [_previewScrollView contentView];
    NSPoint targetPoint = NSZeroPoint;
    if (![self targetScrollPoint:&targetPoint
                     forTextView:_textView
                    inScrollView:_previewScrollView
                  characterIndex:characterIndex
                  verticalAnchor:verticalAnchor]) {
        return;
    }

    CGFloat currentY = NSMinY([clipView bounds]);
    if (fabs(currentY - targetPoint.y) < OMDLinkedScrollDeadband) {
        return;
    }

    [clipView scrollToPoint:targetPoint];
    [_previewScrollView reflectScrolledClipView:clipView];
}

- (void)scrollSourceToCharacterIndex:(NSUInteger)characterIndex verticalAnchor:(CGFloat)verticalAnchor
{
    if (_sourceTextView == nil || _sourceScrollView == nil) {
        return;
    }
    NSClipView *clipView = [_sourceScrollView contentView];
    NSPoint targetPoint = NSZeroPoint;
    if (![self targetScrollPoint:&targetPoint
                     forTextView:_sourceTextView
                    inScrollView:_sourceScrollView
                  characterIndex:characterIndex
                  verticalAnchor:verticalAnchor]) {
        return;
    }

    CGFloat currentY = NSMinY([clipView bounds]);
    if (fabs(currentY - targetPoint.y) < OMDLinkedScrollDeadband) {
        return;
    }

    [clipView scrollToPoint:targetPoint];
    [_sourceScrollView reflectScrolledClipView:clipView];
}

- (void)syncPreviewToSourceSelection
{
    if (_viewerMode != OMDViewerModeSplit || _sourceTextView == nil || _textView == nil) {
        return;
    }

    NSString *sourceText = [_sourceTextView string];
    NSUInteger sourceLength = [sourceText length];
    NSRange selectedRange = [_sourceTextView selectedRange];
    NSUInteger sourceLocation = selectedRange.location;
    if (sourceLocation > sourceLength) {
        sourceLocation = sourceLength;
    }

    NSString *previewText = [[_textView textStorage] string];
    NSUInteger previewLength = [previewText length];
    if (previewLength == 0) {
        return;
    }

    NSUInteger previewLocation = OMDMapSourceLocationWithBlockAnchors(sourceText,
                                                                      sourceLocation,
                                                                      previewText,
                                                                      [_renderer blockAnchors]);
    _isProgrammaticScrollSync = YES;
    [self scrollPreviewToCharacterIndex:previewLocation verticalAnchor:0.35];
    _isProgrammaticScrollSync = NO;
}

- (void)syncSourceSelectionToPreviewSelection
{
    if (_viewerMode != OMDViewerModeSplit || _sourceTextView == nil || _textView == nil) {
        return;
    }
    if (_sourceRevision != _lastRenderedSourceRevision) {
        return;
    }

    NSString *sourceText = [_sourceTextView string];
    NSUInteger sourceLength = [sourceText length];
    NSString *previewText = [[_textView textStorage] string];
    NSUInteger previewLength = [previewText length];
    if (previewLength == 0) {
        return;
    }

    NSRange selectedRange = [_textView selectedRange];
    NSUInteger previewLocation = selectedRange.location;
    BOOL atPreviewEnd = previewLocation >= previewLength;
    if (previewLocation > previewLength) {
        previewLocation = previewLength;
    }

    NSUInteger sourceLocation = OMDMapTargetLocationWithBlockAnchors(sourceText,
                                                                     previewText,
                                                                     previewLocation,
                                                                     [_renderer blockAnchors]);
    if (atPreviewEnd) {
        sourceLocation = sourceLength;
    }

    _isProgrammaticSelectionSync = YES;
    [_sourceTextView setSelectedRange:NSMakeRange(sourceLocation, 0)];
    _isProgrammaticScrollSync = YES;
    [self scrollSourceToCharacterIndex:sourceLocation verticalAnchor:0.35];
    _isProgrammaticScrollSync = NO;
    _isProgrammaticSelectionSync = NO;
}

- (void)scheduleLivePreviewRender
{
    if (![self isPreviewVisible] || _currentMarkdown == nil) {
        [self setPreviewUpdating:NO];
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
    [self setPreviewUpdating:YES];
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
    _isApplyingSplitViewRatio = YES;
    [_splitView setPosition:position ofDividerAtIndex:0];
    _isApplyingSplitViewRatio = NO;
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

- (void)updateRendererParsingOptionsForSourcePath:(NSString *)sourcePath
{
    if (_renderer == nil) {
        return;
    }

    OMMarkdownParsingOptions *existing = [_renderer parsingOptions];
    OMMarkdownParsingOptions *options = existing != nil ? [[existing copy] autorelease]
                                                        : [OMMarkdownParsingOptions defaultOptions];
    NSURL *baseURL = nil;
    if (sourcePath != nil && [sourcePath length] > 0) {
        NSString *directory = [sourcePath stringByDeletingLastPathComponent];
        if (directory != nil && [directory length] > 0) {
            baseURL = [NSURL fileURLWithPath:directory isDirectory:YES];
        }
    }
    [options setBaseURL:baseURL];
    [_renderer setParsingOptions:options];
}

- (OMMarkdownMathRenderingPolicy)currentMathRenderingPolicy
{
    OMMarkdownParsingOptions *options = _renderer != nil ? [_renderer parsingOptions] : nil;
    if (options == nil) {
        return OMMarkdownMathRenderingPolicyStyledText;
    }
    return [options mathRenderingPolicy];
}

- (BOOL)isAllowRemoteImagesEnabled
{
    OMMarkdownParsingOptions *options = _renderer != nil ? [_renderer parsingOptions] : nil;
    if (options == nil) {
        return NO;
    }
    return [options allowRemoteImages];
}

- (void)applyParsingOptionsAndRender:(OMMarkdownParsingOptions *)options
{
    if (_renderer == nil || options == nil) {
        return;
    }
    [_renderer setParsingOptions:options];
    [self updateRendererParsingOptionsForSourcePath:_currentPath];

    if (_currentMarkdown != nil && [self isPreviewVisible]) {
        [self cancelPendingInteractiveRender];
        [self cancelPendingMathArtifactRender];
        [self cancelPendingLivePreviewRender];
        [self renderCurrentMarkdown];
    }
}

- (void)setMathRenderingPolicyPreference:(OMMarkdownMathRenderingPolicy)policy
{
    if (_renderer == nil) {
        return;
    }
    OMMarkdownParsingOptions *existing = [_renderer parsingOptions];
    OMMarkdownParsingOptions *options = existing != nil ? [[existing copy] autorelease]
                                                        : [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:policy];
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)policy
                                               forKey:OMDMathRenderingPolicyDefaultsKey];
    [self applyParsingOptionsAndRender:options];
    [self syncPreferencesPanelFromSettings];
}

- (void)setAllowRemoteImagesPreference:(BOOL)allow
{
    if (_renderer == nil) {
        return;
    }
    OMMarkdownParsingOptions *existing = [_renderer parsingOptions];
    OMMarkdownParsingOptions *options = existing != nil ? [[existing copy] autorelease]
                                                        : [OMMarkdownParsingOptions defaultOptions];
    [options setAllowRemoteImages:allow];
    [[NSUserDefaults standardUserDefaults] setBool:allow forKey:OMDAllowRemoteImagesDefaultsKey];
    [self applyParsingOptionsAndRender:options];
    [self syncPreferencesPanelFromSettings];
}

- (void)setMathRenderingDisabled:(id)sender
{
    [self setMathRenderingPolicyPreference:OMMarkdownMathRenderingPolicyDisabled];
}

- (void)setMathRenderingStyledText:(id)sender
{
    [self setMathRenderingPolicyPreference:OMMarkdownMathRenderingPolicyStyledText];
}

- (void)setMathRenderingExternalTools:(id)sender
{
    [self setMathRenderingPolicyPreference:OMMarkdownMathRenderingPolicyExternalTools];
}

- (void)toggleAllowRemoteImages:(id)sender
{
    [self setAllowRemoteImagesPreference:![self isAllowRemoteImagesEnabled]];
}

- (BOOL)isWordSelectionModifierShimEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDWordSelectionModifierShimDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return YES;
}

- (void)setWordSelectionModifierShimEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:OMDWordSelectionModifierShimDefaultsKey];
    [self syncPreferencesPanelFromSettings];
}

- (void)toggleWordSelectionModifierShim:(id)sender
{
    [self setWordSelectionModifierShimEnabled:![self isWordSelectionModifierShimEnabled]];
}

- (BOOL)isSourceVimKeyBindingsEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDSourceVimKeyBindingsDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return NO;
}

- (void)setSourceVimKeyBindingsEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:OMDSourceVimKeyBindingsDefaultsKey];
    if (!enabled) {
        [_sourceVimCommandLine release];
        _sourceVimCommandLine = nil;
    }
    [self configureSourceVimBindingController];
    [self syncPreferencesPanelFromSettings];
}

- (void)toggleSourceVimKeyBindings:(id)sender
{
    [self setSourceVimKeyBindingsEnabled:![self isSourceVimKeyBindingsEnabled]];
}

- (void)configureSourceVimBindingController
{
    if (_sourceTextView == nil) {
        [_sourceVimCommandLine release];
        _sourceVimCommandLine = nil;
        [_sourceVimBindingController release];
        _sourceVimBindingController = nil;
        return;
    }

    NSTextView *targetView = _sourceTextView;
    if (_sourceVimBindingController == nil ||
        [_sourceVimBindingController textView] != targetView) {
        [_sourceVimBindingController release];
        _sourceVimBindingController = [[GSVVimBindingController alloc] initWithTextView:targetView];
        [_sourceVimBindingController setDelegate:self];
        [_sourceVimBindingController setConfig:[GSVVimConfigLoader loadDefaultConfig]];
    }

    [_sourceVimBindingController setEnabled:[self isSourceVimKeyBindingsEnabled]];
    [self updatePreviewStatusIndicator];
}

- (BOOL)sourceTextView:(OMDSourceTextView *)textView handleVimKeyEvent:(NSEvent *)event
{
    if (textView == nil || event == nil || (NSTextView *)textView != _sourceTextView) {
        return NO;
    }

    if (_sourceVimBindingController == nil) {
        [self configureSourceVimBindingController];
    }
    if (_sourceVimBindingController == nil) {
        return NO;
    }

    return [_sourceVimBindingController handleKeyEvent:event];
}

- (BOOL)vimBindingController:(GSVVimBindingController *)controller
              handleExAction:(GSVVimExAction)action
                       force:(BOOL)force
                  rawCommand:(NSString *)rawCommand
                 forTextView:(NSTextView *)textView
{
    (void)controller;
    (void)rawCommand;

    if (textView == nil || textView != _sourceTextView) {
        return NO;
    }

    switch (action) {
        case GSVVimExActionWrite:
            return [self saveDocumentFromVimCommand];
        case GSVVimExActionQuit:
            [self performCloseFromVimCommandForcingDiscard:force];
            return YES;
        case GSVVimExActionWriteQuit:
            if (![self saveDocumentFromVimCommand]) {
                return NO;
            }
            [self performCloseFromVimCommandForcingDiscard:force];
            return YES;
        case GSVVimExActionUnknown:
        default:
            return NO;
    }
}

- (void)vimBindingController:(GSVVimBindingController *)controller
        didUpdateCommandLine:(NSString *)commandLine
                      active:(BOOL)active
                 forTextView:(NSTextView *)textView
{
    (void)controller;
    if (textView == nil || textView != _sourceTextView) {
        return;
    }

    [_sourceVimCommandLine release];
    _sourceVimCommandLine = nil;
    if (active && commandLine != nil && [commandLine length] > 0) {
        _sourceVimCommandLine = [commandLine copy];
    }
    [self updatePreviewStatusIndicator];
}

- (void)vimBindingController:(GSVVimBindingController *)controller
               didChangeMode:(GSVVimMode)mode
                 forTextView:(NSTextView *)textView
{
    (void)controller;
    (void)mode;
    (void)textView;
    [self updatePreviewStatusIndicator];
}

- (BOOL)isSourceSyntaxHighlightingEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDSourceSyntaxHighlightingDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return YES;
}

- (void)setSourceSyntaxHighlightingEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:OMDSourceSyntaxHighlightingDefaultsKey];
    if (enabled) {
        _sourceHighlightNeedsFullPass = YES;
        [self requestSourceSyntaxHighlightingRefresh];
    } else {
        [self cancelPendingSourceSyntaxHighlighting];
        [self clearSourceSyntaxHighlighting];
    }
    [self syncPreferencesPanelFromSettings];
}

- (void)toggleSourceSyntaxHighlighting:(id)sender
{
    [self setSourceSyntaxHighlightingEnabled:![self isSourceSyntaxHighlightingEnabled]];
}

- (BOOL)isSourceHighlightHighContrastEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDSourceHighlightHighContrastDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return NO;
}

- (void)setSourceHighlightHighContrastEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:OMDSourceHighlightHighContrastDefaultsKey];
    _sourceHighlightNeedsFullPass = YES;
    [self requestSourceSyntaxHighlightingRefresh];
    [self syncPreferencesPanelFromSettings];
}

- (void)toggleSourceHighlightHighContrast:(id)sender
{
    [self setSourceHighlightHighContrastEnabled:![self isSourceHighlightHighContrastEnabled]];
}

- (NSColor *)sourceHighlightAccentColor
{
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:OMDSourceHighlightAccentColorDefaultsKey];
    return OMDColorFromDefaultsString(stored);
}

- (void)setSourceHighlightAccentColor:(NSColor *)color
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *encoded = OMDColorDefaultsString(color);
    if (encoded == nil || [encoded length] == 0) {
        [defaults removeObjectForKey:OMDSourceHighlightAccentColorDefaultsKey];
    } else {
        [defaults setObject:encoded forKey:OMDSourceHighlightAccentColorDefaultsKey];
    }
    _sourceHighlightNeedsFullPass = YES;
    [self requestSourceSyntaxHighlightingRefresh];
    [self syncPreferencesPanelFromSettings];
}

- (BOOL)isTreeSitterAvailable
{
    return [OMMarkdownRenderer isTreeSitterAvailable];
}

- (BOOL)isRendererSyntaxHighlightingPreferenceEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDRendererSyntaxHighlightingDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return YES;
}

- (BOOL)isRendererSyntaxHighlightingEnabled
{
    if (![self isTreeSitterAvailable]) {
        return NO;
    }
    return [self isRendererSyntaxHighlightingPreferenceEnabled];
}

- (void)setRendererSyntaxHighlightingPreferenceEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:OMDRendererSyntaxHighlightingDefaultsKey];

    if (_renderer != nil) {
        OMMarkdownParsingOptions *existing = [_renderer parsingOptions];
        OMMarkdownParsingOptions *options = existing != nil ? [[existing copy] autorelease]
                                                            : [OMMarkdownParsingOptions defaultOptions];
        [options setCodeSyntaxHighlightingEnabled:(enabled && [self isTreeSitterAvailable])];
        [self applyParsingOptionsAndRender:options];
    } else {
        [self syncPreferencesPanelFromSettings];
    }
}

- (void)toggleRendererSyntaxHighlighting:(id)sender
{
    [self setRendererSyntaxHighlightingPreferenceEnabled:![self isRendererSyntaxHighlightingPreferenceEnabled]];
}

- (void)requestSourceSyntaxHighlightingRefresh
{
    if (_sourceTextView == nil) {
        return;
    }
    if (![self isSourceSyntaxHighlightingEnabled]) {
        [self cancelPendingSourceSyntaxHighlighting];
        return;
    }
    NSTimeInterval delay = OMDSourceSyntaxHighlightDebounceInterval;
    NSTextStorage *storage = [_sourceTextView textStorage];
    NSUInteger length = storage != nil ? [storage length] : 0;
    if (!_sourceHighlightNeedsFullPass && length > OMDSourceSyntaxIncrementalThreshold) {
        delay = OMDSourceSyntaxHighlightLargeDocDebounceInterval;
    }
    [self scheduleSourceSyntaxHighlightingAfterDelay:delay];
}

- (void)scheduleSourceSyntaxHighlightingAfterDelay:(NSTimeInterval)delay
{
    if (delay < 0.01) {
        delay = 0.01;
    }
    if (_sourceSyntaxHighlightTimer != nil) {
        [_sourceSyntaxHighlightTimer invalidate];
        [_sourceSyntaxHighlightTimer release];
        _sourceSyntaxHighlightTimer = nil;
    }
    _sourceSyntaxHighlightTimer = [[NSTimer scheduledTimerWithTimeInterval:delay
                                                                     target:self
                                                                   selector:@selector(sourceSyntaxHighlightTimerFired:)
                                                                   userInfo:nil
                                                                    repeats:NO] retain];
}

- (void)sourceSyntaxHighlightTimerFired:(NSTimer *)timer
{
    if (timer != _sourceSyntaxHighlightTimer) {
        return;
    }
    [_sourceSyntaxHighlightTimer invalidate];
    [_sourceSyntaxHighlightTimer release];
    _sourceSyntaxHighlightTimer = nil;
    [self applySourceSyntaxHighlightingNow];
}

- (void)cancelPendingSourceSyntaxHighlighting
{
    if (_sourceSyntaxHighlightTimer != nil) {
        [_sourceSyntaxHighlightTimer invalidate];
        [_sourceSyntaxHighlightTimer release];
        _sourceSyntaxHighlightTimer = nil;
    }
}

- (NSColor *)sourceEditorBaseTextColor
{
    NSColor *color = [NSColor textColor];
    if (color == nil) {
        color = [NSColor controlTextColor];
    }
    if (color == nil) {
        color = [NSColor blackColor];
    }
    return color;
}

- (NSRange)sourceSyntaxHighlightIncrementalRangeForStorage:(NSTextStorage *)storage
{
    if (storage == nil) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger length = [storage length];
    if (_sourceHighlightNeedsFullPass || length <= OMDSourceSyntaxIncrementalThreshold || _sourceTextView == nil) {
        return NSMakeRange(NSNotFound, 0);
    }

    NSString *text = [storage string];
    if (text == nil || [text length] == 0) {
        return NSMakeRange(NSNotFound, 0);
    }

    NSUInteger location = [_sourceTextView selectedRange].location;
    if (location > length) {
        location = length;
    }

    NSUInteger windowStart = location > OMDSourceSyntaxIncrementalContextChars
        ? (location - OMDSourceSyntaxIncrementalContextChars)
        : 0;
    NSUInteger windowEnd = location + OMDSourceSyntaxIncrementalContextChars;
    if (windowEnd > length) {
        windowEnd = length;
    }

    NSRange startLine = [text lineRangeForRange:NSMakeRange(windowStart, 0)];
    NSRange endLine;
    if (windowEnd >= length && length > 0) {
        endLine = [text lineRangeForRange:NSMakeRange(length - 1, 0)];
    } else {
        endLine = [text lineRangeForRange:NSMakeRange(windowEnd, 0)];
    }

    NSUInteger targetStart = startLine.location;
    NSUInteger targetEnd = NSMaxRange(endLine);
    if (targetEnd > length) {
        targetEnd = length;
    }
    if (targetEnd <= targetStart) {
        if (targetStart < length) {
            targetEnd = targetStart + 1;
        } else {
            return NSMakeRange(NSNotFound, 0);
        }
    }
    return NSMakeRange(targetStart, targetEnd - targetStart);
}

- (void)clearSourceSyntaxHighlighting
{
    if (_sourceTextView == nil) {
        return;
    }

    NSColor *baseColor = [self sourceEditorBaseTextColor];

    NSTextStorage *storage = [_sourceTextView textStorage];
    if (storage != nil && [storage length] > 0) {
        _isProgrammaticSourceHighlightUpdate = YES;
        @try {
            [storage beginEditing];
            [storage removeAttribute:NSForegroundColorAttributeName
                               range:NSMakeRange(0, [storage length])];
            [storage endEditing];
        } @finally {
            _isProgrammaticSourceHighlightUpdate = NO;
        }
    }

    NSMutableDictionary *typing = nil;
    NSDictionary *currentTyping = [_sourceTextView typingAttributes];
    if (currentTyping != nil) {
        typing = [currentTyping mutableCopy];
    } else {
        typing = [[NSMutableDictionary alloc] init];
    }
    NSFont *font = [_sourceTextView font];
    if (font != nil) {
        [typing setObject:font forKey:NSFontAttributeName];
    }
    [typing setObject:baseColor forKey:NSForegroundColorAttributeName];
    [_sourceTextView setTypingAttributes:typing];
    [typing release];
}

- (void)applySourceSyntaxHighlightingNow
{
    if (_sourceTextView == nil) {
        return;
    }
    if (![self isSourceSyntaxHighlightingEnabled]) {
        [self clearSourceSyntaxHighlighting];
        return;
    }

    NSTextStorage *storage = [_sourceTextView textStorage];
    if (storage == nil || [storage length] == 0) {
        return;
    }

    NSColor *baseColor = [self sourceEditorBaseTextColor];

    NSColor *backgroundColor = [_sourceTextView backgroundColor];
    if (backgroundColor == nil) {
        backgroundColor = [NSColor textBackgroundColor];
    }

    NSMutableDictionary *highlightOptions = [NSMutableDictionary dictionary];
    [highlightOptions setObject:[NSNumber numberWithBool:[self isSourceHighlightHighContrastEnabled]]
                         forKey:OMDSourceHighlighterOptionHighContrast];
    NSColor *accentColor = [self sourceHighlightAccentColor];
    if (accentColor != nil) {
        [highlightOptions setObject:accentColor forKey:OMDSourceHighlighterOptionAccentColor];
    }

    NSRange targetRange = [self sourceSyntaxHighlightIncrementalRangeForStorage:storage];
    BOOL fullPass = targetRange.location == NSNotFound;

    _isProgrammaticSourceHighlightUpdate = YES;
    @try {
        [OMDSourceHighlighter highlightTextStorage:storage
                                     baseTextColor:baseColor
                                   backgroundColor:backgroundColor
                                           options:highlightOptions
                                       targetRange:targetRange];
    } @finally {
        _isProgrammaticSourceHighlightUpdate = NO;
    }
    if (fullPass) {
        _sourceHighlightNeedsFullPass = NO;
    }

    NSMutableDictionary *typing = nil;
    NSDictionary *currentTyping = [_sourceTextView typingAttributes];
    if (currentTyping != nil) {
        typing = [currentTyping mutableCopy];
    } else {
        typing = [[NSMutableDictionary alloc] init];
    }
    NSFont *font = [_sourceTextView font];
    if (font != nil) {
        [typing setObject:font forKey:NSFontAttributeName];
    }
    [typing setObject:baseColor forKey:NSForegroundColorAttributeName];
    [_sourceTextView setTypingAttributes:typing];
    [typing release];
}

- (NSString *)currentGNUstepThemeName
{
    GSTheme *theme = [GSTheme theme];
    NSString *name = nil;
    if (theme != nil && [theme respondsToSelector:@selector(name)]) {
        name = [theme name];
    }
    if (name == nil || [name length] == 0) {
        name = [self themePreference];
    }
    return name;
}

- (OMDLayoutDensityMode)effectiveLayoutDensityMode
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDLayoutDensityDefaultsKey];
    if ([value respondsToSelector:@selector(integerValue)]) {
        return OMDClampedLayoutDensityMode([value integerValue]);
    }

    NSString *themeName = [[self currentGNUstepThemeName] lowercaseString];
    if (themeName != nil && [themeName rangeOfString:@"adwaita"].location != NSNotFound) {
        return OMDLayoutDensityModeAdwaita;
    }
    return OMDLayoutDensityModeBalanced;
}

- (void)setLayoutDensityPreference:(OMDLayoutDensityMode)mode
{
    OMDLayoutDensityMode clampedMode = OMDClampedLayoutDensityMode(mode);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasFormattingBarOverride = ([defaults objectForKey:OMDShowFormattingBarDefaultsKey] != nil);
    [defaults setInteger:(NSInteger)clampedMode
                                               forKey:OMDLayoutDensityDefaultsKey];
    if (!hasFormattingBarOverride) {
        _showFormattingBar = OMDDefaultFormattingBarEnabledForMode(clampedMode);
    }
    [self applyLayoutDensityPreference];
}

- (void)applyLayoutDensityPreference
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);

    if (_textView != nil) {
        [_textView setTextContainerInset:NSMakeSize(metrics.previewTextInsetX, metrics.previewTextInsetY)];
    }
    if (_sourceTextView != nil) {
        [_sourceTextView setTextContainerInset:NSMakeSize(metrics.sourceTextInsetX, metrics.sourceTextInsetY)];
    }

    if (_sourceEditorContainer != nil) {
        [self rebuildFormattingBar];
        [self layoutSourceEditorContainer];
    }

    if (_sidebarContainer != nil) {
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

    [self layoutWorkspaceChrome];
    [self updatePreviewStatusIndicator];

    if (_currentMarkdown != nil && [self isPreviewVisible]) {
        _lastRenderedLayoutWidth = -1.0;
        [self renderCurrentMarkdown];
    }

    if (_preferencesPanel != nil && [_preferencesPanel isVisible]) {
        [self rebuildPreferencesPanelContent];
        [self syncPreferencesPanelFromSettings];
    }
}

- (void)releasePreferencesPanelControls
{
    [_preferencesSectionControl release];
    _preferencesSectionControl = nil;
    [_preferencesMathPolicyPopup release];
    _preferencesMathPolicyPopup = nil;
    [_preferencesSplitSyncModePopup release];
    _preferencesSplitSyncModePopup = nil;
    [_preferencesThemePopup release];
    _preferencesThemePopup = nil;
    [_preferencesLayoutModePopup release];
    _preferencesLayoutModePopup = nil;
    [_preferencesScrollSpeedSlider release];
    _preferencesScrollSpeedSlider = nil;
    [_preferencesAllowRemoteImagesButton release];
    _preferencesAllowRemoteImagesButton = nil;
    [_preferencesFormattingBarButton release];
    _preferencesFormattingBarButton = nil;
    [_preferencesWordSelectionShimButton release];
    _preferencesWordSelectionShimButton = nil;
    [_preferencesSourceVimKeyBindingsButton release];
    _preferencesSourceVimKeyBindingsButton = nil;
    [_preferencesSyntaxHighlightingButton release];
    _preferencesSyntaxHighlightingButton = nil;
    [_preferencesSourceHighContrastButton release];
    _preferencesSourceHighContrastButton = nil;
    [_preferencesSourceAccentColorWell release];
    _preferencesSourceAccentColorWell = nil;
    [_preferencesSourceAccentResetButton release];
    _preferencesSourceAccentResetButton = nil;
    [_preferencesRendererSyntaxHighlightingButton release];
    _preferencesRendererSyntaxHighlightingButton = nil;
    [_preferencesRendererSyntaxHighlightingNoteLabel release];
    _preferencesRendererSyntaxHighlightingNoteLabel = nil;
    [_preferencesExplorerLocalRootField release];
    _preferencesExplorerLocalRootField = nil;
    [_preferencesExplorerMaxFileSizeField release];
    _preferencesExplorerMaxFileSizeField = nil;
    [_preferencesExplorerListFontSizeField release];
    _preferencesExplorerListFontSizeField = nil;
    [_preferencesExplorerGitHubTokenField release];
    _preferencesExplorerGitHubTokenField = nil;
}

- (void)normalizePreferencesPanelFrameForSize:(NSSize)size
{
    if (_preferencesPanel == nil) {
        return;
    }

    NSScreen *screen = [_window screen];
    if (screen == nil) {
        screen = [_preferencesPanel screen];
    }
    if (screen == nil) {
        screen = [NSScreen mainScreen];
    }
    if (screen == nil) {
        return;
    }

    NSRect visible = [screen visibleFrame];
    NSRect maxFrame = NSInsetRect(visible, 40.0, 48.0);
    if (maxFrame.size.width <= 0.0 || maxFrame.size.height <= 0.0) {
        maxFrame = visible;
    }

    NSRect maxContentRect = [_preferencesPanel contentRectForFrameRect:maxFrame];
    CGFloat minWidth = MIN(560.0, maxContentRect.size.width);
    CGFloat minHeight = MIN(360.0, maxContentRect.size.height);
    CGFloat width = size.width;
    CGFloat height = size.height;
    if (width > maxContentRect.size.width) {
        width = maxContentRect.size.width;
    }
    if (height > maxContentRect.size.height) {
        height = maxContentRect.size.height;
    }
    if (width < minWidth) {
        width = minWidth;
    }
    if (height < minHeight) {
        height = minHeight;
    }

    NSRect targetFrame = [_preferencesPanel frameRectForContentRect:NSMakeRect(0.0, 0.0, width, height)];
    NSRect frame = [_preferencesPanel frame];
    CGFloat x = frame.origin.x;
    CGFloat y = frame.origin.y;
    CGFloat top = NSMaxY(frame);
    BOOL center = !NSIntersectsRect(frame, visible);
    if (center) {
        x = visible.origin.x + floor((visible.size.width - targetFrame.size.width) * 0.5);
        y = visible.origin.y + floor((visible.size.height - targetFrame.size.height) * 0.5);
    } else {
        y = top - targetFrame.size.height;
        if (x < visible.origin.x) {
            x = visible.origin.x;
        }
        if ((x + targetFrame.size.width) > NSMaxX(visible)) {
            x = NSMaxX(visible) - targetFrame.size.width;
        }
        if (y < visible.origin.y) {
            y = visible.origin.y;
        }
        if ((y + targetFrame.size.height) > NSMaxY(visible)) {
            y = NSMaxY(visible) - targetFrame.size.height;
        }
    }

    [_preferencesPanel setFrame:NSIntegralRect(NSMakeRect(x,
                                                          y,
                                                          targetFrame.size.width,
                                                          targetFrame.size.height))
                        display:NO];
}

- (void)buildPreferencesAppearanceSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    OMDRoundedCardView *card = OMDCreatePreferencesCard(NSMakeRect(0.0,
                                                                   0.0,
                                                                   NSWidth([view bounds]),
                                                                   metrics.preferencesAppearanceCardHeight),
                                                        metrics);
    [view addSubview:card];

    CGFloat pad = metrics.preferencesCardPadding;
    CGFloat sectionWidth = NSWidth([card bounds]) - (pad * 2.0);
    CGFloat rowLabelWidth = MIN(metrics.preferencesLabelWidth + 20.0, floor(sectionWidth * 0.28));
    CGFloat controlX = pad + rowLabelWidth + 12.0;
    CGFloat controlWidth = sectionWidth - rowLabelWidth - 12.0;
    CGFloat rowY = pad + 52.0;
    NSColor *titleColor = OMDResolvedControlTextColor();
    NSColor *noteColor = OMDResolvedMutedTextColor();

    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad, sectionWidth, 20.0),
                                        @"Appearance",
                                        OMDPreferencesSectionTitleFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad + 22.0, sectionWidth, 20.0),
                                        @"Choose the active GNUstep theme and how roomy the interface should feel.",
                                        OMDPreferencesSectionSubtitleFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"GNUstep Theme",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesThemePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX,
                                                                             rowY,
                                                                             controlWidth,
                                                                             metrics.preferencesControlHeight)
                                                         pullsDown:NO];
    [_preferencesThemePopup setTarget:self];
    [_preferencesThemePopup setAction:@selector(preferencesThemeChanged:)];
    [_preferencesThemePopup setToolTip:@"Theme changes apply after relaunch."];
    [card addSubview:_preferencesThemePopup];

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"Layout Mode",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesLayoutModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX,
                                                                                  rowY,
                                                                                  controlWidth,
                                                                                  metrics.preferencesControlHeight)
                                                              pullsDown:NO];
    [_preferencesLayoutModePopup addItemWithTitle:@"Compact"];
    [[_preferencesLayoutModePopup itemAtIndex:0] setTag:OMDLayoutDensityModeCompact];
    [_preferencesLayoutModePopup addItemWithTitle:@"Balanced"];
    [[_preferencesLayoutModePopup itemAtIndex:1] setTag:OMDLayoutDensityModeBalanced];
    [_preferencesLayoutModePopup addItemWithTitle:@"Adwaita Style"];
    [[_preferencesLayoutModePopup itemAtIndex:2] setTag:OMDLayoutDensityModeAdwaita];
    [_preferencesLayoutModePopup setTarget:self];
    [_preferencesLayoutModePopup setAction:@selector(preferencesLayoutModeChanged:)];
    [_preferencesLayoutModePopup setToolTip:@"Switch between compact, balanced, and roomier Adwaita-style spacing."];
    [card addSubview:_preferencesLayoutModePopup];

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"Scroll Speed",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesScrollSpeedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(controlX,
                                                                               rowY,
                                                                               controlWidth,
                                                                               metrics.preferencesControlHeight)];
    [_preferencesScrollSpeedSlider setMinValue:OMDScrollSpeedMinimum];
    [_preferencesScrollSpeedSlider setMaxValue:OMDScrollSpeedMaximum];
    [_preferencesScrollSpeedSlider setContinuous:YES];
    [_preferencesScrollSpeedSlider setTarget:self];
    [_preferencesScrollSpeedSlider setAction:@selector(preferencesScrollSpeedChanged:)];
    [_preferencesScrollSpeedSlider setToolTip:@"Adjust how far the app scrolls for each wheel or trackpad step."];
    [card addSubview:_preferencesScrollSpeedSlider];

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad,
                                                   rowY,
                                                   sectionWidth,
                                                   metrics.preferencesNoteHeight),
                                        @"GNUstep's default scroll speed is at the left. Theme changes apply on next launch; layout mode and scroll speed update immediately.",
                                        OMDPreferencesNoteFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];
}

- (void)buildPreferencesExplorerSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    OMDRoundedCardView *card = OMDCreatePreferencesCard(NSMakeRect(0.0,
                                                                   0.0,
                                                                   NSWidth([view bounds]),
                                                                   metrics.preferencesExplorerCardHeight),
                                                        metrics);
    [view addSubview:card];

    CGFloat pad = metrics.preferencesCardPadding;
    CGFloat sectionWidth = NSWidth([card bounds]) - (pad * 2.0);
    CGFloat rowLabelWidth = MIN(metrics.preferencesLabelWidth + 20.0, floor(sectionWidth * 0.24));
    CGFloat controlX = pad + rowLabelWidth + 12.0;
    CGFloat controlWidth = sectionWidth - rowLabelWidth - 12.0;
    CGFloat rowY = pad + 52.0;
    NSColor *titleColor = OMDResolvedControlTextColor();
    NSColor *noteColor = OMDResolvedMutedTextColor();

    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad, sectionWidth, 20.0),
                                        @"Explorer",
                                        OMDPreferencesSectionTitleFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad + 22.0, sectionWidth, 20.0),
                                        @"Control the local browser root and GitHub integration defaults.",
                                        OMDPreferencesSectionSubtitleFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"Local Root",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];

    CGFloat browseWidth = metrics.preferencesSmallButtonWidth;
    CGFloat rootFieldWidth = controlWidth - browseWidth - 8.0;
    if (rootFieldWidth < 180.0) {
        rootFieldWidth = controlWidth;
        browseWidth = 0.0;
    }
    _preferencesExplorerLocalRootField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX,
                                                                                        rowY,
                                                                                        rootFieldWidth,
                                                                                        metrics.preferencesControlHeight)];
    [_preferencesExplorerLocalRootField setTarget:self];
    [_preferencesExplorerLocalRootField setAction:@selector(preferencesExplorerLocalRootChanged:)];
    [card addSubview:_preferencesExplorerLocalRootField];

    if (browseWidth > 0.0) {
        NSButton *browseButton = [[[NSButton alloc] initWithFrame:NSMakeRect(controlX + rootFieldWidth + 8.0,
                                                                             rowY,
                                                                             browseWidth,
                                                                             metrics.preferencesControlHeight)] autorelease];
        [browseButton setTitle:@"Browse..."];
        [browseButton setBezelStyle:NSRoundedBezelStyle];
        [browseButton setTarget:self];
        [browseButton setAction:@selector(preferencesExplorerLocalRootChanged:)];
        [card addSubview:browseButton];
    }

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"Max File Size",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesExplorerMaxFileSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX,
                                                                                          rowY,
                                                                                          metrics.preferencesSmallFieldWidth,
                                                                                          metrics.preferencesControlHeight)];
    [_preferencesExplorerMaxFileSizeField setTarget:self];
    [_preferencesExplorerMaxFileSizeField setAction:@selector(preferencesExplorerMaxFileSizeChanged:)];
    [card addSubview:_preferencesExplorerMaxFileSizeField];
    [card addSubview:OMDStaticTextField(NSMakeRect(controlX + metrics.preferencesSmallFieldWidth + 6.0,
                                                   rowY + 5.0,
                                                   28.0,
                                                   20.0),
                                        @"MB",
                                        OMDPreferencesLabelFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        NO)];

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"List Font",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesExplorerListFontSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX,
                                                                                           rowY,
                                                                                           metrics.preferencesSmallFieldWidth,
                                                                                           metrics.preferencesControlHeight)];
    [_preferencesExplorerListFontSizeField setTarget:self];
    [_preferencesExplorerListFontSizeField setAction:@selector(preferencesExplorerListFontSizeChanged:)];
    [card addSubview:_preferencesExplorerListFontSizeField];
    [card addSubview:OMDStaticTextField(NSMakeRect(controlX + metrics.preferencesSmallFieldWidth + 6.0,
                                                   rowY + 5.0,
                                                   28.0,
                                                   20.0),
                                        @"pt",
                                        OMDPreferencesLabelFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        NO)];

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"GitHub Token",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesExplorerGitHubTokenField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(controlX,
                                                                                                rowY,
                                                                                                controlWidth,
                                                                                                metrics.preferencesControlHeight)];
    [_preferencesExplorerGitHubTokenField setTarget:self];
    [_preferencesExplorerGitHubTokenField setAction:@selector(preferencesExplorerGitHubTokenChanged:)];
    [card addSubview:_preferencesExplorerGitHubTokenField];

    rowY += metrics.preferencesControlHeight + 8.0;
    [card addSubview:OMDStaticTextField(NSMakeRect(controlX,
                                                   rowY,
                                                   controlWidth,
                                                   metrics.preferencesNoteHeight),
                                        @"Optional. Raises GitHub API rate limits for repo browsing.",
                                        OMDPreferencesNoteFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];
}

- (void)buildPreferencesPreviewSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    CGFloat cardHeight = OMDPreferencesPreviewSectionHeightForMetrics(metrics);
    OMDRoundedCardView *card = OMDCreatePreferencesCard(NSMakeRect(0.0,
                                                                   0.0,
                                                                   NSWidth([view bounds]),
                                                                   cardHeight),
                                                        metrics);
    [view addSubview:card];

    CGFloat pad = metrics.preferencesCardPadding;
    CGFloat sectionWidth = NSWidth([card bounds]) - (pad * 2.0);
    CGFloat rowLabelWidth = MIN(metrics.preferencesLabelWidth + 24.0, floor(sectionWidth * 0.24));
    CGFloat controlX = pad + rowLabelWidth + 12.0;
    CGFloat controlWidth = sectionWidth - rowLabelWidth - 12.0;
    CGFloat rowY = pad + 52.0;
    NSColor *titleColor = OMDResolvedControlTextColor();
    NSColor *noteColor = OMDResolvedMutedTextColor();

    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad, sectionWidth, 20.0),
                                        @"Preview",
                                        OMDPreferencesSectionTitleFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad + 22.0, sectionWidth, 20.0),
                                        @"Tune preview sync, math rendering, remote media, and code-block highlighting together.",
                                        OMDPreferencesSectionSubtitleFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"Split Sync",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesSplitSyncModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX,
                                                                                      rowY,
                                                                                      controlWidth,
                                                                                      metrics.preferencesControlHeight)
                                                                 pullsDown:NO];
    [_preferencesSplitSyncModePopup addItemWithTitle:@"Independent"];
    [[_preferencesSplitSyncModePopup itemAtIndex:0] setTag:OMDSplitSyncModeUnlinked];
    [_preferencesSplitSyncModePopup addItemWithTitle:@"Linked Scrolling"];
    [[_preferencesSplitSyncModePopup itemAtIndex:1] setTag:OMDSplitSyncModeLinkedScrolling];
    [_preferencesSplitSyncModePopup addItemWithTitle:@"Follow Caret"];
    [[_preferencesSplitSyncModePopup itemAtIndex:2] setTag:OMDSplitSyncModeCaretSelectionFollow];
    [_preferencesSplitSyncModePopup setTarget:self];
    [_preferencesSplitSyncModePopup setAction:@selector(preferencesSplitSyncModeChanged:)];
    [card addSubview:_preferencesSplitSyncModePopup];

    rowY += metrics.preferencesControlHeight + 8.0;
    [card addSubview:OMDStaticTextField(NSMakeRect(controlX,
                                                   rowY,
                                                   controlWidth,
                                                   metrics.preferencesNoteHeight),
                                        @"Linked Scrolling follows pane scroll; Follow Caret tracks cursor and selection moves.",
                                        OMDPreferencesNoteFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];

    rowY += metrics.preferencesNoteHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"Math",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesMathPolicyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX,
                                                                                   rowY,
                                                                                   controlWidth,
                                                                                   metrics.preferencesControlHeight)
                                                              pullsDown:NO];
    [_preferencesMathPolicyPopup addItemWithTitle:@"Styled Text (Safe)"];
    [[_preferencesMathPolicyPopup itemAtIndex:0] setTag:OMMarkdownMathRenderingPolicyStyledText];
    [_preferencesMathPolicyPopup addItemWithTitle:@"Disabled (Literal $...$)"];
    [[_preferencesMathPolicyPopup itemAtIndex:1] setTag:OMMarkdownMathRenderingPolicyDisabled];
    [_preferencesMathPolicyPopup addItemWithTitle:@"External Tools (LaTeX)"];
    [[_preferencesMathPolicyPopup itemAtIndex:2] setTag:OMMarkdownMathRenderingPolicyExternalTools];
    [_preferencesMathPolicyPopup setTarget:self];
    [_preferencesMathPolicyPopup setAction:@selector(preferencesMathPolicyChanged:)];
    [card addSubview:_preferencesMathPolicyPopup];

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    _preferencesAllowRemoteImagesButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad,
                                                                                     rowY,
                                                                                     sectionWidth,
                                                                                     22.0)];
    [_preferencesAllowRemoteImagesButton setButtonType:NSSwitchButton];
    [_preferencesAllowRemoteImagesButton setTitle:@"Allow Remote Images"];
    [_preferencesAllowRemoteImagesButton setFont:OMDPreferencesLabelFont(metrics)];
    [_preferencesAllowRemoteImagesButton setTarget:self];
    [_preferencesAllowRemoteImagesButton setAction:@selector(preferencesAllowRemoteImagesChanged:)];
    [card addSubview:_preferencesAllowRemoteImagesButton];

    rowY += 28.0;
    _preferencesRendererSyntaxHighlightingButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad,
                                                                                               rowY,
                                                                                               sectionWidth,
                                                                                               22.0)];
    [_preferencesRendererSyntaxHighlightingButton setButtonType:NSSwitchButton];
    [_preferencesRendererSyntaxHighlightingButton setTitle:@"Renderer Syntax Highlighting (Code Blocks)"];
    [_preferencesRendererSyntaxHighlightingButton setFont:OMDPreferencesLabelFont(metrics)];
    [_preferencesRendererSyntaxHighlightingButton setTarget:self];
    [_preferencesRendererSyntaxHighlightingButton setAction:@selector(preferencesRendererSyntaxHighlightingChanged:)];
    [card addSubview:_preferencesRendererSyntaxHighlightingButton];

    rowY += 28.0;
    _preferencesRendererSyntaxHighlightingNoteLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + 22.0,
                                                                                                      rowY,
                                                                                                      sectionWidth - 22.0,
                                                                                                      metrics.preferencesNoteHeight)];
    [_preferencesRendererSyntaxHighlightingNoteLabel setBezeled:NO];
    [_preferencesRendererSyntaxHighlightingNoteLabel setEditable:NO];
    [_preferencesRendererSyntaxHighlightingNoteLabel setSelectable:NO];
    [_preferencesRendererSyntaxHighlightingNoteLabel setDrawsBackground:NO];
    [_preferencesRendererSyntaxHighlightingNoteLabel setFont:OMDPreferencesNoteFont(metrics)];
    [_preferencesRendererSyntaxHighlightingNoteLabel setTextColor:noteColor];
    if ([[_preferencesRendererSyntaxHighlightingNoteLabel cell] respondsToSelector:@selector(setWraps:)]) {
        [[_preferencesRendererSyntaxHighlightingNoteLabel cell] setWraps:YES];
    }
    [card addSubview:_preferencesRendererSyntaxHighlightingNoteLabel];
}

- (void)buildPreferencesEditorSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    OMDRoundedCardView *card = OMDCreatePreferencesCard(NSMakeRect(0.0,
                                                                   0.0,
                                                                   NSWidth([view bounds]),
                                                                   metrics.preferencesEditingCardHeight),
                                                        metrics);
    [view addSubview:card];

    CGFloat pad = metrics.preferencesCardPadding;
    CGFloat sectionWidth = NSWidth([card bounds]) - (pad * 2.0);
    CGFloat rowY = pad + 52.0;
    NSColor *titleColor = OMDResolvedControlTextColor();
    NSColor *noteColor = OMDResolvedMutedTextColor();

    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad, sectionWidth, 20.0),
                                        @"Editor",
                                        OMDPreferencesSectionTitleFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, pad + 22.0, sectionWidth, 20.0),
                                        @"Tweak source-editor behavior without crowding the main workspace.",
                                        OMDPreferencesSectionSubtitleFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];
    _preferencesFormattingBarButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad, rowY, sectionWidth, 22.0)];
    [_preferencesFormattingBarButton setButtonType:NSSwitchButton];
    [_preferencesFormattingBarButton setTitle:@"Show Formatting Bar in Edit and Split"];
    [_preferencesFormattingBarButton setFont:OMDPreferencesLabelFont(metrics)];
    [_preferencesFormattingBarButton setTarget:self];
    [_preferencesFormattingBarButton setAction:@selector(preferencesFormattingBarChanged:)];
    [card addSubview:_preferencesFormattingBarButton];

    rowY += 28.0;
    _preferencesWordSelectionShimButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad, rowY, sectionWidth, 22.0)];
    [_preferencesWordSelectionShimButton setButtonType:NSSwitchButton];
    [_preferencesWordSelectionShimButton setTitle:@"Ctrl/Cmd+Shift+Arrow Selects Words"];
    [_preferencesWordSelectionShimButton setFont:OMDPreferencesLabelFont(metrics)];
    [_preferencesWordSelectionShimButton setTarget:self];
    [_preferencesWordSelectionShimButton setAction:@selector(preferencesWordSelectionShimChanged:)];
    [card addSubview:_preferencesWordSelectionShimButton];

    rowY += 28.0;
    _preferencesSourceVimKeyBindingsButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad, rowY, sectionWidth, 22.0)];
    [_preferencesSourceVimKeyBindingsButton setButtonType:NSSwitchButton];
    [_preferencesSourceVimKeyBindingsButton setTitle:@"Enable Vim Key Bindings"];
    [_preferencesSourceVimKeyBindingsButton setFont:OMDPreferencesLabelFont(metrics)];
    [_preferencesSourceVimKeyBindingsButton setTarget:self];
    [_preferencesSourceVimKeyBindingsButton setAction:@selector(preferencesSourceVimKeyBindingsChanged:)];
    [card addSubview:_preferencesSourceVimKeyBindingsButton];

    rowY += 28.0;
    _preferencesSyntaxHighlightingButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad, rowY, sectionWidth, 22.0)];
    [_preferencesSyntaxHighlightingButton setButtonType:NSSwitchButton];
    [_preferencesSyntaxHighlightingButton setTitle:@"Source Syntax Highlighting"];
    [_preferencesSyntaxHighlightingButton setFont:OMDPreferencesLabelFont(metrics)];
    [_preferencesSyntaxHighlightingButton setTarget:self];
    [_preferencesSyntaxHighlightingButton setAction:@selector(preferencesSyntaxHighlightingChanged:)];
    [card addSubview:_preferencesSyntaxHighlightingButton];

    rowY += 28.0;
    _preferencesSourceHighContrastButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad + 20.0,
                                                                                      rowY,
                                                                                      sectionWidth - 20.0,
                                                                                      22.0)];
    [_preferencesSourceHighContrastButton setButtonType:NSSwitchButton];
    [_preferencesSourceHighContrastButton setTitle:@"High Contrast Source Highlighting"];
    [_preferencesSourceHighContrastButton setFont:OMDPreferencesLabelFont(metrics)];
    [_preferencesSourceHighContrastButton setTarget:self];
    [_preferencesSourceHighContrastButton setAction:@selector(preferencesSourceHighContrastChanged:)];
    [card addSubview:_preferencesSourceHighContrastButton];

    rowY += 32.0;
    CGFloat accentX = pad + 20.0;
    CGFloat accentRowWidth = sectionWidth - 20.0;
    [card addSubview:OMDStaticTextField(NSMakeRect(accentX, rowY + 4.0, accentRowWidth, 20.0),
                                        @"Accent Color",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];

    rowY += 24.0;
    CGFloat accentResetWidth = metrics.preferencesSmallButtonWidth;
    CGFloat accentWellWidth = accentRowWidth - accentResetWidth - 8.0;
    CGFloat accentResetX = accentX + accentRowWidth - accentResetWidth;
    CGFloat accentWellX = accentX;
    BOOL stackAccentReset = NO;
    if (accentWellWidth < 160.0) {
        accentWellWidth = accentRowWidth;
        stackAccentReset = YES;
    }

    _preferencesSourceAccentColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(accentWellX,
                                                                                      rowY,
                                                                                      accentWellWidth,
                                                                                      metrics.preferencesControlHeight)];
    [_preferencesSourceAccentColorWell setTarget:self];
    [_preferencesSourceAccentColorWell setAction:@selector(preferencesSourceAccentColorChanged:)];
    [card addSubview:_preferencesSourceAccentColorWell];

    if (stackAccentReset) {
        rowY += metrics.preferencesControlHeight + 8.0;
        accentResetX = accentX + accentRowWidth - accentResetWidth;
    }

    _preferencesSourceAccentResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(accentResetX,
                                                                                     rowY,
                                                                                     accentResetWidth,
                                                                                     metrics.preferencesControlHeight)];
    [_preferencesSourceAccentResetButton setTitle:@"Reset"];
    [_preferencesSourceAccentResetButton setBezelStyle:NSRoundedBezelStyle];
    [_preferencesSourceAccentResetButton setTarget:self];
    [_preferencesSourceAccentResetButton setAction:@selector(preferencesSourceAccentReset:)];
    [card addSubview:_preferencesSourceAccentResetButton];
}

- (NSView *)preferencesItemContainerForSection:(OMDPreferencesSection)section
                                   contentRect:(NSRect)contentRect
                                       metrics:(OMDLayoutMetrics)metrics
{
    OMDFlippedFillView *container = [[[OMDFlippedFillView alloc] initWithFrame:contentRect] autorelease];
    [container setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [container setFillColor:OMDResolvedPanelBackdropColor()];

    CGFloat contentHeight = OMDPreferencesSectionContentHeight(section, metrics);
    CGFloat documentHeight = MAX(contentHeight, NSHeight(contentRect));
    OMDFlippedFillView *documentView = [[[OMDFlippedFillView alloc] initWithFrame:NSMakeRect(0.0,
                                                                                              0.0,
                                                                                              NSWidth(contentRect),
                                                                                              documentHeight)] autorelease];
    [documentView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [documentView setFillColor:OMDResolvedPanelBackdropColor()];

    switch (section) {
        case OMDPreferencesSectionExplorer:
            [self buildPreferencesExplorerSectionInView:documentView metrics:metrics];
            break;
        case OMDPreferencesSectionPreview:
            [self buildPreferencesPreviewSectionInView:documentView metrics:metrics];
            break;
        case OMDPreferencesSectionEditor:
            [self buildPreferencesEditorSectionInView:documentView metrics:metrics];
            break;
        case OMDPreferencesSectionAppearance:
        default:
            [self buildPreferencesAppearanceSectionInView:documentView metrics:metrics];
            break;
    }

    if (contentHeight > NSHeight(contentRect)) {
        NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:[container bounds]] autorelease];
        [scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
        [scrollView setHasVerticalScroller:YES];
        [scrollView setHasHorizontalScroller:NO];
        [scrollView setAutohidesScrollers:YES];
        [scrollView setBorderType:NSNoBorder];
        [scrollView setDrawsBackground:NO];
        [scrollView setDocumentView:documentView];
        [container addSubview:scrollView];
    } else {
        [container addSubview:documentView];
    }

    return container;
}

- (void)rebuildPreferencesPanelContent
{
    if (_preferencesPanel == nil) {
        return;
    }

    [self releasePreferencesPanelControls];

    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
    OMDPreferencesSection selectedSection = OMDClampedPreferencesSection(_preferencesSelectedSection);
    CGFloat outerPadding = metrics.preferencesOuterPadding;
    CGFloat panelHeight = OMDPreferencesPanelHeightForSection(selectedSection, metrics);
    [self normalizePreferencesPanelFrameForSize:NSMakeSize(OMDPreferencesPanelWidthForMetrics(metrics), panelHeight)];

    NSRect panelBounds = [[_preferencesPanel contentView] bounds];
    CGFloat contentWidth = NSWidth(panelBounds) - (outerPadding * 2.0);
    if (contentWidth < 420.0) {
        contentWidth = 420.0;
    }

    OMDFlippedFillView *rootView = [[[OMDFlippedFillView alloc] initWithFrame:panelBounds] autorelease];
    [rootView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [rootView setFillColor:OMDResolvedPanelBackdropColor()];

    CGFloat sectionControlHeight = (metrics.scale > 1.05 ? 36.0 : 32.0);
    CGFloat sectionControlY = outerPadding;
    _preferencesSectionControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(outerPadding,
                                                                                      sectionControlY,
                                                                                      contentWidth,
                                                                                      sectionControlHeight)];
    [_preferencesSectionControl setAutoresizingMask:NSViewWidthSizable];
    if ([_preferencesSectionControl respondsToSelector:@selector(setFont:)]) {
        [_preferencesSectionControl setFont:OMDPreferencesSectionControlFont(metrics)];
    }
    [_preferencesSectionControl setSegmentCount:4];
    [_preferencesSectionControl setLabel:@"Appearance" forSegment:0];
    [_preferencesSectionControl setLabel:@"Explorer" forSegment:1];
    [_preferencesSectionControl setLabel:@"Preview" forSegment:2];
    [_preferencesSectionControl setLabel:@"Editor" forSegment:3];
    if ([[_preferencesSectionControl cell] respondsToSelector:@selector(setTrackingMode:)]) {
        [[_preferencesSectionControl cell] setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    }
    NSInteger segmentIndex = 0;
    for (; segmentIndex < 4; segmentIndex++) {
        CGFloat segmentWidth = floor(contentWidth / 4.0);
        if (segmentIndex == 3) {
            segmentWidth = contentWidth - floor(contentWidth / 4.0) * 3.0;
        }
        [_preferencesSectionControl setWidth:segmentWidth forSegment:segmentIndex];
    }
    _preferencesSelectedSection = (NSInteger)selectedSection;
    [_preferencesSectionControl setSelectedSegment:_preferencesSelectedSection];
    [_preferencesSectionControl setTarget:self];
    [_preferencesSectionControl setAction:@selector(preferencesSectionChanged:)];
    [rootView addSubview:_preferencesSectionControl];

    CGFloat contentY = sectionControlY + sectionControlHeight + 16.0;
    NSRect contentRect = NSMakeRect(outerPadding,
                                    contentY,
                                    contentWidth,
                                    NSHeight(panelBounds) - contentY - outerPadding);
    if (contentRect.size.height < 160.0) {
        contentRect.size.height = 160.0;
    }
    [rootView addSubview:[self preferencesItemContainerForSection:selectedSection
                                                      contentRect:contentRect
                                                          metrics:metrics]];

    [_preferencesPanel setContentView:rootView];
}

- (void)showPreferences:(id)sender
{
    (void)sender;
    if (_preferencesPanel == nil) {
        OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
        OMDPreferencesSection selectedSection = OMDClampedPreferencesSection(_preferencesSelectedSection);
        NSRect frame = NSMakeRect(160,
                                  140,
                                  OMDPreferencesPanelWidthForMetrics(metrics),
                                  OMDPreferencesPanelHeightForSection(selectedSection, metrics));
        _preferencesPanel = [[NSPanel alloc] initWithContentRect:frame
                                                        styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        [_preferencesPanel setTitle:@"Preferences"];
        [_preferencesPanel setFrameAutosaveName:@"ObjcMarkdownViewerPreferencesPanel"];
        [_preferencesPanel setReleasedWhenClosed:NO];
    }

    [self rebuildPreferencesPanelContent];
    [self syncPreferencesPanelFromSettings];
    [_preferencesPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showAboutPanel:(id)sender
{
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSString *appName = OMDInfoStringForKey(@"ApplicationName");
    if (appName == nil || [appName length] == 0) {
        appName = [[NSProcessInfo processInfo] processName];
    }
    if (appName != nil && [appName length] > 0) {
        [options setObject:appName forKey:@"ApplicationName"];
    }

    NSString *release = OMDInfoStringForKey(@"ApplicationRelease");
    if (release == nil || [release length] == 0) {
        release = OMDInfoStringForKey(@"ApplicationVersion");
    }
    if (release == nil || [release length] == 0) {
        release = OMDInfoStringForKey(@"CFBundleShortVersionString");
    }
    if (release != nil && [release length] > 0) {
        [options setObject:release forKey:@"ApplicationRelease"];
    }

    id authors = OMDInfoValueForKey(@"Authors");
    if ([authors isKindOfClass:[NSArray class]] && [(NSArray *)authors count] > 0) {
        [options setObject:authors forKey:@"Authors"];
    } else if ([authors isKindOfClass:[NSString class]] && [(NSString *)authors length] > 0) {
        [options setObject:[NSArray arrayWithObject:authors] forKey:@"Authors"];
    }

    NSString *copyright = OMDInfoStringForKey(@"Copyright");
    if (copyright == nil || [copyright length] == 0) {
        copyright = OMDInfoStringForKey(@"NSHumanReadableCopyright");
    }
    if (copyright != nil && [copyright length] > 0) {
        [options setObject:copyright forKey:@"Copyright"];
    }

    NSImage *icon = [NSApp applicationIconImage];
    if (icon != nil) {
        [options setObject:icon forKey:@"ApplicationIcon"];
    }

    if ([options count] > 0 && [NSApp respondsToSelector:@selector(orderFrontStandardAboutPanelWithOptions:)]) {
        [NSApp orderFrontStandardAboutPanelWithOptions:options];
    } else {
        [NSApp orderFrontStandardAboutPanel:sender];
    }
}

- (void)syncPreferencesPanelFromSettings
{
    if (_preferencesPanel == nil) {
        return;
    }

    if (_preferencesSectionControl != nil) {
        _preferencesSelectedSection = (NSInteger)OMDClampedPreferencesSection(_preferencesSelectedSection);
        [_preferencesSectionControl setSelectedSegment:_preferencesSelectedSection];
    }

    if (_preferencesThemePopup != nil) {
        [self reloadThemePopupItems];
        NSString *themeName = [self themePreference];
        NSInteger themeIndex = 0;
        NSInteger themeCount = [_preferencesThemePopup numberOfItems];
        NSInteger index = 0;
        BOOL matched = NO;
        for (; index < themeCount; index++) {
            id<NSMenuItem> item = [_preferencesThemePopup itemAtIndex:index];
            NSString *value = [item representedObject];
            if (themeName == nil || [themeName length] == 0) {
                if (value == nil || [value length] == 0) {
                    themeIndex = index;
                    matched = YES;
                    break;
                }
            } else if (value != nil && [value isEqualToString:themeName]) {
                themeIndex = index;
                matched = YES;
                break;
            }
        }
        if (!matched && themeName != nil && [themeName length] > 0) {
            [_preferencesThemePopup addItemWithTitle:themeName];
            id<NSMenuItem> newItem = [_preferencesThemePopup itemAtIndex:[_preferencesThemePopup numberOfItems] - 1];
            [newItem setRepresentedObject:themeName];
            themeIndex = [_preferencesThemePopup indexOfItem:newItem];
        }
        [_preferencesThemePopup selectItemAtIndex:themeIndex];
    }

    if (_preferencesLayoutModePopup != nil) {
        OMDLayoutDensityMode mode = [self effectiveLayoutDensityMode];
        NSInteger selectedIndex = 0;
        NSInteger itemCount = [_preferencesLayoutModePopup numberOfItems];
        NSInteger index = 0;
        for (; index < itemCount; index++) {
            id<NSMenuItem> item = [_preferencesLayoutModePopup itemAtIndex:index];
            if ([item tag] == (NSInteger)mode) {
                selectedIndex = index;
                break;
            }
        }
        [_preferencesLayoutModePopup selectItemAtIndex:selectedIndex];
    }
    if (_preferencesScrollSpeedSlider != nil) {
        [_preferencesScrollSpeedSlider setDoubleValue:[self scrollSpeedPreference]];
    }

    if (_preferencesSplitSyncModePopup != nil) {
        OMDSplitSyncMode splitSyncMode = [self currentSplitSyncMode];
        NSInteger splitSelectedIndex = 0;
        NSInteger splitItemCount = [_preferencesSplitSyncModePopup numberOfItems];
        NSInteger splitIndex = 0;
        for (; splitIndex < splitItemCount; splitIndex++) {
            id<NSMenuItem> splitItem = [_preferencesSplitSyncModePopup itemAtIndex:splitIndex];
            if ([splitItem tag] == (NSInteger)splitSyncMode) {
                splitSelectedIndex = splitIndex;
                break;
            }
        }
        [_preferencesSplitSyncModePopup selectItemAtIndex:splitSelectedIndex];
    }

    OMMarkdownMathRenderingPolicy policy = [self currentMathRenderingPolicy];
    if (_preferencesMathPolicyPopup != nil) {
        NSInteger selectedIndex = 0;
        NSInteger itemCount = [_preferencesMathPolicyPopup numberOfItems];
        NSInteger index = 0;
        for (; index < itemCount; index++) {
            id<NSMenuItem> item = [_preferencesMathPolicyPopup itemAtIndex:index];
            if ([item tag] == (NSInteger)policy) {
                selectedIndex = index;
                break;
            }
        }
        [_preferencesMathPolicyPopup selectItemAtIndex:selectedIndex];
    }
    if (_preferencesAllowRemoteImagesButton != nil) {
        [_preferencesAllowRemoteImagesButton setState:([self isAllowRemoteImagesEnabled] ? NSOnState : NSOffState)];
    }
    if (_preferencesFormattingBarButton != nil) {
        [_preferencesFormattingBarButton setState:([self isFormattingBarEnabledPreference] ? NSOnState : NSOffState)];
    }
    if (_preferencesWordSelectionShimButton != nil) {
        [_preferencesWordSelectionShimButton setState:([self isWordSelectionModifierShimEnabled] ? NSOnState : NSOffState)];
    }
    if (_preferencesSourceVimKeyBindingsButton != nil) {
        [_preferencesSourceVimKeyBindingsButton setState:([self isSourceVimKeyBindingsEnabled] ? NSOnState : NSOffState)];
    }
    if (_preferencesSyntaxHighlightingButton != nil) {
        [_preferencesSyntaxHighlightingButton setState:([self isSourceSyntaxHighlightingEnabled] ? NSOnState : NSOffState)];
    }
    BOOL sourceHighlightingEnabled = [self isSourceSyntaxHighlightingEnabled];
    if (_preferencesSourceHighContrastButton != nil) {
        [_preferencesSourceHighContrastButton setState:([self isSourceHighlightHighContrastEnabled] ? NSOnState : NSOffState)];
        [_preferencesSourceHighContrastButton setEnabled:sourceHighlightingEnabled];
    }
    if (_preferencesSourceAccentColorWell != nil) {
        NSColor *accent = [self sourceHighlightAccentColor];
        if (accent == nil) {
            accent = [NSColor colorWithCalibratedRed:0.00 green:0.36 blue:0.74 alpha:1.0];
        }
        [_preferencesSourceAccentColorWell setColor:accent];
        [_preferencesSourceAccentColorWell setEnabled:sourceHighlightingEnabled];
    }
    if (_preferencesSourceAccentResetButton != nil) {
        [_preferencesSourceAccentResetButton setEnabled:(sourceHighlightingEnabled && [self sourceHighlightAccentColor] != nil)];
    }

    BOOL treeSitterAvailable = [self isTreeSitterAvailable];
    if (_preferencesRendererSyntaxHighlightingButton != nil) {
        [_preferencesRendererSyntaxHighlightingButton setEnabled:treeSitterAvailable];
        [_preferencesRendererSyntaxHighlightingButton setState:([self isRendererSyntaxHighlightingEnabled] ? NSOnState : NSOffState)];
    }
    if (_preferencesRendererSyntaxHighlightingNoteLabel != nil) {
        if (treeSitterAvailable) {
            [_preferencesRendererSyntaxHighlightingNoteLabel setTextColor:[NSColor controlTextColor]];
            [_preferencesRendererSyntaxHighlightingNoteLabel setStringValue:@"Tree-sitter detected. Renderer syntax highlighting can be toggled here."];
        } else {
            [_preferencesRendererSyntaxHighlightingNoteLabel setTextColor:[NSColor disabledControlTextColor]];
            [_preferencesRendererSyntaxHighlightingNoteLabel setStringValue:@"Renderer syntax highlighting requires Tree-sitter (install tree-sitter-cli and libtree-sitter-dev)."];
        }
    }

    if (_preferencesExplorerLocalRootField != nil) {
        NSString *root = [self explorerLocalRootPathPreference];
        [_preferencesExplorerLocalRootField setStringValue:(root != nil ? root : @"")];
    }
    if (_preferencesExplorerMaxFileSizeField != nil) {
        NSUInteger megabytes = [self explorerMaxOpenFileSizeBytes] / (1024U * 1024U);
        [_preferencesExplorerMaxFileSizeField setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)megabytes]];
    }
    if (_preferencesExplorerListFontSizeField != nil) {
        CGFloat listFontSize = [self explorerListFontSizePreference];
        if (fabs(listFontSize - round(listFontSize)) < 0.05) {
            [_preferencesExplorerListFontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", listFontSize]];
        } else {
            [_preferencesExplorerListFontSizeField setStringValue:[NSString stringWithFormat:@"%.1f", listFontSize]];
        }
    }
    if (_preferencesExplorerGitHubTokenField != nil) {
        NSString *token = [self explorerGitHubTokenPreference];
        [_preferencesExplorerGitHubTokenField setStringValue:(token != nil ? token : @"")];
    }
}

- (void)preferencesSplitSyncModeChanged:(id)sender
{
    id<NSMenuItem> item = [_preferencesSplitSyncModePopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMDSplitSyncModeLinkedScrolling;
    [self setSplitSyncModePreference:OMDSplitSyncModeFromInteger(tag)];
}

- (void)preferencesLayoutModeChanged:(id)sender
{
    (void)sender;
    id<NSMenuItem> item = [_preferencesLayoutModePopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMDLayoutDensityModeBalanced;
    [self setLayoutDensityPreference:OMDClampedLayoutDensityMode(tag)];
}

- (void)preferencesScrollSpeedChanged:(id)sender
{
    (void)sender;
    CGFloat scrollSpeed = (_preferencesScrollSpeedSlider != nil
                           ? (CGFloat)[_preferencesScrollSpeedSlider doubleValue]
                           : [self scrollSpeedPreference]);
    [self setScrollSpeedPreference:scrollSpeed];
}

- (void)preferencesSectionChanged:(id)sender
{
    (void)sender;
    NSInteger selectedSegment = (_preferencesSectionControl != nil
                                 ? [_preferencesSectionControl selectedSegment]
                                 : _preferencesSelectedSection);
    OMDPreferencesSection selectedSection = OMDClampedPreferencesSection(selectedSegment);
    if ((NSInteger)selectedSection == _preferencesSelectedSection) {
        return;
    }
    _preferencesSelectedSection = (NSInteger)selectedSection;
    [self rebuildPreferencesPanelContent];
    [self syncPreferencesPanelFromSettings];
}

- (void)preferencesMathPolicyChanged:(id)sender
{
    id<NSMenuItem> item = [_preferencesMathPolicyPopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMMarkdownMathRenderingPolicyStyledText;
    OMMarkdownMathRenderingPolicy policy = OMDMathRenderingPolicyFromInteger(tag);
    [self setMathRenderingPolicyPreference:policy];
}

- (void)preferencesAllowRemoteImagesChanged:(id)sender
{
    BOOL allow = [_preferencesAllowRemoteImagesButton state] == NSOnState;
    [self setAllowRemoteImagesPreference:allow];
}

- (void)preferencesWordSelectionShimChanged:(id)sender
{
    BOOL enabled = [_preferencesWordSelectionShimButton state] == NSOnState;
    [self setWordSelectionModifierShimEnabled:enabled];
}

- (void)preferencesFormattingBarChanged:(id)sender
{
    BOOL enabled = [_preferencesFormattingBarButton state] == NSOnState;
    [self setFormattingBarEnabledPreference:enabled];
}

- (void)preferencesSourceVimKeyBindingsChanged:(id)sender
{
    BOOL enabled = [_preferencesSourceVimKeyBindingsButton state] == NSOnState;
    [self setSourceVimKeyBindingsEnabled:enabled];
}

- (void)preferencesSyntaxHighlightingChanged:(id)sender
{
    BOOL enabled = [_preferencesSyntaxHighlightingButton state] == NSOnState;
    [self setSourceSyntaxHighlightingEnabled:enabled];
}

- (void)preferencesSourceHighContrastChanged:(id)sender
{
    BOOL enabled = [_preferencesSourceHighContrastButton state] == NSOnState;
    [self setSourceHighlightHighContrastEnabled:enabled];
}

- (void)preferencesSourceAccentColorChanged:(id)sender
{
    [self setSourceHighlightAccentColor:[_preferencesSourceAccentColorWell color]];
}

- (void)preferencesSourceAccentReset:(id)sender
{
    [self setSourceHighlightAccentColor:nil];
}

- (void)preferencesRendererSyntaxHighlightingChanged:(id)sender
{
    if (![self isTreeSitterAvailable]) {
        return;
    }
    BOOL enabled = [_preferencesRendererSyntaxHighlightingButton state] == NSOnState;
    [self setRendererSyntaxHighlightingPreferenceEnabled:enabled];
}

- (void)preferencesThemeChanged:(id)sender
{
    (void)sender;
    id<NSMenuItem> item = [_preferencesThemePopup selectedItem];
    NSString *themeName = [item representedObject];
    if (themeName == nil || [themeName length] == 0) {
        [self setThemePreference:nil];
    } else {
        [self setThemePreference:themeName];
    }
    [self syncPreferencesPanelFromSettings];
    [self showThemeRestartNotice];
}

- (void)preferencesExplorerLocalRootChanged:(id)sender
{
    if (sender != nil && sender != _preferencesExplorerLocalRootField) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setCanChooseDirectories:YES];
        [panel setCanChooseFiles:NO];
        [panel setAllowsMultipleSelection:NO];
        if ([panel respondsToSelector:@selector(setCanCreateDirectories:)]) {
            [panel setCanCreateDirectories:YES];
        }
        [panel setTitle:@"Choose Local Explorer Root"];
        [panel setPrompt:@"Choose"];

        NSString *startingPath = (_preferencesExplorerLocalRootField != nil
                                  ? [_preferencesExplorerLocalRootField stringValue]
                                  : nil);
        startingPath = OMDTrimmedString(startingPath);
        if ([startingPath length] == 0) {
            startingPath = [self explorerLocalRootPathPreference];
        }
        if ([startingPath length] == 0) {
            startingPath = NSHomeDirectory();
        }
        if ([startingPath length] > 0) {
            [panel setDirectory:[startingPath stringByExpandingTildeInPath]];
        }

        NSInteger result = [panel runModal];
        if (result != NSOKButton && result != NSFileHandlingPanelOKButton) {
            return;
        }
        NSArray *selectedPaths = OMDSelectedPathsFromOpenPanel(panel);
        NSString *path = [selectedPaths count] > 0 ? [selectedPaths objectAtIndex:0] : nil;
        if (path != nil && [path length] > 0 && _preferencesExplorerLocalRootField != nil) {
            [_preferencesExplorerLocalRootField setStringValue:path];
        }
    }

    NSString *path = (_preferencesExplorerLocalRootField != nil
                      ? [_preferencesExplorerLocalRootField stringValue]
                      : @"");
    [self setExplorerLocalRootPathPreference:path];
    [self syncPreferencesPanelFromSettings];
}

- (void)preferencesExplorerMaxFileSizeChanged:(id)sender
{
    (void)sender;
    NSString *value = (_preferencesExplorerMaxFileSizeField != nil
                       ? [_preferencesExplorerMaxFileSizeField stringValue]
                       : @"");
    NSInteger megabytes = [OMDTrimmedString(value) integerValue];
    if (megabytes < 1) {
        megabytes = 1;
    }
    [self setExplorerMaxOpenFileSizeMBPreference:(NSUInteger)megabytes];
    [self syncPreferencesPanelFromSettings];
}

- (void)preferencesExplorerListFontSizeChanged:(id)sender
{
    (void)sender;
    NSString *value = (_preferencesExplorerListFontSizeField != nil
                       ? [_preferencesExplorerListFontSizeField stringValue]
                       : @"");
    CGFloat fontSize = (CGFloat)[OMDTrimmedString(value) doubleValue];
    if (fontSize <= 0.0) {
        fontSize = OMDExplorerListDefaultFontSize;
    }
    [self setExplorerListFontSizePreference:fontSize];
    [self syncPreferencesPanelFromSettings];
}

- (void)preferencesExplorerGitHubTokenChanged:(id)sender
{
    (void)sender;
    NSString *token = (_preferencesExplorerGitHubTokenField != nil
                       ? [_preferencesExplorerGitHubTokenField stringValue]
                       : @"");
    [self setExplorerGitHubTokenPreference:token];
    [self syncPreferencesPanelFromSettings];
}

- (NSString *)themePreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *globalDomain = [defaults persistentDomainForName:NSGlobalDomain];
    id value = [globalDomain objectForKey:OMDThemeDefaultsKey];
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return (NSString *)value;
    }

    // Fall back to any older app-domain value so existing local settings
    // still appear in the UI until they are rewritten into the global domain.
    value = [defaults objectForKey:OMDThemeDefaultsKey];
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return (NSString *)value;
    }

    return nil;
}

- (void)setThemePreference:(NSString *)themeName
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *globalDomain = nil;
    NSDictionary *existingGlobalDomain = [defaults persistentDomainForName:NSGlobalDomain];
    if (existingGlobalDomain != nil) {
        globalDomain = [[existingGlobalDomain mutableCopy] autorelease];
    } else {
        globalDomain = [NSMutableDictionary dictionary];
    }

    // Remove any app-local copy so GSTheme resolves consistently from the
    // same global domain GNUstep's own preferences pane uses.
    [defaults removeObjectForKey:OMDThemeDefaultsKey];

    if (themeName == nil || [themeName length] == 0) {
        [globalDomain removeObjectForKey:OMDThemeDefaultsKey];
        [defaults setPersistentDomain:globalDomain forName:NSGlobalDomain];
        [defaults synchronize];
        return;
    }

    [globalDomain setObject:themeName forKey:OMDThemeDefaultsKey];
    [defaults setPersistentDomain:globalDomain forName:NSGlobalDomain];
    [defaults synchronize];
}

- (NSArray *)availableThemeNames
{
    NSMutableSet *names = [NSMutableSet set];
    NSArray *libraryPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask, YES);
    NSFileManager *manager = [NSFileManager defaultManager];

    for (NSString *libraryPath in libraryPaths) {
        if (libraryPath == nil || [libraryPath length] == 0) {
            continue;
        }
        NSString *themesPath = [libraryPath stringByAppendingPathComponent:@"Themes"];
        BOOL isDir = NO;
        if (![manager fileExistsAtPath:themesPath isDirectory:&isDir] || !isDir) {
            continue;
        }
        NSArray *entries = [manager contentsOfDirectoryAtPath:themesPath error:nil];
        for (NSString *entry in entries) {
            if ([[entry pathExtension] caseInsensitiveCompare:@"theme"] != NSOrderedSame) {
                continue;
            }
            NSString *name = [entry stringByDeletingPathExtension];
            if (name != nil &&
                [name length] > 0 &&
                [name caseInsensitiveCompare:@"GNUstep"] != NSOrderedSame) {
                [names addObject:name];
            }
        }
    }

    NSArray *sorted = [[names allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    return sorted;
}

- (void)reloadThemePopupItems
{
    if (_preferencesThemePopup == nil) {
        return;
    }
    [_preferencesThemePopup removeAllItems];
    [_preferencesThemePopup addItemWithTitle:@"GNUstep"];
    [[_preferencesThemePopup itemAtIndex:0] setRepresentedObject:@""];
    NSArray *themes = [self availableThemeNames];
    for (NSString *name in themes) {
        [_preferencesThemePopup addItemWithTitle:name];
        id<NSMenuItem> item = [_preferencesThemePopup itemAtIndex:[_preferencesThemePopup numberOfItems] - 1];
        [item setRepresentedObject:name];
    }
}

- (void)showThemeRestartNotice
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Theme change will apply on next launch."];
    [alert setInformativeText:@"Close and reopen the app to load the selected GNUstep theme."];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
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
    if (font == nil || !OMDFontIsMonospaced(font)) {
        font = [NSFont userFixedPitchFontOfSize:fontSize];
    }
    if (font == nil || !OMDFontIsMonospaced(font)) {
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

    if (!OMDFontIsMonospaced(resolved)) {
        NSFont *fallback = [NSFont userFixedPitchFontOfSize:size];
        if (fallback == nil || !OMDFontIsMonospaced(fallback)) {
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
    _sourceHighlightNeedsFullPass = YES;
    [self requestSourceSyntaxHighlightingRefresh];

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
    [self setSourceEditorFont:converted persistPreference:YES];
}

- (BOOL)isPreviewVisible
{
    return _viewerMode != OMDViewerModeEdit;
}

- (NSColor *)modeLabelTextColor
{
    return OMDResolvedControlTextColor();
}

- (void)updateWindowTitle
{
    if (_window == nil) {
        return;
    }

    [self updateToolbarActionControlsState];

    NSString *baseTitle = nil;
    if (_currentDisplayTitle != nil && [_currentDisplayTitle length] > 0) {
        baseTitle = _currentDisplayTitle;
    } else if (_currentPath != nil) {
        baseTitle = [_currentPath lastPathComponent];
    } else {
        baseTitle = @"Markdown Viewer";
    }
    NSString *modeTitle = OMDViewerModeTitle(_viewerMode);
    NSString *readOnlyMarker = _currentDocumentReadOnly ? @" [read-only]" : @"";
    NSString *dirtyMarker = _sourceIsDirty ? @" *" : @"";
    NSString *updatingMarker = _previewIsUpdating ? @" [updating]" : @"";
    [_window setTitle:[NSString stringWithFormat:@"%@%@%@ (%@%@)", baseTitle, readOnlyMarker, dirtyMarker, modeTitle, updatingMarker]];
}

- (void)updateCodeBlockButtons
{
    [self hideCopyFeedback];

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
    NSPoint textOrigin = [_textView textContainerOrigin];
    NSSize blockPadding = NSMakeSize(12.0, 8.0);
    if ([_textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *codeView = (OMDTextView *)_textView;
        if (codeView.codeBlockPadding.width > 0.0 && codeView.codeBlockPadding.height > 0.0) {
            blockPadding = codeView.codeBlockPadding;
        }
    }

    for (NSValue *value in ranges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            index++;
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        if (glyphRange.length == 0) {
            index++;
            continue;
        }

        NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];

        CGFloat buttonWidth = 20.0;
        CGFloat buttonHeight = 20.0;
        NSRect blockBounds = NSMakeRect(textOrigin.x + blockRect.origin.x - blockPadding.width,
                                        textOrigin.y + blockRect.origin.y - blockPadding.height,
                                        blockRect.size.width + (blockPadding.width * 2.0),
                                        blockRect.size.height + (blockPadding.height * 2.0));
        if (blockBounds.size.width < 1.0 || blockBounds.size.height < 1.0) {
            index++;
            continue;
        }

        CGFloat x = NSMaxX(blockBounds) - buttonWidth - 6.0;
        CGFloat y = 0.0;
        if ([_textView isFlipped]) {
            y = NSMinY(blockBounds) + 4.0;
        } else {
            y = NSMaxY(blockBounds) - buttonHeight - 4.0;
        }

        CGFloat minX = 2.0;
        CGFloat maxX = NSWidth([_textView bounds]) - buttonWidth - 2.0;
        if (x < minX) {
            x = minX;
        }
        if (x > maxX) {
            x = maxX;
        }

        CGFloat minY = 2.0;
        CGFloat maxY = NSHeight([_textView bounds]) - buttonHeight - 2.0;
        if (y < minY) {
            y = minY;
        }
        if (y > maxY) {
            y = maxY;
        }

        NSRect buttonFrame = NSIntegralRect(NSMakeRect(x, y, buttonWidth, buttonHeight));
        OMDCodeCopyButton *button = [[OMDCodeCopyButton alloc] initWithFrame:buttonFrame];
        [self applyCopyButtonDefaultAppearance:button];
        [button setButtonType:NSMomentaryChangeButton];
        [button setBordered:NO];
        [button setToolTip:@"Copy code block"];
        id buttonCell = [button cell];
        if (buttonCell != nil && [buttonCell respondsToSelector:@selector(setImageScaling:)]) {
            [buttonCell setImageScaling:NSImageScaleNone];
        }
        if (buttonCell != nil && [buttonCell respondsToSelector:@selector(setHighlightsBy:)]) {
            [buttonCell setHighlightsBy:NSNoCellMask];
        }
        [button setTarget:self];
        [button setAction:@selector(copyCodeBlock:)];
        [button setTag:index];
        [_textView addSubview:button];
        [_codeBlockButtons addObject:button];
        [button release];
        index++;
    }
}

- (void)applyCopyButtonDefaultAppearance:(NSButton *)button
{
    if (button == nil) {
        return;
    }

    NSImage *copyImage = OMDCodeBlockCopyImage();
    if (copyImage != nil) {
        [button setImage:copyImage];
        [button setImagePosition:NSImageOnly];
        [button setTitle:@""];
        return;
    }

    NSFont *buttonFont = [NSFont systemFontOfSize:10.0];
    if (buttonFont == nil) {
        buttonFont = [NSFont systemFontOfSize:9.0];
    }
    NSDictionary *buttonAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      buttonFont, NSFontAttributeName,
                                      [NSColor colorWithCalibratedWhite:0.56 alpha:1.0], NSForegroundColorAttributeName,
                                      nil];
    NSAttributedString *buttonTitle = [[[NSAttributedString alloc] initWithString:@"copy"
                                                                        attributes:buttonAttributes] autorelease];
    [button setAttributedTitle:buttonTitle];
    [button setImage:nil];
    [button setImagePosition:NSNoImage];
}

- (void)showCopyFeedbackForButton:(NSButton *)button
{
    [self hideCopyFeedback];
    if (button == nil) {
        return;
    }

    _copyFeedbackButton = [button retain];

    NSImage *checkImage = OMDCodeBlockCopiedCheckImage();
    if (checkImage != nil) {
        [_copyFeedbackButton setImage:checkImage];
        [_copyFeedbackButton setImagePosition:NSImageOnly];
        [_copyFeedbackButton setTitle:@""];
    }

    NSString *feedbackText = @"Copied!";
    NSFont *font = [NSFont boldSystemFontOfSize:11.0];
    if (font == nil) {
        font = [NSFont systemFontOfSize:11.0];
    }
    NSSize bubbleSize = [OMDCopyFeedbackBadgeView sizeForText:feedbackText font:font];
    CGFloat bubbleWidth = bubbleSize.width;
    CGFloat bubbleHeight = bubbleSize.height;
    NSRect buttonFrame = [_copyFeedbackButton frame];
    CGFloat x = NSMinX(buttonFrame) - bubbleWidth - 8.0;
    if (x < 4.0) {
        x = NSMaxX(buttonFrame) + 8.0;
    }
    CGFloat y = 0.0;
    if ([_textView isFlipped]) {
        y = NSMinY(buttonFrame);
        if (y + bubbleHeight > NSHeight([_textView bounds]) - 4.0) {
            y = NSHeight([_textView bounds]) - bubbleHeight - 4.0;
        }
    } else {
        y = NSMaxY(buttonFrame) - bubbleHeight;
        if (y < 4.0) {
            y = 4.0;
        }
    }
    if (x + bubbleWidth > NSWidth([_textView bounds]) - 4.0) {
        x = NSWidth([_textView bounds]) - bubbleWidth - 4.0;
    }

    NSRect hudFrame = NSIntegralRect(NSMakeRect(x, y, bubbleWidth, bubbleHeight));
    OMDCopyFeedbackBadgeView *hud = [[OMDCopyFeedbackBadgeView alloc] initWithFrame:hudFrame
                                                                                text:feedbackText
                                                                                font:font];
    [_textView addSubview:hud];
    _copyFeedbackHUDView = hud;

    _copyFeedbackTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDCopyFeedbackDisplayInterval
                                                           target:self
                                                         selector:@selector(copyFeedbackTimerFired:)
                                                         userInfo:nil
                                                          repeats:NO] retain];
}

- (void)copyFeedbackTimerFired:(NSTimer *)timer
{
    if (timer != _copyFeedbackTimer) {
        return;
    }
    [self hideCopyFeedback];
}

- (void)hideCopyFeedback
{
    if (_copyFeedbackTimer != nil) {
        [_copyFeedbackTimer invalidate];
        [_copyFeedbackTimer release];
        _copyFeedbackTimer = nil;
    }
    if (_copyFeedbackHUDView != nil) {
        [_copyFeedbackHUDView removeFromSuperview];
        [_copyFeedbackHUDView release];
        _copyFeedbackHUDView = nil;
    }
    if (_copyFeedbackButton != nil) {
        [self applyCopyButtonDefaultAppearance:_copyFeedbackButton];
        [_copyFeedbackButton release];
        _copyFeedbackButton = nil;
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

    if ([sender isKindOfClass:[NSButton class]]) {
        [self showCopyFeedbackForButton:(NSButton *)sender];
    }
}

- (void)replaceSourceTextInRange:(NSRange)range withString:(NSString *)replacement selectedRange:(NSRange)selection
{
    if (_sourceTextView == nil) {
        return;
    }

    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }
    if (range.location > [source length]) {
        return;
    }
    if (range.length > [source length] - range.location) {
        return;
    }

    if (replacement == nil) {
        replacement = @"";
    }

    [_window makeFirstResponder:_sourceTextView];
    if (![_sourceTextView shouldChangeTextInRange:range replacementString:replacement]) {
        return;
    }

    NSUndoManager *undoManager = [_sourceTextView undoManager];
    BOOL didBeginUndoGroup = NO;
    if (undoManager != nil) {
        [undoManager beginUndoGrouping];
        didBeginUndoGroup = YES;
    }

    NSTextStorage *storage = [_sourceTextView textStorage];
    [storage beginEditing];
    [storage replaceCharactersInRange:range withString:replacement];
    [storage endEditing];
    [_sourceTextView didChangeText];

    NSUInteger newLength = [source length] - range.length + [replacement length];
    if (selection.location > newLength) {
        selection.location = newLength;
        selection.length = 0;
    }
    if (selection.length > newLength - selection.location) {
        selection.length = newLength - selection.location;
    }
    _isProgrammaticSelectionSync = YES;
    [_sourceTextView setSelectedRange:selection];
    [_sourceTextView scrollRangeToVisible:selection];
    _isProgrammaticSelectionSync = NO;

    if (didBeginUndoGroup) {
        [undoManager endUndoGrouping];
    }

    [self updateFormattingBarContextState];
}

- (void)applyInlineWrapWithPrefix:(NSString *)prefix
                           suffix:(NSString *)suffix
                      placeholder:(NSString *)placeholder
{
    if (_sourceTextView == nil) {
        return;
    }

    NSString *source = [_sourceTextView string];
    NSRange selection = [_sourceTextView selectedRange];
    NSRange replaceRange = NSMakeRange(0, 0);
    NSRange nextSelection = NSMakeRange(0, 0);
    NSString *replacement = nil;
    BOOL hasEdit = OMDComputeInlineToggleEdit(source,
                                              selection,
                                              prefix,
                                              suffix,
                                              placeholder,
                                              &replaceRange,
                                              &replacement,
                                              &nextSelection);
    if (!hasEdit || replacement == nil) {
        return;
    }

    [self replaceSourceTextInRange:replaceRange withString:replacement selectedRange:nextSelection];
}

- (void)applyLinkTemplateCommand
{
    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }

    NSRange selection = [_sourceTextView selectedRange];
    if (selection.location > [source length]) {
        selection.location = [source length];
        selection.length = 0;
    }
    if (selection.length > [source length] - selection.location) {
        selection.length = [source length] - selection.location;
    }

    NSString *label = selection.length > 0 ? [source substringWithRange:selection] : @"link text";
    NSString *url = @"https://example.com";
    NSString *replacement = [NSString stringWithFormat:@"[%@](%@)", label, url];
    NSUInteger urlLocation = selection.location + [label length] + 3;
    NSRange nextSelection = NSMakeRange(urlLocation, [url length]);
    [self replaceSourceTextInRange:selection withString:replacement selectedRange:nextSelection];
}

- (void)applyImageTemplateCommand
{
    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }

    NSRange selection = [_sourceTextView selectedRange];
    if (selection.location > [source length]) {
        selection.location = [source length];
        selection.length = 0;
    }
    if (selection.length > [source length] - selection.location) {
        selection.length = [source length] - selection.location;
    }

    NSString *altText = selection.length > 0 ? [source substringWithRange:selection] : @"alt text";
    NSString *url = @"https://example.com/image.png";
    NSString *replacement = [NSString stringWithFormat:@"![%@](%@)", altText, url];
    NSUInteger urlLocation = selection.location + [altText length] + 4;
    NSRange nextSelection = NSMakeRange(urlLocation, [url length]);
    [self replaceSourceTextInRange:selection withString:replacement selectedRange:nextSelection];
}

- (NSRange)sourceLineRangeForSelection:(NSRange)selection source:(NSString *)source
{
    if (source == nil) {
        source = @"";
    }
    if ([source length] == 0) {
        return NSMakeRange(0, 0);
    }

    if (selection.location > [source length]) {
        selection.location = [source length];
        selection.length = 0;
    }
    if (selection.length > [source length] - selection.location) {
        selection.length = [source length] - selection.location;
    }

    if (selection.length == 0 && selection.location == [source length] && selection.location > 0) {
        selection.location -= 1;
    }

    return [source lineRangeForRange:selection];
}

- (NSArray *)sourceLinesForRange:(NSRange)range source:(NSString *)source trailingNewline:(BOOL *)trailingNewline
{
    if (source == nil) {
        source = @"";
    }
    if (range.location > [source length]) {
        range.location = [source length];
        range.length = 0;
    }
    if (range.length > [source length] - range.location) {
        range.length = [source length] - range.location;
    }

    NSString *chunk = [source substringWithRange:range];
    BOOL hasTrailingNewline = [chunk hasSuffix:@"\n"];
    NSArray *parts = [chunk componentsSeparatedByString:@"\n"];
    if (hasTrailingNewline && [parts count] > 0) {
        parts = [parts subarrayWithRange:NSMakeRange(0, [parts count] - 1)];
    }

    if (trailingNewline != NULL) {
        *trailingNewline = hasTrailingNewline;
    }

    return parts;
}

- (void)applyLineTransformWithTag:(OMDFormattingCommandTag)tag
{
    if (_sourceTextView == nil) {
        return;
    }

    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }

    NSRange selection = [_sourceTextView selectedRange];
    NSRange lineRange = [self sourceLineRangeForSelection:selection source:source];
    BOOL trailingNewline = NO;
    NSArray *lines = [self sourceLinesForRange:lineRange source:source trailingNewline:&trailingNewline];
    NSMutableArray *updated = [NSMutableArray arrayWithCapacity:[lines count]];

    NSInteger numberedIndex = 1;

    for (NSString *line in lines) {
        NSString *work = line != nil ? line : @"";
        NSUInteger indentLength = 0;
        while (indentLength < [work length]) {
            unichar ch = [work characterAtIndex:indentLength];
            if (ch == ' ' || ch == '\t') {
                indentLength++;
            } else {
                break;
            }
        }

        NSString *indent = [work substringToIndex:indentLength];
        NSString *body = [work substringFromIndex:indentLength];
        NSString *result = work;

        if (tag == OMDFormattingCommandTagListBullet) {
            if ([body hasPrefix:@"- "]) {
                body = [body substringFromIndex:2];
            } else if ([body hasPrefix:@"* "]) {
                body = [body substringFromIndex:2];
            } else if ([body hasPrefix:@"+ "]) {
                body = [body substringFromIndex:2];
            } else {
                body = [@"- " stringByAppendingString:body];
            }
            result = [indent stringByAppendingString:body];
        } else if (tag == OMDFormattingCommandTagListNumber) {
            NSUInteger cursor = 0;
            while (cursor < [body length]) {
                unichar ch = [body characterAtIndex:cursor];
                if (ch >= '0' && ch <= '9') {
                    cursor++;
                } else {
                    break;
                }
            }
            BOOL wasNumbered = (cursor > 0 &&
                                cursor + 1 < [body length] &&
                                [body characterAtIndex:cursor] == '.' &&
                                [body characterAtIndex:cursor + 1] == ' ');
            if (wasNumbered) {
                body = [body substringFromIndex:(cursor + 2)];
            } else {
                NSString *prefix = [NSString stringWithFormat:@"%ld. ", (long)numberedIndex];
                body = [prefix stringByAppendingString:body];
                numberedIndex += 1;
            }
            result = [indent stringByAppendingString:body];
        } else if (tag == OMDFormattingCommandTagListTask) {
            if ([body hasPrefix:@"- [ ] "]) {
                body = [body substringFromIndex:6];
            } else if ([body hasPrefix:@"- [x] "] || [body hasPrefix:@"- [X] "]) {
                body = [body substringFromIndex:6];
            } else if ([body hasPrefix:@"- "] || [body hasPrefix:@"* "] || [body hasPrefix:@"+ "]) {
                body = [@"- [ ] " stringByAppendingString:[body substringFromIndex:2]];
            } else {
                body = [@"- [ ] " stringByAppendingString:body];
            }
            result = [indent stringByAppendingString:body];
        } else if (tag == OMDFormattingCommandTagBlockQuote) {
            if ([body hasPrefix:@"> "]) {
                body = [body substringFromIndex:2];
            } else if ([body hasPrefix:@">"]) {
                body = [body substringFromIndex:1];
            } else {
                body = [@"> " stringByAppendingString:body];
            }
            result = [indent stringByAppendingString:body];
        }

        [updated addObject:result];
    }

    NSString *replacement = [updated componentsJoinedByString:@"\n"];
    if (trailingNewline) {
        replacement = [replacement stringByAppendingString:@"\n"];
    }
    NSRange nextSelection = NSMakeRange(lineRange.location, [replacement length]);
    [self replaceSourceTextInRange:lineRange withString:replacement selectedRange:nextSelection];
}

- (void)applyCodeFenceCommand
{
    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }

    NSRange selection = [_sourceTextView selectedRange];
    if (selection.location > [source length]) {
        selection.location = [source length];
        selection.length = 0;
    }
    if (selection.length > [source length] - selection.location) {
        selection.length = [source length] - selection.location;
    }

    NSString *content = selection.length > 0 ? [source substringWithRange:selection] : @"code";
    NSString *replacement = [NSString stringWithFormat:@"```\n%@\n```", content];
    NSRange nextSelection = NSMakeRange(selection.location + 4, [content length]);
    [self replaceSourceTextInRange:selection withString:replacement selectedRange:nextSelection];
}

- (void)applyTableCommand
{
    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }

    NSRange selection = [_sourceTextView selectedRange];
    if (selection.location > [source length]) {
        selection.location = [source length];
        selection.length = 0;
    }
    if (selection.length > [source length] - selection.location) {
        selection.length = [source length] - selection.location;
    }

    NSString *replacement = @"| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |";
    NSRange nextSelection = NSMakeRange(selection.location + 2, [@"Column 1" length]);
    [self replaceSourceTextInRange:selection withString:replacement selectedRange:nextSelection];
}

- (void)applyHorizontalRuleCommand
{
    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }

    NSRange selection = [_sourceTextView selectedRange];
    if (selection.location > [source length]) {
        selection.location = [source length];
        selection.length = 0;
    }
    if (selection.length > [source length] - selection.location) {
        selection.length = [source length] - selection.location;
    }

    NSString *replacement = @"\n---\n";
    NSRange nextSelection = NSMakeRange(selection.location + [replacement length], 0);
    [self replaceSourceTextInRange:selection withString:replacement selectedRange:nextSelection];
}

- (void)applyHeadingLevel:(NSInteger)level
{
    if (_sourceTextView == nil) {
        return;
    }

    if (level < 0) {
        level = 0;
    }
    if (level > 6) {
        level = 6;
    }

    NSString *source = [_sourceTextView string];
    if (source == nil) {
        source = @"";
    }

    NSRange selection = [_sourceTextView selectedRange];
    NSRange lineRange = [self sourceLineRangeForSelection:selection source:source];
    BOOL trailingNewline = NO;
    NSArray *lines = [self sourceLinesForRange:lineRange source:source trailingNewline:&trailingNewline];
    NSMutableArray *updated = [NSMutableArray arrayWithCapacity:[lines count]];

    for (NSString *line in lines) {
        NSString *work = line != nil ? line : @"";
        NSUInteger indentLength = 0;
        while (indentLength < [work length]) {
            unichar ch = [work characterAtIndex:indentLength];
            if (ch == ' ' || ch == '\t') {
                indentLength++;
            } else {
                break;
            }
        }
        NSString *indent = [work substringToIndex:indentLength];
        NSString *withoutPrefix = [self lineByRemovingMarkdownPrefix:work];
        if ([withoutPrefix length] >= indentLength) {
            withoutPrefix = [withoutPrefix substringFromIndex:indentLength];
        } else {
            withoutPrefix = @"";
        }

        if (level == 0) {
            [updated addObject:[indent stringByAppendingString:withoutPrefix]];
        } else {
            NSString *content = OMDTrimmedString(withoutPrefix);
            if ([content length] == 0) {
                content = @"Heading";
            }
            NSString *prefix = [@"" stringByPaddingToLength:(NSUInteger)level withString:@"#" startingAtIndex:0];
            NSString *result = [NSString stringWithFormat:@"%@%@ %@", indent, prefix, content];
            [updated addObject:result];
        }
    }

    NSString *replacement = [updated componentsJoinedByString:@"\n"];
    if (trailingNewline) {
        replacement = [replacement stringByAppendingString:@"\n"];
    }
    NSRange nextSelection = NSMakeRange(lineRange.location, [replacement length]);
    [self replaceSourceTextInRange:lineRange withString:replacement selectedRange:nextSelection];
}

- (void)formattingHeadingControlChanged:(id)sender
{
    if (sender != _formatHeadingControl) {
        return;
    }
    if (![self isFormattingBarVisibleInCurrentMode]) {
        return;
    }
    if (_currentDocumentReadOnly) {
        return;
    }
    NSInteger index = [_formatHeadingControl selectedSegment];
    if (index < 0) {
        return;
    }
    [self applyHeadingLevel:index];
}

- (void)performFormattingCommandWithTag:(NSInteger)tag
{
    switch (tag) {
        case OMDFormattingCommandTagBold:
            [self applyInlineWrapWithPrefix:@"**" suffix:@"**" placeholder:@"bold text"];
            break;
        case OMDFormattingCommandTagItalic:
            [self applyInlineWrapWithPrefix:@"*" suffix:@"*" placeholder:@"italic text"];
            break;
        case OMDFormattingCommandTagStrike:
            [self applyInlineWrapWithPrefix:@"~~" suffix:@"~~" placeholder:@"strikethrough"];
            break;
        case OMDFormattingCommandTagInlineCode:
            [self applyInlineWrapWithPrefix:@"`" suffix:@"`" placeholder:@"code"];
            break;
        case OMDFormattingCommandTagLink:
            [self applyLinkTemplateCommand];
            break;
        case OMDFormattingCommandTagImage:
            [self applyImageTemplateCommand];
            break;
        case OMDFormattingCommandTagListBullet:
        case OMDFormattingCommandTagListNumber:
        case OMDFormattingCommandTagListTask:
        case OMDFormattingCommandTagBlockQuote:
            [self applyLineTransformWithTag:(OMDFormattingCommandTag)tag];
            break;
        case OMDFormattingCommandTagCodeFence:
            [self applyCodeFenceCommand];
            break;
        case OMDFormattingCommandTagTable:
            [self applyTableCommand];
            break;
        case OMDFormattingCommandTagHorizontalRule:
            [self applyHorizontalRuleCommand];
            break;
        default:
            break;
    }
}

- (void)formattingCommandGroupChanged:(id)sender
{
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    if (_sourceTextView == nil || ![self isFormattingBarVisibleInCurrentMode]) {
        OMDClearSegmentedControlSelection(control);
        return;
    }
    if (_currentDocumentReadOnly) {
        OMDClearSegmentedControlSelection(control);
        return;
    }

    NSInteger segment = [control selectedSegment];
    if (segment < 0) {
        return;
    }
    NSInteger tag = 0;
    switch ([control tag]) {
        case 1:
            if (segment == 0) {
                tag = OMDFormattingCommandTagBold;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagItalic;
            } else if (segment == 2) {
                tag = OMDFormattingCommandTagStrike;
            } else if (segment == 3) {
                tag = OMDFormattingCommandTagInlineCode;
            }
            break;
        case 2:
            if (segment == 0) {
                tag = OMDFormattingCommandTagLink;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagImage;
            }
            break;
        case 3:
            if (segment == 0) {
                tag = OMDFormattingCommandTagListBullet;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagListNumber;
            } else if (segment == 2) {
                tag = OMDFormattingCommandTagListTask;
            } else if (segment == 3) {
                tag = OMDFormattingCommandTagBlockQuote;
            }
            break;
        case 4:
            if (segment == 0) {
                tag = OMDFormattingCommandTagCodeFence;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagTable;
            } else if (segment == 2) {
                tag = OMDFormattingCommandTagHorizontalRule;
            }
            break;
        default:
            break;
    }
    OMDClearSegmentedControlSelection(control);
    if (tag == 0) {
        return;
    }
    [self performFormattingCommandWithTag:tag];
}

- (void)formattingCommandPressed:(id)sender
{
    NSInteger tag = [sender tag];
    if (_sourceTextView == nil || ![self isFormattingBarVisibleInCurrentMode]) {
        return;
    }
    if (_currentDocumentReadOnly) {
        return;
    }
    [self performFormattingCommandWithTag:tag];
}

- (void)toggleBoldFormatting:(id)sender
{
    (void)sender;
    if (_sourceTextView == nil) {
        return;
    }
    if (_viewerMode == OMDViewerModeRead) {
        return;
    }
    if (_currentDocumentReadOnly) {
        return;
    }
    [self applyInlineWrapWithPrefix:@"**" suffix:@"**" placeholder:@"bold text"];
}

- (void)toggleItalicFormatting:(id)sender
{
    (void)sender;
    if (_sourceTextView == nil) {
        return;
    }
    if (_viewerMode == OMDViewerModeRead) {
        return;
    }
    if (_currentDocumentReadOnly) {
        return;
    }
    [self applyInlineWrapWithPrefix:@"*" suffix:@"*" placeholder:@"italic text"];
}

- (NSTextView *)activeEditingTextView
{
    if (_currentDocumentReadOnly) {
        return nil;
    }

    if (_window != nil) {
        id responder = [_window firstResponder];
        if ([responder isKindOfClass:[NSTextView class]]) {
            return (NSTextView *)responder;
        }
    }

    if (_viewerMode == OMDViewerModeEdit || _viewerMode == OMDViewerModeSplit) {
        return _sourceTextView;
    }
    return nil;
}

- (void)undo:(id)sender
{
    (void)sender;
    NSTextView *textView = [self activeEditingTextView];
    if (textView == nil) {
        return;
    }
    NSUndoManager *undoManager = [textView undoManager];
    if (undoManager != nil && [undoManager canUndo]) {
        [undoManager undo];
    }
}

- (void)redo:(id)sender
{
    (void)sender;
    NSTextView *textView = [self activeEditingTextView];
    if (textView == nil) {
        return;
    }
    NSUndoManager *undoManager = [textView undoManager];
    if (undoManager != nil && [undoManager canRedo]) {
        [undoManager redo];
    }
}

- (NSString *)lineByRemovingMarkdownPrefix:(NSString *)line
{
    if (line == nil || [line length] == 0) {
        return @"";
    }

    NSUInteger indentLength = 0;
    while (indentLength < [line length]) {
        unichar ch = [line characterAtIndex:indentLength];
        if (ch == ' ' || ch == '\t') {
            indentLength++;
        } else {
            break;
        }
    }

    NSString *indent = [line substringToIndex:indentLength];
    NSString *body = [line substringFromIndex:indentLength];
    NSUInteger hashCount = 0;
    while (hashCount < [body length] && hashCount < 6) {
        unichar ch = [body characterAtIndex:hashCount];
        if (ch == '#') {
            hashCount++;
        } else {
            break;
        }
    }

    if (hashCount > 0 &&
        hashCount < [body length] &&
        [body characterAtIndex:hashCount] == ' ') {
        NSUInteger cursor = hashCount;
        while (cursor < [body length] && [body characterAtIndex:cursor] == ' ') {
            cursor++;
        }
        return [indent stringByAppendingString:[body substringFromIndex:cursor]];
    }
    return line;
}

- (NSInteger)headingLevelForLine:(NSString *)line
{
    if (line == nil || [line length] == 0) {
        return 0;
    }

    NSUInteger cursor = 0;
    while (cursor < [line length]) {
        unichar ch = [line characterAtIndex:cursor];
        if (ch == ' ' || ch == '\t') {
            cursor++;
        } else {
            break;
        }
    }

    NSUInteger hashCount = 0;
    while (cursor + hashCount < [line length] && hashCount < 6) {
        if ([line characterAtIndex:(cursor + hashCount)] == '#') {
            hashCount++;
        } else {
            break;
        }
    }

    if (hashCount > 0 &&
        cursor + hashCount < [line length] &&
        [line characterAtIndex:(cursor + hashCount)] == ' ') {
        return (NSInteger)hashCount;
    }
    return 0;
}

- (void)textDidChange:(NSNotification *)notification
{
    if (_isProgrammaticSourceUpdate || _isProgrammaticSourceHighlightUpdate) {
        return;
    }
    if ([notification object] != _sourceTextView) {
        return;
    }

    NSString *updatedMarkdown = [[_sourceTextView string] copy];
    [_currentMarkdown release];
    _currentMarkdown = updatedMarkdown;
    BOOL wasDirty = _sourceIsDirty;
    _sourceIsDirty = YES;
    _sourceRevision += 1;
    [self updateWindowTitle];
    [self captureCurrentStateIntoSelectedTab];
    if (!wasDirty) {
        [self updateTabStrip];
    }
    [self scheduleRecoveryAutosave];

    if (_viewerMode == OMDViewerModeSplit) {
        if (_sourceRevision == _lastRenderedSourceRevision) {
            [self syncPreviewToSourceInteractionAnchor];
        }
        [self scheduleLivePreviewRender];
    }
    [self requestSourceSyntaxHighlightingRefresh];
    [self updatePreviewStatusIndicator];
    [self updateFormattingBarContextState];
}

- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    if (_isProgrammaticSelectionSync) {
        return;
    }

    id object = [notification object];
    if (object == _sourceTextView) {
        if (_viewerMode == OMDViewerModeSplit && !_isProgrammaticSourceUpdate) {
            if ([self usesCaretSelectionSync] && _sourceRevision == _lastRenderedSourceRevision) {
                [self syncPreviewToSourceSelection];
            }
        }
        [self updateFormattingBarContextState];
        return;
    }

    if (object != _textView) {
        return;
    }
    if (_viewerMode != OMDViewerModeSplit || _isProgrammaticPreviewUpdate) {
        return;
    }
    if (_window != nil && [_window firstResponder] != _textView) {
        return;
    }
    if (![self usesCaretSelectionSync]) {
        return;
    }

    [self syncSourceSelectionToPreviewSelection];
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
        if (!OMDShouldOpenURLForUserNavigation(url)) {
            NSBeep();
            return NO;
        }
        BOOL opened = [[NSWorkspace sharedWorkspace] openURL:url];
        if (!opened) {
            opened = OMDOpenURLUsingXDGOpen(url);
        }
        if (!opened) {
            NSBeep();
        }
        return opened;
    }

    return NO;
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    return [self textView:textView clickedOnLink:link];
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
        NSString *expanded = [self resolvedAbsolutePathForLocalPath:candidate];
        if ([expanded length] == 0) {
            continue;
        }
        if ([fm fileExistsAtPath:expanded]) {
            BOOL opened = [self openDocumentAtPath:expanded];
            _openedFileOnLaunch = YES;
            if (opened) {
                return YES;
            }
        }
    }

    return NO;
}

- (BOOL)isImportableDocumentPath:(NSString *)path
{
    if (path == nil || [path length] == 0) {
        return NO;
    }
    NSString *extension = [[path pathExtension] lowercaseString];
    return [OMDDocumentConverter isSupportedExtension:extension];
}

- (BOOL)openDocumentAtPath:(NSString *)path
{
    return [self openDocumentAtPath:path inNewTab:NO requireDirtyConfirm:YES];
}

- (BOOL)openDocumentAtPath:(NSString *)path
                  inNewTab:(BOOL)inNewTab
       requireDirtyConfirm:(BOOL)requireDirtyConfirm
{
    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:path];
    if ([resolvedPath length] == 0) {
        return NO;
    }

    NSString *markdown = nil;
    NSString *displayTitle = nil;
    NSString *syntaxLanguage = nil;
    OMDDocumentRenderMode renderMode = OMDDocumentRenderModeMarkdown;
    if (![self loadDocumentContentsAtPath:resolvedPath
                               actionName:@"Open"
                                 markdown:&markdown
                             displayTitle:&displayTitle
                               renderMode:&renderMode
                           syntaxLanguage:&syntaxLanguage
                              fingerprint:NULL]) {
        return NO;
    }

    BOOL opened = [self openDocumentWithMarkdown:markdown
                                       sourcePath:resolvedPath
                                     displayTitle:displayTitle
                                         readOnly:NO
                                       renderMode:renderMode
                                   syntaxLanguage:syntaxLanguage
                                         inNewTab:inNewTab
                              requireDirtyConfirm:requireDirtyConfirm];
    if (opened) {
        [self noteRecentDocumentAtPathIfAvailable:resolvedPath];
    }
    return opened;
}

- (BOOL)openDocumentAtPathInNewWindow:(NSString *)path
{
    if (path == nil || [path length] == 0) {
        return NO;
    }

    OMDAppDelegate *controller = [[OMDAppDelegate alloc] init];
    [controller setupWindow];
    BOOL opened = [controller openDocumentAtPath:path];
    if (opened) {
        [controller schedulePostPresentationSetupIfNeeded];
        [controller registerAsSecondaryWindow];
    } else {
        [controller->_window close];
    }
    [controller release];
    return opened;
}

- (BOOL)windowShouldClose:(id)sender
{
    if (_sourceVimForceClose) {
        _sourceVimForceClose = NO;
        return YES;
    }

    [self captureCurrentStateIntoSelectedTab];
    NSInteger dirtyCount = 0;
    NSInteger index = 0;
    for (; index < (NSInteger)[_documentTabs count]; index++) {
        NSDictionary *tab = [_documentTabs objectAtIndex:index];
        if ([[tab objectForKey:OMDTabDirtyKey] boolValue]) {
            dirtyCount += 1;
        }
    }

    if (dirtyCount == 0) {
        return YES;
    }
    if (dirtyCount == 1 && _sourceIsDirty) {
        return [self confirmDiscardingUnsavedChangesForAction:@"closing"];
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Close with unsaved tabs?"];
    [alert setInformativeText:[NSString stringWithFormat:@"There are %ld tabs with unsaved changes. Save the tabs you want to keep before closing.",
                                                         (long)dirtyCount]];
    [alert addButtonWithTitle:@"Discard and Close"];
    [alert addButtonWithTitle:@"Cancel"];
    NSInteger buttonIndex = OMDAlertButtonIndexForResponse([alert runModal]);
    return (buttonIndex == 0);
}

- (void)windowWillClose:(NSNotification *)notification
{
    (void)notification;
    [self stopExternalFileMonitor];
    [self cancelPendingInteractiveRender];
    [self cancelPendingMathArtifactRender];
    [self cancelPendingLivePreviewRender];
    [self cancelPendingPreviewStatusUpdatingVisibility];
    [self cancelPendingPreviewStatusAutoHide];
    [self cancelPendingRecoveryAutosave];
    [self clearRecoverySnapshot];
    [self setPreviewUpdating:NO];
    _externalReloadPromptVisible = NO;
    [self unregisterAsSecondaryWindow];
}

@end
