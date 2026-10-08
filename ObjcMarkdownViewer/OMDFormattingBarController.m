// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDFormattingBarController.h"
#import "OMDLayoutMetrics.h"
#import "OMDControlSupport.h"
#import "OMDViewerImages.h"

#include <math.h>

// The bar's command groups, in order. Each entry is a command tag, its
// name (the shortcuts match the Edit menu) and its symbolic icon.
typedef struct {
    NSInteger tag;
    const char *name;
    NSString *iconName;
} OMDFormattingCommand;

static const OMDFormattingCommand OMDFormattingInlineCommands[] = {
    { OMDFormattingCommandTagBold, "Bold (Ctrl+B)", @"omd-format-text-bold-symbolic" },
    { OMDFormattingCommandTagItalic, "Italic (Ctrl+I)", @"omd-format-text-italic-symbolic" },
    { OMDFormattingCommandTagStrike, "Strikethrough", @"omd-format-text-strikethrough-symbolic" },
    { OMDFormattingCommandTagInlineCode, "Inline Code", @"omd-format-code-symbolic" }
};
static const OMDFormattingCommand OMDFormattingMediaCommands[] = {
    { OMDFormattingCommandTagLink, "Link", @"omd-insert-link-symbolic" },
    { OMDFormattingCommandTagImage, "Image", @"omd-insert-image-symbolic" }
};
static const OMDFormattingCommand OMDFormattingListCommands[] = {
    { OMDFormattingCommandTagListBullet, "Bulleted List", @"omd-view-list-bullet-symbolic" },
    { OMDFormattingCommandTagListNumber, "Numbered List", @"omd-view-list-ordered-symbolic" },
    { OMDFormattingCommandTagListTask, "Task List", @"omd-view-list-task-symbolic" },
    { OMDFormattingCommandTagBlockQuote, "Quote", @"omd-format-quote-symbolic" }
};
static const OMDFormattingCommand OMDFormattingInsertCommands[] = {
    { OMDFormattingCommandTagCodeFence, "Code Block", @"omd-format-code-block-symbolic" },
    { OMDFormattingCommandTagTable, "Table", @"omd-insert-table-symbolic" },
    { OMDFormattingCommandTagHorizontalRule, "Horizontal Rule", @"omd-insert-rule-symbolic" }
};

typedef struct {
    const OMDFormattingCommand *commands;
    NSUInteger count;
} OMDFormattingCommandGroup;

static const OMDFormattingCommandGroup OMDFormattingCommandGroups[] = {
    { OMDFormattingInlineCommands, 4 },
    { OMDFormattingMediaCommands, 2 },
    { OMDFormattingListCommands, 4 },
    { OMDFormattingInsertCommands, 3 }
};
static const NSUInteger OMDFormattingCommandGroupCount = 4;

static NSString *OMDFormattingCommandName(const OMDFormattingCommand *command)
{
    return OMDShortcutText([NSString stringWithUTF8String:command->name]);
}

// The command alone, without its shortcut: what VoiceOver says.
static NSString *OMDFormattingCommandSpokenName(const OMDFormattingCommand *command)
{
    NSString *name = [NSString stringWithUTF8String:command->name];
    NSRange shortcut = [name rangeOfString:@" ("];
    return shortcut.location != NSNotFound ? [name substringToIndex:shortcut.location] : name;
}

@interface OMDFormattingBarController ()
- (void)setupFormattingBar;
- (void)updateOverflowMenu;
- (void)formattingHeadingControlChanged:(id)sender;
- (void)formattingCommandGroupChanged:(id)sender;
- (void)formattingOverflowItemChosen:(id)sender;
@end

@implementation OMDFormattingBarController

- (instancetype)initWithDelegate:(id<OMDFormattingBarControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [_formatHeadingPopup release];
    [_formatCommandGroups release];
    [_formatOverflowButton release];
    [_formattingBarView release];
    [super dealloc];
}

- (void)setupInContainer:(NSView *)container
{
    _containerView = container;
    [self setupFormattingBar];
}

- (NSView *)barView
{
    return _formattingBarView;
}

- (void)setControlsEnabled:(BOOL)enabled
{
    if (_formatHeadingPopup != nil) {
        [_formatHeadingPopup setEnabled:enabled];
        if (!enabled) {
            [_formatHeadingPopup selectItemAtIndex:0];
        }
    }
    [_formatOverflowButton setEnabled:enabled];
    NSEnumerator *enumerator = [_formatCommandGroups objectEnumerator];
    NSSegmentedControl *control = nil;
    while ((control = [enumerator nextObject]) != nil) {
        [control setEnabled:enabled];
        if (!enabled) {
            OMDClearSegmentedControlSelection(control);
        }
    }
}

- (void)selectHeadingLevel:(NSInteger)level
{
    if (level < 0 || level >= [_formatHeadingPopup numberOfItems]) {
        return;
    }
    [_formatHeadingPopup selectItemAtIndex:level];
}

