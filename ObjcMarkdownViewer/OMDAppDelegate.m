// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDAppDelegate.h"
#import "OMMarkdownRenderer.h"
#import "OMRenderedObject.h"
#import "OMTheme.h"
#import "OMDTextView.h"
#import "OMDOutlineController.h"
#import "OMDSourceTextView.h"
#import "OMDSourceHighlighter.h"
#import "OMDLineNumberRulerView.h"
#import "OMDDocumentConverter.h"
#import "OMDCodeCopyButton.h"
#import "OMDControlSupport.h"
#import "OMDFormattingBarController.h"
#import "OMDPreviewSync.h"
#import "OMDViewerModeState.h"
#import "OMDInlineToggle.h"
#import "OMDPanelSelection.h"
#import "OMDViewerColors.h"
#import "OMDViewerDiagnostics.h"
#import "OMDWindowsMenuBar.h"
#import "OMDMainWindow.h"
#import "OMDFillViews.h"
#import "OMDToolbarViews.h"
#import "OMDPreferencesPopup.h"
#import "OMDWin11SplitView.h"
#import "OMDTextFileSupport.h"
#import "OMDExternalTools.h"
#import "OMDLayoutMetrics.h"
#import "OMDMainMenu.h"
#import "OMDToolbarController.h"
#import "OMDCopyButtonsController.h"
#import "OMDRenderScheduler.h"
#import "OMDPreviewTextUpdate.h"
#import "OMDViewerDefaults.h"
#import "OMDViewerImages.h"
#import "OMDDocumentTabsController.h"
#import "OMDExplorerController.h"
#import "OMDOpenLocationController.h"
#import "OMDRemoteDocument.h"
#import "OMDRemoteDocumentBar.h"
#import "OMDPreferencesController.h"
#import "GSVVimBindingController.h"
#import "GSVVimConfigLoader.h"
#if defined(_WIN32)
#import "GSOpenSave.h"
#endif
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

@interface GPStandardUpdaterController : NSObject
- (instancetype)initWithPackagedConfiguration:(NSError **)error;
- (void)setParentWindow:(NSWindow *)parentWindow;
- (void)start;
- (void)checkForUpdates:(id)sender;
@end

static const CGFloat OMDPrintExportZoomScale = 0.8;
static const NSTimeInterval OMDInteractiveRenderDebounceInterval = 0.15;
static const NSTimeInterval OMDZoomAdaptiveSamplingWindow = 0.35;
static const NSTimeInterval OMDPreviewStatusUpdatingDelayInterval = 0.30;
static const NSTimeInterval OMDPreviewStatusUpdatedDisplayInterval = 0.90;
static const NSTimeInterval OMDLinkedScrollDriverHoldInterval = 0.14;
static const NSTimeInterval OMDSourceSyntaxHighlightDebounceInterval = 0.08;
static const NSTimeInterval OMDSourceSyntaxHighlightLargeDocDebounceInterval = 0.16;
static const NSTimeInterval OMDRecoveryAutosaveDebounceInterval = 1.25;
static const NSTimeInterval OMDExternalFileMonitorInterval = 1.50;
static const NSUInteger OMDSourceSyntaxIncrementalThreshold = 120000;
static const NSUInteger OMDSourceSyntaxIncrementalContextChars = 12000;
static const CGFloat OMDSourceEditorDefaultFontSize = 13.0;
static const CGFloat OMDSourceEditorMinFontSize = 9.0;
static const CGFloat OMDSourceEditorMaxFontSize = 32.0;
static const CGFloat OMDUsableWindowWidthPadding = 96.0;
// The preview's text column: this many average characters of body text at
// the current zoom, unless the preview is set to use the full width.
static const CGFloat OMDPreviewReadableColumnCharacters = 80.0;
static const CGFloat OMDLinkedScrollViewportAnchor = 0.30;
static const CGFloat OMDLinkedScrollDeadband = 8.0;
static NSString * const OMDTextFileErrorDomain = @"OMDTextFileErrorDomain";

static NSUInteger OMDCountAttachmentsInAttributedString(NSAttributedString *attributedString)
{
    if (attributedString == nil) {
        return 0;
    }

    NSUInteger count = 0;
    NSUInteger length = [attributedString length];
    NSUInteger index = 0;
    while (index < length) {
        NSRange effectiveRange = NSMakeRange(0, 0);
        id value = [attributedString attribute:NSAttachmentAttributeName
                                       atIndex:index
                                effectiveRange:&effectiveRange];
        if (value != nil) {
            count += 1;
        }
        if (effectiveRange.length == 0) {
            index += 1;
        } else {
            index = NSMaxRange(effectiveRange);
        }
    }

    return count;
}

static void OMDApplyWindowsMenuToWindow(NSWindow *window)
{
    if (window == nil) {
        return;
    }

#if defined(_WIN32)
    if (YES) {
#else
    if (NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil) == NSWindows95InterfaceStyle) {
#endif
        NSMenu *mainMenu = [NSApp mainMenu];
        if (mainMenu != nil) {
            GSTheme *theme = [GSTheme theme];
            if ([theme respondsToSelector:@selector(setMenu:forWindow:)]) {
                [theme setMenu:mainMenu forWindow:window];
            } else {
                [window setMenu:mainMenu];
            }
            if ([theme respondsToSelector:@selector(updateMenu:forWindow:)]) {
                [theme updateMenu:mainMenu forWindow:window];
            }
#if defined(_WIN32)
            OMDInstallWinUIStyleWindowsMenuBar(window, mainMenu);
#endif
            OMDStartupTrace(@"windows-style menu applied to window");
        }
    }
}

