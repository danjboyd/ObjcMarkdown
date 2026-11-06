// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDCopyButtonsController.h"
#import "OMDRenderResult.h"
#import "OMDLayoutMetrics.h"
#import "OMDCodeCopyButton.h"
#import "OMDTextView.h"
#import "OMDViewerColors.h"
#import "OMDViewerImages.h"
#import "OMMarkdownRenderer.h"
#import "OMRenderedObject.h"

#include <math.h>

static const NSTimeInterval OMDCopyFeedbackDisplayInterval = 0.95;

@interface OMDCopyButtonsController ()
- (NSArray *)displayMathObjectRanges;
- (void)addCopySlotsForRanges:(NSArray *)ranges
                       action:(SEL)action
                      toolTip:(NSString *)toolTip
                 blockPadding:(NSSize)blockPadding
           matchCodeBlockEdge:(BOOL)matchCodeBlockEdge;
- (BOOL)frameForCopySlot:(NSDictionary *)slot frame:(NSRect *)frameOut;
- (void)observeClipViewOfTextView:(NSTextView *)textView;
- (void)removeButtonForSlot:(NSNumber *)slot;
- (void)applyCopyButtonDefaultAppearance:(NSButton *)button;
- (void)showCopyFeedbackForButton:(NSButton *)button;
@end

@implementation OMDCopyButtonsController

- (instancetype)initWithDelegate:(id<OMDCopyButtonsControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        _codeBlockButtons = [[NSMutableArray alloc] init];
        _copySlots = [[NSMutableArray alloc] init];
        _buttonsBySlot = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [self observeClipViewOfTextView:nil];
    [self hideCopyFeedback];
    [_codeBlockButtons release];
    [_copySlots release];
    [_buttonsBySlot release];
    [super dealloc];
}

- (void)removeCopyButtons
{
    for (NSButton *button in _codeBlockButtons) {
        [button removeFromSuperview];
    }
    [_codeBlockButtons removeAllObjects];
    [_buttonsBySlot removeAllObjects];
    [_copySlots removeAllObjects];
}

// Buttons are made only for blocks near what's visible, so scrolling has to
// update them. A document with 1,600 code blocks had 1,600 buttons, each
// with its cursor rect, tracking rect and tooltip: about 12 s of the main
// thread over one scroll through it (#346).
- (void)observeClipViewOfTextView:(NSTextView *)textView
{
    NSView *clipView = [[textView enclosingScrollView] contentView];
    if (clipView == _observedClipView) {
        return;
    }
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_observedClipView != nil) {
        [center removeObserver:self name:NSViewBoundsDidChangeNotification object:_observedClipView];
        [center removeObserver:self name:NSViewFrameDidChangeNotification object:_observedClipView];
        [_observedClipView release];
        _observedClipView = nil;
    }
    if (clipView != nil) {
        _observedClipView = [clipView retain];
        [clipView setPostsBoundsChangedNotifications:YES];
        [clipView setPostsFrameChangedNotifications:YES];
        [center addObserver:self selector:@selector(clipViewDidChange:)
                       name:NSViewBoundsDidChangeNotification object:clipView];
        [center addObserver:self selector:@selector(clipViewDidChange:)
                       name:NSViewFrameDidChangeNotification object:clipView];
    }
}

- (void)clipViewDidChange:(NSNotification *)notification
{
    if ([_copySlots count] > 0) {
        [self updateVisibleCopyButtons];
    }
}

