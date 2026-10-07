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
    CGFloat preferencesWindowWidth;
    CGFloat preferencesWindowMinHeight;
    CGFloat preferencesOuterPadding;
    CGFloat preferencesColumnGap;
    CGFloat preferencesCardPadding;
    CGFloat preferencesRowGap;
    CGFloat preferencesLabelWidth;
    CGFloat preferencesControlHeight;
    CGFloat preferencesSmallFieldWidth;
    CGFloat preferencesSmallButtonWidth;
} OMDLayoutMetrics;

OMDLayoutDensityMode OMDClampedLayoutDensityMode(NSInteger rawValue);
BOOL OMDDefaultFormattingBarEnabledForMode(OMDLayoutDensityMode mode);
OMDLayoutMetrics OMDLayoutMetricsForMode(OMDLayoutDensityMode mode);

// The theme's fonts for the app's chrome (labels, tabs, bars), so its type
// sizes apply; the layout density changes spacing, not type. The document
// and editor fonts are separate.
NSFont *OMDChromeFont(void);
NSFont *OMDChromeBoldFont(void);
NSFont *OMDChromeSmallFont(void);
// The height a line of text in this font needs.
CGFloat OMDChromeLineHeight(NSFont *font);