static void OMDRefreshWindowsMainMenu(void)
{
#if defined(_WIN32)
    if (YES) {
#else
    if (NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil) == NSWindows95InterfaceStyle) {
#endif
        NSMenu *mainMenu = [NSApp mainMenu];
        if (mainMenu != nil) {
            [mainMenu update];
            if ([[GSTheme theme] respondsToSelector:@selector(updateAllWindowsWithMenu:)]) {
                [[GSTheme theme] updateAllWindowsWithMenu:mainMenu];
            }
#if defined(_WIN32)
            for (NSWindow *window in [NSApp windows]) {
                OMDInstallWinUIStyleWindowsMenuBar(window, mainMenu);
            }
#endif
            OMDStartupTrace(@"windows-style main menu refreshed");
        }
    }
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


typedef NS_ENUM(NSInteger, OMDDocumentRenderMode) {
    OMDDocumentRenderModeMarkdown = 0,
    OMDDocumentRenderModeVerbatim = 1
};

typedef NS_ENUM(NSInteger, OMDLinkedScrollDriver) {
    OMDLinkedScrollDriverNone = 0,
    OMDLinkedScrollDriverSource = 1,
    OMDLinkedScrollDriverPreview = 2
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

#if !defined(_WIN32)
// Only the non-Windows path uses it.
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
#endif

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


@interface OMDAppDelegate () <OMDCopyButtonsControllerDelegate, OMDRenderSchedulerDelegate, OMDDocumentTabsControllerDelegate, OMDToolbarControllerDelegate, OMDExplorerControllerDelegate, OMDOpenLocationDelegate, OMDFormattingBarControllerDelegate, OMDPreferencesControllerDelegate, GSVVimBindingControllerDelegate, OMDTextViewRenderedObjectDelegate, OMDOutlineControllerDelegate>
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
- (NSDictionary *)imageFingerprintsForMarkdown:(NSString *)markdown sourcePath:(NSString *)path;
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
- (void)presentWindowIfNeeded;
- (void)applyWindowsWindowIconsIfPossible;
- (void)layoutWorkspaceChrome;
- (void)documentTabsDidChange;
- (BOOL)isExplorerSidebarVisiblePreference;
- (void)setExplorerSidebarVisiblePreference:(BOOL)visible;
- (void)applyExplorerSidebarVisibility;
- (void)toggleExplorerSidebar:(id)sender;
- (void)filterExplorerFiles:(id)sender;
- (void)toggleOutline:(id)sender;
- (void)openLocalPath:(NSString *)path inNewTab:(BOOL)inNewTab;
- (BOOL)isMarkdownTextPath:(NSString *)path;
- (NSString *)temporaryPathForRemoteImportWithExtension:(NSString *)extension;
- (BOOL)ensureOpenFileSizeWithinLimit:(unsigned long long)size
                           descriptor:(NSString *)descriptor;
- (void)closeDocumentTabAtIndex:(NSInteger)index;
- (void)selectDocumentTabAtIndex:(NSInteger)index;
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
- (BOOL)canSaveCurrentDocument;
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
- (NSRect)currentPreviewClipBounds;
- (CGFloat)currentPreviewLayoutWidth;
- (void)clearPreviewPresentation;
- (void)updatePreviewDocumentGeometry;
- (void)mathArtifactsDidWarm:(NSNotification *)notification;
- (void)remoteImagesDidWarm:(NSNotification *)notification;
- (void)updateLinkedPreviewObject;
- (NSRect)layoutOutlinePanelInBounds:(NSRect)bounds;
- (void)refreshOutline;
- (NSArray *)outlineHeadings;
- (void)scheduleSourceOutlineRefresh;
- (void)updateOutlineCurrentHeading;
- (void)scrollToHeading:(NSDictionary *)heading;
- (BOOL)scrollToAnchor:(NSString *)anchor;
- (BOOL)followDocumentLink:(NSURL *)url;
- (void)openLocation:(id)sender;
- (void)openRemoteDocument:(OMDRemoteDocument *)document
                  inNewTab:(BOOL)inNewTab
                completion:(void (^)(NSString *errorMessage))completion;
- (void)openRemoteDocumentAfterLaunch:(OMDRemoteDocument *)document;
- (void)updateRemoteDocumentBar;
- (void)saveRemoteDocumentCopy:(id)sender;
- (void)openRemoteDocumentInBrowser:(id)sender;
- (void)modeControlChanged:(id)sender;
- (void)setReadMode:(id)sender;
- (void)setEditMode:(id)sender;
- (void)setSplitMode:(id)sender;
- (void)setViewerMode:(OMDViewerMode)mode persistPreference:(BOOL)persistPreference;
- (BOOL)isFormattingBarEnabledPreference;
- (void)setFormattingBarEnabledPreference:(BOOL)enabled;
- (BOOL)isFormattingBarVisibleInCurrentMode;
- (void)toggleFormattingBar:(id)sender;
- (BOOL)isPreviewFullWidth;
- (void)togglePreviewFullWidth:(id)sender;
- (NSColor *)previewPageBackgroundColor;
- (CGFloat)previewReadableColumnWidth;
- (OMDSplitSyncMode)currentSplitSyncMode;
- (void)setSplitSyncModePreference:(OMDSplitSyncMode)mode;
- (void)setSplitSyncModeUnlinked:(id)sender;
- (void)setSplitSyncModeLinkedScrolling:(id)sender;
- (void)setSplitSyncModeCaretSelectionFollow:(id)sender;
- (BOOL)usesLinkedScrolling;
- (BOOL)usesCaretSelectionSync;
- (void)applyViewerModeLayout;
- (void)layoutDocumentViews;
- (void)layoutSourceEditorContainer;
- (void)normalizeWindowFrameIfNeeded;
- (void)updateFormattingBarContextState;
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
- (void)applySplitViewRatio;
- (void)persistSplitViewRatio;
- (BOOL)isPreviewVisible;
- (void)updateWindowTitle;
- (NSColor *)modeLabelTextColor;
- (void)applySourceEditorFontFromDefaults;
- (void)setSourceEditorFont:(NSFont *)font persistPreference:(BOOL)persistPreference;
- (void)updateRendererParsingOptionsForSourcePath:(NSString *)sourcePath;
- (OMMarkdownMathRenderingPolicy)currentMathRenderingPolicy;
- (OMMarkdownDiagramRenderingPolicy)currentDiagramRenderingPolicy;
- (void)setDiagramRenderingPolicyPreference:(OMMarkdownDiagramRenderingPolicy)policy;
- (void)setDiagramRenderingNative:(id)sender;
- (void)setDiagramRenderingSourceCode:(id)sender;
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
- (NSString *)sourceEditorFontDescription;
- (BOOL)sourceEditorHasFocus;
- (void)setPreviewZoomScale:(CGFloat)scale;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)zoomToActualSize:(id)sender;
- (void)checkForUpdates:(id)sender;
- (void)showAboutPanel:(id)sender;
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshOutline) object:nil];
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
    [_renderScheduler cancelPendingInteractiveRender];
    [_renderScheduler cancelPendingMathArtifactRender];
    [_renderScheduler cancelPendingLivePreviewRender];
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
    [_copyButtonsController hideCopyFeedback];
    [_sourceVimCommandLine release];
    [_pendingLaunchOpenPath release];
    [_currentDocumentSyntaxLanguage release];
    [_currentDisplayTitle release];
    [_currentMarkdown release];
    [_currentPath release];
    [_currentLoadedDiskFingerprint release];
    [_currentObservedDiskFingerprint release];
    [_currentSuppressedDiskFingerprint release];
    [_documentTabsController release];
    [_explorerController release];
    [_openLocationController release];
    [_currentRemoteDocument release];
    [_remoteDocumentBar release];
    [_preferencesController release];
    [_toolbarController release];
    [_updaterController release];
    if (_fileOpenRecentMenu != nil) {
        [_fileOpenRecentMenu setDelegate:nil];
        [_fileOpenRecentMenu release];
    }
    [_launchOverlayTitleLabel release];
    [_launchOverlayDetailLabel release];
    [_launchOverlayView release];
    [_linkedScrollDriverResetTimer invalidate];
    [_linkedScrollDriverResetTimer release];
    [_formattingBarController release];
    [_sourceEditorContainer release];
    [_copyButtonsController release];
    [_renderScheduler release];
    [_documentConverter release];
    [_sourceVimBindingController release];
    [_sourceLineNumberRuler release];
    [_splitView release];
    [_workspaceSplitView release];
    [_workspaceMainContainer release];
    [_sidebarContainer release];
    [_renderer release];
    [_sourceTextView release];
    [_sourceScrollView release];
    [_previewScrollView release];
    [_previewCanvasView release];
    [_documentContainer release];
    [_outlineController setDelegate:nil];
    [_outlineController release];
    [_pendingLinkFragment release];
    [_textView release];
    [_window release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    OMDStartupTrace(@"appDidFinishLaunching: enter");
#if defined(_WIN32)
    // Ensure OpenSave is initialized and prefers native Win32 dialogs.
    // Elsewhere the GNUstep theme provides the open and save panels.
    GSOpenSaveSetMode(GSOpenSaveModeWin32);
    OMDStartupTrace(@"appDidFinishLaunching: open-save mode set");
#endif

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
    if (_updaterController == nil) {
        NSError *updateError = nil;
        GPStandardUpdaterController *controller = [[GPStandardUpdaterController alloc] initWithPackagedConfiguration:&updateError];
        if (controller == nil) {
            NSLog(@"Updater disabled: %@", [updateError localizedDescription]);
        } else {
            [controller setParentWindow:_window];
            [controller start];
            _updaterController = controller;
        }
    } else {
        [(GPStandardUpdaterController *)_updaterController setParentWindow:_window];
    }
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
    OMDRemoveRetiredDefaults();
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
    // A web address given on the command line.
    NSString *lowerName = [filename lowercaseString];
    if ([lowerName hasPrefix:@"https://"] || [lowerName hasPrefix:@"http://"] || [lowerName hasPrefix:@"github.com/"]) {
        OMDRemoteDocument *remote = [OMDRemoteDocument documentWithURLString:filename];
        if (remote != nil) {
            _openedFileOnLaunch = YES;
            [self performSelector:@selector(openRemoteDocumentAfterLaunch:) withObject:remote afterDelay:0.0];
            return YES;
        }
    }
    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:filename];
    _openedFileOnLaunch = YES;

    BOOL shouldDeferForLaunch = (_window == nil ||
                                 _launchWorkScheduled ||
                                 (!_postPresentationSetupComplete &&
                                  [_documentTabsController count] == 0 &&
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

    BOOL openInNewTab = !([_documentTabsController count] == 0 && _currentPath == nil && _currentMarkdown == nil);
    return [self openDocumentAtPath:(resolvedPath != nil ? resolvedPath : filename)
                           inNewTab:openInNewTab
                requireDirtyConfirm:!openInNewTab];
}

- (void)setupMainMenu
{
    OMDStartupTrace(@"setupMainMenu: enter");
    OMDMainMenu *mainMenu = [[[OMDMainMenu alloc] initWithTarget:self] autorelease];
    NSMenu *menubar = [mainMenu menubar];
    [_fileOpenRecentMenu release];
    _fileOpenRecentMenu = [[mainMenu openRecentMenu] retain];
#if !defined(_WIN32)
    [self rebuildOpenRecentMenu];
#endif

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
    _lastZoomSliderEventTime = 0.0;
    NSNumber *savedZoom = [[NSUserDefaults standardUserDefaults] objectForKey:@"ObjcMarkdownZoomScale"];
    if (savedZoom != nil) {
        double value = [savedZoom doubleValue];
        if (value > 0.25 && value < 4.0) {
            _zoomScale = value;
        }
    }
    _toolbarController = [[OMDToolbarController alloc] initWithDelegate:self];
    _copyButtonsController = [[OMDCopyButtonsController alloc] initWithDelegate:self];
    _renderScheduler = [[OMDRenderScheduler alloc] initWithDelegate:self];
    [_toolbarController installInWindow:_window];
    [self updateZoomLabel];
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
    [_previewScrollView setBackgroundColor:[self previewPageBackgroundColor]];

    _previewCanvasView = [[OMDPreviewCanvasView alloc] initWithFrame:[[_previewScrollView contentView] bounds]];
    [_previewCanvasView setAutoresizesSubviews:NO];
    if ([_previewCanvasView isKindOfClass:[OMDFlippedFillView class]]) {
        [(OMDFlippedFillView *)_previewCanvasView setFillColor:[self previewPageBackgroundColor]];
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
        // No card: the whole pane is the page (see -previewPageBackgroundColor).
        [previewTextView setDocumentBackgroundColor:nil];
        [previewTextView setDocumentBorderColor:nil];
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
    [_formattingBarController setupInContainer:_sourceEditorContainer];
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
    NSBox *launchCard = [[[NSBox alloc]
        initWithFrame:NSMakeRect(floor((NSWidth(overlayBounds) - cardWidth) * 0.5),
                                 floor((NSHeight(overlayBounds) - cardHeight) * 0.5),
                                 cardWidth,
                                 cardHeight)] autorelease];
    [launchCard setAutoresizingMask:(NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin)];
    [launchCard setTitlePosition:NSNoTitle];
    [launchCard setBorderType:NSLineBorder];
    [launchCard setContentViewMargins:NSZeroSize];

    _launchOverlayTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(22.0, 58.0, cardWidth - 44.0, 24.0)];
    [_launchOverlayTitleLabel setBezeled:NO];
    [_launchOverlayTitleLabel setEditable:NO];
    [_launchOverlayTitleLabel setSelectable:NO];
    [_launchOverlayTitleLabel setDrawsBackground:NO];
    [_launchOverlayTitleLabel setAlignment:NSCenterTextAlignment];
    [_launchOverlayTitleLabel setFont:[NSFont boldSystemFontOfSize:16.0]];
    [_launchOverlayTitleLabel setStringValue:@"Loading document..."];
    [[launchCard contentView] addSubview:_launchOverlayTitleLabel];

    _launchOverlayDetailLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(22.0, 30.0, cardWidth - 44.0, 20.0)];
    [_launchOverlayDetailLabel setBezeled:NO];
    [_launchOverlayDetailLabel setEditable:NO];
    [_launchOverlayDetailLabel setSelectable:NO];
    [_launchOverlayDetailLabel setDrawsBackground:NO];
    [_launchOverlayDetailLabel setAlignment:NSCenterTextAlignment];
    [_launchOverlayDetailLabel setTextColor:[NSColor disabledControlTextColor]];
    [_launchOverlayDetailLabel setFont:[NSFont systemFontOfSize:12.0]];
    [_launchOverlayDetailLabel setStringValue:@""];
    [[launchCard contentView] addSubview:_launchOverlayDetailLabel];

    [_launchOverlayView addSubview:launchCard];
    [_documentContainer addSubview:_launchOverlayView];

    [self applyExplorerSidebarVisibility];

    _renderer = [[OMMarkdownRenderer alloc] init];
    // The preview follows the desktop's light or dark appearance; printing
    // keeps its own light renderer.
    [_renderer setTheme:[OMTheme defaultThemeForDarkAppearance:OMDSystemAppearanceIsDark()]];
    OMDStartupTrace(@"setupWindow: renderer allocated");
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    id mathPolicyValue = [defaults objectForKey:OMDMathRenderingPolicyDefaultsKey];
    if ([mathPolicyValue respondsToSelector:@selector(integerValue)]) {
        [options setMathRenderingPolicy:OMDMathRenderingPolicyFromInteger([mathPolicyValue integerValue])];
    } else {
#if defined(_WIN32)
        if (OMDWindowsBundledExternalMathToolchainAvailable()) {
            [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyExternalTools];
            [defaults setInteger:(NSInteger)OMMarkdownMathRenderingPolicyExternalTools
                          forKey:OMDMathRenderingPolicyDefaultsKey];
            [defaults synchronize];
            OMDStartupTrace(@"setupWindow: defaulted math policy to external tools");
        } else {
            [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
            OMDStartupTrace(@"setupWindow: defaulted math policy to styled text");
        }
#else
        [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
#endif
    }
    id diagramPolicyValue = [defaults objectForKey:OMDDiagramRenderingPolicyDefaultsKey];
    if ([diagramPolicyValue respondsToSelector:@selector(integerValue)]) {
        [options setDiagramRenderingPolicy:
            OMDDiagramRenderingPolicyFromInteger([diagramPolicyValue integerValue])];
    } else {
        [options setDiagramRenderingPolicy:OMMarkdownDiagramRenderingPolicyNative];
    }

    OMDStartupTrace([NSString stringWithFormat:@"setupWindow: math policy=%ld",
                                               (long)[options mathRenderingPolicy]]);
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
#if defined(_WIN32)
    // Windows GNUstep should render external math attachments on first paint
    // instead of relying on background warmup callbacks.
    [_renderer setAsynchronousMathGenerationEnabled:NO];
#else
    [_renderer setAsynchronousMathGenerationEnabled:YES];
#endif
    [_renderer setAllowTableHorizontalOverflow:NO];
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
    [_documentTabsController updateTabStrip];
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

    [_explorerController reloadExplorerEntries];
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

    _documentTabsController = [[OMDDocumentTabsController alloc] initWithDelegate:self];
    [_workspaceMainContainer addSubview:[_documentTabsController stripView]];

    _documentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    [_documentContainer setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_workspaceMainContainer addSubview:_documentContainer];

    _outlineController = [[OMDOutlineController alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 400.0)];
    [_outlineController setDelegate:self];
    _outlineVisible = [[NSUserDefaults standardUserDefaults] boolForKey:OMDOutlineVisibleDefaultsKey];

    _currentDocumentRenderMode = OMDDocumentRenderModeMarkdown;
    _explorerController = [[OMDExplorerController alloc] initWithDelegate:self];
    _preferencesController = [[OMDPreferencesController alloc] initWithDelegate:self];
    _formattingBarController = [[OMDFormattingBarController alloc] initWithDelegate:self];
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
    [_explorerController setupInContainer:_sidebarContainer];
}

- (void)layoutWorkspaceChrome
{
    NSView *tabStripView = [_documentTabsController stripView];
    if (_workspaceMainContainer == nil || _documentContainer == nil || tabStripView == nil) {
        return;
    }

    NSRect bounds = [_workspaceMainContainer bounds];
    CGFloat tabHeight = [_documentTabsController currentTabStripHeight];
    if (tabHeight > NSHeight(bounds)) {
        tabHeight = NSHeight(bounds);
    }
    BOOL tabStripVisible = (tabHeight > 0.0);
    [tabStripView setHidden:!tabStripVisible];
    if (tabStripVisible) {
        NSRect tabFrame = NSMakeRect(NSMinX(bounds),
                                     NSMaxY(bounds) - tabHeight,
                                     NSWidth(bounds),
                                     tabHeight);
        [tabStripView setFrame:NSIntegralRect(tabFrame)];
    } else {
        [tabStripView setFrame:NSZeroRect];
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
    [_documentTabsController updateTabStrip];
}

// After a tab is added or closed: the strip shows only with two or more
// tabs, so lay the workspace out again when that changes.
- (void)documentTabsDidChange
{
    BOOL stripShouldShow = ([_documentTabsController currentTabStripHeight] > 0.0);
    if ([[_documentTabsController stripView] isHidden] == stripShouldShow) {
        [self layoutWorkspaceChrome];
    } else {
        [_documentTabsController updateTabStrip];
    }
}

- (BOOL)isExplorerSidebarVisiblePreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:OMDExplorerSidebarVisibleDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return NO;
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
        // Hidden, it takes no room: the document fills the width. Only the
        // frames: a full -adjustSubviews here, during setup, made the
        // AppImage exit at launch in CI (libs-gui 549f639).
        OMDWin11SplitView *workspaceSplitView = (OMDWin11SplitView *)_workspaceSplitView;
        [workspaceSplitView omdSnapSubviewsToPixels];
        [workspaceSplitView omdRebuildDividerTrackingRects];
    }

    [self layoutWorkspaceChrome];
}

- (void)toggleOutline:(id)sender
{
    (void)sender;
    _outlineVisible = !_outlineVisible;
    [[NSUserDefaults standardUserDefaults] setBool:_outlineVisible forKey:OMDOutlineVisibleDefaultsKey];
    [self layoutDocumentViews];
    [self refreshOutline];
}

- (void)toggleExplorerSidebar:(id)sender
{
    (void)sender;
    _explorerSidebarVisible = !_explorerSidebarVisible;
    [self setExplorerSidebarVisiblePreference:_explorerSidebarVisible];
    [self applyExplorerSidebarVisibility];
}

// Shows the explorer if it is hidden and puts the keyboard in its filter.
- (void)filterExplorerFiles:(id)sender
{
    if (!_explorerSidebarVisible) {
        [self toggleExplorerSidebar:sender];
    }
    [_explorerController focusFilterField];
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

// The menu item for action anywhere in menu, or nil.
static NSMenuItem *OMDMenuItemWithAction(NSMenu *menu, SEL action)
{
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == action) {
            return item;
        }
        NSMenuItem *found = [item hasSubmenu] ? OMDMenuItemWithAction([item submenu], action) : nil;
        if (found != nil) {
            return found;
        }
    }
    return nil;
}

