// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDLayoutMetrics.h"

static const CGFloat OMDFormattingBarHeight = 32.0;
static const CGFloat OMDFormattingBarInsetX = 8.0;
static const CGFloat OMDFormattingBarControlHeight = 22.0;
static const CGFloat OMDFormattingBarPopupWidth = 84.0;
static const CGFloat OMDFormattingBarButtonWidth = 22.0;
static const CGFloat OMDFormattingBarButtonWideWidth = 24.0;
static const CGFloat OMDFormattingBarControlSpacing = 2.0;
static const CGFloat OMDFormattingBarGroupSpacing = 6.0;
static const CGFloat OMDExplorerSidebarDefaultWidth = 300.0;
static const CGFloat OMDTabStripHeight = 30.0;
static const CGFloat OMDPreviewCanvasHorizontalMargin = 32.0;

OMDLayoutDensityMode OMDClampedLayoutDensityMode(NSInteger rawValue)
{
    if (rawValue == OMDLayoutDensityModeCompact) {
        return OMDLayoutDensityModeCompact;
    }
    if (rawValue == OMDLayoutDensityModeAdwaita) {
        return OMDLayoutDensityModeAdwaita;
    }
    return OMDLayoutDensityModeBalanced;
}

BOOL OMDDefaultFormattingBarEnabledForMode(OMDLayoutDensityMode mode)
{
    return mode != OMDLayoutDensityModeAdwaita;
}

OMDLayoutMetrics OMDLayoutMetricsForMode(OMDLayoutDensityMode mode)
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
    metrics.preferencesCardPadding = 18.0;
    metrics.preferencesRowGap = 12.0;
    metrics.preferencesNoteHeight = 30.0;
    metrics.preferencesLabelWidth = 120.0;
    metrics.preferencesControlHeight = 28.0;
    metrics.preferencesSmallFieldWidth = 56.0;
    metrics.preferencesSmallButtonWidth = 80.0;
    metrics.preferencesAppearanceCardHeight = 236.0;
    metrics.preferencesExplorerCardHeight = 196.0;
    metrics.preferencesPreviewCardHeight = 132.0;
    metrics.preferencesRenderingCardHeight = 236.0;
    metrics.preferencesEditingCardHeight = 402.0;

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
        metrics.preferencesExplorerCardHeight = 182.0;
        metrics.preferencesPreviewCardHeight = 124.0;
        metrics.preferencesRenderingCardHeight = 224.0;
        metrics.preferencesEditingCardHeight = 382.0;
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
        metrics.preferencesCardPadding = 22.0;
        metrics.preferencesRowGap = 14.0;
        metrics.preferencesNoteHeight = 34.0;
        metrics.preferencesLabelWidth = 128.0;
        metrics.preferencesControlHeight = 32.0;
        metrics.preferencesSmallFieldWidth = 64.0;
        metrics.preferencesSmallButtonWidth = 96.0;
        metrics.preferencesAppearanceCardHeight = 270.0;
        metrics.preferencesExplorerCardHeight = 220.0;
        metrics.preferencesPreviewCardHeight = 156.0;
        metrics.preferencesRenderingCardHeight = 272.0;
        metrics.preferencesEditingCardHeight = 460.0;
    }

    return metrics;
}
