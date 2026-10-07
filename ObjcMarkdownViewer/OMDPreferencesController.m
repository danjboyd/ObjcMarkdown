// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDPreferencesController.h"
#import "OMDExplorerController.h"
#import "OMDFillViews.h"
#import "OMDPanelSelection.h"
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

static CGFloat OMDPreferencesPanelWidthForMetrics(OMDLayoutMetrics metrics)
{
    CGFloat width = metrics.preferencesWindowWidth;
    if (width < 720.0) {
        width = 720.0;
    }
    return ceil(width);
}

// The panel's text is the theme's (#85): bold system for section titles,
// the system font for subtitles, labels and controls, the small system
// font for notes. The layout density changes spacing only.
static NSFont *OMDPreferencesSectionTitleFont(OMDLayoutMetrics metrics)
{
    (void)metrics;
    return OMDChromeBoldFont();
}

static NSFont *OMDPreferencesSectionSubtitleFont(OMDLayoutMetrics metrics)
{
    (void)metrics;
    return OMDChromeFont();
}

static NSFont *OMDPreferencesLabelFont(OMDLayoutMetrics metrics)
{
    (void)metrics;
    return OMDChromeFont();
}

static NSFont *OMDPreferencesNoteFont(OMDLayoutMetrics metrics)
{
    (void)metrics;
    return OMDChromeSmallFont();
}

static NSFont *OMDPreferencesSectionControlFont(OMDLayoutMetrics metrics)
{
    (void)metrics;
    return OMDChromeFont();
}

// The height text takes in font, wrapped to width.
static CGFloat OMDPreferencesTextHeight(NSString *text, NSFont *font, CGFloat width)
{
    CGFloat line = OMDChromeLineHeight(font);
    if ([text length] == 0 || font == nil || width < 1.0) {
        return line;
    }
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:text
                                                         attributes:[NSDictionary dictionaryWithObject:font
                                                                                                forKey:NSFontAttributeName]] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, 1.0e7)] autorelease];
    [container setLineFragmentPadding:2.0];
    [layoutManager addTextContainer:container];
    [storage addLayoutManager:layoutManager];
    [layoutManager glyphRangeForTextContainer:container];
    CGFloat height = ceil(NSHeight([layoutManager usedRectForTextContainer:container]));
    return MAX(line, height) + 2.0;
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

// Laying a card out from the top: rows are as tall as their control or
// text needs in the theme's fonts, and the card is sized to fit at the end.
typedef struct {
    CGFloat pad;
    CGFloat width;          // the card's content width
    CGFloat controlHeight;
    CGFloat rowGap;
    CGFloat labelHeight;
    CGFloat checkboxHeight;
    NSFont *labelFont;
    NSFont *noteFont;
    NSColor *titleColor;
    NSColor *noteColor;
} OMDPreferencesCardLayout;

static OMDPreferencesCardLayout OMDPreferencesCardLayoutMake(NSView *card, OMDLayoutMetrics metrics)
{
    OMDPreferencesCardLayout layout;
    layout.pad = metrics.preferencesCardPadding;
    layout.width = NSWidth([card bounds]) - (layout.pad * 2.0);
    layout.labelFont = OMDPreferencesLabelFont(metrics);
    layout.noteFont = OMDPreferencesNoteFont(metrics);
    layout.labelHeight = OMDChromeLineHeight(layout.labelFont) + 2.0;
    layout.controlHeight = MAX(metrics.preferencesControlHeight, layout.labelHeight + 8.0);
    layout.rowGap = metrics.preferencesRowGap;
    layout.checkboxHeight = MAX(22.0, layout.labelHeight + 2.0);
    layout.titleColor = OMDResolvedControlTextColor();
    layout.noteColor = OMDResolvedMutedTextColor();
    return layout;
}