- (void)updateZoomLabel
{
    NSTextField *zoomLabel = [_toolbarController zoomLabel];
    NSInteger percent = (NSInteger)lrint(_zoomScale * 100.0);
    // Without the toolbar's zoom controls, the menu says what the zoom is.
    NSMenuItem *actualSize = OMDMenuItemWithAction([NSApp mainMenu], @selector(zoomToActualSize:));
    if (actualSize != nil) {
        [actualSize setTitle:(percent == 100 ? @"Actual Size"
                                             : [NSString stringWithFormat:@"Actual Size (now %ld%%)", (long)percent])];
    }
    if (zoomLabel == nil) {
        return;
    }
    [zoomLabel setStringValue:[NSString stringWithFormat:@"%ld%%", (long)percent]];
}

- (BOOL)canSaveCurrentDocument
{
    return ([self hasLoadedDocument] && _sourceIsDirty);
}

- (void)zoomSliderChanged:(id)sender
{
    NSSlider *zoomSlider = [_toolbarController zoomSlider];
    _zoomScale = [zoomSlider doubleValue] / 100.0;
    [[NSUserDefaults standardUserDefaults] setDouble:_zoomScale forKey:@"ObjcMarkdownZoomScale"];
    [self updateZoomLabel];
    _lastZoomSliderEventTime = OMDNow();
    if ([_renderScheduler zoomUsesDebouncedRendering]) {
        [self requestInteractiveRender];
        return;
    }
    [_renderScheduler cancelPendingInteractiveRender];
    [self renderCurrentMarkdown];
}