- (void)updateCodeBlockButtons
{
    NSTextView *textView = [_delegate previewTextView];
    OMDRenderResult *renderResult = [_delegate previewRenderResult];
    [self hideCopyFeedback];

    if (_codeBlockButtons == nil) {
        _codeBlockButtons = [[NSMutableArray alloc] init];
    }
    for (NSButton *button in _codeBlockButtons) {
        [button removeFromSuperview];
    }
    [_codeBlockButtons removeAllObjects];
    [_buttonsBySlot removeAllObjects];
    [_copySlots removeAllObjects];
    [self observeClipViewOfTextView:textView];

    NSArray *codeRanges = [renderResult codeBlockRanges];
    NSArray *diagramBlocks = [renderResult diagramBlocks];
    NSArray *displayMathRanges = [self displayMathObjectRanges];

    NSLayoutManager *layoutManager = [textView layoutManager];
    NSTextContainer *container = [textView textContainer];
    if (layoutManager == nil || container == nil) {
        return;
    }
    [layoutManager ensureLayoutForTextContainer:container];
    [_delegate previewDidLayoutForCopyButtons];
    if ([codeRanges count] == 0 && [diagramBlocks count] == 0 && [displayMathRanges count] == 0) {
        return;
    }

    NSSize blockPadding = NSMakeSize(12.0, 8.0);
    if ([textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *codeView = (OMDTextView *)textView;
        if (codeView.codeBlockPadding.width > 0.0 && codeView.codeBlockPadding.height > 0.0) {
            blockPadding = codeView.codeBlockPadding;
        }
    }

    [self addCopySlotsForRanges:codeRanges
                         action:@selector(copyCodeBlock:)
                        toolTip:@"Copy code block"
                   blockPadding:blockPadding
             matchCodeBlockEdge:NO];

    // Diagrams are centred attachments: their button goes at the code blocks'
    // right edge, level with the diagram's top.
    NSMutableArray *diagramRanges = [NSMutableArray arrayWithCapacity:[diagramBlocks count]];
    for (NSDictionary *block in diagramBlocks) {
        NSValue *range = [block objectForKey:OMMarkdownRendererDiagramRangeKey];
        if (range != nil) {
            [diagramRanges addObject:range];
        }
    }
    [self addCopySlotsForRanges:diagramRanges
                         action:@selector(copyDiagramBlock:)
                        toolTip:@"Copy diagram source"
                   blockPadding:blockPadding
             matchCodeBlockEdge:YES];

    // Equations are narrow and centred: put the button just right of the
    // formula instead of over its corner (button 20 + 6 inset + 6 gap).
    [self addCopySlotsForRanges:displayMathRanges
                         action:@selector(copyDisplayMathBlock:)
                        toolTip:@"Copy equation source"
                   blockPadding:NSMakeSize(32.0, 0.0)
             matchCodeBlockEdge:NO];
    // In document order, so a scroll finds the blocks near it by bisection.
    [_copySlots sortUsingFunction:OMDCompareCopySlots context:NULL];
    [self updateVisibleCopyButtons];
}

- (NSArray *)displayMathObjectRanges
{
    NSTextView *textView = [_delegate previewTextView];
    NSMutableArray *ranges = [NSMutableArray array];
    NSTextStorage *storage = [textView textStorage];
    NSUInteger length = [storage length];
    NSUInteger index = 0;
    while (index < length) {
        NSRange effective;
        OMRenderedObject *object = [storage attribute:OMRenderedObjectAttributeName
                                              atIndex:index
                                       effectiveRange:&effective];
        if (object != nil && [object kind] == OMRenderedObjectKindDisplayMath) {
            NSUInteger location = effective.location;
            for (; location < NSMaxRange(effective); location++) {
                [ranges addObject:[NSValue valueWithRange:NSMakeRange(location, 1)]];
            }
        }
        index = NSMaxRange(effective);
    }
    return ranges;
}

- (void)copyDisplayMathBlock:(id)sender
{
    NSTextView *textView = [_delegate previewTextView];
    NSArray *ranges = [self displayMathObjectRanges];
    NSInteger index = [sender tag];
    if (index < 0 || index >= (NSInteger)[ranges count]) {
        return;
    }
    NSRange range = [[ranges objectAtIndex:index] rangeValue];
    OMRenderedObject *object = [[textView textStorage] attribute:OMRenderedObjectAttributeName
                                                          atIndex:range.location
                                                   effectiveRange:NULL];
    if (object == nil) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pasteboard setString:[[object source] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                  forType:NSStringPboardType];
    if ([sender isKindOfClass:[NSButton class]]) {
        [self showCopyFeedbackForButton:(NSButton *)sender];
    }
}

static NSInteger OMDCompareCopySlots(id a, id b, void *context)
{
    NSUInteger left = [[a objectForKey:@"range"] rangeValue].location;
    NSUInteger right = [[b objectForKey:@"range"] rangeValue].location;
    return left < right ? NSOrderedAscending : (left > right ? NSOrderedDescending : NSOrderedSame);
}

// One slot per block: what its button does and where it goes. The tag is
// the block's index in its own list, as the copy actions expect.
- (void)addCopySlotsForRanges:(NSArray *)ranges
                       action:(SEL)action
                      toolTip:(NSString *)toolTip
                 blockPadding:(NSSize)blockPadding
           matchCodeBlockEdge:(BOOL)matchCodeBlockEdge
{
    NSInteger index = 0;
    for (NSValue *value in ranges) {
        if ([value rangeValue].length > 0) {
            [_copySlots addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                   value, @"range",
                                   NSStringFromSelector(action), @"action",
                                   toolTip, @"toolTip",
                                   [NSValue valueWithSize:blockPadding], @"padding",
                                   [NSNumber numberWithBool:matchCodeBlockEdge], @"matchEdge",
                                   [NSNumber numberWithInteger:index], @"tag",
                                   nil]];
        }
        index++;
    }
}

