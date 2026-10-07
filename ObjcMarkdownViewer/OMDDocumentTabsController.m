// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDDocumentTabsController.h"
#import "OMDMarkdownDocument.h"
#import "OMDLayoutMetrics.h"
#import "OMDTextFileSupport.h"

#include <math.h>

@interface OMDDocumentTabsController ()
- (void)tabButtonPressed:(id)sender;
- (void)tabCloseButtonPressed:(id)sender;
@end

@implementation OMDDocumentTabsController

- (instancetype)initWithDelegate:(id<OMDDocumentTabsControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        _tabs = [[NSMutableArray alloc] init];
        _selectedIndex = -1;
        _stripView = [[NSView alloc] initWithFrame:NSZeroRect];
        [_stripView setAutoresizingMask:0];
    }
    return self;
}

- (void)dealloc
{
    [_tabs release];
    [_stripView release];
    [super dealloc];
}

- (NSUInteger)count
{
    return [_tabs count];
}

- (OMDMarkdownDocument *)tabAtIndex:(NSInteger)index
{
    return [_tabs objectAtIndex:index];
}

- (void)addTab:(OMDMarkdownDocument *)tab
{
    [_tabs addObject:tab];
}

- (void)replaceTabAtIndex:(NSInteger)index withTab:(OMDMarkdownDocument *)tab
{
    [_tabs replaceObjectAtIndex:index withObject:tab];
}

- (void)removeTabAtIndex:(NSInteger)index
{
    [_tabs removeObjectAtIndex:index];
}

- (NSInteger)selectedIndex
{
    return _selectedIndex;
}

- (void)setSelectedIndex:(NSInteger)index
{
    _selectedIndex = index;
}

- (OMDMarkdownDocument *)selectedTab
{
    if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)[_tabs count]) {
        return nil;
    }
    return [_tabs objectAtIndex:_selectedIndex];
}

- (NSView *)stripView
{
    return _stripView;
}

- (CGFloat)currentTabStripHeight
{
    OMDLayoutMetrics metrics = OMDLayoutMetricsForMode([_delegate effectiveLayoutDensityMode]);
    if (_tabs == nil) {
        return 0.0;
    }
    if ([_tabs count] <= 1) {
        return 0.0;
    }
    return metrics.tabStripHeight;
}

- (void)updateTabStrip
{
    if (_stripView == nil) {
        return;
    }

    NSArray *existingSubviews = [[_stripView subviews] copy];
    for (NSView *view in existingSubviews) {
        [view removeFromSuperview];
    }
    [existingSubviews release];

    if ([_stripView isHidden] || [self currentTabStripHeight] <= 0.0) {
        return;
    }

    NSRect bounds = [_stripView bounds];
    if ([_tabs count] == 0) {
        NSTextField *label = [[[NSTextField alloc] initWithFrame:NSInsetRect(bounds, 8.0, 6.0)] autorelease];
        [label setBezeled:NO];
        [label setEditable:NO];
        [label setSelectable:NO];
        [label setDrawsBackground:NO];
        [label setTextColor:[NSColor disabledControlTextColor]];
        [label setFont:OMDChromeSmallFont()];
        [label setStringValue:@"No document open"];
        [_stripView addSubview:label];
        return;
    }

    CGFloat x = 6.0;
    CGFloat y = 4.0;
    CGFloat height = NSHeight(bounds) - 8.0;
    CGFloat available = NSWidth(bounds) - 6.0;
    const CGFloat closeButtonSize = 14.0;
    const CGFloat closeButtonInset = 3.0;

    NSInteger index = 0;
    for (; index < (NSInteger)[_tabs count]; index++) {
        OMDMarkdownDocument *tab = [_tabs objectAtIndex:index];
        NSString *title = [tab tabTitle];
        if ([tab isDocumentEdited]) {
            title = [title stringByAppendingString:@" *"];
        }
        if ([tab readOnly]) {
            title = [title stringByAppendingString:@" [RO]"];
        }

        // As wide as the title in the theme's font, plus the button's
        // padding and the close button.
        NSDictionary *titleAttributes = [NSDictionary dictionaryWithObject:OMDChromeFont()
                                                                    forKey:NSFontAttributeName];
        CGFloat titleTextWidth = ceil([title sizeWithAttributes:titleAttributes].width);
        CGFloat width = titleTextWidth + 28.0 + closeButtonSize + (closeButtonInset * 2.0);
        if (width < 108.0) {
            width = 108.0;
        }
        if (width > 280.0) {
            width = 280.0;
        }
        if (x + width > available) {
            width = available - x;
        }
        if (width < 72.0) {
            break;
        }

        NSView *tabContainer = [[[NSView alloc] initWithFrame:NSMakeRect(x, y, width, height)] autorelease];
        [tabContainer setAutoresizingMask:NSViewMinYMargin];

        CGFloat titleWidth = width - closeButtonSize - (closeButtonInset * 2.0);
        if (titleWidth < 52.0) {
            titleWidth = width - closeButtonSize - closeButtonInset;
        }
        if (titleWidth < 40.0) {
            break;
        }

        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, titleWidth, height)] autorelease];
        [button setTitle:title];
        [button setTag:index];
        [button setButtonType:NSPushOnPushOffButton];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setState:(index == _selectedIndex ? NSOnState : NSOffState)];
        [button setTarget:self];
        [button setAction:@selector(tabButtonPressed:)];
        [button setFont:OMDChromeFont()];
        [button setAlignment:NSLeftTextAlignment];
        [tabContainer addSubview:button];

        NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(width - closeButtonSize - closeButtonInset,
                                                                              floor((height - closeButtonSize) * 0.5),
                                                                              closeButtonSize,
                                                                              closeButtonSize)] autorelease];
        [closeButton setTitle:@"x"];
        [closeButton setTag:index];
        [closeButton setButtonType:NSMomentaryPushInButton];
        [closeButton setBezelStyle:NSRoundRectBezelStyle];
        [closeButton setTarget:self];
        [closeButton setAction:@selector(tabCloseButtonPressed:)];
        [closeButton setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
        [tabContainer addSubview:closeButton];

        [_stripView addSubview:tabContainer];
        x += width + 4.0;
    }
}

- (void)tabButtonPressed:(id)sender
{
    NSInteger index = [sender tag];
    [_delegate selectDocumentTabAtIndex:index];
}

- (void)tabCloseButtonPressed:(id)sender
{
    NSInteger index = [sender tag];
    [_delegate closeDocumentTabAtIndex:index];
}

- (NSInteger)documentTabIndexForRemoteURL:(NSString *)rawURL
{
    if ([rawURL length] == 0) {
        return -1;
    }
    NSInteger index = 0;
    for (; index < (NSInteger)[_tabs count]; index++) {
        if ([rawURL isEqualToString:[[_tabs objectAtIndex:index] remoteURL]]) {
            return index;
        }
    }
    return -1;
}

- (NSInteger)documentTabIndexForLocalPath:(NSString *)sourcePath
{
    NSString *targetPath = OMDTrimmedString(sourcePath);
    if ([targetPath length] == 0) {
        return -1;
    }
    targetPath = [targetPath stringByStandardizingPath];

    NSInteger index = 0;
    for (; index < (NSInteger)[_tabs count]; index++) {
        NSString *tabPath = OMDTrimmedString([[_tabs objectAtIndex:index] sourcePath]);
        if ([tabPath length] == 0) {
            continue;
        }
        tabPath = [tabPath stringByStandardizingPath];
        if ([tabPath isEqualToString:targetPath]) {
            return index;
        }
    }
    return -1;
}

@end
