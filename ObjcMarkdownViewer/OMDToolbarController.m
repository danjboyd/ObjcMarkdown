// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDToolbarController.h"
#import "OMDLayoutMetrics.h"
#import "OMDControlSupport.h"
#import "OMDToolbarViews.h"
#import "OMDViewerColors.h"
#import "OMDViewerImages.h"

#include <math.h>

<<<<<<< Updated upstream
// Labels fit the theme's text (OMDChromeBoldFont).
#define OMDToolbarLabelHeight MAX(20.0, OMDChromeLineHeight(OMDChromeBoldFont()) + 2.0)
=======
// Toolbar labels in the theme's bold system font, as tall as it needs.
static NSFont *OMDToolbarLabelFont(void)
{
    return [NSFont boldSystemFontOfSize:0.0];
}

static NSSize OMDToolbarLabelTextSize(NSString *text)
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:OMDToolbarLabelFont() forKey:NSFontAttributeName];
    NSSize size = [text sizeWithAttributes:attributes];
    return NSMakeSize(ceil(size.width), ceil(size.height));
}

static CGFloat OMDToolbarLabelHeight(void)
{
    return MAX(20.0, OMDToolbarLabelTextSize(@"Ag").height + 2.0);
}
>>>>>>> Stashed changes

// Off Windows the toolbar is a few GNOME-style buttons around a flexible
// space; with the Adwaita theme's header bar (GnomeThemeHeaderBarToolbar in
// the Info.plist) it sits in the title row. Windows keeps its own toolbar.
static BOOL OMDUsesCompactToolbar(void)
{
#if defined(_WIN32)
    return NO;
#else
    return YES;
#endif
}

static BOOL OMDShouldUseToolbarFlexibleSpace(void)
{
#if defined(_WIN32) || defined(__APPLE__)
    return YES;
#else
    return NO;
#endif
}

@interface OMDToolbarController ()
- (void)toolbarActionControlChanged:(id)sender;
- (void)showRecentDocumentsMenu:(id)sender;
@end

@implementation OMDToolbarController

- (instancetype)initWithDelegate:(id<OMDToolbarControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [_toolbarPrimaryActionsContainer release];
    [_toolbarFileActionsControl release];
    [_toolbarUtilityActionsControl release];
    [_zoomSlider release];
    [_zoomLabel release];
    [_zoomResetButton release];
    [_zoomContainer release];
    [_modeContainer release];
    [_modeControl release];
    [_modeLabel release];
    [_previewStatusLabel release];
    [super dealloc];
}

