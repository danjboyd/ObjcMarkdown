// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDToolbarController.h"
#import "OMDToolbarViews.h"
#import "OMDViewerImages.h"

@interface OMDToolbarController ()
#if defined(GNUSTEP)
- (void)openSegmentClicked:(id)sender;
#endif
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
    [_toolbar release];
    [_modeContainer release];
    [_modeControl release];
    [super dealloc];
}

#if defined(GNUSTEP)
- (void)openSegmentClicked:(id)sender
{
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = [control selectedSegment];
    // GNUstep's segmented cell has no momentary tracking: the clicked
    // segment stays selected, and drawn so, until it is deselected.
    if (segment >= 0) {
        [control setSelected:NO forSegment:segment];
    }
    if (segment != 1) {
        [_delegate openDocument:sender];
        return;
    }
    NSMenu *menu = [_delegate recentDocumentsMenu];
    NSEvent *event = [NSApp currentEvent];
    NSView *view = [[event window] contentView];
    if (menu == nil || event == nil || view == nil) {
        return;
    }
    [control setMenu:menu forSegment:1];
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}
#else
// The Open item's menu is filled each time it opens, so it lists the
// recent documents of the moment.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    NSMenu *recent = [_delegate recentDocumentsMenu];
    NSArray *items = [[[recent itemArray] copy] autorelease];
    for (NSMenuItem *menuItem in items) {
        [recent removeItem:menuItem];
        [menu addItem:menuItem];
    }
}
#endif

- (NSSegmentedControl *)modeControl
{
    return _modeControl;
}

- (void)installInWindow:(NSWindow *)window
{
    [_toolbar release];
    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"ObjcMarkdownViewerToolbar"];
    [_toolbar setDelegate:self];
    [_toolbar setAllowsUserCustomization:NO];
    [_toolbar setAutosavesConfiguration:NO];
