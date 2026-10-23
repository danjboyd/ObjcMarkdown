// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDTextView.h"
#import "OMStrikethroughLayoutManager.h"
#import "OMMarkdownRenderer.h"
#import "OMRenderedObject.h"
#import "OMTextTable.h"

// The tool tip owner callback OMDTextView implements for its object rects.
@interface OMDTextView (ToolTipOwner)
- (NSString *)view:(NSView *)view
  stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point
          userData:(void *)userData;
@end

// Records the task box a click asked to toggle.
@interface OMDTaskToggleRecorder : NSObject <OMDTextViewRenderedObjectDelegate>
{
    NSUInteger _toggledIndex;
}
- (NSUInteger)toggledIndex;
@end

@implementation OMDTaskToggleRecorder

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _toggledIndex = NSNotFound;
    }
    return self;
}

- (NSUInteger)toggledIndex
{
    return _toggledIndex;
}

- (BOOL)textView:(OMDTextView *)textView toggleTaskItemAtIndex:(NSUInteger)itemIndex
{
    (void)textView;
    _toggledIndex = itemIndex;
    return YES;
}

@end

// Records the preview range Reveal in Source asked for (#293).
@interface OMDRevealRecorder : NSObject <OMDTextViewRenderedObjectDelegate>
{
    NSRange _revealedRange;
}
- (NSRange)revealedRange;
@end

@implementation OMDRevealRecorder

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _revealedRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}

- (NSRange)revealedRange
{
    return _revealedRange;
}

- (void)textView:(OMDTextView *)textView revealSourceOfPreviewRange:(NSRange)range
{
    (void)textView;
    _revealedRange = range;
}

@end

@interface OMDTextViewTests : XCTestCase
@end

@implementation OMDTextViewTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (OMDTextView *)textViewShowingMarkdown:(NSString *)markdown
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:600.0];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    OMDTextView *textView = [[[OMDTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 800.0)] autorelease];
    [textView setEditable:NO];
    [textView setSelectable:YES];
    [textView setRichText:YES];
    [[textView textStorage] setAttributedString:rendered];
    [[textView layoutManager] glyphRangeForTextContainer:[textView textContainer]];
    return textView;
}

- (NSUInteger)firstObjectIndexInTextView:(OMDTextView *)textView
{
    NSTextStorage *storage = [textView textStorage];
    NSUInteger index = 0;
    for (; index < [storage length]; index++) {
        if ([storage attribute:OMRenderedObjectAttributeName atIndex:index effectiveRange:NULL] != nil) {
            return index;
        }
    }
    return NSNotFound;
}

- (NSString *)tableMarkdown
{
    return @"| a | b |\n|---|---|\n| 1 | 2 |";
}

// A drawn diagram: the rendered object the tests below work with.
- (NSString *)objectSource
{
    return @"erDiagram\n    A ||--o{ B : has\n";
}

- (NSString *)objectMarkdown
{
    return [NSString stringWithFormat:@"```mermaid\n%@```", [self objectSource]];
}

