// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDPreferencesController.h"
#import "OMDExplorerController.h"
#import "OMDFillViews.h"
#import "OMDPanelSelection.h"
#import "OMDPreferencesPopup.h"
#import "OMDTextFileSupport.h"
#import "OMDViewerColors.h"
#import "OMDViewerDefaults.h"

#include <math.h>

typedef NS_ENUM(NSInteger, OMDPreferencesSection) {
    OMDPreferencesSectionAppearance = 0,
    OMDPreferencesSectionExplorer = 1,
    OMDPreferencesSectionPreview = 2,
    OMDPreferencesSectionEditor = 3
};

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

static void OMDConfigurePreferencesPopup(NSPopUpButton *popup, OMDLayoutMetrics metrics)
{
    if (popup == nil) {
        return;
    }
    [popup setBordered:YES];
    [popup setBezelStyle:NSRoundedBezelStyle];
    [popup setFont:OMDPreferencesLabelFont(metrics)];
    if ([[popup cell] respondsToSelector:@selector(setControlSize:)]) {
        [[popup cell] setControlSize:NSRegularControlSize];
    }
    [popup setNeedsDisplay:YES];
}

// A section of the panel: a theme-drawn box whose content view is flipped,
// so rows are laid out from the top. Returns the content view.
static NSView *OMDAddPreferencesCard(NSView *parent, NSRect frame)
{
    NSBox *box = [[[NSBox alloc] initWithFrame:frame] autorelease];
    [box setTitlePosition:NSNoTitle];
    [box setBorderType:NSLineBorder];
    [box setContentViewMargins:NSZeroSize];
    NSView *content = [[[OMDFlippedView alloc] initWithFrame:[[box contentView] frame]] autorelease];
    [box setContentView:content];
    [parent addSubview:box];
    return content;
}

@interface OMDPreferencesController ()
- (void)preferencesExplorerLocalRootChanged:(id)sender;
- (void)preferencesExplorerMaxFileSizeChanged:(id)sender;
- (void)preferencesExplorerListFontSizeChanged:(id)sender;
- (void)preferencesDiagramPolicyChanged:(id)sender;
- (void)releasePreferencesPanelControls;
- (void)rebuildPreferencesPanelContent;
- (void)normalizePreferencesPanelFrameForSize:(NSSize)size;
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
- (void)reloadThemePopupItems;
- (void)preferencesThemeChanged:(id)sender;
- (void)showThemeRestartNotice;
@end

@implementation OMDPreferencesController

- (instancetype)initWithDelegate:(id<OMDPreferencesControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [_preferencesPanel release];
    [_preferencesSectionControl release];
    [_preferencesMathPolicyPopup release];
    [_preferencesDiagramPolicyPopup release];
    [_preferencesSplitSyncModePopup release];
    [_preferencesThemePopup release];
    [_preferencesLayoutModePopup release];
    [_preferencesScrollSpeedSlider release];
    [_preferencesAllowRemoteImagesButton release];
    [_preferencesFormattingBarButton release];
    [_preferencesWordSelectionShimButton release];
    [_preferencesSourceVimKeyBindingsButton release];
    [_preferencesSyntaxHighlightingButton release];
    [_preferencesSourceHighContrastButton release];
    [_preferencesSourceAccentColorWell release];
    [_preferencesSourceAccentResetButton release];
    [_preferencesSourceFontField release];
    [_preferencesSourceFontButton release];
    [_preferencesRendererSyntaxHighlightingButton release];
    [_preferencesRendererSyntaxHighlightingNoteLabel release];
    [_preferencesExplorerLocalRootField release];
    [_preferencesExplorerMaxFileSizeField release];
    [_preferencesExplorerListFontSizeField release];
    [super dealloc];
}

- (void)layoutDensityDidChange
{
    if (_preferencesPanel != nil && [_preferencesPanel isVisible]) {
        [self rebuildPreferencesPanelContent];
        [self syncPreferencesPanelFromSettings];
    }
}

- (void)refreshSourceFontDescription
{
    if (_preferencesSourceFontField != nil) {
        [_preferencesSourceFontField setStringValue:[_delegate sourceEditorFontDescription]];
    }
}

- (void)chooseSourceEditorFont:(id)sender
{
    [_delegate chooseSourceEditorFont:sender];
}

