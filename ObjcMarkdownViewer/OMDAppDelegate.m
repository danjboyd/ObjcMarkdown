// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

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
static const CGFloat OMDToolbarControlHeight = 22.0;
static const CGFloat OMDToolbarLabelHeight = 20.0;
static const CGFloat OMDToolbarItemHeight = 26.0;
static NSString * const OMDSourceEditorFontNameDefaultsKey = @"ObjcMarkdownSourceEditorFontName";
static NSString * const OMDSourceEditorFontSizeDefaultsKey = @"ObjcMarkdownSourceEditorFontSize";
static NSString * const OMDMathRenderingPolicyDefaultsKey = @"ObjcMarkdownMathRenderingPolicy";
static NSString * const OMDAllowRemoteImagesDefaultsKey = @"ObjcMarkdownAllowRemoteImages";
static NSString * const OMDSplitSyncModeDefaultsKey = @"ObjcMarkdownSplitSyncMode";
static NSString * const OMDWordSelectionModifierShimDefaultsKey = @"ObjcMarkdownWordSelectionShimEnabled";
static NSString * const OMDSourceSyntaxHighlightingDefaultsKey = @"ObjcMarkdownSourceSyntaxHighlightingEnabled";
static NSString * const OMDSourceHighlightHighContrastDefaultsKey = @"ObjcMarkdownSourceHighlightHighContrastEnabled";
static NSString * const OMDSourceHighlightAccentColorDefaultsKey = @"ObjcMarkdownSourceHighlightAccentColor";
static NSString * const OMDRendererSyntaxHighlightingDefaultsKey = @"ObjcMarkdownRendererSyntaxHighlightingEnabled";
static NSString * const OMDShowFormattingBarDefaultsKey = @"ObjcMarkdownShowFormattingBar";