- (void)testCopyingMixedSelectionWritesObjectsAsMarkdown
{
    NSString *markdown = [NSString stringWithFormat:@"Before\n\n%@\n\n%@\n\nAfter", [self objectMarkdown], [self tableMarkdown]];
    OMDTextView *textView = [self textViewShowingMarkdown:markdown];
    [textView setSelectedRange:NSMakeRange(0, [[textView textStorage] length])];

    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    NSArray *types = [NSArray arrayWithObjects:NSStringPboardType, NSRTFPboardType, nil];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard types:types]);
    NSString *text = [pboard stringForType:NSStringPboardType];
    XCTAssertTrue([text rangeOfString:[self tableMarkdown]].location != NSNotFound);
    XCTAssertTrue([text rangeOfString:[self objectMarkdown]].location != NSNotFound);
    NSString *tableThenAfter = [[self tableMarkdown] stringByAppendingString:@"\n\nAfter"];
    XCTAssertTrue([text rangeOfString:tableThenAfter].location != NSNotFound, @"the table keeps its line break: %@", text);
    XCTAssertTrue([text hasPrefix:@"Before"]);
    XCTAssertTrue([text hasSuffix:@"After"]);
    unichar attachmentCharacter = NSAttachmentCharacter;
    XCTAssertTrue([text rangeOfString:[NSString stringWithCharacters:&attachmentCharacter length:1]].location == NSNotFound);

    NSData *rtf = [pboard dataForType:NSRTFPboardType];
    XCTAssertNotNil(rtf);
    NSAttributedString *fromRTF = [[[NSAttributedString alloc] initWithRTF:rtf documentAttributes:NULL] autorelease];
    XCTAssertTrue([[fromRTF string] rangeOfString:@"|---|---|"].location != NSNotFound);
    [pboard releaseGlobally];
}

- (void)testCopyingOneObjectWritesItsSourceAndAnImage
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self objectMarkdown]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    if (index == NSNotFound) {
        return;
    }
    [textView setSelectedRange:NSMakeRange(index, 1)];

    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard
                                                 types:[NSArray arrayWithObject:NSStringPboardType]]);
    XCTAssertEqualObjects([pboard stringForType:NSStringPboardType], [self objectSource]);
    NSData *tiff = [pboard dataForType:NSTIFFPboardType];
    XCTAssertNotNil(tiff);
    NSImage *image = [[[NSImage alloc] initWithData:tiff] autorelease];
    XCTAssertTrue([image size].width > 0.0 && [image size].height > 0.0);
    [pboard releaseGlobally];
}

- (void)testPlainTextSelectionCopiesNormally
{
    OMDTextView *textView = [self textViewShowingMarkdown:@"Just *some* text."];
    [textView setSelectedRange:NSMakeRange(0, 4)];
    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard
                                                 types:[NSArray arrayWithObject:NSStringPboardType]]);
    XCTAssertEqualObjects([pboard stringForType:NSStringPboardType], @"Just");
    XCTAssertNil([pboard dataForType:NSTIFFPboardType]);
    [pboard releaseGlobally];
}

- (void)testEscapeClearsSelectionInReadOnlyPreview
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self objectMarkdown]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    [textView setSelectedRange:NSMakeRange(index, 1)];
    NSEvent *escape = [NSEvent keyEventWithType:NSKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0.0
                                   windowNumber:0
                                        context:nil
                                     characters:@"\x1b"
                    charactersIgnoringModifiers:@"\x1b"
                                      isARepeat:NO
                                        keyCode:9];
    [textView keyDown:escape];
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)0);
    XCTAssertEqual([textView selectedRange].location, index);
}

- (void)testToolTipShowsObjectSource
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self objectMarkdown]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    XCTAssertFalse(NSIsEmptyRect([textView viewRectForRenderedObjectAtIndex:index]));
    [textView updateRenderedObjectToolTips];
    NSString *tip = [textView view:textView
                      stringForToolTip:0
                                 point:NSZeroPoint
                              userData:(void *)(uintptr_t)index];
    XCTAssertEqualObjects(tip, @"erDiagram\n    A ||--o{ B : has");
}

- (void)testSourceLocationFindsItsObject
{
    NSString *markdown = [NSString stringWithFormat:@"Intro\n\n%@\n\nOutro", [self objectMarkdown]];
    OMDTextView *textView = [self textViewShowingMarkdown:markdown];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    NSUInteger insideDiagram = [markdown rangeOfString:@"A ||"].location;
    XCTAssertEqual([textView renderedObjectIndexContainingSourceLocation:insideDiagram], index);
    XCTAssertEqual([textView renderedObjectIndexContainingSourceLocation:2], (NSUInteger)NSNotFound);
    XCTAssertEqual([textView renderedObjectIndexContainingSourceLocation:[markdown length] - 2], (NSUInteger)NSNotFound);
}

