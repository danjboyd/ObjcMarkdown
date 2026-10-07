// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDStatusBarController.h"
#import "OMDLayoutMetrics.h"

#include <math.h>

static const CGFloat OMDStatusBarInsetX = 12.0;
static const CGFloat OMDStatusBarSliderWidth = 130.0;
static const CGFloat OMDStatusBarGap = 8.0;
// Status text 132pt wide at least, then the zoom slider and button.
const CGFloat OMDStatusBarMinimumWidth = 12.0 + 132.0 + 8.0 + 130.0 + 8.0 + 72.0 + 12.0;

@implementation OMDStatusBarController

- (instancetype)initWithDelegate:(id<OMDStatusBarControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [_statusLabel release];
    [_zoomSlider release];
    [_zoomButton release];
    [_view release];
    [super dealloc];
}

- (void)buildControls
{
    if (_zoomButton != nil) {
        return;
    }
    _statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [_statusLabel setBezeled:NO];
    [_statusLabel setBordered:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:OMDChromeFont()];
    [_statusLabel setStringValue:@""];

    _zoomSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [_zoomSlider setMinValue:50];
    [_zoomSlider setMaxValue:200];
    [_zoomSlider setDoubleValue:[_delegate previewZoomScale] * 100.0];
    [_zoomSlider setTarget:_delegate];
    [_zoomSlider setAction:@selector(zoomSliderChanged:)];
    [_zoomSlider setToolTip:@"Zoom"];

    _zoomButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [_zoomButton setBezelStyle:NSRoundedBezelStyle];
    [_zoomButton setTitle:@"200%"];
    [_zoomButton setTarget:_delegate];
    [_zoomButton setAction:@selector(zoomReset:)];
    [_zoomButton setToolTip:@"Reset zoom to 100%"];
}

// The theme's own sizes for the button and slider decide the bar's height.
- (CGFloat)height
{
    [self buildControls];
    CGFloat buttonHeight = ceil([[_zoomButton cell] cellSize].height);
    CGFloat textHeight = OMDChromeLineHeight(OMDChromeFont()) + 4.0;
    return ceil(MAX(MAX(buttonHeight, textHeight), 24.0) + 8.0);
}

- (NSView *)viewWithWidth:(CGFloat)width
{
    if (_view != nil) {
        return _view;
    }
    [self buildControls];
    CGFloat height = [self height];
    _view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)];
    [_view setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(0.0, height - 1.0, width, 1.0)] autorelease];
    [separator setBoxType:NSBoxSeparator];
    [separator setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_view addSubview:separator];

    NSSize buttonSize = [[_zoomButton cell] cellSize];
    CGFloat buttonWidth = MAX(72.0, ceil(buttonSize.width));
    CGFloat buttonHeight = MIN(height - 4.0, ceil(buttonSize.height));
    CGFloat buttonX = width - OMDStatusBarInsetX - buttonWidth;
    [_zoomButton setFrame:NSMakeRect(buttonX, floor((height - buttonHeight) / 2.0), buttonWidth, buttonHeight)];
    [_zoomButton setAutoresizingMask:NSViewMinXMargin];
    [_view addSubview:_zoomButton];

    CGFloat sliderHeight = MIN(height - 4.0, MAX(20.0, ceil([[_zoomSlider cell] cellSize].height)));
    CGFloat sliderX = buttonX - OMDStatusBarGap - OMDStatusBarSliderWidth;
    [_zoomSlider setFrame:NSMakeRect(sliderX, floor((height - sliderHeight) / 2.0), OMDStatusBarSliderWidth, sliderHeight)];
    [_zoomSlider setAutoresizingMask:NSViewMinXMargin];
    [_view addSubview:_zoomSlider];

    CGFloat labelHeight = OMDChromeLineHeight(OMDChromeFont()) + 4.0;
    CGFloat labelWidth = MAX(1.0, sliderX - OMDStatusBarGap - OMDStatusBarInsetX);
    [_statusLabel setFrame:NSMakeRect(OMDStatusBarInsetX, floor((height - labelHeight) / 2.0), labelWidth, labelHeight)];
    [_statusLabel setAutoresizingMask:NSViewWidthSizable];
    [_view addSubview:_statusLabel];

    [_delegate updateZoomLabel];
    [_delegate updatePreviewStatusIndicator];
    return _view;
}

- (NSTextField *)statusLabel
{
    return _statusLabel;
}

- (NSSlider *)zoomSlider
{
    return _zoomSlider;
}

- (NSButton *)zoomButton
{
    return _zoomButton;
}

@end