- (void)showRecentDocumentsMenu:(id)sender
{
    (void)sender;
    NSMenu *menu = [_delegate recentDocumentsMenu];
    NSEvent *event = [NSApp currentEvent];
    NSView *view = [[event window] contentView];
    if (menu == nil || event == nil || view == nil) {
        return;
    }
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (NSSegmentedControl *)modeControl
{
    return _modeControl;
}

- (NSTextField *)modeLabel
{
    return _modeLabel;
}

- (NSTextField *)previewStatusLabel
{
    return _previewStatusLabel;
}

- (NSSlider *)zoomSlider
{
    return _zoomSlider;
}

- (NSTextField *)zoomLabel
{
    return _zoomLabel;
}

- (void)installInWindow:(NSWindow *)window
{
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:@"ObjcMarkdownViewerToolbar"] autorelease];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
    [toolbar setDisplayMode:(OMDUsesCompactToolbar() ? NSToolbarDisplayModeIconOnly : NSToolbarDisplayModeIconAndLabel)];
    [toolbar setSizeMode:NSToolbarSizeModeRegular];
    [window setToolbar:toolbar];
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
            _toolbarPrimaryActionsContainer = [[OMDToolbarToolTipView alloc] initWithFrame:NSMakeRect(0, 0, containerWidth, OMDToolbarItemHeight)];

            _toolbarFileActionsControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, controlY, fileActionsWidth, OMDToolbarControlHeight)];
            [_toolbarFileActionsControl setSegmentCount:3];
            [_toolbarFileActionsControl setSegmentStyle:NSSegmentStyleRounded];
            [[_toolbarFileActionsControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
            [_toolbarFileActionsControl setTarget:self];
            [_toolbarFileActionsControl setAction:@selector(toolbarActionControlChanged:)];
            [_toolbarFileActionsControl setTag:1];
            [_toolbarFileActionsControl setImage:OMDSymbolicImageNamed(@"omd-sidebar-show-symbolic") forSegment:0];
            [_toolbarFileActionsControl setImage:OMDSymbolicImageNamed(@"omd-document-open-symbolic") forSegment:1];
            [_toolbarFileActionsControl setImage:OMDSymbolicImageNamed(@"omd-document-save-symbolic") forSegment:2];
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
            [_toolbarUtilityActionsControl setImage:OMDSymbolicImageNamed(@"omd-document-export-symbolic") forSegment:0];
            [_toolbarUtilityActionsControl setImage:OMDSymbolicImageNamed(@"omd-document-print-symbolic") forSegment:1];
            [_toolbarUtilityActionsControl setImage:OMDSymbolicImageNamed(@"omd-preferences-symbolic") forSegment:2];
            [[_toolbarUtilityActionsControl cell] setToolTip:@"Export the current document as PDF" forSegment:0];
            [[_toolbarUtilityActionsControl cell] setToolTip:@"Print the current document" forSegment:1];
            [[_toolbarUtilityActionsControl cell] setToolTip:@"Open Preferences" forSegment:2];
            [_toolbarUtilityActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:0];
            [_toolbarUtilityActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:1];
            [_toolbarUtilityActionsControl setWidth:OMDToolbarActionSegmentWidth forSegment:2];
            [_toolbarPrimaryActionsContainer addSubview:_toolbarUtilityActionsControl];

            // GNUstep doesn't show a segment's own tooltip; the container's
            // rects do, as for the mode and zoom controls.
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:@"Show the file explorer"
                                                                    forRect:NSMakeRect(0.0, controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:@"Open a Markdown file"
                                                                    forRect:NSMakeRect(OMDToolbarActionSegmentWidth, controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:@"No unsaved changes to save"
                                                                    forRect:NSMakeRect(OMDToolbarActionSegmentWidth * 2.0, controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:@"Export the current document as PDF"
                                                                    forRect:NSMakeRect(fileActionsWidth + OMDToolbarActionGroupSpacing, controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:@"Print the current document"
                                                                    forRect:NSMakeRect(fileActionsWidth + OMDToolbarActionGroupSpacing + OMDToolbarActionSegmentWidth, controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:@"Open Preferences"
                                                                    forRect:NSMakeRect(fileActionsWidth + OMDToolbarActionGroupSpacing + (OMDToolbarActionSegmentWidth * 2.0), controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];

            [self updateToolbarActionControlsState];
        }

        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"PrimaryActions"] autorelease];
        [item setView:_toolbarPrimaryActionsContainer];
        [item setMinSize:NSMakeSize(containerWidth, OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(containerWidth, OMDToolbarItemHeight)];
        [item setLabel:@""];
        [item setPaletteLabel:@"Actions"];
        return item;
    }

    if ([identifier isEqualToString:@"ToggleExplorer"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ToggleExplorer"] autorelease];
        [item setLabel:@"Explorer"];
        [item setPaletteLabel:@"Explorer"];
        [item setToolTip:@"Show or hide the file explorer"];
        [item setTarget:_delegate];
        [item setAction:@selector(toggleExplorerSidebar:)];
        [item setImage:OMDSymbolicImageNamed(@"omd-sidebar-show-symbolic")];
        return item;
    }

    if ([identifier isEqualToString:@"OpenDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"OpenDocument"] autorelease];
        [item setLabel:@"Open"];
        [item setPaletteLabel:@"Open"];
        [item setToolTip:@"Open a Markdown file"];
        [item setTarget:_delegate];
        [item setAction:@selector(openDocument:)];
        NSImage *image = OMDSymbolicImageNamed(@"omd-document-open-symbolic");
        if (!OMDUsesCompactToolbar()) {
            [item setImage:image];
            return item;
        }
        // In the header bar Open is a split button: the icon opens the
        // open panel, the arrow beside it lists the recent documents.
        CGFloat openWidth = 34.0;
        CGFloat arrowWidth = 16.0;
        NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, openWidth + arrowWidth, OMDToolbarItemHeight)] autorelease];
        NSButton *openButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, openWidth, OMDToolbarItemHeight)] autorelease];
        [openButton setBordered:NO];
        [openButton setImagePosition:NSImageOnly];
        [openButton setImage:image];
        [openButton setToolTip:@"Open a Markdown file"];
        [openButton setTarget:_delegate];
        [openButton setAction:@selector(openDocument:)];
        [container addSubview:openButton];
        NSButton *arrowButton = [[[NSButton alloc] initWithFrame:NSMakeRect(openWidth, 0.0, arrowWidth, OMDToolbarItemHeight)] autorelease];
        [arrowButton setBordered:NO];
        [arrowButton setImagePosition:NSImageOnly];
        [arrowButton setImage:OMDSymbolicImageNamed(@"omd-pan-down-symbolic")];
        [arrowButton setToolTip:@"Open a recent file"];
        [arrowButton setTarget:self];
        [arrowButton setAction:@selector(showRecentDocumentsMenu:)];
        [container addSubview:arrowButton];
        [item setView:container];
        [item setMinSize:[container frame].size];
        [item setMaxSize:[container frame].size];
        return item;
    }

    if ([identifier isEqualToString:@"SaveDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"SaveDocument"] autorelease];
        [item setLabel:@"Save"];
        [item setPaletteLabel:@"Save"];
        [item setToolTip:@"Save current markdown changes"];
        [item setTarget:_delegate];
        [item setAction:@selector(saveDocument:)];
        [item setImage:OMDSymbolicImageNamed(@"omd-document-save-symbolic")];
        return item;
    }

    if ([identifier isEqualToString:@"Preferences"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Preferences"] autorelease];
        [item setLabel:@"Prefs"];
        [item setPaletteLabel:@"Preferences"];
        [item setToolTip:@"Open Preferences"];
        [item setTarget:_delegate];
        [item setAction:@selector(showPreferences:)];
        [item setImage:OMDSymbolicImageNamed(@"omd-preferences-symbolic")];
        return item;
    }

    if ([identifier isEqualToString:@"PrintDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"PrintDocument"] autorelease];
        [item setLabel:@"Print"];
        [item setPaletteLabel:@"Print"];
        [item setToolTip:@"Print the current document"];
        [item setTarget:_delegate];
        [item setAction:@selector(printDocument:)];
        [item setImage:OMDSymbolicImageNamed(@"omd-document-print-symbolic")];
        return item;
    }

    if ([identifier isEqualToString:@"ExportDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ExportDocument"] autorelease];
        [item setLabel:@"Export PDF"];
        [item setPaletteLabel:@"Export PDF"];
        [item setToolTip:@"Export the current document as PDF (more formats in File > Export)"];
        [item setTarget:_delegate];
        [item setAction:@selector(exportDocumentAsPDF:)];
        [item setImage:OMDSymbolicImageNamed(@"omd-document-export-symbolic")];
        return item;
    }

    if ([identifier isEqualToString:@"ModeControls"] && OMDUsesCompactToolbar()) {
        CGFloat statusWidth = 132.0;
        CGFloat switcherWidth = 182.0;
        CGFloat containerWidth = statusWidth + 8.0 + switcherWidth;
        if (_modeContainer == nil) {
            CGFloat labelY = floor((OMDToolbarItemHeight - OMDToolbarLabelHeight()) * 0.5);
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            _modeContainer = [[OMDToolbarToolTipView alloc] initWithFrame:NSMakeRect(0, 0, containerWidth, OMDToolbarItemHeight)];
            // Vim's mode and command line, beside the switcher.
            _previewStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, labelY, statusWidth, OMDToolbarLabelHeight())];
            [_previewStatusLabel setBezeled:NO];
            [_previewStatusLabel setEditable:NO];
            [_previewStatusLabel setSelectable:NO];
            [_previewStatusLabel setDrawsBackground:NO];
            [_previewStatusLabel setAlignment:NSRightTextAlignment];
<<<<<<< Updated upstream
            [_previewStatusLabel setFont:OMDChromeBoldFont()];
=======
            [_previewStatusLabel setFont:OMDToolbarLabelFont()];
>>>>>>> Stashed changes
            [_previewStatusLabel setStringValue:@""];
            [_previewStatusLabel setHidden:YES];
            [_modeContainer addSubview:_previewStatusLabel];

            CGFloat switcherX = statusWidth + 8.0;
            _modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(switcherX, controlY, switcherWidth, OMDToolbarControlHeight)];
            [_modeControl setSegmentCount:3];
            [_modeControl setLabel:@"Read" forSegment:0];
            [_modeControl setLabel:@"Edit" forSegment:1];
            [_modeControl setLabel:@"Split" forSegment:2];
            [[_modeControl cell] setToolTip:@"Read (Ctrl+1)" forSegment:0];
            [[_modeControl cell] setToolTip:@"Edit (Ctrl+2)" forSegment:1];
            [[_modeControl cell] setToolTip:@"Split (Ctrl+3)" forSegment:2];
            [_modeControl setTarget:_delegate];
            [_modeControl setAction:@selector(modeControlChanged:)];
            [_modeContainer addSubview:_modeControl];
            CGFloat segment = floor(switcherWidth / 3.0);
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:@"Read (Ctrl+1)"
                                                        forRect:NSMakeRect(switcherX, controlY, segment, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:@"Edit (Ctrl+2)"
                                                        forRect:NSMakeRect(switcherX + segment, controlY, segment, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:@"Split (Ctrl+3)"
                                                        forRect:NSMakeRect(switcherX + 2.0 * segment, controlY, switcherWidth - 2.0 * segment, OMDToolbarControlHeight)];
            [_delegate updateModeControlSelection];
            [_delegate updatePreviewStatusIndicator];
        }
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ModeControls"] autorelease];
        [item setView:_modeContainer];
        [item setMinSize:NSMakeSize(containerWidth, OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(containerWidth, OMDToolbarItemHeight)];
        [item setLabel:@""];
        [item setPaletteLabel:@"View"];
        return item;
    }

    if ([identifier isEqualToString:@"ModeControls"]) {
        if (_modeContainer == nil) {
            CGFloat labelY = floor((OMDToolbarItemHeight - OMDToolbarLabelHeight()) * 0.5);
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            CGFloat captionWidth = OMDToolbarLabelTextSize(@"View").width + 4.0;
            CGFloat switcherX = captionWidth + 4.0;
            _modeContainer = [[OMDToolbarToolTipView alloc] initWithFrame:NSMakeRect(0, 0, switcherX + 182.0 + 6.0 + 132.0, OMDToolbarItemHeight)];
            _modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, labelY, captionWidth, OMDToolbarLabelHeight())];
            [_modeLabel setBezeled:NO];
            [_modeLabel setEditable:NO];
            [_modeLabel setSelectable:NO];
            [_modeLabel setDrawsBackground:NO];
            [_modeLabel setAlignment:NSRightTextAlignment];
<<<<<<< Updated upstream
            [_modeLabel setFont:OMDChromeBoldFont()];
=======
            [_modeLabel setFont:OMDToolbarLabelFont()];
>>>>>>> Stashed changes
            [_modeLabel setTextColor:[_delegate modeLabelTextColor]];
            [_modeLabel setStringValue:@"View"];
            [_modeContainer addSubview:_modeLabel];

            _modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(switcherX, controlY, 182, OMDToolbarControlHeight)];
            [_modeControl setSegmentCount:3];
            [_modeControl setLabel:@"Read" forSegment:0];
            [_modeControl setLabel:@"Edit" forSegment:1];
            [_modeControl setLabel:@"Split" forSegment:2];
            [[_modeControl cell] setToolTip:@"Read mode" forSegment:0];
            [[_modeControl cell] setToolTip:@"Edit mode" forSegment:1];
            [[_modeControl cell] setToolTip:@"Split mode" forSegment:2];
            [_modeControl setTarget:_delegate];
            [_modeControl setAction:@selector(modeControlChanged:)];
            [_modeContainer addSubview:_modeControl];
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:@"Read mode"
                                                        forRect:NSMakeRect(switcherX, controlY, 60.0, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:@"Edit mode"
                                                        forRect:NSMakeRect(switcherX + 60.0, controlY, 61.0, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:@"Split mode"
                                                        forRect:NSMakeRect(switcherX + 121.0, controlY, 61.0, OMDToolbarControlHeight)];

            _previewStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(switcherX + 182.0 + 6.0, labelY, 132, OMDToolbarLabelHeight())];
            [_previewStatusLabel setBezeled:NO];
            [_previewStatusLabel setEditable:NO];
            [_previewStatusLabel setSelectable:NO];
            [_previewStatusLabel setDrawsBackground:NO];
            [_previewStatusLabel setAlignment:NSLeftTextAlignment];