typedef NS_ENUM(NSInteger, OMDSplitSyncMode) {
    OMDSplitSyncModeUnlinked = 0,
    OMDSplitSyncModeLinkedScrolling = 1,
    OMDSplitSyncModeCaretSelectionFollow = 2
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

static BOOL OMDIsInlineWhitespace(unichar ch)
{
    return ch == ' ' || ch == '\t';
}

static NSUInteger OMDLeadingRunLengthForCharacter(NSString *text, unichar token)
{
    if (text == nil) {
        return 0;
    }
    NSUInteger length = [text length];
    NSUInteger count = 0;
    while (count < length && [text characterAtIndex:count] == token) {
        count += 1;
    }
    return count;
}

static NSUInteger OMDTrailingRunLengthForCharacter(NSString *text, unichar token)
{
    if (text == nil) {
        return 0;
    }
    NSUInteger length = [text length];
    NSUInteger count = 0;
    while (count < length && [text characterAtIndex:(length - count - 1)] == token) {
        count += 1;
    }
    return count;
}

static BOOL OMDInlineSingleCharacterWrapperToken(NSString *prefix, NSString *suffix, unichar *tokenOut)
{
    if (prefix == nil || suffix == nil) {
        return NO;
    }
    if ([prefix length] != 1 || [suffix length] != 1) {
        return NO;
    }
    unichar token = [prefix characterAtIndex:0];
    if ([suffix characterAtIndex:0] != token) {
        return NO;
    }
    if (tokenOut != NULL) {
        *tokenOut = token;
    }
    return YES;
}

static BOOL OMDInlineTextHasToggleWrapper(NSString *text,
                                          NSString *prefix,
                                          NSString *suffix)
{
    if (text == nil || prefix == nil || suffix == nil) {
        return NO;
    }
    NSUInteger prefixLength = [prefix length];
    NSUInteger suffixLength = [suffix length];
    if (prefixLength == 0 || suffixLength == 0) {
        return NO;
    }
    if ([text length] < prefixLength + suffixLength) {
        return NO;
    }
    if (![text hasPrefix:prefix] || ![text hasSuffix:suffix]) {
        return NO;
    }

    unichar token = 0;
    if (!OMDInlineSingleCharacterWrapperToken(prefix, suffix, &token)) {
        return YES;
    }

    NSUInteger leadingRun = OMDLeadingRunLengthForCharacter(text, token);
    NSUInteger trailingRun = OMDTrailingRunLengthForCharacter(text, token);
    return ((leadingRun % 2) == 1) && ((trailingRun % 2) == 1);
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

@interface OMDAppDelegate ()
- (void)importDocument:(id)sender;
- (void)saveDocument:(id)sender;
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
- (BOOL)isImportableDocumentPath:(NSString *)path;
- (void)presentConverterError:(NSError *)error fallbackTitle:(NSString *)title;
- (void)setCurrentMarkdown:(NSString *)markdown sourcePath:(NSString *)sourcePath;
- (BOOL)openDocumentAtPath:(NSString *)path;
- (BOOL)openDocumentAtPathInNewWindow:(NSString *)path;
- (BOOL)saveCurrentMarkdownToPath:(NSString *)path;
- (BOOL)saveDocumentAsMarkdownWithPanel;
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
- (void)preferencesSyntaxHighlightingChanged:(id)sender;
- (void)preferencesSourceHighContrastChanged:(id)sender;
- (void)preferencesSourceAccentColorChanged:(id)sender;
- (void)preferencesSourceAccentReset:(id)sender;
- (void)preferencesRendererSyntaxHighlightingChanged:(id)sender;
- (BOOL)isWordSelectionModifierShimEnabled;
- (void)setWordSelectionModifierShimEnabled:(BOOL)enabled;
- (void)toggleWordSelectionModifierShim:(id)sender;
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
    [_currentMarkdown release];
    [_currentPath release];
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
    [_preferencesSyntaxHighlightingButton release];
    [_preferencesSourceHighContrastButton release];
    [_preferencesSourceAccentColorWell release];
    [_preferencesSourceAccentResetButton release];
    [_preferencesRendererSyntaxHighlightingButton release];
    [_preferencesRendererSyntaxHighlightingNoteLabel release];
    [_formatHeadingPopup release];
    [_formatCommandButtons release];
    [_formattingBarView release];
    [_sourceEditorContainer release];
    [_preferencesPanel release];
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
        if (![self restoreRecoveryIfAvailable]) {
            [self openDocument:self];
        }
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
    if (_currentPath == nil && _currentMarkdown == nil) {
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

    NSMenuItem *wordSelectionShimItem = (NSMenuItem *)[viewMenu addItemWithTitle:@"Word Selection for Ctrl/Cmd+Shift+Arrow"
                                                                            action:@selector(toggleWordSelectionModifierShim:)
                                                                     keyEquivalent:@""];
    [wordSelectionShimItem setTarget:self];
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
    [_previewScrollView setDrawsBackground:YES];
    [_previewScrollView setBackgroundColor:[NSColor whiteColor]];

    _textView = [[OMDTextView alloc] initWithFrame:[[_previewScrollView contentView] bounds]];
    [_textView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_textView setEditable:NO];
    [_textView setSelectable:YES];
    [_textView setRichText:YES];
    [_textView setDrawsBackground:NO];
    [_textView setTextContainerInset:NSMakeSize(20.0, 16.0)];
    [[_textView textContainer] setLineFragmentPadding:0.0];
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
    [[_window contentView] addSubview:_documentContainer];

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
    [_renderer setZoomScale:_zoomScale];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mathArtifactsDidWarm:)
                                                 name:OMMarkdownRendererMathArtifactsDidWarmNotification
                                               object:nil];

    _viewerMode = OMDViewerModeFromInteger([[NSUserDefaults standardUserDefaults] integerForKey:@"ObjcMarkdownViewerMode"]);
    [self setViewerMode:_viewerMode persistPreference:NO];
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
    if (!outsideVisible && !tooWide && !tooTall) {
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
    if ([identifier isEqualToString:@"OpenDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"OpenDocument"] autorelease];
        [item setLabel:@"Open"];
        [item setPaletteLabel:@"Open"];
        [item setToolTip:@"Open a Markdown file"];
        [item setTarget:self];
        [item setAction:@selector(openDocument:)];
        NSImage *image = OMDToolbarImageNamed(@"toolbar-open.png");
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
        NSImage *image = OMDToolbarImageNamed(@"toolbar-import.png");
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
        NSImage *image = OMDToolbarImageNamed(@"toolbar-saveas.png");
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
        NSImage *image = OMDToolbarImageNamed(@"toolbar-print.png");
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
        NSImage *image = OMDToolbarImageNamed(@"toolbar-export.png");
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
        action == @selector(exportDocumentAsODT:)) {
        return [self hasLoadedDocument];
    }
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem
{
    NSString *identifier = [toolbarItem itemIdentifier];
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
    [self updatePreviewStatusIndicator];
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
    if (_currentPath != nil) {
        [snapshot setObject:_currentPath forKey:@"sourcePath"];
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

    [self setCurrentMarkdown:markdown sourcePath:sourcePath];
    _sourceIsDirty = YES;
    _sourceRevision = 1;
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

    [self setCurrentMarkdown:_currentMarkdown sourcePath:path];
    [self clearRecoverySnapshot];
    return YES;
}

- (BOOL)saveDocumentAsMarkdownWithPanel
{
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
        return NO;
    }

    NSString *path = [panel filename];
    if (path == nil || [path length] == 0) {
        return NO;
    }
    NSString *extension = [[path pathExtension] lowercaseString];
    if (![extension isEqualToString:@"md"] && ![extension isEqualToString:@"markdown"]) {
        path = [path stringByAppendingPathExtension:@"md"];
    }

    return [self saveCurrentMarkdownToPath:path];
}

- (void)saveDocument:(id)sender
{
    if (![self ensureDocumentLoadedForActionName:@"Save"]) {
        return;
    }

    if (_currentPath != nil && [_currentPath length] > 0) {
        [self saveCurrentMarkdownToPath:_currentPath];
        return;
    }

    [self saveDocumentAsMarkdownWithPanel];
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
    NSAttributedString *rendered = [_renderer attributedStringFromMarkdown:_currentMarkdown];
    NSTimeInterval markdownMs = perfLogging ? ((OMDNow() - markdownStart) * 1000.0) : 0.0;
    NSTimeInterval applyStart = perfLogging ? OMDNow() : 0.0;
    _isProgrammaticPreviewUpdate = YES;
    [[_textView textStorage] setAttributedString:rendered];
    _isProgrammaticPreviewUpdate = NO;
    NSTimeInterval applyMs = perfLogging ? ((OMDNow() - applyStart) * 1000.0) : 0.0;
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
              (unsigned long)[_currentMarkdown length],
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
    [self layoutDocumentViews];
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

    NSRect bounds = [_textView bounds];
    NSSize inset = [_textView textContainerInset];
    NSTextContainer *container = [_textView textContainer];
    CGFloat padding = container != nil ? [container lineFragmentPadding] : 0.0;
    CGFloat width = bounds.size.width - (inset.width * 2.0) - (padding * 2.0);
    if (width < 0.0) {
        width = 0.0;
    }
    return width;
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
    BOOL enabled = [self isFormattingBarVisibleInCurrentMode] && _sourceTextView != nil;
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
        NSRect frame = NSMakeRect(160, 140, 460, 392);
        _preferencesPanel = [[NSPanel alloc] initWithContentRect:frame
                                                        styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        [_preferencesPanel setTitle:@"Preferences"];
        [_preferencesPanel setFrameAutosaveName:@"ObjcMarkdownViewerPreferencesPanel"];
        [_preferencesPanel setReleasedWhenClosed:NO];

        NSView *content = [_preferencesPanel contentView];

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

        NSTextField *splitSyncLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 332, 170, 20)] autorelease];
        [splitSyncLabel setBezeled:NO];
        [splitSyncLabel setEditable:NO];
        [splitSyncLabel setSelectable:NO];
        [splitSyncLabel setDrawsBackground:NO];
        [splitSyncLabel setStringValue:@"Split Sync Mode:"];
        [content addSubview:splitSyncLabel];

        _preferencesSplitSyncModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(210, 328, 225, 26)
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

        NSTextField *syncHelp = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 308, 420, 16)] autorelease];
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

        _preferencesSyntaxHighlightingButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 70, 350, 22)];
        [_preferencesSyntaxHighlightingButton setButtonType:NSSwitchButton];
        [_preferencesSyntaxHighlightingButton setTitle:@"Source Syntax Highlighting"];
        [_preferencesSyntaxHighlightingButton setTarget:self];
        [_preferencesSyntaxHighlightingButton setAction:@selector(preferencesSyntaxHighlightingChanged:)];
        [content addSubview:_preferencesSyntaxHighlightingButton];

        _preferencesSourceHighContrastButton = [[NSButton alloc] initWithFrame:NSMakeRect(40, 44, 330, 22)];
        [_preferencesSourceHighContrastButton setButtonType:NSSwitchButton];
        [_preferencesSourceHighContrastButton setTitle:@"High Contrast Source Highlighting"];
        [_preferencesSourceHighContrastButton setTarget:self];
        [_preferencesSourceHighContrastButton setAction:@selector(preferencesSourceHighContrastChanged:)];
        [content addSubview:_preferencesSourceHighContrastButton];

        NSTextField *sourceAccentLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(40, 18, 140, 20)] autorelease];
        [sourceAccentLabel setBezeled:NO];
        [sourceAccentLabel setEditable:NO];
        [sourceAccentLabel setSelectable:NO];
        [sourceAccentLabel setDrawsBackground:NO];
        [sourceAccentLabel setStringValue:@"Source Accent Color:"];
        [content addSubview:sourceAccentLabel];

        _preferencesSourceAccentColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(186, 14, 64, 24)];
        [_preferencesSourceAccentColorWell setTarget:self];
        [_preferencesSourceAccentColorWell setAction:@selector(preferencesSourceAccentColorChanged:)];
        [content addSubview:_preferencesSourceAccentColorWell];

        _preferencesSourceAccentResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(256, 14, 74, 24)];
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
    NSString *updatingMarker = _previewIsUpdating ? @" [updating]" : @"";
    [_window setTitle:[NSString stringWithFormat:@"%@%@ (%@%@)", baseTitle, dirtyMarker, modeTitle, updatingMarker]];
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

    NSString *resolvedPrefix = (prefix != nil ? prefix : @"");
    NSString *resolvedSuffix = (suffix != nil ? suffix : @"");
    NSUInteger prefixLength = [resolvedPrefix length];
    NSUInteger suffixLength = [resolvedSuffix length];

    if (selection.length > 0) {
        NSString *selectedText = [source substringWithRange:selection];

        // For multiline selections, toggle line-by-line for deterministic behavior:
        // first pass normalizes mixed states, second pass reverts.
        if (prefixLength > 0 &&
            suffixLength > 0 &&
            [selectedText rangeOfString:@"\n"].location != NSNotFound) {
            NSArray *lines = [selectedText componentsSeparatedByString:@"\n"];
            BOOL sawToggleEligibleLine = NO;
            BOOL allLinesWrapped = YES;
            NSMutableArray *lineMetadata = [NSMutableArray arrayWithCapacity:[lines count]];

            for (NSString *line in lines) {
                NSString *work = (line != nil ? line : @"");
                NSUInteger length = [work length];
                NSUInteger leadingWhitespace = 0;
                while (leadingWhitespace < length &&
                       OMDIsInlineWhitespace([work characterAtIndex:leadingWhitespace])) {
                    leadingWhitespace += 1;
                }

                NSUInteger trailingWhitespace = 0;
                while (trailingWhitespace < length - leadingWhitespace &&
                       OMDIsInlineWhitespace([work characterAtIndex:(length - trailingWhitespace - 1)])) {
                    trailingWhitespace += 1;
                }

                NSUInteger coreLength = length - leadingWhitespace - trailingWhitespace;
                BOOL wrapped = NO;
                if (coreLength > 0) {
                    sawToggleEligibleLine = YES;
                    NSString *core = [work substringWithRange:NSMakeRange(leadingWhitespace, coreLength)];
                    wrapped = OMDInlineTextHasToggleWrapper(core, resolvedPrefix, resolvedSuffix);
                    if (!wrapped) {
                        allLinesWrapped = NO;
                    }
                }

                NSDictionary *meta = @{
                    @"line": work,
                    @"leading": [NSNumber numberWithUnsignedInteger:leadingWhitespace],
                    @"trailing": [NSNumber numberWithUnsignedInteger:trailingWhitespace],
                    @"coreLength": [NSNumber numberWithUnsignedInteger:coreLength],
                    @"wrapped": [NSNumber numberWithBool:wrapped]
                };
                [lineMetadata addObject:meta];
            }

            if (sawToggleEligibleLine) {
                NSMutableArray *updatedLines = [NSMutableArray arrayWithCapacity:[lineMetadata count]];
                NSEnumerator *lineEnum = [lineMetadata objectEnumerator];
                NSDictionary *meta = nil;
                while ((meta = [lineEnum nextObject]) != nil) {
                    NSString *line = [meta objectForKey:@"line"];
                    NSUInteger leadingWhitespace = [[meta objectForKey:@"leading"] unsignedIntegerValue];
                    NSUInteger trailingWhitespace = [[meta objectForKey:@"trailing"] unsignedIntegerValue];
                    NSUInteger coreLength = [[meta objectForKey:@"coreLength"] unsignedIntegerValue];
                    BOOL wrapped = [[meta objectForKey:@"wrapped"] boolValue];

                    if (coreLength == 0) {
                        [updatedLines addObject:line];
                        continue;
                    }

                    NSUInteger lineLength = [line length];
                    NSString *leading = [line substringToIndex:leadingWhitespace];
                    NSString *trailing = [line substringFromIndex:(lineLength - trailingWhitespace)];
                    NSString *core = [line substringWithRange:NSMakeRange(leadingWhitespace, coreLength)];
                    NSString *nextCore = core;

                    if (allLinesWrapped) {
                        if (wrapped && [core length] >= prefixLength + suffixLength) {
                            NSRange unwrapRange = NSMakeRange(prefixLength, [core length] - prefixLength - suffixLength);
                            nextCore = [core substringWithRange:unwrapRange];
                        }
                    } else if (!wrapped) {
                        nextCore = [NSString stringWithFormat:@"%@%@%@", resolvedPrefix, core, resolvedSuffix];
                    }

                    NSString *updatedLine = [NSString stringWithFormat:@"%@%@%@", leading, nextCore, trailing];
                    [updatedLines addObject:updatedLine];
                }

                NSString *replacement = [updatedLines componentsJoinedByString:@"\n"];
                NSRange nextSelection = NSMakeRange(selection.location, [replacement length]);
                [self replaceSourceTextInRange:selection withString:replacement selectedRange:nextSelection];
                return;
            }
        }

        // Toggle-off path 1: selection itself includes both wrappers.
        if (OMDInlineTextHasToggleWrapper(selectedText, resolvedPrefix, resolvedSuffix)) {
            NSRange unwrapRange = NSMakeRange(prefixLength, [selectedText length] - prefixLength - suffixLength);
            NSString *unwrapped = [selectedText substringWithRange:unwrapRange];
            NSRange nextSelection = NSMakeRange(selection.location, [unwrapped length]);
            [self replaceSourceTextInRange:selection withString:unwrapped selectedRange:nextSelection];
            return;
        }

        // Toggle-off path 2: selection is inside wrappers.
        BOOL hasWrappedBefore = selection.location >= prefixLength;
        BOOL hasWrappedAfter = (selection.location + selection.length + suffixLength) <= [source length];
        if (prefixLength > 0 &&
            suffixLength > 0 &&
            hasWrappedBefore &&
            hasWrappedAfter) {
            NSRange beforeRange = NSMakeRange(selection.location - prefixLength, prefixLength);
            NSRange afterRange = NSMakeRange(selection.location + selection.length, suffixLength);
            NSString *beforeText = [source substringWithRange:beforeRange];
            NSString *afterText = [source substringWithRange:afterRange];
            BOOL matchesSurroundingWrapper = [beforeText isEqualToString:resolvedPrefix] &&
                                             [afterText isEqualToString:resolvedSuffix];
            if (matchesSurroundingWrapper) {
                unichar token = 0;
                if (OMDInlineSingleCharacterWrapperToken(resolvedPrefix, resolvedSuffix, &token)) {
                    NSUInteger leftRun = 0;
                    while (selection.location > leftRun &&
                           [source characterAtIndex:(selection.location - leftRun - 1)] == token) {
                        leftRun += 1;
                    }
                    NSUInteger rightRun = 0;
                    NSUInteger rightStart = selection.location + selection.length;
                    while (rightStart + rightRun < [source length] &&
                           [source characterAtIndex:(rightStart + rightRun)] == token) {
                        rightRun += 1;
                    }
                    matchesSurroundingWrapper = ((leftRun % 2) == 1) && ((rightRun % 2) == 1);
                }
            }
            if (matchesSurroundingWrapper) {
                NSRange wrappedRange = NSMakeRange(selection.location - prefixLength,
                                                   selection.length + prefixLength + suffixLength);
                NSString *unwrapped = selectedText;
                NSRange nextSelection = NSMakeRange(wrappedRange.location, [unwrapped length]);
                [self replaceSourceTextInRange:wrappedRange withString:unwrapped selectedRange:nextSelection];
                return;
            }
        }
    }

    NSString *selectedText = @"";
    if (selection.length > 0) {
        selectedText = [source substringWithRange:selection];
    } else if (placeholder != nil) {
        selectedText = placeholder;
    }

    NSString *replacement = [NSString stringWithFormat:@"%@%@%@",
                                                       resolvedPrefix,
                                                       selectedText,
                                                       resolvedSuffix];
    NSRange nextSelection = NSMakeRange(selection.location + prefixLength, [selectedText length]);
    [self replaceSourceTextInRange:selection withString:replacement selectedRange:nextSelection];
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
    NSInteger index = [_formatHeadingPopup indexOfSelectedItem];
    [self applyHeadingLevel:index];
}

- (void)formattingCommandPressed:(id)sender
{
    NSInteger tag = [sender tag];
    if (_sourceTextView == nil || ![self isFormattingBarVisibleInCurrentMode]) {
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
    [self applyInlineWrapWithPrefix:@"*" suffix:@"*" placeholder:@"italic text"];
}

- (NSTextView *)activeEditingTextView
{
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
    _sourceIsDirty = YES;
    _sourceRevision += 1;
    [self updateWindowTitle];
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

    if ([self isImportableDocumentPath:resolvedPath]) {
        return [self importDocumentAtPath:resolvedPath];
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
        return NO;
    }

    [self setCurrentMarkdown:markdown sourcePath:resolvedPath];
    return YES;
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
    return [self confirmDiscardingUnsavedChangesForAction:@"closing"];
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