- (void)setupFormattingBar
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    if (_containerView == nil) {
        return;
    }
    if (_formattingBarView != nil) {
        return;
    }

    // The bar sits on the window background; a separator marks its edge.
    _formattingBarView = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                  0.0,
                                                                  NSWidth([_containerView bounds]),
                                                                  metrics.formattingBarHeight)];
    [_formattingBarView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(0.0,
                                                                0.0,
                                                                NSWidth([_containerView bounds]),
                                                                1.0)] autorelease];
    [separator setBoxType:NSBoxSeparator];
    [separator setAutoresizingMask:NSViewWidthSizable];
    [_formattingBarView addSubview:separator];
    [_containerView addSubview:_formattingBarView];

    NSFont *buttonFont = OMDChromeFont();
    CGFloat compactPadding = (metrics.scale > 1.05 ? 8.0 : 7.0);

    // Paragraph style: one menu instead of a button per heading level.
    NSArray *styles = [NSArray arrayWithObjects:@"Paragraph", @"Heading 1", @"Heading 2", @"Heading 3",
                                                @"Heading 4", @"Heading 5", @"Heading 6", nil];
    CGFloat popupWidth = OMDControlWidthForTitle(@"Paragraph", buttonFont, 96.0, compactPadding) + 24.0;
    _formatHeadingPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0,
                                                                          0.0,
                                                                          popupWidth,
                                                                          metrics.formattingBarControlHeight)
                                                     pullsDown:NO];
    [_formatHeadingPopup addItemsWithTitles:styles];
    [_formatHeadingPopup setFont:buttonFont];
    [_formatHeadingPopup setToolTip:@"Paragraph style"];
    [_formatHeadingPopup setTarget:self];
    [_formatHeadingPopup setAction:@selector(formattingHeadingControlChanged:)];
    [_formatHeadingPopup setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:_formatHeadingPopup];

    // Command groups: symbolic icons, each segment with its own tooltip.
    CGFloat segmentWidth = (metrics.scale > 1.05 ? 30.0 : 26.0);
    _formatCommandGroups = [[NSMutableArray alloc] init];
    NSUInteger groupIndex = 0;
    for (; groupIndex < OMDFormattingCommandGroupCount; groupIndex++) {
        OMDFormattingCommandGroup group = OMDFormattingCommandGroups[groupIndex];
        NSSegmentedControl *control = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0,
                                                                                            0.0,
                                                                                            segmentWidth * group.count,
                                                                                            metrics.formattingBarControlHeight)] autorelease];
        [control setSegmentCount:(NSInteger)group.count];
        [control setSegmentStyle:NSSegmentStyleRounded];
        [[control cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
        NSUInteger segment = 0;
        for (; segment < group.count; segment++) {
            const OMDFormattingCommand *command = &group.commands[segment];
            [control setLabel:@"" forSegment:(NSInteger)segment];
            [control setImage:OMDSymbolicImageNamedForCommand(command->iconName, OMDFormattingCommandSpokenName(command))
                   forSegment:(NSInteger)segment];
#if !defined(GNUSTEP)
            [control setToolTip:OMDFormattingCommandName(command) forSegment:(NSInteger)segment];
#endif
            [control setWidth:segmentWidth forSegment:(NSInteger)segment];
            // Per-segment cell tooltips aren't shown by GNUstep; a tooltip
            // rect per segment is. The string is its own owner.
            [control addToolTipRect:NSMakeRect(segmentWidth * segment,
                                               0.0,
                                               segmentWidth,
                                               metrics.formattingBarControlHeight)
                              owner:OMDFormattingCommandName(command)
                           userData:NULL];
        }
        [control setTag:(NSInteger)groupIndex];
        [control setTarget:self];
        [control setAction:@selector(formattingCommandGroupChanged:)];
        [control setAutoresizingMask:NSViewMinYMargin];
        [_formattingBarView addSubview:control];
        [_formatCommandGroups addObject:control];
    }

    _formatOverflowButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0,
                                                                            0.0,
                                                                            segmentWidth + 14.0,
                                                                            metrics.formattingBarControlHeight)
                                                       pullsDown:YES];
    [_formatOverflowButton addItemWithTitle:@"»"];
    [_formatOverflowButton setFont:buttonFont];
    [_formatOverflowButton setToolTip:@"More formatting"];
    [_formatOverflowButton setAutoresizingMask:NSViewMinYMargin];
    [_formatOverflowButton setHidden:YES];
    [_formattingBarView addSubview:_formatOverflowButton];
    _formatVisibleGroupCount = OMDFormattingCommandGroupCount;

    [_delegate updateFormattingBarContextState];
}