// The section's title and subtitle; returns where the first row goes.
static CGFloat OMDPreferencesAddCardHeader(NSView *card,
                                           NSString *title,
                                           NSString *subtitle,
                                           OMDPreferencesCardLayout layout,
                                           OMDLayoutMetrics metrics)
{
    NSFont *titleFont = OMDPreferencesSectionTitleFont(metrics);
    NSFont *subtitleFont = OMDPreferencesSectionSubtitleFont(metrics);
    CGFloat titleHeight = OMDChromeLineHeight(titleFont) + 2.0;
    CGFloat subtitleHeight = OMDPreferencesTextHeight(subtitle, subtitleFont, layout.width);
    [card addSubview:OMDStaticTextField(NSMakeRect(layout.pad, layout.pad, layout.width, titleHeight),
                                        title, titleFont, layout.titleColor, NSLeftTextAlignment, NO)];
    [card addSubview:OMDStaticTextField(NSMakeRect(layout.pad, layout.pad + titleHeight + 2.0,
                                                   layout.width, subtitleHeight),
                                        subtitle, subtitleFont, layout.noteColor, NSLeftTextAlignment, YES)];
    return layout.pad + titleHeight + 2.0 + subtitleHeight + layout.rowGap + 4.0;
}

// A row's label, centred on a control of the row's height.
static void OMDPreferencesAddRowLabel(NSView *card,
                                      NSString *text,
                                      CGFloat x,
                                      CGFloat rowY,
                                      CGFloat width,
                                      NSColor *color,
                                      OMDPreferencesCardLayout layout)
{
    CGFloat y = rowY + floor((layout.controlHeight - layout.labelHeight) / 2.0);
    [card addSubview:OMDStaticTextField(NSMakeRect(x, y, width, layout.labelHeight),
                                        text, layout.labelFont, color, NSLeftTextAlignment, NO)];
}

// A wrapped note; returns its height.
static CGFloat OMDPreferencesAddNote(NSView *card,
                                     NSString *text,
                                     CGFloat x,
                                     CGFloat y,
                                     CGFloat width,
                                     OMDPreferencesCardLayout layout)
{
    CGFloat height = OMDPreferencesTextHeight(text, layout.noteFont, width);
    [card addSubview:OMDStaticTextField(NSMakeRect(x, y, width, height),
                                        text, layout.noteFont, layout.noteColor, NSLeftTextAlignment, YES)];
    return height;
}

static NSButton *OMDPreferencesCheckbox(NSString *title,
                                        CGFloat x,
                                        CGFloat y,
                                        CGFloat width,
                                        id target,
                                        SEL action,
                                        OMDPreferencesCardLayout layout)
{
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, width, layout.checkboxHeight)];
    [button setButtonType:NSSwitchButton];
    [button setTitle:title];
    [button setFont:layout.labelFont];
    [button setTarget:target];
    [button setAction:action];
    return button;
}

// Sizes the card (its box) to height and returns it.
static CGFloat OMDPreferencesFinishCard(NSView *card, CGFloat height)
{
    NSView *box = [card superview];
    height = ceil(height);
    if (box != nil) {
        NSRect frame = [box frame];
        frame.size.height = height;
        [box setFrame:frame];
    }
    return height;
}

@interface OMDPreferencesController ()
- (void)preferencesExplorerLocalRootChanged:(id)sender;
- (void)preferencesExplorerMaxFileSizeChanged:(id)sender;
- (void)preferencesExplorerListFontSizeChanged:(id)sender;
- (void)preferencesDiagramPolicyChanged:(id)sender;
- (void)releasePreferencesPanelControls;
- (void)rebuildPreferencesPanelContent;
- (void)normalizePreferencesPanelFrameForSize:(NSSize)size;
- (CGFloat)buildPreferencesAppearanceSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (CGFloat)buildPreferencesExplorerSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (CGFloat)buildPreferencesPreviewSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (CGFloat)buildPreferencesEditorSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics;
- (NSView *)preferencesSectionDocumentView:(OMDPreferencesSection)section
                                     width:(CGFloat)width
                                   metrics:(OMDLayoutMetrics)metrics
                                    height:(CGFloat *)height;
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

- (CGFloat)buildPreferencesAppearanceSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0, 0.0, NSWidth([view bounds]), 400.0));
    OMDPreferencesCardLayout layout = OMDPreferencesCardLayoutMake(card, metrics);
    CGFloat pad = layout.pad;
    CGFloat rowLabelWidth = MIN(metrics.preferencesLabelWidth + 20.0, floor(layout.width * 0.28));
    CGFloat controlX = pad + rowLabelWidth + 12.0;
    CGFloat controlWidth = layout.width - rowLabelWidth - 12.0;
#if defined(GNUSTEP)
    NSString *appearanceSummary = @"Choose the active GNUstep theme and how roomy the interface should feel.";
    NSString *appearanceNote = @"GNUstep's default scroll speed is at the left. Theme changes apply on next launch; layout mode and scroll speed update immediately.";
#else
    // On macOS the system draws the app (light or dark is the system's
    // setting), so there is no theme to choose.
    NSString *appearanceSummary = @"Choose how roomy the interface should feel.";
    NSString *appearanceNote = @"The default scroll speed is at the left. Layout mode and scroll speed update immediately.";
#endif
    CGFloat rowY = OMDPreferencesAddCardHeader(card,
                                               @"Appearance",
                                               appearanceSummary,
                                               layout, metrics);

#if defined(GNUSTEP)
    OMDPreferencesAddRowLabel(card, @"GNUstep Theme", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesThemePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, rowY, controlWidth, layout.controlHeight)
                                                         pullsDown:NO];
    OMDConfigurePreferencesPopup(_preferencesThemePopup, metrics);
    [_preferencesThemePopup setTarget:self];
    [_preferencesThemePopup setAction:@selector(preferencesThemeChanged:)];
    [_preferencesThemePopup setToolTip:@"Theme changes apply after relaunch."];
    [card addSubview:_preferencesThemePopup];
    rowY += layout.controlHeight + layout.rowGap;
#endif

    OMDPreferencesAddRowLabel(card, @"Layout Mode", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesLayoutModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, rowY, controlWidth, layout.controlHeight)
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

    rowY += layout.controlHeight + layout.rowGap;
    OMDPreferencesAddRowLabel(card, @"Scroll Speed", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesScrollSpeedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(controlX, rowY, controlWidth, layout.controlHeight)];
    [_preferencesScrollSpeedSlider setMinValue:OMDScrollSpeedMinimum];
    [_preferencesScrollSpeedSlider setMaxValue:OMDScrollSpeedMaximum];
    [_preferencesScrollSpeedSlider setContinuous:YES];
    [_preferencesScrollSpeedSlider setTarget:self];
    [_preferencesScrollSpeedSlider setAction:@selector(preferencesScrollSpeedChanged:)];
    [_preferencesScrollSpeedSlider setToolTip:@"Adjust how far the app scrolls for each wheel or trackpad step."];
    [card addSubview:_preferencesScrollSpeedSlider];

    rowY += layout.controlHeight + layout.rowGap;
    rowY += OMDPreferencesAddNote(card,
                                  appearanceNote,
                                  pad, rowY, layout.width, layout);
    return OMDPreferencesFinishCard(card, rowY + pad);
}