- (void)testLinkedObjectIndexDefaultsToNotFound
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self objectMarkdown]];
    XCTAssertEqual([textView linkedObjectIndex], (NSUInteger)NSNotFound);
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    [textView setLinkedObjectIndex:index];
    XCTAssertEqual([textView linkedObjectIndex], index);
    [textView setLinkedObjectIndex:NSNotFound];
    XCTAssertEqual([textView linkedObjectIndex], (NSUInteger)NSNotFound);
}

// A text view showing text, with strikethrough over the given ranges.
- (OMDTextView *)textViewWithText:(NSString *)text struckRanges:(NSArray *)ranges width:(CGFloat)width
{
    OMDTextView *textView = [[[OMDTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 400.0)] autorelease];
    NSFont *font = [NSFont userFontOfSize:14.0];
    NSMutableAttributedString *string = [[[NSMutableAttributedString alloc]
        initWithString:text attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]] autorelease];
    for (NSValue *range in ranges) {
        [string addAttribute:NSStrikethroughStyleAttributeName
                       value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
                       range:[range rangeValue]];
    }
    [[textView textStorage] setAttributedString:string];
    [[textView layoutManager] glyphRangeForTextContainer:[textView textContainer]];
    return textView;
}

- (void)testStrikethroughLineCrossesStruckWordOnly
{
    NSString *text = @"plain struck plain";
    NSRange struck = [text rangeOfString:@"struck"];
    OMDTextView *textView = [self textViewWithText:text struckRanges:[NSArray arrayWithObject:[NSValue valueWithRange:struck]] width:600.0];
    OMStrikethroughLayoutManager *layoutManager = (OMStrikethroughLayoutManager *)[textView layoutManager];
    XCTAssertTrue([layoutManager isKindOfClass:[OMStrikethroughLayoutManager class]]);

    NSRange allGlyphs = NSMakeRange(0, [layoutManager numberOfGlyphs]);
    NSArray *rects = [layoutManager strikethroughLineRectsForGlyphRange:allGlyphs atPoint:NSZeroPoint];
    XCTAssertEqual([rects count], (NSUInteger)1);
    if ([rects count] != 1) {
        return;
    }
    NSRect line = [[rects objectAtIndex:0] rectValue];
    NSRange struckGlyphs = [layoutManager glyphRangeForCharacterRange:struck actualCharacterRange:NULL];
    NSRect word = [layoutManager boundingRectForGlyphRange:struckGlyphs inTextContainer:[textView textContainer]];
    XCTAssertEqualWithAccuracy(NSMinX(line), NSMinX(word), 0.5);
    XCTAssertEqualWithAccuracy(NSWidth(line), NSWidth(word), 0.5);
    CGFloat baseline = NSMinY([layoutManager lineFragmentRectForGlyphAtIndex:struckGlyphs.location effectiveRange:NULL]) +
                       [layoutManager locationForGlyphAtIndex:struckGlyphs.location].y;
    XCTAssertTrue(NSMaxY(line) < baseline, @"line should sit above the baseline");
    XCTAssertTrue(NSMinY(line) > baseline - [[NSFont userFontOfSize:14.0] xHeight] - 1.0, @"line should sit within the x-height");
    XCTAssertTrue(NSHeight(line) >= 1.0);
}

