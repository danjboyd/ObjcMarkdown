// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDPreferencesPopup.h"
#import "OMDViewerColors.h"

#if defined(_WIN32)
#include <windows.h>
#endif
#include <math.h>

static NSPanel *OMDActivePreferencesPopupPanel = nil;
#if defined(_WIN32)
static WNDPROC OMDOriginalPreferencesPopupWndProc = NULL;
#endif

@interface OMDPreferencesPopupMenuView : NSView
{
    NSPopUpButton *_popupButton;
    NSPanel *_panel;
    CGFloat _rowHeight;
    NSInteger _hoveredIndex;
    BOOL _trackingMouseDown;
}
- (instancetype)initWithPopupButton:(NSPopUpButton *)popupButton
                               size:(NSSize)size
                              panel:(NSPanel *)panel;
#if defined(_WIN32)
- (void)updateHoverFromScreenX:(int)x y:(int)y;
- (void)commitSelectionFromScreenX:(int)x y:(int)y;
- (BOOL)screenPointIsInsideX:(int)x y:(int)y;
- (void)dismissPopup;
#endif
@end

@implementation OMDPreferencesPopupMenuView

- (instancetype)initWithPopupButton:(NSPopUpButton *)popupButton
                               size:(NSSize)size
                              panel:(NSPanel *)panel
{
    self = [super initWithFrame:NSMakeRect(0.0, 0.0, size.width, size.height)];
    if (self != nil) {
        _popupButton = popupButton;
        _panel = panel;
        _rowHeight = 32.0;
        _hoveredIndex = -1;
        _trackingMouseDown = NO;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSInteger)itemIndexForPoint:(NSPoint)point
{
    NSInteger index = (NSInteger)floor(point.y / _rowHeight);
    if (index < 0 || index >= [_popupButton numberOfItems]) {
        return -1;
    }
    return index;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if ([self window] != nil) {
        [[self window] setAcceptsMouseMovedEvents:YES];
    }
}

- (void)updateHoverForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger index = [self itemIndexForPoint:point];
    if (index != _hoveredIndex) {
        _hoveredIndex = index;
        [self setNeedsDisplay:YES];
    }
}

