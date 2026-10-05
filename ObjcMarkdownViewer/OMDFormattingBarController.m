// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDFormattingBarController.h"
#import "OMDControlSupport.h"
#import "OMDFormattingBarView.h"
#import "OMDViewerColors.h"

#include <math.h>

@interface OMDFormattingBarController ()
- (void)setupFormattingBar;
- (void)formattingHeadingControlChanged:(id)sender;
- (void)formattingCommandGroupChanged:(id)sender;
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
    [_formatHeadingControl release];
    [_formatCommandButtons release];
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
    if (_formatHeadingControl != nil) {
        [_formatHeadingControl setEnabled:enabled];
        if (!enabled) {
            OMDClearSegmentedControlSelection(_formatHeadingControl);
        }
    }
    NSEnumerator *enumerator = [_formatCommandButtons objectEnumerator];
    id control = nil;
    while ((control = [enumerator nextObject]) != nil) {
        if ([control respondsToSelector:@selector(setEnabled:)]) {
            [control setEnabled:enabled];
        }
        if (!enabled &&
            [control respondsToSelector:@selector(setSelectedSegment:)]) {
            OMDClearSegmentedControlSelection(control);
        }
    }
}

- (void)selectHeadingLevel:(NSInteger)level
{
    [_formatHeadingControl setSelectedSegment:level];
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

    _formattingBarView = [[OMDFormattingBarView alloc] initWithFrame:NSMakeRect(0.0,
                                                                                 0.0,
                                                                                 NSWidth([_containerView bounds]),
                                                                                 metrics.formattingBarHeight)];
    [_formattingBarView setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_formattingBarView setFillColor:OMDResolvedControlBackgroundColor()];
    [_formattingBarView setBorderColor:OMDResolvedSubtleSeparatorColor()];
    [_containerView addSubview:_formattingBarView];

    _formatCommandButtons = [[NSMutableDictionary alloc] init];

    CGFloat x = metrics.formattingBarInsetX;
    NSFont *buttonFont = [NSFont systemFontOfSize:(metrics.scale > 1.05 ? 11.5 : metrics.formattingBarFontSize)];
    CGFloat compactPadding = (metrics.scale > 1.05 ? 8.0 : 7.0);
    CGFloat narrowPadding = (metrics.scale > 1.05 ? 7.0 : 6.0);

    CGFloat headingPWidth = OMDControlWidthForTitle(@"P", buttonFont, 30.0, narrowPadding);
    CGFloat headingLevelWidth = OMDControlWidthForTitle(@"H6", buttonFont, 36.0, narrowPadding);
    CGFloat headingWidth = headingPWidth + (headingLevelWidth * 6.0);
    _formatHeadingControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                 0.0,
                                                                                 headingWidth,
                                                                                 metrics.formattingBarControlHeight)];
    [_formatHeadingControl setSegmentCount:7];
    [_formatHeadingControl setSegmentStyle:NSSegmentStyleRounded];
    [[_formatHeadingControl cell] setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    [_formatHeadingControl setLabel:@"P" forSegment:0];
    [_formatHeadingControl setLabel:@"H1" forSegment:1];
    [_formatHeadingControl setLabel:@"H2" forSegment:2];
    [_formatHeadingControl setLabel:@"H3" forSegment:3];
    [_formatHeadingControl setLabel:@"H4" forSegment:4];
    [_formatHeadingControl setLabel:@"H5" forSegment:5];
    [_formatHeadingControl setLabel:@"H6" forSegment:6];
    [_formatHeadingControl setWidth:headingPWidth forSegment:0];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:1];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:2];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:3];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:4];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:5];
    [_formatHeadingControl setWidth:headingLevelWidth forSegment:6];
    [[_formatHeadingControl cell] setToolTip:@"Paragraph" forSegment:0];
    [[_formatHeadingControl cell] setToolTip:@"Heading 1" forSegment:1];
    [[_formatHeadingControl cell] setToolTip:@"Heading 2" forSegment:2];
    [[_formatHeadingControl cell] setToolTip:@"Heading 3" forSegment:3];
    [[_formatHeadingControl cell] setToolTip:@"Heading 4" forSegment:4];
    [[_formatHeadingControl cell] setToolTip:@"Heading 5" forSegment:5];
    [[_formatHeadingControl cell] setToolTip:@"Heading 6" forSegment:6];
    if ([_formatHeadingControl respondsToSelector:@selector(setFont:)]) {
        [_formatHeadingControl setFont:buttonFont];
    }
    [_formatHeadingControl setTarget:self];
    [_formatHeadingControl setAction:@selector(formattingHeadingControlChanged:)];
    [_formatHeadingControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:_formatHeadingControl];

    x += headingWidth + metrics.formattingBarGroupSpacing;

    CGFloat boldWidth = OMDControlWidthForTitle(@"B", buttonFont, 32.0, narrowPadding);
    CGFloat italicWidth = OMDControlWidthForTitle(@"I", buttonFont, 32.0, narrowPadding);
    CGFloat strikeWidth = OMDControlWidthForTitle(@"S", buttonFont, 32.0, narrowPadding);
    CGFloat inlineCodeWidth = OMDControlWidthForTitle(@"Code", buttonFont, 50.0, compactPadding);
    CGFloat inlineWidth = boldWidth + italicWidth + strikeWidth + inlineCodeWidth;
    NSSegmentedControl *inlineControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                               0.0,
                                                                                               inlineWidth,
                                                                                               metrics.formattingBarControlHeight)] autorelease];
    [inlineControl setSegmentCount:4];
    [inlineControl setSegmentStyle:NSSegmentStyleRounded];
    [[inlineControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [inlineControl setLabel:@"B" forSegment:0];
    [inlineControl setLabel:@"I" forSegment:1];
    [inlineControl setLabel:@"S" forSegment:2];
    [inlineControl setLabel:@"Code" forSegment:3];
    [inlineControl setWidth:boldWidth forSegment:0];
    [inlineControl setWidth:italicWidth forSegment:1];
    [inlineControl setWidth:strikeWidth forSegment:2];
    [inlineControl setWidth:inlineCodeWidth forSegment:3];
    [[inlineControl cell] setToolTip:@"Bold (Ctrl/Cmd+B)" forSegment:0];
    [[inlineControl cell] setToolTip:@"Italic (Ctrl/Cmd+I)" forSegment:1];
    [[inlineControl cell] setToolTip:@"Strikethrough" forSegment:2];
    [[inlineControl cell] setToolTip:@"Inline code" forSegment:3];
    if ([inlineControl respondsToSelector:@selector(setFont:)]) {
        [inlineControl setFont:buttonFont];
    }
    [inlineControl setTag:1];
    [inlineControl setTarget:self];
    [inlineControl setAction:@selector(formattingCommandGroupChanged:)];
    [inlineControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:inlineControl];
    [_formatCommandButtons setObject:inlineControl forKey:@"inline"];

    x += NSWidth([inlineControl frame]) + metrics.formattingBarGroupSpacing;

    NSSegmentedControl *mediaControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                              0.0,
                                                                                              0.0,
                                                                                              metrics.formattingBarControlHeight)] autorelease];
    [mediaControl setSegmentCount:2];
    [mediaControl setSegmentStyle:NSSegmentStyleRounded];
    [[mediaControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [mediaControl setLabel:@"Link" forSegment:0];
    [mediaControl setLabel:@"Image" forSegment:1];
    CGFloat linkWidth = OMDControlWidthForTitle(@"Link", buttonFont, 46.0, compactPadding);
    CGFloat imageWidth = OMDControlWidthForTitle(@"Image", buttonFont, 54.0, compactPadding);
    [mediaControl setFrame:NSMakeRect(x, 0.0, linkWidth + imageWidth, metrics.formattingBarControlHeight)];
    [mediaControl setWidth:linkWidth forSegment:0];
    [mediaControl setWidth:imageWidth forSegment:1];
    [[mediaControl cell] setToolTip:@"Insert link" forSegment:0];
    [[mediaControl cell] setToolTip:@"Insert image" forSegment:1];
    if ([mediaControl respondsToSelector:@selector(setFont:)]) {
        [mediaControl setFont:buttonFont];
    }
    [mediaControl setTag:2];
    [mediaControl setTarget:self];
    [mediaControl setAction:@selector(formattingCommandGroupChanged:)];
    [mediaControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:mediaControl];
    [_formatCommandButtons setObject:mediaControl forKey:@"media"];

    x += NSWidth([mediaControl frame]) + metrics.formattingBarGroupSpacing;

    NSSegmentedControl *listControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                             0.0,
                                                                                             0.0,
                                                                                             metrics.formattingBarControlHeight)] autorelease];
    [listControl setSegmentCount:4];
    [listControl setSegmentStyle:NSSegmentStyleRounded];
    [[listControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [listControl setLabel:@"-" forSegment:0];
    [listControl setLabel:@"1." forSegment:1];
    [listControl setLabel:@"[]" forSegment:2];
    [listControl setLabel:@">" forSegment:3];
    CGFloat bulletWidth = OMDControlWidthForTitle(@"-", buttonFont, 32.0, narrowPadding);
    CGFloat numberWidth = OMDControlWidthForTitle(@"1.", buttonFont, 36.0, narrowPadding);
    CGFloat taskWidth = OMDControlWidthForTitle(@"[]", buttonFont, 40.0, narrowPadding);
    CGFloat quoteWidth = OMDControlWidthForTitle(@">", buttonFont, 32.0, narrowPadding);
    [listControl setFrame:NSMakeRect(x,
                                     0.0,
                                     bulletWidth + numberWidth + taskWidth + quoteWidth,
                                     metrics.formattingBarControlHeight)];
    [listControl setWidth:bulletWidth forSegment:0];
    [listControl setWidth:numberWidth forSegment:1];
    [listControl setWidth:taskWidth forSegment:2];
    [listControl setWidth:quoteWidth forSegment:3];
    [[listControl cell] setToolTip:@"Toggle bullet list" forSegment:0];
    [[listControl cell] setToolTip:@"Toggle numbered list" forSegment:1];
    [[listControl cell] setToolTip:@"Toggle task list" forSegment:2];
    [[listControl cell] setToolTip:@"Toggle block quote" forSegment:3];
    if ([listControl respondsToSelector:@selector(setFont:)]) {
        [listControl setFont:buttonFont];
    }
    [listControl setTag:3];
    [listControl setTarget:self];
    [listControl setAction:@selector(formattingCommandGroupChanged:)];
    [listControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:listControl];
    [_formatCommandButtons setObject:listControl forKey:@"lists"];

    x += NSWidth([listControl frame]) + metrics.formattingBarGroupSpacing;

    NSSegmentedControl *insertControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(x,
                                                                                               0.0,
                                                                                               0.0,
                                                                                               metrics.formattingBarControlHeight)] autorelease];
    [insertControl setSegmentCount:3];
    [insertControl setSegmentStyle:NSSegmentStyleRounded];
    [[insertControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [insertControl setLabel:@"{}" forSegment:0];
    [insertControl setLabel:@"Tbl" forSegment:1];
    [insertControl setLabel:@"HR" forSegment:2];
    CGFloat codeBlockWidth = OMDControlWidthForTitle(@"{}", buttonFont, 40.0, narrowPadding);
    CGFloat tableWidth = OMDControlWidthForTitle(@"Tbl", buttonFont, 42.0, compactPadding);
    CGFloat ruleWidth = OMDControlWidthForTitle(@"HR", buttonFont, 40.0, narrowPadding);
    [insertControl setFrame:NSMakeRect(x,
                                       0.0,
                                       codeBlockWidth + tableWidth + ruleWidth,
                                       metrics.formattingBarControlHeight)];
    [insertControl setWidth:codeBlockWidth forSegment:0];
    [insertControl setWidth:tableWidth forSegment:1];
    [insertControl setWidth:ruleWidth forSegment:2];
    [[insertControl cell] setToolTip:@"Insert fenced code block" forSegment:0];
    [[insertControl cell] setToolTip:@"Insert table" forSegment:1];
    [[insertControl cell] setToolTip:@"Insert horizontal rule" forSegment:2];
    if ([insertControl respondsToSelector:@selector(setFont:)]) {
        [insertControl setFont:buttonFont];
    }
    [insertControl setTag:4];
    [insertControl setTarget:self];
    [insertControl setAction:@selector(formattingCommandGroupChanged:)];
    [insertControl setAutoresizingMask:NSViewMinYMargin];
    [_formattingBarView addSubview:insertControl];
    [_formatCommandButtons setObject:insertControl forKey:@"insert"];

    [_delegate updateFormattingBarContextState];
}

- (CGFloat)layoutFormattingBarControlsForWidth:(CGFloat)containerWidth
                                  applyFrames:(BOOL)applyFrames
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    CGFloat controlHeight = metrics.formattingBarControlHeight;
    CGFloat insetX = metrics.formattingBarInsetX;
    CGFloat rowInsetY = (metrics.scale > 1.05 ? 6.0 : 5.0);
    CGFloat rowGap = (metrics.scale > 1.05 ? 6.0 : 4.0);
    CGFloat availableWidth = containerWidth - (insetX * 2.0);

    NSSegmentedControl *inlineControl = [_formatCommandButtons objectForKey:@"inline"];
    NSSegmentedControl *mediaControl = [_formatCommandButtons objectForKey:@"media"];
    NSSegmentedControl *listControl = [_formatCommandButtons objectForKey:@"lists"];
    NSSegmentedControl *insertControl = [_formatCommandButtons objectForKey:@"insert"];

    CGFloat headingWidth = (_formatHeadingControl != nil ? NSWidth([_formatHeadingControl frame]) : 0.0);
    CGFloat inlineWidth = (inlineControl != nil ? NSWidth([inlineControl frame]) : 0.0);
    CGFloat mediaWidth = (mediaControl != nil ? NSWidth([mediaControl frame]) : 0.0);
    CGFloat listWidth = (listControl != nil ? NSWidth([listControl frame]) : 0.0);
    CGFloat insertWidth = (insertControl != nil ? NSWidth([insertControl frame]) : 0.0);

    CGFloat oneRowWidth = headingWidth +
                          inlineWidth +
                          mediaWidth +
                          listWidth +
                          insertWidth +
                          (metrics.formattingBarGroupSpacing * 4.0);
    BOOL usesTwoRows = oneRowWidth > availableWidth;

    CGFloat barHeight = rowInsetY + controlHeight + rowInsetY;
    if (usesTwoRows) {
        barHeight = rowInsetY + controlHeight + rowGap + controlHeight + rowInsetY;
    }
    if (!applyFrames) {
        return ceil(barHeight);
    }

    if (usesTwoRows) {
        CGFloat topRowY = barHeight - rowInsetY - controlHeight;
        CGFloat bottomRowY = rowInsetY;

        CGFloat topX = insetX;
        if (_formatHeadingControl != nil) {
            [_formatHeadingControl setFrame:NSMakeRect(topX,
                                                       topRowY,
                                                       headingWidth,
                                                       controlHeight)];
            topX += headingWidth + metrics.formattingBarGroupSpacing;
        }
        if (inlineControl != nil) {
            [inlineControl setFrame:NSMakeRect(topX,
                                               topRowY,
                                               inlineWidth,
                                               controlHeight)];
        }

        CGFloat bottomX = insetX;
        if (mediaControl != nil) {
            [mediaControl setFrame:NSMakeRect(bottomX,
                                              bottomRowY,
                                              mediaWidth,
                                              controlHeight)];
            bottomX += mediaWidth + metrics.formattingBarGroupSpacing;
        }
        if (listControl != nil) {
            [listControl setFrame:NSMakeRect(bottomX,
                                             bottomRowY,
                                             listWidth,
                                             controlHeight)];
            bottomX += listWidth + metrics.formattingBarGroupSpacing;
        }
        if (insertControl != nil) {
            [insertControl setFrame:NSMakeRect(bottomX,
                                               bottomRowY,
                                               insertWidth,
                                               controlHeight)];
        }
    } else {
        CGFloat controlY = floor((barHeight - controlHeight) / 2.0);
        CGFloat currentX = insetX;
        NSArray *orderedControls = [NSArray arrayWithObjects:
                                    _formatHeadingControl,
                                    inlineControl,
                                    mediaControl,
                                    listControl,
                                    insertControl,
                                    nil];
        NSEnumerator *enumerator = [orderedControls objectEnumerator];
        NSSegmentedControl *control = nil;
        while ((control = [enumerator nextObject]) != nil) {
            CGFloat controlWidth = NSWidth([control frame]);
            [control setFrame:NSMakeRect(currentX,
                                         controlY,
                                         controlWidth,
                                         controlHeight)];
            currentX += controlWidth + metrics.formattingBarGroupSpacing;
        }
    }

    return ceil(barHeight);
}