- (void)releasePreferencesPanelControls
{
    [_preferencesSectionControl release];
    _preferencesSectionControl = nil;
    [_preferencesMathPolicyPopup release];
    _preferencesMathPolicyPopup = nil;
    [_preferencesDiagramPolicyPopup release];
    _preferencesDiagramPolicyPopup = nil;
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
    [_preferencesSourceFontField release];
    _preferencesSourceFontField = nil;
    [_preferencesSourceFontButton release];
    _preferencesSourceFontButton = nil;
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
}

- (void)normalizePreferencesPanelFrameForSize:(NSSize)size
{
    if (_preferencesPanel == nil) {
        return;
    }

    NSScreen *screen = [[_delegate mainWindow] screen];
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
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0,
                                                          0.0,
                                                          NSWidth([view bounds]),
                                                          metrics.preferencesAppearanceCardHeight));

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
    OMDConfigurePreferencesPopup(_preferencesThemePopup, metrics);
    [_preferencesThemePopup setTarget:self];
    [_preferencesThemePopup setAction:@selector(preferencesThemeChanged:)];
    [_preferencesThemePopup setToolTip:@"Theme changes apply after relaunch."];
    [card addSubview:_preferencesThemePopup];
    OMDAddPreferencesPopupOverlay(card, _preferencesThemePopup);

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
    OMDConfigurePreferencesPopup(_preferencesLayoutModePopup, metrics);
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
    OMDAddPreferencesPopupOverlay(card, _preferencesLayoutModePopup);

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
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0,
                                                          0.0,
                                                          NSWidth([view bounds]),
                                                          metrics.preferencesExplorerCardHeight));

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
                                        @"Where the explorer starts and how large a file it opens.",
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

}