- (BOOL)frameForCopySlot:(NSDictionary *)slot frame:(NSRect *)frameOut
{
    NSTextView *textView = [_delegate previewTextView];
    OMDRenderResult *renderResult = [_delegate previewRenderResult];
    NSLayoutManager *layoutManager = [textView layoutManager];
    NSTextContainer *container = [textView textContainer];
    NSRange charRange = [[slot objectForKey:@"range"] rangeValue];
    NSSize blockPadding = [[slot objectForKey:@"padding"] sizeValue];
    NSPoint textOrigin = [textView textContainerOrigin];

    NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
    if (glyphRange.length == 0) {
        return NO;
    }

    NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];
    if ([[slot objectForKey:@"matchEdge"] boolValue]) {
        // A code block's text runs to the line end less its tail inset.
        NSRect fragment = [layoutManager lineFragmentRectForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
        CGFloat codeTailInset = 20.0 * ([renderResult zoomScale] > 0.0 ? [renderResult zoomScale] : 1.0);
        CGFloat right = NSMaxX(fragment) - [container lineFragmentPadding] - codeTailInset;
        blockRect.size.width = MAX(1.0, right - NSMinX(blockRect));
    }

    CGFloat buttonWidth = 20.0;
    CGFloat buttonHeight = 20.0;
    NSRect blockBounds = NSMakeRect(textOrigin.x + blockRect.origin.x - blockPadding.width,
                                    textOrigin.y + blockRect.origin.y - blockPadding.height,
                                    blockRect.size.width + (blockPadding.width * 2.0),
                                    blockRect.size.height + (blockPadding.height * 2.0));
    if (blockBounds.size.width < 1.0 || blockBounds.size.height < 1.0) {
        return NO;
    }

    CGFloat x = NSMaxX(blockBounds) - buttonWidth - 6.0;
    CGFloat y = 0.0;
    if ([textView isFlipped]) {
        y = NSMinY(blockBounds) + 4.0;
    } else {
        y = NSMaxY(blockBounds) - buttonHeight - 4.0;
    }

    CGFloat minX = 2.0;
    CGFloat maxX = NSWidth([textView bounds]) - buttonWidth - 2.0;
    if (x < minX) {
        x = minX;
    }
    if (x > maxX) {
        x = maxX;
    }

    CGFloat minY = 2.0;
    CGFloat maxY = NSHeight([textView bounds]) - buttonHeight - 2.0;
    if (y < minY) {
        y = minY;
    }
    if (y > maxY) {
        y = maxY;
    }

    *frameOut = NSIntegralRect(NSMakeRect(x, y, buttonWidth, buttonHeight));
    return YES;
}

- (void)removeButtonForSlot:(NSNumber *)slot
{
    NSButton *button = [_buttonsBySlot objectForKey:slot];
    if (button == nil) {
        return;
    }
    if (button == _copyFeedbackButton) {
        [self hideCopyFeedback];
    }
    [button removeFromSuperview];
    [_codeBlockButtons removeObjectIdenticalTo:button];
    [_buttonsBySlot removeObjectForKey:slot];
}