- (CGFloat)buildPreferencesExplorerSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0, 0.0, NSWidth([view bounds]), 400.0));
    OMDPreferencesCardLayout layout = OMDPreferencesCardLayoutMake(card, metrics);
    CGFloat pad = layout.pad;
    CGFloat rowLabelWidth = MIN(metrics.preferencesLabelWidth + 20.0, floor(layout.width * 0.24));
    CGFloat controlX = pad + rowLabelWidth + 12.0;
    CGFloat controlWidth = layout.width - rowLabelWidth - 12.0;
    CGFloat rowY = OMDPreferencesAddCardHeader(card,
                                               @"Explorer",
                                               @"The explorer shows the open document's repository or folder, and the default folder when no document is open.",
                                               layout, metrics);

    OMDPreferencesAddRowLabel(card, @"Default Folder", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    CGFloat browseWidth = metrics.preferencesSmallButtonWidth;
    CGFloat rootFieldWidth = controlWidth - browseWidth - 8.0;
    if (rootFieldWidth < 180.0) {
        rootFieldWidth = controlWidth;
        browseWidth = 0.0;
    }
    _preferencesExplorerLocalRootField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX, rowY, rootFieldWidth, layout.controlHeight)];
    [_preferencesExplorerLocalRootField setFont:layout.labelFont];
    [_preferencesExplorerLocalRootField setTarget:self];
    [_preferencesExplorerLocalRootField setAction:@selector(preferencesExplorerLocalRootChanged:)];
    [card addSubview:_preferencesExplorerLocalRootField];
    if (browseWidth > 0.0) {
        NSButton *browseButton = [[[NSButton alloc] initWithFrame:NSMakeRect(controlX + rootFieldWidth + 8.0,
                                                                             rowY,
                                                                             browseWidth,
                                                                             layout.controlHeight)] autorelease];
        [browseButton setTitle:@"Browse..."];
        [browseButton setFont:layout.labelFont];
        [browseButton setBezelStyle:NSRoundedBezelStyle];
        [browseButton setTarget:self];
        [browseButton setAction:@selector(preferencesExplorerLocalRootChanged:)];
        [card addSubview:browseButton];
    }

    CGFloat unitX = controlX + metrics.preferencesSmallFieldWidth + 6.0;
    rowY += layout.controlHeight + layout.rowGap;
    OMDPreferencesAddRowLabel(card, @"Max File Size", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesExplorerMaxFileSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX, rowY,
                                                                                          metrics.preferencesSmallFieldWidth,
                                                                                          layout.controlHeight)];
    [_preferencesExplorerMaxFileSizeField setFont:layout.labelFont];
    [_preferencesExplorerMaxFileSizeField setTarget:self];
    [_preferencesExplorerMaxFileSizeField setAction:@selector(preferencesExplorerMaxFileSizeChanged:)];
    [card addSubview:_preferencesExplorerMaxFileSizeField];
    OMDPreferencesAddRowLabel(card, @"MB", unitX, rowY, 40.0, layout.noteColor, layout);

    rowY += layout.controlHeight + layout.rowGap;
    OMDPreferencesAddRowLabel(card, @"List Font", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesExplorerListFontSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX, rowY,
                                                                                           metrics.preferencesSmallFieldWidth,
                                                                                           layout.controlHeight)];
    [_preferencesExplorerListFontSizeField setFont:layout.labelFont];
    [_preferencesExplorerListFontSizeField setTarget:self];
    [_preferencesExplorerListFontSizeField setAction:@selector(preferencesExplorerListFontSizeChanged:)];
    [card addSubview:_preferencesExplorerListFontSizeField];
    OMDPreferencesAddRowLabel(card, @"pt", unitX, rowY, 40.0, layout.noteColor, layout);

    rowY += layout.controlHeight;
    return OMDPreferencesFinishCard(card, rowY + pad);
}