- (void)testStrikethroughGetsOneLinePerWrappedLine
{
    NSString *text = @"alpha beta gamma delta epsilon zeta eta theta iota kappa";
    OMDTextView *textView = [self textViewWithText:text
                                      struckRanges:[NSArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(0, [text length])]]
                                             width:120.0];
    OMStrikethroughLayoutManager *layoutManager = (OMStrikethroughLayoutManager *)[textView layoutManager];
    NSRange allGlyphs = NSMakeRange(0, [layoutManager numberOfGlyphs]);
    NSUInteger lineCount = 0;
    NSUInteger glyph = 0;
    while (glyph < NSMaxRange(allGlyphs)) {
        NSRange fragment;
        [layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&fragment];
        lineCount += 1;
        glyph = NSMaxRange(fragment);
    }
    XCTAssertTrue(lineCount > 1);
    NSArray *rects = [layoutManager strikethroughLineRectsForGlyphRange:allGlyphs atPoint:NSZeroPoint];
    XCTAssertEqual([rects count], lineCount);
}

- (void)testUnstruckTextHasNoStrikethroughLines
{
    OMDTextView *textView = [self textViewWithText:@"nothing struck here\n" struckRanges:[NSArray array] width:600.0];
    OMStrikethroughLayoutManager *layoutManager = (OMStrikethroughLayoutManager *)[textView layoutManager];
    NSArray *rects = [layoutManager strikethroughLineRectsForGlyphRange:NSMakeRange(0, [layoutManager numberOfGlyphs])
                                                                atPoint:NSZeroPoint];
    XCTAssertEqual([rects count], (NSUInteger)0);
}

// The helper draws only on GNUstep; AppKit on macOS draws strikethrough itself.
#if defined(GNUSTEP)
- (void)testStrikethroughHelperDrawsAtMidXHeightInUnflippedContext
{
    NSFont *font = [NSFont userFontOfSize:20.0];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName,
                                [NSNumber numberWithInteger:NSUnderlineStyleSingle], NSStrikethroughStyleAttributeName,
                                [NSColor blackColor], NSForegroundColorAttributeName, nil];
    NSAttributedString *string = [[[NSAttributedString alloc] initWithString:@"struck" attributes:attributes] autorelease];
    NSSize size = NSMakeSize(200.0, 60.0);
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    // Only the line, no glyphs, so every dark pixel belongs to it.
    OMDrawStrikethroughForAttributedString(string, NSMakeRect(0.0, 0.0, size.width, size.height), NO);
    [image unlockFocus];

    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    XCTAssertNotNil(bitmap);
    NSInteger top = NSIntegerMax;
    NSInteger bottom = -1;
    NSInteger x = 0;
    for (; x < [bitmap pixelsWide]; x++) {
        NSInteger y = 0;
        for (; y < [bitmap pixelsHigh]; y++) {
            NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if ([color redComponent] < 0.5) {
                top = MIN(top, y);
                bottom = MAX(bottom, y);
            }
        }
    }
    XCTAssertTrue(bottom >= 0, @"the strikethrough line should be drawn");
    // Bitmap rows count from the top; the text sits at the top of an unflipped rect.
    CGFloat ascent = [font ascender];
    CGFloat expectedMiddle = ascent - [font xHeight] * 0.5;
    XCTAssertTrue(bottom - top <= 3, @"a thin line, not a block");
    XCTAssertEqualWithAccuracy((top + bottom) * 0.5, expectedMiddle, 4.0);
}
#endif

- (void)testLinkTitleIsOfferedAsToolTip
{
    OMDTextView *textView = [self textViewShowingMarkdown:@"See [docs](https://example.com \"The docs\") now."];
    NSUInteger link = [[[textView textStorage] string] rangeOfString:@"docs"].location;
    [textView updateRenderedObjectToolTips];
    NSString *tip = [textView view:textView stringForToolTip:0 point:NSZeroPoint userData:(void *)(uintptr_t)link];
    XCTAssertEqualObjects(tip, @"The docs");
}