- (void)zoomReset:(id)sender
{
    NSSlider *zoomSlider = [_toolbarController zoomSlider];
    _zoomScale = 1.0;
    [[NSUserDefaults standardUserDefaults] setDouble:_zoomScale forKey:@"ObjcMarkdownZoomScale"];
    [zoomSlider setDoubleValue:100.0];
    [self updateZoomLabel];
    _lastZoomSliderEventTime = OMDNow();
    [_renderScheduler cancelPendingInteractiveRender];
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

    if (action == @selector(toggleOutline:)) {
        [menuItem setState:(_outlineVisible ? NSOnState : NSOffState)];
        return [self hasLoadedDocument];
    }

    if (action == @selector(checkForUpdates:)) {
        return _updaterController != nil;
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

    if (action == @selector(setDiagramRenderingNative:) ||
        action == @selector(setDiagramRenderingSourceCode:)) {
        OMMarkdownDiagramRenderingPolicy policy = [self currentDiagramRenderingPolicy];
        OMMarkdownDiagramRenderingPolicy itemPolicy =
            (action == @selector(setDiagramRenderingNative:))
                ? OMMarkdownDiagramRenderingPolicyNative
                : OMMarkdownDiagramRenderingPolicySourceCode;
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

    if (action == @selector(togglePreviewFullWidth:)) {
        [menuItem setState:([self isPreviewFullWidth] ? NSOnState : NSOffState)];
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
            return [self isCurrentDocumentReloadableFromDisk];
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

// Replaces the items of menu with the recent documents and Clear Menu.
- (void)fillRecentDocumentsMenu:(NSMenu *)menu
{
    if (menu == nil) {
        return;
    }

    while ([menu numberOfItems] > 0) {
        [menu removeItemAtIndex:0];
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
        [menu addItem:item];
        addedCount += 1;
    }

    if (addedCount == 0) {
        NSMenuItem *empty = [[[NSMenuItem alloc] initWithTitle:@"No Recent Documents"
                                                         action:NULL
                                                  keyEquivalent:@""] autorelease];
        [empty setEnabled:NO];
        [menu addItem:empty];
        return;
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clearItem = [[[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                                         action:@selector(clearRecentDocumentsMenu:)
                                                  keyEquivalent:@""] autorelease];
    [clearItem setTarget:self];
    [menu addItem:clearItem];
}

- (void)rebuildOpenRecentMenu
{
    [self fillRecentDocumentsMenu:_fileOpenRecentMenu];
}

// A menu of the recent documents, for the toolbar's Open Recent button.
- (NSMenu *)recentDocumentsMenu
{
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Open Recent"] autorelease];
    [menu setAutoenablesItems:NO];
    [self fillRecentDocumentsMenu:menu];
    return menu;
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

    BOOL openInNewTab = !([_documentTabsController count] == 0 && _currentPath == nil && _currentMarkdown == nil);
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
    BOOL openInNewTab = !([_documentTabsController count] == 0 && _currentPath == nil && _currentMarkdown == nil);
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

    if ([_documentTabsController count] == 0 && _currentPath == nil && _currentMarkdown == nil) {
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
    return YES;
}

- (NSDictionary *)imageFingerprintsForMarkdown:(NSString *)markdown sourcePath:(NSString *)path
{
    NSString *resolvedPath = [self resolvedAbsolutePathForLocalPath:path];
    if ([resolvedPath length] == 0) {
        return [NSDictionary dictionary];
    }
    NSURL *baseURL = [NSURL fileURLWithPath:[resolvedPath stringByDeletingLastPathComponent] isDirectory:YES];
    NSMutableDictionary *fingerprints = [NSMutableDictionary dictionary];
    for (NSURL *url in [OMMarkdownRenderer localImageURLsInMarkdown:markdown baseURL:baseURL]) {
        NSString *imagePath = [[url path] stringByStandardizingPath];
        [fingerprints setObject:([self diskFingerprintForPath:imagePath] ?: @"missing") forKey:imagePath];
    }
    return fingerprints;
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
    if ([_currentPath length] > 0) {
        // Saved (a copy) or another local document: no longer from the web.
        [_currentRemoteDocument release];
        _currentRemoteDocument = nil;
    }
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

    NSMutableDictionary *tab = [_documentTabsController selectedTab];
    NSMutableDictionary *loadedImages = [[[tab objectForKey:OMDTabImageFingerprintsKey] mutableCopy] autorelease];
    if (loadedImages == nil) {
        loadedImages = [NSMutableDictionary dictionary];
    }
    NSDictionary *images = nil;
    if ([_currentMarkdown isEqual:[tab objectForKey:OMDTabImageMarkdownKey]] &&
        [_currentPath isEqual:[tab objectForKey:OMDTabImageSourcePathKey]]) {
        // Poll file metadata without reparsing unchanged Markdown on every tick.
        NSMutableDictionary *observedImages = [NSMutableDictionary dictionary];
        for (NSString *path in loadedImages) {
            [observedImages setObject:([self diskFingerprintForPath:path] ?: @"missing") forKey:path];
        }
        images = observedImages;
    } else {
        images = (_currentDocumentRenderMode == OMDDocumentRenderModeMarkdown
                  ? [self imageFingerprintsForMarkdown:_currentMarkdown sourcePath:_currentPath]
                  : [NSDictionary dictionary]);
        [tab setObject:(_currentMarkdown ?: @"") forKey:OMDTabImageMarkdownKey];
        [tab setObject:(_currentPath ?: @"") forKey:OMDTabImageSourcePathKey];
    }
    // Editing references establishes a baseline for new paths; it is not a disk change.
    for (NSString *path in [loadedImages allKeys]) {
        if ([images objectForKey:path] == nil) {
            [loadedImages removeObjectForKey:path];
        }
    }
    for (NSString *path in images) {
        if ([loadedImages objectForKey:path] == nil) {
            [loadedImages setObject:[images objectForKey:path] forKey:path];
        }
    }
    [tab setObject:loadedImages forKey:OMDTabImageFingerprintsKey];
    BOOL imagesChanged = ![loadedImages isEqual:images];
    if (!imagesChanged) {
        [tab removeObjectForKey:OMDTabSuppressedImageFingerprintsKey];
    }

    if (!allowPrompt || _externalReloadPromptVisible) {
        return;
    }
    if (_window == nil || ![_window isVisible] || ![_window isKeyWindow]) {
        return;
    }
    if (NSApp != nil && ![NSApp isActive]) {
        return;
    }
    BOOL documentChanged = [self currentDocumentHasNewerDiskVersion];
    if (!documentChanged && !imagesChanged) {
        return;
    }
    if ((!documentChanged || [_currentObservedDiskFingerprint isEqualToString:_currentSuppressedDiskFingerprint]) &&
        (!imagesChanged || [images isEqual:[tab objectForKey:OMDTabSuppressedImageFingerprintsKey]])) {
        return;
    }

    NSString *documentName = (_currentPath != nil ? [_currentPath lastPathComponent] : @"Untitled");
    NSString *changeDescription = (imagesChanged
                                  ? [NSString stringWithFormat:@"Referenced images in \"%@\"%@ changed on disk.",
                                     documentName, documentChanged ? @" and the document itself" : @""]
                                  : [NSString stringWithFormat:@"\"%@\" changed on disk.", documentName]);
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Reload from disk?"];
    if (_sourceIsDirty) {
        [alert setInformativeText:[NSString stringWithFormat:@"%@ Reloading discards your unsaved changes in this window. Keep stops prompts until another disk change.",
                                                             changeDescription]];
    } else {
        [alert setInformativeText:[NSString stringWithFormat:@"%@ Keep stops prompts until another disk change.",
                                                             changeDescription]];
    }
    [alert addButtonWithTitle:@"Reload"];
    [alert addButtonWithTitle:@"Keep"];

    _externalReloadPromptVisible = YES;
    NSInteger buttonIndex = OMDAlertButtonIndexForResponse([alert runModal]);
    _externalReloadPromptVisible = NO;

    if (buttonIndex == 0) {
        if (![self reloadCurrentDocumentFromDiskPreservingViewport]) {
            [tab setObject:images forKey:OMDTabSuppressedImageFingerprintsKey];
            [self setCurrentDiskFingerprintStateLoaded:_currentLoadedDiskFingerprint
                                              observed:_currentObservedDiskFingerprint
                                            suppressed:_currentObservedDiskFingerprint];
            [self captureCurrentStateIntoSelectedTab];
        }
    } else {
        [tab setObject:images forKey:OMDTabSuppressedImageFingerprintsKey];
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
    if (![self ensureDocumentLoadedForActionName:@"Refresh"]) {
        return;
    }

    if (![self isCurrentDocumentReloadableFromDisk]) {
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
    [_documentTabsController updateTabStrip];
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
    [_documentTabsController updateTabStrip];
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
    [alert setInformativeText:@"Reloading from disk will discard your unsaved changes in this window."];
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
    BOOL exported = [converter exportMarkdown:markdown
                                       toPath:fragmentPath
                            resourceDirectory:[_currentPath stringByDeletingLastPathComponent]
                                        error:&error];
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
                                          resourceDirectory:[_currentPath stringByDeletingLastPathComponent]
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
    [_renderScheduler cancelPendingInteractiveRender];
    [_renderScheduler cancelPendingMathArtifactRender];
    [_renderScheduler cancelPendingLivePreviewRender];
    [_renderer setZoomScale:_zoomScale];
    [self updateRendererLayoutWidth];
    NSTimeInterval markdownStart = perfLogging ? OMDNow() : 0.0;
    NSAttributedString *rendered = [_renderer attributedStringFromMarkdown:previewMarkdown];
    OMDStartupTrace([NSString stringWithFormat:@"renderCurrentMarkdown: policy=%ld attachments=%lu renderedLength=%lu markdownLength=%lu",
                                               (long)[self currentMathRenderingPolicy],
                                               (unsigned long)OMDCountAttachmentsInAttributedString(rendered),
                                               (unsigned long)(rendered != nil ? [rendered length] : 0),
                                               (unsigned long)[previewMarkdown length]]);
    NSTimeInterval markdownMs = perfLogging ? ((OMDNow() - markdownStart) * 1000.0) : 0.0;
    NSTimeInterval applyStart = perfLogging ? OMDNow() : 0.0;
    // Only the part that changed is replaced, so the layout manager keeps
    // the layout of the rest.
    _isProgrammaticPreviewUpdate = YES;
    OMDApplyRenderedString([_textView textStorage], rendered);
    _isProgrammaticPreviewUpdate = NO;
    [self logPreviewStyleDiagnosticsForRenderedString:rendered];
    NSTimeInterval applyMs = perfLogging ? ((OMDNow() - applyStart) * 1000.0) : 0.0;
    [self updatePreviewDocumentGeometry];
    NSTimeInterval postStart = perfLogging ? OMDNow() : 0.0;
    [_copyButtonsController updateCodeBlockButtons];
    if ([_textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *codeView = (OMDTextView *)_textView;
        [codeView setDocumentBackgroundColor:nil];
        [codeView setDocumentBorderColor:nil];
        [codeView setCodeBlockRanges:[_renderer codeBlockRanges]];
        OMTheme *theme = [_renderer theme];
        [codeView setCodeBlockBackgroundColor:(theme.codeBackgroundColor != nil
                                               ? theme.codeBackgroundColor
                                               : [NSColor colorWithCalibratedRed:(239.0 / 255.0) green:(243.0 / 255.0) blue:(247.0 / 255.0) alpha:1.0])];
        [codeView setCodeBlockBorderColor:(theme.codeBorderColor != nil
                                           ? theme.codeBorderColor
                                           : [NSColor colorWithCalibratedRed:(208.0 / 255.0) green:(215.0 / 255.0) blue:(222.0 / 255.0) alpha:1.0])];
        if (theme.linkColor != nil) {
            [codeView setLinkTextAttributes:@{
                NSForegroundColorAttributeName: theme.linkColor,
                NSUnderlineStyleAttributeName: [NSNumber numberWithInt:NSUnderlineStyleSingle]
            }];
        }
        [codeView setCodeBlockPadding:NSMakeSize(20.0, 14.0)];
        [codeView setCodeBlockCornerRadius:6.0];
        [codeView setCodeBlockBorderWidth:1.0];
        [codeView setBlockquoteRanges:[_renderer blockquoteRanges]];
        [codeView setBlockquoteLineColor:(theme.blockquoteBorderColor != nil
                                          ? theme.blockquoteBorderColor
                                          : [NSColor colorWithCalibratedWhite:0.82 alpha:1.0])];
        [codeView setBlockquoteLineWidth:3.0];
        [codeView setNeedsDisplay:YES];
    }
    [_textView setDrawsBackground:NO];
    [_previewScrollView setDrawsBackground:YES];
    [_previewScrollView setBackgroundColor:[self previewPageBackgroundColor]];
    if ([_previewCanvasView isKindOfClass:[OMDFlippedFillView class]]) {
        [(OMDFlippedFillView *)_previewCanvasView setFillColor:[self previewPageBackgroundColor]];
        [_previewCanvasView setNeedsDisplay:YES];
    }
    _lastRenderedSourceRevision = revisionAtRenderStart;
    if (_viewerMode == OMDViewerModeSplit) {
        [self syncPreviewToSourceInteractionAnchor];
    }
    [self updatePreviewStatusIndicator];
    [self updateWindowTitle];
    if (_viewerMode == OMDViewerModeSplit && _sourceRevision > _lastRenderedSourceRevision) {
        [_renderScheduler scheduleLivePreviewRender];
    } else {
        [self setPreviewUpdating:NO];
    }
    NSTimeInterval totalMs = (OMDNow() - renderStart) * 1000.0;
    [_renderScheduler updateAdaptiveZoomDebounceWithRenderDurationMs:totalMs sampledAsZoomRender:sampledAsZoomRender];
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

    [_copyButtonsController hideCopyFeedback];
    [_copyButtonsController removeCopyButtons];

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
    [_previewScrollView setBackgroundColor:[self previewPageBackgroundColor]];
    if ([_previewCanvasView isKindOfClass:[OMDFlippedFillView class]]) {
        [(OMDFlippedFillView *)_previewCanvasView setFillColor:[self previewPageBackgroundColor]];
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
    [_copyButtonsController updateCodeBlockButtons];
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
    [_renderScheduler scheduleInteractiveRenderAfterDelay:OMDInteractiveRenderDebounceInterval];
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
    if (![self isPreviewFullWidth]) {
        CGFloat readable = [self previewReadableColumnWidth];
        if (readable > 0.0 && width > readable) {
            width = readable;
        }
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
            [(OMDFlippedFillView *)_previewCanvasView setFillColor:[self previewPageBackgroundColor]];
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

- (void)mathArtifactsDidWarm:(NSNotification *)notification
{
    if (_currentMarkdown == nil) {
        return;
    }
    if (![self isPreviewVisible]) {
        return;
    }
    [_renderScheduler scheduleMathArtifactRefresh];
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

- (void)modeControlChanged:(id)sender
{
    NSSegmentedControl *modeControl = [_toolbarController modeControl];
    NSInteger selectedSegment = [modeControl selectedSegment];
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
    [_preferencesController syncPreferencesPanelFromSettings];
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

- (BOOL)isPreviewFullWidth
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:OMDPreviewFullWidthDefaultsKey];
}

- (void)togglePreviewFullWidth:(id)sender
{
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:![self isPreviewFullWidth] forKey:OMDPreviewFullWidthDefaultsKey];
    if ([self isPreviewVisible]) {
        _lastRenderedLayoutWidth = -1.0;
        [self requestInteractiveRender];
    }
}

// The document's own background, filling the whole preview pane: the text
// sits on it directly rather than on a card.
- (NSColor *)previewPageBackgroundColor
{
    NSColor *background = [_renderer backgroundColor];
    if (background != nil) {
        return background;
    }
    return OMDSystemAppearanceIsDark()
        ? [NSColor colorWithCalibratedRed:(13.0 / 255.0) green:(17.0 / 255.0) blue:(23.0 / 255.0) alpha:1.0]
        : [NSColor whiteColor];
}

// About OMDPreviewReadableColumnCharacters of body text at the current zoom.
- (CGFloat)previewReadableColumnWidth
{
    NSFont *base = [[_renderer theme] baseFont];
    CGFloat size = (base != nil ? [base pointSize] : 16.0) * (_zoomScale > 0.0 ? _zoomScale : 1.0);
    NSFont *font = base != nil ? [NSFont fontWithName:[base fontName] size:size] : nil;
    if (font == nil) {
        font = [NSFont userFontOfSize:size];
    }
    NSString *sample = @"The quick brown fox jumps over the lazy dog, 1234567890.";
    CGFloat sampleWidth = [sample sizeWithAttributes:[NSDictionary dictionaryWithObject:font
                                                                                 forKey:NSFontAttributeName]].width;
    CGFloat average = sampleWidth > 0.0 ? sampleWidth / [sample length] : size * 0.5;
    return ceil(average * OMDPreviewReadableColumnCharacters);
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
    NSView *barView = [_formattingBarController barView];
    if (showBar) {
        if (barView != nil) {
            barHeight = [_formattingBarController layoutFormattingBarControlsForWidth:NSWidth(bounds)
                                                                          applyFrames:NO];
        } else {
            barHeight = metrics.formattingBarHeight;
        }
    }

    if (barView != nil) {
        [barView setHidden:!showBar];
        if (showBar) {
            NSRect barFrame = NSMakeRect(NSMinX(bounds),
                                         NSMaxY(bounds) - barHeight,
                                         NSWidth(bounds),
                                         barHeight);
            [barView setFrame:NSIntegralRect(barFrame)];
            // Place the controls after resizing the bar: their autoresizing
            // would otherwise shift them out of view.
            [_formattingBarController layoutFormattingBarControlsForWidth:NSWidth(bounds)
                                                              applyFrames:YES];
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
    [_formattingBarController setControlsEnabled:enabled];

    if (!enabled || [_formattingBarController barView] == nil || _sourceTextView == nil) {
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
    [_formattingBarController selectHeadingLevel:level];
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
        [self refreshOutline];
    }

    if (_viewerMode == OMDViewerModeEdit) {
        [_renderScheduler cancelPendingInteractiveRender];
        [_renderScheduler cancelPendingMathArtifactRender];
        [_renderScheduler cancelPendingLivePreviewRender];
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
    [self updateLinkedPreviewObject];
}

- (void)applyViewerModeLayout
{
    [self layoutDocumentViews];
}

// Places the outline panel at the right of the document area when shown,
// and returns the rest of the area for the preview and editor.
- (NSRect)layoutOutlinePanelInBounds:(NSRect)bounds
{
    NSView *panel = [_outlineController view];
    if (panel == nil) {
        return bounds;
    }
    CGFloat width = floor(MIN(260.0, MAX(180.0, NSWidth(bounds) * 0.24)));
    if (!_outlineVisible || ![self hasLoadedDocument] || NSWidth(bounds) - width < 320.0) {
        [panel removeFromSuperview];
        return bounds;
    }
    if ([panel superview] != _documentContainer) {
        [_documentContainer addSubview:panel];
    }
    [panel setFrame:NSMakeRect(NSMaxX(bounds) - width, NSMinY(bounds), width, NSHeight(bounds))];
    NSRect rest = bounds;
    rest.size.width -= width;
    return rest;
}

- (void)layoutDocumentViews
{
    if (_documentContainer == nil) {
        return;
    }

    NSRect bounds = [self layoutOutlinePanelInBounds:[_documentContainer bounds]];
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode((OMDViewerMode)_viewerMode);
    if (_remoteDocumentBar != nil && ![_remoteDocumentBar isHidden]) {
        OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([self effectiveLayoutDensityMode]);
        CGFloat barHeight = [OMDRemoteDocumentBar heightForControlHeight:metrics.explorerControlHeight];
        [_remoteDocumentBar setFrame:NSMakeRect(NSMinX(bounds), NSMaxY(bounds) - barHeight,
                                                NSWidth(bounds), barHeight)];
        bounds.size.height = MAX(0.0, NSHeight(bounds) - barHeight);
    }

    if (!layout.splitVisible && layout.previewVisible) {
        [_splitView removeFromSuperview];
        [_previewScrollView removeFromSuperview];
        [_sourceEditorContainer removeFromSuperview];
        [_previewScrollView setHidden:NO];
        [_sourceEditorContainer setHidden:YES];
        [_documentContainer addSubview:_previewScrollView];
        [_previewScrollView setFrame:bounds];
        [self updatePreviewDocumentGeometry];
        [_copyButtonsController updateCodeBlockButtons];
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
    // The panes come back with the frames another mode left them (the
    // preview as wide as the whole area), so the first pass shares the width
    // out wrongly: don't keep that as the user's split ratio.
    BOOL wasApplying = _isApplyingSplitViewRatio;
    _isApplyingSplitViewRatio = YES;
    [_splitView adjustSubviews];
    [self applySplitViewRatio];
    [_splitView adjustSubviews];
    _isApplyingSplitViewRatio = wasApplying;
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
        [_toolbarController updateToolbarActionControlsState];
        return;
    }

    BOOL editable = !_currentDocumentReadOnly;
    [_sourceTextView setEditable:editable];
    [_sourceTextView setSelectable:YES];
    [self updateFormattingBarContextState];
    [_toolbarController updateToolbarActionControlsState];
}

- (void)closeDocumentTabAtIndex:(NSInteger)index
{
    NSInteger count = (NSInteger)[_documentTabsController count];
    if (index < 0 || index >= count) {
        return;
    }

    [self captureCurrentStateIntoSelectedTab];

    NSDictionary *tabRecord = [_documentTabsController tabAtIndex:index];
    BOOL tabIsDirty = [[tabRecord objectForKey:OMDTabDirtyKey] boolValue];
    NSInteger previousSelection = [_documentTabsController selectedIndex];
    BOOL switchedToClosingTab = NO;

    if (tabIsDirty && index != [_documentTabsController selectedIndex]) {
        [self selectDocumentTabAtIndex:index];
        switchedToClosingTab = YES;
    }

    if (tabIsDirty) {
        if (![self confirmDiscardingUnsavedChangesForAction:@"closing this tab"]) {
            if (switchedToClosingTab &&
                previousSelection >= 0 &&
                previousSelection < (NSInteger)[_documentTabsController count]) {
                [self selectDocumentTabAtIndex:previousSelection];
            }
            return;
        }
        [self captureCurrentStateIntoSelectedTab];
    }

    if (index < 0 || index >= (NSInteger)[_documentTabsController count]) {
        return;
    }
    [_documentTabsController removeTabAtIndex:index];

    if ([_documentTabsController count] == 0) {
        [_documentTabsController setSelectedIndex:-1];
        [self setCurrentMarkdown:nil sourcePath:nil];
        [self clearRecoverySnapshot];
        [self documentTabsDidChange];
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

    NSInteger remainingCount = (NSInteger)[_documentTabsController count];
    if (targetSelection >= remainingCount) {
        targetSelection = remainingCount - 1;
    }
    if (targetSelection < 0) {
        targetSelection = 0;
    }

    [_documentTabsController setSelectedIndex:targetSelection];
    NSDictionary *selectedTab = [_documentTabsController tabAtIndex:targetSelection];
    [self applyDocumentTabRecord:selectedTab];
    [self documentTabsDidChange];
}

- (void)captureCurrentStateIntoSelectedTab
{
    NSMutableDictionary *tab = [_documentTabsController selectedTab];
    if (tab == nil) {
        return;
    }
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
    if (_currentRemoteDocument != nil) {
        [tab setObject:[[_currentRemoteDocument rawURL] absoluteString] forKey:OMDTabRemoteURLKey];
    } else {
        [tab removeObjectForKey:OMDTabRemoteURLKey];
    }
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
    [tab setObject:(markdown ?: @"") forKey:OMDTabImageMarkdownKey];
    [tab setObject:(sourcePath ?: @"") forKey:OMDTabImageSourcePathKey];
    if (renderMode == OMDDocumentRenderModeMarkdown) {
        [tab setObject:[self imageFingerprintsForMarkdown:markdown sourcePath:sourcePath]
                forKey:OMDTabImageFingerprintsKey];
    }
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

    if (inNewTab || [_documentTabsController selectedIndex] < 0 || [_documentTabsController selectedIndex] >= (NSInteger)[_documentTabsController count]) {
        [self captureCurrentStateIntoSelectedTab];
        [_documentTabsController addTab:tab];
        [_documentTabsController setSelectedIndex:(NSInteger)[_documentTabsController count] - 1];
    } else {
        [_documentTabsController replaceTabAtIndex:[_documentTabsController selectedIndex] withTab:tab];
    }

    [self applyDocumentTabRecord:tab];
    if (resetViewport) {
        [self resetCurrentDocumentViewportToStart];
    }
    [self documentTabsDidChange];
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
    // Before the text, so the renderer resolves links against it.
    [_currentRemoteDocument release];
    _currentRemoteDocument = [[OMDRemoteDocument documentWithURLString:[tabRecord objectForKey:OMDTabRemoteURLKey]] retain];
    [self setCurrentDocumentText:(markdown != nil ? markdown : @"")
                      sourcePath:sourcePath
                      renderMode:renderMode
                  syntaxLanguage:syntaxLanguage];

    _sourceIsDirty = [[tabRecord objectForKey:OMDTabDirtyKey] boolValue];
    NSString *displayTitle = [tabRecord objectForKey:OMDTabDisplayTitleKey];
    [_currentDisplayTitle release];
    _currentDisplayTitle = [displayTitle copy];
    BOOL readOnly = [[tabRecord objectForKey:OMDTabReadOnlyKey] boolValue];
    _currentDocumentReadOnly = readOnly;
    [self setCurrentDiskFingerprintStateLoaded:[tabRecord objectForKey:OMDTabLoadedDiskFingerprintKey]
                                      observed:[tabRecord objectForKey:OMDTabObservedDiskFingerprintKey]
                                    suppressed:[tabRecord objectForKey:OMDTabSuppressedDiskFingerprintKey]];
    [self applyCurrentDocumentReadOnlyState];
    [self updatePreviewStatusIndicator];
    [self updateWindowTitle];
    if (![self isPreviewVisible]) {
        [self refreshOutline];
    }
}

- (void)selectDocumentTabAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)[_documentTabsController count]) {
        return;
    }
    if (index == [_documentTabsController selectedIndex]) {
        return;
    }

    [self captureCurrentStateIntoSelectedTab];
    [_documentTabsController setSelectedIndex:index];
    NSDictionary *tab = [_documentTabsController tabAtIndex:index];
    [self applyDocumentTabRecord:tab];
    [_documentTabsController updateTabStrip];
    [self refreshCurrentDocumentDiskStateAllowPrompt:YES];
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
        NSInteger existingIndex = [_documentTabsController documentTabIndexForLocalPath:normalizedSourcePath];
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
    NSArray *scrollViews = [NSArray arrayWithObjects:_sourceScrollView, _previewScrollView, [_explorerController scrollView], nil];
    for (NSScrollView *scrollView in scrollViews) {
        if (scrollView == nil) {
            continue;
        }
        [scrollView setVerticalLineScroll:scrollSpeed];
        [scrollView setHorizontalLineScroll:scrollSpeed];
    }
}

- (BOOL)ensureOpenFileSizeWithinLimit:(unsigned long long)size
                           descriptor:(NSString *)descriptor
{
    NSUInteger limit = [_explorerController explorerMaxOpenFileSizeBytes];
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

- (void)updateModeControlSelection
{
    NSSegmentedControl *modeControl = [_toolbarController modeControl];
    NSTextField *modeLabel = [_toolbarController modeLabel];
    if (modeControl == nil) {
        return;
    }
    [modeControl setSelectedSegment:_viewerMode];
    if (modeLabel != nil) {
        [modeLabel setTextColor:[self modeLabelTextColor]];
    }
    [self updatePreviewStatusIndicator];
}

- (void)updatePreviewStatusIndicator
{
    NSTextField *previewStatusLabel = [_toolbarController previewStatusLabel];
    [_toolbarController updateToolbarActionControlsState];
    if (previewStatusLabel == nil) {
        return;
    }

    if (_sourceVimCommandLine != nil && [_sourceVimCommandLine length] > 0) {
        [previewStatusLabel setStringValue:_sourceVimCommandLine];
        [previewStatusLabel setTextColor:[NSColor controlTextColor]];
        [previewStatusLabel setHidden:NO];
        return;
    }

    NSString *vimStatusText = [self sourceVimStatusText];
    if (vimStatusText != nil) {
        [previewStatusLabel setStringValue:vimStatusText];
        [previewStatusLabel setTextColor:[NSColor controlTextColor]];
        [previewStatusLabel setHidden:NO];
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
            statusColor = [NSColor secondaryLabelColor];
        }
    } else if ([status isEqualToString:@"Preview Stale"]) {
        _previewStatusShowsUpdated = NO;
        [self cancelPendingPreviewStatusAutoHide];
        showStatus = YES;
        statusText = @"Preview stale";
        statusColor = [NSColor controlTextColor];
    } else if ([status isEqualToString:@"Preview Live"]) {
        if (_previewStatusShowsUpdated) {
            showStatus = YES;
            statusText = @"Updated";
            statusColor = [NSColor secondaryLabelColor];
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
        [previewStatusLabel setStringValue:statusText];
        [previewStatusLabel setTextColor:statusColor];
        [previewStatusLabel setHidden:NO];
    } else {
        [previewStatusLabel setStringValue:@""];
        [previewStatusLabel setHidden:YES];
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
    [self updateOutlineCurrentHeading];
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
    // round, not floor: the ratio read back from the editor's width must
    // give the same width again.
    CGFloat position = round(available * _splitRatio);
    if (position < minWidth) {
        position = minWidth;
    }
    if (position > (available - minWidth)) {
        position = available - minWidth;
    }
    BOOL wasApplying = _isApplyingSplitViewRatio;
    _isApplyingSplitViewRatio = YES;
    [_splitView setPosition:position ofDividerAtIndex:0];
    _isApplyingSplitViewRatio = wasApplying;
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
    } else if (_currentRemoteDocument != nil) {
        // Relative links and images on the web, next to the document.
        baseURL = [_currentRemoteDocument baseURL];
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
        [_renderScheduler cancelPendingInteractiveRender];
        [_renderScheduler cancelPendingMathArtifactRender];
        [_renderScheduler cancelPendingLivePreviewRender];
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
    [_preferencesController syncPreferencesPanelFromSettings];
}

- (OMMarkdownDiagramRenderingPolicy)currentDiagramRenderingPolicy
{
    OMMarkdownParsingOptions *options = _renderer != nil ? [_renderer parsingOptions] : nil;
    if (options != nil) {
        return [options diagramRenderingPolicy];
    }
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDDiagramRenderingPolicyDefaultsKey];
    if ([value respondsToSelector:@selector(integerValue)]) {
        return OMDDiagramRenderingPolicyFromInteger([value integerValue]);
    }
    return OMMarkdownDiagramRenderingPolicyNative;
}

- (void)setDiagramRenderingPolicyPreference:(OMMarkdownDiagramRenderingPolicy)policy
{
    if (_renderer == nil) {
        return;
    }
    OMMarkdownParsingOptions *existing = [_renderer parsingOptions];
    OMMarkdownParsingOptions *options = existing != nil ? [[existing copy] autorelease]
                                                        : [OMMarkdownParsingOptions defaultOptions];
    [options setDiagramRenderingPolicy:policy];
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)policy
                                               forKey:OMDDiagramRenderingPolicyDefaultsKey];
    [self applyParsingOptionsAndRender:options];
    [_preferencesController syncPreferencesPanelFromSettings];
}

- (void)setDiagramRenderingNative:(id)sender
{
    [self setDiagramRenderingPolicyPreference:OMMarkdownDiagramRenderingPolicyNative];
}

- (void)setDiagramRenderingSourceCode:(id)sender
{
    [self setDiagramRenderingPolicyPreference:OMMarkdownDiagramRenderingPolicySourceCode];
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
    [_preferencesController syncPreferencesPanelFromSettings];
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
    [_preferencesController syncPreferencesPanelFromSettings];
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
    [_preferencesController syncPreferencesPanelFromSettings];
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
    [_preferencesController syncPreferencesPanelFromSettings];
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
    [_preferencesController syncPreferencesPanelFromSettings];
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
    [_preferencesController syncPreferencesPanelFromSettings];
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
        [_preferencesController syncPreferencesPanelFromSettings];
    }
}

- (void)toggleRendererSyntaxHighlighting:(id)sender
{
    [self setRendererSyntaxHighlightingPreferenceEnabled:![self isRendererSyntaxHighlightingPreferenceEnabled]];
}

- (void)requestSourceSyntaxHighlightingRefresh
{
    BOOL profiling = OMDKeyLatencyProfilingEnabled();
    NSTimeInterval start = profiling ? OMDKeyLatencyNow() : 0.0;
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
    if (profiling) {
        NSTimeInterval end = OMDKeyLatencyNow();
        double totalMS = OMDKeyLatencyMS(start, end);
        if (totalMS >= OMDKeyLatencyThresholdMS()) {
            NSLog(@"OMDKeyLatency sourceHighlightRequest total=%.2fms length=%lu delay=%.3fs fullPass=%@",
                  totalMS,
                  (unsigned long)length,
                  delay,
                  _sourceHighlightNeedsFullPass ? @"YES" : @"NO");
        }
    }
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
    BOOL profiling = OMDKeyLatencyProfilingEnabled();
    NSTimeInterval start = profiling ? OMDKeyLatencyNow() : 0.0;
    if (timer != _sourceSyntaxHighlightTimer) {
        return;
    }
    [_sourceSyntaxHighlightTimer invalidate];
    [_sourceSyntaxHighlightTimer release];
    _sourceSyntaxHighlightTimer = nil;
    [self applySourceSyntaxHighlightingNow];
    if (profiling) {
        NSTimeInterval end = OMDKeyLatencyNow();
        double totalMS = OMDKeyLatencyMS(start, end);
        if (totalMS >= OMDKeyLatencyThresholdMS()) {
            NSLog(@"OMDKeyLatency sourceHighlightTimer total=%.2fms", totalMS);
        }
    }
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
    BOOL profiling = OMDKeyLatencyProfilingEnabled();
    NSTimeInterval start = profiling ? OMDKeyLatencyNow() : 0.0;
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
    NSTimeInterval afterRange = profiling ? OMDKeyLatencyNow() : 0.0;

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
    NSTimeInterval afterHighlight = profiling ? OMDKeyLatencyNow() : 0.0;
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

    if (profiling) {
        NSTimeInterval end = OMDKeyLatencyNow();
        double totalMS = OMDKeyLatencyMS(start, end);
        if (totalMS >= OMDKeyLatencyThresholdMS()) {
            NSLog(@"OMDKeyLatency sourceHighlightApply total=%.2fms range=%.2fms highlight=%.2fms typing=%.2fms length=%lu target=%@",
                  totalMS,
                  OMDKeyLatencyMS(start, afterRange),
                  OMDKeyLatencyMS(afterRange, afterHighlight),
                  OMDKeyLatencyMS(afterHighlight, end),
                  (unsigned long)[storage length],
                  fullPass ? @"full" : NSStringFromRange(targetRange));
        }
    }
}

- (OMDLayoutDensityMode)effectiveLayoutDensityMode
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDLayoutDensityDefaultsKey];
    if ([value respondsToSelector:@selector(integerValue)]) {
        return OMDClampedLayoutDensityMode([value integerValue]);
    }
    // The same default under every theme: the app doesn't look at which
    // theme is drawing it.
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
        [_formattingBarController rebuildFormattingBar];
        [self layoutSourceEditorContainer];
    }

    if (_sidebarContainer != nil) {
        [_explorerController applyLayoutDensity];
    }

    [self layoutWorkspaceChrome];
    [self updatePreviewStatusIndicator];

    if (_currentMarkdown != nil && [self isPreviewVisible]) {
        _lastRenderedLayoutWidth = -1.0;
        [self renderCurrentMarkdown];
    }

    [_preferencesController layoutDensityDidChange];
}

- (BOOL)canRenderPreview
{
    return [self isPreviewVisible] && _currentMarkdown != nil;
}

- (NSTextView *)previewTextView
{
    return _textView;
}

- (OMMarkdownRenderer *)previewRenderer
{
    return _renderer;
}

- (void)previewDidLayoutForCopyButtons
{
    if ([_textView isKindOfClass:[OMDTextView class]]) {
        [(OMDTextView *)_textView updateRenderedObjectToolTips];
        // Character indexes changed with the new render.
        [(OMDTextView *)_textView setLinkedObjectIndex:NSNotFound];
        [self updateLinkedPreviewObject];
    }
    [self refreshOutline];
}

- (CGFloat)previewZoomScale
{
    return _zoomScale;
}

- (BOOL)isExplorerSidebarVisible
{
    return _explorerSidebarVisible;
}

- (NSWindow *)mainWindow
{
    return _window;
}

- (OMDExplorerController *)explorerController
{
    return _explorerController;
}

- (void)showPreferences:(id)sender
{
    (void)sender;
    [_preferencesController showPreferences];
}

- (void)checkForUpdates:(id)sender
{
    if (_updaterController == nil) {
        NSBeep();
        return;
    }
    [(GPStandardUpdaterController *)_updaterController checkForUpdates:sender];
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

- (NSString *)themePreference
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *globalDomain = [defaults persistentDomainForName:NSGlobalDomain];
    id value = [globalDomain objectForKey:OMDThemeDefaultsKey];
    // "GNUstep" is the built-in theme, which the menu lists as no theme.
    if ([value isEqual:@"GNUstep"]) {
        return nil;
    }
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

    // GNUstep's own theme is stored by name rather than by removing the
    // key: at launch a missing GSTheme means "never chosen" and becomes
    // Adwaita (OMDEnsureDefaultPreferences in main.m).
    if (themeName == nil || [themeName length] == 0) {
        themeName = @"GNUstep";
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
    [_preferencesController refreshSourceFontDescription];
}

// "Noto Sans Mono, 13 pt", for Preferences.
- (NSString *)sourceEditorFontDescription
{
    NSFont *font = [_sourceTextView font];
    if (font == nil) {
        return @"";
    }
    NSString *name = [font familyName];
    if ([name length] == 0) {
        name = [font displayName];
    }
    if ([name length] == 0) {
        name = [font fontName];
    }
    return [NSString stringWithFormat:@"%@, %g pt", name, (double)[font pointSize]];
}

// Zoom acts on the pane being worked in: the source editor's font while it
// has focus, the preview otherwise.
- (BOOL)sourceEditorHasFocus
{
    return _sourceTextView != nil && _viewerMode != OMDViewerModeRead &&
           [_window firstResponder] == _sourceTextView;
}

- (void)setPreviewZoomScale:(CGFloat)scale
{
    NSSlider *zoomSlider = [_toolbarController zoomSlider];
    scale = MAX(0.5, MIN(2.0, scale));
    _zoomScale = scale;
    [[NSUserDefaults standardUserDefaults] setDouble:_zoomScale forKey:@"ObjcMarkdownZoomScale"];
    if (zoomSlider != nil) {
        [zoomSlider setDoubleValue:_zoomScale * 100.0];
    }
    [self updateZoomLabel];
    _lastZoomSliderEventTime = OMDNow();
    [_renderScheduler cancelPendingInteractiveRender];
    [self renderCurrentMarkdown];
}

- (void)zoomIn:(id)sender
{
    if ([self sourceEditorHasFocus]) {
        [self increaseSourceEditorFontSize:sender];
        return;
    }
    [self setPreviewZoomScale:(floor(_zoomScale * 10.0 + 0.5) + 1.0) / 10.0];
}

- (void)zoomOut:(id)sender
{
    if ([self sourceEditorHasFocus]) {
        [self decreaseSourceEditorFontSize:sender];
        return;
    }
    [self setPreviewZoomScale:(floor(_zoomScale * 10.0 + 0.5) - 1.0) / 10.0];
}

- (void)zoomToActualSize:(id)sender
{
    if ([self sourceEditorHasFocus]) {
        [self resetSourceEditorFontSize:sender];
        return;
    }
    [self setPreviewZoomScale:1.0];
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

    [_toolbarController updateToolbarActionControlsState];
    [_explorerController setDocumentPath:[self resolvedAbsolutePathForLocalPath:_currentPath]];
    [self updateRemoteDocumentBar];

    // Say what the window shows and let the theme present it: a file's
    // name and folder, and whether it has unsaved changes. The mode is on
    // the switcher and "Updating..." in the status label.
    BOOL showsFile = (_currentPath != nil && [_currentPath length] > 0 &&
                      (_currentDisplayTitle == nil || [_currentDisplayTitle length] == 0 ||
                       [_currentDisplayTitle isEqualToString:[_currentPath lastPathComponent]]));
    if (showsFile) {
        [_window setTitleWithRepresentedFilename:_currentPath];
    } else {
        [_window setRepresentedFilename:@""];
        NSString *title = _currentDisplayTitle;
        if (title == nil || [title length] == 0) {
            title = (_currentPath != nil ? [_currentPath lastPathComponent] : @"Markdown Viewer");
        }
        [_window setTitle:title];
    }
    [_window setDocumentEdited:_sourceIsDirty];
}

// Ranges of the display equations in the preview, in document order.
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

- (void)formattingBarController:(OMDFormattingBarController *)controller applyHeadingLevel:(NSInteger)level
{
    (void)controller;
    if (![self isFormattingBarVisibleInCurrentMode]) {
        return;
    }
    if (_currentDocumentReadOnly) {
        return;
    }
    [self applyHeadingLevel:level];
}

- (void)formattingBarController:(OMDFormattingBarController *)controller performCommandWithTag:(NSInteger)tag
{
    (void)controller;
    if (_sourceTextView == nil || ![self isFormattingBarVisibleInCurrentMode]) {
        return;
    }
    if (_currentDocumentReadOnly) {
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
    BOOL profiling = OMDKeyLatencyProfilingEnabled();
    NSTimeInterval start = profiling ? OMDKeyLatencyNow() : 0.0;
    if (_isProgrammaticSourceUpdate || _isProgrammaticSourceHighlightUpdate) {
        return;
    }
    if ([notification object] != _sourceTextView) {
        return;
    }

    NSString *updatedMarkdown = [[_sourceTextView string] copy];
    NSTimeInterval afterCopy = profiling ? OMDKeyLatencyNow() : 0.0;
    [_currentMarkdown release];
    _currentMarkdown = updatedMarkdown;
    BOOL wasDirty = _sourceIsDirty;
    _sourceIsDirty = YES;
    _sourceRevision += 1;
    [self updateWindowTitle];
    NSTimeInterval afterTitle = profiling ? OMDKeyLatencyNow() : 0.0;
    [self captureCurrentStateIntoSelectedTab];
    NSTimeInterval afterCapture = profiling ? OMDKeyLatencyNow() : 0.0;
    if (!wasDirty) {
        [_documentTabsController updateTabStrip];
    }
    NSTimeInterval afterTabs = profiling ? OMDKeyLatencyNow() : 0.0;
    [self scheduleRecoveryAutosave];
    NSTimeInterval afterAutosave = profiling ? OMDKeyLatencyNow() : 0.0;

    if (_viewerMode == OMDViewerModeSplit) {
        if (_sourceRevision == _lastRenderedSourceRevision) {
            [self syncPreviewToSourceInteractionAnchor];
        }
        [_renderScheduler scheduleLivePreviewRender];
    }
    [self scheduleSourceOutlineRefresh];
    NSTimeInterval afterPreview = profiling ? OMDKeyLatencyNow() : 0.0;
    [self requestSourceSyntaxHighlightingRefresh];
    NSTimeInterval afterHighlightRequest = profiling ? OMDKeyLatencyNow() : 0.0;
    [self updatePreviewStatusIndicator];
    NSTimeInterval afterStatus = profiling ? OMDKeyLatencyNow() : 0.0;
    [self updateFormattingBarContextState];
    if (profiling) {
        NSTimeInterval end = OMDKeyLatencyNow();
        double totalMS = OMDKeyLatencyMS(start, end);
        if (totalMS >= OMDKeyLatencyThresholdMS()) {
            NSLog(@"OMDKeyLatency textDidChange total=%.2fms copy=%.2fms title=%.2fms capture=%.2fms tabs=%.2fms autosave=%.2fms preview=%.2fms highlightRequest=%.2fms status=%.2fms formatting=%.2fms length=%lu mode=%ld",
                  totalMS,
                  OMDKeyLatencyMS(start, afterCopy),
                  OMDKeyLatencyMS(afterCopy, afterTitle),
                  OMDKeyLatencyMS(afterTitle, afterCapture),
                  OMDKeyLatencyMS(afterCapture, afterTabs),
                  OMDKeyLatencyMS(afterTabs, afterAutosave),
                  OMDKeyLatencyMS(afterAutosave, afterPreview),
                  OMDKeyLatencyMS(afterPreview, afterHighlightRequest),
                  OMDKeyLatencyMS(afterHighlightRequest, afterStatus),
                  OMDKeyLatencyMS(afterStatus, end),
                  (unsigned long)[_currentMarkdown length],
                  (long)_viewerMode);
        }
    }
}

- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    if ([notification object] == _sourceTextView) {
        [self updateLinkedPreviewObject];
    }
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

// Characters of 1-based source lines [location, location + length), or NSNotFound.
static NSRange OMDCharacterRangeForSourceLines(NSString *source, NSRange lineRange)
{
    if (source == nil || lineRange.location == NSNotFound || lineRange.location == 0 || lineRange.length == 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger line = 1;
    NSUInteger index = 0;
    NSUInteger start = NSNotFound;
    NSUInteger lastLine = lineRange.location + lineRange.length - 1;
    while (index <= [source length]) {
        NSRange lineChars = [source lineRangeForRange:NSMakeRange(index, 0)];
        if (line == lineRange.location) {
            start = lineChars.location;
        }
        if (line == lastLine && start != NSNotFound) {
            NSUInteger end = NSMaxRange(lineChars);
            // Leave the final line break out of the selection.
            while (end > start && ([source characterAtIndex:end - 1] == '\n' || [source characterAtIndex:end - 1] == '\r')) {
                end -= 1;
            }
            return NSMakeRange(start, end - start);
        }
        if (NSMaxRange(lineChars) <= index || NSMaxRange(lineChars) >= [source length]) {
            break;
        }
        index = NSMaxRange(lineChars);
        line += 1;
    }
    return NSMakeRange(NSNotFound, 0);
}

- (void)textView:(OMDTextView *)textView revealSourceOfRenderedObject:(OMRenderedObject *)object
{
    if (textView != _textView || _sourceTextView == nil || object == nil || ![self hasLoadedDocument]) {
        return;
    }
    NSString *source = [_sourceTextView string];
    NSRange characters = NSMakeRange(NSNotFound, 0);
    // The exact range holds only while the preview matches the editor text.
    NSRange exact = [object sourceRange];
    if (_sourceRevision == _lastRenderedSourceRevision &&
        exact.location != NSNotFound && NSMaxRange(exact) <= [source length]) {
        characters = exact;
    } else {
        characters = OMDCharacterRangeForSourceLines(source, [object sourceLineRange]);
    }
    if (characters.location == NSNotFound) {
        NSBeep();
        return;
    }
    if (_viewerMode == OMDViewerModeRead) {
        [self setViewerMode:OMDViewerModeSplit persistPreference:YES];
    }
    [_sourceTextView setSelectedRange:characters];
    [_sourceTextView scrollRangeToVisible:characters];
    [[_sourceTextView window] makeFirstResponder:_sourceTextView];
}

- (void)textView:(OMDTextView *)textView rerenderRenderedObject:(OMRenderedObject *)object
{
    if (textView != _textView || ![object isMath]) {
        return;
    }
    [OMMarkdownRenderer invalidateCachedMathForFormula:[object source]];
    [_renderScheduler scheduleMathArtifactRefresh];
}

- (void)refreshOutline
{
    if (_outlineController == nil) {
        return;
    }
    [_outlineController setHeadings:[self outlineHeadings]];
    if (_pendingLinkFragment != nil && [[_textView textStorage] length] > 0) {
        NSString *fragment = [_pendingLinkFragment autorelease];
        _pendingLinkFragment = nil;
        if (![self scrollToAnchor:fragment]) {
            NSBeep();
        }
    }
    if ([[_outlineController view] superview] == nil && _outlineVisible && [self hasLoadedDocument]) {
        [self layoutDocumentViews];
    }
    [self updateOutlineCurrentHeading];
}

// The rendered headings while the preview is shown; in Edit mode, where
// nothing is rendered, the ones in the editor's Markdown (#42).
- (NSArray *)outlineHeadings
{
    if (![self hasLoadedDocument]) {
        return nil;
    }
    if ([self isPreviewVisible]) {
        return [_renderer headings];
    }
    if (_currentDocumentRenderMode == OMDDocumentRenderModeVerbatim || _currentMarkdown == nil) {
        return nil;
    }
    return [OMMarkdownRenderer headingsInMarkdown:_currentMarkdown];
}

// After an edit in Edit mode, once typing pauses.
- (void)scheduleSourceOutlineRefresh
{
    if (!_outlineVisible || [self isPreviewVisible]) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshOutline) object:nil];
    [self performSelector:@selector(refreshOutline) withObject:nil afterDelay:0.3];
}

// Highlights the heading whose section is at the top of what's being read:
// the preview when it's shown, otherwise the editor.
- (void)updateOutlineCurrentHeading
{
    if (_outlineController == nil || !_outlineVisible) {
        return;
    }
    NSArray *headings = [_outlineController headings];
    NSInteger index = -1;
    if ([headings count] > 0 && [self isPreviewVisible] && _textView != nil) {
        NSLayoutManager *layoutManager = [_textView layoutManager];
        NSTextContainer *container = [_textView textContainer];
        NSRect visible = [_textView visibleRect];
        NSPoint origin = [_textView textContainerOrigin];
        NSPoint probe = NSMakePoint(NSMinX(visible) + 4.0 - origin.x,
                                    MAX(0.0, NSMinY(visible) + NSHeight(visible) * 0.2 - origin.y));
        if ([layoutManager numberOfGlyphs] > 0) {
            NSUInteger glyph = [layoutManager glyphIndexForPoint:probe inTextContainer:container];
            NSUInteger character = [layoutManager characterIndexForGlyphAtIndex:glyph];
            index = [OMDOutlineController headingIndexForRenderedLocation:character inHeadings:headings];
        }
    } else if ([headings count] > 0 && _sourceTextView != nil) {
        NSLayoutManager *layoutManager = [_sourceTextView layoutManager];
        NSRect visible = [_sourceTextView visibleRect];
        NSPoint origin = [_sourceTextView textContainerOrigin];
        NSPoint probe = NSMakePoint(4.0, MAX(0.0, NSMinY(visible) + NSHeight(visible) * 0.2 - origin.y));
        if ([layoutManager numberOfGlyphs] > 0) {
            NSUInteger glyph = [layoutManager glyphIndexForPoint:probe inTextContainer:[_sourceTextView textContainer]];
            NSUInteger character = [layoutManager characterIndexForGlyphAtIndex:glyph];
            NSString *source = [_sourceTextView string];
            NSUInteger line = 1;
            NSUInteger scan = 0;
            for (; scan < character && scan < [source length]; scan++) {
                if ([source characterAtIndex:scan] == '\n') {
                    line += 1;
                }
            }
            index = [OMDOutlineController headingIndexForSourceLine:line inHeadings:headings];
        }
    }
    if (index != [_outlineController currentHeadingIndex]) {
        [_outlineController setCurrentHeadingIndex:index];
    }
}

- (void)outlineController:(OMDOutlineController *)controller didChooseHeading:(NSDictionary *)heading
{
    [self scrollToHeading:heading];
    [controller setCurrentHeadingIndex:[[controller headings] indexOfObject:heading]];
}

// Brings a heading (one of the renderer's -headings) to the top of the
// preview and, in Edit and Split, moves the editor caret to its line.
- (void)scrollToHeading:(NSDictionary *)heading
{
    NSRange range = [[heading objectForKey:OMMarkdownRendererHeadingRangeKey] rangeValue];
    NSUInteger line = [[heading objectForKey:OMMarkdownRendererHeadingSourceLineKey] unsignedIntegerValue];
    // Scroll both panes directly; linked scrolling would otherwise fight it.
    BOOL wasSyncing = _isProgrammaticScrollSync;
    _isProgrammaticScrollSync = YES;
    if ([self isPreviewVisible] && _textView != nil && range.location <= [[_textView textStorage] length]) {
        [self scrollPreviewToCharacterIndex:range.location verticalAnchor:0.06];
    }
    if (_viewerMode != OMDViewerModeRead && _sourceTextView != nil) {
        NSRange characters = OMDCharacterRangeForSourceLines([_sourceTextView string], NSMakeRange(line, 1));
        if (characters.location != NSNotFound) {
            BOOL wasSelecting = _isProgrammaticSelectionSync;
            _isProgrammaticSelectionSync = YES;
            [_sourceTextView setSelectedRange:NSMakeRange(characters.location, 0)];
            _isProgrammaticSelectionSync = wasSelecting;
            [self updateFormattingBarContextState];
            [self scrollSourceToCharacterIndex:characters.location verticalAnchor:0.06];
        }
    }
    _isProgrammaticScrollSync = wasSyncing;
    [self updateOutlineCurrentHeading];
}

// The heading whose anchor matches: exactly, else ignoring case.
- (NSDictionary *)headingForAnchor:(NSString *)anchor
{
    if ([anchor length] == 0) {
        return nil;
    }
    NSArray *headings = [_renderer headings];
    for (NSDictionary *heading in headings) {
        if ([[heading objectForKey:OMMarkdownRendererHeadingAnchorKey] isEqualToString:anchor]) {
            return heading;
        }
    }
    for (NSDictionary *heading in headings) {
        if ([[heading objectForKey:OMMarkdownRendererHeadingAnchorKey] caseInsensitiveCompare:anchor] == NSOrderedSame) {
            return heading;
        }
    }
    return nil;
}

// Where a footnote anchor ("fn-label" on a note, "fnref-label" on a
// reference) is in the preview, or NSNotFound.
- (NSUInteger)previewLocationOfFootnoteAnchor:(NSString *)anchor
{
    NSTextStorage *storage = [_textView textStorage];
    NSUInteger length = [storage length];
    NSUInteger index = 0;
    while (index < length) {
        NSRange effective = NSMakeRange(index, 1);
        id value = [storage attribute:OMMarkdownRendererFootnoteAnchorAttributeName
                              atIndex:index
                       effectiveRange:&effective];
        if ([value isEqual:anchor]) {
            return effective.location;
        }
        index = NSMaxRange(effective);
    }
    return NSNotFound;
}

// Scrolls to a "#fragment" target: a heading's slug, else a footnote.
- (BOOL)scrollToAnchor:(NSString *)anchor
{
    NSDictionary *heading = [self headingForAnchor:anchor];
    if (heading != nil) {
        [self scrollToHeading:heading];
        return YES;
    }
    if (![self isPreviewVisible] || [anchor length] == 0) {
        return NO;
    }
    NSUInteger location = [self previewLocationOfFootnoteAnchor:anchor];
    if (location == NSNotFound) {
        return NO;
    }
    [self scrollPreviewToCharacterIndex:location verticalAnchor:0.06];
    return YES;
}

static NSString *OMDDecodedLinkFragment(NSURL *url)
{
    NSString *fragment = [url fragment];
    NSString *decoded = [fragment stringByRemovingPercentEncoding];
    return decoded != nil ? decoded : fragment;
}

static BOOL OMDIsMarkdownPath(NSString *path)
{
    NSString *extension = [[path pathExtension] lowercaseString];
    return [extension isEqualToString:@"md"] || [extension isEqualToString:@"markdown"] ||
           [extension isEqualToString:@"mdown"];
}

// In-app handling for links into Markdown documents: "#slug" in this
// document, and local Markdown files (optionally with "#slug"). Returns NO
// for links that should open elsewhere.
- (BOOL)followDocumentLink:(NSURL *)url
{
    NSString *fragment = OMDDecodedLinkFragment(url);
    if ([url scheme] == nil && [[url path] length] == 0 && [fragment length] > 0) {
        if (![self scrollToAnchor:fragment]) {
            NSBeep();
        }
        return YES;
    }
    // In a document from the web, a link to another Markdown file there
    // opens here too; elsewhere web links go to the browser.
    if (_currentRemoteDocument != nil &&
        ([[url scheme] isEqualToString:@"https"] || [[url scheme] isEqualToString:@"http"])) {
        OMDRemoteDocument *linked = [OMDRemoteDocument documentWithURLString:[url absoluteString]];
        if (linked != nil) {
            [_remoteDocumentBar setMessage:[NSString stringWithFormat:@"Opening %@...", [linked fileName]]];
            [self openRemoteDocument:linked inNewTab:NO completion:^(NSString *errorMessage) {
                if (errorMessage != nil) {
                    [_remoteDocumentBar setMessage:[NSString stringWithFormat:@"%@: %@", [linked fileName], errorMessage]];
                }
            }];
            return YES;
        }
    }
    if (![url isFileURL] || !OMDIsMarkdownPath([url path])) {
        return NO;
    }
    NSString *path = [[url path] stringByStandardizingPath];
    if (_currentPath != nil && [path isEqualToString:[_currentPath stringByStandardizingPath]]) {
        if ([fragment length] > 0 && ![self scrollToAnchor:fragment]) {
            NSBeep();
        }
        return YES;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    [_pendingLinkFragment release];
    _pendingLinkFragment = nil;
    if (![self openDocumentAtPath:path] || [fragment length] == 0) {
        return YES;
    }
    // Opening resets the viewport to the top after its first render, so
    // scroll now if that render is done, else when the next one finishes.
    if (_sourceRevision != _lastRenderedSourceRevision || ![self scrollToAnchor:fragment]) {
        _pendingLinkFragment = [fragment copy];
    }
    return YES;
}

- (void)openLocation:(id)sender
{
    (void)sender;
    if (_openLocationController == nil) {
        _openLocationController = [[OMDOpenLocationController alloc] initWithDelegate:self];
    }
    [_openLocationController showOverWindow:_window];
}

// OMDOpenLocationDelegate: in a new tab unless the window is empty.
- (void)openRemoteDocument:(OMDRemoteDocument *)document completion:(void (^)(NSString *errorMessage))completion
{
    BOOL inNewTab = !([_documentTabsController count] == 0 && _currentPath == nil && _currentMarkdown == nil);
    [self openRemoteDocument:document inNewTab:inNewTab completion:completion];
}

- (void)openRemoteDocument:(OMDRemoteDocument *)document
                  inNewTab:(BOOL)inNewTab
                completion:(void (^)(NSString *errorMessage))completion
{
    NSInteger existing = [_documentTabsController documentTabIndexForRemoteURL:[[document rawURL] absoluteString]];
    if (existing >= 0) {
        [self selectDocumentTabAtIndex:existing];
        [self presentWindowIfNeeded];
        completion(nil);
        return;
    }
    void (^done)(NSString *) = [[completion copy] autorelease];
    [document retain];
    OMDFetchRemoteDocument(document, [_explorerController explorerMaxOpenFileSizeBytes], ^(NSString *markdown, NSString *errorMessage) {
        [document autorelease];
        if (markdown == nil) {
            done(errorMessage);
            return;
        }
        if (!inNewTab && _sourceIsDirty &&
            ![self confirmDiscardingUnsavedChangesForAction:@"opening another document"]) {
            done(nil);
            return;
        }
        NSMutableDictionary *tab = [self newDocumentTabWithMarkdown:markdown
                                                         sourcePath:nil
                                                       displayTitle:[document fileName]
                                                           readOnly:YES
                                                         renderMode:OMDDocumentRenderModeMarkdown
                                                     syntaxLanguage:nil
                                                    diskFingerprint:nil];
        [tab setObject:[[document rawURL] absoluteString] forKey:OMDTabRemoteURLKey];
        [self installDocumentTabRecord:tab inNewTab:inNewTab resetViewport:YES];
        [self presentWindowIfNeeded];
        done(nil);
    });
}

// A web address from the command line, once the window is up; what went
// wrong shows in the Open Location panel.
- (void)openRemoteDocumentAfterLaunch:(OMDRemoteDocument *)document
{
    if (_window == nil || _launchWorkScheduled || !_postPresentationSetupComplete) {
        [self performSelector:@selector(openRemoteDocumentAfterLaunch:) withObject:document afterDelay:0.2];
        return;
    }
    [self openRemoteDocument:document completion:^(NSString *errorMessage) {
        if (errorMessage != nil) {
            [self openLocation:nil];
            [_openLocationController showAddress:[[document pageURL] absoluteString] message:errorMessage];
        }
    }];
}

- (void)updateRemoteDocumentBar
{
    BOOL show = (_currentRemoteDocument != nil);
    if (show && _remoteDocumentBar == nil && _documentContainer != nil) {
        _remoteDocumentBar = [[OMDRemoteDocumentBar alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)
                                                                  target:self
                                                          saveCopyAction:@selector(saveRemoteDocumentCopy:)
                                                     openInBrowserAction:@selector(openRemoteDocumentInBrowser:)];
        [_remoteDocumentBar setHidden:YES];
        [_documentContainer addSubview:_remoteDocumentBar];
    }
    if (_remoteDocumentBar == nil) {
        return;
    }
    if (show && [_remoteDocumentBar document] != _currentRemoteDocument) {
        [_remoteDocumentBar setDocument:_currentRemoteDocument];
    }
    if ([_remoteDocumentBar isHidden] == show) {
        [_remoteDocumentBar setHidden:!show];
        [self layoutDocumentViews];
    }
}

- (void)saveRemoteDocumentCopy:(id)sender
{
    [self saveDocumentAsMarkdown:sender];
}

- (void)openRemoteDocumentInBrowser:(id)sender
{
    (void)sender;
    NSURL *url = [_currentRemoteDocument pageURL];
    if (url == nil) {
        return;
    }
    if (![[NSWorkspace sharedWorkspace] openURL:url] && !OMDOpenURLUsingXDGOpen(url)) {
        NSBeep();
    }
}

// Outlines the preview object whose source holds the editor caret (Split mode).
- (void)updateLinkedPreviewObject
{
    if (![_textView isKindOfClass:[OMDTextView class]]) {
        return;
    }
    OMDTextView *preview = (OMDTextView *)_textView;
    NSUInteger linked = NSNotFound;
    if (_viewerMode == OMDViewerModeSplit && _sourceTextView != nil &&
        _sourceRevision == _lastRenderedSourceRevision) {
        NSRange selection = [_sourceTextView selectedRange];
        if (selection.location != NSNotFound) {
            linked = [preview renderedObjectIndexContainingSourceLocation:selection.location];
        }
    }
    [preview setLinkedObjectIndex:linked];
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

    if (url != nil && [self followDocumentLink:url]) {
        return YES;
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
    for (; index < (NSInteger)[_documentTabsController count]; index++) {
        NSDictionary *tab = [_documentTabsController tabAtIndex:index];
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
    [_renderScheduler cancelPendingInteractiveRender];
    [_renderScheduler cancelPendingMathArtifactRender];
    [_renderScheduler cancelPendingLivePreviewRender];
    [self cancelPendingPreviewStatusUpdatingVisibility];
    [self cancelPendingPreviewStatusAutoHide];
    [self cancelPendingRecoveryAutosave];
    [self clearRecoverySnapshot];
    [self setPreviewUpdating:NO];
    _externalReloadPromptVisible = NO;
    [self unregisterAsSecondaryWindow];
}

@end