- (CGFloat)buildPreferencesPreviewSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0, 0.0, NSWidth([view bounds]), 600.0));
    OMDPreferencesCardLayout layout = OMDPreferencesCardLayoutMake(card, metrics);
    CGFloat pad = layout.pad;
    CGFloat rowLabelWidth = MIN(metrics.preferencesLabelWidth + 24.0, floor(layout.width * 0.24));
    CGFloat controlX = pad + rowLabelWidth + 12.0;
    CGFloat controlWidth = layout.width - rowLabelWidth - 12.0;
    CGFloat rowY = OMDPreferencesAddCardHeader(card,
                                               @"Preview",
                                               @"Tune preview sync, math rendering, remote media, and code-block highlighting together.",
                                               layout, metrics);

    OMDPreferencesAddRowLabel(card, @"Split Sync", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesSplitSyncModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, rowY, controlWidth, layout.controlHeight)
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

    rowY += layout.controlHeight + 6.0;
    rowY += OMDPreferencesAddNote(card,
                                  @"Linked Scrolling follows pane scroll; Follow Caret tracks cursor and selection moves.",
                                  controlX, rowY, controlWidth, layout);

    rowY += layout.rowGap;
    OMDPreferencesAddRowLabel(card, @"Math", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesMathPolicyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, rowY, controlWidth, layout.controlHeight)
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

    rowY += layout.controlHeight + layout.rowGap;
    OMDPreferencesAddRowLabel(card, @"Diagrams", pad, rowY, rowLabelWidth, layout.titleColor, layout);
    _preferencesDiagramPolicyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, rowY, controlWidth, layout.controlHeight)
                                                                pullsDown:NO];
    OMDConfigurePreferencesPopup(_preferencesDiagramPolicyPopup, metrics);
    [_preferencesDiagramPolicyPopup addItemWithTitle:@"Drawn Diagrams"];
    [[_preferencesDiagramPolicyPopup itemAtIndex:0] setTag:OMMarkdownDiagramRenderingPolicyNative];
    [_preferencesDiagramPolicyPopup addItemWithTitle:@"Diagram Source"];
    [[_preferencesDiagramPolicyPopup itemAtIndex:1] setTag:OMMarkdownDiagramRenderingPolicySourceCode];
    [_preferencesDiagramPolicyPopup setTarget:self];
    [_preferencesDiagramPolicyPopup setAction:@selector(preferencesDiagramPolicyChanged:)];
    [card addSubview:_preferencesDiagramPolicyPopup];

    rowY += layout.controlHeight + 6.0;
    rowY += OMDPreferencesAddNote(card,
                                  @"Mermaid flowchart and erDiagram blocks are drawn; other Mermaid types show their source.",
                                  controlX, rowY, controlWidth, layout);

    rowY += layout.rowGap;
    _preferencesAllowRemoteImagesButton = OMDPreferencesCheckbox(@"Allow Remote Images", pad, rowY, layout.width,
                                                                 self, @selector(preferencesAllowRemoteImagesChanged:), layout);
    [card addSubview:_preferencesAllowRemoteImagesButton];

    rowY += layout.checkboxHeight + 6.0;
    _preferencesRendererSyntaxHighlightingButton = OMDPreferencesCheckbox(@"Renderer Syntax Highlighting (Code Blocks)",
                                                                          pad, rowY, layout.width, self,
                                                                          @selector(preferencesRendererSyntaxHighlightingChanged:),
                                                                          layout);
    [card addSubview:_preferencesRendererSyntaxHighlightingButton];

    // Its text is set later (it names the highlighter in use): room for two lines.
    rowY += layout.checkboxHeight + 4.0;
    CGFloat noteWidth = layout.width - 22.0;
    CGFloat noteHeight = OMDChromeLineHeight(layout.noteFont) * 2.0 + 4.0;
    _preferencesRendererSyntaxHighlightingNoteLabel = [OMDStaticTextField(NSMakeRect(pad + 22.0, rowY, noteWidth, noteHeight),
                                                                          @"", layout.noteFont, layout.noteColor,
                                                                          NSLeftTextAlignment, YES) retain];
    [card addSubview:_preferencesRendererSyntaxHighlightingNoteLabel];
    rowY += noteHeight;
    return OMDPreferencesFinishCard(card, rowY + pad);
}

