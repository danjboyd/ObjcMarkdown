// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>

#import "OMDSourceHighlighter.h"
#import "OMDSourceTextView.h"
#import "OMDLineNumberRulerView.h"

// Not a check: with OMD_INVALIDATION_TRACE set, types into a real source
// view in a window that is never shown, and prints who asks for redraws
// and layout, ranked (#164).

static NSMutableDictionary *OMDTraceCounts = nil;
static NSString *OMDTracePhase = @"setup";

static NSString *OMDTraceCaller(void)
{
    NSArray *stack = [NSThread callStackSymbols];
    NSMutableArray *frames = [NSMutableArray array];
    NSUInteger i = 2;
    for (; i < [stack count] && [frames count] < 7; i++) {
        NSString *frame = [stack objectAtIndex:i];
        NSRange plus = [frame rangeOfString:@" + "];
        NSArray *words = [(plus.location != NSNotFound ? [frame substringToIndex:plus.location] : frame) componentsSeparatedByString:@" "];
        [frames addObject:[words lastObject]];
    }
    return [frames componentsJoinedByString:@" < "];
}

static void OMDTraceNote(NSString *what, NSRect rect, NSRect bounds)
{
    if (OMDTraceCounts == nil) {
        return;
    }
    BOOL full = bounds.size.height > 0 && rect.size.height >= bounds.size.height * 0.9;
    NSString *key = [NSString stringWithFormat:@"%@ %@ [%@] %@", OMDTracePhase, what, full ? @"FULL" : @"part", OMDTraceCaller()];
    NSNumber *count = [OMDTraceCounts objectForKey:key];
    [OMDTraceCounts setObject:[NSNumber numberWithUnsignedInteger:[count unsignedIntegerValue] + 1] forKey:key];
}

@interface OMDTraceTextView : OMDSourceTextView
@end
@implementation OMDTraceTextView
- (void)setNeedsDisplay:(BOOL)flag
{
    if (flag) {
        OMDTraceNote(@"textView.setNeedsDisplay", [self bounds], [self bounds]);
    }
    [super setNeedsDisplay:flag];
}
- (void)setNeedsDisplayInRect:(NSRect)rect
{
    OMDTraceNote(@"textView", rect, [self bounds]);
    [super setNeedsDisplayInRect:rect];
}
- (void)setNeedsDisplayInRect:(NSRect)rect avoidAdditionalLayout:(BOOL)avoid
{
    OMDTraceNote(@"textView.avoidLayout", rect, [self bounds]);
    [super setNeedsDisplayInRect:rect avoidAdditionalLayout:avoid];
}
@end

@interface OMDTraceClipView : NSClipView
@end
@implementation OMDTraceClipView
- (void)setNeedsDisplayInRect:(NSRect)rect
{
    OMDTraceNote(@"clipView", rect, [self bounds]);
    [super setNeedsDisplayInRect:rect];
}
@end

@interface OMDTraceContentView : NSView
@end
@implementation OMDTraceContentView
- (void)setNeedsDisplayInRect:(NSRect)rect
{
    OMDTraceNote(@"contentView", rect, [self bounds]);
    [super setNeedsDisplayInRect:rect];
}
@end

@interface OMDTraceScrollView : NSScrollView
@end
@implementation OMDTraceScrollView
- (void)setNeedsDisplayInRect:(NSRect)rect
{
    OMDTraceNote(@"scrollView", rect, [self bounds]);
    [super setNeedsDisplayInRect:rect];
}
- (void)tile
{
    OMDTraceNote(@"scrollView.tile", NSZeroRect, NSZeroRect);
    [super tile];
}
@end

@interface OMDTraceRuler : OMDLineNumberRulerView
@end
@implementation OMDTraceRuler
- (void)setNeedsDisplayInRect:(NSRect)rect
{
    OMDTraceNote(@"ruler", rect, [self bounds]);
    [super setNeedsDisplayInRect:rect];
}
@end