<<<<<<< Updated upstream
            [_previewStatusLabel setFont:OMDChromeBoldFont()];
=======
            [_previewStatusLabel setFont:OMDToolbarLabelFont()];
>>>>>>> Stashed changes
            [_previewStatusLabel setStringValue:@""];
            [_previewStatusLabel setHidden:YES];
            [_modeContainer addSubview:_previewStatusLabel];

            [_delegate updateModeControlSelection];
            [_delegate updatePreviewStatusIndicator];
        }
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ModeControls"] autorelease];
        [item setView:_modeContainer];
        [item setMinSize:NSMakeSize(NSWidth([_modeContainer frame]), OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(NSWidth([_modeContainer frame]), OMDToolbarItemHeight)];
        [item setLabel:@""];
        [item setPaletteLabel:@"View"];
        return item;
    }

    if ([identifier isEqualToString:@"ZoomControls"]) {
        if (_zoomContainer == nil) {
            CGFloat labelY = floor((OMDToolbarItemHeight - OMDToolbarLabelHeight()) * 0.5);
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            _zoomContainer = [[OMDToolbarToolTipView alloc] initWithFrame:NSMakeRect(0, 0, 300, OMDToolbarItemHeight)];

            _zoomLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, labelY, 55, OMDToolbarLabelHeight())];
            [_zoomLabel setBezeled:NO];
            [_zoomLabel setEditable:NO];
            [_zoomLabel setSelectable:NO];
            [_zoomLabel setDrawsBackground:NO];
            [_zoomLabel setAlignment:NSRightTextAlignment];