- (void)rebuildFormattingBar
{
    [_formatHeadingControl release];
    _formatHeadingControl = nil;
    [_formatCommandButtons release];
    _formatCommandButtons = nil;
    if (_formattingBarView != nil) {
        [_formattingBarView removeFromSuperview];
        [_formattingBarView release];
        _formattingBarView = nil;
    }
    [self setupFormattingBar];
}

- (void)formattingHeadingControlChanged:(id)sender
{
    if (sender != _formatHeadingControl) {
        return;
    }
    NSInteger index = [_formatHeadingControl selectedSegment];
    if (index < 0) {
        return;
    }
    [_delegate formattingBarController:self applyHeadingLevel:index];
}

- (void)formattingCommandGroupChanged:(id)sender
{
    NSSegmentedControl *control = (NSSegmentedControl *)sender;

    NSInteger segment = [control selectedSegment];
    if (segment < 0) {
        return;
    }
    NSInteger tag = 0;
    switch ([control tag]) {
        case 1:
            if (segment == 0) {
                tag = OMDFormattingCommandTagBold;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagItalic;
            } else if (segment == 2) {
                tag = OMDFormattingCommandTagStrike;
            } else if (segment == 3) {
                tag = OMDFormattingCommandTagInlineCode;
            }
            break;
        case 2:
            if (segment == 0) {
                tag = OMDFormattingCommandTagLink;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagImage;
            }
            break;
        case 3:
            if (segment == 0) {
                tag = OMDFormattingCommandTagListBullet;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagListNumber;
            } else if (segment == 2) {
                tag = OMDFormattingCommandTagListTask;
            } else if (segment == 3) {
                tag = OMDFormattingCommandTagBlockQuote;
            }
            break;
        case 4:
            if (segment == 0) {
                tag = OMDFormattingCommandTagCodeFence;
            } else if (segment == 1) {
                tag = OMDFormattingCommandTagTable;
            } else if (segment == 2) {
                tag = OMDFormattingCommandTagHorizontalRule;
            }
            break;
        default:
            break;
    }
    OMDClearSegmentedControlSelection(control);
    if (tag == 0) {
        return;
    }
    [_delegate formattingBarController:self performCommandWithTag:tag];
}

@end
