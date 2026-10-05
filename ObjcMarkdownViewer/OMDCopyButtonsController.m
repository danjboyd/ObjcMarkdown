// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDCopyButtonsController.h"
#import "OMDCodeCopyButton.h"
#import "OMDCopyFeedbackBadgeView.h"
#import "OMDTextView.h"
#import "OMDViewerColors.h"
#import "OMDViewerImages.h"
#import "OMMarkdownRenderer.h"
#import "OMRenderedObject.h"

#include <math.h>

static const NSTimeInterval OMDCopyFeedbackDisplayInterval = 0.95;

@interface OMDCopyButtonsController ()
- (NSArray *)displayMathObjectRanges;
- (void)addCopyButtonsForRanges:(NSArray *)ranges
                        action:(SEL)action
                       toolTip:(NSString *)toolTip
                 layoutManager:(NSLayoutManager *)layoutManager
                     container:(NSTextContainer *)container
                    textOrigin:(NSPoint)textOrigin
                  blockPadding:(NSSize)blockPadding
            matchCodeBlockEdge:(BOOL)matchCodeBlockEdge;
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
    }
    return self;
}

- (void)dealloc
{
    [self hideCopyFeedback];
    [_codeBlockButtons release];
    [super dealloc];
}

- (void)removeCopyButtons
{
    for (NSButton *button in _codeBlockButtons) {
        [button removeFromSuperview];
    }
    [_codeBlockButtons removeAllObjects];
}

- (void)updateCodeBlockButtons
{
    NSTextView *textView = [_delegate previewTextView];
    OMMarkdownRenderer *renderer = [_delegate previewRenderer];
    [self hideCopyFeedback];

    if (_codeBlockButtons == nil) {
        _codeBlockButtons = [[NSMutableArray alloc] init];
    }
    for (NSButton *button in _codeBlockButtons) {
        [button removeFromSuperview];
    }
    [_codeBlockButtons removeAllObjects];

    NSArray *codeRanges = [renderer codeBlockRanges];
    NSArray *diagramBlocks = [renderer diagramBlocks];
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

    NSPoint textOrigin = [textView textContainerOrigin];
    NSSize blockPadding = NSMakeSize(12.0, 8.0);
    if ([textView isKindOfClass:[OMDTextView class]]) {
        OMDTextView *codeView = (OMDTextView *)textView;
        if (codeView.codeBlockPadding.width > 0.0 && codeView.codeBlockPadding.height > 0.0) {
            blockPadding = codeView.codeBlockPadding;
        }
    }

    [self addCopyButtonsForRanges:codeRanges
                           action:@selector(copyCodeBlock:)
                          toolTip:@"Copy code block"
                    layoutManager:layoutManager
                        container:container
                       textOrigin:textOrigin
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
    [self addCopyButtonsForRanges:diagramRanges
                           action:@selector(copyDiagramBlock:)
                          toolTip:@"Copy diagram source"
                    layoutManager:layoutManager
                        container:container
                       textOrigin:textOrigin
                     blockPadding:blockPadding
               matchCodeBlockEdge:YES];

    // Equations are narrow and centred: put the button just right of the
    // formula instead of over its corner (button 20 + 6 inset + 6 gap).
    [self addCopyButtonsForRanges:displayMathRanges
                           action:@selector(copyDisplayMathBlock:)
                          toolTip:@"Copy equation source"
                    layoutManager:layoutManager
                        container:container
                       textOrigin:textOrigin
                     blockPadding:NSMakeSize(32.0, 0.0)
               matchCodeBlockEdge:NO];
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

- (void)addCopyButtonsForRanges:(NSArray *)ranges
                         action:(SEL)action
                        toolTip:(NSString *)toolTip
                  layoutManager:(NSLayoutManager *)layoutManager
                      container:(NSTextContainer *)container
                     textOrigin:(NSPoint)textOrigin
                   blockPadding:(NSSize)blockPadding
             matchCodeBlockEdge:(BOOL)matchCodeBlockEdge
{
    NSTextView *textView = [_delegate previewTextView];
    OMMarkdownRenderer *renderer = [_delegate previewRenderer];
    if ([ranges count] == 0) {
        return;
    }

    NSInteger index = 0;
    for (NSValue *value in ranges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            index++;
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        if (glyphRange.length == 0) {
            index++;
            continue;
        }

        NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];
        if (matchCodeBlockEdge) {
            // A code block's text runs to the line end less its tail inset.
            NSRect fragment = [layoutManager lineFragmentRectForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
            CGFloat codeTailInset = 20.0 * ([renderer zoomScale] > 0.0 ? [renderer zoomScale] : 1.0);
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
            index++;
            continue;
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

        NSRect buttonFrame = NSIntegralRect(NSMakeRect(x, y, buttonWidth, buttonHeight));
        OMDCodeCopyButton *button = [[OMDCodeCopyButton alloc] initWithFrame:buttonFrame];
        [self applyCopyButtonDefaultAppearance:button];
        [button setButtonType:NSMomentaryChangeButton];
        [button setBordered:NO];
        [button setToolTip:toolTip];
        id buttonCell = [button cell];
        if (buttonCell != nil && [buttonCell respondsToSelector:@selector(setImageScaling:)]) {
            [buttonCell setImageScaling:NSImageScaleNone];
        }
        if (buttonCell != nil && [buttonCell respondsToSelector:@selector(setHighlightsBy:)]) {
            [buttonCell setHighlightsBy:NSNoCellMask];
        }
        [button setTarget:self];
        [button setAction:action];
        [button setTag:index];
        [textView addSubview:button];
        [_codeBlockButtons addObject:button];
        [button release];
        index++;
    }
}

- (void)copyDiagramBlock:(id)sender
{
    OMMarkdownRenderer *renderer = [_delegate previewRenderer];
    NSInteger index = [sender tag];
    NSArray *blocks = [renderer diagramBlocks];
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

    NSImage *copyImage = OMDCodeBlockCopyImage();
    if (copyImage != nil) {
        [button setImage:copyImage];
        [button setImagePosition:NSImageOnly];
        [button setTitle:@""];
        return;
    }

    NSFont *buttonFont = [NSFont systemFontOfSize:10.0];
    if (buttonFont == nil) {
        buttonFont = [NSFont systemFontOfSize:9.0];
    }
    NSDictionary *buttonAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      buttonFont, NSFontAttributeName,
                                      [NSColor colorWithCalibratedWhite:0.56 alpha:1.0], NSForegroundColorAttributeName,
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

    NSImage *checkImage = OMDCodeBlockCopiedCheckImage();
    if (checkImage != nil) {
        [_copyFeedbackButton setImage:checkImage];
        [_copyFeedbackButton setImagePosition:NSImageOnly];
        [_copyFeedbackButton setTitle:@""];
    }

    NSString *feedbackText = @"Copied!";
    NSFont *font = [NSFont boldSystemFontOfSize:11.0];
    if (font == nil) {
        font = [NSFont systemFontOfSize:11.0];
    }
    NSSize bubbleSize = [OMDCopyFeedbackBadgeView sizeForText:feedbackText font:font];
    CGFloat bubbleWidth = bubbleSize.width;
    CGFloat bubbleHeight = bubbleSize.height;
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
    OMDCopyFeedbackBadgeView *hud = [[OMDCopyFeedbackBadgeView alloc] initWithFrame:hudFrame
                                                                                text:feedbackText
                                                                                font:font];
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
    OMMarkdownRenderer *renderer = [_delegate previewRenderer];
    NSInteger index = [sender tag];
    NSArray *ranges = [renderer codeBlockRanges];
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