- (void)buildPreferencesPreviewSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    CGFloat cardHeight = OMDPreferencesPreviewSectionHeightForMetrics(metrics);
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0,
                                                          0.0,
                                                          NSWidth([view bounds]),
                                                          cardHeight));

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
    OMDConfigurePreferencesPopup(_preferencesSplitSyncModePopup, metrics);
    [_preferencesSplitSyncModePopup addItemWithTitle:@"Independent"];
    [[_preferencesSplitSyncModePopup itemAtIndex:0] setTag:OMDSplitSyncModeUnlinked];
    [_preferencesSplitSyncModePopup addItemWithTitle:@"Linked Scrolling"];
    [[_preferencesSplitSyncModePopup itemAtIndex:1] setTag:OMDSplitSyncModeLinkedScrolling];
    [_preferencesSplitSyncModePopup addItemWithTitle:@"Follow Caret"];
    [[_preferencesSplitSyncModePopup itemAtIndex:2] setTag:OMDSplitSyncModeCaretSelectionFollow];
    [_preferencesSplitSyncModePopup setTarget:self];
    [_preferencesSplitSyncModePopup setAction:@selector(preferencesSplitSyncModeChanged:)];
    [card addSubview:_preferencesSplitSyncModePopup];
    OMDAddPreferencesPopupOverlay(card, _preferencesSplitSyncModePopup);

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
    OMDConfigurePreferencesPopup(_preferencesMathPolicyPopup, metrics);
    [_preferencesMathPolicyPopup addItemWithTitle:@"Styled Text (Safe)"];
    [[_preferencesMathPolicyPopup itemAtIndex:0] setTag:OMMarkdownMathRenderingPolicyStyledText];
    [_preferencesMathPolicyPopup addItemWithTitle:@"Disabled (Literal $...$)"];
    [[_preferencesMathPolicyPopup itemAtIndex:1] setTag:OMMarkdownMathRenderingPolicyDisabled];
    [_preferencesMathPolicyPopup addItemWithTitle:@"External Tools (LaTeX)"];
    [[_preferencesMathPolicyPopup itemAtIndex:2] setTag:OMMarkdownMathRenderingPolicyExternalTools];
    [_preferencesMathPolicyPopup setTarget:self];
    [_preferencesMathPolicyPopup setAction:@selector(preferencesMathPolicyChanged:)];
    [card addSubview:_preferencesMathPolicyPopup];
    OMDAddPreferencesPopupOverlay(card, _preferencesMathPolicyPopup);

    rowY += metrics.preferencesControlHeight + metrics.preferencesRowGap;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 5.0, rowLabelWidth, 20.0),
                                        @"Diagrams",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesDiagramPolicyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX,
                                                                                      rowY,
                                                                                      controlWidth,
                                                                                      metrics.preferencesControlHeight)
                                                                pullsDown:NO];
    OMDConfigurePreferencesPopup(_preferencesDiagramPolicyPopup, metrics);
    [_preferencesDiagramPolicyPopup addItemWithTitle:@"Drawn Diagrams"];
    [[_preferencesDiagramPolicyPopup itemAtIndex:0] setTag:OMMarkdownDiagramRenderingPolicyNative];
    [_preferencesDiagramPolicyPopup addItemWithTitle:@"Diagram Source"];
    [[_preferencesDiagramPolicyPopup itemAtIndex:1] setTag:OMMarkdownDiagramRenderingPolicySourceCode];
    [_preferencesDiagramPolicyPopup setTarget:self];
    [_preferencesDiagramPolicyPopup setAction:@selector(preferencesDiagramPolicyChanged:)];
    [card addSubview:_preferencesDiagramPolicyPopup];
    OMDAddPreferencesPopupOverlay(card, _preferencesDiagramPolicyPopup);

    rowY += metrics.preferencesControlHeight + 8.0;
    [card addSubview:OMDStaticTextField(NSMakeRect(controlX,
                                                   rowY,
                                                   controlWidth,
                                                   metrics.preferencesNoteHeight),
                                        @"Mermaid erDiagram blocks draw as entity-relationship diagrams; other mermaid types stay as code.",
                                        OMDPreferencesNoteFont(metrics),
                                        noteColor,
                                        NSLeftTextAlignment,
                                        YES)];
    rowY += metrics.preferencesNoteHeight - metrics.preferencesControlHeight;

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
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0,
                                                          0.0,
                                                          NSWidth([view bounds]),
                                                          metrics.preferencesEditingCardHeight));

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
    CGFloat fontLabelWidth = 48.0;
    CGFloat fontButtonWidth = metrics.preferencesSmallButtonWidth + 24.0;
    [card addSubview:OMDStaticTextField(NSMakeRect(pad, rowY + 3.0, fontLabelWidth, 20.0),
                                        @"Font",
                                        OMDPreferencesLabelFont(metrics),
                                        titleColor,
                                        NSLeftTextAlignment,
                                        NO)];
    _preferencesSourceFontField = [OMDStaticTextField(NSMakeRect(pad + fontLabelWidth,
                                                                 rowY + 3.0,
                                                                 sectionWidth - fontLabelWidth - fontButtonWidth - 8.0,
                                                                 20.0),
                                                      [_delegate sourceEditorFontDescription],
                                                      OMDPreferencesLabelFont(metrics),
                                                      noteColor,
                                                      NSLeftTextAlignment,
                                                      NO) retain];
    [card addSubview:_preferencesSourceFontField];
    _preferencesSourceFontButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad + sectionWidth - fontButtonWidth,
                                                                              rowY,
                                                                              fontButtonWidth,
                                                                              metrics.preferencesControlHeight)];
    [_preferencesSourceFontButton setTitle:@"Choose..."];
    [_preferencesSourceFontButton setBezelStyle:NSRoundedBezelStyle];
    [_preferencesSourceFontButton setTarget:self];
    [_preferencesSourceFontButton setAction:@selector(chooseSourceEditorFont:)];
    [card addSubview:_preferencesSourceFontButton];

    rowY += 36.0;
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

    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
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