@interface OMDTraceLayoutManager : NSLayoutManager
@end
@implementation OMDTraceLayoutManager
- (void)invalidateDisplayForCharacterRange:(NSRange)range
{
    OMDTraceNote(@"layoutManager.invalidateDisplayChars", NSZeroRect, NSZeroRect);
    [super invalidateDisplayForCharacterRange:range];
}
- (void)invalidateDisplayForGlyphRange:(NSRange)range
{
    OMDTraceNote(@"layoutManager.invalidateDisplayGlyphs", NSZeroRect, NSZeroRect);
    [super invalidateDisplayForGlyphRange:range];
}
- (void)invalidateLayoutForCharacterRange:(NSRange)range actualCharacterRange:(NSRangePointer)actual
{
    OMDTraceNote(@"layoutManager.invalidateLayout", NSZeroRect, NSZeroRect);
    [super invalidateLayoutForCharacterRange:range actualCharacterRange:actual];
}
@end

@interface OMDSourceInvalidationTraceTests : XCTestCase
@end

@implementation OMDSourceInvalidationTraceTests

- (void)testPrintWhoInvalidates
{
    if (getenv("OMD_INVALIDATION_TRACE") == NULL) {
        return;
    }
    [NSApplication sharedApplication];
    // The theme the defaults chose is active already. Don't load another
    // instance of it: GSTheme records "old" methods when an instance is
    // made, so it would record the active theme's overrides as the
    // originals, and -tile would call itself until the stack ran out.
    fprintf(stderr, "OMDTrace theme %s\n", [[[GSTheme theme] name] UTF8String]);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480)
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setContentView:[[[OMDTraceContentView alloc] initWithFrame:[[window contentView] frame]] autorelease]];
    NSScrollView *scroll = [[[OMDTraceScrollView alloc] initWithFrame:[[window contentView] bounds]] autorelease];
    [scroll setContentView:[[[OMDTraceClipView alloc] initWithFrame:[[scroll contentView] frame]] autorelease]];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasVerticalRuler:YES];
    [scroll setRulersVisible:YES];
    OMDTraceTextView *view = [[[OMDTraceTextView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
    [view setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [view setEditable:YES];
    [view setRichText:NO];
    OMDTraceLayoutManager *manager = [[[OMDTraceLayoutManager alloc] init] autorelease];
    [[view textContainer] replaceLayoutManager:manager];
    [scroll setDocumentView:view];
    OMDTraceRuler *ruler = [[[OMDTraceRuler alloc] initWithScrollView:scroll textView:view] autorelease];
    [scroll setVerticalRulerView:ruler];
    [[window contentView] addSubview:scroll];
    [window makeFirstResponder:view];
    [window displayIfNeeded];

    NSColor *base = [NSColor textColor];
    NSColor *background = [NSColor textBackgroundColor];
    NSString *typed = @"some text\n";
    NSUInteger keys = 50;
    OMDTraceCounts = [NSMutableDictionary dictionary];
    NSUInteger k = 0;
    for (; k < keys; k++) {
        unichar c = [typed characterAtIndex:k % [typed length]];
        OMDTracePhase = @"key";
        [view insertText:[NSString stringWithCharacters:&c length:1]];
        // What -updateWindowTitle does on every change.
        OMDTracePhase = @"title";
        [window setRepresentedFilename:@""];
        [window setTitle:@"Untitled"];
        [window setDocumentEdited:YES];
        OMDTracePhase = @"keyDisplay";
        [window displayIfNeeded];
        // What the 80 ms debounce does between keys.
        OMDTracePhase = @"highlight";
        [OMDSourceHighlighter highlightTextStorage:[view textStorage] baseTextColor:base backgroundColor:background];
        NSMutableDictionary *typing = [[[view typingAttributes] mutableCopy] autorelease];
        [typing setObject:base forKey:NSForegroundColorAttributeName];
        OMDTracePhase = @"typingAttributes";
        [view setTypingAttributes:typing];
        OMDTracePhase = @"highlightDisplay";
        [window displayIfNeeded];
    }
    NSArray *keysSorted = [OMDTraceCounts keysSortedByValueUsingSelector:@selector(compare:)];
    NSEnumerator *e = [keysSorted reverseObjectEnumerator];
    NSString *key = nil;
    NSUInteger shown = 0;
    while ((key = [e nextObject]) != nil && shown++ < 40) {
        fprintf(stderr, "OMDTrace %5lu %s\n", (unsigned long)[[OMDTraceCounts objectForKey:key] unsignedIntegerValue], [key UTF8String]);
    }
    OMDTraceCounts = nil;
    [window close];
}

@end
