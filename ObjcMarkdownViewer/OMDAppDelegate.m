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
#import "GSVVimBindingController.h"
#import "GSVVimConfigLoader.h"
#import "GSOpenSave.h"
#import <AppKit/NSInterfaceStyle.h>
#import <GNUstepGUI/GSTheme.h>

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
static const NSTimeInterval OMDSourceSyntaxHighlightDebounceInterval = 0.08;
static const NSTimeInterval OMDSourceSyntaxHighlightLargeDocDebounceInterval = 0.16;
static const NSTimeInterval OMDRecoveryAutosaveDebounceInterval = 1.25;
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
static const CGFloat OMDToolbarControlHeight = 22.0;
static const CGFloat OMDToolbarLabelHeight = 20.0;
static const CGFloat OMDToolbarItemHeight = 26.0;
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
static NSString * const OMDExplorerLocalRootPathDefaultsKey = @"ObjcMarkdownExplorerLocalRootPath";
static NSString * const OMDExplorerMaxFileSizeMBDefaultsKey = @"ObjcMarkdownExplorerMaxFileSizeMB";
static NSString * const OMDExplorerListFontSizeDefaultsKey = @"ObjcMarkdownExplorerListFontSize";
static NSString * const OMDExplorerIncludeForkArchivedDefaultsKey = @"ObjcMarkdownExplorerIncludeForkArchived";
static NSString * const OMDExplorerShowHiddenFilesDefaultsKey = @"ObjcMarkdownExplorerShowHiddenFiles";
static NSString * const OMDExplorerSidebarVisibleDefaultsKey = @"ObjcMarkdownExplorerSidebarVisible";
static NSString * const OMDExplorerGitHubTokenDefaultsKey = @"ObjcMarkdownGitHubToken";
static NSString * const OMDGitHubCacheErrorDomain = @"OMDGitHubCacheErrorDomain";

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

typedef NS_ENUM(NSInteger, OMDSplitSyncMode) {
    OMDSplitSyncModeUnlinked = 0,
    OMDSplitSyncModeLinkedScrolling = 1,
    OMDSplitSyncModeCaretSelectionFollow = 2
};