- (CGFloat)layoutFormattingBarControlsForWidth:(CGFloat)containerWidth
                                  applyFrames:(BOOL)applyFrames
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    CGFloat controlHeight = metrics.formattingBarControlHeight;
    CGFloat insetX = metrics.formattingBarInsetX;
    CGFloat rowInsetY = (metrics.scale > 1.05 ? 6.0 : 5.0);
    CGFloat spacing = metrics.formattingBarGroupSpacing;
    CGFloat barHeight = ceil(rowInsetY + controlHeight + rowInsetY);
    if (!applyFrames || _formatHeadingPopup == nil) {
        return barHeight;
    }

    CGFloat availableWidth = containerWidth - (insetX * 2.0);
    CGFloat headingWidth = NSWidth([_formatHeadingPopup frame]);
    CGFloat overflowWidth = NSWidth([_formatOverflowButton frame]);

    // Every group if they all fit; otherwise as many as fit beside the
    // overflow button.
    CGFloat allWidth = headingWidth;
    NSEnumerator *enumerator = [_formatCommandGroups objectEnumerator];
    NSSegmentedControl *control = nil;
    while ((control = [enumerator nextObject]) != nil) {
        allWidth += spacing + NSWidth([control frame]);
    }
    NSUInteger visibleCount = [_formatCommandGroups count];
    if (allWidth > availableWidth) {
        CGFloat used = headingWidth + spacing + overflowWidth;
        visibleCount = 0;
        while (visibleCount < [_formatCommandGroups count]) {
            CGFloat groupWidth = NSWidth([[_formatCommandGroups objectAtIndex:visibleCount] frame]);
            if (used + spacing + groupWidth > availableWidth) {
                break;
            }
            used += spacing + groupWidth;
            visibleCount++;
        }
    }

    CGFloat controlY = floor((barHeight - controlHeight) / 2.0);
    CGFloat x = insetX;
    [_formatHeadingPopup setFrame:NSMakeRect(x, controlY, headingWidth, controlHeight)];
    x += headingWidth;
    NSUInteger index = 0;
    for (; index < [_formatCommandGroups count]; index++) {
        control = [_formatCommandGroups objectAtIndex:index];
        BOOL visible = index < visibleCount;
        [control setHidden:!visible];
        if (visible) {
            CGFloat width = NSWidth([control frame]);
            x += spacing;
            [control setFrame:NSMakeRect(x, controlY, width, controlHeight)];
            x += width;
        }
    }
    BOOL overflowing = visibleCount < [_formatCommandGroups count];
    [_formatOverflowButton setHidden:!overflowing];
    if (overflowing) {
        [_formatOverflowButton setFrame:NSMakeRect(x + spacing, controlY, overflowWidth, controlHeight)];
    }
    if (visibleCount != _formatVisibleGroupCount) {
        _formatVisibleGroupCount = visibleCount;
        [self updateOverflowMenu];
    }

    return barHeight;
}

// Lists the commands of the hidden groups, after the pull-down's title item.
- (void)updateOverflowMenu
{
    while ([_formatOverflowButton numberOfItems] > 1) {
        [_formatOverflowButton removeItemAtIndex:1];
    }
    NSUInteger groupIndex = _formatVisibleGroupCount;
    for (; groupIndex < OMDFormattingCommandGroupCount; groupIndex++) {
        OMDFormattingCommandGroup group = OMDFormattingCommandGroups[groupIndex];
        if (groupIndex > _formatVisibleGroupCount) {
            [[_formatOverflowButton menu] addItem:[NSMenuItem separatorItem]];
        }
        NSUInteger index = 0;
        for (; index < group.count; index++) {
            const OMDFormattingCommand *command = &group.commands[index];
            // Items added to the menu directly carry their own action.
            NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:OMDFormattingCommandName(command)
                                                           action:@selector(formattingOverflowItemChosen:)
                                                    keyEquivalent:@""] autorelease];
            [item setTarget:self];
            [item setTag:command->tag];
            [item setImage:OMDSymbolicImageNamed(command->iconName)];
            [[_formatOverflowButton menu] addItem:item];
        }
    }
}

- (void)rebuildFormattingBar
{
    [_formatHeadingPopup release];
    _formatHeadingPopup = nil;
    [_formatCommandGroups release];
    _formatCommandGroups = nil;
    [_formatOverflowButton release];
    _formatOverflowButton = nil;
    if (_formattingBarView != nil) {
        [_formattingBarView removeFromSuperview];
        [_formattingBarView release];
        _formattingBarView = nil;
    }
    [self setupFormattingBar];
}

- (void)formattingHeadingControlChanged:(id)sender
{
    if (sender != _formatHeadingPopup) {
        return;
    }
    NSInteger index = [_formatHeadingPopup indexOfSelectedItem];
    if (index < 0) {
        return;
    }
    [_delegate formattingBarController:self applyHeadingLevel:index];
}

- (void)formattingCommandGroupChanged:(id)sender
{
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = [control selectedSegment];
    NSInteger groupIndex = [control tag];
    OMDClearSegmentedControlSelection(control);
    if (segment < 0 || groupIndex < 0 || (NSUInteger)groupIndex >= OMDFormattingCommandGroupCount) {
        return;
    }
    OMDFormattingCommandGroup group = OMDFormattingCommandGroups[groupIndex];
    if ((NSUInteger)segment >= group.count) {
        return;
    }
    [_delegate formattingBarController:self performCommandWithTag:group.commands[segment].tag];
}

- (void)formattingOverflowItemChosen:(id)sender
{
    NSInteger tag = [sender tag];
    if (tag == 0) {
        return;
    }
    [_delegate formattingBarController:self performCommandWithTag:tag];
}

@end