<<<<<<< Updated upstream
            [_zoomLabel setFont:OMDChromeBoldFont()];
=======
            [_zoomLabel setFont:OMDToolbarLabelFont()];
>>>>>>> Stashed changes
            [_zoomLabel setToolTip:@"Current zoom"];

            _zoomSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(60, controlY, 130, OMDToolbarControlHeight)];
            [_zoomSlider setMinValue:50];
            [_zoomSlider setMaxValue:200];
            [_zoomSlider setDoubleValue:[_delegate previewZoomScale] * 100.0];
            [_zoomSlider setTarget:_delegate];
            [_zoomSlider setAction:@selector(zoomSliderChanged:)];
            [_zoomSlider setToolTip:@"Adjust zoom"];

            _zoomResetButton = [[NSButton alloc] initWithFrame:NSMakeRect(205, controlY, 90, OMDToolbarControlHeight)];
            [_zoomResetButton setTitle:@"100%"];
            [_zoomResetButton setBezelStyle:NSRoundedBezelStyle];
<<<<<<< Updated upstream
            [_zoomResetButton setFont:OMDChromeFont()];
=======
>>>>>>> Stashed changes
            [_zoomResetButton setTarget:_delegate];
            [_zoomResetButton setAction:@selector(zoomReset:)];
            [_zoomResetButton setToolTip:@"Reset zoom to 100%"];

            [_zoomContainer addSubview:_zoomLabel];
            [_zoomContainer addSubview:_zoomSlider];
            [_zoomContainer addSubview:_zoomResetButton];
            [(OMDToolbarToolTipView *)_zoomContainer setToolTip:@"Current zoom"
                                                        forRect:NSMakeRect(0.0, labelY, 55.0, OMDToolbarLabelHeight())];
            [(OMDToolbarToolTipView *)_zoomContainer setToolTip:@"Adjust zoom"
                                                        forRect:NSMakeRect(60.0, controlY, 130.0, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_zoomContainer setToolTip:@"Reset zoom to 100%"
                                                        forRect:NSMakeRect(205.0, controlY, 90.0, OMDToolbarControlHeight)];
            [_delegate updateZoomLabel];
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
    if (OMDUsesCompactToolbar()) {
        // Export, Print and Preferences are in the menus (the header bar's
        // main menu with the Adwaita theme); zoom is View > Zoom In / Out.
        return [NSArray arrayWithObjects:@"ToggleExplorer",
                                         @"OpenDocument",
                                         @"SaveDocument",
                                         NSToolbarFlexibleSpaceItemIdentifier,
                                         @"ModeControls",
                                         nil];
    }
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
                [_delegate toggleExplorerSidebar:control];
                break;
            case 1:
                [_delegate openDocument:control];
                break;
            case 2:
                [_delegate saveDocument:control];
                break;
            default:
                break;
        }
    } else if (control == _toolbarUtilityActionsControl) {
        switch (segment) {
            case 0:
                [_delegate exportDocumentAsPDF:control];
                break;
            case 1:
                [_delegate printDocument:control];
                break;
            case 2:
                [_delegate showPreferences:control];
                break;
            default:
                break;
        }
    }

    [control setSelectedSegment:-1];
    [self updateToolbarActionControlsState];
}