- (void)showPreferences
{
    if (_preferencesPanel == nil) {
        OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
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
        NSString *themeName = [_delegate themePreference];
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
        OMDLayoutDensityMode mode = [_delegate effectiveLayoutDensityMode];
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
        [_preferencesScrollSpeedSlider setDoubleValue:[_delegate scrollSpeedPreference]];
    }

    if (_preferencesSplitSyncModePopup != nil) {
        OMDSplitSyncMode splitSyncMode = [_delegate currentSplitSyncMode];
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

    OMMarkdownMathRenderingPolicy policy = [_delegate currentMathRenderingPolicy];
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
    if (_preferencesDiagramPolicyPopup != nil) {
        OMMarkdownDiagramRenderingPolicy diagramPolicy = [_delegate currentDiagramRenderingPolicy];
        NSInteger selectedIndex = 0;
        NSInteger itemCount = [_preferencesDiagramPolicyPopup numberOfItems];
        NSInteger index = 0;
        for (; index < itemCount; index++) {
            id<NSMenuItem> item = [_preferencesDiagramPolicyPopup itemAtIndex:index];
            if ([item tag] == (NSInteger)diagramPolicy) {
                selectedIndex = index;
                break;
            }
        }
        [_preferencesDiagramPolicyPopup selectItemAtIndex:selectedIndex];
    }
    if (_preferencesAllowRemoteImagesButton != nil) {
        [_preferencesAllowRemoteImagesButton setState:([_delegate isAllowRemoteImagesEnabled] ? NSOnState : NSOffState)];
    }
    if (_preferencesFormattingBarButton != nil) {
        [_preferencesFormattingBarButton setState:([_delegate isFormattingBarEnabledPreference] ? NSOnState : NSOffState)];
    }
    if (_preferencesSourceFontField != nil) {
        [_preferencesSourceFontField setStringValue:[_delegate sourceEditorFontDescription]];
    }
    if (_preferencesWordSelectionShimButton != nil) {
        [_preferencesWordSelectionShimButton setState:([_delegate isWordSelectionModifierShimEnabled] ? NSOnState : NSOffState)];
    }
    if (_preferencesSourceVimKeyBindingsButton != nil) {
        [_preferencesSourceVimKeyBindingsButton setState:([_delegate isSourceVimKeyBindingsEnabled] ? NSOnState : NSOffState)];
    }
    if (_preferencesSyntaxHighlightingButton != nil) {
        [_preferencesSyntaxHighlightingButton setState:([_delegate isSourceSyntaxHighlightingEnabled] ? NSOnState : NSOffState)];
    }
    BOOL sourceHighlightingEnabled = [_delegate isSourceSyntaxHighlightingEnabled];
    if (_preferencesSourceHighContrastButton != nil) {
        [_preferencesSourceHighContrastButton setState:([_delegate isSourceHighlightHighContrastEnabled] ? NSOnState : NSOffState)];
        [_preferencesSourceHighContrastButton setEnabled:sourceHighlightingEnabled];
    }
    if (_preferencesSourceAccentColorWell != nil) {
        NSColor *accent = [_delegate sourceHighlightAccentColor];
        if (accent == nil) {
            accent = [NSColor colorWithCalibratedRed:0.00 green:0.36 blue:0.74 alpha:1.0];
        }
        [_preferencesSourceAccentColorWell setColor:accent];
        [_preferencesSourceAccentColorWell setEnabled:sourceHighlightingEnabled];
    }
    if (_preferencesSourceAccentResetButton != nil) {
        [_preferencesSourceAccentResetButton setEnabled:(sourceHighlightingEnabled && [_delegate sourceHighlightAccentColor] != nil)];
    }

    BOOL treeSitterAvailable = [_delegate isTreeSitterAvailable];
    if (_preferencesRendererSyntaxHighlightingButton != nil) {
        [_preferencesRendererSyntaxHighlightingButton setEnabled:treeSitterAvailable];
        [_preferencesRendererSyntaxHighlightingButton setState:([_delegate isRendererSyntaxHighlightingEnabled] ? NSOnState : NSOffState)];
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
        NSString *root = [[_delegate explorerController] explorerLocalRootPathPreference];
        [_preferencesExplorerLocalRootField setStringValue:(root != nil ? root : @"")];
    }
    if (_preferencesExplorerMaxFileSizeField != nil) {
        NSUInteger megabytes = [[_delegate explorerController] explorerMaxOpenFileSizeBytes] / (1024U * 1024U);
        [_preferencesExplorerMaxFileSizeField setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)megabytes]];
    }
    if (_preferencesExplorerListFontSizeField != nil) {
        CGFloat listFontSize = [[_delegate explorerController] explorerListFontSizePreference];
        if (fabs(listFontSize - round(listFontSize)) < 0.05) {
            [_preferencesExplorerListFontSizeField setStringValue:[NSString stringWithFormat:@"%.0f", listFontSize]];
        } else {
            [_preferencesExplorerListFontSizeField setStringValue:[NSString stringWithFormat:@"%.1f", listFontSize]];
        }
    }
}

