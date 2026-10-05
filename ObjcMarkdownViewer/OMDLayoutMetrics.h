// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, OMDLayoutDensityMode) {
    OMDLayoutDensityModeCompact = 0,
    OMDLayoutDensityModeBalanced = 1,
    OMDLayoutDensityModeAdwaita = 2
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

OMDLayoutDensityMode OMDClampedLayoutDensityMode(NSInteger rawValue);
BOOL OMDDefaultFormattingBarEnabledForMode(OMDLayoutDensityMode mode);
OMDLayoutMetrics OMDLayoutMetricsForMode(OMDLayoutDensityMode mode);