- (void)testHitTestingFindsObjectOnlyInsideItsBox
{
    OMDTextView *textView = [self textViewShowingMarkdown:[NSString stringWithFormat:@"Intro\n\n%@", [self objectMarkdown]]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    if (index == NSNotFound) {
        return;
    }
    NSLayoutManager *layoutManager = [textView layoutManager];
    NSRange glyphs = [layoutManager glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL];
    NSRect box = [layoutManager boundingRectForGlyphRange:glyphs inTextContainer:[textView textContainer]];
    NSPoint origin = [textView textContainerOrigin];
    NSPoint inside = NSMakePoint(NSMidX(box) + origin.x, NSMidY(box) + origin.y);

    NSUInteger hitIndex = NSNotFound;
    OMRenderedObject *object = [textView renderedObjectAtPoint:inside characterIndex:&hitIndex];
    XCTAssertNotNil(object);
    XCTAssertEqual(hitIndex, index);
    XCTAssertEqual([object kind], OMRenderedObjectKindDiagram);

    NSPoint outside = NSMakePoint(NSMaxX(box) + origin.x + 40.0, NSMidY(box) + origin.y);
    XCTAssertNil([textView renderedObjectAtPoint:outside characterIndex:NULL]);
    NSPoint onIntro = NSMakePoint(origin.x + 4.0, origin.y + 4.0);
    XCTAssertNil([textView renderedObjectAtPoint:onIntro characterIndex:NULL]);
}

- (NSString *)taskMarkdown
{
    return @"- [ ] first\n- plain\n- [x] second\n\n```\n- [ ] in code\n```\n";
}

// The character index of the n-th task box, or NSNotFound.
- (NSUInteger)indexOfTaskBox:(NSUInteger)n inTextView:(OMDTextView *)textView
{
    NSTextStorage *storage = [textView textStorage];
    NSUInteger index = 0;
    NSUInteger seen = 0;
    for (; index < [storage length]; index++) {
        if ([storage attribute:OMMarkdownRendererTaskItemAttributeName atIndex:index effectiveRange:NULL] != nil) {
            if (seen == n) {
                return index;
            }
            seen += 1;
        }
    }
    return NSNotFound;
}

// The centre of the glyph at a character index, in view coordinates.
- (NSPoint)centreOfCharacter:(NSUInteger)index inTextView:(OMDTextView *)textView
{
    NSLayoutManager *layoutManager = [textView layoutManager];
    NSRange glyphs = [layoutManager glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL];
    NSRect box = [layoutManager boundingRectForGlyphRange:glyphs inTextContainer:[textView textContainer]];
    NSPoint origin = [textView textContainerOrigin];
    return NSMakePoint(NSMidX(box) + origin.x, NSMidY(box) + origin.y);
}

// Boxes are numbered in order; a "[ ]" in code or an item's text is none.
- (void)testTaskItemIndexesCountTheBoxes
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self taskMarkdown]];
    NSTextStorage *storage = [textView textStorage];
    NSUInteger first = [self indexOfTaskBox:0 inTextView:textView];
    NSUInteger second = [self indexOfTaskBox:1 inTextView:textView];
    XCTAssertTrue(first != NSNotFound && second != NSNotFound);
    XCTAssertEqual([self indexOfTaskBox:2 inTextView:textView], (NSUInteger)NSNotFound);
    if (first == NSNotFound || second == NSNotFound) {
        return;
    }
    XCTAssertEqual(OMDTaskItemIndexAtCharacterIndex(storage, first), (NSUInteger)0);
    XCTAssertEqual(OMDTaskItemIndexAtCharacterIndex(storage, second), (NSUInteger)1);
    XCTAssertEqual(OMDTaskItemIndexAtCharacterIndex(storage, first + 2), (NSUInteger)NSNotFound);
    XCTAssertEqual(OMDTaskItemIndexAtCharacterIndex(storage, [storage length]), (NSUInteger)NSNotFound);
    XCTAssertEqual(OMDTaskItemIndexAtCharacterIndex(nil, 0), (NSUInteger)NSNotFound);

    // Hit testing: the box itself, not the item's text beside it.
    XCTAssertEqual([textView taskItemIndexAtPoint:[self centreOfCharacter:second inTextView:textView]], (NSUInteger)1);
    XCTAssertEqual([textView taskItemIndexAtPoint:[self centreOfCharacter:second + 3 inTextView:textView]],
                   (NSUInteger)NSNotFound);
}