- (void)preferencesSplitSyncModeChanged:(id)sender
{
    id<NSMenuItem> item = [_preferencesSplitSyncModePopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMDSplitSyncModeLinkedScrolling;
    [_delegate setSplitSyncModePreference:OMDSplitSyncModeFromInteger(tag)];
}

- (void)preferencesLayoutModeChanged:(id)sender
{
    (void)sender;
    id<NSMenuItem> item = [_preferencesLayoutModePopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMDLayoutDensityModeBalanced;
    [_delegate setLayoutDensityPreference:OMDClampedLayoutDensityMode(tag)];
}

- (void)preferencesScrollSpeedChanged:(id)sender
{
    (void)sender;
    CGFloat scrollSpeed = (_preferencesScrollSpeedSlider != nil
                           ? (CGFloat)[_preferencesScrollSpeedSlider doubleValue]
                           : [_delegate scrollSpeedPreference]);
    [_delegate setScrollSpeedPreference:scrollSpeed];
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
    [_delegate setMathRenderingPolicyPreference:policy];
}

- (void)preferencesDiagramPolicyChanged:(id)sender
{
    id<NSMenuItem> item = [_preferencesDiagramPolicyPopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMMarkdownDiagramRenderingPolicyNative;
    [_delegate setDiagramRenderingPolicyPreference:OMDDiagramRenderingPolicyFromInteger(tag)];
}

- (void)preferencesAllowRemoteImagesChanged:(id)sender
{
    BOOL allow = [_preferencesAllowRemoteImagesButton state] == NSOnState;
    [_delegate setAllowRemoteImagesPreference:allow];
}

- (void)preferencesWordSelectionShimChanged:(id)sender
{
    BOOL enabled = [_preferencesWordSelectionShimButton state] == NSOnState;
    [_delegate setWordSelectionModifierShimEnabled:enabled];
}

- (void)preferencesFormattingBarChanged:(id)sender
{
    BOOL enabled = [_preferencesFormattingBarButton state] == NSOnState;
    [_delegate setFormattingBarEnabledPreference:enabled];
}

- (void)preferencesSourceVimKeyBindingsChanged:(id)sender
{
    BOOL enabled = [_preferencesSourceVimKeyBindingsButton state] == NSOnState;
    [_delegate setSourceVimKeyBindingsEnabled:enabled];
}

- (void)preferencesSyntaxHighlightingChanged:(id)sender
{
    BOOL enabled = [_preferencesSyntaxHighlightingButton state] == NSOnState;
    [_delegate setSourceSyntaxHighlightingEnabled:enabled];
}

- (void)preferencesSourceHighContrastChanged:(id)sender
{
    BOOL enabled = [_preferencesSourceHighContrastButton state] == NSOnState;
    [_delegate setSourceHighlightHighContrastEnabled:enabled];
}

- (void)preferencesSourceAccentColorChanged:(id)sender
{
    [_delegate setSourceHighlightAccentColor:[_preferencesSourceAccentColorWell color]];
}

- (void)preferencesSourceAccentReset:(id)sender
{
    [_delegate setSourceHighlightAccentColor:nil];
}

- (void)preferencesRendererSyntaxHighlightingChanged:(id)sender
{
    if (![_delegate isTreeSitterAvailable]) {
        return;
    }
    BOOL enabled = [_preferencesRendererSyntaxHighlightingButton state] == NSOnState;
    [_delegate setRendererSyntaxHighlightingPreferenceEnabled:enabled];
}

- (void)preferencesThemeChanged:(id)sender
{
    (void)sender;
    id<NSMenuItem> item = [_preferencesThemePopup selectedItem];
    NSString *themeName = [item representedObject];
    if (themeName == nil || [themeName length] == 0) {
        [_delegate setThemePreference:nil];
    } else {
        [_delegate setThemePreference:themeName];
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
            startingPath = [[_delegate explorerController] explorerLocalRootPathPreference];
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
    [[_delegate explorerController] setExplorerLocalRootPathPreference:path];
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
    [[_delegate explorerController] setExplorerMaxOpenFileSizeMBPreference:(NSUInteger)megabytes];
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
    [[_delegate explorerController] setExplorerListFontSizePreference:fontSize];
    [self syncPreferencesPanelFromSettings];
}

- (void)reloadThemePopupItems
{
    if (_preferencesThemePopup == nil) {
        return;
    }
    [_preferencesThemePopup removeAllItems];
    [_preferencesThemePopup addItemWithTitle:@"GNUstep"];
    [[_preferencesThemePopup itemAtIndex:0] setRepresentedObject:@""];
    NSArray *themes = [_delegate availableThemeNames];
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

@end
