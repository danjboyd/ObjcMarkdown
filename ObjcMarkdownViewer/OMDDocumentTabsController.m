// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDDocumentTabsController.h"
#import "OMDTextFileSupport.h"

#include <math.h>

NSString * const OMDTabMarkdownKey = @"markdown";
NSString * const OMDTabSourcePathKey = @"sourcePath";
NSString * const OMDTabDisplayTitleKey = @"displayTitle";
NSString * const OMDTabDirtyKey = @"dirty";
NSString * const OMDTabReadOnlyKey = @"readOnly";
NSString * const OMDTabRenderModeKey = @"renderMode";
NSString * const OMDTabSyntaxLanguageKey = @"syntaxLanguage";
NSString * const OMDTabLoadedDiskFingerprintKey = @"loadedDiskFingerprint";
NSString * const OMDTabObservedDiskFingerprintKey = @"observedDiskFingerprint";
NSString * const OMDTabSuppressedDiskFingerprintKey = @"suppressedDiskFingerprint";
NSString * const OMDTabImageFingerprintsKey = @"imageFingerprints";
NSString * const OMDTabSuppressedImageFingerprintsKey = @"suppressedImageFingerprints";
NSString * const OMDTabImageMarkdownKey = @"imageMarkdown";
NSString * const OMDTabImageSourcePathKey = @"imageSourcePath";

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

- (NSMutableDictionary *)tabAtIndex:(NSInteger)index
{
    return [_tabs objectAtIndex:index];
}

- (void)addTab:(NSMutableDictionary *)tab
{
    [_tabs addObject:tab];
}

- (void)replaceTabAtIndex:(NSInteger)index withTab:(NSMutableDictionary *)tab
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

- (NSMutableDictionary *)selectedTab
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
        [label setFont:[NSFont systemFontOfSize:11.0]];
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
        NSDictionary *tab = [_tabs objectAtIndex:index];
        NSString *title = [tab objectForKey:OMDTabDisplayTitleKey];
        if (title == nil || [title length] == 0) {
            NSString *path = [tab objectForKey:OMDTabSourcePathKey];
            title = (path != nil ? [path lastPathComponent] : @"Untitled");
        }
        if ([[tab objectForKey:OMDTabDirtyKey] boolValue]) {
            title = [title stringByAppendingString:@" *"];
        }
        if ([[tab objectForKey:OMDTabReadOnlyKey] boolValue]) {
            title = [title stringByAppendingString:@" [RO]"];
        }

        CGFloat width = 30.0 + (CGFloat)[title length] * 6.8;
        if (width < 108.0) {
            width = 108.0;
        }
        if (width > 240.0) {
            width = 240.0;
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
        [button setFont:[NSFont systemFontOfSize:11.0]];
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
        [closeButton setFont:[NSFont boldSystemFontOfSize:10.0]];
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

- (NSInteger)documentTabIndexForLocalPath:(NSString *)sourcePath
{
    NSString *targetPath = OMDTrimmedString(sourcePath);
    if ([targetPath length] == 0) {
        return -1;
    }
    targetPath = [targetPath stringByStandardizingPath];

    NSInteger index = 0;
    for (; index < (NSInteger)[_tabs count]; index++) {
        NSDictionary *tab = [_tabs objectAtIndex:index];
        NSString *tabPath = OMDTrimmedString([tab objectForKey:OMDTabSourcePathKey]);
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