// A click on a box goes to the delegate with the box's number, and the
// view's selection stays as it was.
- (void)testClickOnTaskBoxAsksDelegateAndKeepsSelection
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self taskMarkdown]];
    OMDTaskToggleRecorder *recorder = [[[OMDTaskToggleRecorder alloc] init] autorelease];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 800.0)
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [[window contentView] addSubview:textView];
    [textView setDelegate:(id)recorder];
    NSUInteger second = [self indexOfTaskBox:1 inTextView:textView];
    XCTAssertTrue(second != NSNotFound);
    if (second == NSNotFound) {
        [window release];
        return;
    }
    NSRange selection = NSMakeRange(second + 2, 3);
    [textView setSelectedRange:selection];

    NSPoint inWindow = [textView convertPoint:[self centreOfCharacter:second inTextView:textView] toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSLeftMouseDown
                                        location:inWindow
                                   modifierFlags:0
                                       timestamp:0.0
                                    windowNumber:[window windowNumber]
                                         context:nil
                                     eventNumber:0
                                      clickCount:1
                                        pressure:1.0];
    [textView mouseDown:click];
    XCTAssertEqual([recorder toggledIndex], (NSUInteger)1);
    XCTAssertTrue(NSEqualRanges([textView selectedRange], selection));

    [textView setDelegate:nil];
    [textView removeFromSuperview];
    [window release];
}

// The menu a right click at a character opens.
- (NSMenu *)textMenuAtCharacter:(NSUInteger)index inTextView:(OMDTextView *)textView window:(NSWindow *)window
{
    NSPoint inWindow = [textView convertPoint:[self centreOfCharacter:index inTextView:textView] toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSRightMouseDown
                                        location:inWindow
                                   modifierFlags:0
                                       timestamp:0.0
                                    windowNumber:[window windowNumber]
                                         context:nil
                                     eventNumber:0
                                      clickCount:1
                                        pressure:1.0];
    return [textView menuForEvent:click];
}

// A right click on text offers Reveal in Source, which asks the delegate for
// the selection when the click is in it, else for the clicked position.
- (void)testTextMenuRevealsTheClickedTextInSource
{
    OMDTextView *textView = [self textViewShowingMarkdown:@"First paragraph.\n\nSecond paragraph.\n"];
    OMDRevealRecorder *recorder = [[[OMDRevealRecorder alloc] init] autorelease];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 800.0)
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [[window contentView] addSubview:textView];
    [textView setDelegate:(id)recorder];
    NSString *text = [[textView textStorage] string];
    NSRange second = [text rangeOfString:@"Second"];
    NSRange first = [text rangeOfString:@"First"];

    [textView setSelectedRange:first];
    NSMenu *menu = [self textMenuAtCharacter:second.location + 2 inTextView:textView window:window];
    NSMenuItem *item = (NSMenuItem *)[menu itemWithTitle:@"Reveal in Source"];
    XCTAssertNotNil(item);
    XCTAssertTrue([item isEnabled]);
    [[item target] performSelector:[item action] withObject:item];
    // GNUstep reveals the clicked position; AppKit's menu first selects the
    // clicked word. Either way, the clicked paragraph's.
    NSRange paragraph = [text rangeOfString:@"Second paragraph."];
    NSRange revealed = [recorder revealedRange];
    XCTAssertTrue(revealed.location != NSNotFound && revealed.location >= paragraph.location &&
                  NSMaxRange(revealed) <= NSMaxRange(paragraph) &&
                  revealed.location <= second.location + 2 && second.location + 2 <= NSMaxRange(revealed),
                  @"%@", NSStringFromRange(revealed));

    [textView setSelectedRange:second];
    menu = [self textMenuAtCharacter:second.location + 2 inTextView:textView window:window];
    item = (NSMenuItem *)[menu itemWithTitle:@"Reveal in Source"];
    [[item target] performSelector:[item action] withObject:item];
    XCTAssertTrue(NSEqualRanges([recorder revealedRange], second));

    [textView setDelegate:nil];
    [textView removeFromSuperview];
    [window release];
}