- (void)updateToolbarActionControlsState
{
    BOOL hasDocument = [_delegate hasLoadedDocument];
    BOOL canSaveDocument = [_delegate canSaveCurrentDocument];
    if (_hasLastToolbarActionState &&
        _lastToolbarHadDocument == hasDocument &&
        _lastToolbarCanSaveDocument == canSaveDocument &&
        _lastToolbarExplorerSidebarVisible == [_delegate isExplorerSidebarVisible]) {
        return;
    }
    _lastToolbarHadDocument = hasDocument;
    _lastToolbarCanSaveDocument = canSaveDocument;
    _lastToolbarExplorerSidebarVisible = [_delegate isExplorerSidebarVisible];
    _hasLastToolbarActionState = YES;

    if (_toolbarFileActionsControl != nil) {
        [_toolbarFileActionsControl setEnabled:YES forSegment:0];
        [_toolbarFileActionsControl setEnabled:YES forSegment:1];
        [_toolbarFileActionsControl setEnabled:canSaveDocument forSegment:2];
        [[_toolbarFileActionsControl cell] setToolTip:([_delegate isExplorerSidebarVisible]
                                                        ? @"Hide the file explorer"
                                                        : @"Show the file explorer")
                                           forSegment:0];
        [[_toolbarFileActionsControl cell] setToolTip:(canSaveDocument
                                                       ? @"Save current markdown changes"
                                                       : @"No unsaved changes to save")
                                           forSegment:2];
        if ([_toolbarPrimaryActionsContainer isKindOfClass:[OMDToolbarToolTipView class]]) {
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:([_delegate isExplorerSidebarVisible]
                                                                              ? @"Hide the file explorer"
                                                                              : @"Show the file explorer")
                                                                    forRect:NSMakeRect(0.0, controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_toolbarPrimaryActionsContainer setToolTip:(canSaveDocument
                                                                              ? @"Save current markdown changes"
                                                                              : @"No unsaved changes to save")
                                                                    forRect:NSMakeRect(OMDToolbarActionSegmentWidth * 2.0, controlY, OMDToolbarActionSegmentWidth, OMDToolbarControlHeight)];
        }
    }
    if (_toolbarUtilityActionsControl != nil) {
        [_toolbarUtilityActionsControl setEnabled:hasDocument forSegment:0];
        [_toolbarUtilityActionsControl setEnabled:hasDocument forSegment:1];
        [_toolbarUtilityActionsControl setEnabled:YES forSegment:2];
    }
    // GNUstep doesn't redraw a segmented control when a segment's enabled
    // state changes.
    [_toolbarFileActionsControl setNeedsDisplay:YES];
    [_toolbarUtilityActionsControl setNeedsDisplay:YES];
}

@end
