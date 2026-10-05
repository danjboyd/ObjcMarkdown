// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>
#import "OMDLayoutMetrics.h"
#import "OMDViewerDefaults.h"
#import "OMMarkdownRenderer.h"

@class OMDExplorerController;

// The settings the Preferences panel shows and changes. The setters apply
// their effect to the app as well as storing the setting.
@protocol OMDPreferencesControllerDelegate <NSObject>
- (NSWindow *)mainWindow;
- (OMDExplorerController *)explorerController;
- (void)chooseSourceEditorFont:(id)sender;
- (OMMarkdownDiagramRenderingPolicy)currentDiagramRenderingPolicy;
- (OMMarkdownMathRenderingPolicy)currentMathRenderingPolicy;
- (OMDSplitSyncMode)currentSplitSyncMode;
- (OMDLayoutDensityMode)effectiveLayoutDensityMode;
- (BOOL)isAllowRemoteImagesEnabled;
- (BOOL)isFormattingBarEnabledPreference;
- (BOOL)isRendererSyntaxHighlightingEnabled;
- (BOOL)isSourceHighlightHighContrastEnabled;
- (BOOL)isSourceSyntaxHighlightingEnabled;
- (BOOL)isSourceVimKeyBindingsEnabled;
- (BOOL)isTreeSitterAvailable;
- (BOOL)isWordSelectionModifierShimEnabled;
- (CGFloat)scrollSpeedPreference;
- (void)setAllowRemoteImagesPreference:(BOOL)allow;
- (void)setDiagramRenderingPolicyPreference:(OMMarkdownDiagramRenderingPolicy)policy;
- (void)setFormattingBarEnabledPreference:(BOOL)enabled;
- (void)setLayoutDensityPreference:(OMDLayoutDensityMode)mode;
- (void)setMathRenderingPolicyPreference:(OMMarkdownMathRenderingPolicy)policy;
- (void)setRendererSyntaxHighlightingPreferenceEnabled:(BOOL)enabled;
- (void)setScrollSpeedPreference:(CGFloat)scrollSpeed;
- (void)setSourceHighlightAccentColor:(NSColor *)color;
- (void)setSourceHighlightHighContrastEnabled:(BOOL)enabled;
- (void)setSourceSyntaxHighlightingEnabled:(BOOL)enabled;
- (void)setSourceVimKeyBindingsEnabled:(BOOL)enabled;
- (void)setSplitSyncModePreference:(OMDSplitSyncMode)mode;
- (void)setThemePreference:(NSString *)themeName;
- (void)setWordSelectionModifierShimEnabled:(BOOL)enabled;
- (NSString *)sourceEditorFontDescription;
- (NSColor *)sourceHighlightAccentColor;
- (NSString *)themePreference;
- (NSArray *)availableThemeNames;
@end

// The Preferences panel: one section of settings at a time, chosen by a
// segmented control.
@interface OMDPreferencesController : NSObject
{
    id<OMDPreferencesControllerDelegate> _delegate;
    NSPanel *_preferencesPanel;
    NSSegmentedControl *_preferencesSectionControl;
    NSPopUpButton *_preferencesMathPolicyPopup;
    NSPopUpButton *_preferencesDiagramPolicyPopup;
    NSPopUpButton *_preferencesSplitSyncModePopup;
    NSPopUpButton *_preferencesThemePopup;
    NSPopUpButton *_preferencesLayoutModePopup;
    NSSlider *_preferencesScrollSpeedSlider;
    NSButton *_preferencesAllowRemoteImagesButton;
    NSButton *_preferencesFormattingBarButton;
    NSButton *_preferencesWordSelectionShimButton;
    NSButton *_preferencesSourceVimKeyBindingsButton;
    NSButton *_preferencesSyntaxHighlightingButton;
    NSButton *_preferencesSourceHighContrastButton;
    NSColorWell *_preferencesSourceAccentColorWell;
    NSButton *_preferencesSourceAccentResetButton;
    NSTextField *_preferencesSourceFontField;
    NSButton *_preferencesSourceFontButton;
    NSButton *_preferencesRendererSyntaxHighlightingButton;
    NSTextField *_preferencesRendererSyntaxHighlightingNoteLabel;
    NSTextField *_preferencesExplorerLocalRootField;
    NSTextField *_preferencesExplorerMaxFileSizeField;
    NSTextField *_preferencesExplorerListFontSizeField;
    NSSecureTextField *_preferencesExplorerGitHubTokenField;
    NSInteger _preferencesSelectedSection;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDPreferencesControllerDelegate>)delegate;

- (void)showPreferences;
// Refreshes the controls from the current settings, if the panel exists.
- (void)syncPreferencesPanelFromSettings;
// Rebuilds the visible panel for a new layout density.
- (void)layoutDensityDidChange;
- (void)refreshSourceFontDescription;

@end