// No delegate that can reveal, or an editable view: no Reveal in Source.
- (void)testTextMenuHasNoRevealWithoutADelegate
{
    OMDTextView *textView = [self textViewShowingMarkdown:@"Words.\n"];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 800.0)
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [[window contentView] addSubview:textView];
    NSMenu *menu = [self textMenuAtCharacter:1 inTextView:textView window:window];
    XCTAssertNil([menu itemWithTitle:@"Reveal in Source"]);

    OMDRevealRecorder *recorder = [[[OMDRevealRecorder alloc] init] autorelease];
    [textView setDelegate:(id)recorder];
    [textView setEditable:YES];
    menu = [self textMenuAtCharacter:1 inTextView:textView window:window];
    XCTAssertNil([menu itemWithTitle:@"Reveal in Source"]);

    [textView setDelegate:nil];
    [textView removeFromSuperview];
    [window release];
}

- (void)testPartOfATableCopiesAsTabSeparatedText
{
    OMDTextView *textView = [self textViewShowingMarkdown:@"| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"];
    NSString *text = [[textView textStorage] string];
    NSRange from = [text rangeOfString:@"1"];
    NSRange to = [text rangeOfString:@"4"];
    [textView setSelectedRange:NSMakeRange(from.location, NSMaxRange(to) - from.location)];
    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard
                                                 types:[NSArray arrayWithObject:NSStringPboardType]]);
    XCTAssertEqualObjects([pboard stringForType:NSStringPboardType], @"1\t2\n3\t4");
    [pboard releaseGlobally];
}

- (void)testWholeTableCopiesAsMarkdown
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self tableMarkdown]];
    NSTextStorage *storage = [textView textStorage];
    NSRange table;
    XCTAssertNotNil([storage attribute:OMTextTableAttributeName atIndex:0 longestEffectiveRange:&table
                               inRange:NSMakeRange(0, [storage length])]);
    [textView setSelectedRange:table];
    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard
                                                 types:[NSArray arrayWithObject:NSStringPboardType]]);
    NSString *copied = [pboard stringForType:NSStringPboardType];
    XCTAssertTrue([copied hasPrefix:[self tableMarkdown]], @"%@", copied);
    [pboard releaseGlobally];
}

- (void)testTableGridIsDrawnAlongItsColumnEdges
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self tableMarkdown]];
    NSLayoutManager *layoutManager = [textView layoutManager];
    OMTextTable *table = [[textView textStorage] attribute:OMTextTableAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertNotNil(table);
    XCTAssertEqual([[table columnEdges] count], (NSUInteger)3);
    NSRect used = [layoutManager usedRectForTextContainer:[textView textContainer]];
    NSSize size = NSMakeSize(ceil(NSMaxX(used)) + 20.0, ceil(NSMaxY(used)) + 4.0);
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    OMDrawTextTablesForGlyphRange(layoutManager, NSMakeRange(0, [layoutManager numberOfGlyphs]), NSZeroPoint);
    [image unlockFocus];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    NSInteger x = (NSInteger)[[[table columnEdges] objectAtIndex:1] doubleValue];
    NSInteger ruled = 0;
    NSInteger y = 0;
    for (; y < [bitmap pixelsHigh]; y++) {
        NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if ([color redComponent] < 0.9) {
            ruled += 1;
        }
    }
    XCTAssertTrue(ruled > 30, @"a rule runs down the column edge (%ld px)", (long)ruled);
}

@end