- (NSUInteger)updateVisibleCopyButtons
{
    NSTextView *textView = [_delegate previewTextView];
    NSLayoutManager *layoutManager = [textView layoutManager];
    NSTextContainer *container = [textView textContainer];
    if (textView == nil || layoutManager == nil || container == nil || [_copySlots count] == 0) {
        return [_codeBlockButtons count];
    }

    // What's visible and a screen above and below, so a button is there
    // before its block scrolls in. Without a scroll view, everything.
    NSRect visible = [textView visibleRect];
    NSRange nearby = NSMakeRange(0, [[textView textStorage] length]);
    if ([textView enclosingScrollView] != nil && NSHeight(visible) > 0.0) {
        NSRect area = NSInsetRect(visible, 0.0, -NSHeight(visible));
        NSPoint origin = [textView textContainerOrigin];
        area.origin.x -= origin.x;
        area.origin.y -= origin.y;
        NSRange glyphs = [layoutManager glyphRangeForBoundingRect:area inTextContainer:container];
        nearby = [layoutManager characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
    }

    // Drop the buttons of blocks no longer nearby (there are only a few).
    for (NSNumber *key in [_buttonsBySlot allKeys]) {
        NSRange range = [[[_copySlots objectAtIndex:[key unsignedIntegerValue]] objectForKey:@"range"] rangeValue];
        if (NSMaxRange(range) < nearby.location || range.location > NSMaxRange(nearby)) {
            [self removeButtonForSlot:key];
        }
    }

    // The first slot that may touch that range: blocks don't overlap, so ranges
    // end in the same order they start.
    NSUInteger low = 0;
    NSUInteger high = [_copySlots count];
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        NSRange range = [[[_copySlots objectAtIndex:middle] objectForKey:@"range"] rangeValue];
        if (NSMaxRange(range) < nearby.location) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }

    NSUInteger slotIndex = low;
    for (; slotIndex < [_copySlots count]; slotIndex++) {
        NSDictionary *slot = [_copySlots objectAtIndex:slotIndex];
        NSRange range = [[slot objectForKey:@"range"] rangeValue];
        if (range.location > NSMaxRange(nearby)) {
            break;
        }
        NSNumber *key = [NSNumber numberWithUnsignedInteger:slotIndex];
        if ([_buttonsBySlot objectForKey:key] != nil) {
            continue;
        }
        NSRect frame;
        if (![self frameForCopySlot:slot frame:&frame]) {
            continue;
        }
        NSString *toolTip = [slot objectForKey:@"toolTip"];
        OMDCodeCopyButton *button = [[OMDCodeCopyButton alloc] initWithFrame:frame];
        [self applyCopyButtonDefaultAppearance:button];
        [button setButtonType:NSMomentaryChangeButton];
        [button setBordered:NO];
        [button setToolTip:toolTip];
        // The image has no words: name the button for VoiceOver. GNUstep
        // doesn't declare the method; use it there only if it exists.
#if defined(GNUSTEP)
        if ([button respondsToSelector:@selector(setAccessibilityLabel:)]) {
            [button performSelector:@selector(setAccessibilityLabel:) withObject:toolTip];
        }
#else
        [button setAccessibilityLabel:toolTip];
#endif
        id buttonCell = [button cell];
        if (buttonCell != nil && [buttonCell respondsToSelector:@selector(setImageScaling:)]) {
            [buttonCell setImageScaling:NSImageScaleNone];
        }
        if (buttonCell != nil && [buttonCell respondsToSelector:@selector(setHighlightsBy:)]) {
            [buttonCell setHighlightsBy:NSNoCellMask];
        }
        [button setTarget:self];
        [button setAction:NSSelectorFromString([slot objectForKey:@"action"])];
        [button setTag:[[slot objectForKey:@"tag"] integerValue]];
        [textView addSubview:button];
        [_codeBlockButtons addObject:button];
        [_buttonsBySlot setObject:button forKey:key];
        [button release];
    }
    return [_codeBlockButtons count];
}

- (void)copyDiagramBlock:(id)sender
{
    OMDRenderResult *renderResult = [_delegate previewRenderResult];
    NSInteger index = [sender tag];
    NSArray *blocks = [renderResult diagramBlocks];
    if (index < 0 || index >= (NSInteger)[blocks count]) {
        return;
    }

    NSString *source = [[blocks objectAtIndex:index] objectForKey:OMMarkdownRendererDiagramSourceKey];
    if (source == nil) {
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pasteboard setString:source forType:NSStringPboardType];

    if ([sender isKindOfClass:[NSButton class]]) {
        [self showCopyFeedbackForButton:(NSButton *)sender];
    }
}

- (void)applyCopyButtonDefaultAppearance:(NSButton *)button
{
    if (button == nil) {
        return;
    }

    NSImage *copyImage = OMDSymbolicImageNamedForCommand(@"omd-edit-copy-symbolic", @"Copy Code");
    if (copyImage != nil) {
        [button setImage:copyImage];
        [button setImagePosition:NSImageOnly];
        [button setTitle:@""];
        return;
    }

    NSFont *buttonFont = OMDChromeSmallFont();
    NSDictionary *buttonAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      buttonFont, NSFontAttributeName,
                                      [NSColor secondaryLabelColor], NSForegroundColorAttributeName,
                                      nil];
    NSAttributedString *buttonTitle = [[[NSAttributedString alloc] initWithString:@"copy"
                                                                        attributes:buttonAttributes] autorelease];
    [button setAttributedTitle:buttonTitle];
    [button setImage:nil];
    [button setImagePosition:NSNoImage];
}