- (CGFloat)buildPreferencesEditorSectionInView:(NSView *)view metrics:(OMDLayoutMetrics)metrics
{
    NSView *card = OMDAddPreferencesCard(view, NSMakeRect(0.0, 0.0, NSWidth([view bounds]), 600.0));
    OMDPreferencesCardLayout layout = OMDPreferencesCardLayoutMake(card, metrics);
    CGFloat pad = layout.pad;
    CGFloat rowY = OMDPreferencesAddCardHeader(card,
                                               @"Editor",
                                               @"Tweak source-editor behavior without crowding the main workspace.",
                                               layout, metrics);

    NSDictionary *labelAttributes = [NSDictionary dictionaryWithObject:layout.labelFont forKey:NSFontAttributeName];
    CGFloat fontLabelWidth = ceil([@"Font" sizeWithAttributes:labelAttributes].width) + 12.0;
    CGFloat fontButtonWidth = metrics.preferencesSmallButtonWidth + 24.0;
    OMDPreferencesAddRowLabel(card, @"Font", pad, rowY, fontLabelWidth, layout.titleColor, layout);
    CGFloat fontFieldY = rowY + floor((layout.controlHeight - layout.labelHeight) / 2.0);
    _preferencesSourceFontField = [OMDStaticTextField(NSMakeRect(pad + fontLabelWidth,
                                                                 fontFieldY,
                                                                 layout.width - fontLabelWidth - fontButtonWidth - 8.0,
                                                                 layout.labelHeight),
                                                      [_delegate sourceEditorFontDescription],
                                                      layout.labelFont,
                                                      layout.noteColor,
                                                      NSLeftTextAlignment,
                                                      NO) retain];
    [card addSubview:_preferencesSourceFontField];
    _preferencesSourceFontButton = [[NSButton alloc] initWithFrame:NSMakeRect(pad + layout.width - fontButtonWidth,
                                                                              rowY,
                                                                              fontButtonWidth,
                                                                              layout.controlHeight)];
    [_preferencesSourceFontButton setTitle:@"Choose..."];
    [_preferencesSourceFontButton setFont:layout.labelFont];
    [_preferencesSourceFontButton setBezelStyle:NSRoundedBezelStyle];
    [_preferencesSourceFontButton setTarget:self];
    [_preferencesSourceFontButton setAction:@selector(chooseSourceEditorFont:)];
    [card addSubview:_preferencesSourceFontButton];

    CGFloat checkboxStep = layout.checkboxHeight + 6.0;
    rowY += layout.controlHeight + layout.rowGap;
    _preferencesFormattingBarButton = OMDPreferencesCheckbox(@"Show Formatting Bar in Edit and Split", pad, rowY, layout.width,
                                                             self, @selector(preferencesFormattingBarChanged:), layout);
    [card addSubview:_preferencesFormattingBarButton];

    rowY += checkboxStep;
    _preferencesWordSelectionShimButton = OMDPreferencesCheckbox(@"Ctrl/Cmd+Shift+Arrow Selects Words", pad, rowY, layout.width,
                                                                 self, @selector(preferencesWordSelectionShimChanged:), layout);
    [card addSubview:_preferencesWordSelectionShimButton];

    rowY += checkboxStep;
    _preferencesSourceVimKeyBindingsButton = OMDPreferencesCheckbox(@"Enable Vim Key Bindings", pad, rowY, layout.width,
                                                                    self, @selector(preferencesSourceVimKeyBindingsChanged:), layout);
    [card addSubview:_preferencesSourceVimKeyBindingsButton];

    rowY += checkboxStep;
    _preferencesSyntaxHighlightingButton = OMDPreferencesCheckbox(@"Source Syntax Highlighting", pad, rowY, layout.width,
                                                                  self, @selector(preferencesSyntaxHighlightingChanged:), layout);
    [card addSubview:_preferencesSyntaxHighlightingButton];

    rowY += checkboxStep;
    _preferencesSourceHighContrastButton = OMDPreferencesCheckbox(@"High Contrast Source Highlighting", pad + 20.0, rowY,
                                                                  layout.width - 20.0, self,
                                                                  @selector(preferencesSourceHighContrastChanged:), layout);
    [card addSubview:_preferencesSourceHighContrastButton];

    rowY += checkboxStep + 4.0;
    CGFloat accentX = pad + 20.0;
    CGFloat accentRowWidth = layout.width - 20.0;
    [card addSubview:OMDStaticTextField(NSMakeRect(accentX, rowY, accentRowWidth, layout.labelHeight),
                                        @"Accent Color", layout.labelFont, layout.titleColor, NSLeftTextAlignment, NO)];

    rowY += layout.labelHeight + 4.0;
    CGFloat accentResetWidth = metrics.preferencesSmallButtonWidth;
    CGFloat accentWellWidth = accentRowWidth - accentResetWidth - 8.0;
    CGFloat accentResetX = accentX + accentRowWidth - accentResetWidth;
    BOOL stackAccentReset = NO;
    if (accentWellWidth < 160.0) {
        accentWellWidth = accentRowWidth;
        stackAccentReset = YES;
    }
    _preferencesSourceAccentColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(accentX, rowY, accentWellWidth, layout.controlHeight)];
    [_preferencesSourceAccentColorWell setTarget:self];
    [_preferencesSourceAccentColorWell setAction:@selector(preferencesSourceAccentColorChanged:)];
    [card addSubview:_preferencesSourceAccentColorWell];
    if (stackAccentReset) {
        rowY += layout.controlHeight + 8.0;
    }
    _preferencesSourceAccentResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(accentResetX, rowY, accentResetWidth, layout.controlHeight)];
    [_preferencesSourceAccentResetButton setTitle:@"Reset"];
    [_preferencesSourceAccentResetButton setFont:layout.labelFont];
    [_preferencesSourceAccentResetButton setBezelStyle:NSRoundedBezelStyle];
    [_preferencesSourceAccentResetButton setTarget:self];
    [_preferencesSourceAccentResetButton setAction:@selector(preferencesSourceAccentReset:)];
    [card addSubview:_preferencesSourceAccentResetButton];

    rowY += layout.controlHeight;
    return OMDPreferencesFinishCard(card, rowY + pad);
}