#if !defined(GNUSTEP)
    // On macOS the system's default shows labels; Mac unified toolbars are
    // icon-only. On GNUstep the theme picks the display mode.
    [_toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
#endif
    [_toolbar setSizeMode:NSToolbarSizeModeRegular];
    [window setToolbar:_toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
      itemForItemIdentifier:(NSString *)identifier
  willBeInsertedIntoToolbar:(BOOL)flag
{
    (void)toolbar;
    (void)flag;

    if ([identifier isEqualToString:@"ToggleExplorer"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ToggleExplorer"] autorelease];
        [item setLabel:@"Explorer"];
        [item setPaletteLabel:@"Explorer"];
        [item setToolTip:@"Show or hide the file explorer"];
        [item setTarget:_delegate];
        [item setAction:@selector(toggleExplorerSidebar:)];
        [item setImage:OMDSymbolicImageNamedForCommand(@"omd-sidebar-show-symbolic", @"Explorer")];
        return item;
    }

    if ([identifier isEqualToString:@"OpenDocument"]) {
#if !defined(GNUSTEP)
        // The system's split button: the item opens the open panel, its
        // arrow lists the recent documents.
        NSMenuToolbarItem *item = [[[NSMenuToolbarItem alloc] initWithItemIdentifier:@"OpenDocument"] autorelease];
        NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Open Recent"] autorelease];
        [menu setDelegate:self];
        [item setMenu:menu];
        [item setImage:OMDSymbolicImageNamedForCommand(@"omd-document-open-symbolic", @"Open")];
#else
        // One control for Open and its recent documents, so the theme can
        // present it as a split button: a momentary segmented control whose
        // second segment carries the menu. GNUstep doesn't pop up a
        // segment's menu itself, so openSegmentClicked: does.
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"OpenDocument"] autorelease];
        CGFloat openWidth = 34.0;
        CGFloat arrowWidth = 18.0;
        NSSegmentedControl *control = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, openWidth + arrowWidth, OMDToolbarControlHeight)] autorelease];
        [control setSegmentCount:2];
        [[control cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
        [control setWidth:openWidth forSegment:0];
        [control setWidth:arrowWidth forSegment:1];
        [control setImage:OMDSymbolicImageNamedForCommand(@"omd-document-open-symbolic", @"Open") forSegment:0];
        [control setImage:OMDSymbolicImageNamedForCommand(@"omd-pan-down-symbolic", @"Open Recent") forSegment:1];
        [control setMenu:[[[NSMenu alloc] initWithTitle:@"Open Recent"] autorelease] forSegment:1];
        [control setTarget:self];
        [control setAction:@selector(openSegmentClicked:)];
        // GNUstep doesn't show a segment's own tooltip; the container's
        // rects do.
        OMDToolbarToolTipView *container = [[[OMDToolbarToolTipView alloc] initWithFrame:NSMakeRect(0.0, 0.0, openWidth + arrowWidth, OMDToolbarControlHeight)] autorelease];
        [container addSubview:control];
        [container setToolTip:@"Open a Markdown file"
                      forRect:NSMakeRect(0.0, 0.0, openWidth, OMDToolbarControlHeight)];
        [container setToolTip:@"Open a recent file"
                      forRect:NSMakeRect(openWidth, 0.0, arrowWidth, OMDToolbarControlHeight)];
        [item setView:container];
        [item setMinSize:[container frame].size];
        [item setMaxSize:[container frame].size];
#endif
        [item setLabel:@"Open"];
        [item setPaletteLabel:@"Open"];
        [item setToolTip:@"Open a Markdown file"];
        [item setTarget:_delegate];
        [item setAction:@selector(openDocument:)];
        return item;
    }

    if ([identifier isEqualToString:@"SaveDocument"]) {
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"SaveDocument"] autorelease];
        [item setLabel:@"Save"];
        [item setPaletteLabel:@"Save"];
        [item setToolTip:@"Save current markdown changes"];
        [item setTarget:_delegate];
        [item setAction:@selector(saveDocument:)];
        [item setImage:OMDSymbolicImageNamedForCommand(@"omd-document-save-symbolic", @"Save")];
        return item;
    }

    if ([identifier isEqualToString:@"ModeControls"]) {
        CGFloat switcherWidth = 182.0;
        if (_modeContainer == nil) {
            CGFloat controlY = floor((OMDToolbarItemHeight - OMDToolbarControlHeight) * 0.5);
            _modeContainer = [[OMDToolbarToolTipView alloc] initWithFrame:NSMakeRect(0, 0, switcherWidth, OMDToolbarItemHeight)];
            _modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, controlY, switcherWidth, OMDToolbarControlHeight)];
            [_modeControl setSegmentCount:3];
            [_modeControl setLabel:@"Read" forSegment:0];
            [_modeControl setLabel:@"Edit" forSegment:1];
            [_modeControl setLabel:@"Split" forSegment:2];
            [_modeControl setTarget:_delegate];
            [_modeControl setAction:@selector(modeControlChanged:)];
#if !defined(GNUSTEP)
            [_modeControl setAccessibilityLabel:@"View Mode"];
#endif
            [_modeContainer addSubview:_modeControl];
            // GNUstep doesn't show a segment's own tooltip; the container's
            // rects do.
            CGFloat segment = floor(switcherWidth / 3.0);
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:OMDShortcutText(@"Read (Ctrl+1)")
                                                        forRect:NSMakeRect(0.0, controlY, segment, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:OMDShortcutText(@"Edit (Ctrl+2)")
                                                        forRect:NSMakeRect(segment, controlY, segment, OMDToolbarControlHeight)];
            [(OMDToolbarToolTipView *)_modeContainer setToolTip:OMDShortcutText(@"Split (Ctrl+3)")
                                                        forRect:NSMakeRect(2.0 * segment, controlY, switcherWidth - 2.0 * segment, OMDToolbarControlHeight)];
            [_delegate updateModeControlSelection];
        }
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ModeControls"] autorelease];
        [item setView:_modeContainer];
        [item setMinSize:NSMakeSize(switcherWidth, OMDToolbarItemHeight)];
        [item setMaxSize:NSMakeSize(switcherWidth, OMDToolbarItemHeight)];
        [item setLabel:@""];
        [item setPaletteLabel:@"View"];
        return item;
    }

    return nil;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    (void)toolbar;
    return [NSArray arrayWithObjects:@"ToggleExplorer",
                                     @"OpenDocument",
                                     @"SaveDocument",
                                     NSToolbarFlexibleSpaceItemIdentifier,
                                     @"ModeControls",
                                     nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (void)updateToolbarActionControlsState
{
    [_toolbar validateVisibleItems];
}

@end