typedef NS_ENUM(NSInteger, OMDExplorerSourceMode) {
    OMDExplorerSourceModeLocal = 0,
    OMDExplorerSourceModeGitHub = 1
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
    NSString *themeName = [[NSUserDefaults standardUserDefaults] stringForKey:@"GSTheme"];
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

static NSImage *OMDToolbarImageNamed(NSString *resourceName)
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

static NSImage *OMDToolbarThemedImageNamed(NSString *resourceName)
{
    NSImage *image = OMDToolbarImageNamed(resourceName);
    if (image == nil) {
        return nil;
    }

    NSColor *tint = OMDResolvedControlTextColor();
    if (tint == nil) {
        return image;
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
    [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    [tint set];
    NSRectFillUsingOperation(rect, NSCompositeSourceAtop);
    [tinted unlockFocus];
    [tinted setSize:size];
    return tinted;
}

static NSImage *OMDCodeBlockCopyImage(void)
{
    static NSImage *cached = nil;
    if (cached != nil) {
        return cached;
    }

    NSImage *image = OMDToolbarImageNamed(@"code-copy-icon.png");
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

static NSButton *OMDFormattingButton(NSString *title,
                                     NSString *toolTip,
                                     NSInteger tag,
                                     CGFloat x,
                                     CGFloat y,
                                     CGFloat width,
                                     CGFloat height,
                                     id target)
{
    NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(x, y, width, height)] autorelease];
    [button setTitle:(title != nil ? title : @"")];
    [button setToolTip:toolTip];
    [button setTag:tag];
    [button setTarget:target];
    [button setAction:@selector(formattingCommandPressed:)];
    [button setBezelStyle:NSSmallSquareBezelStyle];
    [button setButtonType:NSMomentaryPushInButton];
    [button setFont:[NSFont systemFontOfSize:11.0]];
    [button setImagePosition:NSNoImage];
    [button setAutoresizingMask:NSViewMinYMargin];
    return button;
}

static NSString *OMDTrimmedString(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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

@interface OMDAppDelegate () <GSVVimBindingControllerDelegate>
- (void)importDocument:(id)sender;
- (void)saveDocument:(id)sender;
- (void)saveDocumentAsMarkdown:(id)sender;
- (void)printDocument:(id)sender;
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
- (void)setCurrentMarkdown:(NSString *)markdown sourcePath:(NSString *)sourcePath;
- (void)setCurrentDocumentText:(NSString *)text
                    sourcePath:(NSString *)sourcePath
                    renderMode:(OMDDocumentRenderMode)renderMode
                syntaxLanguage:(NSString *)syntaxLanguage;
- (NSString *)markdownForCurrentPreview;
- (NSString *)decodedTextForFileAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)openDocumentAtPath:(NSString *)path;
- (BOOL)openDocumentAtPathInNewWindow:(NSString *)path;
- (void)setupWorkspaceChrome;
- (void)layoutWorkspaceChrome;
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
                                     syntaxLanguage:(NSString *)syntaxLanguage;
- (void)applyDocumentTabRecord:(NSDictionary *)tabRecord;
- (BOOL)openDocumentWithMarkdown:(NSString *)markdown
                      sourcePath:(NSString *)sourcePath
                    displayTitle:(NSString *)displayTitle
                        readOnly:(BOOL)readOnly
                      renderMode:(OMDDocumentRenderMode)renderMode
                  syntaxLanguage:(NSString *)syntaxLanguage
                        inNewTab:(BOOL)inNewTab
             requireDirtyConfirm:(BOOL)requireDirtyConfirm;
- (void)applyCurrentDocumentReadOnlyState;
- (void)preferencesExplorerLocalRootChanged:(id)sender;
- (void)preferencesExplorerMaxFileSizeChanged:(id)sender;
- (void)preferencesExplorerListFontSizeChanged:(id)sender;
- (void)preferencesExplorerGitHubTokenChanged:(id)sender;
- (BOOL)saveCurrentMarkdownToPath:(NSString *)path;
- (BOOL)saveDocumentAsMarkdownWithPanel;
- (BOOL)saveDocumentFromVimCommand;
- (void)performCloseFromVimCommandForcingDiscard:(BOOL)force;
- (BOOL)confirmDiscardingUnsavedChangesForAction:(NSString *)actionName;
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
- (void)requestInteractiveRenderForLayoutWidthIfNeeded;
- (void)updateAdaptiveZoomDebounceWithRenderDurationMs:(NSTimeInterval)durationMs
                                     sampledAsZoomRender:(BOOL)isZoomRender;
- (CGFloat)currentPreviewLayoutWidth;
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
- (void)layoutSourceEditorContainer;
- (void)normalizeWindowFrameIfNeeded;
- (void)updateFormattingBarContextState;
- (void)formattingHeadingChanged:(id)sender;
- (void)formattingCommandPressed:(id)sender;
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
- (NSUInteger)topVisibleCharacterIndexForTextView:(NSTextView *)textView
                                      inScrollView:(NSScrollView *)scrollView;
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
- (void)showPreferences:(id)sender;
- (void)syncPreferencesPanelFromSettings;
- (void)preferencesMathPolicyChanged:(id)sender;
- (void)preferencesSplitSyncModeChanged:(id)sender;
- (void)preferencesAllowRemoteImagesChanged:(id)sender;
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
- (void)requestSourceSyntaxHighlightingRefresh;
- (void)scheduleSourceSyntaxHighlightingAfterDelay:(NSTimeInterval)delay;
- (void)sourceSyntaxHighlightTimerFired:(NSTimer *)timer;
- (void)cancelPendingSourceSyntaxHighlighting;
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
    [self hideCopyFeedback];
    [_sourceVimCommandLine release];
    [_currentDocumentSyntaxLanguage release];
    [_currentDisplayTitle release];
    [_currentMarkdown release];
    [_currentPath release];
    [_documentTabs release];
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
    [_zoomSlider release];
    [_zoomLabel release];
    [_zoomResetButton release];
    [_zoomContainer release];
    [_modeLabel release];
    [_previewStatusLabel release];
    [_modeControl release];
    [_modeContainer release];
    [_preferencesMathPolicyPopup release];
    [_preferencesSplitSyncModePopup release];
    [_preferencesAllowRemoteImagesButton release];
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
    [_formatHeadingPopup release];
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
    [_documentContainer release];
    [_textView release];
    [_window release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
#if defined(_WIN32)
    // Ensure OpenSave is initialized and prefers native Win32 dialogs.
    GSOpenSaveSetMode(GSOpenSaveModeWin32);
#else
    GSOpenSaveSetMode(GSOpenSaveModeAuto);
#endif

    [self setupWindow];
    BOOL openedFromArgs = [self openDocumentFromArguments];
    if (!_openedFileOnLaunch && !openedFromArgs) {
        [self restoreRecoveryIfAvailable];
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
    (void)theApplication;
    _openedFileOnLaunch = YES;
    if ([_documentTabs count] == 0 && _currentPath == nil && _currentMarkdown == nil) {
        return [self openDocumentAtPath:filename];
    }
    return [self openDocumentAtPathInNewWindow:filename];
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

    NSMenuItem *saveItem = (NSMenuItem *)[fileMenu addItemWithTitle:@"Save"
                                                              action:@selector(saveDocument:)
                                                       keyEquivalent:@"s"];
    [saveItem setTarget:self];

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

    [NSApp setMainMenu:menubar];
}

- (void)setupWindow
{
    NSRect frame = NSMakeRect(100, 100, 900, 700);
    _window = [[OMDMainWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [_window setFrameAutosaveName:@"ObjcMarkdownViewerMainWindow"];
    [self normalizeWindowFrameIfNeeded];
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
    [self setupWorkspaceChrome];

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
    [_previewScrollView setHasHorizontalScroller:YES];
    [_previewScrollView setAutohidesScrollers:YES];
    [_previewScrollView setDrawsBackground:YES];
    [_previewScrollView setBackgroundColor:[NSColor whiteColor]];

    _textView = [[OMDTextView alloc] initWithFrame:[[_previewScrollView contentView] bounds]];
    [_textView setAutoresizingMask:NSViewHeightSizable];
    [_textView setMinSize:NSMakeSize(0.0, 0.0)];
    [_textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [_textView setHorizontallyResizable:YES];
    [_textView setVerticallyResizable:YES];
    [_textView setEditable:NO];
    [_textView setSelectable:YES];
    [_textView setRichText:YES];
    [_textView setDrawsBackground:NO];
    [_textView setTextContainerInset:NSMakeSize(20.0, 16.0)];
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

    [_previewScrollView setDocumentView:_textView];
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
    [_sourceTextView setTextContainerInset:NSMakeSize(20.0, 16.0)];
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
    _sourceLineNumberRuler = [[OMDLineNumberRulerView alloc] initWithScrollView:_sourceScrollView
                                                                        textView:_sourceTextView];
    [_sourceScrollView setVerticalRulerView:_sourceLineNumberRuler];
    [_sourceEditorContainer addSubview:_sourceScrollView];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id showFormattingBarValue = [defaults objectForKey:OMDShowFormattingBarDefaultsKey];
    _showFormattingBar = YES;
    if ([showFormattingBarValue respondsToSelector:@selector(boolValue)]) {
        _showFormattingBar = [showFormattingBarValue boolValue];
    }
    [self setupFormattingBar];
    [self layoutSourceEditorContainer];

    [_splitView addSubview:_sourceEditorContainer];
    [_splitView addSubview:_previewScrollView];

    [_documentContainer addSubview:_previewScrollView];

    [_window makeKeyAndOrderFront:nil];
    [self normalizeWindowFrameIfNeeded];
    [_window makeKeyAndOrderFront:nil];

    _renderer = [[OMMarkdownRenderer alloc] init];
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
    [self updateTabStrip];
    [self reloadExplorerEntries];
}

- (void)setupWorkspaceChrome
{
    NSRect contentBounds = [[_window contentView] bounds];

    _workspaceSplitView = [[NSSplitView alloc] initWithFrame:contentBounds];
    [_workspaceSplitView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_workspaceSplitView setVertical:YES];
    [_workspaceSplitView setDelegate:self];

    _sidebarContainer = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                 0.0,
                                                                 OMDExplorerSidebarDefaultWidth,
                                                                 NSHeight(contentBounds))];
    [_sidebarContainer setAutoresizingMask:NSViewHeightSizable];

    _workspaceMainContainer = [[NSView alloc] initWithFrame:NSMakeRect(OMDExplorerSidebarDefaultWidth,
                                                                        0.0,
                                                                        NSWidth(contentBounds) - OMDExplorerSidebarDefaultWidth,
                                                                        NSHeight(contentBounds))];
    [_workspaceMainContainer setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    [_workspaceSplitView addSubview:_sidebarContainer];
    [_workspaceSplitView addSubview:_workspaceMainContainer];
    [[_window contentView] addSubview:_workspaceSplitView];

    _tabStripView = [[NSView alloc] initWithFrame:NSZeroRect];
    [_tabStripView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
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
    _explorerSidebarLastVisibleWidth = OMDExplorerSidebarDefaultWidth;

    [self setupExplorerSidebar];
    [self layoutWorkspaceChrome];
    [_workspaceSplitView adjustSubviews];

    CGFloat totalWidth = NSWidth([_workspaceSplitView bounds]);
    CGFloat divider = [_workspaceSplitView dividerThickness];
    CGFloat available = totalWidth - divider;
    CGFloat sidebarWidth = OMDExplorerSidebarDefaultWidth;
    if (available > 0.0) {
        CGFloat minMainWidth = 420.0;
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
}

- (void)layoutWorkspaceChrome
{
    if (_workspaceMainContainer == nil || _documentContainer == nil || _tabStripView == nil) {
        return;
    }

    NSRect bounds = [_workspaceMainContainer bounds];
    CGFloat tabHeight = OMDTabStripHeight;
    if (tabHeight > NSHeight(bounds)) {
        tabHeight = NSHeight(bounds);
    }

    NSRect tabFrame = NSMakeRect(NSMinX(bounds),
                                 NSMaxY(bounds) - tabHeight,
                                 NSWidth(bounds),
                                 tabHeight);
    [_tabStripView setFrame:NSIntegralRect(tabFrame)];

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
        CGFloat target = _explorerSidebarLastVisibleWidth;
        if (target < 170.0) {
            target = OMDExplorerSidebarDefaultWidth;
        }
        if (available > 0.0) {
            CGFloat minMain = 360.0;
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
        }
        if (target < 1.0) {
            target = OMDExplorerSidebarDefaultWidth;
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
    if (width < 720.0) {
        width = MIN(900.0, visible.size.width);
    }
    if (height < 520.0) {
        height = MIN(700.0, visible.size.height);
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
        if (image != nil) {
            [item setImage:image];
        }
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
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-import.png");
        if (image == nil) {
            image = [NSImage imageNamed:@"NSOpen"];
        }
        if (image != nil) {
            [item setImage:image];
        }
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
        if (image != nil) {
            [item setImage:image];
        }
        return item;
    }

    if ([identifier isEqualToString:@"Preferences"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Preferences"] autorelease];
        [item setLabel:@"Prefs"];
        [item setPaletteLabel:@"Preferences"];
        [item setToolTip:@"Open Preferences"];
        [item setTarget:self];
        [item setAction:@selector(showPreferences:)];
        NSImage *image = [NSImage imageNamed:@"NSPreferencesGeneral"];
        if (image == nil) {
            image = [NSImage imageNamed:@"preferences"];
        }
        if (image == nil) {
            image = [NSImage imageNamed:@"NSAdvanced"];
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
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-print.png");
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
        NSImage *image = OMDToolbarThemedImageNamed(@"toolbar-export.png");
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
            _zoomContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, OMDToolbarItemHeight)];

            _zoomLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, labelY, 55, OMDToolbarLabelHeight)];
            [_zoomLabel setBezeled:NO];
            [_zoomLabel setEditable:NO];
            [_zoomLabel setSelectable:NO];
            [_zoomLabel setDrawsBackground:NO];
            [_zoomLabel setAlignment:NSRightTextAlignment];
            [_zoomLabel setFont:[NSFont boldSystemFontOfSize:11.0]];

            _zoomSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(60, controlY, 160, OMDToolbarControlHeight)];
            [_zoomSlider setMinValue:50];
            [_zoomSlider setMaxValue:200];
            [_zoomSlider setDoubleValue:_zoomScale * 100.0];
            [_zoomSlider setTarget:self];
            [_zoomSlider setAction:@selector(zoomSliderChanged:)];

            _zoomResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(225, controlY, 55, OMDToolbarControlHeight)];
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
        [item setMinSize:NSMakeSize(280, OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(280, OMDToolbarItemHeight)];
        return item;
    }

    return nil;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:
        @"ToggleExplorer",
        @"OpenDocument",
        @"ImportDocument",
        @"SaveDocument",
        @"Preferences",
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
        @"ToggleExplorer",
        @"OpenDocument",
        @"ImportDocument",
        @"SaveDocument",
        @"Preferences",
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
        action == @selector(saveDocumentAsMarkdown:) ||
        action == @selector(printDocument:) ||
        action == @selector(exportDocumentAsPDF:) ||
        action == @selector(exportDocumentAsRTF:) ||
        action == @selector(exportDocumentAsDOCX:) ||
        action == @selector(exportDocumentAsODT:) ||
        action == @selector(exportDocumentAsHTML:)) {
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

    NSArray *filenames = [panel filenames];
    if ([filenames count] == 0) {
        return;
    }

    NSString *path = [filenames objectAtIndex:0];
    if ([_documentTabs count] == 0 && _currentPath == nil && _currentMarkdown == nil) {
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

    NSArray *filenames = [panel filenames];
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

    return [self openDocumentWithMarkdown:(importedMarkdown != nil ? importedMarkdown : @"")
                                sourcePath:path
                              displayTitle:[path lastPathComponent]
                                  readOnly:NO
                                renderMode:OMDDocumentRenderModeMarkdown
                            syntaxLanguage:nil
                                  inNewTab:NO
                       requireDirtyConfirm:YES];
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
        return NO;
    }

    [self setCurrentDocumentText:_currentMarkdown
                      sourcePath:path
                      renderMode:(OMDDocumentRenderMode)_currentDocumentRenderMode
                  syntaxLanguage:_currentDocumentSyntaxLanguage];
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

    NSString *path = [panel filename];
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

    OMMarkdownRenderer *printRenderer = [[OMMarkdownRenderer alloc] init];
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

    NSString *path = [panel filename];
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
    NSTimeInterval applyMs = perfLogging ? ((OMDNow() - applyStart) * 1000.0) : 0.0;
    [self updatePreviewDocumentGeometry];
    NSTimeInterval postStart = perfLogging ? OMDNow() : 0.0;
    [self updateCodeBlockButtons];
    if ([_textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *codeView = (OMDTextView *)_textView;
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
    NSColor *bg = [_renderer backgroundColor];
    if (bg != nil) {
        [_textView setDrawsBackground:NO];
        [_textView setBackgroundColor:bg];
        [_previewScrollView setDrawsBackground:YES];
        [_previewScrollView setBackgroundColor:bg];
    } else {
        [_previewScrollView setDrawsBackground:YES];
        [_previewScrollView setBackgroundColor:[NSColor whiteColor]];
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

- (CGFloat)splitView:(NSSplitView *)splitView
constrainSplitPosition:(CGFloat)proposedPosition
         ofSubviewAt:(NSInteger)dividerIndex
{
    if (splitView == _workspaceSplitView) {
        if (!_explorerSidebarVisible) {
            return 0.0;
        }
        CGFloat width = [_workspaceSplitView bounds].size.width;
        CGFloat divider = [_workspaceSplitView dividerThickness];
        CGFloat available = width - divider;
        CGFloat minSidebar = 170.0;
        CGFloat minMain = 360.0;
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
    [self layoutSourceEditorContainer];
    [self persistSplitViewRatio];
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
    if (_textView == nil) {
        return 0.0;
    }

    NSRect bounds = NSZeroRect;
    if (_previewScrollView != nil) {
        bounds = [[_previewScrollView contentView] bounds];
    } else {
        bounds = [_textView bounds];
    }
    NSSize inset = [_textView textContainerInset];
    NSTextContainer *container = [_textView textContainer];
    CGFloat padding = container != nil ? [container lineFragmentPadding] : 0.0;
    CGFloat width = bounds.size.width - (inset.width * 2.0) - (padding * 2.0);
    if (width < 0.0) {
        width = 0.0;
    }
    return width;
}

- (void)updatePreviewDocumentGeometry
{
    if (_textView == nil || _previewScrollView == nil) {
        return;
    }

    NSTextContainer *container = [_textView textContainer];
    NSLayoutManager *layoutManager = [_textView layoutManager];
    if (container == nil || layoutManager == nil) {
        return;
    }

    NSClipView *clipView = [_previewScrollView contentView];
    NSRect clipBounds = [clipView bounds];
    NSSize inset = [_textView textContainerInset];
    CGFloat padding = [container lineFragmentPadding];
    CGFloat layoutWidth = clipBounds.size.width - (inset.width * 2.0) - (padding * 2.0);
    if (layoutWidth < 1.0) {
        layoutWidth = 1.0;
    }

    [container setContainerSize:NSMakeSize(layoutWidth, FLT_MAX)];
    [layoutManager ensureLayoutForTextContainer:container];
    NSRect usedRect = [layoutManager usedRectForTextContainer:container];

    CGFloat contentWidth = ceil(usedRect.size.width + (inset.width * 2.0) + (padding * 2.0) + 2.0);
    CGFloat targetWidth = clipBounds.size.width;
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

    NSRect frame = [_textView frame];
    if (fabs(frame.size.width - targetWidth) > 0.5 ||
        fabs(frame.size.height - targetHeight) > 0.5) {
        [_textView setFrameSize:NSMakeSize(targetWidth, targetHeight)];
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
    return YES;
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
    if (_sourceEditorContainer == nil) {
        return;
    }
    if (_formattingBarView != nil) {
        return;
    }

    _formattingBarView = [[OMDFormattingBarView alloc] initWithFrame:NSMakeRect(0.0,
                                                                                 0.0,
                                                                                 NSWidth([_sourceEditorContainer bounds]),
                                                                                 OMDFormattingBarHeight)];
    [_formattingBarView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_formattingBarView setFillColor:[NSColor colorWithCalibratedRed:0.95 green:0.96 blue:0.97 alpha:1.0]];
    [_formattingBarView setBorderColor:[NSColor colorWithCalibratedRed:0.82 green:0.85 blue:0.89 alpha:1.0]];
    [_sourceEditorContainer addSubview:_formattingBarView];

    _formatCommandButtons = [[NSMutableDictionary alloc] init];

    CGFloat controlY = floor((OMDFormattingBarHeight - OMDFormattingBarControlHeight) / 2.0);
    CGFloat x = OMDFormattingBarInsetX;

    _formatHeadingPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x,
                                                                           controlY,
                                                                           OMDFormattingBarPopupWidth,
                                                                           OMDFormattingBarControlHeight)
                                                     pullsDown:NO];
    [_formatHeadingPopup addItemsWithTitles:[NSArray arrayWithObjects:@"Paragraph",
                                                                       @"Heading 1",
                                                                       @"Heading 2",
                                                                       @"Heading 3",
                                                                       @"Heading 4",
                                                                       @"Heading 5",
                                                                       @"Heading 6",
                                                                       nil]];
    [_formatHeadingPopup setToolTip:@"Heading level"];
    [_formatHeadingPopup setTarget:self];
    [_formatHeadingPopup setAction:@selector(formattingHeadingChanged:)];
    [_formatHeadingPopup setFont:[NSFont systemFontOfSize:11.0]];
    [_formatHeadingPopup setAutoresizingMask:NSViewMinYMargin];
    if ([[_formatHeadingPopup cell] respondsToSelector:@selector(setControlSize:)]) {
        [[_formatHeadingPopup cell] setControlSize:NSSmallControlSize];
    }
    [_formattingBarView addSubview:_formatHeadingPopup];

    x += OMDFormattingBarPopupWidth + OMDFormattingBarGroupSpacing;

    NSButton *button = nil;

    button = OMDFormattingButton(@"B", @"Bold (Ctrl/Cmd+B)", OMDFormattingCommandTagBold,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [button setFont:[NSFont boldSystemFontOfSize:11.0]];
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagBold]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"I", @"Italic (Ctrl/Cmd+I)", OMDFormattingCommandTagItalic,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    NSFont *italicFont = [NSFont fontWithName:@"Helvetica-Oblique" size:11.0];
    if (italicFont == nil) {
        italicFont = [NSFont systemFontOfSize:11.0];
    }
    [button setFont:italicFont];
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagItalic]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"S", @"Strikethrough", OMDFormattingCommandTagStrike,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagStrike]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"`", @"Inline code", OMDFormattingCommandTagInlineCode,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagInlineCode]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"Ln", @"Insert link", OMDFormattingCommandTagLink,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagLink]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"Im", @"Insert image", OMDFormattingCommandTagImage,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagImage]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarGroupSpacing;

    button = OMDFormattingButton(@"-", @"Toggle bullet list", OMDFormattingCommandTagListBullet,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagListBullet]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"1.", @"Toggle numbered list", OMDFormattingCommandTagListNumber,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagListNumber]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"[]", @"Toggle task list", OMDFormattingCommandTagListTask,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagListTask]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@">", @"Toggle block quote", OMDFormattingCommandTagBlockQuote,
                                 x, controlY, OMDFormattingBarButtonWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagBlockQuote]];
    x += OMDFormattingBarButtonWidth + OMDFormattingBarGroupSpacing;

    button = OMDFormattingButton(@"{}", @"Insert fenced code block", OMDFormattingCommandTagCodeFence,
                                 x, controlY, OMDFormattingBarButtonWideWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagCodeFence]];
    x += OMDFormattingBarButtonWideWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"T", @"Insert table", OMDFormattingCommandTagTable,
                                 x, controlY, OMDFormattingBarButtonWideWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagTable]];
    x += OMDFormattingBarButtonWideWidth + OMDFormattingBarControlSpacing;

    button = OMDFormattingButton(@"HR", @"Insert horizontal rule", OMDFormattingCommandTagHorizontalRule,
                                 x, controlY, OMDFormattingBarButtonWideWidth, OMDFormattingBarControlHeight, self);
    [_formattingBarView addSubview:button];
    [_formatCommandButtons setObject:button forKey:[NSNumber numberWithInteger:OMDFormattingCommandTagHorizontalRule]];

    [self updateFormattingBarContextState];
}