// The section's card, laid out at width; returns the view and, in
// height, how tall the card came out.
- (NSView *)preferencesSectionDocumentView:(OMDPreferencesSection)section
                                     width:(CGFloat)width
                                   metrics:(OMDLayoutMetrics)metrics
                                    height:(CGFloat *)height
{
    OMDFlippedFillView *documentView = [[[OMDFlippedFillView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 100.0)] autorelease];
    [documentView setAutoresizingMask:NSViewWidthSizable];
    [documentView setFillColor:OMDResolvedPanelBackdropColor()];
    CGFloat contentHeight = 0.0;
    switch (section) {
        case OMDPreferencesSectionExplorer:
            contentHeight = [self buildPreferencesExplorerSectionInView:documentView metrics:metrics];
            break;
        case OMDPreferencesSectionPreview:
            contentHeight = [self buildPreferencesPreviewSectionInView:documentView metrics:metrics];
            break;
        case OMDPreferencesSectionEditor:
            contentHeight = [self buildPreferencesEditorSectionInView:documentView metrics:metrics];
            break;
        case OMDPreferencesSectionAppearance:
        default:
            contentHeight = [self buildPreferencesAppearanceSectionInView:documentView metrics:metrics];
            break;
    }
    [documentView setFrameSize:NSMakeSize(width, contentHeight)];
    if (height != NULL) {
        *height = contentHeight;
    }
    return documentView;
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
    NSFont *sectionFont = OMDPreferencesSectionControlFont(metrics);
    CGFloat sectionControlHeight = MAX((metrics.scale > 1.05 ? 36.0 : 32.0), OMDChromeLineHeight(sectionFont) + 14.0);

    // The width first (the screen may limit it), then the section laid out
    // at that width, then the height it needs.
    [self normalizePreferencesPanelFrameForSize:NSMakeSize(OMDPreferencesPanelWidthForMetrics(metrics),
                                                           NSHeight([[_preferencesPanel contentView] bounds]))];
    CGFloat contentWidth = NSWidth([[_preferencesPanel contentView] bounds]) - (outerPadding * 2.0);
    if (contentWidth < 420.0) {
        contentWidth = 420.0;
    }
    CGFloat sectionHeight = 0.0;
    NSView *documentView = [self preferencesSectionDocumentView:selectedSection
                                                          width:contentWidth
                                                        metrics:metrics
                                                         height:&sectionHeight];
    CGFloat contentY = outerPadding + sectionControlHeight + 16.0;
    CGFloat panelHeight = MAX(metrics.preferencesWindowMinHeight, ceil(contentY + sectionHeight + outerPadding));
    [self normalizePreferencesPanelFrameForSize:NSMakeSize(OMDPreferencesPanelWidthForMetrics(metrics), panelHeight)];

    NSRect panelBounds = [[_preferencesPanel contentView] bounds];
    OMDFlippedFillView *rootView = [[[OMDFlippedFillView alloc] initWithFrame:panelBounds] autorelease];
    [rootView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [rootView setFillColor:OMDResolvedPanelBackdropColor()];

    _preferencesSectionControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(outerPadding,
                                                                                      outerPadding,
                                                                                      contentWidth,
                                                                                      sectionControlHeight)];
    [_preferencesSectionControl setAutoresizingMask:NSViewWidthSizable];
    if ([_preferencesSectionControl respondsToSelector:@selector(setFont:)]) {
        [_preferencesSectionControl setFont:sectionFont];
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

    NSRect contentRect = NSMakeRect(outerPadding,
                                    contentY,
                                    contentWidth,
                                    MAX(160.0, NSHeight(panelBounds) - contentY - outerPadding));
    OMDFlippedFillView *container = [[[OMDFlippedFillView alloc] initWithFrame:contentRect] autorelease];
    [container setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [container setFillColor:OMDResolvedPanelBackdropColor()];
    if (sectionHeight > NSHeight(contentRect)) {
        // Taller than the screen allows: the section scrolls.
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
    [rootView addSubview:container];

    [_preferencesPanel setContentView:rootView];
}

- (void)showPreferences
{
    if (_preferencesPanel == nil) {
        OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
        NSRect frame = NSMakeRect(160,
                                  140,
                                  OMDPreferencesPanelWidthForMetrics(metrics),
                                  metrics.preferencesWindowMinHeight);
        _preferencesPanel = [[NSPanel alloc] initWithContentRect:frame
                                                        styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        NSString *title = @"Preferences";
#if !defined(GNUSTEP)
        // macOS 13 calls them Settings.
        if (@available(macOS 13.0, *)) {
            title = @"Settings";
        }
        // A Mac settings window stays up when another app is in front.
        [_preferencesPanel setHidesOnDeactivate:NO];
#endif
        [_preferencesPanel setTitle:title];
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
            NSMenuItem *item = (NSMenuItem *)[_preferencesThemePopup itemAtIndex:index];
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
            NSMenuItem *newItem = (NSMenuItem *)[_preferencesThemePopup itemAtIndex:[_preferencesThemePopup numberOfItems] - 1];
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
            NSMenuItem *item = (NSMenuItem *)[_preferencesLayoutModePopup itemAtIndex:index];
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
            NSMenuItem *splitItem = (NSMenuItem *)[_preferencesSplitSyncModePopup itemAtIndex:splitIndex];
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
            NSMenuItem *item = (NSMenuItem *)[_preferencesMathPolicyPopup itemAtIndex:index];
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
            NSMenuItem *item = (NSMenuItem *)[_preferencesDiagramPolicyPopup itemAtIndex:index];
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
    NSMenuItem *item = (NSMenuItem *)[_preferencesSplitSyncModePopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMDSplitSyncModeLinkedScrolling;
    [_delegate setSplitSyncModePreference:OMDSplitSyncModeFromInteger(tag)];
}

- (void)preferencesLayoutModeChanged:(id)sender
{
    (void)sender;
    NSMenuItem *item = (NSMenuItem *)[_preferencesLayoutModePopup selectedItem];
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
    NSMenuItem *item = (NSMenuItem *)[_preferencesMathPolicyPopup selectedItem];
    NSInteger tag = item != nil ? [item tag] : (NSInteger)OMMarkdownMathRenderingPolicyStyledText;
    OMMarkdownMathRenderingPolicy policy = OMDMathRenderingPolicyFromInteger(tag);
    [_delegate setMathRenderingPolicyPreference:policy];
}

- (void)preferencesDiagramPolicyChanged:(id)sender
{
    NSMenuItem *item = (NSMenuItem *)[_preferencesDiagramPolicyPopup selectedItem];
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
    NSMenuItem *item = (NSMenuItem *)[_preferencesThemePopup selectedItem];
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
        [panel setTitle:@"Choose Default Folder"];
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
    // Empty: back to the theme's size.
    CGFloat fontSize = (CGFloat)[OMDTrimmedString(value) doubleValue];
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
        NSMenuItem *item = (NSMenuItem *)[_preferencesThemePopup itemAtIndex:[_preferencesThemePopup numberOfItems] - 1];
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
