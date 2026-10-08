// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDToolbarController.h"
#import "OMDToolbarViews.h"
#import "OMDViewerImages.h"

@interface OMDToolbarController ()
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
    [_toolbar release];
    [_modeContainer release];
    [_modeControl release];
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

- (void)installInWindow:(NSWindow *)window
{
    [_toolbar release];
    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"ObjcMarkdownViewerToolbar"];
    [_toolbar setDelegate:self];
    [_toolbar setAllowsUserCustomization:NO];
    [_toolbar setAutosavesConfiguration:NO];
    [_toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
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
        NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"OpenDocument"] autorelease];
        [item setLabel:@"Open"];
        [item setPaletteLabel:@"Open"];
        [item setToolTip:@"Open a Markdown file"];
        [item setTarget:_delegate];
        [item setAction:@selector(openDocument:)];
        // A split button: the icon opens the open panel, the arrow beside it
        // lists the recent documents.
        CGFloat openWidth = 34.0;
        CGFloat arrowWidth = 16.0;
        NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, openWidth + arrowWidth, OMDToolbarItemHeight)] autorelease];
        NSButton *openButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, openWidth, OMDToolbarItemHeight)] autorelease];
        [openButton setBordered:NO];
        [openButton setImagePosition:NSImageOnly];
        [openButton setImage:OMDSymbolicImageNamedForCommand(@"omd-document-open-symbolic", @"Open")];
        [openButton setToolTip:@"Open a Markdown file"];
        [openButton setTarget:_delegate];
        [openButton setAction:@selector(openDocument:)];
        [container addSubview:openButton];
        NSButton *arrowButton = [[[NSButton alloc] initWithFrame:NSMakeRect(openWidth, 0.0, arrowWidth, OMDToolbarItemHeight)] autorelease];
        [arrowButton setBordered:NO];
        [arrowButton setImagePosition:NSImageOnly];
        [arrowButton setImage:OMDSymbolicImageNamedForCommand(@"omd-pan-down-symbolic", @"Open Recent")];
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