- (void)restoreOwnerWindow:(NSWindow *)ownerWindow
{
    if (ownerWindow == nil) {
        return;
    }

    [ownerWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
#if defined(_WIN32)
    if ([ownerWindow respondsToSelector:@selector(windowHandle)]) {
        HWND ownerHwnd = (HWND)[ownerWindow windowHandle];
        if (ownerHwnd != NULL) {
            BringWindowToTop(ownerHwnd);
            SetForegroundWindow(ownerHwnd);
        }
    }
#endif
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = [self bounds];
    NSColor *background = OMDResolvedControlBackgroundColor();
    NSColor *border = OMDResolvedPanelCardBorderColor();
    NSColor *textColor = OMDResolvedControlTextColor();
    NSColor *selection = OMDColorByBlending(OMDResolvedAccentColor(), background, 0.82);
    NSColor *hover = OMDColorByBlending(OMDResolvedAccentColor(), background, 0.90);
    NSFont *font = [_popupButton font];
    NSInteger selectedIndex = [_popupButton indexOfSelectedItem];
    NSInteger activeIndex = (_hoveredIndex >= 0 ? _hoveredIndex : selectedIndex);
    NSInteger count = [_popupButton numberOfItems];
    NSInteger index = 0;

    (void)dirtyRect;

    if (font == nil) {
        font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    [background setFill];
    NSRectFill(bounds);
    [border setStroke];
    NSFrameRect(NSInsetRect(bounds, 0.5, 0.5));

    for (index = 0; index < count; index++) {
        NSRect rowRect = NSMakeRect(4.0,
                                    4.0 + (_rowHeight * index),
                                    MAX(0.0, NSWidth(bounds) - 8.0),
                                    _rowHeight - 2.0);
        NSString *title = [[_popupButton itemAtIndex:index] title];
        NSDictionary *attributes = nil;
        NSSize titleSize = NSZeroSize;
        NSRect titleRect = rowRect;

        if (index == activeIndex) {
            NSColor *rowFill = (index == selectedIndex && _hoveredIndex < 0) ? selection : hover;
            [rowFill setFill];
            NSRectFill(rowRect);
        }

        attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                      font, NSFontAttributeName,
                      textColor, NSForegroundColorAttributeName,
                      nil];
        titleSize = [title sizeWithAttributes:attributes];
        titleRect.origin.x += 10.0;
        titleRect.size.width = MAX(0.0, titleRect.size.width - 20.0);
        titleRect.origin.y = floor(NSMidY(rowRect) - (titleSize.height / 2.0));
        titleRect.size.height = ceil(titleSize.height) + 1.0;
        [title drawInRect:titleRect withAttributes:attributes];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    [self updateHoverForEvent:event];
}

- (void)mouseEntered:(NSEvent *)event
{
    [self updateHoverForEvent:event];
}

- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    if (_hoveredIndex != -1) {
        _hoveredIndex = -1;
        [self setNeedsDisplay:YES];
    }
}

- (void)commitIndex:(NSInteger)index
{
    NSWindow *ownerWindow = [[_popupButton window] retain];
    id target = [_popupButton target];
    SEL action = [_popupButton action];
    NSInteger oldIndex = [_popupButton indexOfSelectedItem];
    BOOL changed = NO;

    if (index >= 0) {
        [_popupButton selectItemAtIndex:index];
        [_popupButton setNeedsDisplay:YES];
        changed = (index != oldIndex);
    }

    _trackingMouseDown = NO;
    [_panel close];
    OMDActivePreferencesPopupPanel = nil;

    if (changed && target != nil && action != NULL) {
        [NSApp sendAction:action to:target from:_popupButton];
    }
    [self restoreOwnerWindow:ownerWindow];
    [ownerWindow release];
}

#if defined(_WIN32)
- (NSInteger)itemIndexForScreenX:(int)x y:(int)y
{
    HWND hwnd = (_panel != nil && [_panel respondsToSelector:@selector(windowHandle)])
        ? (HWND)[_panel windowHandle]
        : NULL;
    RECT windowRect;
    NSInteger index = -1;

    (void)x;

    if (hwnd == NULL || GetWindowRect(hwnd, &windowRect) == 0) {
        return -1;
    }

    index = (NSInteger)floor(((CGFloat)(y - windowRect.top)) / _rowHeight);
    if (index < 0 || index >= [_popupButton numberOfItems]) {
        return -1;
    }
    return index;
}

- (BOOL)screenPointIsInsideX:(int)x y:(int)y
{
    HWND hwnd = (_panel != nil && [_panel respondsToSelector:@selector(windowHandle)])
        ? (HWND)[_panel windowHandle]
        : NULL;
    RECT windowRect;

    if (hwnd == NULL || GetWindowRect(hwnd, &windowRect) == 0) {
        return NO;
    }

    return (x >= windowRect.left
            && x < windowRect.right
            && y >= windowRect.top
            && y < windowRect.bottom);
}

- (void)updateHoverFromScreenX:(int)x y:(int)y
{
    NSInteger index = [self itemIndexForScreenX:x y:y];
    if (index != _hoveredIndex) {
        _hoveredIndex = index;
        [self setNeedsDisplay:YES];
    }
}

- (void)commitSelectionFromScreenX:(int)x y:(int)y
{
    NSInteger index = [self itemIndexForScreenX:x y:y];
    [self commitIndex:index];
}

- (void)dismissPopup
{
    NSWindow *ownerWindow = [[_popupButton window] retain];

    _trackingMouseDown = NO;
    [_panel close];
    OMDActivePreferencesPopupPanel = nil;
    [self restoreOwnerWindow:ownerWindow];
    [ownerWindow release];
}
#endif

- (void)mouseDown:(NSEvent *)event
{
    _trackingMouseDown = YES;
    [self updateHoverForEvent:event];

    while (_trackingMouseDown && [self window] != nil) {
        NSEvent *nextEvent = [[self window] nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
        if (nextEvent == nil) {
            break;
        }
        if ([nextEvent type] == NSLeftMouseDragged) {
            [self updateHoverForEvent:nextEvent];
        } else if ([nextEvent type] == NSLeftMouseUp) {
            [self mouseUp:nextEvent];
            break;
        }
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_trackingMouseDown) {
        [self updateHoverForEvent:event];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    NSInteger index = -1;

    [self updateHoverForEvent:event];
    index = _hoveredIndex;
    if (index < 0) {
        NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
        index = [self itemIndexForPoint:point];
    }

    [self commitIndex:index];
}

- (void)resetCursorRects
{
    [self addTrackingRect:[self bounds]
                    owner:self
                 userData:NULL
             assumeInside:NO];
}

@end

#if defined(_WIN32)
static LRESULT CALLBACK OMDPreferencesPopupWindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    id view = (id)GetPropW(hwnd, L"OMDPreferencesPopupView");
    POINT cursorPoint;

    (void)wParam;
    (void)lParam;

    if (view != nil) {
        if (message == WM_ACTIVATE && LOWORD(wParam) == WA_INACTIVE) {
            if (OMDActivePreferencesPopupPanel != nil) {
                [OMDActivePreferencesPopupPanel close];
                OMDActivePreferencesPopupPanel = nil;
            }
            return 0;
        }
        if (message == WM_KILLFOCUS) {
            if (OMDActivePreferencesPopupPanel != nil) {
                [OMDActivePreferencesPopupPanel close];
                OMDActivePreferencesPopupPanel = nil;
            }
            return 0;
        }
        if (message == WM_LBUTTONDOWN) {
            if (GetCursorPos(&cursorPoint)) {
                if (![view screenPointIsInsideX:cursorPoint.x y:cursorPoint.y]) {
                    ReleaseCapture();
                    [view dismissPopup];
                    return 0;
                }
                [view updateHoverFromScreenX:cursorPoint.x y:cursorPoint.y];
            }
            return 0;
        }
        if (message == WM_MOUSEMOVE) {
            if (GetCursorPos(&cursorPoint)) {
                [view updateHoverFromScreenX:cursorPoint.x y:cursorPoint.y];
            }
            return 0;
        }
        if (message == WM_LBUTTONUP) {
            if (GetCursorPos(&cursorPoint)) {
                if ([view screenPointIsInsideX:cursorPoint.x y:cursorPoint.y]) {
                    ReleaseCapture();
                    [view commitSelectionFromScreenX:cursorPoint.x y:cursorPoint.y];
                }
            }
            return 0;
        }
    }

    if (OMDOriginalPreferencesPopupWndProc != NULL) {
        return CallWindowProcW(OMDOriginalPreferencesPopupWndProc, hwnd, message, wParam, lParam);
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

static void OMDInstallPreferencesPopupWindowProc(NSPanel *panel, NSView *view)
{
    HWND hwnd = NULL;
    LONG_PTR currentProc = 0;

    if (panel == nil || view == nil || ![panel respondsToSelector:@selector(windowHandle)]) {
        return;
    }

    hwnd = (HWND)[panel windowHandle];
    if (hwnd == NULL) {
        return;
    }

    SetPropW(hwnd, L"OMDPreferencesPopupView", (HANDLE)view);
    currentProc = GetWindowLongPtrW(hwnd, GWLP_WNDPROC);
    if ((WNDPROC)currentProc != OMDPreferencesPopupWindowProc) {
        OMDOriginalPreferencesPopupWndProc = (WNDPROC)currentProc;
        SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)OMDPreferencesPopupWindowProc);
    }
    SetCapture(hwnd);
}
#endif

static OMDPreferencesPopupMenuView *OMDShowPreferencesPopupMenu(NSPopUpButton *popup)
{
    NSInteger itemCount = [popup numberOfItems];
    CGFloat rowHeight = 32.0;
    NSRect popupBounds = [popup bounds];
    NSPoint screenPoint = NSZeroPoint;
    NSRect panelFrame = NSZeroRect;
    NSPanel *panel = nil;
    OMDPreferencesPopupMenuView *menuView = nil;

    if (popup == nil || [popup window] == nil || itemCount <= 0) {
        return nil;
    }

    if (OMDActivePreferencesPopupPanel != nil) {
        [OMDActivePreferencesPopupPanel close];
        OMDActivePreferencesPopupPanel = nil;
    }

    screenPoint = [popup convertPoint:NSMakePoint(NSMinX(popupBounds), NSMaxY(popupBounds))
                               toView:nil];
    screenPoint = [[popup window] convertBaseToScreen:screenPoint];
    panelFrame = NSMakeRect(screenPoint.x,
                            screenPoint.y - (rowHeight * itemCount) - 4.0,
                            NSWidth([popup frame]),
                            (rowHeight * itemCount) + 8.0);
    panel = [[NSPanel alloc] initWithContentRect:panelFrame
                                       styleMask:NSBorderlessWindowMask
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
    [panel setReleasedWhenClosed:YES];
    [panel setLevel:NSPopUpMenuWindowLevel];
    [panel setBackgroundColor:OMDResolvedControlBackgroundColor()];
    [panel setOpaque:YES];
    [panel setAcceptsMouseMovedEvents:YES];
    menuView = [[[OMDPreferencesPopupMenuView alloc] initWithPopupButton:popup
                                                                    size:panelFrame.size
                                                                   panel:panel] autorelease];
    [panel setContentView:menuView];
    OMDActivePreferencesPopupPanel = panel;
    [panel makeKeyAndOrderFront:nil];
#if defined(_WIN32)
    OMDInstallPreferencesPopupWindowProc(panel, menuView);
#endif
    return menuView;
}

@interface OMDPreferencesPopupOverlayView : NSView
{
    NSPopUpButton *_popupButton;
}
- (instancetype)initWithFrame:(NSRect)frame popupButton:(NSPopUpButton *)popupButton;
@end

@implementation OMDPreferencesPopupOverlayView

- (instancetype)initWithFrame:(NSRect)frame popupButton:(NSPopUpButton *)popupButton
{
    self = [super initWithFrame:frame];
    if (self != nil) {
        _popupButton = popupButton;
        [self setAutoresizingMask:[popupButton autoresizingMask]];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSView *)hitTest:(NSPoint)point
{
    return [self isHidden] ? nil : self;
}

- (void)mouseDown:(NSEvent *)event
{
    (void)event;
    OMDShowPreferencesPopupMenu(_popupButton);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *fieldPath = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7.0 yRadius:7.0];
    NSColor *background = OMDResolvedControlBackgroundColor();
    NSColor *border = OMDResolvedPanelCardBorderColor();
    NSColor *textColor = ([_popupButton isEnabled] ? OMDResolvedControlTextColor() : OMDResolvedMutedTextColor());
    NSString *title = [[_popupButton selectedItem] title];
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSFont *font = [_popupButton font];
    CGFloat arrowLaneWidth = 34.0;
    NSRect titleRect = NSMakeRect(NSMinX(bounds) + 12.0,
                                  NSMinY(bounds),
                                  MAX(0.0, NSWidth(bounds) - arrowLaneWidth - 18.0),
                                  NSHeight(bounds));
    NSSize titleSize = NSZeroSize;
    NSBezierPath *chevron = [NSBezierPath bezierPath];
    CGFloat centerX = NSMaxX(bounds) - (arrowLaneWidth / 2.0);
    CGFloat centerY = NSMidY(bounds);

    (void)dirtyRect;

    if (title == nil) {
        title = @"";
    }
    if (font == nil) {
        font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    [background setFill];
    [fieldPath fill];
    [border setStroke];
    [fieldPath setLineWidth:1.0];
    [fieldPath stroke];

    [attributes setObject:font forKey:NSFontAttributeName];
    [attributes setObject:textColor forKey:NSForegroundColorAttributeName];
    titleSize = [title sizeWithAttributes:attributes];
    titleRect.origin.y = floor(NSMidY(bounds) - (titleSize.height / 2.0));
    titleRect.size.height = ceil(titleSize.height) + 1.0;
    [title drawInRect:titleRect withAttributes:attributes];

    [border setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(bounds) - arrowLaneWidth, NSMinY(bounds) + 7.0)
                              toPoint:NSMakePoint(NSMaxX(bounds) - arrowLaneWidth, NSMaxY(bounds) - 7.0)];

    [textColor setStroke];
    [chevron setLineWidth:1.8];
    [chevron setLineCapStyle:NSRoundLineCapStyle];
    [chevron setLineJoinStyle:NSRoundLineJoinStyle];
    [chevron moveToPoint:NSMakePoint(centerX - 4.0, centerY - 2.0)];
    [chevron lineToPoint:NSMakePoint(centerX, centerY + 2.0)];
    [chevron lineToPoint:NSMakePoint(centerX + 4.0, centerY - 2.0)];
    [chevron stroke];
}

@end

void OMDAddPreferencesPopupOverlay(NSView *container, NSPopUpButton *popup)
{
#if defined(_WIN32)
    OMDPreferencesPopupOverlayView *overlay = nil;

    if (container == nil || popup == nil) {
        return;
    }

    overlay = [[[OMDPreferencesPopupOverlayView alloc] initWithFrame:[popup frame]
                                                         popupButton:popup] autorelease];
    [overlay setAutoresizingMask:[popup autoresizingMask]];
    [container addSubview:overlay];
#else
    (void)container;
    (void)popup;
#endif
}