- (void)layoutSourceEditorContainer
{
    if (_sourceEditorContainer == nil || _sourceScrollView == nil) {
        return;
    }

    NSRect bounds = [_sourceEditorContainer bounds];
    BOOL showBar = [self isFormattingBarVisibleInCurrentMode];
    CGFloat barHeight = showBar ? OMDFormattingBarHeight : 0.0;

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
    if (_formatHeadingPopup != nil) {
        [_formatHeadingPopup setEnabled:enabled];
    }
    NSEnumerator *enumerator = [_formatCommandButtons objectEnumerator];
    NSButton *button = nil;
    while ((button = [enumerator nextObject]) != nil) {
        [button setEnabled:enabled];
    }

    if (!enabled || _formatHeadingPopup == nil || _sourceTextView == nil) {
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
    [_formatHeadingPopup selectItemAtIndex:level];
}

- (void)setViewerMode:(OMDViewerMode)mode persistPreference:(BOOL)persistPreference
{
    OMDViewerMode previousMode = OMDViewerModeFromInteger(_viewerMode);
    mode = OMDViewerModeFromInteger(mode);
    NSString *sourceAnchorText = nil;
    NSUInteger sourceAnchorLocation = NSNotFound;

    if (_sourceTextView != nil) {
        sourceAnchorText = [_sourceTextView string];
    }
    if ((sourceAnchorText == nil || [sourceAnchorText length] == 0) && _currentMarkdown != nil) {
        sourceAnchorText = _currentMarkdown;
    }

    if (previousMode == OMDViewerModeEdit || previousMode == OMDViewerModeSplit) {
        if (_sourceTextView != nil) {
            sourceAnchorLocation = [_sourceTextView selectedRange].location;
        }
    } else if (previousMode == OMDViewerModeRead && _textView != nil && sourceAnchorText != nil) {
        NSString *previewText = [[_textView textStorage] string];
        NSRange previewRange = [_textView selectedRange];
        NSUInteger previewLocation = previewRange.location;
        BOOL atPreviewEnd = [previewText length] > 0 && previewLocation >= [previewText length];
        sourceAnchorLocation = OMDMapTargetLocationWithBlockAnchors(sourceAnchorText,
                                                                    previewText,
                                                                    previewLocation,
                                                                    [_renderer blockAnchors]);
        if (atPreviewEnd) {
            sourceAnchorLocation = [sourceAnchorText length];
        }
    }

    if (previousMode == OMDViewerModeSplit && mode != OMDViewerModeSplit) {
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
                [_sourceTextView scrollRangeToVisible:NSMakeRange(sourceAnchorLocation, 0)];
                _isProgrammaticSelectionSync = NO;
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
            [_sourceTextView scrollRangeToVisible:NSMakeRange(sourceAnchorLocation, 0)];
            _isProgrammaticSelectionSync = NO;
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
            if ([sourceText length] > 0 &&
                sourceAnchorLocation >= [sourceText length] &&
                [previewText length] > 0) {
                previewLocation = [previewText length] - 1;
            }
            [self scrollPreviewToCharacterIndex:previewLocation];
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
        return;
    }

    BOOL editable = !_currentDocumentReadOnly;
    [_sourceTextView setEditable:editable];
    [_sourceTextView setSelectable:YES];
    [self updateFormattingBarContextState];
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
        if (_textView != nil) {
            _isProgrammaticPreviewUpdate = YES;
            NSAttributedString *empty = [[[NSAttributedString alloc] initWithString:@""] autorelease];
            [[_textView textStorage] setAttributedString:empty];
            _isProgrammaticPreviewUpdate = NO;
            [self updateCodeBlockButtons];
        }
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
}

- (NSMutableDictionary *)newDocumentTabWithMarkdown:(NSString *)markdown
                                         sourcePath:(NSString *)sourcePath
                                       displayTitle:(NSString *)displayTitle
                                           readOnly:(BOOL)readOnly
                                         renderMode:(OMDDocumentRenderMode)renderMode
                                     syntaxLanguage:(NSString *)syntaxLanguage
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
    return tab;
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
    if ([normalizedSourcePath length] > 0) {
        normalizedSourcePath = [normalizedSourcePath stringByStandardizingPath];
        NSInteger existingIndex = [self documentTabIndexForLocalPath:normalizedSourcePath];
        if (existingIndex >= 0) {
            [self selectDocumentTabAtIndex:existingIndex];
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
                                                  syntaxLanguage:syntaxLanguage];

    if (inNewTab || _selectedDocumentTabIndex < 0 || _selectedDocumentTabIndex >= (NSInteger)[_documentTabs count]) {
        [self captureCurrentStateIntoSelectedTab];
        [_documentTabs addObject:tab];
        _selectedDocumentTabIndex = (NSInteger)[_documentTabs count] - 1;
    } else {
        [_documentTabs replaceObjectAtIndex:_selectedDocumentTabIndex withObject:tab];
    }

    [self applyDocumentTabRecord:tab];
    [self updateTabStrip];
    return YES;
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
    if (_explorerTableView == nil) {
        return;
    }

    CGFloat fontSize = [self explorerListFontSizePreference];
    NSFont *font = [NSFont systemFontOfSize:fontSize];
    if (font == nil) {
        font = [NSFont systemFontOfSize:OMDExplorerListDefaultFontSize];
    }
    CGFloat rowHeight = ceil(fontSize + 8.0);
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
    if (_sidebarContainer == nil) {
        return;
    }

    NSRect bounds = [_sidebarContainer bounds];
    CGFloat width = NSWidth(bounds);

    _explorerSourceModeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(10, NSHeight(bounds) - 34, width - 20, 24)];
    [_explorerSourceModeControl setSegmentCount:2];
    [_explorerSourceModeControl setLabel:@"Local" forSegment:0];
    [_explorerSourceModeControl setLabel:@"GitHub" forSegment:1];
    [_explorerSourceModeControl setSelectedSegment:_explorerSourceMode];
    [_explorerSourceModeControl setTarget:self];
    [_explorerSourceModeControl setAction:@selector(explorerSourceModeChanged:)];
    [_explorerSourceModeControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerSourceModeControl];

    _explorerLocalRootLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, NSHeight(bounds) - 60, width - 20, 16)];
    [_explorerLocalRootLabel setBezeled:NO];
    [_explorerLocalRootLabel setEditable:NO];
    [_explorerLocalRootLabel setSelectable:NO];
    [_explorerLocalRootLabel setDrawsBackground:NO];
    [_explorerLocalRootLabel setFont:[NSFont systemFontOfSize:11.0]];
    [_explorerLocalRootLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerLocalRootLabel];

    _explorerGitHubUserLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, NSHeight(bounds) - 60, 44, 20)];
    [_explorerGitHubUserLabel setBezeled:NO];
    [_explorerGitHubUserLabel setEditable:NO];
    [_explorerGitHubUserLabel setSelectable:NO];
    [_explorerGitHubUserLabel setDrawsBackground:NO];
    [_explorerGitHubUserLabel setStringValue:@"User:"];
    [_explorerGitHubUserLabel setFont:[NSFont systemFontOfSize:11.0]];
    [_explorerGitHubUserLabel setAutoresizingMask:NSViewMinYMargin];
    [_sidebarContainer addSubview:_explorerGitHubUserLabel];

    _explorerGitHubUserComboBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(56, NSHeight(bounds) - 64, width - 66, 22)];
    [_explorerGitHubUserComboBox setUsesDataSource:NO];
    [_explorerGitHubUserComboBox setCompletes:YES];
    [_explorerGitHubUserComboBox setTarget:self];
    [_explorerGitHubUserComboBox setAction:@selector(explorerGitHubUserChanged:)];
    [_explorerGitHubUserComboBox setDelegate:self];
    [_explorerGitHubUserComboBox setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerGitHubUserComboBox];

    _explorerGitHubRepoComboBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(10, NSHeight(bounds) - 90, width - 20, 22)];
    [_explorerGitHubRepoComboBox setUsesDataSource:NO];
    [_explorerGitHubRepoComboBox setCompletes:YES];
    [_explorerGitHubRepoComboBox setTarget:self];
    [_explorerGitHubRepoComboBox setAction:@selector(explorerGitHubRepoChanged:)];
    [_explorerGitHubRepoComboBox setDelegate:self];
    [_explorerGitHubRepoComboBox setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerGitHubRepoComboBox];

    _explorerGitHubIncludeForkArchivedButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, NSHeight(bounds) - 116, width - 20, 20)];
    [_explorerGitHubIncludeForkArchivedButton setButtonType:NSSwitchButton];
    [_explorerGitHubIncludeForkArchivedButton setTitle:@"Include forked + archived repos"];
    [_explorerGitHubIncludeForkArchivedButton setFont:[NSFont systemFontOfSize:11.0]];
    [_explorerGitHubIncludeForkArchivedButton setTarget:self];
    [_explorerGitHubIncludeForkArchivedButton setAction:@selector(explorerGitHubIncludeForkArchivedChanged:)];
    [_explorerGitHubIncludeForkArchivedButton setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerGitHubIncludeForkArchivedButton];

    _explorerShowHiddenFilesButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, NSHeight(bounds) - 84, width - 20, 20)];
    [_explorerShowHiddenFilesButton setButtonType:NSSwitchButton];
    [_explorerShowHiddenFilesButton setTitle:@"Show hidden files"];
    [_explorerShowHiddenFilesButton setFont:[NSFont systemFontOfSize:11.0]];
    [_explorerShowHiddenFilesButton setState:([self isExplorerShowHiddenFilesEnabled] ? NSOnState : NSOffState)];
    [_explorerShowHiddenFilesButton setTarget:self];
    [_explorerShowHiddenFilesButton setAction:@selector(explorerShowHiddenFilesChanged:)];
    [_explorerShowHiddenFilesButton setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerShowHiddenFilesButton];

    _explorerNavigateUpButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, NSHeight(bounds) - 144, 52, 22)];
    [_explorerNavigateUpButton setTitle:@"Up"];
    [_explorerNavigateUpButton setBezelStyle:NSRoundedBezelStyle];
    [_explorerNavigateUpButton setTarget:self];
    [_explorerNavigateUpButton setAction:@selector(explorerNavigateUp:)];
    [_explorerNavigateUpButton setAutoresizingMask:NSViewMinYMargin];
    [_sidebarContainer addSubview:_explorerNavigateUpButton];

    _explorerPathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(66, NSHeight(bounds) - 140, width - 76, 18)];
    [_explorerPathLabel setBezeled:NO];
    [_explorerPathLabel setEditable:NO];
    [_explorerPathLabel setSelectable:NO];
    [_explorerPathLabel setDrawsBackground:NO];
    [_explorerPathLabel setFont:[NSFont systemFontOfSize:10.5]];
    [_explorerPathLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_sidebarContainer addSubview:_explorerPathLabel];

    _explorerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 10, width - 16, NSHeight(bounds) - 160)];
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
    BOOL githubMode = (_explorerSourceMode == OMDExplorerSourceModeGitHub);
    [_explorerSourceModeControl setSelectedSegment:_explorerSourceMode];
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

    NSRect bounds = [_sidebarContainer bounds];
    CGFloat width = NSWidth(bounds);
    CGFloat height = NSHeight(bounds);
    [_explorerSourceModeControl setFrame:NSMakeRect(10, height - 34, width - 20, 24)];
    [_explorerLocalRootLabel setFrame:NSMakeRect(10, height - 60, width - 20, 16)];
    [_explorerGitHubUserLabel setFrame:NSMakeRect(10, height - 60, 44, 20)];
    [_explorerGitHubUserComboBox setFrame:NSMakeRect(56, height - 64, width - 66, 22)];
    [_explorerGitHubRepoComboBox setFrame:NSMakeRect(10, height - 90, width - 20, 22)];
    [_explorerGitHubIncludeForkArchivedButton setFrame:NSMakeRect(10, height - 116, width - 20, 20)];
    [_explorerShowHiddenFilesButton setFrame:NSMakeRect(10, height - 84, width - 20, 20)];

    CGFloat navigateUpY = (githubMode ? height - 144 : height - 118);
    CGFloat pathY = (githubMode ? height - 140 : height - 114);
    CGFloat scrollHeight = (githubMode ? (height - 160) : (height - 126));
    if (scrollHeight < 80) {
        scrollHeight = 80;
    }
    [_explorerNavigateUpButton setFrame:NSMakeRect(10, navigateUpY, 52, 22)];
    [_explorerPathLabel setFrame:NSMakeRect(66, pathY, width - 76, 18)];
    [_explorerScrollView setFrame:NSMakeRect(8, 10, width - 16, scrollHeight)];
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
    BOOL hasEnv = [[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/env"];
    BOOL hasGit = [[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/git"];
    if (!hasEnv && !hasGit) {
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
        if (hasEnv) {
            [task setLaunchPath:@"/usr/bin/env"];
            [taskArguments addObject:@"git"];
        } else {
            [task setLaunchPath:@"/usr/bin/git"];
        }
        if (arguments != nil) {
            [taskArguments addObjectsFromArray:arguments];
        }
        [task setArguments:taskArguments];
        if (directory != nil && [directory length] > 0) {
            [task setCurrentDirectoryPath:directory];
        }

        NSPipe *stdoutPipe = [NSPipe pipe];
        NSPipe *stderrPipe = [NSPipe pipe];
        [task setStandardOutput:stdoutPipe];
        [task setStandardError:stderrPipe];

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
        BOOL cloned = [self runGitArguments:@[@"clone", @"--depth", @"1", remoteURL, repoPath]
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
                    cloned = [self runGitArguments:@[@"clone", @"--depth", @"1", remoteURL, repoPath]
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
    BOOL fetched = [self runGitArguments:@[@"fetch", @"--depth", @"1", @"origin"]
                             inDirectory:repoPath
                                  output:NULL
                                   error:&fetchError];
    if (fetched) {
        BOOL checkedOut = [self runGitArguments:@[@"checkout", @"-f", @"--detach", @"origin/HEAD"]
                                    inDirectory:repoPath
                                         output:NULL
                                          error:NULL];
        if (!checkedOut) {
            checkedOut = [self runGitArguments:@[@"checkout", @"-f", @"--detach", @"origin/main"]
                                    inDirectory:repoPath
                                         output:NULL
                                          error:NULL];
        }
        if (!checkedOut) {
            [self runGitArguments:@[@"checkout", @"-f", @"--detach", @"origin/master"]
                      inDirectory:repoPath
                           output:NULL
                            error:NULL];
        }
        [self runGitArguments:@[@"reset", @"--hard"]
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
    NSInteger mode = [_explorerSourceModeControl selectedSegment];
    if (mode != OMDExplorerSourceModeGitHub) {
        mode = OMDExplorerSourceModeLocal;
    }
    _explorerSourceMode = mode;
    [self reloadExplorerEntries];
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

        [self openDocumentWithMarkdown:(importedMarkdown != nil ? importedMarkdown : @"")
                            sourcePath:path
                          displayTitle:[path lastPathComponent]
                              readOnly:NO
                            renderMode:OMDDocumentRenderModeMarkdown
                        syntaxLanguage:nil
                              inNewTab:inNewTab
                   requireDirtyConfirm:!inNewTab];
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

    [self openDocumentWithMarkdown:markdown
                        sourcePath:path
                      displayTitle:[path lastPathComponent]
                          readOnly:NO
                        renderMode:renderMode
                    syntaxLanguage:syntaxLanguage
                          inNewTab:inNewTab
               requireDirtyConfirm:!inNewTab];
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
    if (_sourceScrollView != nil && object == [_sourceScrollView contentView]) {
        [self syncPreviewToSourceScrollPosition];
    } else if (_previewScrollView != nil && object == [_previewScrollView contentView]) {
        [self syncSourceToPreviewScrollPosition];
    }
}

- (NSUInteger)topVisibleCharacterIndexForTextView:(NSTextView *)textView
                                      inScrollView:(NSScrollView *)scrollView
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

    NSClipView *clipView = [scrollView contentView];
    NSRect visibleRect = [clipView bounds];
    NSPoint textOrigin = [textView textContainerOrigin];
    NSPoint probe = NSMakePoint(4.0, visibleRect.origin.y - textOrigin.y + 1.0);
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

    NSUInteger sourceLocation = [self topVisibleCharacterIndexForTextView:_sourceTextView
                                                              inScrollView:_sourceScrollView];
    NSUInteger previewLocation = OMDMapSourceLocationWithBlockAnchors(sourceText,
                                                                      sourceLocation,
                                                                      previewText,
                                                                      [_renderer blockAnchors]);
    _isProgrammaticScrollSync = YES;
    [self scrollPreviewToCharacterIndex:previewLocation verticalAnchor:0.0];
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

    NSUInteger previewLocation = [self topVisibleCharacterIndexForTextView:_textView
                                                               inScrollView:_previewScrollView];
    NSUInteger sourceLocation = OMDMapTargetLocationWithBlockAnchors(sourceText,
                                                                     previewText,
                                                                     previewLocation,
                                                                     [_renderer blockAnchors]);
    _isProgrammaticScrollSync = YES;
    [self scrollSourceToCharacterIndex:sourceLocation verticalAnchor:0.0];
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

    NSString *previewText = [[_textView textStorage] string];
    NSUInteger previewLength = [previewText length];
    if (previewLength == 0) {
        return;
    }

    if (characterIndex >= previewLength) {
        characterIndex = previewLength - 1;
    }

    NSLayoutManager *layoutManager = [_textView layoutManager];
    NSTextContainer *textContainer = [_textView textContainer];
    if (layoutManager == nil || textContainer == nil) {
        return;
    }

    [layoutManager ensureLayoutForTextContainer:textContainer];

    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(characterIndex, 1)
                                                actualCharacterRange:NULL];
    if (glyphRange.length == 0) {
        return;
    }

    NSRect glyphRect = [layoutManager boundingRectForGlyphRange:glyphRange
                                                 inTextContainer:textContainer];
    NSPoint textOrigin = [_textView textContainerOrigin];

    NSClipView *clipView = [_previewScrollView contentView];
    NSRect visibleRect = [clipView bounds];
    if (verticalAnchor < 0.0) {
        verticalAnchor = 0.0;
    } else if (verticalAnchor > 1.0) {
        verticalAnchor = 1.0;
    }
    CGFloat targetY = glyphRect.origin.y + textOrigin.y - floor((visibleRect.size.height - glyphRect.size.height) * verticalAnchor);
    if (targetY < 0.0) {
        targetY = 0.0;
    }

    CGFloat maxY = [_textView bounds].size.height - visibleRect.size.height;
    if (maxY < 0.0) {
        maxY = 0.0;
    }
    if (targetY > maxY) {
        targetY = maxY;
    }

    [clipView scrollToPoint:NSMakePoint(visibleRect.origin.x, targetY)];
    [_previewScrollView reflectScrolledClipView:clipView];
}

- (void)scrollSourceToCharacterIndex:(NSUInteger)characterIndex verticalAnchor:(CGFloat)verticalAnchor
{
    if (_sourceTextView == nil || _sourceScrollView == nil) {
        return;
    }

    NSString *sourceText = [[_sourceTextView textStorage] string];
    NSUInteger sourceLength = [sourceText length];
    if (sourceLength == 0) {
        return;
    }

    if (characterIndex >= sourceLength) {
        characterIndex = sourceLength - 1;
    }

    NSLayoutManager *layoutManager = [_sourceTextView layoutManager];
    NSTextContainer *textContainer = [_sourceTextView textContainer];
    if (layoutManager == nil || textContainer == nil) {
        return;
    }

    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(characterIndex, 1)
                                                actualCharacterRange:NULL];
    if (glyphRange.length == 0) {
        return;
    }

    NSRect glyphRect = [layoutManager boundingRectForGlyphRange:glyphRange
                                                 inTextContainer:textContainer];
    NSPoint textOrigin = [_sourceTextView textContainerOrigin];

    NSClipView *clipView = [_sourceScrollView contentView];
    NSRect visibleRect = [clipView bounds];
    if (verticalAnchor < 0.0) {
        verticalAnchor = 0.0;
    } else if (verticalAnchor > 1.0) {
        verticalAnchor = 1.0;
    }
    CGFloat targetY = glyphRect.origin.y + textOrigin.y - floor((visibleRect.size.height - glyphRect.size.height) * verticalAnchor);
    if (targetY < 0.0) {
        targetY = 0.0;
    }

    CGFloat maxY = [_sourceTextView bounds].size.height - visibleRect.size.height;
    if (maxY < 0.0) {
        maxY = 0.0;
    }
    if (targetY > maxY) {
        targetY = maxY;
    }

    [clipView scrollToPoint:NSMakePoint(visibleRect.origin.x, targetY)];
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

- (void)showPreferences:(id)sender
{
    if (_preferencesPanel == nil) {
        NSRect frame = NSMakeRect(160, 140, 460, 500);
        _preferencesPanel = [[NSPanel alloc] initWithContentRect:frame
                                                        styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        [_preferencesPanel setTitle:@"Preferences"];
        [_preferencesPanel setFrameAutosaveName:@"ObjcMarkdownViewerPreferencesPanel"];
        [_preferencesPanel setReleasedWhenClosed:NO];

        NSView *content = [_preferencesPanel contentView];

        NSTextField *explorerHeader = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 472, 420, 20)] autorelease];
        [explorerHeader setBezeled:NO];
        [explorerHeader setEditable:NO];
        [explorerHeader setSelectable:NO];
        [explorerHeader setDrawsBackground:NO];
        [explorerHeader setFont:[NSFont boldSystemFontOfSize:12.0]];
        [explorerHeader setStringValue:@"Explorer"];
        [content addSubview:explorerHeader];

        NSBox *explorerSeparator = [[[NSBox alloc] initWithFrame:NSMakeRect(20, 466, 420, 1)] autorelease];
        [explorerSeparator setBoxType:NSBoxSeparator];
        [content addSubview:explorerSeparator];

        NSTextField *localRootLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 442, 170, 20)] autorelease];
        [localRootLabel setBezeled:NO];
        [localRootLabel setEditable:NO];
        [localRootLabel setSelectable:NO];
        [localRootLabel setDrawsBackground:NO];
        [localRootLabel setStringValue:@"Local Explorer Root:"];
        [content addSubview:localRootLabel];

        _preferencesExplorerLocalRootField = [[NSTextField alloc] initWithFrame:NSMakeRect(172, 438, 206, 24)];
        [_preferencesExplorerLocalRootField setTarget:self];
        [_preferencesExplorerLocalRootField setAction:@selector(preferencesExplorerLocalRootChanged:)];
        [content addSubview:_preferencesExplorerLocalRootField];

        NSButton *explorerRootSetButton = [[[NSButton alloc] initWithFrame:NSMakeRect(384, 438, 52, 24)] autorelease];
        [explorerRootSetButton setTitle:@"Set"];
        [explorerRootSetButton setBezelStyle:NSRoundedBezelStyle];
        [explorerRootSetButton setTarget:self];
        [explorerRootSetButton setAction:@selector(preferencesExplorerLocalRootChanged:)];
        [content addSubview:explorerRootSetButton];

        NSTextField *maxFileSizeLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 414, 170, 20)] autorelease];
        [maxFileSizeLabel setBezeled:NO];
        [maxFileSizeLabel setEditable:NO];
        [maxFileSizeLabel setSelectable:NO];
        [maxFileSizeLabel setDrawsBackground:NO];
        [maxFileSizeLabel setStringValue:@"Max Open File Size:"];
        [content addSubview:maxFileSizeLabel];

        _preferencesExplorerMaxFileSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(172, 410, 60, 24)];
        [_preferencesExplorerMaxFileSizeField setTarget:self];
        [_preferencesExplorerMaxFileSizeField setAction:@selector(preferencesExplorerMaxFileSizeChanged:)];
        [content addSubview:_preferencesExplorerMaxFileSizeField];

        NSTextField *maxFileSizeSuffix = [[[NSTextField alloc] initWithFrame:NSMakeRect(236, 414, 40, 20)] autorelease];
        [maxFileSizeSuffix setBezeled:NO];
        [maxFileSizeSuffix setEditable:NO];
        [maxFileSizeSuffix setSelectable:NO];
        [maxFileSizeSuffix setDrawsBackground:NO];
        [maxFileSizeSuffix setStringValue:@"MB"];
        [content addSubview:maxFileSizeSuffix];

        NSTextField *listFontSizeLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(278, 414, 74, 20)] autorelease];
        [listFontSizeLabel setBezeled:NO];
        [listFontSizeLabel setEditable:NO];
        [listFontSizeLabel setSelectable:NO];
        [listFontSizeLabel setDrawsBackground:NO];
        [listFontSizeLabel setStringValue:@"List Font:"];
        [content addSubview:listFontSizeLabel];

        _preferencesExplorerListFontSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(352, 410, 46, 24)];
        [_preferencesExplorerListFontSizeField setTarget:self];
        [_preferencesExplorerListFontSizeField setAction:@selector(preferencesExplorerListFontSizeChanged:)];
        [content addSubview:_preferencesExplorerListFontSizeField];

        NSTextField *listFontSizeSuffix = [[[NSTextField alloc] initWithFrame:NSMakeRect(402, 414, 24, 20)] autorelease];
        [listFontSizeSuffix setBezeled:NO];
        [listFontSizeSuffix setEditable:NO];
        [listFontSizeSuffix setSelectable:NO];
        [listFontSizeSuffix setDrawsBackground:NO];
        [listFontSizeSuffix setStringValue:@"pt"];
        [content addSubview:listFontSizeSuffix];

        NSTextField *tokenLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 386, 170, 20)] autorelease];
        [tokenLabel setBezeled:NO];
        [tokenLabel setEditable:NO];
        [tokenLabel setSelectable:NO];
        [tokenLabel setDrawsBackground:NO];
        [tokenLabel setStringValue:@"GitHub API Token:"];
        [content addSubview:tokenLabel];

        _preferencesExplorerGitHubTokenField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(172, 382, 264, 24)];
        [_preferencesExplorerGitHubTokenField setTarget:self];
        [_preferencesExplorerGitHubTokenField setAction:@selector(preferencesExplorerGitHubTokenChanged:)];
        [content addSubview:_preferencesExplorerGitHubTokenField];

        NSTextField *tokenNote = [[[NSTextField alloc] initWithFrame:NSMakeRect(172, 348, 264, 14)] autorelease];
        [tokenNote setBezeled:NO];
        [tokenNote setEditable:NO];
        [tokenNote setSelectable:NO];
        [tokenNote setDrawsBackground:NO];
        [tokenNote setFont:[NSFont systemFontOfSize:10.0]];
        [tokenNote setTextColor:[NSColor disabledControlTextColor]];
        [tokenNote setStringValue:@"Optional. Increases GitHub API rate limits."];
        [content addSubview:tokenNote];

        NSTextField *syncHeader = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 364, 420, 20)] autorelease];
        [syncHeader setBezeled:NO];
        [syncHeader setEditable:NO];
        [syncHeader setSelectable:NO];
        [syncHeader setDrawsBackground:NO];
        [syncHeader setFont:[NSFont boldSystemFontOfSize:12.0]];
        [syncHeader setStringValue:@"Preview Sync"];
        [content addSubview:syncHeader];

        NSBox *syncSeparator = [[[NSBox alloc] initWithFrame:NSMakeRect(20, 358, 420, 1)] autorelease];
        [syncSeparator setBoxType:NSBoxSeparator];
        [content addSubview:syncSeparator];

        NSTextField *splitSyncLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 324, 170, 20)] autorelease];
        [splitSyncLabel setBezeled:NO];
        [splitSyncLabel setEditable:NO];
        [splitSyncLabel setSelectable:NO];
        [splitSyncLabel setDrawsBackground:NO];
        [splitSyncLabel setStringValue:@"Split Sync Mode:"];
        [content addSubview:splitSyncLabel];

        _preferencesSplitSyncModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(210, 320, 225, 26)
                                                                     pullsDown:NO];
        [_preferencesSplitSyncModePopup addItemWithTitle:@"Independent"];
        [[_preferencesSplitSyncModePopup itemAtIndex:0] setTag:OMDSplitSyncModeUnlinked];
        [_preferencesSplitSyncModePopup addItemWithTitle:@"Linked Scrolling"];
        [[_preferencesSplitSyncModePopup itemAtIndex:1] setTag:OMDSplitSyncModeLinkedScrolling];
        [_preferencesSplitSyncModePopup addItemWithTitle:@"Follow Caret"];
        [[_preferencesSplitSyncModePopup itemAtIndex:2] setTag:OMDSplitSyncModeCaretSelectionFollow];
        [_preferencesSplitSyncModePopup setTarget:self];
        [_preferencesSplitSyncModePopup setAction:@selector(preferencesSplitSyncModeChanged:)];
        [content addSubview:_preferencesSplitSyncModePopup];

        NSTextField *syncHelp = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 300, 420, 16)] autorelease];
        [syncHelp setBezeled:NO];
        [syncHelp setEditable:NO];
        [syncHelp setSelectable:NO];
        [syncHelp setDrawsBackground:NO];
        [syncHelp setFont:[NSFont systemFontOfSize:11.0]];
        [syncHelp setTextColor:[NSColor disabledControlTextColor]];
        [syncHelp setStringValue:@"Linked Scrolling follows pane scroll; Follow Caret tracks cursor/selection moves."];
        [content addSubview:syncHelp];

        NSTextField *renderHeader = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 278, 420, 20)] autorelease];
        [renderHeader setBezeled:NO];
        [renderHeader setEditable:NO];
        [renderHeader setSelectable:NO];
        [renderHeader setDrawsBackground:NO];
        [renderHeader setFont:[NSFont boldSystemFontOfSize:12.0]];
        [renderHeader setStringValue:@"Rendering"];
        [content addSubview:renderHeader];

        NSBox *renderSeparator = [[[NSBox alloc] initWithFrame:NSMakeRect(20, 272, 420, 1)] autorelease];
        [renderSeparator setBoxType:NSBoxSeparator];
        [content addSubview:renderSeparator];

        NSTextField *mathLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 246, 190, 20)] autorelease];
        [mathLabel setBezeled:NO];
        [mathLabel setEditable:NO];
        [mathLabel setSelectable:NO];
        [mathLabel setDrawsBackground:NO];
        [mathLabel setStringValue:@"Math Rendering:"];
        [content addSubview:mathLabel];

        _preferencesMathPolicyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(210, 242, 225, 26)
                                                                  pullsDown:NO];
        [_preferencesMathPolicyPopup addItemWithTitle:@"Styled Text (Safe)"];
        [[_preferencesMathPolicyPopup itemAtIndex:0] setTag:OMMarkdownMathRenderingPolicyStyledText];
        [_preferencesMathPolicyPopup addItemWithTitle:@"Disabled (Literal $...$)"];
        [[_preferencesMathPolicyPopup itemAtIndex:1] setTag:OMMarkdownMathRenderingPolicyDisabled];
        [_preferencesMathPolicyPopup addItemWithTitle:@"External Tools (LaTeX)"];
        [[_preferencesMathPolicyPopup itemAtIndex:2] setTag:OMMarkdownMathRenderingPolicyExternalTools];
        [_preferencesMathPolicyPopup setTarget:self];
        [_preferencesMathPolicyPopup setAction:@selector(preferencesMathPolicyChanged:)];
        [content addSubview:_preferencesMathPolicyPopup];

        _preferencesAllowRemoteImagesButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 214, 300, 22)];
        [_preferencesAllowRemoteImagesButton setButtonType:NSSwitchButton];
        [_preferencesAllowRemoteImagesButton setTitle:@"Allow Remote Images"];
        [_preferencesAllowRemoteImagesButton setTarget:self];
        [_preferencesAllowRemoteImagesButton setAction:@selector(preferencesAllowRemoteImagesChanged:)];
        [content addSubview:_preferencesAllowRemoteImagesButton];

        _preferencesRendererSyntaxHighlightingButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 186, 390, 22)];
        [_preferencesRendererSyntaxHighlightingButton setButtonType:NSSwitchButton];
        [_preferencesRendererSyntaxHighlightingButton setTitle:@"Renderer Syntax Highlighting (Code Blocks)"];
        [_preferencesRendererSyntaxHighlightingButton setTarget:self];
        [_preferencesRendererSyntaxHighlightingButton setAction:@selector(preferencesRendererSyntaxHighlightingChanged:)];
        [content addSubview:_preferencesRendererSyntaxHighlightingButton];

        _preferencesRendererSyntaxHighlightingNoteLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 152, 395, 30)];
        [_preferencesRendererSyntaxHighlightingNoteLabel setBezeled:NO];
        [_preferencesRendererSyntaxHighlightingNoteLabel setEditable:NO];
        [_preferencesRendererSyntaxHighlightingNoteLabel setSelectable:NO];
        [_preferencesRendererSyntaxHighlightingNoteLabel setDrawsBackground:NO];
        [_preferencesRendererSyntaxHighlightingNoteLabel setFont:[NSFont systemFontOfSize:11.0]];
        [_preferencesRendererSyntaxHighlightingNoteLabel setStringValue:@"Tree-sitter is required for renderer syntax highlighting."];
        [content addSubview:_preferencesRendererSyntaxHighlightingNoteLabel];

        NSTextField *editingHeader = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 128, 420, 20)] autorelease];
        [editingHeader setBezeled:NO];
        [editingHeader setEditable:NO];
        [editingHeader setSelectable:NO];
        [editingHeader setDrawsBackground:NO];
        [editingHeader setFont:[NSFont boldSystemFontOfSize:12.0]];
        [editingHeader setStringValue:@"Editing"];
        [content addSubview:editingHeader];

        NSBox *editingSeparator = [[[NSBox alloc] initWithFrame:NSMakeRect(20, 122, 420, 1)] autorelease];
        [editingSeparator setBoxType:NSBoxSeparator];
        [content addSubview:editingSeparator];

        _preferencesWordSelectionShimButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 96, 420, 22)];
        [_preferencesWordSelectionShimButton setButtonType:NSSwitchButton];
        [_preferencesWordSelectionShimButton setTitle:@"Ctrl/Cmd+Shift+Arrow Selects Words (Source Editor)"];
        [_preferencesWordSelectionShimButton setTarget:self];
        [_preferencesWordSelectionShimButton setAction:@selector(preferencesWordSelectionShimChanged:)];
        [content addSubview:_preferencesWordSelectionShimButton];

        _preferencesSourceVimKeyBindingsButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 74, 350, 22)];
        [_preferencesSourceVimKeyBindingsButton setButtonType:NSSwitchButton];
        [_preferencesSourceVimKeyBindingsButton setTitle:@"Enable Vim Key Bindings (Source Editor)"];
        [_preferencesSourceVimKeyBindingsButton setTarget:self];
        [_preferencesSourceVimKeyBindingsButton setAction:@selector(preferencesSourceVimKeyBindingsChanged:)];
        [content addSubview:_preferencesSourceVimKeyBindingsButton];

        _preferencesSyntaxHighlightingButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 52, 350, 22)];
        [_preferencesSyntaxHighlightingButton setButtonType:NSSwitchButton];
        [_preferencesSyntaxHighlightingButton setTitle:@"Source Syntax Highlighting"];
        [_preferencesSyntaxHighlightingButton setTarget:self];
        [_preferencesSyntaxHighlightingButton setAction:@selector(preferencesSyntaxHighlightingChanged:)];
        [content addSubview:_preferencesSyntaxHighlightingButton];

        _preferencesSourceHighContrastButton = [[NSButton alloc] initWithFrame:NSMakeRect(40, 30, 330, 22)];
        [_preferencesSourceHighContrastButton setButtonType:NSSwitchButton];
        [_preferencesSourceHighContrastButton setTitle:@"High Contrast Source Highlighting"];
        [_preferencesSourceHighContrastButton setTarget:self];
        [_preferencesSourceHighContrastButton setAction:@selector(preferencesSourceHighContrastChanged:)];
        [content addSubview:_preferencesSourceHighContrastButton];

        NSTextField *sourceAccentLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(40, 8, 140, 20)] autorelease];
        [sourceAccentLabel setBezeled:NO];
        [sourceAccentLabel setEditable:NO];
        [sourceAccentLabel setSelectable:NO];
        [sourceAccentLabel setDrawsBackground:NO];
        [sourceAccentLabel setStringValue:@"Source Accent Color:"];
        [content addSubview:sourceAccentLabel];

        _preferencesSourceAccentColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(186, 4, 64, 24)];
        [_preferencesSourceAccentColorWell setTarget:self];
        [_preferencesSourceAccentColorWell setAction:@selector(preferencesSourceAccentColorChanged:)];
        [content addSubview:_preferencesSourceAccentColorWell];

        _preferencesSourceAccentResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(256, 4, 74, 24)];
        [_preferencesSourceAccentResetButton setTitle:@"Reset"];
        [_preferencesSourceAccentResetButton setBezelStyle:NSRoundedBezelStyle];
        [_preferencesSourceAccentResetButton setTarget:self];
        [_preferencesSourceAccentResetButton setAction:@selector(preferencesSourceAccentReset:)];
        [content addSubview:_preferencesSourceAccentResetButton];
    }

    [self syncPreferencesPanelFromSettings];
    [_preferencesPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)syncPreferencesPanelFromSettings
{
    if (_preferencesPanel == nil) {
        return;
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
    [_preferencesAllowRemoteImagesButton setState:([self isAllowRemoteImagesEnabled] ? NSOnState : NSOffState)];
    [_preferencesWordSelectionShimButton setState:([self isWordSelectionModifierShimEnabled] ? NSOnState : NSOffState)];
    if (_preferencesSourceVimKeyBindingsButton != nil) {
        [_preferencesSourceVimKeyBindingsButton setState:([self isSourceVimKeyBindingsEnabled] ? NSOnState : NSOffState)];
    }
    [_preferencesSyntaxHighlightingButton setState:([self isSourceSyntaxHighlightingEnabled] ? NSOnState : NSOffState)];
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

- (void)preferencesExplorerLocalRootChanged:(id)sender
{
    (void)sender;
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

- (void)formattingHeadingChanged:(id)sender
{
    if (sender != _formatHeadingPopup) {
        return;
    }
    if (![self isFormattingBarVisibleInCurrentMode]) {
        return;
    }
    if (_currentDocumentReadOnly) {
        return;
    }
    NSInteger index = [_formatHeadingPopup indexOfSelectedItem];
    [self applyHeadingLevel:index];
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
        NSString *expanded = [candidate stringByExpandingTildeInPath];
        if (![expanded isAbsolutePath]) {
            NSString *cwd = [fm currentDirectoryPath];
            expanded = [cwd stringByAppendingPathComponent:expanded];
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
    if (path == nil || [path length] == 0) {
        return NO;
    }

    NSString *resolvedPath = [path stringByExpandingTildeInPath];
    if (![resolvedPath isAbsolutePath]) {
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        resolvedPath = [cwd stringByAppendingPathComponent:resolvedPath];
    }

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:resolvedPath error:NULL];
    NSNumber *sizeValue = [attributes objectForKey:NSFileSize];
    if ([sizeValue respondsToSelector:@selector(unsignedLongLongValue)]) {
        if (![self ensureOpenFileSizeWithinLimit:[sizeValue unsignedLongLongValue]
                                      descriptor:[resolvedPath lastPathComponent]]) {
            return NO;
        }
    }

    if ([self isImportableDocumentPath:resolvedPath]) {
        return [self importDocumentAtPath:resolvedPath];
    }

    NSError *error = nil;
    NSString *markdown = [self decodedTextForFileAtPath:resolvedPath error:&error];
    if (markdown == nil) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Unsupported file type"];
        [alert setInformativeText:(error != nil ? [error localizedDescription]
                                                : @"This file cannot be opened as text.")];
        [alert runModal];
        return NO;
    }

    NSString *extension = [[resolvedPath pathExtension] lowercaseString];
    OMDDocumentRenderMode renderMode = [self isMarkdownTextPath:resolvedPath]
                                       ? OMDDocumentRenderModeMarkdown
                                       : OMDDocumentRenderModeVerbatim;
    NSString *syntaxLanguage = (renderMode == OMDDocumentRenderModeVerbatim
                                ? OMDVerbatimSyntaxTokenForExtension(extension)
                                : nil);

    return [self openDocumentWithMarkdown:markdown
                                sourcePath:resolvedPath
                              displayTitle:[resolvedPath lastPathComponent]
                                  readOnly:NO
                                renderMode:renderMode
                            syntaxLanguage:syntaxLanguage
                                  inNewTab:NO
                       requireDirtyConfirm:YES];
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
    [self persistSplitViewRatio];
    [self cancelPendingInteractiveRender];
    [self cancelPendingMathArtifactRender];
    [self cancelPendingLivePreviewRender];
    [self cancelPendingPreviewStatusUpdatingVisibility];
    [self cancelPendingPreviewStatusAutoHide];
    [self cancelPendingRecoveryAutosave];
    [self clearRecoverySnapshot];
    [self setPreviewUpdating:NO];
    [self unregisterAsSecondaryWindow];
}

@end