- (void)showCopyFeedbackForButton:(NSButton *)button
{
    NSTextView *textView = [_delegate previewTextView];
    [self hideCopyFeedback];
    if (button == nil) {
        return;
    }

    _copyFeedbackButton = [button retain];

    NSImage *checkImage = OMDSymbolicImageNamedForCommand(@"omd-object-select-symbolic", @"Copied");
    if (checkImage != nil) {
        [_copyFeedbackButton setImage:checkImage];
        [_copyFeedbackButton setImagePosition:NSImageOnly];
        [_copyFeedbackButton setTitle:@""];
    }

    // A label in the theme's tooltip colours beside the button.
    NSTextField *hud = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [hud setStringValue:@"Copied!"];
    [hud setFont:[NSFont toolTipsFontOfSize:0.0]];
#if defined(GNUSTEP)
    [hud setTextColor:[NSColor toolTipTextColor]];
    [hud setBackgroundColor:[NSColor toolTipColor]];
#else
    // AppKit on macOS has no public tooltip colours.
    [hud setTextColor:[NSColor labelColor]];
    [hud setBackgroundColor:[NSColor windowBackgroundColor]];
#endif
    [hud setDrawsBackground:YES];
    [hud setBezeled:NO];
    [hud setBordered:NO];
    [hud setEditable:NO];
    [hud setSelectable:NO];
    [hud setAlignment:NSCenterTextAlignment];
    [hud sizeToFit];
    CGFloat bubbleWidth = ceil(NSWidth([hud frame]) + 12.0);
    CGFloat bubbleHeight = ceil(NSHeight([hud frame]) + 4.0);
    NSRect buttonFrame = [_copyFeedbackButton frame];
    CGFloat x = NSMinX(buttonFrame) - bubbleWidth - 8.0;
    if (x < 4.0) {
        x = NSMaxX(buttonFrame) + 8.0;
    }
    CGFloat y = 0.0;
    if ([textView isFlipped]) {
        y = NSMinY(buttonFrame);
        if (y + bubbleHeight > NSHeight([textView bounds]) - 4.0) {
            y = NSHeight([textView bounds]) - bubbleHeight - 4.0;
        }
    } else {
        y = NSMaxY(buttonFrame) - bubbleHeight;
        if (y < 4.0) {
            y = 4.0;
        }
    }
    if (x + bubbleWidth > NSWidth([textView bounds]) - 4.0) {
        x = NSWidth([textView bounds]) - bubbleWidth - 4.0;
    }

    NSRect hudFrame = NSIntegralRect(NSMakeRect(x, y, bubbleWidth, bubbleHeight));
    [hud setFrame:hudFrame];
    [textView addSubview:hud];
    _copyFeedbackHUDView = hud;

    _copyFeedbackTimer = [[NSTimer scheduledTimerWithTimeInterval:OMDCopyFeedbackDisplayInterval
                                                           target:self
                                                         selector:@selector(copyFeedbackTimerFired:)
                                                         userInfo:nil
                                                          repeats:NO] retain];
}

- (void)copyFeedbackTimerFired:(NSTimer *)timer
{
    if (timer != _copyFeedbackTimer) {
        return;
    }
    [self hideCopyFeedback];
}

- (void)hideCopyFeedback
{
    if (_copyFeedbackTimer != nil) {
        [_copyFeedbackTimer invalidate];
        [_copyFeedbackTimer release];
        _copyFeedbackTimer = nil;
    }
    if (_copyFeedbackHUDView != nil) {
        [_copyFeedbackHUDView removeFromSuperview];
        [_copyFeedbackHUDView release];
        _copyFeedbackHUDView = nil;
    }
    if (_copyFeedbackButton != nil) {
        [self applyCopyButtonDefaultAppearance:_copyFeedbackButton];
        [_copyFeedbackButton release];
        _copyFeedbackButton = nil;
    }
}

- (void)copyCodeBlock:(id)sender
{
    NSTextView *textView = [_delegate previewTextView];
    OMDRenderResult *renderResult = [_delegate previewRenderResult];
    NSInteger index = [sender tag];
    NSArray *ranges = [renderResult codeBlockRanges];
    if (index < 0 || index >= (NSInteger)[ranges count]) {
        return;
    }
    NSRange range = [[ranges objectAtIndex:index] rangeValue];
    NSString *fullText = [[textView textStorage] string];
    if (fullText == nil || NSMaxRange(range) > [fullText length]) {
        return;
    }

    NSString *snippet = [fullText substringWithRange:range];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pasteboard setString:snippet forType:NSStringPboardType];

    if ([sender isKindOfClass:[NSButton class]]) {
        [self showCopyFeedbackForButton:(NSButton *)sender];
    }
}

@end
