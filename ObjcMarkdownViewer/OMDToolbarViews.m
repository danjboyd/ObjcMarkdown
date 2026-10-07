// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDToolbarViews.h"
#import "OMDViewerColors.h"

#include <math.h>

@implementation OMDToolbarToolTipView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _toolTipRects = [[NSMutableArray alloc] init];
        _toolTipStrings = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_toolTipRects release];
    [_toolTipStrings release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)rebuildToolTipRects
{
    [self removeAllToolTips];
    NSUInteger count = [_toolTipRects count];
    for (NSUInteger i = 0; i < count; i++) {
        [self addToolTipRect:[[_toolTipRects objectAtIndex:i] rectValue]
                       owner:self
                    userData:(void *)((NSInteger)i)];
    }
}

- (void)setFrame:(NSRect)frameRect
{
    [super setFrame:frameRect];
    [self rebuildToolTipRects];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self rebuildToolTipRects];
}

- (void)setToolTip:(NSString *)toolTip forRect:(NSRect)rect
{
    if (toolTip == nil) {
        toolTip = @"";
    }

    NSUInteger count = [_toolTipRects count];
    for (NSUInteger i = 0; i < count; i++) {
        if (NSEqualRects([[_toolTipRects objectAtIndex:i] rectValue], rect)) {
            [_toolTipStrings replaceObjectAtIndex:i withObject:toolTip];
            [self rebuildToolTipRects];
            return;
        }
    }

    [_toolTipRects addObject:[NSValue valueWithRect:rect]];
    [_toolTipStrings addObject:toolTip];
    [self rebuildToolTipRects];
}

- (NSString *)view:(NSView *)view
  stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point
          userData:(void *)data
{
    (void)view;
    (void)tag;
    (void)point;
    NSInteger index = (NSInteger)data;
    if (index < 0 || index >= (NSInteger)[_toolTipStrings count]) {
        return nil;
    }
    NSString *toolTip = [_toolTipStrings objectAtIndex:(NSUInteger)index];
    return [toolTip length] > 0 ? toolTip : nil;
}

@end

